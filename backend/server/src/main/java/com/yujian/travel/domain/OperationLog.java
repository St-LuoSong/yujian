package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/** 管理员操作日志。只记录动作与目标，不记录密钥、令牌或完整请求体。 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "operation_log", indexes = {
    @Index(name = "idx_operation_log_created", columnList = "created_at"),
    @Index(name = "idx_operation_log_action", columnList = "action")
})
public class OperationLog {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "actor_id")
    private UUID actorId;

    @Column(name = "actor_name", length = 80)
    private String actorName;

    @Column(nullable = false, length = 80)
    private String action;

    @Column(nullable = false, length = 160)
    private String target;

    @Column(length = 500)
    private String detail;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
