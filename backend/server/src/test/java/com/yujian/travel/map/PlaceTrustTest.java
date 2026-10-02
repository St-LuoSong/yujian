package com.yujian.travel.map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * “这个地点名能不能当成一个可信坐标”的守护测试。
 *
 * 三条判据都是实盘踩出来的，不是想当然：
 *
 * 1. 主判据是 level，不是分数 —— 真实景点（龙门石窟）百度只给 confidence=25，
 *    却带 level=乡镇；而“随便走走”能拿到 80 分。
 * 2. 标题自带城市时以标题为准 —— “洛阳博物馆”配郑州做限定会被解析到郑州市中心。
 * 3. 河南范围外的坐标一律不采信 —— 无城市限定时“随便走走”会被解析到深圳，
 *    level 与分数都看着正常，只有坐标露馅。
 */
class PlaceTrustTest {

    @Test
    @DisplayName("只定位到行政区域的 level 一律拒绝")
    void rejectsCoarseLevels() {
        assertThat(PlaceTrust.coarseLevelReason("城市")).isNotNull();
        assertThat(PlaceTrust.coarseLevelReason("区县")).isNotNull();
        assertThat(PlaceTrust.coarseLevelReason("省")).isNotNull();
    }

    @Test
    @DisplayName("乡镇级景点与旅游景点放行：判据是 level，不是分数")
    void acceptsSpecificLevels() {
        assertThat(PlaceTrust.coarseLevelReason("乡镇")).isNull();
        assertThat(PlaceTrust.coarseLevelReason("旅游景点")).isNull();
        assertThat(PlaceTrust.coarseLevelReason("")).isNull();
        assertThat(PlaceTrust.coarseLevelReason(null)).isNull();
    }

    @Test
    @DisplayName("标题里自带城市时以标题为准")
    void readsCityFromTitle() {
        assertThat(PlaceTrust.cityInTitle("洛阳博物馆")).contains("洛阳");
        assertThat(PlaceTrust.cityInTitle("开封府")).contains("开封");
        assertThat(PlaceTrust.cityInTitle("龙门石窟")).isEmpty();
        assertThat(PlaceTrust.cityInTitle("")).isEmpty();
    }

    @Test
    @DisplayName("河南境内的坐标通过范围校验")
    void acceptsHenanCoordinates() {
        assertThat(PlaceTrust.outOfRegionReason(112.484008, 34.564649)).isNull();
        assertThat(PlaceTrust.outOfRegionReason(113.665412, 34.757975)).isNull();
        assertThat(PlaceTrust.outOfRegionReason(113.4, 35.42)).isNull();
        // 边界外扩：允许贴边景点落在略微出界的位置，不误杀。
        assertThat(PlaceTrust.outOfRegionReason(110.1, 31.2)).isNull();
    }

    @Test
    @DisplayName("河南范围外的坐标一律拒绝，并说明实际落点")
    void rejectsOutOfRegionCoordinates() {
        // 实测：“随便走走”不带城市限定会被解析到深圳的一家餐厅。
        String reason = PlaceTrust.outOfRegionReason(113.908246, 22.563477);
        assertThat(reason).isNotNull();
        assertThat(reason).contains("河南范围之外").contains("113.9082").contains("22.5635");
        assertThat(PlaceTrust.outOfRegionReason(116.397428, 39.90923)).isNotNull();
    }
}
