package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.TripPlanFactory;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;

@Component
@Order(100)
public class MockPlanningEngine implements PlanningEngine {
    private final TripPlanFactory tripPlanFactory;

    public MockPlanningEngine(TripPlanFactory tripPlanFactory) {
        this.tripPlanFactory = tripPlanFactory;
    }

    @Override
    public String name() {
        return "mock-trip-factory";
    }

    @Override
    public boolean available() {
        return true;
    }

    @Override
    public TravelModels.TripPlan generate(PlanningContext context) {
        return tripPlanFactory.create(context.request());
    }
}
