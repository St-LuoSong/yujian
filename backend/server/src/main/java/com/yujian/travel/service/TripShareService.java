package com.yujian.travel.service;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.api.TripPlanModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.TripPlanEntity;
import com.yujian.travel.domain.TripShare;
import com.yujian.travel.repository.TripShareRepository;
import com.yujian.travel.security.CurrentUser;
import com.yujian.travel.security.TokenHash;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.UUID;

@Service
public class TripShareService {
    private final TripShareRepository shareRepository;
    private final TripPlanService tripPlanService;
    private final AppProperties properties;

    public TripShareService(TripShareRepository shareRepository, TripPlanService tripPlanService,
                            AppProperties properties) {
        this.shareRepository = shareRepository;
        this.tripPlanService = tripPlanService;
        this.properties = properties;
    }

    @Transactional
    public TripPlanModels.ShareResult create(UUID tripPlanId, TripPlanModels.ShareRequest request) {
        var user = CurrentUser.requireUser();
        OwnerContext owner = new OwnerContext(user.id(), null, null);
        TripPlanEntity plan = tripPlanService.requireOwned(tripPlanId, owner);
        String rawToken = TokenHash.randomToken();
        TripShare share = new TripShare();
        share.setTripPlan(plan);
        share.setTokenHash(TokenHash.sha256Hex(rawToken));
        share.setEnabled(true);
        share.setHideBudget(Boolean.TRUE.equals(request == null ? null : request.hideBudget()));
        int expireDays = request == null || request.expireDays() == null
            ? properties.getShare().getDefaultExpireDays() : Math.max(1, Math.min(30, request.expireDays()));
        share.setExpiresAt(Instant.now().plus(expireDays, ChronoUnit.DAYS));
        share = shareRepository.save(share);
        String url = properties.getShare().getBaseUrl() + "/" + rawToken;
        return new TripPlanModels.ShareResult(share.getId(), rawToken, url, share.getExpiresAt(), share.isHideBudget());
    }

    @Transactional
    public TripPlanModels.SharedTrip view(String rawToken) {
        TripShare share = shareRepository.findByTokenHashAndEnabledTrue(TokenHash.sha256Hex(rawToken))
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SHARE_NOT_FOUND", "分享链接不存在或已关闭"));
        if (share.getExpiresAt() != null && share.getExpiresAt().isBefore(Instant.now())) {
            throw new ApiException(HttpStatus.GONE, "SHARE_EXPIRED", "分享链接已过期");
        }
        share.setViewCount(share.getViewCount() + 1);
        TravelModels.TripPlan plan = tripPlanService.toDto(share.getTripPlan());
        return new TripPlanModels.SharedTrip(share.isHideBudget() ? maskBudget(plan) : plan, share.isHideBudget());
    }

    @Transactional
    public void revoke(UUID shareId) {
        var user = CurrentUser.requireUser();
        TripShare share = shareRepository.findByIdAndTripPlanOwnerId(shareId, user.id())
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "SHARE_NOT_FOUND", "分享链接不存在或无权操作"));
        share.setEnabled(false);
        share.setRevokedAt(Instant.now());
    }

    private TravelModels.TripPlan maskBudget(TravelModels.TripPlan plan) {
        List<TravelModels.TripDay> days = plan.days().stream()
            .map(day -> new TravelModels.TripDay(day.label(), day.date(), day.items().stream()
                .map(item -> new TravelModels.TripItem(item.type(), item.title(), item.time(), item.duration(),
                    item.transport(), item.description(), 0, item.source(), item.dataStatus(), item.risk()))
                .toList()))
            .toList();
        return new TravelModels.TripPlan(plan.id(), plan.title(), plan.summary() + "（预算已隐藏）",
            plan.corridor(), plan.intensity(), 0, 0, days, plan.warnings(), plan.dataStatus());
    }
}
