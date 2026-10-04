package com.yujian.travel.api;

import com.yujian.travel.service.ContentLibraryService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 应用视觉资源管理：首页横幅、个人页背景、行程默认封面、各处占位图。
 *
 * 只有平台控制的图在这里；用户头像与旅记配图走各自的审核链路，不经此处。
 */
@RestController
@RequestMapping("/api/admin/app-resources")
public class AdminAppResourceController {
    private final ContentLibraryService contentLibrary;
    private final OperationLogService operationLog;

    public AdminAppResourceController(ContentLibraryService contentLibrary,
                                      OperationLogService operationLog) {
        this.contentLibrary = contentLibrary;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<ContentModels.VisualResourceView> list() {
        return contentLibrary.adminVisualResources();
    }

    @PutMapping("/{slot}")
    public ContentModels.VisualResourceView save(@PathVariable String slot,
                                                 @Valid @RequestBody ContentModels.VisualResourceInput input) {
        ContentModels.VisualResourceView saved = contentLibrary.saveVisualResource(slot, input);
        operationLog.record("APP_RESOURCE_UPDATE", "app-resource:" + saved.slot(),
            saved.imageUrl() == null ? "清空" : saved.imageUrl());
        return saved;
    }
}
