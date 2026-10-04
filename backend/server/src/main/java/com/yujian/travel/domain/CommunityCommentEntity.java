package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/**
 * 旅记评论。
 *
 * 与点赞/收藏分开存：这两个是"一个人对一篇最多一条"的开关，评论是一篇对多条、
 * 允许同一用户反复发言的流水。混在一张表里会立刻失去唯一约束的意义。
 *
 * 当前只有一层，不做楼中楼：回复的层级、折叠规则和通知口径都是独立的一块工作量，
 * 首版先用一层把"能不能评论"这件事做扎实。
 *
 * `status` 是管理的抓手：`ACTIVE` 正常，`HIDDEN` 是被管理员隐藏（不物理删除，
 * 便于复核与申诉），作者自己删除才会真正删行。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "community_comment", indexes = {
    @Index(name = "idx_community_comment_post", columnList = "post_id, status, created_at"),
    @Index(name = "idx_community_comment_user", columnList = "user_id, created_at")
})
public class CommunityCommentEntity {
    public static final String ACTIVE = "ACTIVE";
    public static final String HIDDEN = "HIDDEN";

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id", nullable = false)
    private CommunityPostEntity post;

    /**
     * 顶层评论 id。为空表示这是一条顶层评论。
     *
     * 用裸 UUID 而不是自关联映射：回复的父级只在"按顶层分组"时用一次，
     * 换成 `@ManyToOne` 只会给每个视图多带一个用不上的懒加载代理。
     */
    @Column(name = "parent_id")
    private UUID parentId;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private UserAccount user;

    @Column(nullable = false, length = 500)
    private String content;

    @Column(name = "like_count", nullable = false)
    private long likeCount;

    @Column(nullable = false, length = 20)
    private String status = ACTIVE;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
        if (status == null || status.isBlank()) {
            status = ACTIVE;
        }
    }
}
