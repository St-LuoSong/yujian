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
                      String imageStatus,
                      /** 开放时间，可能为空：为空时客户端显示"以景区公告为准"，不编造。 */
                      String openingHours,
                      /** 预约说明，可能为空。 */
                      String reservationNote,
                      /** 详情页图集（不含封面）。空列表表示运营还没配图集。 */
                      List<String> gallery) {

        /**
         * 兼容构造器。
         *
         * 老版本客户端只会拿到这些字段，而服务端内部还有若干地方按原来的 15 个
         * 参数构造 Poi（兜底目录、行程校验）。保留这个重载，新增字段就不会变成
         * 一次全仓库的机械改动。
         */
        public Poi(String id, String name, String city, String category, String imageUrl,
                   String description, int ticketFrom, String duration, String suitability,
                   String weatherTip, String dataStatus,
                   String imageCredit, String sourceUrl, String imageStatus) {
            this(id, name, city, category, imageUrl, description, ticketFrom, duration, suitability,
                weatherTip, dataStatus, imageCredit, sourceUrl, imageStatus, null, null, List.of());
        }
    }

    /**
     * 景点信息流的一页。
     *
     * 首页一次只取一小段：内容库越做越大时，不该把整份目录一次性塞进手机。
     * hasMore 由服务端算好（用的是 JPA 的 hasNext），客户端不需要拿
     * page × size 和 total 自己去推 —— 那种推算在边界上最容易出错。
     */
    public record PoiPage(List<Poi> items, int page, int size, long total, boolean hasMore) { }

    /**
     * 收藏榜条目：景点本身 + 被收藏的次数。
     *
     * 不把 favoriteCount 直接塞进 {@link Poi}：/pois 与 /pois/page 根本不统计
     * 收藏数，那样会让"没统计"在客户端看起来像"0 次收藏"。包一层之后，
     * 只有真正查过收藏数的接口才会带上这个字段。
     */
    public record PoiRank(Poi poi, long favoriteCount) { }

    public record Corridor(String id, String title, String subtitle, String cities,
                           String duration, String budget, String imageUrl, List<String> highlights) { }

    /**
     * 主题路线（运营台维护的示范走廊）。
     *
     * 与 Corridor 的区别：Corridor 是旧版首页用的展示结构，ThemeRoute 多带了
     * 规划提示词与图片出处。两条都返回，是为了让已经装出去的 APK 不会因为
     * 一次后端升级就白屏。
     */
    public record ThemeRoute(String id, String title, String subtitle, String cities,
                             String duration, String budget, String coverUrl,
                             List<String> highlights, String planningPrompt,
                             String imageCredit, String sourceUrl) { }

    /**
     * 文化锦囊的列表项。
     *
     * 列表不带正文：一屏十篇文章的正文加起来是几百 KB，首页只要标题和摘要。
     */
    public record CultureArticleSummary(String id, String title, String summary, String category,
                                        String coverUrl, String imageCredit, String sourceUrl,
                                        String updatedAt, int readingMinutes,
                                        String author, int likeCount) { }

    /** 文化锦囊详情，含正文。 */
    public record CultureArticle(String id, String title, String summary, String content,
                                 String category, String coverUrl, String imageCredit,
                                 String sourceUrl, String updatedAt,
                                 String author, int likeCount) { }

    /** 一个视觉资源槽的当前取值。imageUrl 为空表示运营未配置，客户端用内置占位图。 */
    public record VisualResource(String slot, String imageUrl, String imageCredit, String sourceUrl) { }

    /**
     * 首页聚合响应。
     *
     * 一次请求把首页要用的东西取齐：主题路线、精选景点、文化预览、视觉资源。
     * 分成四个接口会让首屏出现"横幅已经显示、景点还在转圈"的割裂感，
     * 而这些数据本来就是一个页面的。
     *
     * corridors 与 headline/subline 保留旧名字，继续服务旧客户端；
     * 新客户端读 themeRoutes 与 visualResources。
     */
    public record HomeResponse(List<Corridor> corridors,
                               List<ThemeRoute> themeRoutes,
                               List<Poi> featuredPois,
                               List<CultureArticleSummary> culturePreview,
                               List<VisualResource> visualResources,
                               String headline,
                               String subline,
                               String updatedAt) { }

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
