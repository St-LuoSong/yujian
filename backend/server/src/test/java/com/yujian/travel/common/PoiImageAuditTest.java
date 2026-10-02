package com.yujian.travel.common;

import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 配图合规判定。
 *
 * 这些用例守着一条底线：**不能让一张占位图在界面上看起来像河南实拍**。
 * 判定出错的代价不是显示难看，而是"合规意识"这项直接失分。
 */
class PoiImageAuditTest {

    @Test
    void treatsABlankUrlAsMissing() {
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify("   ", null, null);

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.MISSING);
        assertThat(verdict.label()).isEqualTo("缺配图");
        assertThat(verdict.gaps()).containsExactly("上传有授权的河南实景图");
    }

    @Test
    void flagsAnUnsplashUrlEvenWhenTheCreditClaimsItIsLicensed() {
        // 说明写得再漂亮，也改变不了这张图不是河南实景。
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify(
            "https://images.unsplash.com/photo-1548013146?w=1200", "已获授权的河南实拍", "https://example.com");

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.PLACEHOLDER);
        assertThat(verdict.label()).isEqualTo("占位示例图");
        assertThat(verdict.gaps()).containsExactly("替换为有授权的河南实景图");
    }

    @Test
    void flagsAPlaceholderWordOnAnOwnDomainPhoto() {
        // 图片被搬到自家存储、域名看不出问题，说明里照实写了"占位"。
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify(
            "/media/longmen.jpg", "占位示例图，待运营台替换", null);

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.PLACEHOLDER);
        assertThat(verdict.gaps()).containsExactly("替换为有授权的河南实景图", "登记资料来源链接");
    }

    @Test
    void asksForBothCreditAndSourceWhenNothingIsRegistered() {
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify(
            "/media/longmen.jpg", "  ", "");

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.UNLICENSED);
        assertThat(verdict.label()).isEqualTo("来源未登记");
        assertThat(verdict.gaps()).containsExactly("登记图片版权 / 授权说明", "登记资料来源链接");
    }

    @Test
    void acceptsARegisteredPhotoWithoutAskingForASourceLink() {
        // 来源链接只是"建议补"，不该混进待办清单 —— 待办里放可以不做的事，
        // 列表就会被永远清不空。
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify(
            "/media/longmen.jpg", "摄影：张三（已授权）", null);

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.REGISTERED);
        assertThat(verdict.gaps()).isEmpty();
        assertThat(PoiImageAudit.needsWork(verdict.status())).isFalse();
    }

    @Test
    void aSourceLinkAloneIsNotEnoughToCountAsRegistered() {
        PoiImageAudit.Verdict verdict = PoiImageAudit.classify(
            "/media/longmen.jpg", null, "https://lylongmen.com");

        assertThat(verdict.status()).isEqualTo(PoiImageAudit.UNLICENSED);
        assertThat(verdict.gaps()).containsExactly("登记图片版权 / 授权说明");
    }

    @Test
    void countsEverythingExceptRegisteredAsOutstanding() {
        assertThat(PoiImageAudit.needsWork(PoiImageAudit.MISSING)).isTrue();
        assertThat(PoiImageAudit.needsWork(PoiImageAudit.PLACEHOLDER)).isTrue();
        assertThat(PoiImageAudit.needsWork(PoiImageAudit.UNLICENSED)).isTrue();
        assertThat(PoiImageAudit.needsWork(PoiImageAudit.REGISTERED)).isFalse();
    }
}
