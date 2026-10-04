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
 * 平台视觉资源槽。
 *
 * 主键就是槽位名（HOME_HERO / PROFILE_HEADER / ...），一个槽只有一条记录。
 * 用业务名当主键而不是自增 id，是为了让"某个位置现在用哪张图"这件事在库里
 * 一眼可读，也避免运营台需要先查 id 再去改。
 *
 * imageUrl 允许为空：为空表示运营还没配，客户端退回 APK 内置的占位图，
 * 而不是显示碎图。此时 enabled 会被客户端忽略。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "app_visual_resource")
public class AppVisualResourceEntity {
    @Id
    @Column(length = 40)
    private String slot;

    @Column(name = "image_url", length = 600)
    private String imageUrl;

    @Column(name = "image_credit", length = 200)
    private String imageCredit;

    @Column(name = "source_url", length = 300)
    private String sourceUrl;

    @Column(nullable = false)
    private boolean enabled;

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
