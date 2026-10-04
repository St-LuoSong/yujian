package com.yujian.travel.domain;

import jakarta.persistence.CollectionTable;
import jakarta.persistence.Column;
import jakarta.persistence.ElementCollection;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OrderColumn;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * 社区旅记主体。
 *
 * 公开可见的内容必须经过审核；图片只保存服务端已经确认安全的 URL，不保存原图二进制。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "community_post", indexes = {
    @Index(name = "idx_community_post_status_created", columnList = "status, created_at"),
    @Index(name = "idx_community_post_city_status", columnList = "city, status"),
    @Index(name = "idx_community_post_user", columnList = "user_id, created_at")
})
public class CommunityPostEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private UserAccount user;

    /** 可选关联的一份本人行程，用于在旅记详情展示行程摘要。 */
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "trip_plan_id")
    private TripPlanEntity tripPlan;

    @Column(nullable = false, length = 80)
    private String title;

    @Column(nullable = false, length = 3000)
    private String content;

    @Column(nullable = false, length = 80)
    private String city;

    /** 逗号分隔的主题标签，例如“历史文化,美食,亲子”。 */
    @Column(length = 200)
    private String tags;

    @Column(nullable = false, length = 16)
    private String visibility = "PUBLIC";

    @Column(nullable = false, length = 20)
    private String status = "PENDING";

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "community_post_image",
        joinColumns = @JoinColumn(name = "post_id"))
    @OrderColumn(name = "sort_order")
    @Column(name = "image_url", nullable = false, length = 1024)
    private List<String> imageUrls = new ArrayList<>();

    @Column(name = "moderation_note", length = 500)
    private String moderationNote;

    @Column(name = "like_count", nullable = false)
    private long likeCount;

    @Column(name = "favorite_count", nullable = false)
    private long favoriteCount;

    /**
     * 评论数。
     *
     * 与点赞/收藏一样是冗余计数：信息流一页要渲染十几张卡片，每条都去
     * count 一次评论表会把列表接口变成 N+1 查询。写评论/删评论时同步维护，
     * 只允许向非负方向收敛。
     */
    @Column(name = "comment_count", nullable = false)
    private long commentCount;

    @Column(name = "view_count", nullable = false)
    private long viewCount;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @Column(name = "published_at")
    private Instant publishedAt;

    @Column(name = "reviewed_at")
    private Instant reviewedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
