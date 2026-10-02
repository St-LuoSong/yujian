package com.yujian.travel.ai;

import com.yujian.travel.config.AppProperties;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

/**
 * Builds the ordered planning chain.
 *
 * Order is a product decision, not a bean discovery accident: enabled vendors
 * sorted by their configured priority, then the mock engine which always
 * answers. Adding a vendor means adding configuration, not code.
 */
@Component
public class PlanningEngineRegistry {
    private final List<PlanningEngine> engines;
    private final List<LlmProvider> providers;

    // Explicitly marked because the class also carries private constructors for
    // tests; without this Spring would look for a no-argument constructor.
    @Autowired
    public PlanningEngineRegistry(AppProperties properties, PlanningPromptFactory promptFactory,
                                  LlmPlanParser planParser, MockPlanningEngine mockEngine) {
        this(resolveProviders(properties), mockEngine, promptFactory, planParser);
    }

    private PlanningEngineRegistry(List<LlmProvider> providers, MockPlanningEngine mockEngine,
                                   PlanningPromptFactory promptFactory, LlmPlanParser planParser) {
        this.providers = List.copyOf(providers);
        List<PlanningEngine> ordered = new ArrayList<>();
        for (LlmProvider provider : providers) {
            ordered.add(new LangChain4jPlanningEngine(provider, promptFactory, planParser));
        }
        ordered.add(mockEngine);
        this.engines = List.copyOf(ordered);
    }

    private PlanningEngineRegistry(List<PlanningEngine> engines) {
        this.engines = List.copyOf(engines);
        this.providers = List.of();
    }

    /**
     * Test seam: an explicit chain with an explicit order.
     *
     * Kept as a factory rather than a second public constructor, otherwise
     * Spring cannot decide which constructor to use when creating the bean.
     */
    static PlanningEngineRegistry of(List<PlanningEngine> engines) {
        return new PlanningEngineRegistry(engines);
    }

    /** Vendors in the order they will be tried, excluding the mock engine. */
    public List<LlmProvider> activeProviders() {
        return providers;
    }

    /** The whole chain, mock engine last. */
    public List<PlanningEngine> engines() {
        return engines;
    }

    private static List<LlmProvider> resolveProviders(AppProperties properties) {
        if (!properties.getLlm().isEnabled()) {
            return List.of();
        }
        return properties.getLlm().getProviders().entrySet().stream()
            .filter(entry -> entry.getValue().isEnabled())
            .map(entry -> LlmProvider.resolve(entry.getKey(), entry.getValue(), properties.getLlm()))
            .filter(LlmProvider::configured)
            .sorted(Comparator.comparingInt(LlmProvider::priority).thenComparing(LlmProvider::id))
            .toList();
    }
}
