package com.yujian.travel.api;

import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.AppReleaseService;
import org.springframework.http.CacheControl;
import org.springframework.http.ContentDisposition;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RestController;

import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.UUID;

@RestController
@RequestMapping("/api/app-releases")
public class AppReleaseController {
    private final AppReleaseService releases;

    public AppReleaseController(AppReleaseService releases) {
        this.releases = releases;
    }

    @GetMapping("/check")
    public ResponseEntity<AppReleaseModels.CheckResult> check(
        @RequestParam String packageName,
        @RequestParam long versionCode,
        // 不设默认值：null 表示"旧客户端，不知道通道"，与显式传 RELEASE 是两回事，
        // 服务端要按不同规则处理（见 AppReleaseService#check）。
        @RequestParam(required = false) String channel) {
        return ResponseEntity.ok()
            .cacheControl(CacheControl.maxAge(Duration.ofMinutes(10)).cachePrivate())
            .body(releases.check(packageName, Math.max(0, versionCode), channel));
    }

    @GetMapping("/{id}/download")
    public ResponseEntity<org.springframework.core.io.Resource> download(@PathVariable UUID id) {
        AppReleaseService.DownloadArtifact artifact = releases.download(id);
        return ResponseEntity.ok()
            .contentType(MediaType.parseMediaType("application/vnd.android.package-archive"))
            .contentLength(artifact.size())
            .header(HttpHeaders.CONTENT_DISPOSITION, ContentDisposition.attachment()
                .filename(artifact.fileName(), StandardCharsets.UTF_8).build().toString())
            .header("X-Checksum-SHA256", artifact.sha256())
            .cacheControl(CacheControl.maxAge(Duration.ofHours(1)).cachePublic())
            .body(artifact.resource());
    }

    /**
     * 装上某个版本之后的回执。
     *
     * 未登录时什么都不做并返回 204，而不是 401：这条请求是客户端启动时顺手发的，
     * 让游客在后台刷出一条红色的鉴权失败毫无意义。
     */
    @PostMapping("/ack")
    public ResponseEntity<Void> acknowledge(
        @RequestParam String packageName,
        @RequestParam long versionCode,
        @RequestParam(required = false, defaultValue = "RELEASE") String channel) {
        AuthUser user = CurrentUser.userOrNull();
        if (user != null) {
            releases.acknowledge(user.id(), packageName, Math.max(0, versionCode), channel);
        }
        return ResponseEntity.noContent().build();
    }
}
