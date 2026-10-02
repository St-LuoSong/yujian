package com.yujian.travel.tools;

import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 外部数据源健康度。
 *
 * 与 {@link ToolResult} 的分工：ToolResult 描述"这一条数据是什么状态"，
 * ToolHealth 描述"这条链路最近到底接上没有"。
 * 运营台靠它回答两个问题：现在哪些源是真实在跑的？哪些一直在降级？
 *
 * 只记录计数、最近状态与耗时，不记录调用参数，因此不会带出任何用户信息。
 */
@Component
public class ToolHealth {
    private final Map<String, Attempts> attempts = new ConcurrentHashMap<>();

    public void record(String toolName, ToolResult<?> result, long durationMs) {
        Attempts entry = attempts.computeIfAbsent(toolName, key -> new Attempts());
        entry.total.incrementAndGet();
        entry.lastAt = Instant.now();
        entry.lastDurationMs = durationMs;
        entry.lastStatus = result.dataStatus();
        entry.lastErrorCode = result.errorCode();
        if (result.errorCode() == null) {
            entry.success.incrementAndGet();
        } else {
            entry.failure.incrementAndGet();
        }
    }

    public List<Snapshot> snapshots() {
        return attempts.entrySet().stream()
            .map(entry -> entry.getValue().snapshot(entry.getKey()))
            .sorted(java.util.Comparator.comparing(Snapshot::tool))
            .toList();
    }

    private static final class Attempts {
        private final AtomicLong total = new AtomicLong();
        private final AtomicLong success = new AtomicLong();
        private final AtomicLong failure = new AtomicLong();
        private volatile Instant lastAt;
        private volatile String lastStatus;
        private volatile String lastErrorCode;
        private volatile long lastDurationMs;

        private Snapshot snapshot(String tool) {
            return new Snapshot(tool, total.get(), success.get(), failure.get(), lastStatus, lastErrorCode,
                lastDurationMs, lastAt);
        }
    }

    public record Snapshot(String tool, long total, long success, long failure, String lastStatus,
                           String lastErrorCode, long lastDurationMs, Instant lastAt) {
    }
}

