package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * 文化锦囊文章。
 *
 * 首版只允许管理员发布，不开放用户投稿：内容需要可追溯，投稿链路（审核、
 * 署名、版权）是另一个量级的工作。
 *
 * content 用 @Lob + longtext：一篇行前准备写下来轻松超过 varchar 上限，
 * 见 V2 对其它 @Lob 字段的处理。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "culture_article")
public class CultureArticleEntity {
    @Id
    @Column(length = 64)
    private String id;

    @Column(nullable = false, length = 160)
    private String title;

    @Column(length = 300)
    private String summary;

    @Lob
    @Column(nullable = false, columnDefinition = "longtext")
    private String content;

    @Column(nullable = false, length = 40)
    private String category;

    /** 署名。为空表示运营台还没填，客户端不显示。 */
    @Column(length = 80)
    private String author;

    /** 展示用点赞数，由运营台维护（见 V7 注释）。 */
    @Column(name = "like_count", nullable = false)
    private int likeCount;

    @Column(name = "cover_url", length = 600)
    private String coverUrl;

    @Column(name = "image_credit", length = 200)
    private String imageCredit;

    @Column(name = "source_url", length = 300)
    private String sourceUrl;

    @Column(nullable = false)
    private boolean published;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

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
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
