package com.yujian.travel.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.ai.PlanningOutcome;
import com.yujian.travel.ai.TravelPlanningFacade;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.api.TripPlanModels;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.AnonymousSession;
import com.yujian.travel.domain.ToolInvocationLog;
import com.yujian.travel.domain.TripDayEntity;
import com.yujian.travel.domain.TripItemEntity;
import com.yujian.travel.domain.TripPlanEntity;
import com.yujian.travel.domain.UserAccount;
import com.yujian.travel.repository.AnonymousSessionRepository;
import com.yujian.travel.repository.ToolInvocationLogRepository;
import com.yujian.travel.repository.TripPlanRepository;
import com.yujian.travel.repository.UserAccountRepository;
import com.yujian.travel.tools.ToolOrchestrator;
import com.yujian.travel.tools.TravelToolPort;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

@Service
public class TripPlanService {
    private static final DateTimeFormatter TIME_FORMATTER = DateTimeFormatter.ofPattern("HH:mm");

    private final TripPlanRepository tripPlanRepository;
    private final UserAccountRepository userRepository;
    private final AnonymousSessionRepository anonymousSessionRepository;
    private final OwnerResolver ownerResolver;
    private final AnonymousSessionService anonymousSessionService;
    private final TravelPlanningFacade travelPlanningFacade;
    private final ToolOrchestrator toolOrchestrator;
    private final ToolInvocationLogRepository toolInvocationLogRepository;
    private final TravelToolPort travelToolPort;
    private final ObjectMapper objectMapper;

    public TripPlanService(TripPlanRepository tripPlanRepository, UserAccountRepository userRepository,
                           AnonymousSessionRepository anonymousSessionRepository, OwnerResolver ownerResolver,
                           AnonymousSessionService anonymousSessionService, TravelPlanningFacade travelPlanningFacade,
                           ToolOrchestrator toolOrchestrator, ToolInvocationLogRepository toolInvocationLogRepository,
                           TravelToolPort travelToolPort, ObjectMapper objectMapper) {
        this.tripPlanRepository = tripPlanRepository;
        this.userRepository = userRepository;
        this.anonymousSessionRepository = anonymousSessionRepository;
        this.ownerResolver = ownerResolver;
        this.anonymousSessionService = anonymousSessionService;
        this.travelPlanningFacade = travelPlanningFacade;
        this.toolOrchestrator = toolOrchestrator;
        this.toolInvocationLogRepository = toolInvocationLogRepository;
        this.travelToolPort = travelToolPort;
        this.objectMapper = objectMapper;
    }

    @Transactional
    public TripPlanModels.CreateResult create(TripPlanModels.CreateRequest request, String deviceFingerprint) {
        OwnerContext owner = ownerResolver.resolveOrCreate(deviceFingerprint);
        if (owner.isAnonymous()) {
            anonymousSessionService.reservePlanning(owner.anonymousSessionId());
        }
        TravelModels.PlanRequest planRequest = new TravelModels.PlanRequest(request.prompt(),
            request.startDate(), request.origin(),
            request.destination(), request.days(), request.travelers(), request.budgetPerPerson(),
            request.interests(), request.pace(), request.transport());
        PlanningOutcome outcome = travelPlanningFacade.generate(planRequest);
        TripPlanEntity entity = persist(outcome.plan(), planRequest, owner, outcome);
        toolOrchestrator.record(entity.getId(), outcome.tools());
        return new TripPlanModels.CreateResult(toDto(entity), owner.newAnonymousToken());
    }

    @Transactional(readOnly = true)
    public List<TripPlanModels.Summary> list() {
        OwnerContext owner = ownerResolver.requireOwner();
        return ownedPlans(owner).stream().map(this::toSummary).toList();
    }

    /**
     * "你的足迹"：把当前会话名下的行程聚合成城市、里程与旅行天数。
     *
     * 与 {@link #list()} 共用同一套归属判定，所以匿名体验和登录账号各看各的，
     * 不会因为共用一台设备就串号。所有数字都来自落库数据：没有任何估算、
     * 没有按天数脑补里程，也没有默认城市。
     */
    @Transactional(readOnly = true)
    public TripPlanModels.Footprint footprint() {
        return footprintOf(ownedPlans(ownerResolver.requireOwner()));
    }

    private List<TripPlanEntity> ownedPlans(OwnerContext owner) {
        return owner.isUser()
            ? tripPlanRepository.findByOwnerIdOrderByUpdatedAtDesc(owner.userId())
            : tripPlanRepository.findByAnonymousSessionIdOrderByUpdatedAtDesc(owner.anonymousSessionId());
    }

    /**
     * 纯函数形式的聚合，方便脱离 Spring 上下文直接验证口径。
     *
     * - 城市：出发地与目的地分别计数，两个城市相同只算一次；
     * - 里程：只累计行程项里真的带了距离的那些（路线工具给过距离才写库），
     *   所以这是"已记录里程"，界面必须照这个口径措辞；
     * - 天数：直接累加每份行程的 {@code daysCount}，不做去重（两趟都去洛阳，
     *   就是两天旅行）。
     */
    static TripPlanModels.Footprint footprintOf(List<TripPlanEntity> plans) {
        Map<String, CityAccumulator> cities = new LinkedHashMap<>();
        long totalMeters = 0L;
        int totalDays = 0;
        for (TripPlanEntity plan : plans) {
            totalDays += Math.max(plan.getDaysCount(), 0);
            for (String name : cityNames(plan)) {
                cities.computeIfAbsent(name, CityAccumulator::new).add(plan);
            }
            for (TripDayEntity day : plan.getDays()) {
                for (TripItemEntity item : day.getItems()) {
                    Integer meters = item.getDistanceMeters();
                    if (meters != null && meters > 0) {
                        totalMeters += meters;
                    }
                }
            }
        }
        Comparator<TripPlanModels.CityVisit> order =
            Comparator.comparing(TripPlanModels.CityVisit::lastVisitAt,
                    Comparator.nullsLast(Comparator.reverseOrder()))
                .thenComparing(Comparator.comparingInt(TripPlanModels.CityVisit::tripCount).reversed())
                .thenComparing(TripPlanModels.CityVisit::name);
        List<TripPlanModels.CityVisit> visits = cities.values().stream()
            .map(CityAccumulator::toVisit)
            .sorted(order)
            .toList();
        return new TripPlanModels.Footprint(visits, totalMeters, totalDays, plans.size(), Instant.now());
    }

    private static List<String> cityNames(TripPlanEntity plan) {
        List<String> names = new ArrayList<>(2);
        for (String raw : List.of(
            plan.getOrigin() == null ? "" : plan.getOrigin(),
            plan.getDestination() == null ? "" : plan.getDestination())) {
            String name = raw.trim();
            if (!name.isEmpty() && !names.contains(name)) {
                names.add(name);
            }
        }
        return names;
    }

    /** 一个城市在足迹里的累加器：次数 + 首次/最近到访时间。 */
    private static final class CityAccumulator {
        private final String name;
        private int tripCount;
        private Instant firstVisitAt;
        private Instant lastVisitAt;

        private CityAccumulator(String name) {
            this.name = name;
        }

        private void add(TripPlanEntity plan) {
            tripCount++;
            Instant created = plan.getCreatedAt();
            if (created != null && (firstVisitAt == null || created.isBefore(firstVisitAt))) {
                firstVisitAt = created;
            }
            // 没有 updatedAt 的旧数据退回 createdAt，绝不拿"现在"顶替。
            Instant last = plan.getUpdatedAt() != null ? plan.getUpdatedAt() : created;
            if (last != null && (lastVisitAt == null || last.isAfter(lastVisitAt))) {
                lastVisitAt = last;
            }
        }

        private TripPlanModels.CityVisit toVisit() {
            return new TripPlanModels.CityVisit(name, tripCount, firstVisitAt, lastVisitAt);
        }
    }

    @Transactional(readOnly = true)
    public TravelModels.TripPlan get(UUID id) {
        return toDto(requireOwned(id, ownerResolver.requireOwner()));
    }

    @Transactional
    public TravelModels.TripPlan patch(UUID id, TripPlanModels.PatchRequest request) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        if (request.title() != null && !request.title().isBlank()) {
            entity.setTitle(request.title().trim());
        }
        if (request.summary() != null && !request.summary().isBlank()) {
            entity.setSummary(request.summary().trim());
        }
        if (request.intensity() != null && !request.intensity().isBlank()) {
            entity.setIntensity(request.intensity().trim());
        }
        return toDto(entity);
    }

    @Transactional
    public void delete(UUID id) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        tripPlanRepository.delete(entity);
    }

    @Transactional
    public TripPlanModels.AdjustmentResult adjust(UUID id, String instruction) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        TravelModels.TripPlan before = toDto(entity);
        String snapshot = writeSnapshot(before);
        AdjustmentEngine.Result result = AdjustmentEngine.adjust(before, instruction);
        applyPlan(entity, result.plan());
        entity.setPreviousSnapshot(snapshot);
        entity.setSnapshotVersion(entity.getSnapshotVersion() + 1);
        return new TripPlanModels.AdjustmentResult(toDto(entity), result.changes(), entity.getSnapshotVersion());
    }

    @Transactional
    public TravelModels.TripPlan undo(UUID id) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        if (entity.getPreviousSnapshot() == null || entity.getPreviousSnapshot().isBlank()) {
            throw new ApiException(HttpStatus.CONFLICT, "NOTHING_TO_UNDO", "当前行程没有可撤销的调整");
        }
        TravelModels.TripPlan previous = readSnapshot(entity.getPreviousSnapshot(), id);
        applyPlan(entity, previous);
        entity.setPreviousSnapshot(null);
        entity.setSnapshotVersion(Math.max(1, entity.getSnapshotVersion() - 1));
        return toDto(entity);
    }

    @Transactional
    public void transferAnonymousPlans(UUID anonymousSessionId, UUID userId) {
        List<TripPlanEntity> plans = tripPlanRepository.findByAnonymousSessionIdOrderByUpdatedAtDesc(anonymousSessionId);
        if (plans.isEmpty()) {
            return;
        }
        UserAccount user = userRepository.getReferenceById(userId);
        plans.forEach(plan -> {
            plan.setOwner(user);
            plan.setAnonymousSession(null);
        });
        tripPlanRepository.saveAll(plans);
    }

    @Transactional(readOnly = true)
    public TripPlanModels.TodayResponse today(UUID id) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        TravelModels.TripPlan plan = toDto(entity);
        List<TravelModels.TripItem> items = plan.days().isEmpty() ? List.of() : plan.days().get(0).items();
        String nextStop = items.isEmpty() ? "暂无安排" : items.get(0).title();
        String arrival = items.isEmpty() ? "待定" : items.get(0).time();
        // 与规划阶段走同一个端口：能取到实时天气就显示实时，取不到会自带降级标记。
        var weather = travelToolPort.getWeather(entity.getDestination(), "今日");
        String weatherText = weather.success()
            ? weather.data().condition() + " " + weather.data().minTemperature() + "—"
            + weather.data().maxTemperature() + "℃"
            : "天气数据暂不可用";
        return new TripPlanModels.TodayResponse(id, "今日", nextStop, arrival,
            weatherText, plan.dataStatus(), items);
    }

    @Transactional(readOnly = true)
    public TripPlanModels.TraceResponse trace(UUID id) {
        TripPlanEntity entity = requireOwned(id, ownerResolver.requireOwner());
        List<TripPlanModels.ToolTrace> traces = toolInvocationLogRepository
            .findByTripPlanIdOrderByCreatedAtAsc(id).stream()
            .map(log -> new TripPlanModels.ToolTrace(log.getToolName(), log.getSource(), log.getDataStatus(),
                log.isSuccess(), log.getOutputSummary(), log.getErrorCode(), log.getDurationMs(), log.getCreatedAt()))
            .toList();
        return new TripPlanModels.TraceResponse(id, entity.getPlanningEngine(), entity.getPromptVersion(),
            entity.getDataStatus(), entity.getToolMockCount() == null ? 0 : entity.getToolMockCount(),
            List.copyOf(entity.getWarnings()), traces);
    }

    @Transactional(readOnly = true)
    public TripPlanEntity requireOwned(UUID id, OwnerContext owner) {
        return (owner.isUser()
            ? tripPlanRepository.findWithDetailsByIdAndOwnerId(id, owner.userId())
            : tripPlanRepository.findWithDetailsByIdAndAnonymousSessionId(id, owner.anonymousSessionId()))
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "TRIP_NOT_FOUND", "行程不存在或无权访问"));
    }

    private TripPlanEntity persist(TravelModels.TripPlan generated, TravelModels.PlanRequest request,
                                   OwnerContext owner, PlanningOutcome outcome) {
        TripPlanEntity entity = new TripPlanEntity();
        entity.setTitle(ColumnText.clamp(generated.title(), 160));
        entity.setSummary(ColumnText.clamp(generated.summary(), 600));
        entity.setCorridor(ColumnText.clamp(generated.corridor(), 80));
        entity.setIntensity(ColumnText.clamp(generated.intensity(), 32));
        entity.setPrompt(ColumnText.clamp(request.prompt(), 1000));
        entity.setOrigin(ColumnText.clamp(request.origin(), 80));
        entity.setDestination(ColumnText.clamp(request.destination(), 80));
        entity.setDaysCount(generated.days().size());
        entity.setTravelers(request.travelers() == null || request.travelers() < 1 ? 2 : request.travelers());
        entity.setBudgetPerPerson(request.budgetPerPerson());
        entity.setTotalCost(generated.totalCost());
        entity.setPerPersonCost(generated.perPersonCost());
        entity.setDataStatus(generated.dataStatus());
        entity.setPlanningEngine(ColumnText.clamp(outcome.engine(), 64));
        entity.setPromptVersion(ColumnText.clamp(outcome.promptVersion(), 64));
        entity.setToolMockCount(outcome.tools().mockCount());
        entity.getWarnings().clear();
        generated.warnings().forEach(warning -> entity.getWarnings().add(ColumnText.clamp(warning, 500)));
        if (owner.isUser()) {
            entity.setOwner(userRepository.getReferenceById(owner.userId()));
        } else {
            entity.setAnonymousSession(anonymousSessionRepository.getReferenceById(owner.anonymousSessionId()));
        }
        applyDays(entity, generated.days());
        return tripPlanRepository.save(entity);
    }

    private void applyPlan(TripPlanEntity entity, TravelModels.TripPlan plan) {
        entity.setTitle(ColumnText.clamp(plan.title(), 160));
        entity.setSummary(ColumnText.clamp(plan.summary(), 600));
        entity.setCorridor(ColumnText.clamp(plan.corridor(), 80));
        entity.setIntensity(ColumnText.clamp(plan.intensity(), 32));
        entity.setTotalCost(plan.totalCost());
        entity.setPerPersonCost(plan.perPersonCost());
        entity.setDaysCount(plan.days().size());
        entity.setDataStatus(plan.dataStatus());
        entity.getWarnings().clear();
        plan.warnings().forEach(warning -> entity.getWarnings().add(ColumnText.clamp(warning, 500)));
        applyDays(entity, plan.days());
    }

    private void applyDays(TripPlanEntity entity, List<TravelModels.TripDay> days) {
        List<TripDayEntity> entities = new ArrayList<>();
        int dayIndex = 0;
        for (TravelModels.TripDay day : days) {
            TripDayEntity dayEntity = new TripDayEntity();
            dayEntity.setLabel(ColumnText.clamp(day.label(), 32));
            dayEntity.setDateLabel(ColumnText.clamp(day.date(), 64));
            dayEntity.setSortOrder(dayIndex++);
            int itemIndex = 0;
            for (TravelModels.TripItem item : day.items()) {
                TripItemEntity itemEntity = new TripItemEntity();
                itemEntity.setItemType(ColumnText.clamp(item.type(), 32));
                itemEntity.setTitle(ColumnText.clamp(item.title(), 160));
                itemEntity.setDescription(ColumnText.clamp(item.description(), 600));
                itemEntity.setStartTime(ColumnText.clamp(item.time(), 16));
                itemEntity.setDurationMinutes(DurationText.parseMinutes(item.duration()));
                itemEntity.setEndTime(ColumnText.clamp(
                    computeEndTime(item.time(), itemEntity.getDurationMinutes()), 16));
                itemEntity.setTransportMode(ColumnText.clamp(item.transport(), 80));
                itemEntity.setEstimatedCost(Math.max(0, item.cost()));
                itemEntity.setSource(ColumnText.clamp(item.source(), 160));
                itemEntity.setDataStatus(ColumnText.clamp(item.dataStatus(), 32));
                itemEntity.setFeasibilityStatus(item.risk() == null || item.risk().isBlank() ? "OK" : "WARNING");
                itemEntity.setRiskWarnings(ColumnText.clamp(item.risk(), 1000));
                itemEntity.setSortOrder(itemIndex++);
                dayEntity.addItem(itemEntity);
            }
            entities.add(dayEntity);
        }
        entity.replaceDays(entities);
    }

    private TripPlanModels.Summary toSummary(TripPlanEntity entity) {
        return new TripPlanModels.Summary(entity.getId(), entity.getTitle(), entity.getSummary(),
            entity.getCorridor(), entity.getIntensity(), entity.getTotalCost(), entity.getPerPersonCost(),
            entity.getDaysCount(), entity.getDataStatus(), entity.getUpdatedAt());
    }

    public TravelModels.TripPlan toDto(TripPlanEntity entity) {
        List<TravelModels.TripDay> days = entity.getDays().stream()
            .sorted(Comparator.comparingInt(TripDayEntity::getSortOrder))
            .map(day -> new TravelModels.TripDay(day.getLabel(), day.getDateLabel(),
                day.getItems().stream().sorted(Comparator.comparingInt(TripItemEntity::getSortOrder))
                    .map(item -> new TravelModels.TripItem(item.getItemType(), item.getTitle(), item.getStartTime(),
                        DurationText.format(item.getDurationMinutes()), item.getTransportMode(), item.getDescription(),
                        item.getEstimatedCost(), item.getSource(), item.getDataStatus(), item.getRiskWarnings()))
                    .toList()))
            .toList();
        return new TravelModels.TripPlan(entity.getId().toString(), entity.getTitle(), entity.getSummary(),
            entity.getCorridor(), entity.getIntensity(), entity.getTotalCost(), entity.getPerPersonCost(),
            days, List.copyOf(entity.getWarnings()), entity.getDataStatus());
    }

    private String writeSnapshot(TravelModels.TripPlan plan) {
        try {
            return objectMapper.writeValueAsString(plan);
        } catch (JsonProcessingException exception) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "SNAPSHOT_FAILED", "暂时无法保存调整前版本");
        }
    }

    private TravelModels.TripPlan readSnapshot(String snapshot, UUID id) {
        try {
            TravelModels.TripPlan plan = objectMapper.readValue(snapshot, TravelModels.TripPlan.class);
            return new TravelModels.TripPlan(id.toString(), plan.title(), plan.summary(), plan.corridor(),
                plan.intensity(), plan.totalCost(), plan.perPersonCost(), plan.days(), plan.warnings(), plan.dataStatus());
        } catch (JsonProcessingException exception) {
            throw new ApiException(HttpStatus.INTERNAL_SERVER_ERROR, "SNAPSHOT_BROKEN", "调整前版本无法恢复");
        }
    }

    private String computeEndTime(String startTime, Integer durationMinutes) {
        if (startTime == null || !startTime.matches("\\d{2}:\\d{2}")) {
            return null;
        }
        try {
            return LocalTime.parse(startTime, TIME_FORMATTER)
                .plusMinutes(durationMinutes == null ? 120 : durationMinutes)
                .format(TIME_FORMATTER);
        } catch (Exception exception) {
            return null;
        }
    }

}
