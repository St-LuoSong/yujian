package com.yujian.travel.domain;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.time.Instant;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "user_account")
public class UserAccount {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, unique = true, length = 64)
    private String username;

    @Column(unique = true, length = 160)
    private String email;

    @Column(length = 40)
    private String nickname;

    /** 预设头像键，不保存外部图片地址，避免把用户照片公开到 /media。 */
    @Column(name = "avatar_key", length = 32)
    private String avatarKey;

    @Column(nullable = false, length = 100)
    private String passwordHash;

    @Column(nullable = false)
    private boolean emailVerified;

    @ElementCollection(fetch = FetchType.EAGER)
    @CollectionTable(name = "user_role", joinColumns = @JoinColumn(name = "user_id"))
    @Column(name = "role_name", nullable = false, length = 32)
    private Set<String> roles = new HashSet<>();

    @Column(nullable = false, updatable = false)
    private Instant createdAt;

    @Column(nullable = false)
    private Instant updatedAt;

    @PrePersist
    void prePersist() {
        Instant now = Instant.now();
        if (createdAt == null) {
            createdAt = now;
        }
        updatedAt = now;
        if (roles.isEmpty()) {
            roles.add("USER");
        }
    }

    @PreUpdate
    void preUpdate() {
        updatedAt = Instant.now();
    }
}
