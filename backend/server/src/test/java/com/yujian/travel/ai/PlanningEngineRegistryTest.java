package com.yujian.travel.ai;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.service.TripPlanFactory;
import org.junit.jupiter.api.Test;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * The vendor chain is a product decision, so it gets an explicit test: only
 * enabled and fully configured vendors are used, and they run in priority order
 * with the mock engine last.
 */
class PlanningEngineRegistryTest {

    @Test
    void disabledAndUnconfiguredVendorsAreLeftOut() {
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("openai", vendor(true, "https://api.openai.com/v1", "sk-openai", 20));
        vendors.put("deepseek", vendor(true, "https://api.deepseek.com/v1", "", 10));
        vendors.put("kimi", vendor(false, "https://api.moonshot.cn/v1", "sk-kimi", 5));

        assertThat(registry(properties(vendors)).activeProviders())
            .extracting(LlmProvider::id)
            .containsExactly("openai");
    }

    @Test
    void vendorsRunInPriorityOrderAndTheMockEngineIsLast() {
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("openai", vendor(true, "https://api.openai.com/v1", "sk-openai", 40));
        vendors.put("deepseek", vendor(true, "https://api.deepseek.com/v1", "sk-deepseek", 10));
        vendors.put("qwen", vendor(true, "https://dashscope.aliyuncs.com/compatible-mode/v1", "sk-qwen", 30));

        PlanningEngineRegistry registry = registry(properties(vendors));

        assertThat(registry.activeProviders())
            .extracting(LlmProvider::id)
            .containsExactly("deepseek", "qwen", "openai");
        assertThat(registry.engines())
            .extracting(PlanningEngine::name)
            .containsExactly("deepseek", "qwen", "openai", "mock-trip-factory");
    }

    @Test
    void disablingTheFeatureLeavesOnlyTheMockEngine() {
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("deepseek", vendor(true, "https://api.deepseek.com/v1", "sk-deepseek", 10));
        AppProperties properties = properties(vendors);
        properties.getLlm().setEnabled(false);

        PlanningEngineRegistry registry = registry(properties);

        assertThat(registry.activeProviders()).isEmpty();
        assertThat(registry.engines())
            .extracting(PlanningEngine::name)
            .containsExactly("mock-trip-factory");
    }

    @Test
    void aVendorInheritsGlobalTemperatureAndTimeout() {
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("deepseek", vendor(true, "https://api.deepseek.com/v1", "sk-deepseek", 10));
        AppProperties properties = properties(vendors);
        properties.getLlm().setTemperature(0.7);
        properties.getLlm().setTimeoutSeconds(45);

        LlmProvider inherited = registry(properties).activeProviders().get(0);

        assertThat(inherited.temperature()).isEqualTo(0.7);
        assertThat(inherited.timeoutSeconds()).isEqualTo(45);
    }

    @Test
    void aVendorCanOverrideTheGlobalTemperatureAndTimeout() {
        AppProperties.Provider deepseek = vendor(true, "https://api.deepseek.com/v1", "sk-deepseek", 10);
        deepseek.setTemperature(0.1);
        deepseek.setTimeoutSeconds(15);
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("deepseek", deepseek);
        AppProperties properties = properties(vendors);
        properties.getLlm().setTemperature(0.7);
        properties.getLlm().setTimeoutSeconds(45);

        LlmProvider resolved = registry(properties).activeProviders().get(0);

        assertThat(resolved.temperature()).isEqualTo(0.1);
        assertThat(resolved.timeoutSeconds()).isEqualTo(15);
    }

    @Test
    void anEnabledVendorWithoutAKeyIsReportedAsNotConfigured() {
        Map<String, AppProperties.Provider> vendors = new LinkedHashMap<>();
        vendors.put("qwen", vendor(true, "https://dashscope.aliyuncs.com/compatible-mode/v1", "", 10));
        AppProperties properties = properties(vendors);

        LlmProvider resolved = LlmProvider.resolve("qwen",
            properties.getLlm().getProviders().get("qwen"), properties.getLlm());

        assertThat(resolved.configured()).isFalse();
        assertThat(resolved.model()).isEqualTo("test-model");
    }

    private static AppProperties properties(Map<String, AppProperties.Provider> vendors) {
        AppProperties properties = new AppProperties();
        properties.getLlm().setEnabled(true);
        properties.getLlm().setProviders(vendors);
        return properties;
    }

    private static AppProperties.Provider vendor(boolean enabled, String baseUrl, String apiKey, int priority) {
        AppProperties.Provider provider = new AppProperties.Provider();
        provider.setEnabled(enabled);
        provider.setBaseUrl(baseUrl);
        provider.setApiKey(apiKey);
        provider.setModel("test-model");
        provider.setPriority(priority);
        return provider;
    }

    private static PlanningEngineRegistry registry(AppProperties properties) {
        ObjectMapper mapper = new ObjectMapper();
        return new PlanningEngineRegistry(properties, new PlanningPromptFactory(mapper),
            new LlmPlanParser(mapper), new MockPlanningEngine(new TripPlanFactory()));
    }
}
