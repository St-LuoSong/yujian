package com.yujian.travel.service;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * 时长文本的解析与格式化。
 *
 * 真实故障（装到模拟器上才看见的）：内容库里“建议游玩时长”写作 “3—4小时”，
 * 旧实现把非数字字符全部删掉，于是 “3—4” 变成 34 小时；龙门石窟因此显示
 * “约34小时”，一天的体力风险被算成 59.1 小时。同一处的格式化又把 125 分钟
 * 拼成 “约2.0833333333333335小时”——双精度直接进了界面。
 *
 * 这类错误会顺着“节点时长 → 行程强度 → 体力风险 → 预算依据”一路放大，
 * 所以解析与格式化收敛到这一个类里，并用单元测试锁住。
 */
public final class DurationText {
    /** 取不到时长时的保底值：一个景点按两小时估算。 */
    private static final int DEFAULT_MINUTES = 120;
    /** 单个节点不可能短于 5 分钟、长于一整天（12 小时），越界一律收敛。 */
    private static final int MIN_MINUTES = 5;
    private static final int MAX_MINUTES = 12 * 60;
    /** 一天的游玩时长按 8 小时折算，“两天”这类写法用它换算。 */
    private static final int HOURS_PER_DAY = 8;

    private static final Pattern NUMBER = Pattern.compile("\\d+(?:\\.\\d+)?");
    /**
     * 修饰词表。
     *
     * 长词必须排在短词前面："约"排在"大约"之前时，"大约2小时"会先被削成"大2小时"，
     * 剩下的"大约"再也匹配不上。同样的顺序问题也让中文数字的"两"被当成 3。
     */
    private static final List<String> NOISE = List.of(
        "大约", "大概", "约", "左右", "前后", "建议", "游览", "游玩", "参观", "使用",
        "时长", "全程", "共", "需", "小时制");
    /** 中文数字。用两个平行的列表而不是 Map，保证"两"稳定映射到 2。 */
    private static final List<String> CHINESE_DIGITS = List.of(
        "一", "二", "两", "三", "四", "五", "六", "七", "八", "九", "十");
    private static final List<Integer> CHINESE_VALUES = List.of(
        1, 2, 2, 3, 4, 5, 6, 7, 8, 9, 10);

    private DurationText() {
    }

    /**
     * 把“3—4小时”“2小时30分钟”“45分钟”“半天”这类写法解析成分钟。
     *
     * 区间取**上界**：行程规划宁可留出余量，也不要因为取下界而把一天排得过满。
     */
    public static int parseMinutes(String raw) {
        if (raw == null || raw.isBlank()) {
            return DEFAULT_MINUTES;
        }
        String text = clean(raw);
        if (text.isEmpty()) {
            return DEFAULT_MINUTES;
        }
        if (text.contains("半天")) {
            return clamp(HOURS_PER_DAY * 60 / 2);
        }
        if (text.contains("全天") || text.contains("一整天")) {
            return clamp(HOURS_PER_DAY * 60);
        }
        if (text.contains("天")) {
            double days = upperNumber(text);
            return clamp((int) Math.round((days > 0 ? days : 1) * HOURS_PER_DAY * 60));
        }

        boolean hasHour = containsAny(text, "小时", "时", "h", "H");
        boolean hasMinute = containsAny(text, "分钟", "分", "m", "min");
        if (hasHour && hasMinute) {
            // “2小时30分钟”：两段各取自己的数字，不能把 2 和 30 拼成 230。
            double hours = numberBefore(text, "小时", "时", "h", "H");
            double minutes = numberBefore(text, "分钟", "分", "m", "min");
            if (hours <= 0 && minutes <= 0) {
                return DEFAULT_MINUTES;
            }
            return clamp((int) Math.round(hours * 60 + minutes));
        }
        if (hasHour) {
            double hours = upperNumber(text);
            return hours <= 0 ? DEFAULT_MINUTES : clamp((int) Math.round(hours * 60));
        }
        if (hasMinute) {
            double minutes = upperNumber(text);
            return minutes <= 0 ? DEFAULT_MINUTES : clamp((int) Math.round(minutes));
        }
        // 只有数字没有单位时按小时理解：内容库里 “3” 指的是 3 小时。
        double bare = upperNumber(text);
        return bare <= 0 ? DEFAULT_MINUTES : clamp((int) Math.round(bare * 60));
    }

    /**
     * 把分钟数写成一句人话。
     *
     * 刻意不输出小数：界面上的 “约2.0833333333333335小时” 就是这么来的。
     */
    public static String format(int minutes) {
        int safe = clamp(minutes);
        if (safe < 60) {
            return "约" + safe + "分钟";
        }
        int hours = safe / 60;
        int rest = safe % 60;
        if (rest == 0) {
            return "约" + hours + "小时";
        }
        return "约" + hours + "小时" + rest + "分钟";
    }

    /** 去掉“约/建议/游览”这类修饰词与空白，只留数字和单位。 */
    private static String clean(String raw) {
        String text = raw.trim();
        for (String noise : NOISE) {
            text = text.replace(noise, "");
        }
        return text.replaceAll("[\\s　:：()（）\u2014\u2013~～\u3001,，、]", " ").trim();
    }

    private static boolean containsAny(String text, String... units) {
        for (String unit : units) {
            if (text.contains(unit)) {
                return true;
            }
        }
        return false;
    }

    /** 单位之前那段文本里的上界数字；“1小时30分钟”取到 30。 */
    private static double numberBefore(String text, String... units) {
        int cut = -1;
        for (String unit : units) {
            int index = text.indexOf(unit);
            if (index >= 0 && (cut < 0 || index < cut)) {
                cut = index;
            }
        }
        if (cut <= 0) {
            return 0;
        }
        return upperNumber(text.substring(0, cut));
    }

    /** 文本里出现的最大数字：区间 “3—4” 取 4。 */
    private static double upperNumber(String text) {
        Matcher matcher = NUMBER.matcher(text);
        List<Double> found = new ArrayList<>();
        while (matcher.find()) {
            try {
                found.add(Double.parseDouble(matcher.group()));
            } catch (NumberFormatException ignored) {
                // 正则已经保证是可解析的数字，这里只是不让意外中断整段解析。
            }
        }
        if (found.isEmpty()) {
            return chineseNumber(text);
        }
        double max = 0;
        for (double value : found) {
            max = Math.max(max, value);
        }
        return max;
    }

    /** “两小时”“三个小时”这类中文数字的兜底，认不出就返回 0。 */
    private static double chineseNumber(String text) {
        if (text.contains("半")) {
            return 0.5;
        }
        for (int index = 0; index < CHINESE_DIGITS.size(); index++) {
            if (text.contains(CHINESE_DIGITS.get(index))) {
                return CHINESE_VALUES.get(index);
            }
        }
        return 0;
    }

    private static int clamp(int minutes) {
        return Math.max(MIN_MINUTES, Math.min(MAX_MINUTES, minutes));
    }
}
