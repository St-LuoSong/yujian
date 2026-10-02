package com.yujian.travel.api;

import com.yujian.travel.service.AdminToolHealthService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 外部数据源健康度。与 {@link AdminStatsController} 的区别：
 * 统计看"用了多少"，这里看"接上没有"。
 */
@RestController
@RequestMapping("/api/admin/tools")
public class AdminToolsController {
    private final AdminToolHealthService toolHealthService;

    public AdminToolsController(AdminToolHealthService toolHealthService) {
        this.toolHealthService = toolHealthService;
    }

    @GetMapping("/health")
    public AdminToolHealthService.HealthView health() {
        return toolHealthService.health();
    }
}

