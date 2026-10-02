package com.yujian.travel.api;

import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.MediaStorageService;
import com.yujian.travel.service.OperationLogService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 用户旅记图片上传。
 *
 * 与运营台图片上传分开：这里走严格重编码流程，主动去掉 EXIF，且只接受 JPEG/PNG。
 */
@RestController
@RequestMapping("/api/community/media")
public class CommunityMediaController {
    private final MediaStorageService mediaStorageService;
    private final OperationLogService operationLog;

    public CommunityMediaController(MediaStorageService mediaStorageService,
                                    OperationLogService operationLog) {
        this.mediaStorageService = mediaStorageService;
        this.operationLog = operationLog;
    }

    @PostMapping(value = "/images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public MediaModels.ImageUploadResult upload(
        @RequestParam("file") MultipartFile file,
        HttpServletRequest request) {
        CurrentUser.requireUser();
        MediaStorageService.StoredImage stored = mediaStorageService.storeCommunityImage(file);
        operationLog.record("COMMUNITY_IMAGE_UPLOAD", stored.fileName(),
            "上传社区旅记图片：" + stored.sizeBytes() + " bytes");
        return new MediaModels.ImageUploadResult(
            stored.fileName(),
            mediaStorageService.publicUrl(stored.fileName(), request),
            stored.relativeUrl(),
            stored.format(),
            stored.sizeBytes(),
            stored.width(),
            stored.height());
    }
}
