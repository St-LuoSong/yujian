package com.yujian.travel.ai;

import com.yujian.travel.config.AppProperties;

/**
 * One resolved vendor configuration.
 *
 * Built from {@link AppProperties.Provider} so the rest of the planning stack
 * reads a small immutable record instead of raw configuration, and never sees a
 * vendor specific field.
 */
public record LlmProvider(String id, String displayName, String baseUrl, String apiKey, String model,
                          int priority, double temperature, int timeoutSeconds) {

    /** Resolves a configured vendor, inheriting the global defaults. */
    public static LlmProvider resolve(String id, AppProperties.Provider provider, AppProperties.Llm defaults) {
        String displayName = text(provider.getDisplayName());
        return new LlmProvider(
            id,
            displayName.isEmpty() ? id : displayName,
            text(provider.getBaseUrl()),
            text(provider.getApiKey()),
            text(provider.getModel()),
            provider.getPriority(),
            provider.getTemperature() == null ? defaults.getTemperature() : provider.getTemperature(),
            provider.getTimeoutSeconds() == null ? defaults.getTimeoutSeconds() : provider.getTimeoutSeconds());
    }

    /**
     * A vendor is usable only when the endpoint, the key and the model are all
     * present. A vendor that is switched on but has no key is reported in the
     * admin console as "enabled but not configured" rather than being tried.
     */
    public boolean configured() {
        return !baseUrl.isEmpty() && !apiKey.isEmpty() && !model.isEmpty();
    }

    private static String text(String value) {
        return value == null ? "" : value.trim();
    }
}
