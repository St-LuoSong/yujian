package com.yujian.travel.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.DemoScenarioEntity;
import com.yujian.travel.repository.DemoScenarioRepository;
import org.junit.jupiter.api.Test;

import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class DemoScenarioServiceTest {
    private final DemoScenarioRepository repository = mock(DemoScenarioRepository.class);
    private final DemoScenarioService service =
        new DemoScenarioService(repository, new ObjectMapper());

    @Test
    void validWeatherOverrideIsNormalizedAndSaved() {
        when(repository.findByScenarioKeyAndMatchKey("weather", "洛阳"))
            .thenReturn(Optional.empty());
        when(repository.save(any(DemoScenarioEntity.class)))
            .thenAnswer(invocation -> invocation.getArgument(0));

        DemoScenarioService.ScenarioView saved = service.upsert("weather", "洛阳", "洛阳晴天",
            "{\"city\":\"洛阳\",\"date\":\"2026-10-03\",\"condition\":\"晴\","
                + "\"minTemperature\":18,\"maxTemperature\":26,\"rainProbability\":10,"
                + "\"wind\":\"东风2级\",\"suggestion\":\"适合游览\"}",
            "测试覆盖", true);

        assertThat(saved.scenarioKey()).isEqualTo("weather");
        assertThat(saved.matchKey()).isEqualTo("洛阳");
        assertThat(saved.enabled()).isTrue();
        assertThat(saved.payloadJson()).contains("\"condition\" : \"晴\"");
    }

    @Test
    void invalidPayloadIsRejectedBeforeItCanReachRuntime() {
        assertThatThrownBy(() -> service.upsert("train", "郑州>洛阳", "坏车次",
            "{\"trainNo\":\"G1\"}", "wrong shape", true))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("结构与 train 的返回类型不匹配");
    }

    @Test
    void lookupReturnsOnlyEnabledOverride() {
        DemoScenarioEntity entity = new DemoScenarioEntity();
        entity.setScenarioKey("weather");
        entity.setMatchKey("洛阳");
        entity.setPayloadJson("{\"city\":\"洛阳\"}");
        entity.setEnabled(true);
        when(repository.findByScenarioKeyAndMatchKeyAndEnabledTrue("weather", "洛阳"))
            .thenReturn(Optional.of(entity));

        assertThat(service.lookup("weather", "洛阳"))
            .contains("{\"city\":\"洛阳\"}");
    }
}
