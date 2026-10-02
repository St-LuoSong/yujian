package com.yujian.travel.infrastructure.external.baidu;

import com.fasterxml.jackson.databind.JsonNode;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.HttpJsonClient;
import com.yujian.travel.infrastructure.external.TtlCache;
import com.yujian.travel.tools.ToolModels;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 百度地图 Web 服务适配器。
 *
 * 当前承担两件事：城市级地理编码，以及城际驾车路线（距离与耗时）。
 * 铁路耗时不在百度地图的能力范围内，由车次参考数据单独负责 —— 不把两者混为一谈。
 *
 * AK 只从服务端环境变量读取，不写进代码、不进日志、不下发到客户端。
 * 地理编码结果变化极小，做了进程内缓存以节省配额。
 */
@Component
public class BaiduMapClient {
    /** 地点坐标几乎不变，缓存一天；这里用带 TTL 的缓存而不是无界 Map，避免长跑后堆积。 */
    private static final Duration PLACE_TTL = Duration.ofHours(24);

    private final HttpJsonClient httpJsonClient;
    private final AppProperties properties;
    private final TtlCache cache;
    private final Map<String, double[]> geocodeCache = new ConcurrentHashMap<>();

    public BaiduMapClient(HttpJsonClient httpJsonClient, AppProperties properties, TtlCache cache) {
        this.httpJsonClient = httpJsonClient;
        this.properties = properties;
        this.cache = cache;
    }

    public boolean configured() {
        String key = properties.getTools().getBaidu().getApiKey();
        return key != null && !key.isBlank();
    }

    /**
     * 公开的地点解析：地点名到经纬度。
     *
     * 与路线规划里的地理编码共用同一个百度接口，但调用场景不同：
     * 地图打点需要知道"这句话是不是一个可信的地点"，因此把 confidence、level 一并返回，
     * 由调用方决定要不要画在地图上，而不是把低置信度结果当成事实。
     *
     * @param cityHint 可选的城市限定，例如"洛阳"。地址本身不带城市时能显著提高命中率。
     */
    public Optional<GeocodeResult> geocodePlace(String address, String cityHint) {
        if (address == null || address.isBlank()) {
            return Optional.empty();
        }
        String city = cityHint == null ? "" : cityHint.trim();
        String key = "baidu:geocode:" + city + ":" + address.trim();
        TtlCache.CachedResult<GeocodeResult> hit = cache.get(key, GeocodeResult.class);
        if (hit != null) {
            return Optional.of(hit.data());
        }

        Map<String, String> query = new LinkedHashMap<>();
        query.put("address", address.trim());
        if (!city.isEmpty()) {
            query.put("city", city);
        }
        query.put("output", "json");
        query.put("ak", apiKey());

        JsonNode response = httpJsonClient.get(baseUrl() + "/geocoding/v3/", query,
            properties.getTools().getTimeoutSeconds());
        ensureSuccess(response);

        JsonNode result = response.path("result");
        JsonNode location = result.path("location");
        double lat = location.path("lat").asDouble(Double.NaN);
        double lng = location.path("lng").asDouble(Double.NaN);
        if (Double.isNaN(lat) || Double.isNaN(lng)) {
            return Optional.empty();
        }
        GeocodeResult resolved = new GeocodeResult(
            result.path("level").asText(""),
            lng,
            lat,
            result.path("confidence").asInt(0),
            result.path("precise").asInt(0) == 1);
        cache.put(key, resolved, "百度地图地理编码", PLACE_TTL);
        return Optional.of(resolved);
    }

    /**
     * 一次地理编码的结果。
     *
     * confidence 是百度给出的可信度（0-100），level 是它认定的地点类型
     * （旅游景点 / 区县 / 城市 等）。地图只画可信的点，其余列进"未定位"清单。
     */
    public record GeocodeResult(String level, double lng, double lat, int confidence, boolean precise) {
    }

    /** 驾车路线作为城际移动参考；返回的 summary 会明确写成"驾车参考"。 */
    public ToolModels.RouteInfo drivingRoute(String origin, String destination, int timeoutSeconds) {
        double[] from = geocode(origin, timeoutSeconds);
        double[] to = geocode(destination, timeoutSeconds);

        JsonNode response = httpJsonClient.get(
            baseUrl() + "/directionlite/v1/driving",
            Map.of(
                "origin", from[0] + "," + from[1],
                "destination", to[0] + "," + to[1],
                "ak", apiKey()),
            timeoutSeconds);
        ensureSuccess(response);

        JsonNode route = response.path("result").path("routes").path(0);
        int distanceMeters = route.path("distance").asInt(0);
        int durationSeconds = route.path("duration").asInt(0);
        if (distanceMeters <= 0 || durationSeconds <= 0) {
            throw new ExternalServiceException("BAIDU_EMPTY_ROUTE", "百度地图未返回可用路线");
        }
        int durationMinutes = Math.max(1, durationSeconds / 60);
        String summary = "百度地图驾车参考：约 " + Math.round(distanceMeters / 1000d) + " 公里，预计 "
            + formatDuration(durationMinutes) + "；铁路出行请以车次为准";
        return new ToolModels.RouteInfo(origin, destination, "驾车（百度地图参考）",
            durationMinutes, distanceMeters, summary);
    }

    private double[] geocode(String address, int timeoutSeconds) {
        if (address == null || address.isBlank()) {
            throw new ExternalServiceException("BAIDU_ADDRESS_EMPTY", "缺少需要解析的地点名称");
        }
        return geocodeCache.computeIfAbsent(address, key -> {
            JsonNode response = httpJsonClient.get(
                baseUrl() + "/geocoding/v3/",
                Map.of("address", key, "output", "json", "ak", apiKey()),
                timeoutSeconds);
            ensureSuccess(response);
            JsonNode location = response.path("result").path("location");
            double lat = location.path("lat").asDouble(Double.NaN);
            double lng = location.path("lng").asDouble(Double.NaN);
            if (Double.isNaN(lat) || Double.isNaN(lng)) {
                throw new ExternalServiceException("BAIDU_GEOCODE_EMPTY", "无法解析地点坐标：" + key);
            }
            return new double[] {lat, lng};
        });
    }

    private void ensureSuccess(JsonNode response) {
        int status = response.path("status").asInt(-1);
        if (status != 0) {
            throw new ExternalServiceException("BAIDU_" + status, describeStatus(status));
        }
    }

    private static String describeStatus(int status) {
        return switch (status) {
            case 1 -> "百度地图服务内部错误";
            case 2 -> "百度地图请求参数不合法";
            case 3 -> "百度地图鉴权失败，请检查 AK 的权限配置";
            case 4 -> "百度地图配额已用尽";
            case 5 -> "百度地图 AK 不存在或被停用";
            default -> "百度地图返回异常状态：" + status;
        };
    }

    private static String formatDuration(int minutes) {
        if (minutes < 60) {
            return minutes + " 分钟";
        }
        int hours = minutes / 60;
        int rest = minutes % 60;
        return rest == 0 ? hours + " 小时" : hours + " 小时 " + rest + " 分钟";
    }

    private String baseUrl() {
        return properties.getTools().getBaidu().getBaseUrl();
    }

    private String apiKey() {
        return properties.getTools().getBaidu().getApiKey();
    }
}
