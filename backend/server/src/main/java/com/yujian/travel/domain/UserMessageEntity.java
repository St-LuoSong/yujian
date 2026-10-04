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
 * 登录用户的服务端消息。
 *
 * 只保存产品与数据说明，不保存推送令牌、设备标识或聊天内容。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "user_message", indexes = {
    @Index(name = "idx_user_message_user", columnList = "user_id, created_at"),
    @Index(name = "idx_user_message_unread", columnList = "user_id, read_flag")
})
public class UserMessageEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id", nullable = false)
    private UserAccount user;

    @Column(nullable = false, length = 32)
    private String type;

    /**
     * 去重键。同一个用户 + 同一个键只会存在一条消息（数据库唯一索引兜底）。
     *
     * 为空表示这条消息不参与去重（例如首次登录时种入的产品说明）。
     */
    @Column(name = "dedupe_key", length = 120)
    private String dedupeKey;

    @Column(nullable = false, length = 120)
    private String title;

    @Column(nullable = false, length = 1000)
    private String body;

    @Column(name = "read_flag", nullable = false)
    private boolean read;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "read_at")
    private Instant readAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
