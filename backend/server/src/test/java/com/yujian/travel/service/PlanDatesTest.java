package com.yujian.travel.service;

import com.yujian.travel.api.TravelModels;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 出发日期口径的回归用例。
 *
 * 真实故障：用户在客户端选了 10-02，请求体里却没有这个字段，
 * 服务端按"周末"口径取天气，模型又自己猜了日期，
 * 结果方案标题写 10-02、风险提示引用 10-01——用户说的"时间戳对不上"。
 */
class PlanDatesTest {

    @Test
    void keepsADateTheTravellerChose() {
        LocalDate future = PlanDates.today().plusDays(30);
        assertThat(PlanDates.resolveStartDate(future.toString())).isEqualTo(future);
    }

    @Test
    void neverStartsInThePast() {
        assertThat(PlanDates.resolveStartDate("2020-01-01")).isEqualTo(PlanDates.today());
    }

    @Test
    void fallsBackToTomorrowWhenMissingOrUnreadable() {
        LocalDate tomorrow = PlanDates.today().plusDays(1);
        assertThat(PlanDates.resolveStartDate(null)).isEqualTo(tomorrow);
        assertThat(PlanDates.resolveStartDate("  ")).isEqualTo(tomorrow);
        assertThat(PlanDates.resolveStartDate("周末")).isEqualTo(tomorrow);
    }

    @Test
    void resolveDaysClampsToTheSupportedRange() {
        assertThat(PlanDates.resolveDays(null)).isEqualTo(2);
        assertThat(PlanDates.resolveDays(0)).isEqualTo(2);
        assertThat(PlanDates.resolveDays(3)).isEqualTo(3);
        assertThat(PlanDates.resolveDays(99)).isEqualTo(7);
    }

    @Test
    void describeBuildsTheRangeShownInThePrompt() {
        LocalDate start = LocalDate.of(2026, 10, 2);
        assertThat(PlanDates.describe(start, 1)).isEqualTo("2026-10-02");
        assertThat(PlanDates.describe(start, 2)).isEqualTo("2026-10-02 至 2026-10-03");
    }

    @Test
    void applyDatesRewritesEveryDayAndKeepsTheThemeLabel() {
        LocalDate start = PlanDates.today().plusDays(3);
        TravelModels.TripDay first = new TravelModels.TripDay("DAY 01", "古都与石窟", List.of());
        TravelModels.TripDay second = new TravelModels.TripDay("DAY 02", "10-03", List.of());
        TravelModels.TripPlan plan = new TravelModels.TripPlan("id", "标题", "摘要", "郑州—洛阳",
            "适中", 0, 0, List.of(first, second), List.of(), "演示数据");

        TravelModels.TripPlan dated = PlanDates.applyDates(plan, start);

        assertThat(dated.days()).hasSize(2);
        assertThat(dated.days().get(0).label()).isEqualTo("DAY 01");
        assertThat(dated.days().get(0).date()).isEqualTo(start.toString());
        assertThat(dated.days().get(1).label()).isEqualTo("DAY 02");
        assertThat(dated.days().get(1).date()).isEqualTo(start.plusDays(1).toString());
    }

    @Test
    void applyDatesToleratesAnEmptyPlan() {
        TravelModels.TripPlan empty = new TravelModels.TripPlan("id", "标题", "摘要", "河南",
            "适中", 0, 0, List.of(), List.of(), "演示数据");
        assertThat(PlanDates.applyDates(empty, PlanDates.today())).isSameAs(empty);
        assertThat(PlanDates.applyDates(null, PlanDates.today())).isNull();
    }
}
