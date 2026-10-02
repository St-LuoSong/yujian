package com.yujian.travel.api;

import com.yujian.travel.ai.LlmProvider;
import com.yujian.travel.ai.PlanningEngineRegistry;
import com.yujian.travel.ai.ProviderHealth;
import com.yujian.travel.config.AppProperties;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Comparator;
import java.util.List;

/**
 * Vendor status for the operator console.
 *
 * The security chain requires the ADMIN role for every `/api/admin/**` request.
 * API keys are never part of the response: the console only needs to know
 * whether a vendor is enabled, whether it is configured, and how it behaved.
 */
@RestController
@RequestMapping("/api/admin/llm")
public class LlmAdminController {
    private final AppProperties properties;
    private final PlanningEngineRegistry registry;
    private final ProviderHealth health;

    public LlmAdminController(AppProperties properties, PlanningEngineRegistry registry,
                              ProviderHealth health) {
        this.properties = properties;
        this.registry = registry;
        this.health = health;
    }

    @GetMapping("/providers")
    public ProviderReport providers() {
        List<ProviderView> catalog = properties.getLlm().getProviders().entrySet().stream()
            .map(entry -> view(entry.getKey(), entry.getValue()))
            .sorted(Comparator.comparingInt(ProviderView::priority).thenComparing(ProviderView::id))
            .toList();
        List<String> selectionOrder = registry.activeProviders().stream().map(LlmProvider::id).toList();
        return new ProviderReport(properties.getLlm().isEnabled(), health.lastSuccessfulEngine(),
            selectionOrder, catalog, health.snapshots());
    }

    private ProviderView view(String id, AppProperties.Provider provider) {
        LlmProvider resolved = LlmProvider.resolve(id, provider, properties.getLlm());
        return new ProviderView(
            id,
            resolved.displayName(),
            resolved.model(),
            resolved.priority(),
            provider.isEnabled(),
            resolved.configured(),
            resolved.baseUrl(),
            resolved.timeoutSeconds(),
            resolved.temperature());
    }

    public record ProviderView(String id, String displayName, String model, int priority, boolean enabled,
                               boolean configured, String baseUrl, int timeoutSeconds, double temperature) {
    }

    public record ProviderReport(boolean llmEnabled, String activeEngine, List<String> selectionOrder,
                                 List<ProviderView> providers, List<ProviderHealth.Snapshot> attempts) {
    }
}
