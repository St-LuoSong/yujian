package com.yujian.travel.service;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 时长解析与格式化的回归用例。
 *
 * 这组用例全部来自真机截图上的错误数字，不是凭空设计的边界：
 * 龙门石窟写着"约34小时"、铁路节点写着"约2.0833333333333335小时"。
 * 前者是解析把"3—4"读成了 34，后者是双精度直接拼进了界面文案。
 */
class DurationTextTest {

    @Test
    void readsARangeAsItsUpperBound() {
        // "3—4小时" 去掉非数字字符后曾变成 34 小时。
        assertThat(DurationText.parseMinutes("3—4小时")).isEqualTo(240);
        assertThat(DurationText.parseMinutes("4-5小时")).isEqualTo(300);
        assertThat(DurationText.parseMinutes("2～3小时")).isEqualTo(180);
        assertThat(DurationText.parseMinutes("约1.5—2小时")).isEqualTo(120);
    }

    @Test
    void readsHoursAndMinutesSeparately() {
        // "2小时30分钟" 不能把 2 和 30 拼成 230。
        assertThat(DurationText.parseMinutes("2小时30分钟")).isEqualTo(150);
        assertThat(DurationText.parseMinutes("1小时30分")).isEqualTo(90);
    }

    @Test
    void readsMinutesAndWholeDayPhrases() {
        assertThat(DurationText.parseMinutes("45分钟")).isEqualTo(45);
        assertThat(DurationText.parseMinutes("半天")).isEqualTo(240);
        assertThat(DurationText.parseMinutes("全天")).isEqualTo(480);
        // "两天"按一天 8 小时折算，并收敛到上限 12 小时。
        assertThat(DurationText.parseMinutes("两天")).isEqualTo(720);
        assertThat(DurationText.parseMinutes("两小时")).isEqualTo(120);
    }

    @Test
    void fallsBackToTwoHoursWhenNothingCanBeRead() {
        assertThat(DurationText.parseMinutes(null)).isEqualTo(120);
        assertThat(DurationText.parseMinutes("   ")).isEqualTo(120);
        assertThat(DurationText.parseMinutes("视情况而定")).isEqualTo(120);
    }

    @Test
    void neverWritesAFractionalHour() {
        assertThat(DurationText.format(125)).isEqualTo("约2小时5分钟");
        assertThat(DurationText.format(240)).isEqualTo("约4小时");
        assertThat(DurationText.format(45)).isEqualTo("约45分钟");
        assertThat(DurationText.format(90)).isEqualTo("约1小时30分钟");
    }

    @Test
    void clampsImpossibleValues() {
        assertThat(DurationText.format(0)).isEqualTo("约5分钟");
        assertThat(DurationText.format(10_000)).isEqualTo("约12小时");
    }
}
