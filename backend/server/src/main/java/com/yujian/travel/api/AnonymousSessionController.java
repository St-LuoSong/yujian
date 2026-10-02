package com.yujian.travel.api;

import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.service.AnonymousSessionService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/anonymous")
public class AnonymousSessionController {
    private final AnonymousSessionService anonymousSessionService;

    public AnonymousSessionController(AnonymousSessionService anonymousSessionService) {
        this.anonymousSessionService = anonymousSessionService;
    }

    @PostMapping("/session")
    @ResponseStatus(HttpStatus.CREATED)
    public AnonymousModels.SessionResponse create(
        @RequestHeader(value = "X-Device-Fingerprint", required = false) String deviceFingerprint) {
        return anonymousSessionService.createSession(deviceFingerprint);
    }

    @GetMapping("/session")
    public AnonymousModels.SessionStatus status() {
        var anonymous = CurrentUser.anonymousOrNull();
        if (anonymous == null) {
            throw new com.yujian.travel.common.ApiException(org.springframework.http.HttpStatus.UNAUTHORIZED,
                "ANONYMOUS_SESSION_REQUIRED", "请先创建匿名体验会话");
        }
        return anonymousSessionService.status(anonymous.sessionId());
    }
}
