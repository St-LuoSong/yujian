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

/** A server-verified Android package that can be promoted to the public channel. */
@Getter
@Setter
@NoArgsConstructor
@Entity
@Table(name = "app_release",
    uniqueConstraints = @UniqueConstraint(
        name = "uk_app_release_channel_version",
        columnNames = {"package_name", "channel", "version_code"}),
    indexes = {
    @Index(name = "idx_app_release_platform_status", columnList = "platform, channel, status"),
    @Index(name = "idx_app_release_version", columnList = "package_name, channel, version_code")
})
public class AppReleaseEntity {
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false, length = 20)
    private String platform;

    /**
     * 发布通道：`RELEASE` 面向正式用户，`DEBUG` 只在内部与演示机之间流转。
     *
     * 分两个通道而不是一条：正式包要求"必须由发布证书签名"，而调试包永远做不到
     * 这一点（debug keystore 每台机器都不一样）。只有一条通道的话，要么为了收调试包
     * 把正式包的签名约束一起废掉，要么就永远没法给调试机推送新包。
     */
    @Column(nullable = false, length = 16)
    private String channel = "RELEASE";

    @Column(name = "package_name", nullable = false, length = 160)
    private String packageName;

    @Column(name = "version_code", nullable = false)
    private long versionCode;

    @Column(name = "version_name", nullable = false, length = 80)
    private String versionName;

    @Column(name = "release_title", nullable = false, length = 120)
    private String releaseTitle;

    @Lob
    @Column(name = "release_notes", nullable = false)
    private String releaseNotes;

    @Column(name = "minimum_supported_version_code", nullable = false)
    private long minimumSupportedVersionCode;

    @Column(name = "update_mode", nullable = false, length = 20)
    private String updateMode;

    @Column(nullable = false, length = 20)
    private String status;

    @Column(name = "storage_key", nullable = false, unique = true, length = 180)
    private String storageKey;

    @Column(name = "original_file_name", nullable = false, length = 180)
    private String originalFileName;

    @Column(name = "file_size", nullable = false)
    private long fileSize;

    @Column(name = "file_sha256", nullable = false, length = 64)
    private String fileSha256;

    @Column(name = "signing_certificate_sha256", nullable = false, length = 64)
    private String signingCertificateSha256;

    @Column(name = "minimum_sdk")
    private Integer minimumSdk;

    @Column(name = "target_sdk")
    private Integer targetSdk;

    @Column(name = "published_at")
    private Instant publishedAt;

    @Column(name = "created_at", nullable = false, updatable = false)
    private Instant createdAt;

    @Column(name = "updated_at", nullable = false)
    private Instant updatedAt;

    @PrePersist
    void createTimestamps() {
        Instant now = Instant.now();
        createdAt = now;
        updatedAt = now;
    }

    @PreUpdate
    void updateTimestamp() {
        updatedAt = Instant.now();
    }
}
