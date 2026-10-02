package com.yujian.travel.service;

import com.yujian.travel.api.MapModels;
import com.yujian.travel.api.TravelModels;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.domain.PoiEntity;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.baidu.BaiduMapClient;
import com.yujian.travel.infrastructure.external.baidu.BaiduStaticMapClient;
import com.yujian.travel.map.MapTicketService;
import com.yujian.travel.map.PlaceTrust;
import com.yujian.travel.map.WebMercator;
import com.yujian.travel.repository.PoiRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;
import java.util.Optional;
import java.util.UUID;

/**
 * 把一份行程的某一天变成"可以画出来"的地图快照。
 *
 * 这里承担三件事，每一件都必须有明确的降级口径：
 *
 * 1. **解析坐标**：先查运营台维护的景点库（人工填的坐标最可信），
 *    查不到再调百度地理编码，并按 confidence 过滤。低可信度的点不画，
 *    而是列进 unplaced —— 宁可少画一个，也不要把错误的位置说成那一站。
 * 2. **算窗口**：把所有点框进画面，留出边距；只有一个点时用街道级缩放。
 * 3. **算像素**：用 {@link WebMercator} 把经纬度投影到底图像素，
 *    客户端拿到的是已经可以直接画的坐标。
 *
 * 任何一步失败都不会抛给客户端：返回 fallback 快照，
 * 让界面退回文字路线，而不是留一个空白的地图 Tab。
 */
@Service
public class MapSnapshotService {
    private static final Logger log = LoggerFactory.getLogger(MapSnapshotService.class);

    /** 单点定位用的街道级缩放。 */
    private static final int SINGLE_POINT_ZOOM = 14;
    private static final int MIN_FIT_ZOOM = 6;
    private static final int MAX_FIT_ZOOM = 16;
    /** 画框时四周留白比例：太满会让边缘标记贴边，看不清。 */
    private static final double FIT_PADDING = 0.18;

    /**
     * 底图与坐标的数据状态。
     *
     * 这里刻意不写"实时数据"：这是一张**静态**底图加地理编码坐标，
     * 不含实时路况，也不随用户当前位置刷新。此前标成"实时数据"再配上
     * 生成时刻，读起来像"路况刚更新过"，属于把参考材料说成了实时值。
     */
    private static final String MAP_DATA_STATUS = "系统资料";
    private static final String MAP_SOURCE = "百度地图静态底图 + 地理编码（不含实时路况）";

    /**
     * 明显不是地点的安排。
     *
     * 只用于"短标题"判断：像"老洛阳面馆（午餐）"这种带具体店名的仍然会去解析，
     * 因为那确实是一个可以标在地图上的位置。
     */
    private static final List<String> GENERIC_TITLES = List.of(
        "午餐", "晚餐", "早餐", "用餐", "休息", "自由活动", "返程", "出发", "集合",
        "办理入住", "退房", "休整", "小憩", "补给", "备用时间");

    /**
     * 移动类描述词。
     *
     * "郑州出发前往洛阳""返回郑州"这类文本在百度地理编码里常常会命中一个村庄或乡镇，
     * 得到一个看起来很正常、实际完全是另一回事的坐标。地图宁可少画一个点，
     * 也不能把出发/返程这种"过程"画成一个"地点"。
     */
    private static final List<String> MOVEMENT_WORDS = List.of(
        "前往", "出发", "返回", "返程", "抵达", "换乘", "乘车", "自驾", "路上", "途经");

    /** 交通类安排里，只有真正指向一个设施的名字才值得打点。 */
    private static final List<String> TRANSPORT_PLACE_WORDS = List.of("站", "机场", "码头", "服务区", "汽车站");

    // “可信地点”的判据与河南城市限定统一收敛在 PlaceTrust，
    // 行程地图的打点和运营台的“解析坐标”按钮共用同一份规则。

    private final TripPlanService tripPlanService;
    private final PoiRepository poiRepository;
    private final BaiduMapClient baiduMapClient;
    private final BaiduStaticMapClient staticMapClient;
    private final MapTicketService ticketService;
    private final AppProperties properties;

    public MapSnapshotService(TripPlanService tripPlanService,
                              PoiRepository poiRepository,
                              BaiduMapClient baiduMapClient,
                              BaiduStaticMapClient staticMapClient,
                              MapTicketService ticketService,
                              AppProperties properties) {
        this.tripPlanService = tripPlanService;
        this.poiRepository = poiRepository;
        this.baiduMapClient = baiduMapClient;
        this.staticMapClient = staticMapClient;
        this.ticketService = ticketService;
        this.properties = properties;
    }

    /**
     * 生成地图快照。
     *
     * @param centerLngOverride 前一次快照给出的中心经度，可为空
     * @param centerLatOverride 前一次快照给出的中心纬度，可为空
     * @param zoomOverride      缩放按钮的级别，可为空
     * @param panXPixels        拖动产生的"视野中心像素位移"，向右为正，可为空
     * @param panYPixels        拖动产生的纵向位移，向下为正，可为空
     */
    public MapModels.RouteMap snapshot(UUID tripId, Integer dayNumber,
                                       Double centerLngOverride, Double centerLatOverride,
                                       Integer zoomOverride,
                                       Double panXPixels, Double panYPixels) {
        TravelModels.TripPlan plan = tripPlanService.get(tripId);
        List<TravelModels.TripDay> days =
            plan.days() == null ? List.of() : plan.days();
        if (days.isEmpty()) {
            return fallback(plan.id(), 1, null, List.of(),
                "这份行程还没有安排任何一天，暂时没有可展示的路线。");
        }
        int index = dayNumber == null ? 1 : Math.max(1, Math.min(days.size(), dayNumber));
        TravelModels.TripDay day = days.get(index - 1);

        int width = clamp(properties.getTools().getBaidu().getMapWidth(), 320, 1024);
        int height = clamp(properties.getTools().getBaidu().getMapHeight(), 320, 1024);

        if (!staticMapClient.configured()) {
            return fallback(plan.id(), index, day, List.of(),
                "服务端未配置百度地图 AK，地图暂不可用，已切换为文字路线。");
        }

        Resolution resolution = resolve(plan, day);
        if (resolution.placed().isEmpty()) {
            return fallback(plan.id(), index, day, resolution.unplaced(),
                resolution.failureMessage() == null
                    ? "没有解析到可信的站点坐标，已切换为文字路线。"
                    : resolution.failureMessage());
        }

        WebMercator.Coordinate center = resolution.placed().size() == 1
            ? new WebMercator.Coordinate(resolution.placed().get(0).lng(), resolution.placed().get(0).lat())
            : boundingCenter(resolution.placed());
        int zoom = resolution.placed().size() == 1
            ? SINGLE_POINT_ZOOM
            : fitZoom(resolution.placed(), width, height);
        boolean fitted = centerLngOverride == null && centerLatOverride == null
            && zoomOverride == null && panXPixels == null && panYPixels == null;
        if (centerLngOverride != null && centerLatOverride != null) {
            center = new WebMercator.Coordinate(centerLngOverride, centerLatOverride);
        }
        if (zoomOverride != null) {
            zoom = WebMercator.clampZoom(zoomOverride);
        }
        // 拖动只在服务端换算：客户端只会说"我往右拖了 300 像素"，
        // 投影与反投影都留在这一个类里，APK 不需要懂百度坐标系。
        if (panXPixels != null || panYPixels != null) {
            center = WebMercator.shiftCenter(center.lng(), center.lat(), zoom,
                panXPixels == null ? 0 : panXPixels, panYPixels == null ? 0 : panYPixels);
        }

        // 先自己取一次底图：取到就说明客户端随后一定能拿到图，取不到就当场降级，
        // 不会出现"接口成功但客户端显示裂图"这种半失败状态。
        try {
            staticMapClient.fetch(center.lng(), center.lat(), zoom, width, height);
        } catch (ExternalServiceException failure) {
            log.warn("Static map unavailable, falling back to text route: {} {}", failure.getCode(), failure.getMessage());
            return fallback(plan.id(), index, day, resolution.unplaced(),
                "底图暂时拉取失败（" + failure.getMessage() + "），已切换为文字路线。");
        }

        List<MapModels.Marker> markers = new ArrayList<>();
        for (int i = 0; i < resolution.placed().size(); i++) {
            Placed placed = resolution.placed().get(i);
            WebMercator.Pixel pixel = WebMercator.project(
                placed.lng(), placed.lat(), center.lng(), center.lat(), zoom, width, height);
            markers.add(new MapModels.Marker(
                i + 1,
                placed.item().title(),
                placed.item().type() == null ? "" : placed.item().type(),
                placed.item().time() == null ? "" : placed.item().time(),
                round6(placed.lng()),
                round6(placed.lat()),
                round2(pixel.x()),
                round2(pixel.y()),
                pixel.inside(width, height),
                placed.source(),
                placed.confidence()));
        }

        List<List<Double>> polyline = new ArrayList<>();
        for (MapModels.Marker marker : markers) {
            polyline.add(List.of(marker.x(), marker.y()));
        }

        Instant now = Instant.now();
        String canonical = MapTicketService.canonical(center.lng(), center.lat(), zoom, width, height);
        String ticket = ticketService.issue(canonical, now.getEpochSecond());
        long lifetime = Math.max(300, ticketService.remainingSeconds(ticket, now.getEpochSecond()));

        String imageUrl = String.format(Locale.ROOT,
            "/api/map/image?center=%.6f,%.6f&zoom=%d&width=%d&height=%d&ticket=%s",
            center.lng(), center.lat(), zoom, width, height, ticket);

        return new MapModels.RouteMap(
            plan.id(),
            index,
            day.label() == null ? ("DAY " + index) : day.label(),
            day.date() == null ? "" : day.date(),
            new MapModels.Viewport(round6(center.lng()), round6(center.lat()), zoom, width, height, fitted),
            imageUrl,
            (int) lifetime,
            markers,
            polyline,
            resolution.unplaced(),
            attribution(),
            MAP_DATA_STATUS,
            MAP_SOURCE,
            now,
            now.plusSeconds(lifetime),
            false,
            null);
    }

    /** 坐标解析结果：能画的点 + 不能画的点 + 失败原因。 */
    private record Resolution(List<Placed> placed, List<MapModels.Unplaced> unplaced, String failureMessage) {
    }

    private record Placed(TravelModels.TripItem item, double lng, double lat, String source, int confidence) {
    }

    private Resolution resolve(TravelModels.TripPlan plan, TravelModels.TripDay day) {
        int limit = Math.max(1, properties.getTools().getBaidu().getMapMaxMarkers());
        int minConfidence = Math.max(0, properties.getTools().getBaidu().getMapMinConfidence());
        List<PoiEntity> catalog = poiRepository.findByPublishedTrueOrderBySortOrderAscNameAsc();
        String defaultCityHint = cityHint(plan, day);

        List<Placed> placed = new ArrayList<>();
        List<MapModels.Unplaced> unplaced = new ArrayList<>();
        String failure = null;

        for (TravelModels.TripItem item : day.items()) {
            if (placed.size() >= limit) {
                unplaced.add(new MapModels.Unplaced(item.title(), "超出单日打点上限（" + limit + " 个）"));
                continue;
            }
            String title = item.title() == null ? "" : item.title().trim();
            if (title.isEmpty()) {
                continue;
            }
            if (looksGeneric(item, title)) {
                unplaced.add(new MapModels.Unplaced(title, "属于移动/休息类安排，不是具体地点，不在地图上打点"));
                continue;
            }
            if (placed.stream().anyMatch(p -> p.item().title().equals(item.title()))) {
                continue;
            }

            Optional<PoiEntity> catalogHit = matchCatalog(catalog, title);
            if (catalogHit.isPresent() && catalogHit.get().getLng() != null && catalogHit.get().getLat() != null) {
                PoiEntity poi = catalogHit.get();
                placed.add(new Placed(item, poi.getLng(), poi.getLat(), "景点库坐标（运营台维护）", 100));
                continue;
            }
            try {
                // 标题自带城市时以它为准："洛阳博物馆"配郑州做限定会被解析成郑州市中心。
                String hint = PlaceTrust.cityInTitle(title).orElse(defaultCityHint);
                Optional<BaiduMapClient.GeocodeResult> geocoded = baiduMapClient.geocodePlace(title, hint);
                if (geocoded.isEmpty()) {
                    unplaced.add(new MapModels.Unplaced(title, "百度地图没有返回可用坐标"));
                    continue;
                }
                BaiduMapClient.GeocodeResult result = geocoded.get();
                String coarse = PlaceTrust.coarseLevelReason(result.level());
                if (coarse != null) {
                    unplaced.add(new MapModels.Unplaced(title, coarse));
                    continue;
                }
                String outOfRegion = PlaceTrust.outOfRegionReason(result.lng(), result.lat());
                if (outOfRegion != null) {
                    unplaced.add(new MapModels.Unplaced(title, outOfRegion + "，未在地图上打点"));
                    continue;
                }
                if (result.confidence() < minConfidence) {
                    unplaced.add(new MapModels.Unplaced(title,
                        "坐标可信度不足（" + result.confidence() + "），未在地图上打点"));
                    continue;
                }
                placed.add(new Placed(item, result.lng(), result.lat(),
                    "百度地图地理编码" + (result.level().isEmpty() ? "" : "（" + result.level() + "）"),
                    result.confidence()));
            } catch (ExternalServiceException failure2) {
                log.warn("Geocode failed for '{}': {}", title, failure2.getMessage());
                failure = "百度地图地理编码暂时不可用（" + failure2.getMessage() + "），已切换为文字路线。";
                unplaced.add(new MapModels.Unplaced(title, "地理编码调用失败"));
                if (placed.isEmpty()) {
                    break;
                }
            }
        }
        return new Resolution(placed, unplaced, placed.isEmpty() ? failure : null);
    }

    private static Optional<PoiEntity> matchCatalog(List<PoiEntity> catalog, String title) {
        for (PoiEntity poi : catalog) {
            if (poi.getName() == null || poi.getName().isBlank()) {
                continue;
            }
            if (title.equals(poi.getName()) || title.contains(poi.getName()) || poi.getName().contains(title)) {
                return Optional.of(poi);
            }
        }
        return Optional.empty();
    }

    private static boolean looksGeneric(TravelModels.TripItem item, String title) {
        if (title.length() <= 6) {
            for (String generic : GENERIC_TITLES) {
                if (title.equals(generic) || title.contains(generic)) {
                    return true;
                }
            }
        }
        // "郑州 → 洛阳" 这类移动描述不是地点本身，跨城交通另有车次模块负责。
        if (title.contains("→") || title.contains("->")) {
            return true;
        }
        for (String movement : MOVEMENT_WORDS) {
            if (title.contains(movement)) {
                return true;
            }
        }
        if (isTransport(item.type())) {
            for (String place : TRANSPORT_PLACE_WORDS) {
                if (title.contains(place)) {
                    return false;
                }
            }
            return true;
        }
        return false;
    }

    private static boolean isTransport(String itemType) {
        if (itemType == null) {
            return false;
        }
        String type = itemType.toLowerCase(Locale.ROOT);
        return type.contains("transport") || type.contains("traffic") || type.contains("交通") || type.contains("transfer");
    }

    private static String cityHint(TravelModels.TripPlan plan, TravelModels.TripDay day) {
        StringBuilder dayText = new StringBuilder();
        for (TravelModels.TripItem item : day.items()) {
            dayText.append(item.title() == null ? "" : item.title()).append(' ');
            dayText.append(item.description() == null ? "" : item.description()).append(' ');
        }
        String text = dayText.toString();
        for (String city : PlaceTrust.HENAN_CITIES) {
            if (text.contains(city)) {
                return city;
            }
        }
        String corridor = plan.corridor() == null ? "" : plan.corridor();
        for (String city : PlaceTrust.HENAN_CITIES) {
            if (corridor.contains(city)) {
                return city;
            }
        }
        return "";
    }

    private WebMercator.Coordinate boundingCenter(List<Placed> placed) {
        double minX = Double.MAX_VALUE;
        double maxX = -Double.MAX_VALUE;
        double minY = Double.MAX_VALUE;
        double maxY = -Double.MAX_VALUE;
        for (Placed point : placed) {
            double x = WebMercator.meterX(point.lng());
            double y = WebMercator.meterY(point.lat());
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
        }
        return new WebMercator.Coordinate(
            WebMercator.lngOf((minX + maxX) / 2),
            WebMercator.latOf((minY + maxY) / 2));
    }

    /** 选一个能把这些点全部框进画面的缩放级别。 */
    private int fitZoom(List<Placed> placed, int width, int height) {
        double minX = Double.MAX_VALUE;
        double maxX = -Double.MAX_VALUE;
        double minY = Double.MAX_VALUE;
        double maxY = -Double.MAX_VALUE;
        for (Placed point : placed) {
            double x = WebMercator.meterX(point.lng());
            double y = WebMercator.meterY(point.lat());
            minX = Math.min(minX, x);
            maxX = Math.max(maxX, x);
            minY = Math.min(minY, y);
            maxY = Math.max(maxY, y);
        }
        double usableWidth = Math.max(1, width * (1 - 2 * FIT_PADDING));
        double usableHeight = Math.max(1, height * (1 - 2 * FIT_PADDING));
        double needed = Math.max((maxX - minX) / usableWidth, (maxY - minY) / usableHeight);
        if (needed <= 0) {
            return MAX_FIT_ZOOM;
        }
        int zoom = (int) Math.floor(18 - Math.log(needed) / Math.log(2));
        return Math.max(MIN_FIT_ZOOM, Math.min(MAX_FIT_ZOOM, zoom));
    }

    private MapModels.RouteMap fallback(String tripId, int dayIndex, TravelModels.TripDay day,
                                        List<MapModels.Unplaced> unplaced, String message) {
        log.info("Map snapshot degraded for trip {}: {}", tripId, message);
        List<MapModels.Unplaced> details = new ArrayList<>(unplaced);
        if (day != null) {
            for (TravelModels.TripItem item : day.items()) {
                if (item.title() == null || item.title().isBlank()) {
                    continue;
                }
                boolean known = details.stream().anyMatch(entry -> entry.title().equals(item.title()));
                if (!known) {
                    details.add(new MapModels.Unplaced(item.title(), "地图不可用，已按文字路线展示"));
                }
            }
        }
        return new MapModels.RouteMap(
            tripId,
            dayIndex,
            day == null || day.label() == null ? ("DAY " + dayIndex) : day.label(),
            day == null || day.date() == null ? "" : day.date(),
            null,
            null,
            0,
            List.of(),
            List.of(),
            details,
            attribution(),
            "演示数据（降级）",
            "文字路线（地图降级）",
            Instant.now(),
            null,
            true,
            message);
    }

    private static List<String> attribution() {
        return List.of(
            "底图 © 百度地图",
            "静态底图不含实时路况",
            "站点坐标由百度地图地理编码解析，未定位的站点单独列出");
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static double round2(double value) {
        return Math.round(value * 100d) / 100d;
    }

    private static double round6(double value) {
        return Math.round(value * 1_000_000d) / 1_000_000d;
    }
}
