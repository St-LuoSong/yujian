package com.yujian.travel.service;

import com.yujian.travel.api.AppReleaseModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.AppReleaseEntity;
import com.yujian.travel.infrastructure.AppReleasePackageInspector;
import com.yujian.travel.repository.AppReleaseRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

import java.nio.file.Path;
import java.time.Instant;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyBoolean;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class AppReleaseServiceTest {
    @TempDir
    Path tempDir;

    @Test
    void uploadRefusesPackagesUntilTheTrustedCertificateIsConfigured() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleasePackageInspector inspector = mock(AppReleasePackageInspector.class);
        when(inspector.inspect(any(), anyBoolean())).thenReturn(inspected("trusted"));
        AppReleaseService service = service(repository, inspector, properties);

        assertThatThrownBy(() -> service.upload(apk(), "RELEASE"))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("尚未配置正式签名证书");
        verifyNoInteractions(repository);
    }

    @Test
    void checkRequiresUpdateBelowMinimumSupportedVersion() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(20, 15, "OPTIONAL");
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(Optional.of(release));
        AppReleaseService service = service(repository, mock(AppReleasePackageInspector.class), properties);

        AppReleaseModels.CheckResult result = service.check("com.yujian.travel", 12, "RELEASE");

        assertThat(result.updateAvailable()).isTrue();
        assertThat(result.updateRequired()).isTrue();
        assertThat(result.downloadUrl()).contains(release.getId().toString());
    }

    @Test
    void checkDoesNotOfferTheSameOrNewerVersion() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(20, 15, "REQUIRED");
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(Optional.of(release));
        AppReleaseService service = service(repository, mock(AppReleasePackageInspector.class), properties);

        AppReleaseModels.CheckResult result = service.check("com.yujian.travel", 20, "RELEASE");

        assertThat(result.updateAvailable()).isFalse();
        assertThat(result.updateRequired()).isFalse();
    }

    @Test
    void supersededPackageRemainsDownloadableForAnAlreadyIssuedLink() throws Exception {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(20, 15, "OPTIONAL");
        release.setStatus("SUPERSEDED");
        release.setStorageKey("release.apk");
        java.nio.file.Files.write(tempDir.resolve("release.apk"), new byte[] {1, 2, 3});
        when(repository.findById(release.getId())).thenReturn(Optional.of(release));
        AppReleaseService service = service(repository, mock(AppReleasePackageInspector.class), properties);

        assertThat(service.download(release.getId()).resource().exists()).isTrue();
    }

    @Test
    void publishRejectsAStagedVersionBelowTheCurrentPublicVersion() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity staged = published(20, 1, "OPTIONAL");
        staged.setStatus("UPLOADED");
        AppReleaseEntity current = published(21, 1, "OPTIONAL");
        when(repository.findById(staged.getId())).thenReturn(Optional.of(staged));
        when(repository.findByPlatformAndPackageNameAndChannelAndStatus(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(List.of(current));
        AppReleaseService service = service(repository, mock(AppReleasePackageInspector.class), properties);

        assertThatThrownBy(() -> service.publish(staged.getId(),
            new AppReleaseModels.PublishRequest("旧版本", "不能回滚", 1, "OPTIONAL")))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("不能发布低于或等于");
    }

    @Test
    void aVersionFarBehindIsForcedEvenWhenTheReleaseIsOptional() {
        AppProperties properties = properties();
        properties.getAppRelease().setForcedUpdateGap(5);
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(30, 1, "OPTIONAL");
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(Optional.of(release));
        AppReleaseService service = service(repository, mock(AppReleasePackageInspector.class), properties);

        // 落后 6 个版本，超过 5 的跨度上限：即使发布策略是 OPTIONAL 也强制更新。
        AppReleaseModels.CheckResult farBehind = service.check("com.yujian.travel", 24, "RELEASE");
        assertThat(farBehind.updateAvailable()).isTrue();
        assertThat(farBehind.updateRequired()).isTrue();

        // 只落后 2 个版本：仍然让用户自己决定什么时候升。
        AppReleaseModels.CheckResult justBehind = service.check("com.yujian.travel", 28, "RELEASE");
        assertThat(justBehind.updateAvailable()).isTrue();
        assertThat(justBehind.updateRequired()).isFalse();
    }

    @Test
    void debugChannelAcceptsPackagesWithoutTheReleaseCertificate() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleasePackageInspector inspector = mock(AppReleasePackageInspector.class);
        when(inspector.inspect(any(), anyBoolean()))
            .thenReturn(new AppReleasePackageInspector.InspectedPackage(
                "com.yujian.travel", 7, "0.4.0", 29, 35, "debug-keystore-fingerprint", "filehash"));
        when(repository.existsByPackageNameAndChannelAndVersionCode(
            "com.yujian.travel", "DEBUG", 7)).thenReturn(false);
        when(repository.findFirstByPlatformAndPackageNameAndChannelOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "DEBUG")).thenReturn(Optional.empty());
        when(repository.save(any(AppReleaseEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        AppReleaseService service = service(repository, inspector, properties);

        AppReleaseModels.ReleaseView uploaded = service.upload(apk(), "DEBUG");

        // 正式通道在没有证书白名单时会直接拒绝，调试通道必须放行 debuggable 包。
        assertThat(uploaded.channel()).isEqualTo("DEBUG");
        verify(inspector).inspect(any(), eq(true));
    }

    @Test
    void aLegacyCheckWithoutChannelFallsBackToTheDebugChannel() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity debugRelease = published(20, 1, "OPTIONAL");
        debugRelease.setChannel("DEBUG");
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(Optional.empty());
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "DEBUG", "PUBLISHED")).thenReturn(Optional.of(debugRelease));
        AppReleaseService service =
            service(repository, mock(AppReleasePackageInspector.class), properties);

        AppReleaseModels.CheckResult result = service.check("com.yujian.travel", 4, null);

        // v0.4.0 及以前不带 channel：正式通道没有已发布版本时必须能回落到调试通道，
        // 否则已经装到手机上的那份 APK 永远看不到新版本，只能手动重装。
        assertThat(result.releaseAvailable()).isTrue();
        assertThat(result.latestVersionCode()).isEqualTo(20);
    }

    @Test
    void restoringADisabledVersionPutsItBackOnThePublicChannel() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(20, 1, "OPTIONAL");
        release.setStatus("DISABLED");
        when(repository.findById(release.getId())).thenReturn(Optional.of(release));
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(Optional.empty());
        when(repository.findByPlatformAndPackageNameAndChannelAndStatus(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED")).thenReturn(List.of());
        when(repository.save(any(AppReleaseEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));
        AppReleaseService service =
            service(repository, mock(AppReleasePackageInspector.class), properties);

        AppReleaseModels.ReleaseView restored = service.restore(release.getId());

        assertThat(restored.status()).isEqualTo("PUBLISHED");
    }

    @Test
    void restoringAVersionOlderThanThePublicOneIsRejected() {
        AppProperties properties = properties();
        AppReleaseRepository repository = mock(AppReleaseRepository.class);
        AppReleaseEntity release = published(20, 1, "OPTIONAL");
        release.setStatus("DISABLED");
        when(repository.findById(release.getId())).thenReturn(Optional.of(release));
        when(repository.findFirstByPlatformAndPackageNameAndChannelAndStatusOrderByVersionCodeDesc(
            "ANDROID", "com.yujian.travel", "RELEASE", "PUBLISHED"))
            .thenReturn(Optional.of(published(30, 1, "OPTIONAL")));
        AppReleaseService service =
            service(repository, mock(AppReleasePackageInspector.class), properties);

        // 往回恢复等于把客户端推回老包，必须拦住并说清原因。
        assertThatThrownBy(() -> service.restore(release.getId()))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("已有更高的公开版本");
    }

    private AppReleaseService service(AppReleaseRepository repository,
                                      AppReleasePackageInspector inspector,
                                      AppProperties properties) {
        AppReleaseService service = new AppReleaseService(
            repository, inspector, properties, mock(MessageCenterService.class));
        service.initialize();
        return service;
    }

    private AppProperties properties() {
        AppProperties properties = new AppProperties();
        properties.getAppRelease().setStorageDir(tempDir.toString());
        properties.getAppRelease().setExpectedPackageName("com.yujian.travel");
        properties.getAppRelease().setAllowedCertificateSha256(List.of());
        return properties;
    }

    private MockMultipartFile apk() {
        return new MockMultipartFile(
            "file", "app-release.apk", "application/vnd.android.package-archive", new byte[] {1, 2, 3});
    }

    private AppReleasePackageInspector.InspectedPackage inspected(String certificate) {
        return new AppReleasePackageInspector.InspectedPackage(
            "com.yujian.travel", 20, "0.2.0", 29, 35, certificate, "filehash");
    }

    private AppReleaseEntity published(long versionCode, long minimumVersion, String mode) {
        AppReleaseEntity release = new AppReleaseEntity();
        release.setId(UUID.randomUUID());
        release.setPlatform("ANDROID");
        release.setChannel("RELEASE");
        release.setPackageName("com.yujian.travel");
        release.setVersionCode(versionCode);
        release.setVersionName("0.2.0");
        release.setReleaseTitle("可信更新");
        release.setReleaseNotes("修复版本兼容问题");
        release.setMinimumSupportedVersionCode(minimumVersion);
        release.setUpdateMode(mode);
        release.setStatus("PUBLISHED");
        release.setStorageKey("release.apk");
        release.setOriginalFileName("release.apk");
        release.setFileSize(1024);
        release.setFileSha256("filehash");
        release.setSigningCertificateSha256("certificate");
        release.setPublishedAt(Instant.parse("2026-10-03T02:00:00Z"));
        return release;
    }
}
