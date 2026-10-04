package com.yujian.travel.api;

import com.yujian.travel.service.ContentLibraryService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/** 主题路线（示范走廊）管理。 /api/home 的精选路线直接读这张表。 */
@RestController
@RequestMapping("/api/admin/theme-routes")
public class AdminThemeRouteController {
    private final ContentLibraryService contentLibrary;
    private final OperationLogService operationLog;

    public AdminThemeRouteController(ContentLibraryService contentLibrary,
                                     OperationLogService operationLog) {
        this.contentLibrary = contentLibrary;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<ContentModels.ThemeRouteView> list() {
        return contentLibrary.adminThemeRoutes();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public ContentModels.ThemeRouteView create(@Valid @RequestBody ContentModels.ThemeRouteInput input) {
        ContentModels.ThemeRouteView created = contentLibrary.createThemeRoute(input);
        operationLog.record("THEME_ROUTE_CREATE", "theme-route:" + created.id(), created.title());
        return created;
    }

    @PutMapping("/{id}")
    public ContentModels.ThemeRouteView update(@PathVariable String id,
                                               @Valid @RequestBody ContentModels.ThemeRouteInput input) {
        ContentModels.ThemeRouteView updated = contentLibrary.updateThemeRoute(id, input);
        operationLog.record("THEME_ROUTE_UPDATE", "theme-route:" + id, updated.title());
        return updated;
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable String id) {
        contentLibrary.deleteThemeRoute(id);
        operationLog.record("THEME_ROUTE_DELETE", "theme-route:" + id, null);
    }
}
