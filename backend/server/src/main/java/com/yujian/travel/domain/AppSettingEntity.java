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
 * 运行时可改的系统设置。
 *
 * 主键就是设置键本身（业务可读的字符串），不做自增 id：查一处配置时
 * "按名字查"才是最自然的入口，多一层代理主键只会让排障时多跳一次。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "app_setting")
public class AppSettingEntity {
    @Id
    @Column(name = "setting_key", length = 120)
    private String key;

    @Column(name = "setting_value", nullable = false, length = 500)
    private String value;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    @PreUpdate
    void touch() {
        updatedAt = Instant.now();
    }
}
