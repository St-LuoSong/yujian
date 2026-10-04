package com.yujian.travel.api;

import com.yujian.travel.service.OperationLogService;
import com.yujian.travel.service.PoiContentService;
import com.yujian.travel.service.PoiGeocodeService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 景点内容管理。仅 ADMIN 可访问（/api/admin/** 在 SecurityConfig 中统一收口）。
 * 所有写操作都会落一条操作日志，交付时可以直接展示"谁在什么时候改了什么"。
 */
@RestController
@RequestMapping("/api/admin/pois")
public class AdminPoiController {
    private final PoiContentService contentService;
    private final OperationLogService operationLog;
    private final PoiGeocodeService geocodeService;

    public AdminPoiController(PoiContentService contentService,
                              OperationLogService operationLog,
                              PoiGeocodeService geocodeService) {
        this.contentService = contentService;
        this.operationLog = operationLog;
        this.geocodeService = geocodeService;
    }

    @GetMapping
    public List<PoiModels.PoiView> list(@RequestParam(required = false) String keyword) {
        return contentService.adminList(keyword);
    }

    @GetMapping("/{id}")
    public PoiModels.PoiView get(@PathVariable String id) {
        return contentService.adminGet(id);
    }

    /**
     * 把景点名解析成候选坐标。只回参考值、不落库，保存仍走 PUT/POST。
     *
     * 放在 /api/admin/** 之下：解析会消耗百度地图配额，因此必须是运营人员
     * 登录后才能调用，不能暴露给游客端。
     */
    @PostMapping("/geocode")
    public PoiModels.GeocodePreview geocode(@Valid @RequestBody PoiModels.GeocodeRequest request) {
        return geocodeService.preview(request.name(), request.city());
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PoiModels.PoiView create(@Valid @RequestBody PoiModels.PoiInput input) {
        PoiModels.PoiView created = contentService.create(input);
        operationLog.record("POI_CREATE", "poi:" + created.id(), created.name());
        return created;
    }

    @PutMapping("/{id}")
    public PoiModels.PoiView update(@PathVariable String id, @Valid @RequestBody PoiModels.PoiInput input) {
        PoiModels.PoiView updated = contentService.update(id, input);
        operationLog.record("POI_UPDATE", "poi:" + id, updated.name());
        return updated;
    }

    @PatchMapping("/{id}/publish")
    public PoiModels.PoiView publish(@PathVariable String id, @RequestBody PoiModels.PublishInput input) {
        PoiModels.PoiView updated = contentService.setPublished(id, input.published());
        operationLog.record(updated.published() ? "POI_PUBLISH" : "POI_UNPUBLISH", "poi:" + id, updated.name());
        return updated;
    }

    /** 首页推荐位开关与排序。和整份编辑分开，勾一下就能上/下首页。 */
    @PatchMapping("/{id}/featured")
    public PoiModels.PoiView featured(@PathVariable String id,
                                      @RequestBody PoiModels.FeaturedInput input) {
        PoiModels.PoiView updated = contentService.setFeatured(id, input);
        operationLog.record(updated.homeFeatured() ? "POI_FEATURE" : "POI_UNFEATURE",
            "poi:" + id, updated.name());
        return updated;
    }

    // ---------- 景区图集 ----------

    @GetMapping("/{id}/media")
    public List<PoiModels.MediaView> media(@PathVariable String id) {
        return contentService.listMedia(id);
    }

    @PostMapping("/{id}/media")
    @ResponseStatus(HttpStatus.CREATED)
    public PoiModels.MediaView addMedia(@PathVariable String id,
                                        @Valid @RequestBody PoiModels.MediaInput input) {
        PoiModels.MediaView created = contentService.addMedia(id, input);
        operationLog.record("POI_MEDIA_ADD", "poi:" + id + ":media:" + created.id(), created.imageUrl());
        return created;
    }

    @PutMapping("/{id}/media/{mediaId}")
    public PoiModels.MediaView updateMedia(@PathVariable String id,
                                           @PathVariable Long mediaId,
                                           @Valid @RequestBody PoiModels.MediaInput input) {
        PoiModels.MediaView updated = contentService.updateMedia(id, mediaId, input);
        operationLog.record("POI_MEDIA_UPDATE", "poi:" + id + ":media:" + mediaId, updated.imageUrl());
        return updated;
    }

    @DeleteMapping("/{id}/media/{mediaId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void deleteMedia(@PathVariable String id, @PathVariable Long mediaId) {
        contentService.deleteMedia(id, mediaId);
        operationLog.record("POI_MEDIA_DELETE", "poi:" + id + ":media:" + mediaId, null);
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        PoiModels.PoiView existing = contentService.adminGet(id);
        contentService.delete(id);
        operationLog.record("POI_DELETE", "poi:" + id, existing.name());
    }
}
