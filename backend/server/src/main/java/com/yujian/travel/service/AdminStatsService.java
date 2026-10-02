package com.yujian.travel.service;

import com.yujian.travel.ai.LlmProvider;
import com.yujian.travel.ai.PlanningEngineRegistry;
import com.yujian.travel.ai.ProviderHealth;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.repository.FeedbackRepository;
import com.yujian.travel.repository.PoiRepository;
import com.yujian.travel.repository.ToolInvocationLogRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.TripShareRepository;
import com.yujian.travel.repository.UserAccountRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneId;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

/**
 * 运营统计。
 *
 * 只做聚合，不返回任何可识别个人的明细；所有数字都能在管理台追到时间范围和来源。
 * 数据量按比赛演示规模设计：近 7 天的时间戳在内存里分桶，避免为了一个折线图引入分析数据库。
 */
@Service
public class AdminStatsService {
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");
    private static final int TREND_DAYS = 7;

    private final UserAccountRepository userRepository;
    private final TripPlanRepository tripPlanRepository;
    private final TripShareRepository shareRepository;
    private final ToolInvocationLogRepository toolLogRepository;
    private final PoiRepository poiRepository;
    private final FeedbackRepository feedbackRepository;
    private final PlanningEngineRegistry registry;
    private final ProviderHealth providerHealth;
    private final AppProperties properties;

    public AdminStatsService(UserAccountRepository userRepository, TripPlanRepository tripPlanRepository,
                             TripShareRepository shareRepository, ToolInvocationLogRepository toolLogRepository,
                             PoiRepository poiRepository, FeedbackRepository feedbackRepository,
                             PlanningEngineRegistry registry, ProviderHealth providerHealth,
                             AppProperties properties) {
        this.userRepository = userRepository;
        this.tripPlanRepository = tripPlanRepository;
        this.shareRepository = shareRepository;
        this.toolLogRepository = toolLogRepository;
        this.poiRepository = poiRepository;
        this.feedbackRepository = feedbackRepository;
        this.registry = registry;
        this.providerHealth = providerHealth;
        this.properties = properties;
    }

    @Transactional(readOnly = true)
    public OverviewView overview() {
        Instant now = Instant.now();
        Instant from = now.minus(TREND_DAYS, ChronoUnit.DAYS);

        long userTotal = userRepository.count();
        long userVerified = userRepository.countByEmailVerifiedTrue();
        List<Instant> userCreated = userRepository.findCreatedAtFrom(from);

        long tripTotal = tripPlanRepository.count();
        long tripRegistered = tripPlanRepository.countByOwnerIsNotNull();
        long tripAnonymous = tripPlanRepository.countByAnonymousSessionIsNotNull();
        Double avgDays = tripPlanRepository.averageDaysCount();
        List<Instant> tripCreated = tripPlanRepository.findCreatedAtFrom(from);

        long toolTotal = toolLogRepository.count();
        long toolSucceeded = toolLogRepository.countBySuccessTrue();
        long toolFailed = toolLogRepository.countBySuccessFalse();
        long toolMock = toolLogRepository.countByDataStatusContaining("演示");
        long toolRealtime = toolLogRepository.countByDataStatusContaining("实时");
        long toolCached = toolLogRepository.countByDataStatusContaining("缓存");
        // 降级是演示数据的子集，单独统计才能说明"外部服务到底有没有接上"。
        long toolDegraded = toolLogRepository.countByDataStatusContainingAndErrorCodeIsNotNull("演示");
        List<Instant> toolCreated = toolLogRepository.findCreatedAtFrom(from);

        double successRate = toolTotal == 0 ? 0d : round1(toolSucceeded * 100d / toolTotal);

        UserStats users = new UserStats(userTotal, userVerified, userCreated.size());
        TripStats trips = new TripStats(tripTotal, tripRegistered, tripAnonymous, tripCreated.size(),
            avgDays == null ? 0d : round1(avgDays));
        ContentStats content = new ContentStats(poiRepository.countByPublishedTrue(), poiRepository.count(),
            feedbackRepository.countByStatus("OPEN"));
        ToolStats tools = new ToolStats(toolTotal, toolSucceeded, toolFailed, successRate, toolMock,
            toolRealtime, toolCached, toolDegraded);
        ShareStats shares = new ShareStats(shareRepository.count(),
            shareRepository.countByEnabledTrueAndExpiresAtAfter(now), shareRepository.totalViewCount());

        return new OverviewView(now, users, trips, content, tools, shares,
            daily(tripCreated, toolCreated, now), llm());
    }

    private LlmStats llm() {
        List<String> order = registry.activeProviders().stream().map(LlmProvider::id).toList();
        List<ProviderHealth.Snapshot> attempts = providerHealth.snapshots();
        Map<String, ProviderHealth.Snapshot> byId = attempts.stream()
            .collect(Collectors.toMap(ProviderHealth.Snapshot::engine, snapshot -> snapshot, (a, b) -> a));
        List<ProviderLine> lines = properties.getLlm().getProviders().entrySet().stream()
            .map(entry -> {
                LlmProvider provider = LlmProvider.resolve(entry.getKey(), entry.getValue(), properties.getLlm());
                ProviderHealth.Snapshot snapshot = byId.get(entry.getKey());
                return new ProviderLine(entry.getKey(), provider.displayName(), provider.model(), provider.priority(),
                    entry.getValue().isEnabled(), provider.configured(),
                    snapshot == null ? 0 : snapshot.successCount(),
                    snapshot == null ? 0 : snapshot.failureCount(),
                    snapshot == null ? null : snapshot.lastError(),
                    snapshot == null ? null : snapshot.lastDurationMs());
            })
            .sorted(java.util.Comparator.comparingInt(ProviderLine::priority))
            .toList();
        return new LlmStats(properties.getLlm().isEnabled(), providerHealth.lastSuccessfulEngine(), order, lines);
    }

    private List<DailyPoint> daily(List<Instant> trips, List<Instant> tools, Instant now) {
        Map<LocalDate, Long> tripBuckets = bucket(trips);
        Map<LocalDate, Long> toolBuckets = bucket(tools);
        List<DailyPoint> points = new ArrayList<>();
        LocalDate today = now.atZone(ZONE).toLocalDate();
        for (int offset = TREND_DAYS - 1; offset >= 0; offset--) {
            LocalDate date = today.minusDays(offset);
            points.add(new DailyPoint(date.toString(), tripBuckets.getOrDefault(date, 0L),
                toolBuckets.getOrDefault(date, 0L)));
        }
        return points;
    }

    private static Map<LocalDate, Long> bucket(List<Instant> timestamps) {
        return timestamps.stream().collect(Collectors.groupingBy(
            instant -> instant.atZone(ZONE).toLocalDate(), Collectors.counting()));
    }

    private static double round1(double value) {
        return Math.round(value * 10d) / 10d;
    }

    public record OverviewView(Instant generatedAt, UserStats users, TripStats trips, ContentStats content,
                               ToolStats tools, ShareStats shares, List<DailyPoint> daily, LlmStats llm) {
    }

    public record UserStats(long total, long verified, long newLast7Days) {
    }

    public record TripStats(long total, long registered, long anonymous, long newLast7Days, double avgDays) {
    }

    public record ContentStats(long publishedPois, long totalPois, long openFeedback) {
    }

    public record ToolStats(long total, long succeeded, long failed, double successRate,
                            long mockCalls, long realtimeCalls, long cachedCalls, long degradedCalls) {
    }

    public record ShareStats(long total, long active, long views) {
    }

    public record DailyPoint(String date, long plans, long toolCalls) {
    }

    public record LlmStats(boolean enabled, String lastSuccessfulEngine, List<String> selectionOrder,
                           List<ProviderLine> providers) {
    }

    public record ProviderLine(String id, String displayName, String model, int priority, boolean enabled,
                               boolean configured, long successCount, long failureCount,
                               String lastError, Long lastLatencyMs) {
    }
}
