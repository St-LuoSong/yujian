package com.yujian.travel.ai;

import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Comparator;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * Per vendor attempt record.
 *
 * The admin console reads this to answer "which vendor served the last plan"
 * and "why did we switch". Nothing here is exposed on the traveller facing API,
 * and no API key or prompt content is ever recorded.
 */
@Component
public class ProviderHealth {
    private static final int MAX_REASON_LENGTH = 200;

    private final Map<String, Attempts> attempts = new ConcurrentHashMap<>();

    public void success(String engineId, long durationMs) {
        attempts.computeIfAbsent(engineId, Attempts::new).success(durationMs);
    }

    public void failure(String engineId, long durationMs, String reason) {
        attempts.computeIfAbsent(engineId, Attempts::new).failure(durationMs, reason);
    }

    /** Engine id of the most recent successful attempt, or null when none ran. */
    public String lastSuccessfulEngine() {
        return attempts.values().stream()
            .filter(Attempts::hasSucceeded)
            .max(Comparator.comparing(Attempts::lastSuccessAt))
            .map(Attempts::engineId)
            .orElse(null);
    }

    public List<Snapshot> snapshots() {
        return attempts.values().stream()
            .map(Attempts::snapshot)
            .sorted(Comparator.comparing(Snapshot::engine))
            .toList();
    }

    public record Snapshot(String engine, long successCount, long failureCount, long lastDurationMs,
                           String lastStatus, String lastError, Instant lastChangedAt) {
    }

    private static final class Attempts {
        private final String engineId;
        private long successCount;
        private long failureCount;
        private long lastDurationMs;
        private String lastStatus = "idle";
        private String lastError;
        private Instant lastChangedAt = Instant.now();
        private Instant lastSuccessAt;

        private Attempts(String engineId) {
            this.engineId = engineId;
        }

        private String engineId() {
            return engineId;
        }

        private synchronized void success(long durationMs) {
            successCount++;
            lastDurationMs = durationMs;
            lastStatus = "success";
            lastError = null;
            lastSuccessAt = Instant.now();
            lastChangedAt = lastSuccessAt;
        }

        private synchronized void failure(long durationMs, String reason) {
            failureCount++;
            lastDurationMs = durationMs;
            lastStatus = "failure";
            lastError = truncate(reason);
            lastChangedAt = Instant.now();
        }

        private synchronized boolean hasSucceeded() {
            return lastSuccessAt != null;
        }

        private synchronized Instant lastSuccessAt() {
            return lastSuccessAt;
        }

        private synchronized Snapshot snapshot() {
            return new Snapshot(engineId, successCount, failureCount, lastDurationMs, lastStatus,
                lastError, lastChangedAt);
        }

        private static String truncate(String reason) {
            if (reason == null) {
                return null;
            }
            return reason.length() <= MAX_REASON_LENGTH ? reason : reason.substring(0, MAX_REASON_LENGTH);
        }
    }
}
