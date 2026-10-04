package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;

import java.time.Instant;
import java.util.List;

public final class PoiModels {
    private PoiModels() {
    }

    /**
     * 运营台契约。
     *
     * imageStatus / imageStatusLabel / imageGaps 是**派生字段**，不落库：
     * 由 {@link com.yujian.travel.common.PoiImageAudit} 按当前图片与来源信息现算。
     * 这样"配图能不能交付"这件事只有一处规则，管理台不需要自己再判一遍。
     */
    public record PoiView(String id, String name, String city, String category, String imageUrl,
                          String description, int ticketFrom, String duration, String suitability,
                          String weatherTip, String dataStatus, String imageCredit, String sourceUrl,
                          Double lng, Double lat,
                          boolean published, int sortOrder, Instant createdAt, Instant updatedAt,
                          String imageStatus, String imageStatusLabel, List<String> imageGaps,
                          String openingHours, String reservationNote,
                          boolean homeFeatured, int featuredSortOrder,
                          List<MediaView> gallery) {
    }

    public record PoiInput(@NotBlank(message = "请填写景点名称") String name,
                           @NotBlank(message = "请填写所属城市") String city,
                           @NotBlank(message = "请填写主题分类") String category,
                           String imageUrl,
                           @NotBlank(message = "请填写一句话介绍") String description,
                           Integer ticketFrom,
                           @NotBlank(message = "请填写建议游玩时长") String duration,
                           String suitability,
                           String weatherTip,
                           String dataStatus,
                           String imageCredit,
                           String sourceUrl,
                           Double lng,
                           Double lat,
                           Boolean published,
                           Integer sortOrder,
                           /** 开放时间，可空。留空时客户端显示"以景区公告为准"。 */
                           String openingHours,
                           /** 预约说明，可空。 */
                           String reservationNote) {
    }

    /** 首页推荐位的开关与排序。和整体编辑分开，运营勾一下就能上/下首页。 */
    public record FeaturedInput(Boolean homeFeatured, Integer featuredSortOrder) {
    }

    /** 图集里的一张图。 */
    public record MediaView(Long id, String poiId, String imageUrl, String caption,
                            String imageCredit, String sourceUrl, int sortOrder, boolean published) {
    }

    public record MediaInput(@NotBlank(message = "请先上传图片") String imageUrl,
                             String caption,
                             String imageCredit,
                             String sourceUrl,
                             Integer sortOrder,
                             Boolean published) {
    }

    public record PublishInput(boolean published) {
    }

    /**
     * 运营台“解析坐标”的入参。
     *
     * 与保存景点分开：解析只是给运营人员一个参考值，点“保存”之前不会写库，
     * 所以可以放心地点、放心地试，不会因为一次误操作把坐标存坏。
     */
    public record GeocodeRequest(@NotBlank(message = "请填写景点名称") String name, String city) {
    }

    /**
     * 解析结果。
     *
     * trusted=false 时 lng/lat **一律为空**：只定位到城市中心、可信度不足、
     * 或是外部服务不可用，都不给出一个"看起来能用"的坐标。宁可让运营人员
     * 手工填写，也不允许一个错误的坐标顺着界面流进数据库。
     */
    public record GeocodePreview(String query, String cityHint, Double lng, Double lat, String level,
                                 int confidence, boolean trusted, String source, String message) {
    }
}
