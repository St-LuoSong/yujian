package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.tools.ToolCollection;

public record PlanningOutcome(TravelModels.TripPlan plan, String engine, String promptVersion,
                              ToolCollection tools, ValidationReport validation, boolean fallback) {
}
