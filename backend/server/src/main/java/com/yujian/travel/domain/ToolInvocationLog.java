package com.yujian.travel.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "tool_invocation_log", indexes = {
    @Index(name = "idx_tool_invocation_trip", columnList = "trip_plan_id, created_at"),
    @Index(name = "idx_tool_invocation_correlation", columnList = "correlation_id")
})
public class ToolInvocationLog {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "trip_plan_id")
    private UUID tripPlanId;

    @Column(name = "correlation_id", nullable = false)
    private UUID correlationId;

    @Column(name = "tool_name", nullable = false, length = 80)
    private String toolName;

    @Column(length = 160)
    private String source;

    @Column(name = "data_status", length = 32)
    private String dataStatus;

    @Column(nullable = false)
    private boolean success;

    @Column(name = "input_summary", length = 500)
    private String inputSummary;

    @Column(name = "output_summary", length = 1000)
    private String outputSummary;

    @Column(name = "error_code", length = 80)
    private String errorCode;

    @Column(name = "duration_ms")
    private Long durationMs;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
