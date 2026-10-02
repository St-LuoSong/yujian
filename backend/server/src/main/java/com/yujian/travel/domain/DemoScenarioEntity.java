package com.yujian.travel.domain;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Index;
import jakarta.persistence.Lob;
import jakarta.persistence.PrePersist;
import jakarta.persistence.PreUpdate;
import jakarta.persistence.Table;
import jakarta.persistence.UniqueConstraint;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

/**
 * 运营台维护的演示数据覆盖项。
 *
 * 只有显式配置并启用的记录才会覆盖代码内演示数据；没有匹配项时仍然回退到内置样例。
 * `matchKey` 用业务上可读的键，例如 `洛阳`、`郑州>洛阳`、`default`，不保存任何真实用户数据。
 */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "demo_scenario",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_demo_scenario_key_match", columnNames = {"scenario_key", "match_key"}),
    indexes = @Index(name = "idx_demo_scenario_type", columnList = "scenario_key, enabled"))
public class DemoScenarioEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "scenario_key", nullable = false, length = 48)
    private String scenarioKey;

    @Column(name = "match_key", nullable = false, length = 120)
    private String matchKey;

    @Column(nullable = false, length = 120)
    private String name;

    @Lob
    @Column(name = "payload_json", nullable = false)
    private String payloadJson;

    @Column(length = 300)
    private String note;

    @Column(nullable = false)
    private boolean enabled;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    @PreUpdate
    void touch() {
        updatedAt = Instant.now();
    }
}
