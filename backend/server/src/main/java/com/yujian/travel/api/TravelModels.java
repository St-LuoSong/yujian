package com.yujian.travel.api;

import java.util.List;

public final class TravelModels {
    private TravelModels() { }

    /**
     * 公开景点。
     *
     * imageCredit / sourceUrl 是运营台填写的图片出处与资料链接：景区照片要么是
     * 有授权的实景图，要么是明确标注的占位图，客户端要能把这句话显示出来，
     * 而不是让"这张图从哪来"只存在于后台。
     */
    public record Poi(String id, String name, String city, String category, String imageUrl,
                      String description, int ticketFrom, String duration, String suitability,
                      String weatherTip, String dataStatus,
                      String imageCredit, String sourceUrl,
                      String imageStatus) { }

    /**
     * 景点信息流的一页。
     *
     * 首页一次只取一小段：内容库越做越大时，不该把整份目录一次性塞进手机。
     * hasMore 由服务端算好（用的是 JPA 的 hasNext），客户端不需要拿
     * page × size 和 total 自己去推 —— 那种推算在边界上最容易出错。
     */
    public record PoiPage(List<Poi> items, int page, int size, long total, boolean hasMore) { }

    public record Corridor(String id, String title, String subtitle, String cities,
                           String duration, String budget, String imageUrl, List<String> highlights) { }

    public record HomeResponse(List<Corridor> corridors, List<Poi> featuredPois,
                               String headline, String subline) { }

    /**
     * 旅行需求。
     *
     * startDate 是“出发日期”（yyyy-MM-dd，可空）。它是唯一由用户决定的时间口径：
     * 天气与车次按它查询，方案里每一天的日期也由它推导，模型不再自己猜日期。
     */
    public record PlanRequest(String prompt, String startDate, String origin, String destination, Integer days,
                              Integer travelers, Integer budgetPerPerson, String interests,
                              String pace, String transport) { }

    public record PlanPreview(String sessionId, PlanRequest request, List<String> extracted,
                              List<String> missing, boolean requiresConfirmation, String dataStatus) { }

    public record TripItem(String type, String title, String time, String duration,
                           String transport, String description, int cost, String source,
                           String dataStatus, String risk) { }

    public record TripDay(String label, String date, List<TripItem> items) { }

    public record TripPlan(String id, String title, String summary, String corridor,
                           String intensity, int totalCost, int perPersonCost,
                           List<TripDay> days, List<String> warnings, String dataStatus) { }

    /**
     * 附近景点的一条结果。
     *
     * distanceMeters 是**直线距离**（同一坐标系下的球面距离），不是步行或驾车里程，
     * 界面必须照这个口径措辞。没有可信坐标的景点不会被返回 —— 不拿城市中心凑一个数出来。
     */
    public record NearbyPoi(Poi poi, int distanceMeters) { }

    /**
     * 附近景点的响应。
     *
     * skippedWithoutCoordinate 是"上架了但没配坐标、因此没能参与计算"的景点数。
     * 少了它，"附近没景点"和"附近景点都没配坐标"在界面上长得一模一样，
     * 运营排查也就没有了线索。
     */
    public record NearbyResult(List<NearbyPoi> items, int radiusMeters, String coordinateSystem,
                               int skippedWithoutCoordinate, String dataStatus) { }
}
