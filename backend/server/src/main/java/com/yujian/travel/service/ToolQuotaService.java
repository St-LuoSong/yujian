package com.yujian.travel.service;

import com.yujian.travel.repository.ToolInvocationLogRepository;
import com.yujian.travel.security.SecuritySettings;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.util.Locale;
import java.util.Optional;

/**
 * 外部工具调用的每日配额。
 *
 * 不新开计数表：`tool_invocation_log` 本来就逐次记录了每次调用，直接拿它当计数器，
 * 服务重启、实例重启都不会把额度清零 —— 这是"用一个假计数器"最容易出问题的地方。
 *
 * 只在外部工具上生效。景点检索、开放时间、门票价格读的是我们自己的内容库，
 * 既没有第三方额度可烧，也快，没有限制的必要。
 */
@Service
public class ToolQuotaService {
    /**
     * 自然日的边界时区。
     *
     * 必须与 JDBC 的 serverTimezone、以及运营台展示"今日用量"的口径一致，
     * 否则会出现"运营台说还剩 3 次、实际已经用不了"这种对不上的情况。
     */
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Shanghai");

    private final AppSettingService settings;
    private final ToolInvocationLogRepository logs;

    public ToolQuotaService(AppSettingService settings, ToolInvocationLogRepository logs) {
        this.settings = settings;
        this.logs = logs;
    }

    public record Decision(boolean allowed, String group, String label, long limit, long used,
                           String reason) {
        static Decision unrestricted() {
            return new Decision(true, "local", "本地资料", 0, 0, "");
        }
    }

    /** 这个工具属于哪个配额组。本地工具返回空，表示不消耗外部额度。 */
    public Optional<SecuritySettings.QuotaGroup> groupFor(String toolName) {
        String base = baseName(toolName);
        return SecuritySettings.QUOTA_GROUPS.stream()
            .filter(group -> group.toolNames().contains(base)
                || (group.toolPrefix() != null && base.startsWith(group.toolPrefix())))
            .findFirst();
    }

    @Transactional(readOnly = true)
    public Decision check(String toolName) {
        Optional<SecuritySettings.QuotaGroup> found = groupFor(toolName);
        if (found.isEmpty()) {
            return Decision.unrestricted();
        }
        SecuritySettings.QuotaGroup group = found.get();
        long limit = Math.max(1, settings.longValue(group.key()));
        if (!settings.enabled(SecuritySettings.QUOTA_ENABLED)) {
            return new Decision(true, group.name(), group.label(), limit, 0, "");
        }
        long used = todayUsage(group);
        if (used < limit) {
            return new Decision(true, group.name(), group.label(), limit, used, "");
        }
        return new Decision(false, group.name(), group.label(), limit, used,
            "今日「" + group.label() + "」的调用额度已用完（上限 " + limit + " 次），本次未调用外部接口。");
    }

    @Transactional(readOnly = true)
    public long todayUsage(SecuritySettings.QuotaGroup group) {
        Instant from = LocalDate.now(BUSINESS_ZONE).atStartOfDay(BUSINESS_ZONE).toInstant();
        if (group.toolPrefix() != null) {
            return logs.countByToolNamePrefixSince(group.toolPrefix(), from);
        }
        return logs.countByToolNamesSince(group.toolNames(), from);
    }

    /** "getWeather:第2天" → "getweather"。 */
    private static String baseName(String toolName) {
        String value = toolName == null ? "" : toolName;
        int cut = value.indexOf(':');
        return (cut < 0 ? value : value.substring(0, cut)).toLowerCase(Locale.ROOT);
    }
}
