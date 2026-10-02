package com.yujian.travel.service;

import com.yujian.travel.config.AppProperties;
import com.yujian.travel.tools.ToolHealth;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;

/**
 * 数据源健康度。
 *
 * 回答的不是"代码里配了几个源"，而是"这几个源现在到底接上没有"：
 * 每个源给出 ready / not-configured / not-implemented / disabled，
 * 加上 {@link ToolHealth} 记录的最近调用结果。
 *
 * 这里只输出"是否已配置"这类布尔信息，绝不回显任何密钥内容。
 */
@Service
public class AdminToolHealthService {
    private final AppProperties properties;
    private final ToolHealth toolHealth;

    public AdminToolHealthService(AppProperties properties, ToolHealth toolHealth) {
        this.properties = properties;
        this.toolHealth = toolHealth;
    }

    public HealthView health() {
        boolean live = liveMode();
        List<SourceLine> sources = new ArrayList<>();

        String weatherProvider = properties.getTools().getWeather().getProvider();
        boolean weatherOff = "none".equalsIgnoreCase(weatherProvider);
        sources.add(new SourceLine("weather", "天气", weatherProvider,
            !live || weatherOff ? status(live, false) : "ready",
            !live ? "当前为 mock 模式，全部使用本地演示数据"
                : weatherOff ? "已配置为不使用外部天气，将标注为演示数据"
                : "Open-Meteo 免费且无需密钥，可直接返回实时预报"));

        boolean baidu = !isBlank(properties.getTools().getBaidu().getApiKey());
        sources.add(new SourceLine("route", "城际路线", "baidu-map",
            !live ? "disabled" : baidu ? "ready" : "not-configured",
            !live ? "当前为 mock 模式，全部使用本地演示数据"
                : baidu ? "百度地图 AK 已配置，距离与耗时使用 Web 服务结果"
                : "未配置 BAIDU_MAP_AK，路线将带原因降级为演示数据（不会发请求）"));

        String railwayProvider = properties.getTools().getRailway().getProvider();
        boolean mcpMode = "12306-mcp".equalsIgnoreCase(railwayProvider);
        boolean mcpConfigured = !isBlank(properties.getTools().getRailway().getMcpUrl());
        sources.add(new SourceLine("railway", "跨城车次", railwayProvider,
            !live ? "disabled" : !mcpMode ? "not-implemented" : mcpConfigured ? "ready" : "not-configured",
            !live ? "当前为 mock 模式，全部使用本地演示数据"
                : !mcpMode ? "当前使用参考时刻表（非实时），购票引导至铁路官方渠道"
                : mcpConfigured ? "12306 MCP 地址已配置，车次与余票来自官方接口"
                : "未配置 RAILWAY_MCP_URL，车次将带原因降级为参考时刻表"));

        String ticketProvider = properties.getTools().getTicket().getProvider();
        boolean smartBuy = "smart-buy".equalsIgnoreCase(ticketProvider);
        sources.add(new SourceLine("ticket", "门票价格", ticketProvider,
            !smartBuy ? "ready" : "not-implemented",
            !smartBuy ? "使用运营台维护的景区内容库参考价，标注为系统资料"
                : "已选择外部比价服务，但适配器尚未接入，当前使用内容库参考价并标注降级"));

        return new HealthView(Instant.now(), live ? "live" : "mock", sources, toolHealth.snapshots());
    }

    private static String status(boolean live, boolean ready) {
        return live && ready ? "ready" : "disabled";
    }

    private boolean liveMode() {
        return !"mock".equalsIgnoreCase(properties.getTools().getMode());
    }

    private static boolean isBlank(String value) {
        return value == null || value.isBlank();
    }

    public record HealthView(Instant generatedAt, String mode, List<SourceLine> sources,
                             List<ToolHealth.Snapshot> tools) {
    }

    public record SourceLine(String id, String displayName, String provider, String status, String detail) {
    }
}

