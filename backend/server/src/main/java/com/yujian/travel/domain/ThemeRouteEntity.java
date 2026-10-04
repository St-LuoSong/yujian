package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;

/**
 * 主题路线（示范走廊）。
 *
 * id 是业务主键，例如 zheng-luo：行程文本与分享链接引用它，所以不随内容更新变化。
 * highlights 以英文逗号分隔存一行 —— 它是纯展示用的短标签列表，量小且不参与查询，
 * 单独建表只会多一次 join。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "theme_route")
public class ThemeRouteEntity {
    @Id
    @Column(length = 64)
    private String id;

    @Column(nullable = false, length = 120)
    private String title;

    @Column(nullable = false, length = 200)
    private String subtitle;

    @Column(length = 120)
    private String cities;

    @Column(length = 40)
    private String duration;

    @Column(length = 40)
    private String budget;

    @Column(name = "cover_url", length = 600)
    private String coverUrl;

    /** 英文逗号分隔的短标签，例如 "龙门石窟,博物馆,古都深度游"。 */
    @Column(length = 500)
    private String highlights;

    /** 点击这条路线时带去规划页的自然语言提示词。 */
    @Column(name = "planning_prompt", length = 500)
    private String planningPrompt;

    @Column(nullable = false)
    private boolean published;

    @Column(name = "sort_order", nullable = false)
    private int sortOrder;

    @Column(name = "image_credit", length = 200)
    private String imageCredit;

    @Column(name = "source_url", length = 300)
    private String sourceUrl;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        updatedAt = Instant.now();
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
