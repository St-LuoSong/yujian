package com.yujian.travel.service;

import java.util.UUID;

public record OwnerContext(UUID userId, UUID anonymousSessionId, String newAnonymousToken) {
    public boolean isUser() {
        return userId != null;
    }

    public boolean isAnonymous() {
        return userId == null && anonymousSessionId != null;
    }
}
