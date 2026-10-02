package com.yujian.travel.service;

import com.yujian.travel.api.AnonymousModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.AnonymousSession;
import com.yujian.travel.repository.AnonymousSessionRepository;
import com.yujian.travel.security.TokenHash;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.UUID;

@Service
public class AnonymousSessionService {
    private final AnonymousSessionRepository repository;
    private final AppProperties properties;

    public AnonymousSessionService(AnonymousSessionRepository repository, AppProperties properties) {
        this.repository = repository;
        this.properties = properties;
    }

    @Transactional
    public AnonymousModels.SessionResponse createSession(String deviceFingerprint) {
        String rawToken = TokenHash.randomToken();
        AnonymousSession session = new AnonymousSession();
        session.setTokenHash(TokenHash.sha256Hex(rawToken));
        session.setDeviceFingerprintHash(deviceFingerprint == null || deviceFingerprint.isBlank()
            ? null : TokenHash.sha256Hex(deviceFingerprint));
        session.setPlanningCount(0);
        session.setExpiresAt(Instant.now().plus(30, ChronoUnit.DAYS));
        session = repository.save(session);
        return new AnonymousModels.SessionResponse(session.getId(), rawToken, session.getExpiresAt(),
            properties.getTrialLimit());
    }

    @Transactional
    public AnonymousModels.SessionStatus status(UUID sessionId) {
        AnonymousSession session = requireSession(sessionId);
        return new AnonymousModels.SessionStatus(session.getId(), session.getPlanningCount(),
            properties.getTrialLimit(), session.getExpiresAt());
    }

    @Transactional
    public void reservePlanning(UUID sessionId) {
        AnonymousSession session = requireSession(sessionId);
        if (session.getPlanningCount() >= properties.getTrialLimit()) {
            throw new ApiException(HttpStatus.TOO_MANY_REQUESTS, "TRIAL_LIMIT_REACHED",
                "当前体验额度已用完，登录后可继续保存和管理行程");
        }
        session.setPlanningCount(session.getPlanningCount() + 1);
        session.setLastSeenAt(Instant.now());
    }

    @Transactional(readOnly = true)
    public UUID requireSessionIdByToken(String rawToken) {
        if (rawToken == null || rawToken.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "ANONYMOUS_SESSION_REQUIRED",
                "当前请求没有可合并的匿名体验会话");
        }
        return repository.findByTokenHash(TokenHash.sha256Hex(rawToken))
            .filter(session -> session.getExpiresAt().isAfter(Instant.now()))
            .filter(session -> session.getConvertedUserId() == null)
            .map(AnonymousSession::getId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "ANONYMOUS_SESSION_INVALID",
                "匿名体验会话已失效，无法合并"));
    }

    @Transactional
    public void convertToUser(UUID sessionId, UUID userId) {
        AnonymousSession session = requireSession(sessionId);
        session.setConvertedUserId(userId);
        session.setLastSeenAt(Instant.now());
    }

    private AnonymousSession requireSession(UUID sessionId) {
        AnonymousSession session = repository.findById(sessionId)
            .orElseThrow(() -> new ApiException(HttpStatus.UNAUTHORIZED, "ANONYMOUS_SESSION_INVALID",
                "匿名体验会话已失效，请重新开始"));
        if (session.getExpiresAt().isBefore(Instant.now())) {
            throw new ApiException(HttpStatus.UNAUTHORIZED, "ANONYMOUS_SESSION_EXPIRED",
                "匿名体验会话已过期，请重新开始");
        }
        return session;
    }
}
