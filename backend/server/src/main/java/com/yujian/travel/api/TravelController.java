package com.yujian.travel.api;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.service.ContentLibraryService;
import com.yujian.travel.service.PoiContentService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api")
public class TravelController {
    private final PoiContentService poiContentService;
    private final ContentLibraryService contentLibraryService;

    public TravelController(PoiContentService poiContentService,
                            ContentLibraryService contentLibraryService) {
        this.poiContentService = poiContentService;
        this.contentLibraryService = contentLibraryService;
    }

    /**
     * 首页聚合。
     *
     * 一次返回首屏需要的全部内容：横幅文案与图片、四条主题路线、精选景点、
     * 文化锦囊预览。拆成多个接口会让首屏出现"图出来了、字还在转"的割裂感，
     * 而这些数据本来就是同一屏的。
     *
     * corridors 与 headline/subline 保留旧名字，继续服务旧客户端。
     */
    @GetMapping("/home")
    public TravelModels.HomeResponse home() {
        return new TravelModels.HomeResponse(
            contentLibraryService.legacyCorridors(),
            contentLibraryService.publicThemeRoutes(),
            poiContentService.featuredPois(),
            contentLibraryService.publicCulturePreview(),
            contentLibraryService.publicVisualResources(),
            "河南，让旅行更简单",
            "AI 智能规划 · 精准推荐 · 陪伴出行",
            java.time.Instant.now().toString());
    }

    /** 主题路线：旧客户端读 /home，新客户端也可以在"精选路线"页单独翻页。 */
    @GetMapping("/theme-routes")
    public List<TravelModels.ThemeRoute> themeRoutes() {
        return contentLibraryService.publicThemeRoutes();
    }

    /** 文化锦囊列表。category 为空即全部。 */
    @GetMapping("/culture-articles")
    public List<TravelModels.CultureArticleSummary> cultureArticles(
        @RequestParam(required = false) String category) {
        return contentLibraryService.publicCulture(category);
    }

    @GetMapping("/culture-articles/{id}")
    public ResponseEntity<TravelModels.CultureArticle> cultureArticle(@PathVariable String id) {
        return contentLibraryService.publicCultureArticle(id)
            .map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @GetMapping("/pois")
    public List<TravelModels.Poi> pois(@RequestParam(required = false) String city) {
        // 内容来自管理台维护的景点库，不再直接读硬编码目录，保证"改了就生效"。
        return poiContentService.publicPois(city);
    }

    /**
     * 首页的信息流。
     *
     * 与 /pois 分开而不是给 /pois 加参数：/pois 的响应是一个数组，被"全部景点"
     * 一类的调用方与离线缓存直接使用；把同一个地址的响应体在有无参数时变成两种
     * 形状，是那种过半年一定会踩到的坑。
     *
     * 路径 /pois/page 是字面量，优先级高于 /pois/{id} 模板，因此不会把 "page"
     * 当成一个景点 id。
     */
    @GetMapping("/pois/page")
    public TravelModels.PoiPage poiPage(@RequestParam(required = false) String city,
                                        @RequestParam(required = false) String category,
                                        @RequestParam(required = false) String keyword,
                                        @RequestParam(required = false) Integer page,
                                        @RequestParam(required = false) Integer size) {
        return poiContentService.publicPoiPage(city, category, keyword, page, size);
    }

    /**
     * 收藏榜：被收藏最多的景点，默认前 10 条。
     *
     * 与 /pois 分开是有意的：这里要多做一次收藏聚合，而 /pois 是"整份目录"的
     * 入口，不该为它多算一遍。路径是字面量，优先级高于 /pois/{id}，
     * 不会把 "popular" 当成某个景点 id。
     */
    @GetMapping("/pois/popular")
    public List<TravelModels.PoiRank> popularPois(@RequestParam(required = false) Integer limit) {
        return poiContentService.popularPois(limit);
    }

    /**
     * 附近的景点。
     *
     * 入参是设备定位的原始 WGS-84 坐标，服务端负责换算到内容库使用的 BD-09 之后再比距离。
     * 不让客户端自己换算，是因为坐标系这件事只该在服务端踩一次坑，
     * 而且换底图或换数据源时不需要所有已发布的 APK 跟着升版。
     *
     * 放在 /api/pois/** 之下，因此免登录可调：附近有什么景点不是隐私。
     * 反过来说，服务端**不保存**这次查询的坐标 —— 位置不落库，也就没有位置历史。
     *
     * 路径 /pois/nearby 与 /pois/page 一样是字面量，优先级高于 /pois/{id} 模板，
     * 不会把 "nearby" 当成一个景点 id。
     */
    @GetMapping("/pois/nearby")
    public TravelModels.NearbyResult nearby(@RequestParam(required = false) Double lng,
                                            @RequestParam(required = false) Double lat,
                                            @RequestParam(required = false) Integer radius,
                                            @RequestParam(required = false) Integer limit) {
        if (lng == null || lat == null || lng.isNaN() || lat.isNaN()
            || Math.abs(lng) > 180 || Math.abs(lat) > 90) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "COORDINATE_INVALID",
                "请提供合法的定位坐标（lng、lat）");
        }
        return poiContentService.nearbyPois(lng, lat, radius, limit);
    }

    @GetMapping("/pois/{id}")
    public ResponseEntity<TravelModels.Poi> poi(@PathVariable String id) {
        return poiContentService.publicPoi(id).map(ResponseEntity::ok)
            .orElseGet(() -> ResponseEntity.notFound().build());
    }

    @PostMapping("/trip-plans/preview")
    public TravelModels.PlanPreview preview(@Valid @RequestBody PlanRequestPayload payload) {
        String prompt = payload.prompt() == null ? "" : payload.prompt().trim();
        String destination = payload.destination() == null ? inferDestination(prompt) : payload.destination();
        var request = new TravelModels.PlanRequest(prompt, payload.startDate(),
            defaultText(payload.origin(), "郑州"), destination,
            payload.days(), payload.travelers(), payload.budgetPerPerson(), payload.interests(), payload.pace(),
            payload.transport());
        List<String> extracted = List.of("出发地：" + request.origin(), "目的地：" + request.destination(),
            "兴趣：" + defaultText(request.interests(), "历史文化"), "节奏：" + defaultText(request.pace(), "适中"));
        List<String> missing = request.days() == null ? List.of("计划游玩几天？") : List.of();
        return new TravelModels.PlanPreview(UUID.randomUUID().toString(), request, extracted, missing,
            !missing.isEmpty(), "演示数据");
    }

    private String inferDestination(String prompt) {
        if (prompt != null && prompt.contains("开封")) {
            return "开封";
        }
        if (prompt != null && prompt.contains("云台")) {
            return "云台山";
        }
        return "洛阳";
    }

    private String defaultText(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    /**
     * 预览请求。字段名与 POST /api/trip-plans 保持一致，客户端两条入口共用同一份表单。
     *
     * startDate（yyyy-MM-dd）是“出发日期”，也是全链路唯一的时间口径：
     * 天气、车次与方案里的每一天都由它推导，缺失时才退回“明天”。
     */
    public record PlanRequestPayload(
        @NotBlank(message = "请描述你的旅行需求") String prompt,
        String startDate,
        String origin, String destination, Integer days, Integer travelers,
        Integer budgetPerPerson, String interests, String pace, String transport) {
    }
}
