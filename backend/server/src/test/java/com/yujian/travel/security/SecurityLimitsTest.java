package com.yujian.travel.security;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.AppSettingEntity;
import com.yujian.travel.repository.AppSettingRepository;
import com.yujian.travel.repository.ToolInvocationLogRepository;
import com.yujian.travel.service.AppSettingService;
import com.yujian.travel.service.ToolQuotaService;
import org.junit.jupiter.api.Test;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 限流与工具配额的行为约束。
 *
 * 这两件事都属于"平时看不出、关键时刻决定服务会不会被打穿"的类型，
 * 所以这里盯的是边界：刚好到额度放行、超出才拒绝、未登记的键一律不认。
 */
class SecurityLimitsTest {

    @Test
    void rateLimitAllowsUpToTheLimitThenRejects() {
        AppSettingService settings = settingsWith(Map.of(
            "rate.read.limit", 3L,
            "rate.read.window", 60L));
        RateLimitService limiter = new RateLimitService(settings);

        assertThat(limiter.check(List.of("read"), "ip:1.1.1.1").allowed()).isTrue();
        assertThat(limiter.check(List.of("read"), "ip:1.1.1.1").allowed()).isTrue();
        assertThat(limiter.check(List.of("read"), "ip:1.1.1.1").allowed()).isTrue();

        RateLimitService.Decision blocked = limiter.check(List.of("read"), "ip:1.1.1.1");

        assertThat(blocked.allowed()).isFalse();
        // 拒绝时要带上"还要等多久"，否则客户端只能盲目重试。
        assertThat(blocked.retryAfterSeconds()).isGreaterThan(0);
        // 换一个身份不受影响：限流必须按主体分桶，不能一处超限全员被挡。
        assertThat(limiter.check(List.of("read"), "ip:2.2.2.2").allowed()).isTrue();
    }

    @Test
    void rateLimitCanBeTurnedOffFromSettings() {
        AppSettingService settings = settingsWith(Map.of(
            "rate.enabled", 0L,
            "rate.read.limit", 1L));
        RateLimitService limiter = new RateLimitService(settings);

        for (int index = 0; index < 5; index++) {
            assertThat(limiter.check(List.of("read"), "ip:1.1.1.1").allowed()).isTrue();
        }
    }

    @Test
    void settingsRejectUnknownKeysAndOutOfRangeValues() {
        AppSettingService settings = settingsWith(Map.of());

        assertThatThrownBy(() -> settings.update(Map.of("rate.read.limitX", 5L)))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("不认识的设置项");

        // 上限写成 0 会让读接口全部不可用，必须当场拒绝而不是先存下来。
        assertThatThrownBy(() -> settings.update(Map.of("rate.read.limit", 0L)))
            .isInstanceOf(ApiException.class)
            .hasMessageContaining("必须在");
    }

    @Test
    void toolQuotaOnlyAppliesToExternalTools() {
        AppSettingService settings = settingsWith(Map.of(
            "quota.weather.daily", 5L,
            "quota.route.daily", 5L,
            "quota.rail.daily", 5L));
        ToolInvocationLogRepository logs = mock(ToolInvocationLogRepository.class);
        // 只有天气今天用满了；路线是空的。
        when(logs.countByToolNamePrefixSince(anyString(), any())).thenAnswer(invocation ->
            "getweather".equals(invocation.getArgument(0, String.class)) ? 5L : 0L);
        when(logs.countByToolNamesSince(any(), any())).thenReturn(0L);
        ToolQuotaService quota = new ToolQuotaService(settings, logs);

        // 本地内容库不消耗任何外部额度。
        assertThat(quota.check("searchPoi").allowed()).isTrue();
        assertThat(quota.check("checkAttractionOpening").allowed()).isTrue();

        // 外部工具用满即熔断，并说明原因；"第 2 天"这类带天号的键算在同一个额度里。
        assertThat(quota.check("getWeather").allowed()).isFalse();
        assertThat(quota.check("getWeather:第2天").allowed()).isFalse();
        assertThat(quota.check("getWeather").reason()).contains("额度已用完");

        // 别的组不受影响：一个上游用满不该把另外两个也停掉。
        assertThat(quota.check("getRoute").allowed()).isTrue();
        assertThat(quota.check("searchTrain").allowed()).isTrue();
    }

    /** 用一个内存仓库替身构造设置服务；未登记的键走默认值。 */
    private static AppSettingService settingsWith(Map<String, Long> overrides) {
        AppSettingRepository repository = mock(AppSettingRepository.class);
        Map<String, AppSettingEntity> stored = new HashMap<>();
        overrides.forEach((key, value) -> {
            AppSettingEntity entity = new AppSettingEntity();
            entity.setKey(key);
            entity.setValue(String.valueOf(value));
            stored.put(key, entity);
        });
        when(repository.findAll()).thenReturn(List.copyOf(stored.values()));
        when(repository.findById(anyString())).thenAnswer(invocation ->
            Optional.ofNullable(stored.get(invocation.getArgument(0, String.class))));
        when(repository.save(any(AppSettingEntity.class))).thenAnswer(invocation -> {
            AppSettingEntity entity = invocation.getArgument(0);
            stored.put(entity.getKey(), entity);
            return entity;
        });
        return new AppSettingService(repository);
    }
}
