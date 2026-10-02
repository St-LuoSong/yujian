package com.yujian.travel.api;

import com.yujian.travel.service.AdminStatsService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/admin/stats")
public class AdminStatsController {
    private final AdminStatsService statsService;

    public AdminStatsController(AdminStatsService statsService) {
        this.statsService = statsService;
    }

    @GetMapping("/overview")
    public AdminStatsService.OverviewView overview() {
        return statsService.overview();
    }
}
