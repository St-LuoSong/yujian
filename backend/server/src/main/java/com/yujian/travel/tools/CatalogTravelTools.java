package com.yujian.travel.tools;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.PoiContentService;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Locale;

/**
 * 系统自有资料：景点检索与景区开放时间参考。
 *
 * 这两项不来自第三方接口，因此标注为"系统资料"而不是"演示数据"——
 * 内容由运营台维护，管理台改完游客端立即生效。
 */
@Component
public class CatalogTravelTools {
    private final PoiContentService poiContentService;

    public CatalogTravelTools(PoiContentService poiContentService) {
        this.poiContentService = poiContentService;
    }

    public ToolResult<List<TravelModels.Poi>> searchPoi(String keyword, String city) {
        List<TravelModels.Poi> byCity = poiContentService.publicPois(city);
        List<TravelModels.Poi> matched = filter(byCity, keyword);
        // 城市里没有匹配项时放宽到全库，避免用户输入方言或别称时得到空结果。
        return ToolResult.reference(matched.isEmpty() ? filter(poiContentService.publicPois(null), keyword) : matched,
            "系统景点库");
    }

    public ToolResult<List<ToolModels.OpeningInfo>> checkOpening(String destination) {
        String city = destination == null ? "" : destination;
        List<ToolModels.OpeningInfo> openings;
        if (city.contains("开封")) {
            openings = List.of(
                new ToolModels.OpeningInfo("开封府", "08:00—18:00", false, "开衙仪式时间随季节调整"),
                new ToolModels.OpeningInfo("清明上河园", "09:00—22:00", false, "夜游演出需单独确认"));
        } else if (city.contains("云台") || city.contains("焦作")) {
            openings = List.of(
                new ToolModels.OpeningInfo("红石峡", "06:30—18:30", true, "强降雨天气可能临时关闭"),
                new ToolModels.OpeningInfo("茱萸峰", "07:00—17:30", true, "山路较多，关注天气和体能"));
        } else {
            openings = List.of(
                new ToolModels.OpeningInfo("龙门石窟", "08:00—18:00", true, "建议提前预约"),
                new ToolModels.OpeningInfo("洛阳博物馆", "09:00—17:00", true, "周一通常闭馆"));
        }
        return ToolResult.reference(openings, "景区公开资料（参考）");
    }

    private static List<TravelModels.Poi> filter(List<TravelModels.Poi> pois, String keyword) {
        if (keyword == null || keyword.isBlank()) {
            return pois;
        }
        String needle = keyword.trim().toLowerCase(Locale.ROOT);
        List<TravelModels.Poi> matched = pois.stream().filter(poi -> matches(poi, needle)).toList();
        return matched.isEmpty() ? pois : matched;
    }

    private static boolean matches(TravelModels.Poi poi, String needle) {
        return contains(poi.name(), needle) || contains(poi.city(), needle) || contains(poi.category(), needle)
            || contains(poi.description(), needle);
    }

    private static boolean contains(String value, String needle) {
        return value != null && value.toLowerCase(Locale.ROOT).contains(needle);
    }
}
