package com.yujian.travel.common;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * 「附近景点」的筛选与排序。
 *
 * <p>抽成纯函数是为了能不被 Spring 拖进测试：输入是**已经换算到同一坐标系**的点，
 * 输出是半径内、按距离升序、截断到 limit 的结果。
 *
 * <p>只做直线距离，不做路径规划 —— 说"步行 5 分钟"需要路网，
 * 没有路网就得闭嘴，不能拿直线距离除以步速编一个数出来。
 */
public final class NearbySearch {
    private NearbySearch() {
    }

    /** 内容库里的一个点，坐标必须已经与中心点同属一个坐标系。 */
    public record Point(String id, double lng, double lat) {
    }

    public record Hit(String id, int distanceMeters) {
    }

    /**
     * @param radiusMeters 半径，单位米（含边界）
     * @param limit        最多返回几条
     */
    public static List<Hit> rank(List<Point> points, double centerLng, double centerLat,
                                 int radiusMeters, int limit) {
        if (points == null || points.isEmpty() || limit <= 0) {
            return List.of();
        }
        List<Hit> hits = new ArrayList<>();
        for (Point point : points) {
            if (point == null) {
                continue;
            }
            double meters = GeoCoordinate.haversineMeters(centerLng, centerLat, point.lng(), point.lat());
            if (meters > radiusMeters) {
                continue;
            }
            hits.add(new Hit(point.id(), (int) Math.round(meters)));
        }
        // 距离相同时按 id 排：否则同一份请求两次可能给出不同顺序，
        // 分页、缓存和"为什么这次少了那个景点"都会变成玄学。
        hits.sort(Comparator.comparingInt(Hit::distanceMeters).thenComparing(Hit::id));
        return hits.size() <= limit ? List.copyOf(hits) : List.copyOf(hits.subList(0, limit));
    }
}
