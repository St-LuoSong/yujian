package com.yujian.travel.api;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.baidu.BaiduStaticMapClient;
import com.yujian.travel.map.MapTicketService;
import com.yujian.travel.map.WebMercator;
import com.yujian.travel.service.MapSnapshotService;
import org.springframework.http.CacheControl;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.Duration;
import java.time.Instant;
import java.util.UUID;

/**
 * 行程地图接口。
 *
 * 两个端点分工明确：
 *
 * - {@code GET /api/trip-plans/{id}/map} 需要登录态（含匿名会话）与行程归属校验，
 *   回答"这一天的站点在哪里、底图怎么取"；
 * - {@code GET /api/map/image} 是给 CachedNetworkImage 直接消费的 PNG，
 *   凭短时票据访问：票据只对同一组参数有效，过期即失效，
 *   这样它既不需要带 Authorization 头，也不会变成任何人都能刷的百度代理。
 */
@RestController
public class MapController {
    private static final int MIN_EDGE = 320;
    private static final int MAX_EDGE = 1024;

    private final MapSnapshotService mapSnapshotService;
    private final BaiduStaticMapClient staticMapClient;
    private final MapTicketService ticketService;
    private final AppProperties properties;

    public MapController(MapSnapshotService mapSnapshotService,
                         BaiduStaticMapClient staticMapClient,
                         MapTicketService ticketService,
                         AppProperties properties) {
        this.mapSnapshotService = mapSnapshotService;
        this.staticMapClient = staticMapClient;
        this.ticketService = ticketService;
        this.properties = properties;
    }

    @GetMapping("/api/trip-plans/{id}/map")
    public MapModels.RouteMap routeMap(@PathVariable UUID id,
                                       @RequestParam(required = false) Integer day,
                                       @RequestParam(required = false) String center,
                                       @RequestParam(required = false) Integer zoom,
                                       @RequestParam(required = false) Double panX,
                                       @RequestParam(required = false) Double panY) {
        Coordinate centerPoint = center == null || center.isBlank() ? null : parseCenter(center);
        return mapSnapshotService.snapshot(id, day,
            centerPoint == null ? null : centerPoint.lng(),
            centerPoint == null ? null : centerPoint.lat(),
            zoom, panX, panY);
    }

    @GetMapping("/api/map/image")
    public ResponseEntity<byte[]> image(@RequestParam String center,
                                        @RequestParam Integer zoom,
                                        @RequestParam Integer width,
                                        @RequestParam Integer height,
                                        @RequestParam String ticket) {
        Coordinate point = parseCenter(center);
        int safeZoom = WebMercator.clampZoom(zoom);
        int safeWidth = clampEdge(width);
        int safeHeight = clampEdge(height);

        String canonical = MapTicketService.canonical(point.lng(), point.lat(), safeZoom, safeWidth, safeHeight);
        long now = Instant.now().getEpochSecond();
        if (!ticketService.verify(canonical, ticket, now)) {
            throw new ApiException(HttpStatus.FORBIDDEN, "MAP_TICKET_INVALID",
                "地图票据无效或已过期，请返回行程页重新打开地图");
        }

        BaiduStaticMapClient.StaticImage image =
            staticMapClient.fetch(point.lng(), point.lat(), safeZoom, safeWidth, safeHeight);
        long maxAge = Math.max(60, Math.min(1800, ticketService.remainingSeconds(ticket, now)));
        return ResponseEntity.ok()
            .contentType(MediaType.IMAGE_PNG)
            .cacheControl(CacheControl.maxAge(Duration.ofSeconds(maxAge)).cachePublic())
            .body(image.bytes());
    }

    /** 默认尺寸，供客户端在没有特别指定时使用（例如未来在景点详情页放一张小图）。 */
    @GetMapping("/api/map/size")
    public MapSize size() {
        return new MapSize(
            clampEdge(properties.getTools().getBaidu().getMapWidth()),
            clampEdge(properties.getTools().getBaidu().getMapHeight()));
    }

    public record MapSize(int width, int height) {
    }

    private record Coordinate(double lng, double lat) {
    }

    private static Coordinate parseCenter(String center) {
        String[] parts = center.split(",");
        if (parts.length != 2) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MAP_CENTER_INVALID",
                "地图中心点格式应为 经度,纬度");
        }
        double lng;
        double lat;
        try {
            lng = Double.parseDouble(parts[0].trim());
            lat = Double.parseDouble(parts[1].trim());
        } catch (NumberFormatException invalid) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MAP_CENTER_INVALID", "地图中心点不是合法数字");
        }
        if (Double.isNaN(lng) || Double.isNaN(lat) || Math.abs(lng) > 180 || Math.abs(lat) > 90) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "MAP_CENTER_INVALID", "地图中心点超出合法范围");
        }
        return new Coordinate(lng, lat);
    }

    private static int clampEdge(int value) {
        return Math.max(MIN_EDGE, Math.min(MAX_EDGE, value));
    }
}
