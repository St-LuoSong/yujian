package com.yujian.travel.api;

import com.yujian.travel.security.RateLimitService;
import com.yujian.travel.security.SecuritySettings;
import com.yujian.travel.service.AppSettingService;
import com.yujian.travel.service.OperationLogService;
import com.yujian.travel.service.ToolQuotaService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

/**
 * 限流与工具配额的运营开关。
 *
 * 之所以做成运营可调而不是写死在配置文件里：外部接口的额度是会被用光的，
 * 而"什么时候该收紧"是运营看着用量决定的事，不该每次都要改环境变量重启服务。
 */
@RestController
@RequestMapping("/api/admin/security")
public class AdminSecurityController {
    private final AppSettingService settings;
    private final ToolQuotaService quotaService;
    private final RateLimitService rateLimitService;
    private final OperationLogService operationLog;

    public AdminSecurityController(AppSettingService settings, ToolQuotaService quotaService,
                                   RateLimitService rateLimitService,
                                   OperationLogService operationLog) {
        this.settings = settings;
        this.quotaService = quotaService;
        this.rateLimitService = rateLimitService;
        this.operationLog = operationLog;
    }

    @GetMapping("/limits")
    public SecurityModels.LimitsView limits() {
        return view();
    }

    @PutMapping("/limits")
    public SecurityModels.LimitsView update(
        @RequestBody SecurityModels.UpdateLimitsRequest request) {
        Map<String, Long> values = request == null ? null : request.values();
        if (values == null || values.isEmpty()) {
            return view();
        }
        settings.update(values);
        operationLog.record("SECURITY_LIMITS_UPDATE", String.valueOf(values.size()),
            "调整限流/配额：" + String.join("、", values.keySet()));
        return view();
    }

    @PatchMapping("/limits/reset")
    public SecurityModels.LimitsView reset() {
        settings.resetToDefaults();
        operationLog.record("SECURITY_LIMITS_RESET", "all", "恢复默认限流与配额");
        return view();
    }

    private SecurityModels.LimitsView view() {
        Map<String, Long> values = settings.values();
        List<SecurityModels.SettingItem> items = new ArrayList<>();
        for (SecuritySettings.Definition definition : SecuritySettings.definitions()) {
            items.add(new SecurityModels.SettingItem(
                definition.key(),
                definition.group(),
                definition.label(),
                values.getOrDefault(definition.key(), definition.defaultValue()),
                definition.defaultValue(),
                definition.min(),
                definition.max(),
                definition.unit(),
                definition.description()));
        }
        List<SecurityModels.QuotaUsage> quotas = new ArrayList<>();
        for (SecuritySettings.QuotaGroup group : SecuritySettings.QUOTA_GROUPS) {
            quotas.add(new SecurityModels.QuotaUsage(
                group.name(),
                group.label(),
                values.getOrDefault(group.key(), group.defaultValue()),
                quotaService.todayUsage(group)));
        }
        return new SecurityModels.LimitsView(items, quotas, rateLimitService.activeWindowCount());
    }
}
