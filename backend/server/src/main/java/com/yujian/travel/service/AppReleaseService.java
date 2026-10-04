package com.yujian.travel.service;

import com.yujian.travel.api.AppReleaseModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.AppReleaseEntity;
import com.yujian.travel.infrastructure.AppReleasePackageInspector;
import com.yujian.travel.repository.AppReleaseRepository;
import jakarta.annotation.PostConstruct;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.time.Instant;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Collectors;

/** Owns the complete trusted release lifecycle: verify, stage, publish, check and download. */
@Service
public class AppReleaseService {
    public static final String PLATFORM_ANDROID = "ANDROID";
    /** 正式通道：必须由发布证书签名。 */
    public static final String CHANNEL_RELEASE = "RELEASE";
    /** 调试通道：允许 debuggable APK，签名只要求"是一份有效签名"。 */
    public static final String CHANNEL_DEBUG = "DEBUG";
    public static final String STATUS_UPLOADED = "UPLOADED";
    public static final String STATUS_PUBLISHED = "PUBLISHED";
    public static final String STATUS_SUPERSEDED = "SUPERSEDED";
    public static final String STATUS_DISABLED = "DISABLED";

    private final AppReleaseRepository repository;
    private final AppReleasePackageInspector inspector;
    private final AppProperties properties;
    private final MessageCenterService messageCenter;
    private Path root;

    public AppReleaseService(AppReleaseRepository repository,
                             AppReleasePackageInspector inspector,
                             AppProperties properties,
                             MessageCenterService messageCenter) {
        this.repository = repository;
        this.inspector = inspector;
        this.properties = properties;
        this.messageCenter = messageCenter;
    }

    @PostConstruct
    void initialize() {
        try {
            root = Path.of(properties.getAppRelease().getStorageDir()).toAbsolutePath().normalize();
            Files.createDirectories(root);
        } catch (IOException exception) {
            throw new IllegalStateException("无法创建 APK 发布目录", exception);
        }
    }

    @Transactional
    public AppReleaseModels.ReleaseView upload(MultipartFile file, String rawChannel) {
        validateUpload(file);
        String channel = normalizeChannel(rawChannel);
        Path temporary = null;
        Path target = null;
        try {
            temporary = Files.createTempFile(root, "release-", ".upload");
            try (InputStream input = file.getInputStream()) {
                Files.copy(input, temporary, StandardCopyOption.REPLACE_EXISTING);
            }

            AppReleasePackageInspector.InspectedPackage inspected =
                inspector.inspect(temporary, CHANNEL_DEBUG.equals(channel));
            validateIdentity(inspected, channel);
            if (repository.existsByPackageNameAndChannelAndVersionCode(
                inspected.packageName(), channel, inspected.versionCode())) {
                throw new ApiException(HttpStatus.CONFLICT, "APP_RELEASE_VERSION_EXISTS",
                    "该 versionCode 已上传，请递增版本号后重新构建");
            }
            repository.findFirstByPlatformAndPackageNameAndChannelOrderByVersionCodeDesc(
                    PLATFORM_ANDROID, inspected.packageName(), channel)
                .filter(previous -> inspected.versionCode() <= previous.getVersionCode())
                .ifPresent(previous -> {
                    throw new ApiException(HttpStatus.CONFLICT, "APP_RELEASE_VERSION_NOT_NEWER",
                        "versionCode 必须高于已上传版本 " + previous.getVersionCode());
                });

            String storageKey = "yujian-" + channel.toLowerCase(Locale.ROOT) + "-"
                + inspected.versionCode() + "-"
                + UUID.randomUUID().toString().replace("-", "") + ".apk";
            target = resolve(storageKey);
            try {
                Files.move(temporary, target, StandardCopyOption.ATOMIC_MOVE);
            } catch (java.nio.file.AtomicMoveNotSupportedException ignored) {
                Files.move(temporary, target, StandardCopyOption.REPLACE_EXISTING);
            }
            temporary = null;

            AppReleaseEntity entity = new AppReleaseEntity();
            entity.setPlatform(PLATFORM_ANDROID);
            entity.setChannel(channel);
            entity.setPackageName(inspected.packageName());
            entity.setVersionCode(inspected.versionCode());
            entity.setVersionName(nonBlank(inspected.versionName(), String.valueOf(inspected.versionCode())));
            entity.setReleaseTitle("豫见智旅 v" + entity.getVersionName());
            entity.setReleaseNotes("待填写更新说明");
            entity.setMinimumSupportedVersionCode(1);
            entity.setUpdateMode("OPTIONAL");
            entity.setStatus(STATUS_UPLOADED);
            entity.setStorageKey(storageKey);
            entity.setOriginalFileName(safeOriginalName(file.getOriginalFilename()));
            entity.setFileSize(Files.size(target));
            entity.setFileSha256(inspected.fileSha256());
            entity.setSigningCertificateSha256(inspected.certificateSha256());
            entity.setMinimumSdk(inspected.minimumSdk());
            entity.setTargetSdk(inspected.targetSdk());
            return view(repository.save(entity));
        } catch (ApiException exception) {
            deleteQuietly(target);
            throw exception;
        } catch (IOException exception) {
            deleteQuietly(target);
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "APP_RELEASE_WRITE_FAILED",
                "APK 保存失败，请检查服务端存储空间");
        } catch (RuntimeException exception) {
            deleteQuietly(target);
            throw exception;
        } finally {
            deleteQuietly(temporary);
        }
    }

    @Transactional(readOnly = true)
    public List<AppReleaseModels.ReleaseView> list() {
        return repository.findAllByOrderByCreatedAtDesc().stream().map(this::view).toList();
    }

    @Transactional
    public AppReleaseModels.ReleaseView publish(UUID id, AppReleaseModels.PublishRequest request) {
        AppReleaseEntity release = require(id);
        if (!STATUS_UPLOADED.equals(release.getStatus())) {
            throw new ApiException(HttpStatus.CONFLICT, "APP_RELEASE_NOT_STAGED", "只有待发布版本可以发布");
        }
        if (request.minimumSupportedVersionCode() > release.getVersionCode()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_MIN_VERSION_INVALID",
                "最低支持版本不能高于本次发布的 versionCode");
        }
        List<AppReleaseEntity> published = repository.findByPlatformAndPackageNameAndChannelAndStatus(
            PLATFORM_ANDROID, release.getPackageName(), release.getChannel(), STATUS_PUBLISHED);
        published.stream()
            .filter(item -> item.getVersionCode() >= release.getVersionCode())
            .findFirst()
            .ifPresent(item -> {
                throw new ApiException(HttpStatus.CONFLICT, "APP_RELEASE_VERSION_NOT_NEWER",
                    "不能发布低于或等于当前公开版本的安装包");
            });
        published.stream()
            .filter(item -> !item.getId().equals(release.getId()))
            .forEach(item -> item.setStatus(STATUS_SUPERSEDED));

        release.setReleaseTitle(request.releaseTitle().trim());
        release.setReleaseNotes(request.releaseNotes().trim());
        release.setMinimumSupportedVersionCode(request.minimumSupportedVersionCode());
        release.setUpdateMode(request.updateMode().trim().toUpperCase(Locale.ROOT));
        release.setStatus(STATUS_PUBLISHED);
        release.setPublishedAt(Instant.now());
        return view(repository.save(release));
    }

    @Transactional
    public AppReleaseModels.ReleaseView disable(UUID id) {
        AppReleaseEntity release = require(id);
        release.setStatus(STATUS_DISABLED);
        return view(repository.save(release));
    }

    /**
     * 把一个已停用（或已被替代）的版本重新放回公开通道。
     *
     * 只能"往上恢复"：如果已经有更高的版本在公开，恢复旧版本会把客户端推回老包。
     * 这种情况下的正确操作是把新版本停用，而不是把旧的捡回来。
     */
    @Transactional
    public AppReleaseModels.ReleaseView restore(UUID id) {
        AppReleaseEntity release = require(id);
        if (STATUS_PUBLISHED.equals(release.getStatus())) {
            return view(release);
        }
        repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
                PLATFORM_ANDROID, release.getPackageName(), release.getChannel(), STATUS_PUBLISHED)
            .filter(current -> current.getVersionCode() > release.getVersionCode())
            .ifPresent(current -> {
                throw new ApiException(HttpStatus.CONFLICT, "APP_RELEASE_VERSION_NOT_NEWER",
                    "已有更高的公开版本 " + current.getVersionCode() + "，不能恢复这一版");
            });
        repository.findByPlatformAndPackageNameAndChannelAndStatus(
                PLATFORM_ANDROID, release.getPackageName(), release.getChannel(), STATUS_PUBLISHED)
            .stream()
            .filter(item -> !item.getId().equals(release.getId()))
            .forEach(item -> item.setStatus(STATUS_SUPERSEDED));
        release.setStatus(STATUS_PUBLISHED);
        release.setPublishedAt(Instant.now());
        return view(repository.save(release));
    }

    @Transactional(readOnly = true)
    public AppReleaseModels.CheckResult check(String packageName, long versionCode, String rawChannel) {
        String expected = properties.getAppRelease().getExpectedPackageName();
        if (!expected.equals(packageName)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_PACKAGE_INVALID", "应用包名不匹配");
        }
        // 显式带了通道就严格按它查：正式包用户不该拿到调试包。
        if (rawChannel != null && !rawChannel.isBlank()) {
            return publishedRelease(expected, normalizeChannel(rawChannel))
                .map(release -> checkResult(release, versionCode))
                .orElseGet(AppReleaseModels.CheckResult::unavailable);
        }
        // 没带通道的是 v0.4.0 及以前的老客户端，它不知道通道这回事。先按正式通道
        // 找，找不到再回落到调试通道 —— 否则手上那份 APK 会被永久锁死。
        Optional<AppReleaseEntity> release = publishedRelease(expected, CHANNEL_RELEASE);
        if (release.isEmpty() && properties.getAppRelease().isLegacyCheckFallsBackToDebug()) {
            release = publishedRelease(expected, CHANNEL_DEBUG);
        }
        return release.map(item -> checkResult(item, versionCode))
            .orElseGet(AppReleaseModels.CheckResult::unavailable);
    }

    private Optional<AppReleaseEntity> publishedRelease(String packageName, String channel) {
        return repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            PLATFORM_ANDROID, packageName, channel, STATUS_PUBLISHED);
    }

    /**
     * 客户端装上某个版本之后回执一次，服务端据此在消息中心留一条更新说明。
     *
     * 幂等靠消息中心的去重键，而不是靠客户端"只调用一次"：客户端可能重装、
     * 清数据后重新登录，任何一次都不该再攒出一条重复通知。
     */
    @Transactional
    public void acknowledge(UUID userId, String packageName, long versionCode, String rawChannel) {
        String expected = properties.getAppRelease().getExpectedPackageName();
        if (!expected.equals(packageName) || versionCode < 1) {
            // 回执是顺手做的事：参数不对就静默忽略，不该让它变成一个用户可见的错误。
            return;
        }
        String channel = normalizeChannel(rawChannel);
        AppReleaseEntity release = repository
            .findFirstByPlatformAndPackageNameAndChannelAndVersionCode(
                PLATFORM_ANDROID, expected, channel, versionCode)
            .orElseGet(() -> repository
                .findFirstByPlatformAndPackageNameAndChannelAndVersionCodeLessThanEqualOrderByVersionCodeDesc(
                    PLATFORM_ANDROID, expected, channel, versionCode)
                .orElse(null));
        if (release == null) {
            return;
        }
        String notes = release.getReleaseNotes() == null || release.getReleaseNotes().isBlank()
            ? release.getReleaseTitle() : release.getReleaseNotes();
        messageCenter.publishOnce(userId, "APP_UPDATE", "版本",
            "已更新到 v" + release.getVersionName(), notes,
            "APP_RELEASE:" + release.getId());
    }

    @Transactional(readOnly = true)
    public DownloadArtifact download(UUID id) {
        AppReleaseEntity release = require(id);
        if (!STATUS_PUBLISHED.equals(release.getStatus())
            && !STATUS_SUPERSEDED.equals(release.getStatus())) {
            throw new ApiException(HttpStatus.NOT_FOUND, "APP_RELEASE_NOT_FOUND", "安装包不存在或已停止发布");
        }
        Path path = resolve(release.getStorageKey());
        if (!Files.isRegularFile(path)) {
            throw new ApiException(HttpStatus.NOT_FOUND, "APP_RELEASE_FILE_MISSING", "安装包文件不存在");
        }
        return new DownloadArtifact(new FileSystemResource(path),
            "yujian-" + release.getVersionName() + ".apk", release.getFileSize(), release.getFileSha256());
    }

    private void validateUpload(MultipartFile file) {
        if (file == null || file.isEmpty()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_FILE_REQUIRED", "请选择 APK 文件");
        }
        if (file.getOriginalFilename() == null
            || !file.getOriginalFilename().toLowerCase(Locale.ROOT).endsWith(".apk")) {
            throw new ApiException(HttpStatus.UNSUPPORTED_MEDIA_TYPE, "APP_RELEASE_TYPE_INVALID", "只允许上传 .apk 文件");
        }
        long maximum = Math.max(1, properties.getAppRelease().getMaxSizeMb()) * 1024L * 1024L;
        if (file.getSize() > maximum) {
            throw new ApiException(HttpStatus.PAYLOAD_TOO_LARGE, "APP_RELEASE_TOO_LARGE",
                "APK 不能超过 " + properties.getAppRelease().getMaxSizeMb() + "MB");
        }
    }

    private void validateIdentity(AppReleasePackageInspector.InspectedPackage inspected, String channel) {
        AppProperties.AppRelease config = properties.getAppRelease();
        if (!config.getExpectedPackageName().equals(inspected.packageName())) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_PACKAGE_INVALID",
                "APK 包名必须是 " + config.getExpectedPackageName());
        }
        if (inspected.versionCode() < 1) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_VERSION_INVALID", "APK versionCode 不合法");
        }
        // 调试通道只能校验到"文件本身是一份有效签名"这一层（ApkVerifier 已经在
        // inspect 里验过）。debug keystore 每台机器都不一样，用发布证书白名单去卡
        // 只会让内部更新通道永远收不了包。
        if (CHANNEL_DEBUG.equals(channel)) {
            return;
        }
        Set<String> allowed = config.getAllowedCertificateSha256().stream()
            .map(value -> value.replace(":", "").trim().toLowerCase(Locale.ROOT))
            .filter(value -> !value.isBlank())
            .collect(Collectors.toSet());
        if (allowed.isEmpty()) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "APP_RELEASE_CERT_NOT_CONFIGURED",
                "服务端尚未配置正式签名证书指纹，拒绝接收安装包");
        }
        if (!allowed.contains(inspected.certificateSha256().toLowerCase(Locale.ROOT))) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_CERT_MISMATCH",
                "APK 不是由豫见智旅正式发布证书签名的安装包");
        }
    }

    private AppReleaseModels.CheckResult checkResult(AppReleaseEntity release, long current) {
        boolean available = current < release.getVersionCode();
        // 落后太多就直接强制：这些用户手上的客户端可能已经跟服务端的接口契约对不上，
        // 让他们"自愿"继续用旧版本，只会换来一串解释不清的报错。
        long gap = release.getVersionCode() - current;
        boolean tooFarBehind = gap > Math.max(1, properties.getAppRelease().getForcedUpdateGap());
        boolean required = current < release.getMinimumSupportedVersionCode()
            || (available && "REQUIRED".equals(release.getUpdateMode()))
            || (available && tooFarBehind);
        return new AppReleaseModels.CheckResult(
            true, available, required, release.getVersionCode(), release.getVersionName(),
            release.getMinimumSupportedVersionCode(), release.getReleaseTitle(), release.getReleaseNotes(),
            "/api/app-releases/" + release.getId() + "/download", release.getFileSize(),
            release.getFileSha256(), release.getSigningCertificateSha256(), trustedCertificates(),
            release.getPublishedAt());
    }

    private List<String> trustedCertificates() {
        return properties.getAppRelease().getAllowedCertificateSha256().stream()
            .map(value -> value.replace(":", "").trim().toLowerCase(Locale.ROOT))
            .filter(value -> !value.isBlank())
            .distinct()
            .toList();
    }

    private AppReleaseEntity require(UUID id) {
        return repository.findById(id).orElseThrow(() ->
            new ApiException(HttpStatus.NOT_FOUND, "APP_RELEASE_NOT_FOUND", "应用版本不存在"));
    }

    private AppReleaseModels.ReleaseView view(AppReleaseEntity entity) {
        return new AppReleaseModels.ReleaseView(entity.getId(), entity.getPlatform(), entity.getChannel(),
            entity.getPackageName(),
            entity.getVersionCode(), entity.getVersionName(), entity.getReleaseTitle(), entity.getReleaseNotes(),
            entity.getMinimumSupportedVersionCode(), entity.getUpdateMode(), entity.getStatus(), entity.getFileSize(),
            entity.getFileSha256(), entity.getSigningCertificateSha256(), entity.getMinimumSdk(),
            entity.getTargetSdk(), entity.getPublishedAt(), entity.getCreatedAt());
    }

    private Path resolve(String key) {
        Path path = root.resolve(key).normalize();
        if (!path.startsWith(root) || path.equals(root)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "APP_RELEASE_PATH_REJECTED", "非法的安装包路径");
        }
        return path;
    }

    private static String safeOriginalName(String value) {
        if (value == null || value.isBlank()) {
            return "application.apk";
        }
        String fileName = new java.io.File(value).getName();
        return fileName.length() <= 180 ? fileName : fileName.substring(fileName.length() - 180);
    }

    private static String nonBlank(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value.trim();
    }

    /**
     * 通道只有两个取值，缺省是正式通道。
     *
     * 缺省给 RELEASE 而不是"猜客户端类型"：旧版 APK 不带 channel 参数，如果这里
     * 默认成 DEBUG，它们会被推到调试包上 —— 那是一份签名不同、装不上去的包。
     */
    private static String normalizeChannel(String raw) {
        String value = raw == null ? "" : raw.trim().toUpperCase(Locale.ROOT);
        if (value.isEmpty()) {
            return CHANNEL_RELEASE;
        }
        if (!CHANNEL_RELEASE.equals(value) && !CHANNEL_DEBUG.equals(value)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "APP_RELEASE_CHANNEL_INVALID", "发布通道不合法");
        }
        return value;
    }

    private static void deleteQuietly(Path path) {
        if (path == null) return;
        try {
            Files.deleteIfExists(path);
        } catch (IOException ignored) {
            // Best-effort cleanup; the verified package record is never created on failure.
        }
    }

    public record DownloadArtifact(Resource resource, String fileName, long size, String sha256) {
    }
}
