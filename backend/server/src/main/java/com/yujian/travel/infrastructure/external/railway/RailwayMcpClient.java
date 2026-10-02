package com.yujian.travel.infrastructure.external.railway;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.HttpJsonClient;
import com.yujian.travel.tools.ToolModels;
import org.springframework.stereotype.Component;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Pattern;

/**
 * 12306 车次适配器：通过 Model Context Protocol 调用独立部署的 mcp-server-12306。
 *
 * 分层原则（这也是整个工具层的规矩）：
 * 1. **12306 只由它自己负责**——车次、余票、票价、经停全部来自 MCP 服务，
 *    本项目不抓网页、不存证件、不代购，只做"查询 + 如实标注 + 失败降级"；
 * 2. MCP 服务是独立进程/容器，Spring Boot 通过 Streamable HTTP 调它，
 *    APK 永远拿不到它的地址，更拿不到任何凭证；
 * 3. 取不到就带 errorCode 降级成参考时刻表，绝不让规划失败。
 *
 * 协议实现只覆盖我们真正需要的三步：initialize → notifications/initialized → tools/call，
 * 并处理会话过期（HTTP 404 或会话头失效）后重试一次。
 */
@Component
public class RailwayMcpClient {
    /** 首版没有独立日期字段，没有明确日期时按"明日"查询车次。 */
    private static final int DEFAULT_DAYS_AHEAD = 1;
    private static final DateTimeFormatter DATE = DateTimeFormatter.ISO_LOCAL_DATE;
    private static final Pattern ISO_DATE = Pattern.compile("\\d{4}-\\d{2}-\\d{2}");
    private static final String CLIENT_NAME = "yujian-travel-server";
    private static final String CLIENT_VERSION = "0.2.0";
    /** 协议版本只在握手时声明；服务端会自动协商，声明得比它新也不会被拒绝。 */
    private static final String PROTOCOL_VERSION = "2025-06-18";

    private final HttpJsonClient httpJsonClient;
    private final AppProperties properties;
    private final ObjectMapper objectMapper;
    private final AtomicInteger requestIds = new AtomicInteger(1);
    private final AtomicReference<String> sessionId = new AtomicReference<>();

    public RailwayMcpClient(HttpJsonClient httpJsonClient, AppProperties properties, ObjectMapper objectMapper) {
        this.httpJsonClient = httpJsonClient;
        this.properties = properties;
        this.objectMapper = objectMapper;
    }

    public boolean configured() {
        String url = properties.getTools().getRailway().getMcpUrl();
        return url != null && !url.isBlank();
    }

    /** 查询指定日期、指定区间的车次与余票。 */
    public List<ToolModels.TrainInfo> queryTickets(String origin, String destination, String date,
                                                   int timeoutSeconds) {
        String travelDate = resolveDate(date);
        Map<String, Object> arguments = new LinkedHashMap<>();
        arguments.put("from_station", origin);
        arguments.put("to_station", destination);
        arguments.put("train_date", travelDate);

        String text = callTool("query-tickets", arguments, timeoutSeconds);
        return parseTrains(text, travelDate);
    }

    /** 查询指定区间的官方票价；不返回车次余票，余票仍由 query-tickets 负责。 */
    public List<ToolModels.RailFare> queryFares(String origin, String destination, String date,
                                                int timeoutSeconds) {
        String travelDate = resolveDate(date);
        Map<String, Object> arguments = new LinkedHashMap<>();
        arguments.put("from_station", origin);
        arguments.put("to_station", destination);
        arguments.put("train_date", travelDate);
        arguments.put("purpose_codes", "ADULT");

        String text = callTool("query-ticket-price", arguments, timeoutSeconds);
        return parseFares(text);
    }

    /** 查询一次换乘方案；结果只作为规划参考，购票仍在官方渠道完成。 */
    public List<ToolModels.RailTransfer> queryTransfers(String origin, String destination, String date,
                                                        int timeoutSeconds) {
        String travelDate = resolveDate(date);
        Map<String, Object> arguments = new LinkedHashMap<>();
        arguments.put("from_station", origin);
        arguments.put("to_station", destination);
        arguments.put("train_date", travelDate);
        arguments.put("isShowWZ", "N");
        arguments.put("purpose_codes", "00");

        String text = callTool("query-transfer", arguments, timeoutSeconds);
        return parseTransfers(text);
    }

    /** 把"周末/今日/空"这类口语日期落成 12306 能接受的 yyyy-MM-dd。 */
    public static String resolveDate(String date) {
        if (date != null && ISO_DATE.matcher(date.trim()).matches()) {
            return date.trim();
        }
        return LocalDate.now().plusDays(DEFAULT_DAYS_AHEAD).format(DATE);
    }

    private String callTool(String name, Map<String, Object> arguments, int timeoutSeconds) {
        try {
            return invoke(name, arguments, timeoutSeconds);
        } catch (ExternalServiceException exception) {
            // 会话过期（服务端重启或超过空闲时间）只重试一次：重新握手再调一次。
            if (!isSessionFailure(exception)) {
                throw exception;
            }
            sessionId.set(null);
            return invoke(name, arguments, timeoutSeconds);
        }
    }

    private static boolean isSessionFailure(ExternalServiceException exception) {
        String code = exception.getCode();
        return "RAILWAY_MCP_HTTP_404".equals(code) || "RAILWAY_MCP_HTTP_400".equals(code)
            || "RAILWAY_MCP_NO_SESSION".equals(code);
    }

    private String invoke(String name, Map<String, Object> arguments, int timeoutSeconds) {
        String url = properties.getTools().getRailway().getMcpUrl();
        if (url == null || url.isBlank()) {
            throw new ExternalServiceException("RAILWAY_MCP_NOT_CONFIGURED", "未配置 12306 MCP 服务地址");
        }
        String session = ensureSession(url, timeoutSeconds);

        ObjectNode params = objectMapper.createObjectNode();
        params.put("name", name);
        params.set("arguments", objectMapper.valueToTree(arguments));
        HttpJsonClient.Exchange exchange = post(url, "tools/call", params, session, timeoutSeconds);
        JsonNode response = json(exchange);
        JsonNode error = response.path("error");
        if (!error.isMissingNode() && !error.isNull()) {
            throw new ExternalServiceException("RAILWAY_MCP_ERROR",
                "12306 MCP 返回错误：" + error.path("message").asText("未知错误"));
        }
        JsonNode result = response.path("result");
        if (result.path("isError").asBoolean(false)) {
            throw new ExternalServiceException("RAILWAY_MCP_TOOL_ERROR",
                "12306 MCP 工具执行失败：" + firstText(result).orElse("未提供原因"));
        }
        String text = firstText(result).orElseThrow(() -> new ExternalServiceException(
            "RAILWAY_MCP_EMPTY", "12306 MCP 没有返回车次内容"));
        return text;
    }

    /** 握手：拿到会话头之后，后续请求都要带上它。 */
    private String ensureSession(String url, int timeoutSeconds) {
        String existing = sessionId.get();
        if (existing != null) {
            return existing;
        }
        ObjectNode capabilities = objectMapper.createObjectNode();
        ObjectNode params = objectMapper.createObjectNode();
        params.put("protocolVersion", PROTOCOL_VERSION);
        params.set("capabilities", capabilities);
        ObjectNode clientInfo = objectMapper.createObjectNode();
        clientInfo.put("name", CLIENT_NAME);
        clientInfo.put("version", CLIENT_VERSION);
        params.set("clientInfo", clientInfo);

        HttpJsonClient.Exchange exchange = post(url, "initialize", params, null, timeoutSeconds);
        JsonNode response = json(exchange);
        if (!response.path("error").isMissingNode() && !response.path("error").isNull()) {
            throw new ExternalServiceException("RAILWAY_MCP_HANDSHAKE",
                "12306 MCP 握手失败：" + response.path("error").path("message").asText("未知错误"));
        }
        String session = exchange.header("Mcp-Session-Id");
        if (session == null || session.isBlank()) {
            // 无状态部署允许不返回会话头，此时按"空会话"继续调用即可。
            session = "";
        }
        sessionId.set(session);
        notifyInitialized(url, session, timeoutSeconds);
        return session;
    }

    /** 通知类请求没有 id，也不该因为失败就中断业务：拿不到响应只意味着少一次确认。 */
    private void notifyInitialized(String url, String session, int timeoutSeconds) {
        try {
            ObjectNode params = objectMapper.createObjectNode();
            post(url, "notifications/initialized", params, session, timeoutSeconds);
        } catch (RuntimeException ignored) {
            // 通知失败不改变"已拿到会话"的事实，真正的失败会在 tools/call 暴露。
        }
    }

    private HttpJsonClient.Exchange post(String url, String method, JsonNode params, String session,
                                         int timeoutSeconds) {
        ObjectNode request = objectMapper.createObjectNode();
        request.put("jsonrpc", "2.0");
        boolean notification = method.startsWith("notifications/");
        if (!notification) {
            request.put("id", requestIds.getAndIncrement());
        }
        request.put("method", method);
        request.set("params", params);

        Map<String, String> headers = new LinkedHashMap<>();
        if (session != null && !session.isBlank()) {
            headers.put("Mcp-Session-Id", session);
        }
        HttpJsonClient.Exchange exchange = httpJsonClient.postJson(url, request.toString(), headers, timeoutSeconds);
        if (!exchange.successful() && !(notification && exchange.status() == 202)) {
            throw new ExternalServiceException("RAILWAY_MCP_HTTP_" + exchange.status(),
                "12306 MCP 返回 " + exchange.status());
        }
        return exchange;
    }

    /**
     * 响应可能是普通 JSON，也可能是 `text/event-stream`（MCP Streamable HTTP 允许两者）。
     * SSE 模式下取最后一条带 result/error 的 data 事件。
     */
    private JsonNode json(HttpJsonClient.Exchange exchange) {
        String body = exchange.body() == null ? "" : exchange.body().trim();
        if (body.isEmpty()) {
            return objectMapper.createObjectNode();
        }
        if (body.startsWith("{")) {
            return httpJsonClient.parse(body);
        }
        JsonNode last = null;
        for (String line : body.split("\\r?\\n")) {
            String trimmed = line.trim();
            if (!trimmed.startsWith("data:")) {
                continue;
            }
            String payload = trimmed.substring("data:".length()).trim();
            if (payload.isEmpty() || "[DONE]".equals(payload)) {
                continue;
            }
            try {
                JsonNode node = httpJsonClient.parse(payload);
                if (node.has("result") || node.has("error")) {
                    last = node;
                }
            } catch (RuntimeException ignored) {
                // 心跳或非 JSON 事件直接跳过。
            }
        }
        if (last == null) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 MCP 返回了无法识别的内容");
        }
        return last;
    }

    private static java.util.Optional<String> firstText(JsonNode result) {
        JsonNode content = result.path("content");
        if (content.isArray()) {
            for (JsonNode item : content) {
                String text = item.path("text").asText("");
                if (!text.isBlank()) {
                    return java.util.Optional.of(text);
                }
            }
        }
        String structured = result.path("structuredContent").toString();
        return structured.isBlank() || "null".equals(structured)
            ? java.util.Optional.empty() : java.util.Optional.of(structured);
    }

    /**
     * 工具返回的是 JSON 字符串：{"success":true,"trains":[{"train_no":"G1234",...}]}。
     * 这里只取我们真正会展示与校验的字段，余票信息压成一行人类可读的座席提示。
     */
    private List<ToolModels.TrainInfo> parseTrains(String text, String travelDate) {
        JsonNode payload;
        try {
            payload = httpJsonClient.parse(text);
        } catch (RuntimeException exception) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 车次内容无法解析");
        }
        if (!payload.path("success").asBoolean(true) && !payload.has("trains")) {
            throw new ExternalServiceException("RAILWAY_MCP_TOOL_ERROR",
                payload.path("message").asText("12306 查询未成功"));
        }
        return trainsFrom(payload, travelDate);
    }

    static List<ToolModels.TrainInfo> trainsFrom(JsonNode payload, String travelDate) {
        JsonNode trains = payload.path("trains");
        if (!trains.isArray()) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 车次内容缺少 trains 字段");
        }
        List<ToolModels.TrainInfo> results = new ArrayList<>();
        for (JsonNode train : trains) {
            String trainNo = train.path("train_no").asText("");
            if (trainNo.isBlank()) {
                continue;
            }
            Map<String, String> seats = seatsFrom(train.path("seats"));
            results.add(new ToolModels.TrainInfo(
                trainNo,
                train.path("from_station").asText(""),
                train.path("to_station").asText(""),
                train.path("start_time").asText(""),
                train.path("arrive_time").asText(""),
                humanDuration(train.path("duration").asText("")),
                seatHint(train.path("seats"), travelDate),
                seats));
            if (results.size() >= 6) {
                break;
            }
        }
        return results;
    }

    private List<ToolModels.RailFare> parseFares(String text) {
        JsonNode payload;
        try {
            payload = httpJsonClient.parse(text);
        } catch (RuntimeException exception) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 票价内容无法解析");
        }
        if (!payload.path("success").asBoolean(true) && !payload.has("data")) {
            throw new ExternalServiceException("RAILWAY_MCP_TOOL_ERROR",
                payload.path("error").asText(payload.path("message").asText("12306 票价查询未成功")));
        }
        return faresFrom(payload);
    }

    static List<ToolModels.RailFare> faresFrom(JsonNode payload) {
        JsonNode rows = payload.path("data");
        if (!rows.isArray()) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 票价内容缺少 data 字段");
        }
        List<ToolModels.RailFare> results = new ArrayList<>();
        for (JsonNode row : rows) {
            String trainNo = row.path("train_code").asText("");
            if (trainNo.isBlank()) {
                continue;
            }
            Map<String, Integer> prices = new LinkedHashMap<>();
            JsonNode rawPrices = row.path("prices");
            if (rawPrices.isObject()) {
                rawPrices.fields().forEachRemaining(entry -> {
                    Integer price = priceYuan(entry.getValue().asText(""));
                    if (price != null && price > 0) {
                        prices.put(entry.getKey(), price);
                    }
                });
            }
            if (prices.isEmpty()) {
                continue;
            }
            results.add(new ToolModels.RailFare(
                trainNo,
                row.path("from_station").asText(""),
                row.path("to_station").asText(""),
                row.path("start_time").asText(""),
                row.path("arrive_time").asText(""),
                humanDuration(row.path("duration").asText("")),
                row.path("train_class_name").asText(""),
                prices));
        }
        return results;
    }

    private List<ToolModels.RailTransfer> parseTransfers(String text) {
        JsonNode payload;
        try {
            payload = httpJsonClient.parse(text);
        } catch (RuntimeException exception) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 中转内容无法解析");
        }
        if (!payload.path("success").asBoolean(true) && !payload.has("transfers")) {
            throw new ExternalServiceException("RAILWAY_MCP_TOOL_ERROR",
                payload.path("error").asText(payload.path("message").asText("12306 中转查询未成功")));
        }
        return transfersFrom(payload);
    }

    static List<ToolModels.RailTransfer> transfersFrom(JsonNode payload) {
        JsonNode rows = payload.path("transfers");
        if (!rows.isArray()) {
            throw new ExternalServiceException("RAILWAY_MCP_MALFORMED", "12306 中转内容缺少 transfers 字段");
        }
        List<ToolModels.RailTransfer> results = new ArrayList<>();
        for (JsonNode row : rows) {
            List<ToolModels.RailTransferSegment> segments = new ArrayList<>();
            JsonNode rawSegments = row.path("segments");
            if (rawSegments.isArray()) {
                for (JsonNode segment : rawSegments) {
                    String trainNo = segment.path("train_code").asText("");
                    if (trainNo.isBlank()) {
                        continue;
                    }
                    segments.add(new ToolModels.RailTransferSegment(
                        trainNo,
                        segment.path("from_station").asText(""),
                        segment.path("to_station").asText(""),
                        segment.path("start_time").asText(""),
                        segment.path("arrive_time").asText(""),
                        humanDuration(segment.path("duration").asText("")),
                        seatsFrom(segment.path("seats"))));
                }
            }
            if (segments.size() < 2) {
                continue;
            }
            results.add(new ToolModels.RailTransfer(
                row.path("middle_station").asText(""),
                row.path("wait_time").asText(""),
                humanDuration(row.path("total_duration").asText("")),
                segments));
            if (results.size() >= 3) {
                break;
            }
        }
        return results;
    }

    /** 把 MCP 返回的席别对象转成结构化映射；未知席别也保留，避免丢信息。 */
    static Map<String, String> seatsFrom(JsonNode seats) {
        if (seats == null || !seats.isObject()) {
            return Map.of();
        }
        Map<String, String> result = new LinkedHashMap<>();
        seats.fields().forEachRemaining(entry -> {
            String value = entry.getValue().asText("");
            if (!value.isBlank() && !"-".equals(value) && !"无".equals(value)) {
                result.put(entry.getKey(), value);
            }
        });
        return result;
    }

    /**
     * 12306 票价接口返回的是元字符串（例如 55.3、25），
     * 但历史接口存在以分为单位的数字，因此统一按“有小数就是元、无小数且大于 1000 视为分”处理。
     * 不确定的价格宁可返回 null，也不把 0.5 元当成 5 元写进预算。
     */
    static Integer priceYuan(String raw) {
        if (raw == null || raw.isBlank() || "--".equals(raw.trim())) {
            return null;
        }
        try {
            BigDecimal value = new BigDecimal(raw.trim());
            if (value.signum() <= 0) {
                return null;
            }
            if (raw.indexOf('.') < 0 && value.compareTo(BigDecimal.valueOf(1000)) >= 0) {
                value = value.movePointLeft(2);
            }
            return value.setScale(0, RoundingMode.HALF_UP).intValue();
        } catch (NumberFormatException exception) {
            return null;
        }
    }

    private static String humanDuration(String raw) {
        if (raw == null || raw.isBlank() || raw.contains("小时")) {
            return raw == null ? "" : raw;
        }
        String[] parts = raw.split(":");
        if (parts.length < 2) {
            return raw;
        }
        try {
            int hours = Integer.parseInt(parts[0]);
            int minutes = Integer.parseInt(parts[1]);
            return hours <= 0 ? minutes + " 分钟" : hours + " 小时 " + minutes + " 分钟";
        } catch (NumberFormatException exception) {
            return raw;
        }
    }

    /** 余票：只说事实。"有"表示官方返回有余票，"N"表示官方返回的剩余张数。 */
    private static String seatHint(JsonNode seats, String travelDate) {
        if (seats == null || !seats.isObject()) {
            return "余票以铁路官方渠道为准";
        }
        Map<String, String> labels = new LinkedHashMap<>();
        labels.put("business", "商务座");
        labels.put("first_class", "一等座");
        labels.put("second_class", "二等座");
        labels.put("soft_sleeper", "软卧");
        labels.put("hard_sleeper", "硬卧");
        labels.put("hard_seat", "硬座");
        labels.put("no_seat", "无座");
        List<String> parts = new ArrayList<>();
        for (Map.Entry<String, String> entry : labels.entrySet()) {
            String value = seats.path(entry.getKey()).asText("");
            if (value.isBlank() || "-".equals(value) || "无".equals(value)) {
                continue;
            }
            parts.add(entry.getValue() + " " + ("有".equals(value) ? "有票" : value + " 张"));
        }
        String base = parts.isEmpty() ? "未返回可售席别" : String.join(" · ", parts);
        return base + "（" + travelDate + " 官方余票，购票请前往铁路官方渠道）";
    }
}

