package com.yujian.travel.service;

import com.yujian.travel.api.TripPlanModels;
import com.yujian.travel.domain.TripDayEntity;
import com.yujian.travel.domain.TripItemEntity;
import com.yujian.travel.domain.TripPlanEntity;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * "你的足迹"的口径。
 *
 * 这一块最容易变成"看起来很漂亮但数字是编的"：城市数、里程、天数三项里，
 * 里程尤其危险 —— 路线工具没返回距离时行程项的 distanceMeters 是 null，
 * 如果按天或者按景点数估算一个公里数，界面上就会出现一个没人走过的数字。
 * 这里的用例把这个口径钉死：只累计真实落库的值，缺失就是缺失。
 */
class TripFootprintTest {

    @Test
    void countsCitiesDaysAndRecordedMeters() {
        TripPlanEntity zhengzhouToLuoyang = plan("郑州", "洛阳", 2,
            Instant.parse("2026-09-28T02:00:00Z"), Instant.parse("2026-10-01T02:00:00Z"),
            42_000, 8_000);
        TripPlanEntity luoyangToKaifeng = plan("洛阳", "开封", 3,
            Instant.parse("2026-10-02T02:00:00Z"), Instant.parse("2026-10-02T06:00:00Z"),
            1_200, null);

        TripPlanModels.Footprint footprint =
            TripPlanService.footprintOf(List.of(zhengzhouToLuoyang, luoyangToKaifeng));

        assertThat(footprint.tripCount()).isEqualTo(2);
        assertThat(footprint.totalDays()).isEqualTo(5);
        // 42_000 + 8_000 + 1_200，null 的那一项不参与累计。
        assertThat(footprint.totalMeters()).isEqualTo(51_200L);
        // 最近到访的排前面；同一时间到访的按次数排，洛阳去过两次所以在开封之前。
        assertThat(footprint.cities()).extracting(TripPlanModels.CityVisit::name)
            .containsExactly("洛阳", "开封", "郑州");
        assertThat(footprint.cities()).extracting(TripPlanModels.CityVisit::tripCount)
            .containsExactly(2, 1, 1);
    }

    @Test
    void skipsBlankCitiesAndCountsACityOncePerPlan() {
        TripPlanEntity sameCity = plan("郑州", "郑州", 1,
            Instant.parse("2026-10-01T02:00:00Z"), Instant.parse("2026-10-01T02:00:00Z"),
            null, null);
        TripPlanEntity blank = plan("  ", null, 1, null, null, null, null);

        TripPlanModels.Footprint footprint =
            TripPlanService.footprintOf(List.of(sameCity, blank));

        assertThat(footprint.cities()).hasSize(1);
        assertThat(footprint.cities().get(0).name()).isEqualTo("郑州");
        assertThat(footprint.cities().get(0).tripCount()).isEqualTo(1);
        assertThat(footprint.totalMeters()).isZero();
        // 一份没写城市的行程仍然算一次旅行，不能因为城市缺失就把天数吞掉。
        assertThat(footprint.totalDays()).isEqualTo(2);
        assertThat(footprint.tripCount()).isEqualTo(2);
    }

    @Test
    void newerVisitComesFirstAndEmptyInputIsAnEmptyFootprint() {
        TripPlanEntity old = plan("安阳", "焦作", 1,
            Instant.parse("2026-08-01T02:00:00Z"), Instant.parse("2026-08-01T02:00:00Z"), null, null);
        TripPlanEntity recent = plan("南阳", "信阳", 1,
            Instant.parse("2026-09-30T02:00:00Z"), Instant.parse("2026-09-30T02:00:00Z"), null, null);

        TripPlanModels.Footprint footprint =
            TripPlanService.footprintOf(List.of(old, recent));

        // 同一天到访的两个城市按名称兜底排序，保证同一份数据每次都给出同样顺序。
        assertThat(footprint.cities()).extracting(TripPlanModels.CityVisit::name)
            .containsExactly("信阳", "南阳", "安阳", "焦作");

        TripPlanModels.Footprint empty = TripPlanService.footprintOf(List.of());
        assertThat(empty.cities()).isEmpty();
        assertThat(empty.totalMeters()).isZero();
        assertThat(empty.totalDays()).isZero();
        assertThat(empty.tripCount()).isZero();
    }

    private static TripPlanEntity plan(String origin, String destination, int daysCount,
                                       Instant createdAt, Instant updatedAt,
                                       Integer firstItemMeters, Integer secondItemMeters) {
        TripPlanEntity plan = new TripPlanEntity();
        plan.setOrigin(origin);
        plan.setDestination(destination);
        plan.setDaysCount(daysCount);
        plan.setCreatedAt(createdAt);
        plan.setUpdatedAt(updatedAt);
        TripDayEntity day = new TripDayEntity();
        day.addItem(item(firstItemMeters));
        day.addItem(item(secondItemMeters));
        plan.addDay(day);
        return plan;
    }

    private static TripItemEntity item(Integer meters) {
        TripItemEntity item = new TripItemEntity();
        item.setDistanceMeters(meters);
        return item;
    }
}
