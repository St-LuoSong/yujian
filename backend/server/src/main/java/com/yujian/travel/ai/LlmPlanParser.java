package com.yujian.travel.ai;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.yujian.travel.api.TravelModels;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;

/**
 * 把模型返回的自由文本转成 {@link TravelModels.TripPlan}。
 *
 * 这个类刻意**不做严格的对象绑定**。真实模型不会像单元测试那样听话：
 * 它会把 `cost` 写成 `"约120元"`，把 `warnings` 写成一句话而不是数组，
 * 用 Markdown 代码块包住 JSON，或者在 JSON 前后加一句"好的，以下是行程"。
 * 这些都不是错误答案，只是格式波动；严格绑定会让整份可用方案直接报废，
 * 然后用户看到"AI 降级"。所以这里逐字段宽松取值，取不到才用默认值。
 *
 * 唯一不能容忍的是**根本拿不到 days**——那不是格式波动，而是模型没按契约办事，
 * 此时抛出的异常会带上原始输出片段，便于在运营台定位是提示词问题还是模型问题。
 */
@Component
public class LlmPlanParser {

    /** 出错时带在异常里的原文片段长度，够定位问题又不会把日志刷爆。 */
    private static final int SNIPPET_LIMIT = 400;

    private final ObjectMapper objectMapper;

    public LlmPlanParser(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    public TravelModels.TripPlan parse(String content, TravelModels.PlanRequest request) {
        JsonNode root;
        try {
            root = objectMapper.readTree(extractJson(content));
        } catch (Exception exception) {
            throw new IllegalStateException(
                "LLM 返回的行程 JSON 无法解析：" + snippet(content), exception);
        }

        List<TravelModels.TripDay> days = readDays(root);
        if (days.isEmpty()) {
            throw new IllegalStateException("LLM 行程缺少 days：" + snippet(content));
        }

        int totalCost = days.stream()
            .flatMap(day -> day.items().stream())
            .mapToInt(TravelModels.TripItem::cost)
            .sum();
        int travelers = request == null || request.travelers() == null || request.travelers() < 1
            ? 2
            : request.travelers();

        return new TravelModels.TripPlan(
            UUID.randomUUID().toString(),
            text(root, "title", "河南 AI 行程"),
            text(root, "summary", "由 AI 结合工具数据生成的河南旅行方案。"),
            text(root, "corridor", "河南"),
            text(root, "intensity", "适中"),
            totalCost,
            Math.max(1, totalCost / travelers),
            days,
            stringList(root, "warnings"),
            "AI 生成");
    }

    private List<TravelModels.TripDay> readDays(JsonNode root) {
        JsonNode node = root.get("days");
        if (node == null || !node.isArray()) {
            return List.of();
        }
        List<TravelModels.TripDay> days = new ArrayList<>();
        int index = 1;
        for (JsonNode day : node) {
            if (!day.isObject()) {
                continue;
            }
            List<TravelModels.TripItem> items = new ArrayList<>();
            JsonNode itemNodes = day.get("items");
            if (itemNodes != null && itemNodes.isArray()) {
                for (JsonNode item : itemNodes) {
                    if (item.isObject()) {
                        items.add(readItem(item));
                    }
                }
            }
            days.add(new TravelModels.TripDay(
                text(day, "label", "DAY " + index),
                text(day, "date", "待定"),
                List.copyOf(items)));
            index++;
        }
        return List.copyOf(days);
    }

    private TravelModels.TripItem readItem(JsonNode item) {
        return new TravelModels.TripItem(
            text(item, "type", "活动"),
            text(item, "title", "待定"),
            normalizeTime(text(item, "time", ""), "09:00"),
            text(item, "duration", "约2小时"),
            text(item, "transport", "公共交通"),
            text(item, "description", "AI 生成节点"),
            integer(item.get("cost"), 0),
            text(item, "source", "AI 生成"),
            "AI 生成",
            text(item, "risk", ""));
    }

    /** 取字符串字段；数字或布尔也会被当作文本取出，避免类型不符就整份失败。 */
    private String text(JsonNode node, String field, String fallback) {
        JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return fallback;
        }
        String raw = value.isValueNode() ? value.asText() : value.toString();
        return raw == null || raw.isBlank() ? fallback : raw.trim();
    }

    /**
     * 取整数字段，容忍 `"约120元"`、`"120"`、`120.0`。
     * 取不到第一个数字串时用 fallback，而不是抛异常。
     */
    private int integer(JsonNode value, int fallback) {
        if (value == null || value.isNull()) {
            return fallback;
        }
        if (value.isNumber()) {
            return value.asInt(fallback);
        }
        return firstInteger(value.asText(""), fallback);
    }

    private int firstInteger(String raw, int fallback) {
        StringBuilder digits = new StringBuilder();
        boolean negative = false;
        for (int i = 0; i < raw.length(); i++) {
            char current = raw.charAt(i);
            if (digits.length() == 0 && current == '-' && !negative) {
                negative = true;
                continue;
            }
            if (Character.isDigit(current)) {
                digits.append(current);
                continue;
            }
            if (digits.length() > 0) {
                break;
            }
        }
        if (digits.length() == 0) {
            return fallback;
        }
        try {
            int parsed = Integer.parseInt(digits.toString());
            return negative ? -parsed : parsed;
        } catch (NumberFormatException ignored) {
            return fallback;
        }
    }

    /**
     * `time` 是时钟值，不是句子。
     *
     * 真实故障：模型把"建议上午出发，具体车次以铁路官方为准"写进 time，
     * 而该列是 VARCHAR(16)，于是本该成功的生成直接 500。
     * 这里能抽出 HH:mm 就用它，抽不出才退回默认值——语义纠正放在解析层，
     * 长度兜底交给 {@link com.yujian.travel.service.ColumnText}。
     */
    private String normalizeTime(String raw, String fallback) {
        if (raw != null) {
            for (int i = 0; i < raw.length(); i++) {
                if (!Character.isDigit(raw.charAt(i))) {
                    continue;
                }
                int cursor = i;
                while (cursor < raw.length() && Character.isDigit(raw.charAt(cursor))) {
                    cursor++;
                }
                if (cursor >= raw.length() || raw.charAt(cursor) != ':') {
                    i = cursor - 1;
                    continue;
                }
                int minuteStart = cursor + 1;
                int minuteEnd = minuteStart;
                while (minuteEnd < raw.length() && Character.isDigit(raw.charAt(minuteEnd))) {
                    minuteEnd++;
                }
                if (minuteEnd > minuteStart) {
                    int hour = Integer.parseInt(raw.substring(i, cursor));
                    int minute = Integer.parseInt(raw.substring(minuteStart, minuteEnd));
                    if (hour <= 23 && minute <= 59) {
                        return String.format("%02d:%02d", hour, minute);
                    }
                }
                i = Math.max(i, minuteEnd - 1);
            }
        }
        return fallback;
    }

    /** 数组或单句都能接受：模型经常把 warnings 写成一句话。 */
    private List<String> stringList(JsonNode node, String field) {
        JsonNode value = node.get(field);
        if (value == null || value.isNull()) {
            return List.of();
        }
        if (value.isArray()) {
            List<String> items = new ArrayList<>();
            for (JsonNode element : value) {
                String text = element.isValueNode() ? element.asText() : element.toString();
                if (text != null && !text.isBlank()) {
                    items.add(text.trim());
                }
            }
            return List.copyOf(items);
        }
        if (value.isValueNode()) {
            String single = value.asText();
            return single == null || single.isBlank() ? List.of() : List.of(single.trim());
        }
        return List.of();
    }

    /**
     * 从可能带 Markdown 代码块、前后夹着说明文字的输出里取出 JSON 对象。
     * 顺带去掉对象/数组末尾的多余逗号——这是模型最常犯的语法错误。
     */
    private String extractJson(String content) {
        String cleaned = content == null ? "" : content.trim();
        cleaned = cleaned.replace("```json", "").replace("```", "");
        int start = cleaned.indexOf('{');
        int end = cleaned.lastIndexOf('}');
        if (start < 0 || end <= start) {
            throw new IllegalStateException("LLM 未返回 JSON 对象");
        }
        return removeTrailingCommas(cleaned.substring(start, end + 1));
    }

    private String removeTrailingCommas(String json) {
        StringBuilder out = new StringBuilder(json.length());
        boolean inString = false;
        boolean escaped = false;
        for (int i = 0; i < json.length(); i++) {
            char current = json.charAt(i);
            if (inString) {
                out.append(current);
                if (escaped) {
                    escaped = false;
                } else if (current == '\\') {
                    escaped = true;
                } else if (current == '"') {
                    inString = false;
                }
                continue;
            }
            if (current == '"') {
                inString = true;
                out.append(current);
                continue;
            }
            if (current == ',') {
                int next = i + 1;
                while (next < json.length() && Character.isWhitespace(json.charAt(next))) {
                    next++;
                }
                if (next < json.length() && (json.charAt(next) == '}' || json.charAt(next) == ']')) {
                    continue;
                }
            }
            out.append(current);
        }
        return out.toString();
    }

    private String snippet(String content) {
        if (content == null) {
            return "(模型没有返回任何内容)";
        }
        StringBuilder flat = new StringBuilder();
        boolean lastWasSpace = false;
        for (int i = 0; i < content.length() && flat.length() < SNIPPET_LIMIT; i++) {
            char current = content.charAt(i);
            if (Character.isWhitespace(current)) {
                if (!lastWasSpace && flat.length() > 0) {
                    flat.append(' ');
                    lastWasSpace = true;
                }
            } else {
                flat.append(current);
                lastWasSpace = false;
            }
        }
        return flat.isEmpty() ? "(模型没有返回任何内容)" : flat.toString();
    }
}
