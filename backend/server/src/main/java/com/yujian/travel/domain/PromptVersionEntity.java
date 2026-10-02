package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/**
 * 可管理的系统提示词版本。
 *
 * 只保存系统提示词，不保存用户请求和工具数据；工具数据仍由服务端在每次规划时按请求组装。
 * 旧版本不删除，用于回滚和答辩时说明“为什么某次方案用了这个版本”。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "prompt_version", indexes = {
    @Index(name = "idx_prompt_version_active", columnList = "active, created_at")
})
public class PromptVersionEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true, length = 64)
    private String version;

    @Lob
    @Column(name = "system_prompt", nullable = false)
    private String systemPrompt;

    @Column(length = 200)
    private String note;

    @Column(nullable = false)
    private boolean active;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
