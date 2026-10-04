package com.yujian.travel.api;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class AppReleaseModels {
    private AppReleaseModels() {
    }

    public record ReleaseView(
        UUID id,
        String platform,
        String channel,
        String packageName,
        long versionCode,
        String versionName,
        String releaseTitle,
        String releaseNotes,
        long minimumSupportedVersionCode,
        String updateMode,
        String status,
        long fileSize,
        String fileSha256,
        String signingCertificateSha256,
        Integer minimumSdk,
        Integer targetSdk,
        Instant publishedAt,
        Instant createdAt
    ) {
    }

    public record CheckResult(
        boolean releaseAvailable,
        boolean updateAvailable,
        boolean updateRequired,
        long latestVersionCode,
        String latestVersionName,
        long minimumSupportedVersionCode,
        String releaseTitle,
        String releaseNotes,
        String downloadUrl,
        long fileSize,
        String fileSha256,
        String signingCertificateSha256,
        List<String> trustedCertificateSha256,
        Instant publishedAt
    ) {
        public static CheckResult unavailable() {
            return new CheckResult(false, false, false, 0, "", 0, "", "", "", 0, "", "", List.of(), null);
        }
    }

    public record PublishRequest(
        @NotBlank(message = "更新标题不能为空")
        @Size(max = 120, message = "更新标题不能超过 120 个字符")
        String releaseTitle,
        @NotBlank(message = "更新说明不能为空")
        @Size(max = 5000, message = "更新说明不能超过 5000 个字符")
        String releaseNotes,
        @Min(value = 1, message = "最低支持版本必须大于 0")
        long minimumSupportedVersionCode,
        @Pattern(regexp = "OPTIONAL|RECOMMENDED|REQUIRED", message = "更新策略不合法")
        String updateMode
    ) {
    }
}
