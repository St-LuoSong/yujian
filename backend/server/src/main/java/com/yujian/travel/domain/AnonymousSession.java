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
@Table(name = "anonymous_session", indexes = {
    @Index(name = "idx_anonymous_token_hash", columnList = "token_hash", unique = true)
})
public class AnonymousSession {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(name = "token_hash", nullable = false, unique = true, length = 64)
    private String tokenHash;

    @Column(name = "device_fingerprint_hash", length = 64)
    private String deviceFingerprintHash;

    @Column(name = "planning_count", nullable = false)
    private int planningCount;

    @Column(name = "converted_user_id")
    private UUID convertedUserId;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "last_seen_at", nullable = false)
    private Instant lastSeenAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        lastSeenAt = now;
    }
}
