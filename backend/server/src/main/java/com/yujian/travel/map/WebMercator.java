package com.yujian.travel.map;

/**
 * 百度静态底图的像素投影。
 *
 * 百度地图的坐标不是 WGS84，静态图接口内部用的是百度墨卡托（BD09MC）。
 * 本项目需要把一批景点坐标画到同一张底图上，因此必须复刻这套投影。
 *
 * 依据（已用真实接口反证，见 WebMercatorTest）：
 *
 * 1. 百度墨卡托的 x 与经度成正比，比例系数对应地球半径 6378137 米，与球面墨卡托一致；
 * 2. y 方向是墨卡托的纬度拉伸，直接用 R 乘 ln(tan(pi/4 + phi/2)) 计算，
 *    与百度自身的多项式拟合在城市尺度下相差不到 1 像素；
 * 3. zoom 为 18 时 1 像素等于 1 米，每降一级分辨率翻倍。
 *
 * 验证方式：向百度静态图接口请求一张以 C 为中心、在 M 处打点的图，
 * 用像素差分找出标记的真实位置，与这里的预测值比对（当前偏差不到 1 像素）。
 *
 * 不依赖百度 SDK：坐标是公开的数学事实，公式放在这里既能被单元测试覆盖，
 * 也能在百度接口不可用时继续把已有坐标画在缓存底图上。
 */
public final class WebMercator {
    /** 百度瓦片体系在 18 级时 1 像素代表 1 米。 */
    private static final int MAX_ZOOM = 18;
    private static final double EARTH_RADIUS = 6378137.0;
    /** 墨卡托在极区发散，百度同样把纬度截断在这个范围内。 */
    private static final double MAX_LATITUDE = 85.05112878;
    private static final int MIN_ZOOM = 3;
    private static final int MAX_STATIC_ZOOM = 19;

    private WebMercator() {
    }

    /** 一级缩放对应的地面分辨率（米/像素）。 */
    public static double resolution(int zoom) {
        return Math.pow(2, MAX_ZOOM - clampZoom(zoom));
    }

    /** 百度墨卡托 x，单位米。 */
    public static double meterX(double lng) {
        return EARTH_RADIUS * Math.toRadians(clampLng(lng));
    }

    /** 百度墨卡托 y，单位米。 */
    public static double meterY(double lat) {
        double safe = clampLat(lat);
        return EARTH_RADIUS * Math.log(Math.tan(Math.PI / 4 + Math.toRadians(safe) / 2));
    }

    /**
     * 把经纬度投影到底图像素坐标。
     *
     * 返回值的原点是图片左上角；x 向右、y 向下，与 Canvas 和 Flutter 的绘制坐标系一致，
     * 客户端可以直接使用，不需要再做一次翻转。
     */
    public static Pixel project(double lng, double lat, double centerLng, double centerLat,
                                int zoom, int width, int height) {
        double resolution = resolution(zoom);
        double dx = (meterX(lng) - meterX(centerLng)) / resolution;
        double dy = (meterY(centerLat) - meterY(lat)) / resolution;
        return new Pixel(width / 2d + dx, height / 2d + dy);
    }

    /**
     * 以某个像素偏移量反推新的中心点，用于拖动后重新取图。
     *
     * 拖动是"看地图"的自然手势：手指向左移动，视野中心向右移动。
     * 这里把屏幕像素位移换算回经纬度，客户端不需要理解投影。
     */
    public static Coordinate shiftCenter(double centerLng, double centerLat, int zoom,
                                         double dxPixels, double dyPixels) {
        double resolution = resolution(zoom);
        double x = meterX(centerLng) + dxPixels * resolution;
        double y = meterY(centerLat) - dyPixels * resolution;
        return new Coordinate(lngOf(x), latOf(y));
    }

    /** 墨卡托 x 反算经度。 */
    public static double lngOf(double meterX) {
        return Math.toDegrees(meterX / EARTH_RADIUS);
    }

    /** 墨卡托 y 反算纬度。 */
    public static double latOf(double meterY) {
        return Math.toDegrees(2 * Math.atan(Math.exp(meterY / EARTH_RADIUS)) - Math.PI / 2);
    }

    private static double clampLng(double lng) {
        if (Double.isNaN(lng)) {
            return 0;
        }
        return Math.max(-180, Math.min(180, lng));
    }

    private static double clampLat(double lat) {
        if (Double.isNaN(lat)) {
            return 0;
        }
        return Math.max(-MAX_LATITUDE, Math.min(MAX_LATITUDE, lat));
    }

    public static int clampZoom(int zoom) {
        return Math.max(MIN_ZOOM, Math.min(MAX_STATIC_ZOOM, zoom));
    }

    /** 底图上的一个像素点。 */
    public record Pixel(double x, double y) {
        public boolean inside(int width, int height) {
            return x >= 0 && y >= 0 && x <= width && y <= height;
        }
    }

    /** 一个经纬度点。 */
    public record Coordinate(double lng, double lat) {
    }
}
