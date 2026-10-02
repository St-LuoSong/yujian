package com.yujian.travel.api;

import com.yujian.travel.service.MediaStorageService;
import com.yujian.travel.service.OperationLogService;
import jakarta.servlet.http.HttpServletRequest;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestPart;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

/**
 * 运营台图片上传。位于 /api/admin/** 之下，因此只有 ADMIN 角色能写入；
 * 上传后的文件通过公开只读的 /media/** 提供。
 */
@RestController
@RequestMapping("/api/admin/media")
public class AdminMediaController {
    private final MediaStorageService mediaStorageService;
    private final OperationLogService operationLog;

    public AdminMediaController(MediaStorageService mediaStorageService, OperationLogService operationLog) {
        this.mediaStorageService = mediaStorageService;
        this.operationLog = operationLog;
    }

    @PostMapping(value = "/images", consumes = MediaType.MULTIPART_FORM_DATA_VALUE)
    @ResponseStatus(HttpStatus.CREATED)
    public MediaModels.ImageUploadResult upload(@RequestPart("file") MultipartFile file,
                                                HttpServletRequest request) {
        MediaStorageService.StoredImage stored = mediaStorageService.store(file);
        String url = mediaStorageService.publicUrl(stored.fileName(), request);
        // 日志只记录尺寸与体积，不记录原始文件名（可能包含个人信息）。
        operationLog.record("MEDIA_UPLOAD", "media:" + stored.fileName(),
            stored.width() + "x" + stored.height() + " · " + humanSize(stored.sizeBytes()));
        return new MediaModels.ImageUploadResult(stored.fileName(), url, stored.relativeUrl(),
            stored.format(), stored.sizeBytes(), stored.width(), stored.height());
    }

    private static String humanSize(long bytes) {
        if (bytes >= 1024 * 1024) {
            return String.format("%.1fMB", bytes / 1024d / 1024d);
        }
        return Math.max(1, bytes / 1024) + "KB";
    }
}
