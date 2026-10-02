package com.yujian.travel.config;

import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import static org.assertj.core.api.Assertions.assertThat;

class SecurityConfigCorsTest {
    @Test
    void anonymousDeviceHeaderIsAllowedForBrowserPreflight() {
        SecurityConfig securityConfig = new SecurityConfig();
        UrlBasedCorsConfigurationSource source = (UrlBasedCorsConfigurationSource)
            securityConfig.corsConfigurationSource(new AppProperties());

        CorsConfiguration configuration = source.getCorsConfiguration(
            new MockHttpServletRequest("OPTIONS", "/api/anonymous/session"));

        assertThat(configuration).isNotNull();
        assertThat(configuration.getAllowedHeaders())
            .contains("Authorization", "Content-Type", "X-Anonymous-Token", "X-Device-Fingerprint");
    }
}
