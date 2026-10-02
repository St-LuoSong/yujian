package com.yujian.travel.map;

import org.assertj.core.data.Offset;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 投影公式的守护测试。
 *
 * 最关键的一条是 matchesBaiduStaticMapRender：它不是自己推自己，
 * 而是拿百度真实渲染出来的底图做基准（基准数据与复现步骤写在注释里）。
 */
class WebMercatorTest {

    @Test
    @DisplayName("分辨率遵循百度瓦片体系：18 级 1 米/像素，每降一级翻倍")
    void resolutionFollowsBaiduTileScheme() {
        assertThat(WebMercator.resolution(18)).isEqualTo(1d);
        assertThat(WebMercator.resolution(12)).isEqualTo(64d);
        assertThat(WebMercator.resolution(11)).isEqualTo(128d);
        assertThat(WebMercator.resolution(0)).isEqualTo(WebMercator.resolution(3));
    }

    @Test
    @DisplayName("中心点永远落在图片正中")
    void centerProjectsToImageCenter() {
        WebMercator.Pixel pixel = WebMercator.project(113.65, 34.76, 113.65, 34.76, 12, 1024, 768);
        assertThat(pixel.x()).isEqualTo(512d);
        assertThat(pixel.y()).isEqualTo(384d);
    }

    @Test
    @DisplayName("与百度静态图的真实渲染对齐（城市尺度内误差小于 2 像素）")
    void matchesBaiduStaticMapRender() {
        // 反证过程（可复现）：
        // 1. 请求 staticimage/v2，center=113.65,34.76&zoom=12&width=256&height=256
        //    并带 markers=113.70,34.80；
        // 2. 再取一张完全相同的图但不带 markers，两张图做像素差分（阈值 12），
        //    唯一连通的大块差异就是图钉本身：一次实测得到 18x25 的色块；
        // 3. 用同样方法在中心点打点，图钉 bbox 中心是 (127.5, 120)，
        //    而该点的真实像素就是图片正中 (127.5, 127.5)，由此得出
        //    图钉 bbox 中心比它的锚点高 7.5 像素；
        // 4. 把第 2 步的 bbox 中心换算成锚点，实测锚点约为 (215.0, 44.0)。
        WebMercator.Pixel pixel = WebMercator.project(113.70, 34.80, 113.65, 34.76, 12, 256, 256);
        assertThat(pixel.x()).isCloseTo(215.0, Offset.offset(1.5));
        assertThat(pixel.y()).isCloseTo(44.0, Offset.offset(1.5));
    }

    @Test
    @DisplayName("纬向是墨卡托拉伸，不是等距圆柱投影")
    void latitudeUsesMercatorStretch() {
        // 同一个基准里，纬度差 0.04 度对应 84.7 像素；
        // 若按等距圆柱（每度 111320 米）算只会得到 69.6 像素，偏差远超容差。
        // 84.7 / 69.6 = 1.217，与 1/cos(34.76°) 一致，说明确实是墨卡托拉伸。
        WebMercator.Pixel north = WebMercator.project(113.65, 34.80, 113.65, 34.76, 12, 256, 256);
        assertThat(north.y()).isCloseTo(43.29, Offset.offset(1.0));
        assertThat(north.x()).isEqualTo(128d);

        WebMercator.Pixel south = WebMercator.project(113.65, 34.72, 113.65, 34.76, 12, 256, 256);
        assertThat(south.y() - 128d).isCloseTo(84.67, Offset.offset(1.0));
    }

    @Test
    @DisplayName("纬度越高 y 越小：北在上")
    void northIsUp() {
        WebMercator.Pixel north = WebMercator.project(113.65, 34.90, 113.65, 34.76, 12, 512, 512);
        WebMercator.Pixel south = WebMercator.project(113.65, 34.60, 113.65, 34.76, 12, 512, 512);
        assertThat(north.y()).isLessThan(256d);
        assertThat(south.y()).isGreaterThan(256d);
    }

    @Test
    @DisplayName("拖动位移换算回中心点，来回一趟可以还原")
    void shiftCenterIsReversible() {
        WebMercator.Coordinate moved = WebMercator.shiftCenter(113.65, 34.76, 12, 320, -160);
        WebMercator.Coordinate back = WebMercator.shiftCenter(moved.lng(), moved.lat(), 12, -320, 160);
        assertThat(back.lng()).isCloseTo(113.65, Offset.offset(1e-9));
        assertThat(back.lat()).isCloseTo(34.76, Offset.offset(1e-9));
    }

    @Test
    @DisplayName("墨卡托正反算可以互相还原")
    void projectionRoundTrip() {
        double x = WebMercator.meterX(113.65);
        double y = WebMercator.meterY(34.76);
        assertThat(WebMercator.lngOf(x)).isCloseTo(113.65, Offset.offset(1e-9));
        assertThat(WebMercator.latOf(y)).isCloseTo(34.76, Offset.offset(1e-7));
    }

    @Test
    @DisplayName("越界坐标与缩放级别被收敛到合法区间，不会抛出异常")
    void clampsOutOfRangeInput() {
        assertThat(WebMercator.clampZoom(-5)).isEqualTo(3);
        assertThat(WebMercator.clampZoom(99)).isEqualTo(19);
        assertThat(WebMercator.meterY(89.9)).isEqualTo(WebMercator.meterY(85.05112878));
        assertThat(WebMercator.meterX(999)).isEqualTo(WebMercator.meterX(180));
    }
}
