package com.yujian.travel.api;

import java.time.Instant;
import java.util.UUID;

public final class AnonymousModels {
    private AnonymousModels() {
    }

    public record SessionResponse(UUID sessionId, String token, Instant expiresAt, int trialLimit) {
    }

    public record SessionStatus(UUID sessionId, int planningCount, int trialLimit, Instant expiresAt) {
    }
}
