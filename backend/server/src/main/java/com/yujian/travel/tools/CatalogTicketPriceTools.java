package com.yujian.travel.tools;

import com.yujian.travel.api.TravelModels;
import com.yujian.travel.service.PoiContentService;
import org.springframework.stereotype.Component;

import java.util.ArrayList;
import java.util.List;
import java.util.stream.Collectors;

/**
 * 系统自有资料：门票参考价。
 *
 * 价格来自运营台维护的景区内容库，所以标注为"系统资料"而不是"实时数据"——
 * 参考价可以帮用户做预算判断，但不能冒充官方实时票价。
 */
@Component
public class CatalogTicketPriceTools implements TicketPricePort {
    private final PoiContentService poiContentService;

    public CatalogTicketPriceTools(PoiContentService poiContentService) {
        this.poiContentService = poiContentService;
    }

    @Override
    public ToolResult<List<ToolModels.TicketPrice>> quote(List<TravelModels.Poi> pois, String city) {
        List<TravelModels.Poi> source = pois == null || pois.isEmpty()
            ? poiContentService.publicPois(city)
            : pois;
        List<ToolModels.TicketPrice> prices = source.stream()
            .map(CatalogTicketPriceTools::toPrice)
            .collect(Collectors.toCollection(ArrayList::new));
        return ToolResult.reference(prices, "景区内容库参考价");
    }

    private static ToolModels.TicketPrice toPrice(TravelModels.Poi poi) {
        List<String> notes = new ArrayList<>();
        if (poi.duration() != null && !poi.duration().isBlank()) {
            notes.add("建议游玩 " + poi.duration());
        }
        notes.add("以景区官方公示为准");
        return new ToolModels.TicketPrice(poi.name(), poi.city(), poi.ticketFrom(),
            "景区内容库参考价", String.join("，", notes));
    }
}

