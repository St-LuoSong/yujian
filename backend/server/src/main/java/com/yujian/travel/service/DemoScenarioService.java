package com.yujian.travel.service;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.DemoScenarioEntity;
import com.yujian.travel.repository.DemoScenarioRepository;
import com.yujian.travel.tools.ToolModels;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Optional;
import java.util.UUID;

/**
 * 演示数据覆盖目录。
 *
 * 保存前按工具返回类型做严格 JSON 校验，运行时只读取已启用的记录；读取失败或没有记录时，
 * MockTravelTools 会回退到代码内置样例。这样运营台可以稳定演示，同时不会把坏 JSON 带进规划。
 */
@Service
public class DemoScenarioService {
    private static final String DEFAULT_MATCH = "default";

    private final DemoScenarioRepository repository;
    private final ObjectMapper objectMapper;

    public DemoScenarioService(DemoScenarioRepository repository, ObjectMapper objectMapper) {
        this.repository = repository;
        this.objectMapper = objectMapper;
    }

    public MockCatalogView catalog() {
        List<ScenarioView> scenarios = repository.findAllByOrderByScenarioKeyAscMatchKeyAsc().stream()
            .map(this::view)
            .toList();
        return new MockCatalogView(supported(), scenarios);
    }

    public List<ScenarioView> list() {
        return repository.findAllByOrderByScenarioKeyAscMatchKeyAsc().stream()
            .map(this::view)
            .toList();
    }

    /**
     * 运行时查找：先精确匹配，再匹配 default。
     *
     * 只返回 enabled 的记录；空值表示“没有运营台覆盖”，调用方必须使用内置样例。
     */
    public Optional<String> lookup(String scenarioKey, String matchKey) {
        String key = cleanKey(scenarioKey);
        String match = cleanMatch(matchKey);
        return repository.findByScenarioKeyAndMatchKeyAndEnabledTrue(key, match)
            .or(() -> repository.findByScenarioKeyAndMatchKeyAndEnabledTrue(key, DEFAULT_MATCH))
            .map(DemoScenarioEntity::getPayloadJson);
    }

    @Transactional
    public ScenarioView upsert(String scenarioKey, String matchKey, String name, String payloadJson,
                               String note, boolean enabled) {
        String key = cleanKey(scenarioKey);
        String match = cleanMatch(matchKey);
        if (!supportedKeys().contains(key)) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MOCK_SCENARIO_UNSUPPORTED",
                "不支持的演示数据类型：" + key);
        }
        String cleanName = clean(name, "名称不能为空");
        String normalizedJson = validateAndNormalize(key, payloadJson);

        DemoScenarioEntity entity = repository.findByScenarioKeyAndMatchKey(key, match)
            .orElseGet(DemoScenarioEntity::new);
        entity.setScenarioKey(key);
        entity.setMatchKey(match);
        entity.setName(truncate(cleanName, 120));
        entity.setPayloadJson(normalizedJson);
        entity.setNote(truncate(note, 300));
        entity.setEnabled(enabled);
        if (entity.getUpdatedAt() == null) {
            entity.setUpdatedAt(java.time.Instant.now());
        }
        return view(repository.save(entity));
    }

    @Transactional
    public void delete(UUID id) {
        DemoScenarioEntity entity = repository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "MOCK_SCENARIO_NOT_FOUND",
                "演示数据不存在"));
        repository.delete(entity);
    }

    private String validateAndNormalize(String key, String payloadJson) {
        if (payloadJson == null || payloadJson.isBlank()) {
            throw invalid("JSON 内容不能为空");
        }
        try {
            JsonNode node = objectMapper.readTree(payloadJson);
            switch (key) {
                case "weather" -> objectMapper.treeToValue(node, ToolModels.WeatherInfo.class);
                case "route" -> objectMapper.treeToValue(node, ToolModels.RouteInfo.class);
                case "train" -> objectMapper.convertValue(node,
                    new TypeReference<List<ToolModels.TrainInfo>>() { });
                case "railFare" -> objectMapper.convertValue(node,
                    new TypeReference<List<ToolModels.RailFare>>() { });
                case "transfer" -> objectMapper.convertValue(node,
                    new TypeReference<List<ToolModels.RailTransfer>>() { });
                default -> throw invalid("不支持的演示数据类型：" + key);
            }
            return objectMapper.writerWithDefaultPrettyPrinter().writeValueAsString(node);
        } catch (ApiException exception) {
            throw exception;
        } catch (Exception exception) {
            throw invalid("JSON 结构与 " + key + " 的返回类型不匹配：" + exception.getMessage());
        }
    }

    private ApiException invalid(String message) {
        return new ApiException(HttpStatus.BAD_REQUEST, "MOCK_PAYLOAD_INVALID", message);
    }

    private ScenarioView view(DemoScenarioEntity entity) {
        return new ScenarioView(entity.getId(), entity.getScenarioKey(), entity.getMatchKey(),
            entity.getName(), entity.getPayloadJson(), entity.getNote(), entity.isEnabled(),
            entity.getUpdatedAt());
    }

    private List<SupportedScenario> supported() {
        return List.of(
            new SupportedScenario("weather", "天气", "城市名，例如 洛阳；填写 default 作为兜底",
                "{\"city\":\"洛阳\",\"date\":\"2026-10-03\",\"condition\":\"晴\","
                    + "\"minTemperature\":18,\"maxTemperature\":26,\"rainProbability\":10,"
                    + "\"wind\":\"东风2级\",\"suggestion\":\"适合游览\"}"),
            new SupportedScenario("route", "路线", "起终点，例如 郑州>洛阳；填写 default 作为兜底",
                "{\"origin\":\"郑州\",\"destination\":\"洛阳\",\"mode\":\"高铁\","
                    + "\"durationMinutes\":45,\"distanceMeters\":124000,\"summary\":\"高铁约45分钟\"}"),
            new SupportedScenario("train", "车次", "起终点，例如 郑州>洛阳；填写 default 作为兜底",
                "[{\"trainNo\":\"G5678\",\"from\":\"郑州东\",\"to\":\"洛阳龙门\","
                    + "\"departure\":\"08:20\",\"arrival\":\"09:06\",\"duration\":\"46分钟\","
                    + "\"seatHint\":\"演示数据\",\"seats\":{\"second_class\":\"有\"}}]"),
            new SupportedScenario("railFare", "铁路票价", "起终点，例如 郑州>洛阳；填写 default 作为兜底",
                "[{\"trainNo\":\"G5678\",\"from\":\"郑州东\",\"to\":\"洛阳龙门\","
                    + "\"departure\":\"08:20\",\"arrival\":\"09:06\",\"duration\":\"46分钟\","
                    + "\"trainClass\":\"高铁\",\"prices\":{\"二等座\":65,\"一等座\":104}}]"),
            new SupportedScenario("transfer", "中转换乘", "起终点，例如 郑州>洛阳；填写 default 作为兜底",
                "[{\"middleStation\":\"郑州东\",\"waitTime\":\"约35分钟\",\"totalDuration\":\"约2小时\","
                    + "\"segments\":[{\"trainNo\":\"G1001\",\"from\":\"安阳东\",\"to\":\"郑州东\","
                    + "\"departure\":\"08:00\",\"arrival\":\"08:40\",\"duration\":\"40分钟\","
                    + "\"seats\":{\"二等座\":\"有\"}}]}]")
        );
    }

    private java.util.Set<String> supportedKeys() {
        return supported().stream().map(SupportedScenario::key)
            .collect(java.util.stream.Collectors.toCollection(java.util.LinkedHashSet::new));
    }

    private static String cleanKey(String value) {
        return clean(value, "数据类型不能为空").toLowerCase(java.util.Locale.ROOT);
    }

    private static String cleanMatch(String value) {
        return value == null || value.isBlank() ? DEFAULT_MATCH : value.trim();
    }

    private static String clean(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
        }
        return value.trim();
    }

    private static String truncate(String value, int max) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() <= max ? trimmed : trimmed.substring(0, max);
    }

    public record SupportedScenario(String key, String displayName, String matchHint, String sampleJson) {
    }

    public record ScenarioView(UUID id, String scenarioKey, String matchKey, String name,
                               String payloadJson, String note, boolean enabled,
                               java.time.Instant updatedAt) {
    }

    public record MockCatalogView(List<SupportedScenario> supported, List<ScenarioView> scenarios) {
    }
}
