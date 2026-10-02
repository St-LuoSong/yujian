package com.yujian.travel.infrastructure.external.weather;

import com.fasterxml.jackson.databind.JsonNode;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.HttpJsonClient;
import com.yujian.travel.tools.ToolModels;
import org.springframework.stereotype.Component;

import java.time.LocalDate;
import java.time.ZoneId;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * Open-Meteo 天气适配器。
 *
 * 选择它的原因是：**免费且无需密钥**，可以直接在比赛现场真实验证"实时数据"这条链路，
 * 而不是只能挂一个需要付费申请的数据源占位。需要换成商业天气源时，只要替换本类，
 * 端口与上层完全不用改。
 *
 * 主要支持河南范围内的城市；未知城市按洛阳处理，并在 suggestion 中不做额外承诺。
 */
@Component
public class OpenMeteoWeatherClient {
    private static final Map<String, double[]> COORDINATES = new LinkedHashMap<>();
    private static final String DAILY_FIELDS =
        "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,wind_speed_10m_max";

    static {
        COORDINATES.put("郑州", new double[] {34.7466, 113.6254});
        COORDINATES.put("洛阳", new double[] {34.6197, 112.4540});
        COORDINATES.put("开封", new double[] {34.7971, 114.3074});
        COORDINATES.put("焦作", new double[] {35.2159, 113.2418});
        COORDINATES.put("云台山", new double[] {35.4167, 113.4167});
        COORDINATES.put("登封", new double[] {34.4597, 112.9454});
        COORDINATES.put("少林寺", new double[] {34.5078, 112.9425});
        COORDINATES.put("安阳", new double[] {36.1034, 114.3931});
        COORDINATES.put("信阳", new double[] {32.1479, 114.0916});
        COORDINATES.put("南阳", new double[] {32.9908, 112.5286});
    }

    /** Open-Meteo 免费预报最多 16 天，超出就必须如实降级，不能拿今天的天气顶替。 */
    private static final int MAX_FORECAST_DAYS = 16;
    /** 没有指定日期时至少取三天，够 1—3 天行程使用。 */
    private static final int MIN_FORECAST_DAYS = 3;
    /** 与全项目一致的北京时间：跨时区部署时"今天"必须是用户眼中的今天。 */
    private static final ZoneId ZONE = ZoneId.of("Asia/Shanghai");

    private final HttpJsonClient httpJsonClient;
    private final AppProperties properties;

    public OpenMeteoWeatherClient(HttpJsonClient httpJsonClient, AppProperties properties) {
        this.httpJsonClient = httpJsonClient;
        this.properties = properties;
    }

    public ToolModels.WeatherInfo fetch(String city, String date, int timeoutSeconds) {
        String key = resolveKey(city);
        double[] coordinate = COORDINATES.getOrDefault(key, COORDINATES.get("洛阳"));

        LocalDate requested = parseDate(date);
        int forecastDays = forecastDays(requested);

        JsonNode response = httpJsonClient.get(
            properties.getTools().getWeather().getBaseUrl() + "/v1/forecast",
            Map.of(
                "latitude", String.valueOf(coordinate[0]),
                "longitude", String.valueOf(coordinate[1]),
                "daily", DAILY_FIELDS,
                "timezone", "Asia/Shanghai",
                "forecast_days", String.valueOf(forecastDays)),
            timeoutSeconds);

        JsonNode daily = response.path("daily");
        JsonNode times = daily.path("time");
        if (!times.isArray() || times.isEmpty()) {
            throw new ExternalServiceException("WEATHER_EMPTY", "天气服务未返回可用数据");
        }
        int index = pickIndex(times, requested);
        if (index < 0) {
            // 旧实现匹配不到就回 index 0，于是"10-02 出发"的方案里出现 10-01 的天气。
            // 日期对不上比没有天气更危险：这里宁可降级，也不返回一个别的日期的值。
            throw new ExternalServiceException("WEATHER_DATE_OUT_OF_RANGE",
                "天气服务暂不提供 " + date + " 的预报（当前仅覆盖未来 " + forecastDays + " 天）");
        }

        int code = daily.path("weather_code").path(index).asInt(-1);
        double max = daily.path("temperature_2m_max").path(index).asDouble(Double.NaN);
        double min = daily.path("temperature_2m_min").path(index).asDouble(Double.NaN);
        int rain = daily.path("precipitation_probability_max").path(index).asInt(0);
        double wind = daily.path("wind_speed_10m_max").path(index).asDouble(0);

        if (Double.isNaN(max) || Double.isNaN(min)) {
            throw new ExternalServiceException("WEATHER_INCOMPLETE", "天气服务返回的数据不完整");
        }

        String condition = describe(code);
        String dateLabel = times.path(index).asText(times.path(0).asText("今日"));
        return new ToolModels.WeatherInfo(
            key,
            dateLabel,
            condition,
            (int) Math.round(min),
            (int) Math.round(max),
            Math.max(0, Math.min(100, rain)),
            Math.round(wind) + " km/h",
            suggestion(condition, rain, min, max));
    }

    /** 解析客户端传来的 yyyy-MM-dd；认不出来（例如"今日"）时返回 null，按最近一天处理。 */
    private static LocalDate parseDate(String date) {
        if (date == null || date.isBlank()) {
            return null;
        }
        try {
            return LocalDate.parse(date.trim());
        } catch (DateTimeParseException ignored) {
            return null;
        }
    }

    /** 预报窗口要覆盖到用户选的出发日，否则连请求都不该发出去。 */
    private static int forecastDays(LocalDate requested) {
        if (requested == null) {
            return MIN_FORECAST_DAYS;
        }
        long offset = ChronoUnit.DAYS.between(LocalDate.now(ZONE), requested);
        return (int) Math.max(MIN_FORECAST_DAYS, Math.min(MAX_FORECAST_DAYS, offset + 1));
    }

    /** 返回 -1 表示这一天不在返回窗口里；调用方据此降级，绝不回退到别的日期。 */
    private static int pickIndex(JsonNode times, LocalDate date) {
        if (date == null) {
            return times.isEmpty() ? -1 : 0;
        }
        String wanted = date.toString();
        for (int index = 0; index < times.size(); index++) {
            if (wanted.equals(times.path(index).asText())) {
                return index;
            }
        }
        return -1;
    }

    private static String resolveKey(String city) {
        if (city == null || city.isBlank()) {
            return "洛阳";
        }
        for (String key : COORDINATES.keySet()) {
            if (city.contains(key)) {
                return key;
            }
        }
        return city;
    }

    private static String suggestion(String condition, int rain, double min, double max) {
        if (rain >= 60 || condition.contains("雨") || condition.contains("雷")) {
            return "降水概率较高，建议携带雨具并准备一条室内替代路线";
        }
        if (max >= 32) {
            return "白天气温偏高，注意防晒补水，把户外行程安排在早晚";
        }
        if (min <= 5) {
            return "早晚偏冷，注意保暖，户外活动适当缩短";
        }
        if (condition.contains("雪") || condition.contains("雾")) {
            return "能见度或路面条件可能受影响，出发前请再确认交通";
        }
        return "天气条件适合户外游览，早晚注意温差";
    }

    /** WMO Weather interpretation codes。 */
    private static String describe(int code) {
        return switch (code) {
            case 0 -> "晴";
            case 1 -> "晴间多云";
            case 2 -> "多云";
            case 3 -> "阴";
            case 45, 48 -> "雾";
            case 51, 53, 55 -> "毛毛雨";
            case 56, 57, 66, 67 -> "冻雨";
            case 61 -> "小雨";
            case 63 -> "中雨";
            case 65 -> "大雨";
            case 71 -> "小雪";
            case 73 -> "中雪";
            case 75, 77 -> "大雪";
            case 80, 81 -> "阵雨";
            case 82 -> "强阵雨";
            case 85, 86 -> "阵雪";
            case 95 -> "雷阵雨";
            case 96, 99 -> "雷暴伴冰雹";
            default -> "天气状况待确认";
        };
    }
}
