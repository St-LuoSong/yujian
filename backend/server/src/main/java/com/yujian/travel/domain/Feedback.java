package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/**
 * 游客反馈。
 *
 * 只保存必要内容：不要求真实姓名，不采集设备标识；联系方式是可选字段，
 * 用户可以留空，管理台也只展示运营需要的最小信息。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "feedback", indexes = {
    @Index(name = "idx_feedback_status_created", columnList = "status, created_at")
})
public class Feedback {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "user_id")
    private UUID userId;

    @Column(name = "anonymous_session_id")
    private UUID anonymousSessionId;

    @Column(nullable = false, length = 32)
    private String category;

    @Column(nullable = false, length = 1000)
    private String content;

    @Column(length = 160)
    private String contact;

    /** 反馈来自哪个页面，便于定位问题。 */
    @Column(name = "page", length = 120)
    private String page;

    @Column(nullable = false, length = 32)
    private String status;

    @Column(name = "handler_note", length = 500)
    private String handlerNote;

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
            status = "OPEN";
        }
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
