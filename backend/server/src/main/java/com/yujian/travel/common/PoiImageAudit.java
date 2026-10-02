package com.yujian.travel.common;

import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * 景区配图的合规判定。
 *
 * 为什么需要它：内容库里"填了图片地址"不等于"这张图可以交付"。占位示例图、
 * 来源没登记的图，既不能拿去比赛，也不该让游客以为这是河南实拍。判定的规则
 * 集中在这一个类里，管理台列表、游客端接口和单元测试用的是同一份结论，
 * 不会出现"后台显示已登记、前台看着像实拍"这种两套口径。
 *
 * 四种状态：
 * <ul>
 *   <li>{@link #MISSING} —— 没有配图；</li>
 *   <li>{@link #PLACEHOLDER} —— 占位 / 示例素材，必须替换；</li>
 *   <li>{@link #UNLICENSED} —— 有图，但版权与来源都没登记，出处不明；</li>
 *   <li>{@link #REGISTERED} —— 有图且登记了版权 / 授权说明。</li>
 * </ul>
 *
 * gaps 只放**必须补**的项，不放"建议"。列表页把它当作待办清单直接展示。
 */
public final class PoiImageAudit {
    public static final String MISSING = "MISSING";
    public static final String PLACEHOLDER = "PLACEHOLDER";
    public static final String UNLICENSED = "UNLICENSED";
    public static final String REGISTERED = "REGISTERED";

    /**
     * 示例素材的域名。命中即视为占位图 —— 与图片来源说明写没写无关：
     * 一段写得很漂亮的授权说明，也改变不了这张图不是河南实景这个事实。
     */
    private static final List<String> PLACEHOLDER_HOSTS =
        List.of("unsplash.com", "pexels.com", "pixabay.com");

    /**
     * 图片来源说明里的措辞。
     *
     * 运营人员只要照实写（"占位""示例素材""待替换"），判定就会命中；
     * 这是给"图片来源说明"留的第二个入口，方便那些被搬去别处托管的占位图。
     */
    private static final List<String> PLACEHOLDER_WORDS =
        List.of("占位", "示例素材", "非河南实景", "待替换");

    private PoiImageAudit() {
    }

    /** 判定结果。label 给界面直接显示，gaps 是必须补齐的项（可为空）。 */
    public record Verdict(String status, String label, List<String> gaps) {
    }

    public static Verdict classify(String imageUrl, String imageCredit, String sourceUrl) {
        String url = normalize(imageUrl);
        String credit = normalize(imageCredit);
        String source = normalize(sourceUrl);

        if (url.isEmpty()) {
            return new Verdict(MISSING, "缺配图", List.of("上传有授权的河南实景图"));
        }
        if (isPlaceholder(url, credit)) {
            List<String> gaps = new ArrayList<>();
            gaps.add("替换为有授权的河南实景图");
            addIfBlank(gaps, credit, "登记图片版权 / 授权说明");
            addIfBlank(gaps, source, "登记资料来源链接");
            return new Verdict(PLACEHOLDER, "占位示例图", List.copyOf(gaps));
        }
        if (credit.isEmpty()) {
            List<String> gaps = new ArrayList<>();
            gaps.add("登记图片版权 / 授权说明");
            addIfBlank(gaps, source, "登记资料来源链接");
            return new Verdict(UNLICENSED, "来源未登记", List.copyOf(gaps));
        }
        // 有图 + 有版权说明即视为闭环。来源链接缺失只是"建议补"，
        // 不计入 gaps，避免待办清单里混进可以不做的事。
        return new Verdict(REGISTERED, "已登记", List.of());
    }

    /** 只有 REGISTERED 才算配图闭环完成；列表页用它算"还有几个待处理"。 */
    public static boolean needsWork(String status) {
        return !REGISTERED.equals(status);
    }

    /**
     * 占位图识别：先看图片地址的域名，再看来源说明里的措辞。两者都只看
     * 是否命中，不做模糊匹配 —— 宁可漏判成"来源未登记"让人再确认一次，
     * 也不要把一张真实的授权照片误判成占位图。
     */
    public static boolean isPlaceholder(String imageUrl, String imageCredit) {
        String url = normalize(imageUrl).toLowerCase(Locale.ROOT);
        for (String host : PLACEHOLDER_HOSTS) {
            if (url.contains(host)) {
                return true;
            }
        }
        String creditText = normalize(imageCredit);
        for (String word : PLACEHOLDER_WORDS) {
            if (creditText.contains(word)) {
                return true;
            }
        }
        return false;
    }

    private static void addIfBlank(List<String> gaps, String value, String item) {
        if (value.isEmpty()) {
            gaps.add(item);
        }
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim();
    }
}
