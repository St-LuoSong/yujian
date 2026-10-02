package com.yujian.travel.tools;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.service.DemoScenarioService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.Optional;

/**
 * 本地演示数据。
 *
 * 只在真实数据源不可用时使用，并且必须在 source 与 errorCode 上留下痕迹，
 * 不允许静默冒充实时数据。
 */
@Component
public class MockTravelTools {
    private static final Logger log = LoggerFactory.getLogger(MockTravelTools.class);

    private final DemoScenarioService demoScenarios;
    private final ObjectMapper objectMapper;

    /** 测试可用的无参构造：不读数据库，只返回内置样例。 */
    public MockTravelTools() {
        this(null, new ObjectMapper());
    }

    @Autowired
    public MockTravelTools(DemoScenarioService demoScenarios, ObjectMapper objectMapper) {
        this.demoScenarios = demoScenarios;
        this.objectMapper = objectMapper;
    }

    public ToolResult<ToolModels.WeatherInfo> getWeather(String city, String date) {
        String normalized = normalizeCity(city);
        Optional<ToolModels.WeatherInfo> override =
            override("weather", normalized, ToolModels.WeatherInfo.class);
        if (override.isPresent()) {
            return ToolResult.mock(override.get(), "天气演示数据（运营台配置）");
        }
        ToolModels.WeatherInfo weather = switch (normalized) {
            case "开封" -> new ToolModels.WeatherInfo("开封", defaultDate(date), "多云", 17, 25, 20,
                "东南风2级", "适合城市漫游和夜游，晚间注意保暖");
            case "云台山" -> new ToolModels.WeatherInfo("云台山", defaultDate(date), "小雨", 15, 22, 60,
                "东北风3级", "雨天山路湿滑，建议准备室内替代方案");
            default -> new ToolModels.WeatherInfo("洛阳", defaultDate(date), "晴", 18, 26, 10,
                "东风2级", "适合石窟和户外游览，注意早晚温差");
        };
        return ToolResult.mock(weather, "天气演示数据");
    }

    public ToolResult<ToolModels.RouteInfo> getRoute(String origin, String destination, String mode) {
        String from = defaultText(origin, "郑州");
        String to = normalizeCity(destination);
        Optional<ToolModels.RouteInfo> override =
            override("route", from + ">" + to, ToolModels.RouteInfo.class);
        if (override.isPresent()) {
            return ToolResult.mock(override.get(), "路线演示数据（运营台配置）");
        }
        ToolModels.RouteInfo route = switch (to) {
            case "开封" -> new ToolModels.RouteInfo(from, "开封", defaultText(mode, "高铁"),
                35, 72_000, "郑州东至开封北约35分钟，抵达后建议公共交通接驳");
            case "云台山" -> new ToolModels.RouteInfo(from, "云台山", defaultText(mode, "城际巴士"),
                120, 105_000, "郑州至云台山约2小时，建议预留景区换乘时间");
            default -> new ToolModels.RouteInfo(from, "洛阳", defaultText(mode, "高铁"),
                45, 124_000, "郑州东至洛阳龙门约45分钟，高铁站至景区需额外接驳");
        };
        return ToolResult.mock(route, "路线演示数据");
    }

    /**
     * 铁路时刻表参考数据。
     *
     * 12306 没有提供公开的授权查询接口，本项目不抓取网页，因此这里给出的是
     * 参考车次并明确标注为非实时；购票一律引导到铁路官方渠道。
     */
    public ToolResult<List<ToolModels.TrainInfo>> searchTrain(String origin, String destination, String date) {
        String to = normalizeCity(destination);
        String from = defaultText(origin, "郑州东");
        Optional<List<ToolModels.TrainInfo>> override = overrideList(
            "train", from + ">" + to, new TypeReference<>() { });
        if (override.isPresent()) {
            return ToolResult.mock(override.get(), "铁路时刻表演示数据（运营台配置）");
        }
        List<ToolModels.TrainInfo> trains = to.equals("开封")
            ? List.of(new ToolModels.TrainInfo("G1234", from, "开封北",
            "08:10", "08:46", "36分钟", "参考车次，购票请前往铁路官方渠道",
            Map.of("second_class", "有", "first_class", "有")))
            : to.equals("云台山")
            ? List.of(new ToolModels.TrainInfo("C2901", from, "修武西",
            "07:40", "08:25", "45分钟", "参考车次，购票请前往铁路官方渠道",
            Map.of("second_class", "有")))
            : List.of(new ToolModels.TrainInfo("G5678", from, "洛阳龙门",
            "08:20", "09:06", "46分钟", "参考车次，购票请前往铁路官方渠道",
            Map.of("second_class", "有", "first_class", "有")));
        return ToolResult.mock(trains, "铁路时刻表参考（非实时）");
    }

    /**
     * 铁路参考票价。
     *
     * 这些数字只用于离线演示与预算下限校验，来源必须是“参考”，不能跟着实时车次
     * 一起冒充官方价格。真实票价由 12306 MCP 的 query-ticket-price 提供。
     */
    public ToolResult<List<ToolModels.RailFare>> quoteRailFares(String origin, String destination, String date) {
        String to = normalizeCity(destination);
        String from = defaultText(origin, "郑州东");
        Optional<List<ToolModels.RailFare>> override = overrideList(
            "railFare", from + ">" + to, new TypeReference<>() { });
        if (override.isPresent()) {
            return ToolResult.mock(override.get(), "铁路票价演示数据（运营台配置）");
        }
        List<ToolModels.RailFare> fares = to.equals("开封")
            ? List.of(new ToolModels.RailFare("G1234", from, "开封北", "08:10", "08:46",
            "36分钟", "高铁", Map.of("二等座", 25, "一等座", 40)))
            : to.equals("云台山")
            ? List.of(new ToolModels.RailFare("C2901", from, "修武西", "07:40", "08:25",
            "45分钟", "城际", Map.of("二等座", 30)))
            : List.of(new ToolModels.RailFare("G5678", from, "洛阳龙门", "08:20", "09:06",
            "46分钟", "高铁", Map.of("二等座", 65, "一等座", 104)));
        return ToolResult.mock(fares, "铁路票价参考（非实时）");
    }

    /** 离线演示用的一个中转样例，明确标注为演示数据。 */
    public ToolResult<List<ToolModels.RailTransfer>> searchTransfer(String origin, String destination, String date) {
        String from = defaultText(origin, "郑州");
        String to = normalizeCity(destination);
        Optional<List<ToolModels.RailTransfer>> override = overrideList(
            "transfer", from + ">" + to, new TypeReference<>() { });
        if (override.isPresent()) {
            return ToolResult.mock(override.get(), "铁路中转演示数据（运营台配置）");
        }
        if (from.contains(to)) {
            return ToolResult.mock(List.of(), "铁路中转演示数据");
        }
        ToolModels.RailTransfer transfer = new ToolModels.RailTransfer("郑州东", "约 35 分钟", "约 2 小时",
            List.of(
                new ToolModels.RailTransferSegment("G1001", from, "郑州东", "08:00", "08:40",
                    "40分钟", Map.of("二等座", "有")),
                new ToolModels.RailTransferSegment("G2001", "郑州东", to, "09:15", "10:10",
                    "55分钟", Map.of("二等座", "有"))));
        return ToolResult.mock(List.of(transfer), "铁路中转演示数据");
    }

    private <T> Optional<T> override(String scenarioKey, String matchKey, Class<T> type) {
        if (demoScenarios == null) {
            return Optional.empty();
        }
        return demoScenarios.lookup(scenarioKey, matchKey).flatMap(json -> {
            try {
                return Optional.ofNullable(objectMapper.readValue(json, type));
            } catch (Exception exception) {
                log.warn("演示数据覆盖无法解析，已回退内置样例：{} / {}",
                    scenarioKey, matchKey);
                return Optional.empty();
            }
        });
    }

    private <T> Optional<T> overrideList(String scenarioKey, String matchKey, TypeReference<T> type) {
        if (demoScenarios == null) {
            return Optional.empty();
        }
        return demoScenarios.lookup(scenarioKey, matchKey).flatMap(json -> {
            try {
                return Optional.ofNullable(objectMapper.readValue(json, type));
            } catch (Exception exception) {
                log.warn("演示数据覆盖无法解析，已回退内置样例：{} / {}",
                    scenarioKey, matchKey);
                return Optional.empty();
            }
        });
    }

    private String normalizeCity(String city) {
        if (city == null || city.isBlank()) {
            return "洛阳";
        }
        if (city.contains("开封")) {
            return "开封";
        }
        if (city.contains("云台") || city.contains("焦作")) {
            return "云台山";
        }
        return "洛阳";
    }

    private String defaultDate(String date) {
        return date == null || date.isBlank() ? "周末" : date;
    }

    private String defaultText(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }
}
