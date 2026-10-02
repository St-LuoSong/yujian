package com.yujian.travel.api;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

public final class TripPlanModels {
    private TripPlanModels() {
    }

    public record CreateRequest(
        @NotBlank(message = "请描述你的旅行需求") String prompt,
        /** 出发日期（yyyy-MM-dd）。空值按“明天”处理，绝不静默改成别的日期。 */
        String startDate,
        String origin, String destination, Integer days, Integer travelers,
        Integer budgetPerPerson, String interests, String pace, String transport) {
    }

    /**
     * 局部修改。{@code title} 的上限与 APK 的重命名输入框保持一致（40 字），
     * 免得超长标题在客户端能输入、在服务端才炸。
     */
    public record PatchRequest(
        @Size(max = 40, message = "行程名称最多 40 个字") String title,
        String summary, String intensity) {
    }

    public record AdjustRequest(@NotBlank(message = "请输入调整要求") String instruction) {
    }

    public record CreateResult(TravelModels.TripPlan plan, String anonymousToken) {
    }

    public record Summary(UUID id, String title, String summary, String corridor, String intensity,
                          int totalCost, int perPersonCost, int daysCount, String dataStatus, Instant updatedAt) {
    }

    /**
     * "你的足迹"统计。仅由真实落库的行程聚合而来，不做任何估算。
     *
     * {@code totalMeters} 只累计行程项里确实带距离的那些（路线工具返回时才写入），
     * 所以它是"已记录里程"而不是"实际走过的里程"——界面必须照这个口径措辞。
     */
    public record Footprint(List<CityVisit> cities, long totalMeters, int totalDays, int tripCount,
                            Instant generatedAt) {
    }

    /**
     * 一个到访城市。{@code firstVisitAt} / {@code lastVisitAt} 取该城市相关行程的
     * 创建时间与最后更新时间，用于"最近去过"的排序与展示。
     */
    public record CityVisit(String name, int tripCount, Instant firstVisitAt, Instant lastVisitAt) {
    }

    public record AdjustmentResult(TravelModels.TripPlan plan, List<String> changes, int version) {
    }

    public record TodayResponse(UUID tripId, String date, String nextStop, String arrival, String weather,
                                String status, List<TravelModels.TripItem> remainingItems) {
    }

    public record ShareRequest(Boolean hideBudget, Integer expireDays) {
    }

    public record ShareResult(UUID id, String token, String url, Instant expiresAt, boolean hideBudget) {
    }

    public record SharedTrip(TravelModels.TripPlan plan, boolean hideBudget) {
    }

    public record ToolTrace(String toolName, String source, String dataStatus, boolean success,
                            String outputSummary, String errorCode, Long durationMs, Instant createdAt) {
    }

    public record TraceResponse(UUID tripId, String engine, String promptVersion, String dataStatus,
                                int toolMockCount, List<String> warnings, List<ToolTrace> toolInvocations) {
    }
}
