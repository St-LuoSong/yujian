package com.yujian.travel.tools;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.domain.ToolInvocationLog;
import com.yujian.travel.repository.ToolInvocationLogRepository;
import com.yujian.travel.service.PlanDates;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.function.Supplier;
import java.util.stream.Collectors;

/**
 * 工具编排：一次规划需要哪些外部依据、按什么顺序取、取不到怎么降级、事后如何复盘。
 *
 * 这里只依赖 {@link TravelToolPort}，因此"系统资料 / 真实接口 / 缓存 / 演示降级"
 * 的来源差异全部由端口实现负责，编排层只做两件事：如实记录，如实提示。
 */
@Service
public class ToolOrchestrator {
    private static final String DEFAULT_ORIGIN = "郑州";
    /**
     * 多天行程里第 N 天天气的工具键。
     *
     * 第 1 天仍然叫 "getWeather"：TripPlanValidator 与警告文案都按这个名字取数据，
     * 后面的天数用 "getWeather:第2天" 这样的键，既能在工具轨迹里分开看，
     * 也不会让第一天的既有链路失效。
     */
    private static final String WEATHER_KEY = "getWeather";

    private static final Map<String, String> TOOL_LABELS = Map.of(
        "searchPoi", "景点检索",
        "getWeather", "天气",
        "getRoute", "路线",
        "searchTrain", "车次",
        "quoteRailFares", "铁路票价",
        "searchTransfer", "中转换乘",
        "checkAttractionOpening", "开放时间",
        "quoteTicketPrices", "门票价格");

    private final TravelToolPort travelTools;
    private final ToolInvocationLogRepository invocationLogRepository;
    private final ToolHealth toolHealth;

    public ToolOrchestrator(TravelToolPort travelTools, ToolInvocationLogRepository invocationLogRepository,
                            ToolHealth toolHealth) {
        this.travelTools = travelTools;
        this.invocationLogRepository = invocationLogRepository;
        this.toolHealth = toolHealth;
    }

    public ToolCollection collect(TravelModels.PlanRequest request) {
        long startedAt = System.nanoTime();
        UUID correlationId = UUID.randomUUID();
        Map<String, ToolResult<?>> results = new LinkedHashMap<>();
        Map<String, String> inputs = new LinkedHashMap<>();
        String destination = inferDestination(request);
        String origin = defaultText(request.origin(), DEFAULT_ORIGIN);
        // 日期由用户选的出发日决定。此前这里写死"周末"，于是用户选了 10-02，
        // 天气却按今天（10-01）取，方案里出现"10-01 小雨"这种对不上的时间戳。
        LocalDate start = PlanDates.resolveStartDate(request.startDate());
        int days = PlanDates.resolveDays(request.days());

        call(results, inputs, "searchPoi", destination + " / " + defaultText(request.interests(), "未指定兴趣"),
            () -> travelTools.searchPoi(request.interests(), destination));
        // 每天各查一次天气：方案里有几天，就必须有几天对应的预报，
        // 否则模型只能拿第一天的天气去描述整段行程。
        for (int index = 0; index < days; index++) {
            LocalDate date = start.plusDays(index);
            String key = weatherKey(index);
            call(results, inputs, key, destination + " / " + date.format(PlanDates.ISO),
                () -> travelTools.getWeather(destination, date.format(PlanDates.ISO)));
        }
        call(results, inputs, "getRoute", origin + " -> " + destination + " / " + defaultText(request.transport(), "未指定交通"),
            () -> travelTools.getRoute(origin, destination, request.transport()));
        call(results, inputs, "searchTrain", origin + " -> " + destination + " / " + start.format(PlanDates.ISO),
            () -> travelTools.searchTrain(origin, destination, start.format(PlanDates.ISO)));
        // 票价与余票来自两个 12306 工具：余票决定"能不能走"，票价决定"要花多少钱"。
        // 分成两条工具轨迹后，任何一条失败都不会把另一条误标成实时。
        call(results, inputs, "quoteRailFares", origin + " -> " + destination + " / " + start.format(PlanDates.ISO),
            () -> travelTools.quoteRailFares(origin, destination, start.format(PlanDates.ISO)));
        call(results, inputs, "searchTransfer", origin + " -> " + destination + " / " + start.format(PlanDates.ISO),
            () -> travelTools.searchTransfer(origin, destination, start.format(PlanDates.ISO)));
        call(results, inputs, "checkAttractionOpening", destination,
            () -> travelTools.checkOpening(destination));
        // 门票价格跟着景点检索的结果走：既省一次查询，也保证"这些价就是这几个景点的价"。
        List<TravelModels.Poi> pois = poiData(results.get("searchPoi"));
        call(results, inputs, "quoteTicketPrices", destination + " / " + pois.size() + " 个景点",
            () -> travelTools.quoteTicketPrices(pois, destination));

        long durationMs = (System.nanoTime() - startedAt) / 1_000_000;
        // 先算数据再算提示：提示语依赖各项的真实状态，顺序反了就会写出不诚实的文案。
        ToolCollection collected = new ToolCollection(correlationId, results, inputs, List.of(), durationMs);
        return new ToolCollection(correlationId, results, inputs, warningsFor(collected), durationMs);
    }

    @Transactional
    public void record(UUID tripPlanId, ToolCollection collection) {
        List<ToolInvocationLog> logs = new ArrayList<>();
        for (Map.Entry<String, ToolResult<?>> entry : collection.results().entrySet()) {
            ToolResult<?> result = entry.getValue();
            ToolInvocationLog log = new ToolInvocationLog();
            log.setTripPlanId(tripPlanId);
            log.setCorrelationId(collection.correlationId());
            log.setToolName(entry.getKey());
            log.setSource(result.source());
            log.setDataStatus(result.dataStatus());
            log.setSuccess(result.success());
            log.setInputSummary(truncate(collection.inputs().get(entry.getKey()), 500));
            log.setOutputSummary(truncate(summarize(result), 1000));
            log.setErrorCode(result.errorCode());
            log.setDurationMs(collection.durationMs());
            logs.add(log);
        }
        invocationLogRepository.saveAll(logs);
    }

    /**
     * 提示语必须和真实来源一致：降级了就说降级了，并指明是哪一项、去哪里看原因。
     * 全部来自真实接口时不添加噪音，用户可以在"依据"页看到每一条的来源与状态。
     */
    private List<String> warningsFor(ToolCollection collection) {
        List<String> warnings = new ArrayList<>();
        if (collection.degradedCount() > 0) {
            warnings.add("本次方案中" + label(collection, true) + "未取到实时数据，已用演示数据兜底，"
                + "原因见「依据」页。正式出行前请通过官方渠道核验。");
        } else if (collection.mockCount() > 0) {
            warnings.add("本次方案中" + label(collection, false) + "为演示数据，正式出行前请通过官方渠道核验。");
        }
        if (collection.errorCount() > 0) {
            warnings.add("有 " + collection.errorCount() + " 项外部数据未能获取，方案中相关内容已省略或使用参考值。");
        }
        return warnings;
    }

    /**
     * 人类可读的输出摘要。
     *
     * 「依据」页是直接给用户和评委看的，把记录的 toString 原样丢过去既难读也没有信息量，
     * 所以每种数据都压成一行：城市与温度、里程与耗时、车次与时刻。
     */
    private static String summarize(ToolResult<?> result) {
        Object data = result.data();
        if (data == null) {
            return result.errorMessage() == null ? "本次没有取到数据" : result.errorMessage();
        }
        if (data instanceof ToolModels.WeatherInfo weather) {
            return weather.city() + " " + weather.date() + " " + weather.condition() + " "
                + weather.minTemperature() + "—" + weather.maxTemperature() + "℃，降水概率 "
                + weather.rainProbability() + "%";
        }
        if (data instanceof ToolModels.RouteInfo route) {
            return route.origin() + " → " + route.destination() + "（" + route.mode() + "）约 "
                + route.durationMinutes() + " 分钟 / " + Math.round(route.distanceMeters() / 1000d) + " 公里";
        }
        if (data instanceof List<?> list) {
            return summarizeList(list);
        }
        return String.valueOf(data);
    }

    private static String summarizeList(List<?> list) {
        if (list.isEmpty()) {
            return "本次没有匹配到内容";
        }
        return list.stream().limit(5).map(ToolOrchestrator::summarizeItem)
            .collect(Collectors.joining("；"));
    }

    private static String summarizeItem(Object item) {
        if (item instanceof ToolModels.WeatherInfo weather) {
            return weather.city() + " " + weather.date() + " " + weather.condition() + " "
                + weather.minTemperature() + "—" + weather.maxTemperature() + "℃，降水概率 "
                + weather.rainProbability() + "%";
        }
        if (item instanceof ToolModels.TrainInfo train) {
            return train.trainNo() + " " + train.from() + " → " + train.to() + " " + train.departure()
                + "-" + train.arrival();
        }
        if (item instanceof ToolModels.RailFare fare) {
            return fare.trainNo() + " " + fare.from() + " → " + fare.to()
                + " " + fare.prices().entrySet().stream()
                .map(entry -> entry.getKey() + " ¥" + entry.getValue())
                .collect(Collectors.joining(" / "));
        }
        if (item instanceof ToolModels.RailTransfer transfer) {
            return transfer.middleStation() + " 中转，等待 " + transfer.waitTime()
                + "，全程 " + transfer.totalDuration();
        }
        if (item instanceof ToolModels.OpeningInfo opening) {
            return opening.poiName() + " " + opening.openingHours()
                + (opening.requiresReservation() ? "（需预约）" : "");
        }
        if (item instanceof TravelModels.Poi poi) {
            return poi.name() + (poi.ticketFrom() <= 0 ? "" : "（门票参考 " + poi.ticketFrom() + " 元起）");
        }
        return String.valueOf(item);
    }

    private static String label(ToolCollection collection, boolean degradedOnly) {
        return collection.results().entrySet().stream()
            .filter(entry -> entry.getValue().isMock())
            .filter(entry -> !degradedOnly || entry.getValue().errorCode() != null)
            .map(entry -> toolLabel(entry.getKey()))
            .collect(Collectors.joining("、"));
    }

    /**
     * 工具键到人话的映射。
     *
     * "getWeather:第2天" 这种带天数的键要显示成"天气（第2天）"，
     * 而不是把内部键名直接写到用户能看到的警告里。
     */
    private static String toolLabel(String key) {
        int cut = key.indexOf(':');
        String base = cut < 0 ? key : key.substring(0, cut);
        String label = TOOL_LABELS.getOrDefault(base, base);
        return cut < 0 ? label : label + "（" + key.substring(cut + 1) + "）";
    }

    /** 第 1 天沿用 getWeather，后续天数带上天号，便于在工具轨迹里逐日核对。 */
    private static String weatherKey(int index) {
        return index == 0 ? WEATHER_KEY : WEATHER_KEY + ":第" + (index + 1) + "天";
    }

    private void call(Map<String, ToolResult<?>> results, Map<String, String> inputs, String toolName,
                      String inputSummary, Supplier<ToolResult<?>> supplier) {
        inputs.put(toolName, inputSummary);
        results.put(toolName, measure(toolName, supplier));
    }

    private ToolResult<?> measure(String toolName, Supplier<ToolResult<?>> supplier) {
        long startedAt = System.nanoTime();
        ToolResult<?> result;
        try {
            result = supplier.get();
        } catch (Exception exception) {
            // 端口实现内部已经做了降级；能抛到这里说明是未预料的异常，仍然如实记为失败而不是静默吞掉。
            result = ToolResult.error(toolLabel(toolName) + "工具",
                "TOOL_FAILED", describe(exception));
        }
        // 健康度按"有没有 errorCode"判定：降级也算没接上，这正是运营台要看到的信号。
        toolHealth.record(toolName, result, (System.nanoTime() - startedAt) / 1_000_000);
        return result;
    }

    /** 门票价格复用景点检索的返回值；取不到就返回空列表，让价格端口自己按城市兜底。 */
    private static List<TravelModels.Poi> poiData(ToolResult<?> result) {
        if (result != null && result.data() instanceof List<?> list) {
            return list.stream()
                .filter(TravelModels.Poi.class::isInstance)
                .map(TravelModels.Poi.class::cast)
                .toList();
        }
        return List.of();
    }

    private static String describe(Exception exception) {
        String message = exception.getMessage();
        return message == null || message.isBlank() ? exception.getClass().getSimpleName() : message;
    }

    private String inferDestination(TravelModels.PlanRequest request) {
        if (request.destination() != null && !request.destination().isBlank()) {
            return request.destination();
        }
        String prompt = request.prompt() == null ? "" : request.prompt();
        if (prompt.contains("开封")) {
            return "开封";
        }
        if (prompt.contains("云台")) {
            return "云台山";
        }
        return "洛阳";
    }

    private static String defaultText(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private static String truncate(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}

