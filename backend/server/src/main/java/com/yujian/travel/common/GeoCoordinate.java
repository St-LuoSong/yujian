package com.yujian.travel.common;

/**
 * 坐标系换算与直线距离计算。
 *
 * <p>为什么需要它：设备 GNSS（GPS / 北斗）给出的是 <b>WGS-84</b>，而运营台维护的景点坐标是
 * <b>百度坐标系 BD-09</b>（见 {@link com.yujian.travel.domain.PoiEntity} 的 lng / lat 字段）。
 * 两者在河南境内相差 500 米上下。直接相减，"附近景点"会把 800 米外的景点说成 300 米，
 * 把 1.2 公里的说成 700 米 —— 这不是精度问题，是错误。
 *
 * <p>所以换算只在这一处实现：服务端先把设备坐标换算成 BD-09，再和内容库比距离。
 * 客户端拿到的始终是"在同一套坐标系里算出来的直线距离"。
 *
 * <p>算法是公开的 GCJ-02 偏移 + GCJ-02→BD-09 二次变换，与主流地图 SDK 一致。
 * 两步的适用范围**不一样**，别把它们混成一句：GCJ-02 的偏移只在中国大陆生效
 * （境外点原样通过），而 GCJ-02→BD-09 是恒定的小量平移，对任何点都会加上去 ——
 * 这正是百度坐标系在全世界的定义方式。
 */
public final class GeoCoordinate {
    /** 克拉索夫斯基椭球长半轴。 */
    private static final double AXIS = 6378245.0;
    private static final double EE = 0.00669342162296594323;
    private static final double X_PI = Math.PI * 3000.0 / 180.0;
    /** IUGG 平均地球半径，用于大圆距离。 */
    private static final double EARTH_RADIUS_METERS = 6371008.8;

    private GeoCoordinate() {
    }

    /** WGS-84 → BD-09。返回 {lng, lat}。 */
    public static double[] wgs84ToBd09(double lng, double lat) {
        double[] gcj = wgs84ToGcj02(lng, lat);
        return gcj02ToBd09(gcj[0], gcj[1]);
    }

    public static double[] wgs84ToGcj02(double lng, double lat) {
        if (outsideChina(lng, lat)) {
            return new double[] {lng, lat};
        }
        double dLat = transformLat(lng - 105.0, lat - 35.0);
        double dLng = transformLng(lng - 105.0, lat - 35.0);
        double radLat = lat / 180.0 * Math.PI;
        double magic = Math.sin(radLat);
        magic = 1 - EE * magic * magic;
        double sqrtMagic = Math.sqrt(magic);
        dLat = (dLat * 180.0) / ((AXIS * (1 - EE)) / (magic * sqrtMagic) * Math.PI);
        dLng = (dLng * 180.0) / (AXIS / sqrtMagic * Math.cos(radLat) * Math.PI);
        return new double[] {lng + dLng, lat + dLat};
    }

    public static double[] gcj02ToBd09(double lng, double lat) {
        double z = Math.sqrt(lng * lng + lat * lat) + 0.00002 * Math.sin(lat * X_PI);
        double theta = Math.atan2(lat, lng) + 0.000003 * Math.cos(lng * X_PI);
        return new double[] {z * Math.cos(theta) + 0.0065, z * Math.sin(theta) + 0.006};
    }

    /**
     * 球面直线距离，单位米。
     *
     * <p>它是**直线距离**，不是步行或驾车里程。没有路网数据时不拿它除以步速去编一个
     * "步行 5 分钟"出来。
     */
    public static double haversineMeters(double lng1, double lat1, double lng2, double lat2) {
        double dLat = Math.toRadians(lat2 - lat1);
        double dLng = Math.toRadians(lng2 - lng1);
        double a = Math.sin(dLat / 2) * Math.sin(dLat / 2)
            + Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2))
            * Math.sin(dLng / 2) * Math.sin(dLng / 2);
        return 2 * EARTH_RADIUS_METERS * Math.asin(Math.min(1.0, Math.sqrt(a)));
    }

    private static boolean outsideChina(double lng, double lat) {
        return !(lng > 73.66 && lng < 135.05 && lat > 3.86 && lat < 53.55);
    }

    private static double transformLat(double x, double y) {
        double ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y
            + 0.2 * Math.sqrt(Math.abs(x));
        ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
        ret += (20.0 * Math.sin(y * Math.PI) + 40.0 * Math.sin(y / 3.0 * Math.PI)) * 2.0 / 3.0;
        ret += (160.0 * Math.sin(y / 12.0 * Math.PI) + 320 * Math.sin(y * Math.PI / 30.0)) * 2.0 / 3.0;
        return ret;
    }

    private static double transformLng(double x, double y) {
        double ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y
            + 0.1 * Math.sqrt(Math.abs(x));
        ret += (20.0 * Math.sin(6.0 * x * Math.PI) + 20.0 * Math.sin(2.0 * x * Math.PI)) * 2.0 / 3.0;
        ret += (20.0 * Math.sin(x * Math.PI) + 40.0 * Math.sin(x / 3.0 * Math.PI)) * 2.0 / 3.0;
        ret += (150.0 * Math.sin(x / 12.0 * Math.PI) + 300.0 * Math.sin(x / 30.0 * Math.PI)) * 2.0 / 3.0;
        return ret;
    }
}
