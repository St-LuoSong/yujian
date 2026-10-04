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
        String authorAvatarUrl,
        UUID tripPlanId,
        String title,
        String content,
        String city,
        String tags,
        String visibility,
        String status,
        List<String> imageUrls,
        long likeCount,
        long favoriteCount,
        long commentCount,
        long viewCount,
        boolean likedByMe,
        boolean favoritedByMe,
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

    public record CreateCommentRequest(
        @NotBlank(message = "评论内容不能为空")
        @Size(max = 500, message = "评论不能超过 500 个字符")
        String content,
        /** 为空是顶层评论；非空表示回复某条顶层评论。 */
        UUID parentId
    ) {
    }

    /**
     * 一条评论。
     *
     * [mine] 由服务端判定，而不是让客户端拿自己的用户名去比对 —— 用户名可能
     * 被管理员改过，而且客户端也不该知道"删除按钮该不该出现"这件事的全部条件。
     *
     * [replies] 只有顶层评论会带内容；回复自身的这一项恒为空列表，避免客户端
     * 递归渲染出一棵它没法收尾的树。
     */
    public record CommentView(
        UUID id,
        UUID postId,
        UUID parentId,
        String authorName,
        String authorAvatarKey,
        String authorAvatarUrl,
        String content,
        String status,
        long likeCount,
        boolean likedByMe,
        boolean mine,
        Instant createdAt,
        List<CommentView> replies
    ) {
    }

    public record CommentPage(List<CommentView> items, int page, int size, long total, boolean hasMore) {
    }

    /**
     * 「我的」页的互动数据。
     *
     * 每一项都只统计"别人对我"的动作：自己给自己的旅记点赞、给自己的评论点赞
     * 都不该出现在"我获得的"里，否则这块数字就退化成"我点过多少下"。
     */
    public record CommunityStats(
        long postLikes,
        long commentLikes,
        long favorites,
        long comments
    ) {
    }

    public record CommentModerationRequest(
        @NotBlank(message = "请选择处理结果") String status
    ) {
    }
}
