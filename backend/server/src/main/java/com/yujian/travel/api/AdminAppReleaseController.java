package com.yujian.travel.api;

import com.yujian.travel.service.AppReleaseService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/admin/app-releases")
public class AdminAppReleaseController {
    private final AppReleaseService releases;
    private final OperationLogService operationLog;

    public AdminAppReleaseController(AppReleaseService releases, OperationLogService operationLog) {
        this.releases = releases;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<AppReleaseModels.ReleaseView> list() {
        return releases.list();
    }

    @PostMapping(consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public AppReleaseModels.ReleaseView upload(
        @RequestPart("file") MultipartFile file,
        // RELEASE 为缺省值：只传文件的旧管理台调用行为保持不变。
        @RequestParam(required = false, defaultValue = "RELEASE") String channel) {
        AppReleaseModels.ReleaseView uploaded = releases.upload(file, channel);
        operationLog.record("APP_RELEASE_UPLOAD", uploaded.id().toString(),
            uploaded.channel() + " · " + uploaded.packageName() + " " + uploaded.versionName()
                + " (" + uploaded.versionCode() + ")");
        return uploaded;
    }

    @PostMapping("/{id}/publish")
    public AppReleaseModels.ReleaseView publish(@PathVariable UUID id,
                                                @Valid @RequestBody AppReleaseModels.PublishRequest request) {
        AppReleaseModels.ReleaseView published = releases.publish(id, request);
        operationLog.record("APP_RELEASE_PUBLISH", id.toString(),
            published.versionName() + " · " + published.updateMode());
        return published;
    }

    @PatchMapping("/{id}/disable")
    public AppReleaseModels.ReleaseView disable(@PathVariable UUID id) {
        AppReleaseModels.ReleaseView disabled = releases.disable(id);
        operationLog.record("APP_RELEASE_DISABLE", id.toString(), disabled.versionName());
        return disabled;
    }

    /** 把停用/被替代的版本重新放回公开通道（只能往上恢复）。 */
    @PatchMapping("/{id}/restore")
    public AppReleaseModels.ReleaseView restore(@PathVariable UUID id) {
        AppReleaseModels.ReleaseView restored = releases.restore(id);
        operationLog.record("APP_RELEASE_RESTORE", id.toString(),
            restored.channel() + " · " + restored.versionName());
        return restored;
    }
}
