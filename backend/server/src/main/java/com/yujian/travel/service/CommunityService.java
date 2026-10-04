package com.yujian.travel.service;

import com.yujian.travel.api.CommunityModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.CommunityCommentEntity;
import com.yujian.travel.domain.CommunityLikeEntity;
import com.yujian.travel.domain.CommunityFavoriteEntity;
import com.yujian.travel.domain.CommunityPostEntity;
import com.yujian.travel.domain.CommunityReportEntity;
import com.yujian.travel.domain.TripPlanEntity;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.CommunityCommentRepository;
import com.yujian.travel.repository.CommunityCommentLikeRepository;
import com.yujian.travel.domain.CommunityCommentLikeEntity;
import com.yujian.travel.repository.CommunityLikeRepository;
import com.yujian.travel.repository.CommunityFavoriteRepository;
import com.yujian.travel.repository.CommunityPostRepository;
import com.yujian.travel.repository.CommunityReportRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

@Service
public class CommunityService {
    public static final String PUBLIC = "PUBLIC";
    public static final String PRIVATE = "PRIVATE";
    public static final String PENDING = "PENDING";
    public static final String APPROVED = "APPROVED";
    public static final String REJECTED = "REJECTED";
    public static final String TAKEN_DOWN = "TAKEN_DOWN";

    private final CommunityPostRepository posts;
    private final CommunityLikeRepository likes;
    private final CommunityFavoriteRepository favorites;
    private final CommunityCommentRepository comments;
    private final CommunityCommentLikeRepository commentLikes;
    private final CommunityReportRepository reports;
    private final UserAccountRepository users;
    private final TripPlanRepository trips;
    private final MessageCenterService messageCenter;
    private final MediaStorageService mediaStorage;

    public CommunityService(CommunityPostRepository posts, CommunityLikeRepository likes,
                            CommunityFavoriteRepository favorites,
                            CommunityCommentRepository comments,
                            CommunityCommentLikeRepository commentLikes,
                            CommunityReportRepository reports, UserAccountRepository users,
                            TripPlanRepository trips, MessageCenterService messageCenter,
                            MediaStorageService mediaStorage) {
        this.posts = posts;
        this.likes = likes;
        this.favorites = favorites;
        this.comments = comments;
        this.commentLikes = commentLikes;
        this.reports = reports;
        this.users = users;
        this.trips = trips;
        this.messageCenter = messageCenter;
        this.mediaStorage = mediaStorage;
    }

    @Transactional
    public CommunityModels.PostView create(UUID userId, CommunityModels.CreatePostRequest request) {
        UserAccount user = requireUser(userId);
        CommunityPostEntity post = new CommunityPostEntity();
        post.setUser(user);
        post.setStatus(PENDING);
        apply(post, userId, request.title(), request.content(), request.city(), request.tags(),
            request.visibility(), request.tripPlanId(), request.imageUrls());
        return view(posts.save(post), userId);
    }

    @Transactional
    public CommunityModels.PostView update(UUID userId, UUID postId,
                                           CommunityModels.UpdatePostRequest request) {
        CommunityPostEntity post = requirePost(postId);
        requireOwner(post, userId);
        List<String> previousImages = List.copyOf(post.getImageUrls());
        post.setStatus(PENDING);
        post.setPublishedAt(null);
        post.setReviewedAt(null);
        post.setModerationNote(null);
        apply(post, userId, request.title(), request.content(), request.city(), request.tags(),
            request.visibility(), request.tripPlanId(), request.imageUrls());
        CommunityPostEntity saved = posts.save(post);
        deleteImagesNoLongerReferenced(previousImages, saved.getImageUrls(), postId);
        return view(saved, userId);
    }

    @Transactional
    public void delete(UUID userId, UUID postId) {
        CommunityPostEntity post = requirePost(postId);
        requireOwner(post, userId);
        List<String> images = List.copyOf(post.getImageUrls());
        // 先清评论：community_comment.post_id 有外键指向旅记，留着会挡住删除。
        comments.deleteByPostId(postId);
        posts.delete(post);
        posts.flush();
        deleteImagesNoLongerReferenced(images, List.of(), postId);
    }

    /**
     * 清理这次编辑/删除之后已经没有任何旅记引用的图片文件。
     *
     * 仍然被别的旅记引用（例如作者把同一张图用在了两篇旅记里）的文件必须保留，
     * 否则另一篇旅记会出现打不开的图。
     */
    private void deleteImagesNoLongerReferenced(List<String> previousImages,
                                                List<String> currentImages,
                                                UUID postId) {
        for (String url : previousImages) {
            if (currentImages.contains(url)) {
                continue;
            }
            String fileName = MediaStorageService.fileNameOf(url);
            if (fileName == null) {
                continue;
            }
            if (posts.countOthersUsingImageFile(fileName, postId) > 0) {
                continue;
            }
            mediaStorage.delete(fileName);
        }
    }

    @Transactional(readOnly = true)
    public CommunityModels.PostPage feed(String city, String tag, int page, int size, UUID viewerId) {
        PageRequest pageable = pageRequest(page, size,
            Sort.by(Sort.Direction.DESC, "publishedAt").and(Sort.by(Sort.Direction.DESC, "createdAt")));
        Page<CommunityPostEntity> result;
        if (city != null && !city.isBlank()) {
            result = posts.findByStatusAndVisibilityAndCityIgnoreCaseOrderByPublishedAtDescCreatedAtDesc(
                APPROVED, PUBLIC, city.trim(), pageable);
        } else if (tag != null && !tag.isBlank()) {
            result = posts.findByStatusAndVisibilityAndTagsContainingIgnoreCaseOrderByPublishedAtDescCreatedAtDesc(
                APPROVED, PUBLIC, tag.trim(), pageable);
        } else {
            result = posts.findByStatusAndVisibilityOrderByPublishedAtDescCreatedAtDesc(
                APPROVED, PUBLIC, pageable);
        }
        List<CommunityModels.PostView> items = result.getContent().stream()
            .map(post -> view(post, viewerId))
            .toList();
        return new CommunityModels.PostPage(items, pageable.getPageNumber() + 1,
            pageable.getPageSize(), result.getTotalElements(), result.hasNext());
    }

    @Transactional(readOnly = true)
    public CommunityModels.PostPage mine(UUID userId, int page, int size) {
        Page<CommunityPostEntity> result = posts.findByUserIdOrderByCreatedAtDesc(
            userId, pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt")));
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
        return new CommunityModels.PostPage(
            result.getContent().stream().map(post -> view(post, userId)).toList(),
            pageable.getPageNumber() + 1, pageable.getPageSize(),
            result.getTotalElements(), result.hasNext());
    }

    @Transactional
    public CommunityModels.PostView detail(UUID postId, UUID viewerId) {
        CommunityPostEntity post = requirePost(postId);
        boolean owner = viewerId != null && post.getUser().getId().equals(viewerId);
        if (!APPROVED.equals(post.getStatus()) && !owner) {
            throw notFound();
        }
        post.setViewCount(post.getViewCount() + 1);
        return view(posts.save(post), viewerId);
    }

    @Transactional
    public CommunityModels.PostView like(UUID userId, UUID postId) {
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        if (!likes.existsByUserIdAndPostId(userId, postId)) {
            CommunityLikeEntity like = new CommunityLikeEntity();
            like.setUser(requireUser(userId));
            like.setPost(post);
            likes.save(like);
            post.setLikeCount(post.getLikeCount() + 1);
            posts.save(post);
        }
        return view(post, userId);
    }

    @Transactional
    public CommunityModels.PostView unlike(UUID userId, UUID postId) {
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        likes.findByUserIdAndPostId(userId, postId).ifPresent(like -> {
            likes.delete(like);
            post.setLikeCount(Math.max(0, post.getLikeCount() - 1));
            posts.save(post);
        });
        return view(post, userId);
    }

    /**
     * 收藏（书签）一篇旅记。
     *
     * 与点赞分开：点赞表达"喜欢"，收藏表达"留着以后看"。
     * 重复调用不会重复计数。
     */
    @Transactional
    public CommunityModels.PostView favorite(UUID userId, UUID postId) {
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        if (!favorites.existsByUserIdAndPostId(userId, postId)) {
            CommunityFavoriteEntity favorite = new CommunityFavoriteEntity();
            favorite.setUser(requireUser(userId));
            favorite.setPost(post);
            favorites.save(favorite);
            post.setFavoriteCount(post.getFavoriteCount() + 1);
            posts.save(post);
        }
        return view(post, userId);
    }

    @Transactional
    public CommunityModels.PostView unfavorite(UUID userId, UUID postId) {
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        favorites.findByUserIdAndPostId(userId, postId).ifPresent(favorite -> {
            favorites.delete(favorite);
            post.setFavoriteCount(Math.max(0, post.getFavoriteCount() - 1));
            posts.save(post);
        });
        return view(post, userId);
    }

    /** 我的收藏：只返回此刻仍然公开可见的那些旅记。 */
    @Transactional(readOnly = true)
    public CommunityModels.PostPage favorites(UUID userId, int page, int size) {
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
        Page<CommunityFavoriteEntity> saved =
            favorites.findByUserIdOrderByCreatedAtDesc(userId, pageable);
        List<CommunityModels.PostView> items = saved.getContent().stream()
            .map(CommunityFavoriteEntity::getPost)
            .filter(post -> APPROVED.equals(post.getStatus()) && PUBLIC.equals(post.getVisibility()))
            .map(post -> view(post, userId))
            .toList();
        return new CommunityModels.PostPage(items, pageable.getPageNumber() + 1,
            pageable.getPageSize(), saved.getTotalElements(), saved.hasNext());
    }

    @Transactional
    public void report(UUID userId, UUID postId, String reason) {
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        if (post.getUser().getId().equals(userId)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "CANNOT_REPORT_OWN_POST", "不能举报自己的旅记");
        }
        if (reports.existsByReporterIdAndPostId(userId, postId)) {
            return;
        }
        CommunityReportEntity report = new CommunityReportEntity();
        report.setPost(post);
        report.setReporter(requireUser(userId));
        report.setReason(reason.trim());
        reports.save(report);
    }

    @Transactional(readOnly = true)
    public CommunityModels.PostPage moderationList(String status, int page, int size) {
        String target = status == null || status.isBlank() ? PENDING : status.trim().toUpperCase(Locale.ROOT);
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.ASC, "createdAt"));
        Page<CommunityPostEntity> result = posts.findByStatusOrderByCreatedAtAsc(target, pageable);
        List<CommunityModels.PostView> items = result.getContent().stream()
            .map(post -> view(post, null))
            .toList();
        return new CommunityModels.PostPage(items, pageable.getPageNumber() + 1,
            pageable.getPageSize(), result.getTotalElements(), result.hasNext());
    }

    @Transactional
    public CommunityModels.PostView moderate(UUID postId, String rawStatus, String note) {
        String status = rawStatus == null ? "" : rawStatus.trim().toUpperCase(Locale.ROOT);
        if (!List.of(APPROVED, REJECTED, TAKEN_DOWN, PENDING).contains(status)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_STATUS_INVALID", "审核状态不合法");
        }
        CommunityPostEntity post = requirePost(postId);
        post.setStatus(status);
        post.setReviewedAt(Instant.now());
        post.setModerationNote(note == null ? null : note.trim());
        if (APPROVED.equals(status)) {
            post.setPublishedAt(Instant.now());
        }
        CommunityPostEntity saved = posts.save(post);
        publishModerationMessage(saved, status, note);
        return view(saved, null);
    }

    private void publishModerationMessage(CommunityPostEntity post, String status, String note) {
        if (PENDING.equals(status)) {
            return;
        }
        String title;
        String body;
        switch (status) {
            case APPROVED -> {
                title = "你的旅记已通过审核";
                body = "《" + post.getTitle() + "》已通过审核，现在可以在旅记信息流中公开查看。";
            }
            case REJECTED -> {
                title = "你的旅记未通过审核";
                body = "《" + post.getTitle() + "》暂未通过审核。"
                    + moderationNote(note);
            }
            case TAKEN_DOWN -> {
                title = "你的旅记已被下架";
                body = "《" + post.getTitle() + "》已从公开旅记中下架。"
                    + moderationNote(note);
            }
            default -> { return; }
        }
        messageCenter.publish(post.getUser().getId(), "COMMUNITY_MODERATION", "旅记",
            title, body);
    }

    private static String moderationNote(String note) {
        return note == null || note.isBlank() ? "请打开“我的旅记”查看审核状态。"
            : "审核说明：" + note.trim();
    }

    @Transactional(readOnly = true)
    public CommunityModels.ReportPage reports(String status, int page, int size) {
        String target = status == null || status.isBlank() ? "OPEN" : status.trim().toUpperCase(Locale.ROOT);
        Page<CommunityReportEntity> result = reports.findByStatusOrderByCreatedAtDesc(
            target, pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt")));
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
        return new CommunityModels.ReportPage(result.getContent().stream().map(this::reportView).toList(),
            pageable.getPageNumber() + 1, pageable.getPageSize(),
            result.getTotalElements(), result.hasNext());
    }

    @Transactional
    public CommunityModels.ReportView handleReport(UUID reportId, String rawStatus, String note) {
        String status = rawStatus == null ? "" : rawStatus.trim().toUpperCase(Locale.ROOT);
        if (!List.of("HANDLED", "IGNORED").contains(status)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "REPORT_STATUS_INVALID", "举报处理状态不合法");
        }
        CommunityReportEntity report = reports.findById(reportId)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "REPORT_NOT_FOUND", "举报记录不存在"));
        report.setStatus(status);
        report.setHandlerNote(note == null ? null : note.trim());
        report.setHandledAt(Instant.now());
        return reportView(reports.save(report));
    }

    // ------------------------------------------------------------------
    // 评论
    // ------------------------------------------------------------------

    /**
     * 旅记下的评论列表：一页顶层评论 + 它们的全部回复。
     *
     * 可读性跟着详情页走：未过审的旅记只有作者能看到它的评论。
     */
    @Transactional(readOnly = true)
    public CommunityModels.CommentPage comments(UUID postId, int page, int size, UUID viewerId) {
        requireReadablePost(postId, viewerId);
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
        Page<CommunityCommentEntity> roots = comments
            .findByPostIdAndParentIdIsNullAndStatus(postId, CommunityCommentEntity.ACTIVE, pageable);
        List<UUID> rootIds =
            roots.getContent().stream().map(CommunityCommentEntity::getId).toList();
        Map<UUID, List<CommunityCommentEntity>> repliesByRoot = new HashMap<>();
        if (!rootIds.isEmpty()) {
            for (CommunityCommentEntity reply : comments
                .findByParentIdInAndStatusOrderByCreatedAtAsc(rootIds, CommunityCommentEntity.ACTIVE)) {
                repliesByRoot.computeIfAbsent(reply.getParentId(), key -> new ArrayList<>())
                    .add(reply);
            }
        }
        List<CommunityModels.CommentView> items = roots.getContent().stream()
            .map(root -> commentView(root, viewerId,
                repliesByRoot.getOrDefault(root.getId(), List.of()).stream()
                    .map(reply -> commentView(reply, viewerId, List.of()))
                    .toList()))
            .toList();
        return new CommunityModels.CommentPage(items, pageable.getPageNumber() + 1,
            pageable.getPageSize(), roots.getTotalElements(), roots.hasNext());
    }

    /** 运营端：一篇旅记下的全部评论，包含被隐藏的；回复挂在各自的父评论下。 */
    @Transactional(readOnly = true)
    public CommunityModels.CommentPage allComments(UUID postId, int page, int size) {
        PageRequest pageable = pageRequest(page, size, Sort.by(Sort.Direction.DESC, "createdAt"));
        Page<CommunityCommentEntity> roots =
            comments.findByPostIdAndParentIdIsNull(postId, pageable);
        List<UUID> rootIds =
            roots.getContent().stream().map(CommunityCommentEntity::getId).toList();
        Map<UUID, List<CommunityCommentEntity>> repliesByRoot = new HashMap<>();
        if (!rootIds.isEmpty()) {
            for (CommunityCommentEntity reply
                : comments.findByParentIdInOrderByCreatedAtAsc(rootIds)) {
                repliesByRoot.computeIfAbsent(reply.getParentId(), key -> new ArrayList<>())
                    .add(reply);
            }
        }
        List<CommunityModels.CommentView> items = roots.getContent().stream()
            .map(root -> commentView(root, null,
                repliesByRoot.getOrDefault(root.getId(), List.of()).stream()
                    .map(reply -> commentView(reply, null, List.of()))
                    .toList()))
            .toList();
        return new CommunityModels.CommentPage(items, pageable.getPageNumber() + 1,
            pageable.getPageSize(), roots.getTotalElements(), roots.hasNext());
    }

    @Transactional
    public CommunityModels.CommentView addComment(UUID userId, UUID postId, String rawContent,
                                                  UUID rawParentId) {
        String content = rawContent == null ? "" : rawContent.trim();
        if (content.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_COMMENT_EMPTY", "评论内容不能为空");
        }
        if (content.length() > 500) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_COMMENT_TOO_LONG",
                "评论不能超过 500 个字符");
        }
        // 只有公开且已过审的旅记能被评论：私密旅记下面冒出别人的留言会很怪。
        CommunityPostEntity post = requireVisiblePublicPost(postId);
        UserAccount author = requireUser(userId);
        CommunityCommentEntity parent = resolveReplyTarget(postId, rawParentId);

        CommunityCommentEntity comment = new CommunityCommentEntity();
        comment.setPost(post);
        comment.setUser(author);
        comment.setContent(content);
        comment.setParentId(parent == null ? null : parent.getId());
        CommunityCommentEntity saved = comments.save(comment);

        // 回复也计入总数：读者眼里"这篇有几条留言"就是列表里能看到的总条数。
        post.setCommentCount(post.getCommentCount() + 1);
        posts.save(post);

        notifyComment(post, author, content, parent);
        return commentView(saved, userId, List.of());
    }

    /**
     * 解析"回复谁"。
     *
     * 只允许回复同一篇旅记下、仍然可见的评论；回复的回复一律收敛到同一条顶层评论，
     * 所以树永远只有两层。
     */
    private CommunityCommentEntity resolveReplyTarget(UUID postId, UUID rawParentId) {
        if (rawParentId == null) {
            return null;
        }
        CommunityCommentEntity parent = requireComment(rawParentId);
        if (!parent.getPost().getId().equals(postId)
            || !CommunityCommentEntity.ACTIVE.equals(parent.getStatus())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_COMMENT_PARENT_INVALID",
                "被回复的评论不存在或已不可见");
        }
        return parent.getParentId() == null ? parent : requireComment(parent.getParentId());
    }

    /** 给评论点赞。重复调用不会重复计数。 */
    @Transactional
    public CommunityModels.CommentView likeComment(UUID userId, UUID commentId) {
        CommunityCommentEntity comment = requireComment(commentId);
        requireVisiblePublicPost(comment.getPost().getId());
        if (!commentLikes.existsByUserIdAndCommentId(userId, commentId)) {
            CommunityCommentLikeEntity like = new CommunityCommentLikeEntity();
            like.setComment(comment);
            like.setUser(requireUser(userId));
            commentLikes.save(like);
            comment.setLikeCount(comment.getLikeCount() + 1);
            comments.save(comment);
        }
        return commentView(comment, userId, List.of());
    }

    @Transactional
    public CommunityModels.CommentView unlikeComment(UUID userId, UUID commentId) {
        CommunityCommentEntity comment = requireComment(commentId);
        requireVisiblePublicPost(comment.getPost().getId());
        commentLikes.findByUserIdAndCommentId(userId, commentId).ifPresent(like -> {
            commentLikes.delete(like);
            comment.setLikeCount(Math.max(0, comment.getLikeCount() - 1));
            comments.save(comment);
        });
        return commentView(comment, userId, List.of());
    }

    /** 「我的」页的互动数据：只统计别人对我的动作。 */
    @Transactional(readOnly = true)
    public CommunityModels.CommunityStats myStats(UUID userId) {
        return new CommunityModels.CommunityStats(
            likes.countReceivedByAuthor(userId),
            commentLikes.countReceivedByAuthor(userId),
            favorites.countReceivedByAuthor(userId),
            comments.countByAuthorAndStatus(userId, CommunityCommentEntity.ACTIVE));
    }

    /** 作者撤回自己的评论。 */
    @Transactional
    public void deleteComment(UUID userId, UUID commentId) {
        CommunityCommentEntity comment = requireComment(commentId);
        if (!comment.getUser().getId().equals(userId)) {
            // 不区分"不存在"和"不是你的"：后者会告诉攻击者哪些 id 是真的。
            throw new ApiException(HttpStatus.NOT_FOUND, "COMMUNITY_COMMENT_NOT_FOUND", "评论不存在");
        }
        removeComment(comment);
    }

    /** 运营端隐藏 / 恢复一条评论。隐藏不删行，保留复核与申诉的余地。 */
    @Transactional
    public CommunityModels.CommentView moderateComment(UUID commentId, String rawStatus) {
        String status = rawStatus == null ? "" : rawStatus.trim().toUpperCase(Locale.ROOT);
        if (!List.of(CommunityCommentEntity.ACTIVE, CommunityCommentEntity.HIDDEN).contains(status)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_COMMENT_STATUS_INVALID",
                "评论处理状态不合法");
        }
        CommunityCommentEntity comment = requireComment(commentId);
        if (comment.getParentId() == null) {
            // 顶层评论连同它的回复一起处理：只藏父评论的话，那些回复会既算在
            // comment_count 里，又因为父评论不可见而在界面上消失。
            List<CommunityCommentEntity> replies =
                comments.findByParentIdOrderByCreatedAtAsc(comment.getId());
            for (CommunityCommentEntity reply : replies) {
                adjustCommentCount(reply, status);
                reply.setStatus(status);
            }
            comments.saveAll(replies);
        }
        adjustCommentCount(comment, status);
        comment.setStatus(status);
        CommunityCommentEntity saved = comments.save(comment);
        return commentView(saved, null, List.of());
    }

    /** 状态真的变了才动 comment_count，且只把 ACTIVE 计入。 */
    private void adjustCommentCount(CommunityCommentEntity comment, String nextStatus) {
        if (nextStatus.equals(comment.getStatus())) {
            return;
        }
        CommunityPostEntity post = comment.getPost();
        long delta = CommunityCommentEntity.ACTIVE.equals(nextStatus) ? 1L : -1L;
        post.setCommentCount(Math.max(0, post.getCommentCount() + delta));
        posts.save(post);
    }

    private void removeComment(CommunityCommentEntity comment) {
        CommunityPostEntity post = comment.getPost();
        long counted = CommunityCommentEntity.ACTIVE.equals(comment.getStatus()) ? 1L : 0L;
        // 回复由外键 on delete cascade 一起删掉，但它们的计数要在这里扣回来。
        counted += comments.countByParentIdAndStatus(comment.getId(), CommunityCommentEntity.ACTIVE);
        comments.delete(comment);
        if (counted > 0) {
            post.setCommentCount(Math.max(0, post.getCommentCount() - counted));
            posts.save(post);
        }
    }

    private CommunityCommentEntity requireComment(UUID commentId) {
        return comments.findById(commentId).orElseThrow(() ->
            new ApiException(HttpStatus.NOT_FOUND, "COMMUNITY_COMMENT_NOT_FOUND", "评论不存在"));
    }

    /**
     * 有人评论 / 回复时给对方发一条站内消息。
     *
     * 收件人优先是"被回复的那条评论的作者"，没有父评论时才是旅记作者。
     * 发给自己的不发 —— 那只会变成一条自己看自己的噪音；但如果"回复自己"
     * 发生在别人的旅记下，旅记作者仍然该知道有新留言，所以这时退回到作者。
     */
    private void notifyComment(CommunityPostEntity post, UserAccount commenter, String content,
                               CommunityCommentEntity parent) {
        UUID postAuthorId = post.getUser().getId();
        UUID targetId = parent == null ? postAuthorId : parent.getUser().getId();
        if (targetId.equals(commenter.getId())) {
            targetId = postAuthorId;
            if (targetId.equals(commenter.getId())) {
                return;
            }
        }
        String name = commenter.getNickname() == null || commenter.getNickname().isBlank()
            ? commenter.getUsername() : commenter.getNickname();
        String excerpt = content.length() <= 60 ? content : content.substring(0, 60) + "…";
        String title = parent == null ? name + " 评论了你的旅记" : name + " 回复了你的评论";
        messageCenter.publish(targetId, "COMMUNITY_COMMENT", "旅记", title,
            "《" + post.getTitle() + "》：" + excerpt);
    }

    private CommunityPostEntity requireReadablePost(UUID postId, UUID viewerId) {
        CommunityPostEntity post = requirePost(postId);
        boolean owner = viewerId != null && post.getUser().getId().equals(viewerId);
        if (!APPROVED.equals(post.getStatus()) && !owner) {
            throw notFound();
        }
        return post;
    }

    private void apply(CommunityPostEntity post, UUID userId, String title, String content,
                       String city, String tags, String visibility, UUID tripPlanId,
                       List<String> imageUrls) {
        post.setTitle(title.trim());
        post.setContent(content.trim());
        post.setCity(city.trim());
        post.setTags(tags == null ? null : tags.trim());
        post.setVisibility(visibility == null || visibility.isBlank()
            ? PUBLIC : visibility.trim().toUpperCase(Locale.ROOT));
        if (!List.of(PUBLIC, PRIVATE).contains(post.getVisibility())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_VISIBILITY_INVALID", "公开范围不合法");
        }
        List<String> cleanImages = imageUrls == null ? List.of() : imageUrls.stream()
            .map(String::trim)
            .filter(value -> !value.isBlank())
            .limit(9)
            .toList();
        for (String imageUrl : cleanImages) {
            if (!(imageUrl.startsWith("https://")
                || imageUrl.startsWith("http://")
                || imageUrl.startsWith("/media/"))) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "COMMUNITY_IMAGE_URL_INVALID",
                    "图片地址不合法");
            }
        }
        post.setImageUrls(new ArrayList<>(cleanImages));
        if (tripPlanId == null) {
            post.setTripPlan(null);
        } else {
            TripPlanEntity trip = trips.findWithDetailsByIdAndOwnerId(tripPlanId, userId)
                .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "TRIP_NOT_FOUND", "关联行程不存在"));
            post.setTripPlan(trip);
        }
    }

    private CommunityPostEntity requireVisiblePublicPost(UUID postId) {
        CommunityPostEntity post = requirePost(postId);
        if (!APPROVED.equals(post.getStatus()) || !PUBLIC.equals(post.getVisibility())) {
            throw notFound();
        }
        return post;
    }

    private CommunityPostEntity requirePost(UUID postId) {
        return posts.findWithDetailsById(postId).orElseThrow(this::notFound);
    }

    private UserAccount requireUser(UUID userId) {
        return users.findById(userId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "请先登录"));
    }

    private void requireOwner(CommunityPostEntity post, UUID userId) {
        if (!post.getUser().getId().equals(userId)) {
            throw notFound();
        }
    }

    private CommunityModels.PostView view(CommunityPostEntity post, UUID viewerId) {
        String author = post.getUser().getNickname() == null || post.getUser().getNickname().isBlank()
            ? post.getUser().getUsername() : post.getUser().getNickname();
        boolean liked = viewerId != null && likes.existsByUserIdAndPostId(viewerId, post.getId());
        boolean favorited =
            viewerId != null && favorites.existsByUserIdAndPostId(viewerId, post.getId());
        return new CommunityModels.PostView(post.getId(), author, post.getUser().getAvatarKey(),
            post.getUser().getAvatarUrl(),
            post.getTripPlan() == null ? null : post.getTripPlan().getId(),
            post.getTitle(), post.getContent(), post.getCity(), post.getTags(),
            post.getVisibility(), post.getStatus(), List.copyOf(post.getImageUrls()),
            post.getLikeCount(), post.getFavoriteCount(), post.getCommentCount(),
            post.getViewCount(),
            liked, favorited, post.getCreatedAt(),
            post.getPublishedAt(), post.getModerationNote());
    }

    private CommunityModels.CommentView commentView(CommunityCommentEntity comment, UUID viewerId,
                                                    List<CommunityModels.CommentView> replies) {
        UserAccount author = comment.getUser();
        String name = author.getNickname() == null || author.getNickname().isBlank()
            ? author.getUsername() : author.getNickname();
        return new CommunityModels.CommentView(comment.getId(), comment.getPost().getId(),
            comment.getParentId(), name, author.getAvatarKey(), author.getAvatarUrl(),
            comment.getContent(), comment.getStatus(), comment.getLikeCount(),
            viewerId != null && commentLikes.existsByUserIdAndCommentId(viewerId, comment.getId()),
            viewerId != null && author.getId().equals(viewerId),
            comment.getCreatedAt(), replies);
    }

    private CommunityModels.ReportView reportView(CommunityReportEntity report) {
        String reporter = report.getReporter().getNickname() == null
            || report.getReporter().getNickname().isBlank()
            ? report.getReporter().getUsername() : report.getReporter().getNickname();
        return new CommunityModels.ReportView(report.getId(), report.getPost().getId(), reporter,
            report.getReason(), report.getStatus(), report.getHandlerNote(),
            report.getCreatedAt(), report.getHandledAt());
    }

    private PageRequest pageRequest(int page, int size, Sort sort) {
        int safePage = Math.max(1, page);
        int safeSize = Math.min(50, Math.max(1, size));
        return PageRequest.of(safePage - 1, safeSize, sort);
    }

    private ApiException notFound() {
        return new ApiException(HttpStatus.NOT_FOUND, "COMMUNITY_POST_NOT_FOUND", "旅记不存在或未公开");
    }
}
