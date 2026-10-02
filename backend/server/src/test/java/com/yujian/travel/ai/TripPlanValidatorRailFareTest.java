package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.tools.ToolCollection;
import com.yujian.travel.tools.ToolModels;
import com.yujian.travel.tools.ToolResult;
import org.junit.jupiter.api.Test;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import static org.assertj.core.api.Assertions.assertThat;

class TripPlanValidatorRailFareTest {
    private final TripPlanValidator validator = new TripPlanValidator();

    @Test
    void warnsWhenPlanTotalIsBelowKnownRoundTripRailFloor() {
        ValidationReport report = validator.validate(plan(100), request(), tools());

        assertThat(report.warnings())
            .anyMatch(message -> message.contains("跨城交通预算可能不完整"));
    }

    @Test
    void doesNotWarnWhenPlanAlreadyCoversRailFloor() {
        ValidationReport report = validator.validate(plan(300), request(), tools());

        assertThat(report.warnings())
            .noneMatch(message -> message.contains("跨城交通预算可能不完整"));
    }

    private TravelModels.PlanRequest request() {
        return new TravelModels.PlanRequest("郑州到洛阳两日游", "2026-10-03", "郑州", "洛阳",
            2, 2, 1000, "历史文化", "轻松", "高铁");
    }

    private TravelModels.TripPlan plan(int totalCost) {
        TravelModels.TripItem item = new TravelModels.TripItem("交通", "郑州东→洛阳龙门", "08:20",
            "约36分钟", "高铁", "12306 票价参考", totalCost, "12306", "实时数据", "");
        return new TravelModels.TripPlan("trip-1", "洛阳两日游", "测试方案", "郑州—洛阳",
            "轻松", totalCost, totalCost / 2,
            List.of(
                new TravelModels.TripDay("DAY 01", "2026-10-03", List.of(item)),
                new TravelModels.TripDay("DAY 02", "2026-10-04", List.of())),
            List.of(), "AI 生成");
    }

    private ToolCollection tools() {
        ToolModels.RailFare fare = new ToolModels.RailFare("G1903", "郑州东", "洛阳龙门",
            "08:20", "08:56", "36分钟", "高铁", Map.of("二等座", 65, "一等座", 104));
        ToolResult<List<ToolModels.RailFare>> result = ToolResult.realtime(List.of(fare),
            "12306 MCP 官方票价", Instant.now().plusSeconds(600));
        return new ToolCollection(UUID.randomUUID(), Map.of("quoteRailFares", result),
            Map.of(), List.of(), 0);
    }
}
