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
@Table(name = "email_verification", indexes = {
    @Index(name = "idx_email_verification_lookup", columnList = "email, purpose, created_at")
})
public class EmailVerification {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 160)
    private String email;

    @Column(nullable = false, length = 32)
    private String purpose;

    @Column(name = "code_hash", nullable = false, length = 64)
    private String codeHash;

    @Column(name = "requester_key_hash", length = 64)
    private String requesterKeyHash;

    @Column(nullable = false)
    private int attempts;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    @Column(name = "consumed_at")
    private Instant consumedAt;

    @PrePersist
    void prePersist() {
        if (createdAt == null) {
            createdAt = Instant.now();
        }
    }
}
