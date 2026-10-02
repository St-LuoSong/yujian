package com.yujian.travel.service;

import com.yujian.travel.api.CommunityModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.CommunityLikeEntity;
import com.yujian.travel.domain.CommunityPostEntity;
import com.yujian.travel.domain.CommunityReportEntity;
import com.yujian.travel.domain.TripPlanEntity;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.CommunityLikeRepository;
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
import java.util.List;
import java.util.Locale;
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
    private final CommunityReportRepository reports;
    private final UserAccountRepository users;
    private final TripPlanRepository trips;

    public CommunityService(CommunityPostRepository posts, CommunityLikeRepository likes,
                            CommunityReportRepository reports, UserAccountRepository users,
                            TripPlanRepository trips) {
        this.posts = posts;
        this.likes = likes;
        this.reports = reports;
        this.users = users;
        this.trips = trips;
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
        post.setStatus(PENDING);
        post.setPublishedAt(null);
        post.setReviewedAt(null);
        post.setModerationNote(null);
        apply(post, userId, request.title(), request.content(), request.city(), request.tags(),
            request.visibility(), request.tripPlanId(), request.imageUrls());
        return view(posts.save(post), userId);
    }

    @Transactional
    public void delete(UUID userId, UUID postId) {
        CommunityPostEntity post = requirePost(postId);
        requireOwner(post, userId);
        posts.delete(post);
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
        return view(posts.save(post), null);
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
        return new CommunityModels.PostView(post.getId(), author, post.getUser().getAvatarKey(),
            post.getTripPlan() == null ? null : post.getTripPlan().getId(),
            post.getTitle(), post.getContent(), post.getCity(), post.getTags(),
            post.getVisibility(), post.getStatus(), List.copyOf(post.getImageUrls()),
            post.getLikeCount(), post.getViewCount(), liked, post.getCreatedAt(),
            post.getPublishedAt(), post.getModerationNote());
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
