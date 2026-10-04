package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;

import java.util.List;

/**
 * 内容运营（应用资源 / 主题路线 / 文化锦囊）的接口契约。
 *
 * 与景点内容分开：景点的读者是"要去某个地方的人"，这里三类的读者分别是
 * "打开首页的人""在选旅行主题的人""在补旅行常识的人"，字段重合度很低。
 */
public final class ContentModels {
    private ContentModels() {
    }

    /** 视觉资源槽的写入请求。四个字段都可以留空 —— 留空即"清掉这个槽"。 */
    public record VisualResourceInput(String imageUrl, String imageCredit, String sourceUrl,
                                      Boolean enabled) {
    }

    public record VisualResourceView(String slot, String imageUrl, String imageCredit,
                                     String sourceUrl, boolean enabled, String updatedAt) {
    }

    public record ThemeRouteInput(@NotBlank(message = "请填写路线标题") String title,
                                  @NotBlank(message = "请填写路线副标题") String subtitle,
                                  String cities,
                                  String duration,
                                  String budget,
                                  String coverUrl,
                                  List<String> highlights,
                                  String planningPrompt,
                                  String imageCredit,
                                  String sourceUrl,
                                  Boolean published,
                                 Integer sortOrder) {
    }

    public record ThemeRouteView(String id, String title, String subtitle, String cities,
                                 String duration, String budget, String coverUrl,
                                 List<String> highlights, String planningPrompt,
                                 String imageCredit, String sourceUrl,
                                 boolean published, int sortOrder, String updatedAt) {
    }

    public record CultureArticleInput(@NotBlank(message = "请填写标题") String title,
                                      String summary,
                                      @NotBlank(message = "请填写正文") String content,
                                      @NotBlank(message = "请选择分类") String category,
                                      String coverUrl,
                                      String imageCredit,
                                      String sourceUrl,
                                      Boolean published,
                                     Integer sortOrder,
                                     String author,
                                     Integer likeCount) {
    }

    public record CultureArticleView(String id, String title, String summary, String content,
                                     String category, String coverUrl, String imageCredit,
                                     String sourceUrl, boolean published, int sortOrder,
                                     String createdAt, String updatedAt,
                                     String author, int likeCount) {
    }
}
