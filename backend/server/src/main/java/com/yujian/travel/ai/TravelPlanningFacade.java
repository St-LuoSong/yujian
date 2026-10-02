package com.yujian.travel.ai;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.PlanDates;
import com.yujian.travel.service.PromptVersionService;
import com.yujian.travel.tools.ToolCollection;
import com.yujian.travel.tools.ToolOrchestrator;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;

/**
 * Plans a trip through an ordered chain of vendors.
 *
 * The chain comes from {@link PlanningEngineRegistry}: enabled vendors sorted by
 * priority, then the mock engine which always answers. Every attempt is timed
 * and recorded in {@link ProviderHealth}, so the admin console can explain which
 * vendor served a plan and why the chain moved on.
 */
@Service
public class TravelPlanningFacade {
    private final PlanningEngineRegistry engineRegistry;
    private final MockPlanningEngine mockPlanningEngine;
    private final TripPlanValidator tripPlanValidator;
    private final ToolOrchestrator toolOrchestrator;
    private final ProviderHealth providerHealth;
    private final PromptVersionService promptVersionService;

    /** 测试用构造器：没有数据库时使用内置提示词版本。 */
    public TravelPlanningFacade(PlanningEngineRegistry engineRegistry, MockPlanningEngine mockPlanningEngine,
                                TripPlanValidator tripPlanValidator, ToolOrchestrator toolOrchestrator,
                                ProviderHealth providerHealth) {
        this(engineRegistry, mockPlanningEngine, tripPlanValidator, toolOrchestrator, providerHealth,
            new PromptVersionService(null));
    }

    @Autowired
    public TravelPlanningFacade(PlanningEngineRegistry engineRegistry, MockPlanningEngine mockPlanningEngine,
                                TripPlanValidator tripPlanValidator, ToolOrchestrator toolOrchestrator,
                                ProviderHealth providerHealth, PromptVersionService promptVersionService) {
        this.engineRegistry = engineRegistry;
        this.mockPlanningEngine = mockPlanningEngine;
        this.tripPlanValidator = tripPlanValidator;
        this.toolOrchestrator = toolOrchestrator;
        this.providerHealth = providerHealth;
        this.promptVersionService = promptVersionService;
    }

    public PlanningOutcome generate(TravelModels.PlanRequest request) {
        ToolCollection tools = toolOrchestrator.collect(request);
        String promptVersion = promptVersionService.currentVersion();
        PlanningContext context = new PlanningContext(request, tools, promptVersion);
        List<PlanningEngine> candidates = engineRegistry.engines().stream()
            .filter(engine -> !engine.name().equals(mockPlanningEngine.name()))
            .filter(PlanningEngine::available)
            .toList();

        boolean fallback = false;
        String engineName = mockPlanningEngine.name();
        TravelModels.TripPlan plan = null;
        for (PlanningEngine candidate : candidates) {
            long startedAt = System.nanoTime();
            try {
                plan = candidate.generate(context);
                providerHealth.success(candidate.name(), elapsedMillis(startedAt));
                engineName = candidate.name();
                break;
            } catch (Exception exception) {
                // Try the next vendor in priority order; the mock engine is last.
                providerHealth.failure(candidate.name(), elapsedMillis(startedAt), describe(exception));
            }
        }
        if (plan == null) {
            plan = mockPlanningEngine.generate(context);
            fallback = !candidates.isEmpty();
            engineName = fallback ? "mock-fallback" : mockPlanningEngine.name();
        }

        // 日期由用户选的出发日说了算：模型可以决定"怎么玩"，
        // 但不能决定"哪天玩"。校验之前先落地日期，
        // 这样开放时间、天气与跨城交通的风险判断都对着同一天。
        LocalDate start = PlanDates.resolveStartDate(request.startDate());
        TravelModels.TripPlan datedPlan = PlanDates.applyDates(plan, start);

        ValidationReport validation = tripPlanValidator.validate(datedPlan, request, tools);
        List<String> warnings = mergeWarnings(datedPlan.warnings(), tools.warnings(), validation.warnings(),
            fallback ? List.of("AI 规划服务暂时不可用，已自动使用稳定演示方案。") : List.of());
        String dataStatus = fallback ? "演示数据（AI 降级）" : datedPlan.dataStatus();
        TravelModels.TripPlan finalPlan = new TravelModels.TripPlan(datedPlan.id(), datedPlan.title(),
            datedPlan.summary(), datedPlan.corridor(), datedPlan.intensity(), datedPlan.totalCost(),
            datedPlan.perPersonCost(), datedPlan.days(), warnings, dataStatus);
        return new PlanningOutcome(finalPlan, engineName, promptVersion, tools, validation, fallback);
    }

    private static long elapsedMillis(long startedAt) {
        return (System.nanoTime() - startedAt) / 1_000_000;
    }

    private static String describe(Exception exception) {
        String message = exception.getMessage();
        return message == null || message.isBlank() ? exception.getClass().getSimpleName() : message;
    }

    @SafeVarargs
    private final List<String> mergeWarnings(List<String>... groups) {
        Set<String> merged = new LinkedHashSet<>();
        for (List<String> group : groups) {
            if (group != null) {
                merged.addAll(group);
            }
        }
        return new ArrayList<>(merged);
    }
}
