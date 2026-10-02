package com.yujian.travel.service;

import com.yujian.travel.api.TravelModels;

import java.time.DateTimeException;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;

/**
 * 行程日期口径。
 *
 * 真实故障：客户端表单里明明选了出发日期，但请求体里没有这个字段，
 * 于是模型自己“猜”日期——方案标题写着 2 日游、日期是 10-02 至 10-03，
 * 风险提示里却引用 10-01 的天气。用户看到的就是“时间戳对不上”。
 *
 * 修法是把日期变成一等输入：客户端选好的日期随请求上来，
 * 服务端用它去查天气与车次、写进提示词，并在方案生成后强制覆盖
 * 每一天的日期字段——日期不再由模型决定。
 */
public final class PlanDates {
    /** 全项目统一按北京时间判断“今天”。 */
    public static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    /** 全项目统一的日期文本格式：yyyy-MM-dd。 */
    public static final DateTimeFormatter ISO = DateTimeFormatter.ISO_LOCAL_DATE;

    /** 计划天数上限。首版是 1—3 天短途，多留几天的余量给“周”级行程。 */
    private static final int MAX_DAYS = 7;
    /** 缺省天数：一句话入口没有说天数时，按两日游处理。 */
    private static final int DEFAULT_DAYS = 2;

    private PlanDates() {
    }

    public static LocalDate today() {
        return LocalDate.now(ZONE);
    }

    /**
     * 把请求里的出发日期落地。
     *
     * 缺失或早于今天时退回“明天”：与其让行程从一个已经过去的日期开始，
     * 不如按最近的可出行日期规划，并在界面上如实显示。
     */
    public static LocalDate resolveStartDate(String raw) {
        if (raw != null && !raw.isBlank()) {
            try {
                LocalDate parsed = LocalDate.parse(raw.trim());
                return parsed.isBefore(today()) ? today() : parsed;
            } catch (DateTimeException ignored) {
                // 客户端传了无法识别的写法时按缺省处理，不因此让整次规划失败。
            }
        }
        return today().plusDays(1);
    }

    /**
     * 把请求里的天数收敛到可规划范围。
     *
     * 天气、车次与提示词都按这个值取，必须只有一个来源，
     * 否则会出现“提示词说 2 天、工具查了 3 天天气”这种口径分叉。
     */
    public static int resolveDays(Integer days) {
        if (days == null || days < 1) {
            return DEFAULT_DAYS;
        }
        return Math.min(MAX_DAYS, days);
    }

    /** 给提示词与工具用的一句话日期范围，例如 “2026-10-02 至 2026-10-03”。 */
    public static String describe(LocalDate start, int days) {
        if (days <= 1) {
            return start.format(ISO);
        }
        return start.format(ISO) + " 至 " + start.plusDays(days - 1).format(ISO);
    }

    /**
     * 强制把每一天的日期改成“出发日 + 第 N 天”。
     *
     * 只改日期字段，不动模型给出的主题名（label）与安排内容：
     * 模型可以决定“怎么玩”，但“哪天玩”必须由用户选的日期说了算。
     */
    public static TravelModels.TripPlan applyDates(TravelModels.TripPlan plan, LocalDate start) {
        if (plan == null || plan.days() == null || plan.days().isEmpty()) {
            return plan;
        }
        List<TravelModels.TripDay> days = new ArrayList<>();
        for (int index = 0; index < plan.days().size(); index++) {
            TravelModels.TripDay day = plan.days().get(index);
            days.add(new TravelModels.TripDay(
                day.label(),
                start.plusDays(index).format(ISO),
                day.items()));
        }
        return new TravelModels.TripPlan(plan.id(), plan.title(), plan.summary(), plan.corridor(),
            plan.intensity(), plan.totalCost(), plan.perPersonCost(), List.copyOf(days),
            plan.warnings(), plan.dataStatus());
    }
}
