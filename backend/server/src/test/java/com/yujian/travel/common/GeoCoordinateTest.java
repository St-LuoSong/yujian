package com.yujian.travel.common;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 坐标系换算与距离。
 *
 * 这些用例守着一件事：**"附近景点"的距离必须是真的**。
 * 设备给 WGS-84、内容库存 BD-09，不换算就差几百米 —— 界面上看起来只是"有点不准"，
 * 实际是把 800 米的距离说成了 300 米。
 */
class GeoCoordinateTest {
    /** 郑州二七广场附近。 */
    private static final double ZHENGZHOU_LNG = 113.6254;
    private static final double ZHENGZHOU_LAT = 34.7466;

    @Test
    void shiftsDomesticCoordinatesOntoTheMapCoordinateSystem() {
        double[] bd = GeoCoordinate.wgs84ToBd09(ZHENGZHOU_LNG, ZHENGZHOU_LAT);
        double shift = GeoCoordinate.haversineMeters(ZHENGZHOU_LNG, ZHENGZHOU_LAT, bd[0], bd[1]);

        assertThat(bd[0]).isNotEqualTo(ZHENGZHOU_LNG);
        assertThat(bd[1]).isNotEqualTo(ZHENGZHOU_LAT);
        // 河南境内 WGS-84 → BD-09 的总偏移约 1.2 公里（GCJ-02 偏移数百米 + BD-09 恒定平移约 890 米）。
        // 若这里变成 0，说明换算整段失效；若变成几十公里，说明某一步的系数写错了。
        assertThat(shift).isBetween(300.0, 2500.0);
    }

    @Test
    void doesNotApplyTheObfuscationOffsetOutsideChina() {
        // GCJ-02 的偏移只在中国大陆生效 —— 这是两个变换里唯一"看地方"的那一步。
        double[] gcj = GeoCoordinate.wgs84ToGcj02(139.6917, 35.6895);

        assertThat(gcj[0]).isEqualTo(139.6917);
        assertThat(gcj[1]).isEqualTo(35.6895);
    }

    @Test
    void stillAppliesTheConstantBd09ShiftOutsideChina() {
        // 但 GCJ-02 → BD-09 是恒定平移，对任何点都加，境外的百度坐标也是这么定义的。
        // 把这条钉住，免得以后有人"顺手"给境外点加一个提前返回，让两套坐标悄悄错开。
        double[] bd = GeoCoordinate.wgs84ToBd09(139.6917, 35.6895);

        assertThat(bd[0]).isNotEqualTo(139.6917);
        assertThat(bd[1]).isNotEqualTo(35.6895);
        assertThat(GeoCoordinate.haversineMeters(139.6917, 35.6895, bd[0], bd[1]))
            .isBetween(700.0, 1000.0);
    }

    @Test
    void isDeterministic() {
        // 同一份输入必须给同一份输出：否则同一份请求两次会得到不同的"附近"。
        assertThat(GeoCoordinate.wgs84ToBd09(ZHENGZHOU_LNG, ZHENGZHOU_LAT))
            .containsExactly(GeoCoordinate.wgs84ToBd09(ZHENGZHOU_LNG, ZHENGZHOU_LAT));
    }

    @Test
    void measuresZeroForTheSamePoint() {
        assertThat(GeoCoordinate.haversineMeters(ZHENGZHOU_LNG, ZHENGZHOU_LAT, ZHENGZHOU_LNG, ZHENGZHOU_LAT))
            .isZero();
    }

    @Test
    void measuresDistanceInMetersNotKilometers() {
        // 纬度增加 1° 约 111.2 公里 —— 用来钉住半径的单位是米。
        double meters = GeoCoordinate.haversineMeters(113.6, 34.0, 113.6, 35.0);

        assertThat(meters).isBetween(111_000.0, 111_500.0);
    }

    @Test
    void shortDistanceMatchesAPlausibleWalkingScale() {
        // 经度 0.0046°（郑州纬度上）大约 400 多米 —— 这就是"附近"要分辨的量级。
        double meters = GeoCoordinate.haversineMeters(ZHENGZHOU_LNG, ZHENGZHOU_LAT, 113.6300, ZHENGZHOU_LAT);

        assertThat(meters).isBetween(300.0, 600.0);
    }
}
