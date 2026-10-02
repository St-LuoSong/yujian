package com.yujian.travel.api;

import java.time.Instant;
import java.util.List;

/**
 * 行程地图的接口契约。
 *
 * 服务端一次性给出"底图地址 + 已经算好像素位置的标记与折线"，客户端只负责绘制。
 * 这样投影公式只有一份实现（Java 侧，可单元测试），
 * 也避免把百度坐标系的换算知识散落到 APK 里。
 */
public final class MapModels {
    private MapModels() {
    }

    /** 底图窗口：中心点、缩放级别与像素尺寸。 */
    public record Viewport(double centerLng, double centerLat, int zoom, int width, int height, boolean fitted) {
    }

    /**
     * 一个已经落到像素坐标上的站点。
     *
     * x / y 的原点是底图左上角，单位是底图像素；客户端按显示宽度等比换算即可。
     * inside 为 false 表示这个点在当前窗口外（用户拖动或放大之后很常见），
     * 客户端不应把它画在边缘，而是提示"还有几个站点在画面外"。
     */
    public record Marker(int index, String title, String itemType, String time,
                         double lng, double lat, double x, double y, boolean inside,
                         String coordinateSource, int confidence) {
    }

    /** 没能可信定位的站点：明确列出来，而不是悄悄丢掉。 */
    public record Unplaced(String title, String reason) {
    }

    public record RouteMap(String tripId,
                           int dayIndex,
                           String dayLabel,
                           String dayDate,
                           Viewport viewport,
                           String imageUrl,
                           int imageLifetimeSeconds,
                           List<Marker> markers,
                           List<List<Double>> polyline,
                           List<Unplaced> unplaced,
                           List<String> attribution,
                           String dataStatus,
                           String source,
                           Instant queriedAt,
                           Instant expiresAt,
                           boolean fallback,
                           String message) {
    }
}
