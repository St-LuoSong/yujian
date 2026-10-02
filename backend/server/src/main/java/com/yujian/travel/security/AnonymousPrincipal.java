package com.yujian.travel.security;

import java.util.UUID;

public record AnonymousPrincipal(UUID sessionId) {
}
