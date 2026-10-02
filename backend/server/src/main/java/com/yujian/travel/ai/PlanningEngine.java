package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;

public interface PlanningEngine {
    String name();

    boolean available();

    TravelModels.TripPlan generate(PlanningContext context);
}
