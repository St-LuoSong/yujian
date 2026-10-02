package com.yujian.travel.service;

import com.yujian.travel.api.AnonymousModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.security.AnonymousPrincipal;
import com.yujian.travel.security.AuthUser;
import com.yujian.travel.security.CurrentUser;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

@Service
public class OwnerResolver {
    private final AnonymousSessionService anonymousSessionService;

    public OwnerResolver(AnonymousSessionService anonymousSessionService) {
        this.anonymousSessionService = anonymousSessionService;
    }

    public OwnerContext resolveOrCreate(String deviceFingerprint) {
        AuthUser user = CurrentUser.userOrNull();
        if (user != null) {
            return new OwnerContext(user.id(), null, null);
        }
        AnonymousPrincipal anonymous = CurrentUser.anonymousOrNull();
        if (anonymous != null) {
            return new OwnerContext(null, anonymous.sessionId(), null);
        }
        AnonymousModels.SessionResponse session = anonymousSessionService.createSession(deviceFingerprint);
        return new OwnerContext(null, session.sessionId(), session.token());
    }

    public OwnerContext requireOwner() {
        AuthUser user = CurrentUser.userOrNull();
        if (user != null) {
            return new OwnerContext(user.id(), null, null);
        }
        AnonymousPrincipal anonymous = CurrentUser.anonymousOrNull();
        if (anonymous != null) {
            return new OwnerContext(null, anonymous.sessionId(), null);
        }
        throw new ApiException(HttpStatus.UNAUTHORIZED, "AUTH_REQUIRED", "请先登录或创建匿名体验会话");
    }

    public boolean isUser(OwnerContext owner) {
        return owner.userId() != null;
    }
}
