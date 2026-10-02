package com.yujian.travel.common;

import org.junit.jupiter.api.Test;

import java.util.Arrays;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 「附近景点」的筛选与排序。
 *
 * 这里不碰数据库也不碰 Spring：输入是已经同坐标系的点，
 * 所以能直接把"半径、排序、截断、并列顺序"这几条规则钉住。
 */
class NearbySearchTest {
    private static final double CENTER_LNG = 113.6254;
    private static final double CENTER_LAT = 34.7466;

    @Test
    void sortsByStraightLineDistance() {
        List<NearbySearch.Point> points = List.of(
            new NearbySearch.Point("far", 113.7000, CENTER_LAT),
            new NearbySearch.Point("near", 113.6300, CENTER_LAT),
            new NearbySearch.Point("middle", 113.6600, CENTER_LAT));

        List<NearbySearch.Hit> hits = NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 20_000, 10);

        assertThat(hits).extracting(NearbySearch.Hit::id).containsExactly("near", "middle", "far");
        assertThat(hits.get(0).distanceMeters()).isLessThan(hits.get(1).distanceMeters());
        assertThat(hits.get(1).distanceMeters()).isLessThan(hits.get(2).distanceMeters());
    }

    @Test
    void dropsPointsOutsideTheRadius() {
        List<NearbySearch.Point> points = List.of(
            new NearbySearch.Point("in", 113.6300, CENTER_LAT),
            new NearbySearch.Point("out", 113.9000, CENTER_LAT));

        List<NearbySearch.Hit> hits = NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 1_000, 10);

        assertThat(hits).extracting(NearbySearch.Hit::id).containsExactly("in");
    }

    @Test
    void truncatesToTheLimitAfterSorting() {
        // 先排序再截断，否则 limit=1 拿到的可能是最远的那个。
        List<NearbySearch.Point> points = List.of(
            new NearbySearch.Point("far", 113.7000, CENTER_LAT),
            new NearbySearch.Point("near", 113.6300, CENTER_LAT),
            new NearbySearch.Point("middle", 113.6600, CENTER_LAT));

        List<NearbySearch.Hit> hits = NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 20_000, 2);

        assertThat(hits).extracting(NearbySearch.Hit::id).containsExactly("near", "middle");
    }

    @Test
    void breaksTiesByIdSoRepeatedCallsKeepTheSameOrder() {
        // 同名距离的并列项如果顺序随机，分页与缓存都会变成玄学。
        List<NearbySearch.Point> points = List.of(
            new NearbySearch.Point("b", 113.6300, CENTER_LAT),
            new NearbySearch.Point("a", 113.6300, CENTER_LAT));

        List<NearbySearch.Hit> hits = NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 5_000, 10);

        assertThat(hits).extracting(NearbySearch.Hit::id).containsExactly("a", "b");
    }

    @Test
    void returnsEmptyForEmptyOrUnusableInput() {
        assertThat(NearbySearch.rank(List.of(), CENTER_LNG, CENTER_LAT, 1_000, 10)).isEmpty();
        assertThat(NearbySearch.rank(null, CENTER_LNG, CENTER_LAT, 1_000, 10)).isEmpty();
        assertThat(NearbySearch.rank(List.of(new NearbySearch.Point("x", CENTER_LNG, CENTER_LAT)),
            CENTER_LNG, CENTER_LAT, 1_000, 0)).isEmpty();
    }

    @Test
    void ignoresNullEntriesInsteadOfFailingTheWholeRequest() {
        // 一个坏点位不应该让整次"附近"查询失败。
        List<NearbySearch.Point> points = Arrays.asList(null,
            new NearbySearch.Point("x", CENTER_LNG, CENTER_LAT), null);

        List<NearbySearch.Hit> hits = NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 1_000, 10);

        assertThat(hits).extracting(NearbySearch.Hit::id).containsExactly("x");
        assertThat(hits.get(0).distanceMeters()).isZero();
    }

    @Test
    void keepsPointsExactlyOnTheRadius() {
        // 边界含在内：地图上"刚好 3 公里"的景点不该因为浮点比较被剔掉。
        List<NearbySearch.Point> points = List.of(new NearbySearch.Point("edge", CENTER_LNG, CENTER_LAT));

        assertThat(NearbySearch.rank(points, CENTER_LNG, CENTER_LAT, 0, 10))
            .extracting(NearbySearch.Hit::id).containsExactly("edge");
    }
}
