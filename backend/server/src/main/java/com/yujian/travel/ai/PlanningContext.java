package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.tools.ToolCollection;

public record PlanningContext(TravelModels.PlanRequest request, ToolCollection tools, String promptVersion) {
}
