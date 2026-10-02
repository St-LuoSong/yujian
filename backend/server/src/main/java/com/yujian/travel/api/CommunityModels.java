package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class CommunityModels {
    private CommunityModels() {
    }

    public record CreatePostRequest(
        @NotBlank(message = "请输入旅记标题")
        @Size(max = 80, message = "标题不能超过 80 个字符")
        String title,
        @NotBlank(message = "请输入旅记正文")
        @Size(max = 3000, message = "正文不能超过 3000 个字符")
        String content,
        @NotBlank(message = "请输入城市")
        @Size(max = 80, message = "城市不能超过 80 个字符")
        String city,
        @Size(max = 200, message = "标签不能超过 200 个字符")
        String tags,
        String visibility,
        UUID tripPlanId,
        @Size(max = 9, message = "最多上传 9 张图片")
        List<@Size(max = 1024, message = "图片地址过长") String> imageUrls
    ) {
    }

    public record UpdatePostRequest(
        @NotBlank(message = "请输入旅记标题")
        @Size(max = 80, message = "标题不能超过 80 个字符")
        String title,
        @NotBlank(message = "请输入旅记正文")
        @Size(max = 3000, message = "正文不能超过 3000 个字符")
        String content,
        @NotBlank(message = "请输入城市")
        @Size(max = 80, message = "城市不能超过 80 个字符")
        String city,
        @Size(max = 200, message = "标签不能超过 200 个字符")
        String tags,
        String visibility,
        UUID tripPlanId,
        @Size(max = 9, message = "最多上传 9 张图片")
        List<@Size(max = 1024, message = "图片地址过长") String> imageUrls
    ) {
    }

    public record ModerationRequest(
        @NotBlank(message = "请选择审核结果") String status,
        @Size(max = 500, message = "审核说明不能超过 500 个字符") String note
    ) {
    }

    public record ReportRequest(
        @NotBlank(message = "请选择举报原因")
        @Size(max = 500, message = "举报原因不能超过 500 个字符")
        String reason
    ) {
    }

    public record ReportHandleRequest(
        @NotBlank(message = "请选择处理结果") String status,
        @Size(max = 500, message = "处理说明不能超过 500 个字符") String note
    ) {
    }

    public record PostView(
        UUID id,
        String authorName,
        String authorAvatarKey,
        UUID tripPlanId,
        String title,
        String content,
        String city,
        String tags,
        String visibility,
        String status,
        List<String> imageUrls,
        long likeCount,
        long viewCount,
        boolean likedByMe,
        Instant createdAt,
        Instant publishedAt,
        String moderationNote
    ) {
    }

    public record PostPage(List<PostView> items, int page, int size, long total, boolean hasMore) {
    }

    public record ReportView(
        UUID id,
        UUID postId,
        String reporterName,
        String reason,
        String status,
        String handlerNote,
        Instant createdAt,
        Instant handledAt
    ) {
    }

    public record ReportPage(List<ReportView> items, int page, int size, long total, boolean hasMore) {
    }
}
