package com.yujian.travel.service;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.UUID;

@Service
public class AccountMergeService {
    private final AnonymousSessionService anonymousSessionService;
    private final TripPlanService tripPlanService;

    public AccountMergeService(AnonymousSessionService anonymousSessionService, TripPlanService tripPlanService) {
        this.anonymousSessionService = anonymousSessionService;
        this.tripPlanService = tripPlanService;
    }

    @Transactional
    public void merge(UUID anonymousSessionId, UUID userId) {
        tripPlanService.transferAnonymousPlans(anonymousSessionId, userId);
        anonymousSessionService.convertToUser(anonymousSessionId, userId);
    }
}
