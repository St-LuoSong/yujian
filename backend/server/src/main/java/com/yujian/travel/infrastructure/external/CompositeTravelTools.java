package com.yujian.travel.infrastructure.external;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.baidu.BaiduMapClient;
import com.yujian.travel.infrastructure.external.railway.RailwayMcpClient;
import com.yujian.travel.infrastructure.external.weather.OpenMeteoWeatherClient;
import com.yujian.travel.tools.CatalogTicketPriceTools;
import com.yujian.travel.tools.CatalogTravelTools;
import com.yujian.travel.tools.MockTravelTools;
import com.yujian.travel.tools.ToolModels;
import com.yujian.travel.tools.ToolResult;
import com.yujian.travel.tools.TravelToolPort;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;

/**
 * 工具端口的总入口：优先真实数据，取不到就带原因地降级。
 *
 * 三条纪律：
 * 1. 系统自有资料（景点库、开放时间）不冒充"实时"，标注为系统资料；
 * 2. 真实接口成功才标"实时数据"或"缓存数据"；
 * 3. 任何降级都必须带上 errorCode 与可读原因，让用户、工具轨迹和运营统计都能看到。
 */
@Component
public class CompositeTravelTools implements TravelToolPort {
    private static final Duration FAILURE_BACKOFF = Duration.ofMinutes(2);

    private final CatalogTravelTools catalogTravelTools;
    private final CatalogTicketPriceTools catalogTicketPriceTools;
    private final MockTravelTools mockTravelTools;
    private final OpenMeteoWeatherClient weatherClient;
    private final BaiduMapClient baiduMapClient;
    private final RailwayMcpClient railwayMcpClient;
    private final TtlCache cache;
    private final AppProperties properties;

    public CompositeTravelTools(CatalogTravelTools catalogTravelTools,
                                CatalogTicketPriceTools catalogTicketPriceTools,
                                MockTravelTools mockTravelTools, OpenMeteoWeatherClient weatherClient,
                                BaiduMapClient baiduMapClient, RailwayMcpClient railwayMcpClient,
                                TtlCache cache, AppProperties properties) {
        this.catalogTravelTools = catalogTravelTools;
        this.catalogTicketPriceTools = catalogTicketPriceTools;
        this.mockTravelTools = mockTravelTools;
        this.weatherClient = weatherClient;
        this.baiduMapClient = baiduMapClient;
        this.railwayMcpClient = railwayMcpClient;
        this.cache = cache;
        this.properties = properties;
    }

    @Override
    public ToolResult<List<TravelModels.Poi>> searchPoi(String keyword, String city) {
        // 景点内容由运营台维护，属于系统资料，不经过第三方接口。
        return catalogTravelTools.searchPoi(keyword, city);
    }

    @Override
    public ToolResult<List<ToolModels.OpeningInfo>> checkOpening(String destination) {
        return catalogTravelTools.checkOpening(destination);
    }

    @Override
    public ToolResult<ToolModels.WeatherInfo> getWeather(String city, String date) {
        String provider = properties.getTools().getWeather().getProvider();
        if (mockMode() || "none".equalsIgnoreCase(provider == null ? "" : provider)) {
            return mockTravelTools.getWeather(city, date);
        }

        String key = "weather:" + city + ":" + date;
        TtlCache.CachedResult<ToolModels.WeatherInfo> cached = cache.get(key, ToolModels.WeatherInfo.class);
        if (cached != null) {
            return ToolResult.cached(cached.data(), cached.source(), cached.expiresAt());
        }
        if (cache.isSuppressed(key)) {
            return degradedWeather(city, date, "WEATHER_BACKOFF", "天气服务近期不可用，暂时使用演示数据");
        }

        try {
            ToolModels.WeatherInfo info = weatherClient.fetch(city, date, timeoutSeconds());
            String source = "Open-Meteo 实时天气";
            long minutes = Math.max(1, properties.getTools().getWeather().getCacheMinutes());
            cache.put(key, info, source, Duration.ofMinutes(minutes));
            return ToolResult.realtime(info, source, java.time.Instant.now().plus(Duration.ofMinutes(minutes)));
        } catch (RuntimeException exception) {
            cache.suppress(key, FAILURE_BACKOFF);
            return degradedWeather(city, date, errorCode(exception, "WEATHER_FAILED"), describe(exception));
        }
    }

    @Override
    public ToolResult<ToolModels.RouteInfo> getRoute(String origin, String destination, String mode) {
        if (mockMode()) {
            return mockTravelTools.getRoute(origin, destination, mode);
        }
        if (!baiduMapClient.configured()) {
            // 没有 AK 就不发请求：既避免无意义的等待，也让降级原因一目了然。
            ToolResult<ToolModels.RouteInfo> fallback = mockTravelTools.getRoute(origin, destination, mode);
            return ToolResult.degraded(fallback.data(), "路线演示数据", "BAIDU_NOT_CONFIGURED",
                "未配置百度地图 AK，路线距离与耗时使用演示数据");
        }

        String key = "route:" + origin + ":" + destination;
        TtlCache.CachedResult<ToolModels.RouteInfo> cached = cache.get(key, ToolModels.RouteInfo.class);
        if (cached != null) {
            return ToolResult.cached(cached.data(), cached.source(), cached.expiresAt());
        }
        if (cache.isSuppressed(key)) {
            return degradedRoute(origin, destination, mode, "BAIDU_BACKOFF", "百度地图近期调用失败，暂时使用演示数据");
        }

        try {
            ToolModels.RouteInfo route = baiduMapClient.drivingRoute(origin, destination, timeoutSeconds());
            String source = "百度地图 Web 服务";
            Duration ttl = Duration.ofHours(24);
            cache.put(key, route, source, ttl);
            return ToolResult.realtime(route, source, java.time.Instant.now().plus(ttl));
        } catch (RuntimeException exception) {
            cache.suppress(key, FAILURE_BACKOFF);
            return degradedRoute(origin, destination, mode, errorCode(exception, "BAIDU_FAILED"), describe(exception));
        }
    }

    @Override
    public ToolResult<List<ToolModels.TrainInfo>> searchTrain(String origin, String destination, String date) {
        String provider = properties.getTools().getRailway().getProvider();
        if (mockMode() || !"12306-mcp".equalsIgnoreCase(provider)) {
            // 参考时刻表：明确标注"非实时"，购票一律引导到铁路官方渠道。
            return mockTravelTools.searchTrain(origin, destination, date);
        }
        if (!railwayMcpClient.configured()) {
            return degradedTrains(origin, destination, date, "RAILWAY_MCP_NOT_CONFIGURED",
                "未配置 12306 MCP 服务地址，车次暂时使用参考数据");
        }

        String key = railwayKey(origin, destination, date);
        TtlCache.CachedResult<List<ToolModels.TrainInfo>> cached = cachedTrains(key);
        if (cached != null) {
            return ToolResult.cached(cached.data(), cached.source(), cached.expiresAt());
        }
        if (cache.isSuppressed(key)) {
            return degradedTrains(origin, destination, date, "RAILWAY_BACKOFF",
                "12306 MCP 近期调用失败，车次暂时使用参考数据");
        }

        try {
            List<ToolModels.TrainInfo> trains = railwayMcpClient.queryTickets(origin, destination, date,
                timeoutSeconds());
            String source = "12306 MCP（" + RailwayMcpClient.resolveDate(date) + " 官方车次与余票）";
            Duration ttl = Duration.ofMinutes(Math.max(1, properties.getTools().getRailway().getCacheMinutes()));
            cache.put(key, trains, source, ttl);
            return ToolResult.realtime(trains, source, java.time.Instant.now().plus(ttl));
        } catch (RuntimeException exception) {
            cache.suppress(key, FAILURE_BACKOFF);
            return degradedTrains(origin, destination, date, errorCode(exception, "RAILWAY_MCP_FAILED"),
                describe(exception));
        }
    }

    @Override
    public ToolResult<List<ToolModels.RailFare>> quoteRailFares(String origin, String destination, String date) {
        String provider = properties.getTools().getRailway().getProvider();
        if (mockMode() || !"12306-mcp".equalsIgnoreCase(provider)) {
            return mockTravelTools.quoteRailFares(origin, destination, date);
        }
        if (!railwayMcpClient.configured()) {
            return degradedRailFares(origin, destination, date, "RAILWAY_MCP_NOT_CONFIGURED",
                "未配置 12306 MCP 服务地址，铁路票价暂时使用参考数据");
        }

        String key = "railfare:" + origin + ":" + destination + ":" + RailwayMcpClient.resolveDate(date);
        TtlCache.CachedResult<List<ToolModels.RailFare>> cached = cachedRailFares(key);
        if (cached != null) {
            return ToolResult.cached(cached.data(), cached.source(), cached.expiresAt());
        }
        if (cache.isSuppressed(key)) {
            return degradedRailFares(origin, destination, date, "RAILWAY_BACKOFF",
                "12306 票价服务近期调用失败，暂时使用参考价");
        }

        try {
            List<ToolModels.RailFare> fares = railwayMcpClient.queryFares(origin, destination, date,
                timeoutSeconds());
            String source = "12306 MCP（" + RailwayMcpClient.resolveDate(date) + " 官方票价）";
            Duration ttl = Duration.ofMinutes(Math.max(1, properties.getTools().getRailway().getCacheMinutes()));
            cache.put(key, fares, source, ttl);
            return ToolResult.realtime(fares, source, java.time.Instant.now().plus(ttl));
        } catch (RuntimeException exception) {
            cache.suppress(key, FAILURE_BACKOFF);
            return degradedRailFares(origin, destination, date, errorCode(exception, "RAILWAY_MCP_FAILED"),
                describe(exception));
        }
    }

    @Override
    public ToolResult<List<ToolModels.RailTransfer>> searchTransfer(String origin, String destination, String date) {
        String provider = properties.getTools().getRailway().getProvider();
        if (mockMode() || !"12306-mcp".equalsIgnoreCase(provider)) {
            return mockTravelTools.searchTransfer(origin, destination, date);
        }
        if (!railwayMcpClient.configured()) {
            return degradedTransfers(origin, destination, date, "RAILWAY_MCP_NOT_CONFIGURED",
                "未配置 12306 MCP 服务地址，中转方案暂时使用参考数据");
        }

        String key = "railtransfer:" + origin + ":" + destination + ":" + RailwayMcpClient.resolveDate(date);
        TtlCache.CachedResult<List<ToolModels.RailTransfer>> cached = cachedTransfers(key);
        if (cached != null) {
            return ToolResult.cached(cached.data(), cached.source(), cached.expiresAt());
        }
        if (cache.isSuppressed(key)) {
            return degradedTransfers(origin, destination, date, "RAILWAY_BACKOFF",
                "12306 中转服务近期调用失败，暂时不展示实时中转方案");
        }

        try {
            List<ToolModels.RailTransfer> transfers = railwayMcpClient.queryTransfers(origin, destination, date,
                timeoutSeconds());
            String source = "12306 MCP（" + RailwayMcpClient.resolveDate(date) + " 官方中转换乘）";
            Duration ttl = Duration.ofMinutes(Math.max(1, properties.getTools().getRailway().getCacheMinutes()));
            cache.put(key, transfers, source, ttl);
            return ToolResult.realtime(transfers, source, java.time.Instant.now().plus(ttl));
        } catch (RuntimeException exception) {
            cache.suppress(key, FAILURE_BACKOFF);
            return degradedTransfers(origin, destination, date, errorCode(exception, "RAILWAY_MCP_FAILED"),
                describe(exception));
        }
    }

    @Override
    public ToolResult<List<ToolModels.TicketPrice>> quoteTicketPrices(List<TravelModels.Poi> pois, String city) {
        String provider = properties.getTools().getTicket().getProvider();
        if (mockMode() || !"smart-buy".equalsIgnoreCase(provider)) {
            return catalogTicketPriceTools.quote(pois, city);
        }
        // 选中了外部比价服务，但项目里还没有它的适配器：如实降级，不伪造"比价结果"。
        String reason = properties.getTools().getTicket().getBaseUrl().isBlank()
            ? "TICKET_PROVIDER_NOT_CONFIGURED"
            : "TICKET_PROVIDER_NOT_READY";
        ToolResult<List<ToolModels.TicketPrice>> fallback = catalogTicketPriceTools.quote(pois, city);
        return ToolResult.degraded(fallback.data(), "景区内容库参考价", reason,
            "外部比价服务尚未接入，先使用景区内容库参考价");
    }

    private String railwayKey(String origin, String destination, String date) {
        return "railway:" + origin + ":" + destination + ":" + RailwayMcpClient.resolveDate(date);
    }

    /** 车次是列表，泛型擦除后只能按 List 取回，取回后再做一次显式收窄。 */
    @SuppressWarnings("unchecked")
    private TtlCache.CachedResult<List<ToolModels.TrainInfo>> cachedTrains(String key) {
        return (TtlCache.CachedResult<List<ToolModels.TrainInfo>>) (TtlCache.CachedResult<?>)
            cache.get(key, List.class);
    }

    /** 票价列表同样是泛型擦除，缓存读取后显式收窄。 */
    @SuppressWarnings("unchecked")
    private TtlCache.CachedResult<List<ToolModels.RailFare>> cachedRailFares(String key) {
        return (TtlCache.CachedResult<List<ToolModels.RailFare>>) (TtlCache.CachedResult<?>)
            cache.get(key, List.class);
    }

    @SuppressWarnings("unchecked")
    private TtlCache.CachedResult<List<ToolModels.RailTransfer>> cachedTransfers(String key) {
        return (TtlCache.CachedResult<List<ToolModels.RailTransfer>>) (TtlCache.CachedResult<?>)
            cache.get(key, List.class);
    }

    private ToolResult<List<ToolModels.TrainInfo>> degradedTrains(String origin, String destination, String date,
                                                                 String code, String message) {
        ToolResult<List<ToolModels.TrainInfo>> fallback =
            mockTravelTools.searchTrain(origin, destination, date);
        return ToolResult.degraded(fallback.data(), fallback.source(), code, message);
    }

    private ToolResult<List<ToolModels.RailFare>> degradedRailFares(String origin, String destination, String date,
                                                                    String code, String message) {
        ToolResult<List<ToolModels.RailFare>> fallback =
            mockTravelTools.quoteRailFares(origin, destination, date);
        return ToolResult.degraded(fallback.data(), fallback.source(), code, message);
    }

    private ToolResult<List<ToolModels.RailTransfer>> degradedTransfers(String origin, String destination, String date,
                                                                        String code, String message) {
        ToolResult<List<ToolModels.RailTransfer>> fallback =
            mockTravelTools.searchTransfer(origin, destination, date);
        return ToolResult.degraded(fallback.data(), fallback.source(), code, message);
    }

    private ToolResult<ToolModels.WeatherInfo> degradedWeather(String city, String date, String code, String message) {
        ToolModels.WeatherInfo fallback = mockTravelTools.getWeather(city, date).data();
        return ToolResult.degraded(fallback, "天气演示数据", code, message);
    }

    private ToolResult<ToolModels.RouteInfo> degradedRoute(String origin, String destination, String mode,
                                                           String code, String message) {
        ToolModels.RouteInfo fallback = mockTravelTools.getRoute(origin, destination, mode).data();
        return ToolResult.degraded(fallback, "路线演示数据", code, message);
    }

    private boolean mockMode() {
        return "mock".equalsIgnoreCase(properties.getTools().getMode());
    }

    private int timeoutSeconds() {
        return Math.max(1, properties.getTools().getTimeoutSeconds());
    }

    private static String errorCode(RuntimeException exception, String fallback) {
        return exception instanceof ExternalServiceException external ? external.getCode() : fallback;
    }

    private static String describe(RuntimeException exception) {
        String message = exception.getMessage();
        return message == null || message.isBlank() ? exception.getClass().getSimpleName() : message;
    }
}
