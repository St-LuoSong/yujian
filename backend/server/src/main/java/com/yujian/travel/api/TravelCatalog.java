package com.yujian.travel.api;

import com.yujian.travel.common.PoiImageAudit;

import java.util.List;

/**
 * 断网 / 首次启动时的内置兜底内容。
 *
 * 这里的四张图确实是占位示例图，因此景点会带上 PLACEHOLDER 配图状态 ——
 * 兜底路径也不能把"来源不明"悄悄放过去。
 */
public final class TravelCatalog {
    private TravelCatalog() { }

    public static final String IMAGE_LONGMEN = "https://images.unsplash.com/photo-1548013146-72479768bada?auto=format&fit=crop&w=1200&q=80";
    public static final String IMAGE_SHAOLIN = "https://images.unsplash.com/photo-1528360983277-13d401cdc186?auto=format&fit=crop&w=1200&q=80";
    public static final String IMAGE_YUNTAI = "https://images.unsplash.com/photo-1500534623283-312aade485b7?auto=format&fit=crop&w=1200&q=80";
    public static final String IMAGE_KAIFENG = "https://images.unsplash.com/photo-1518005020951-eccb494ad742?auto=format&fit=crop&w=1200&q=80";

    /**
     * 内置兜底图库的出处。
     *
     * 这几张是断网时用的占位示例图，不是河南实景，也不是有授权的交付素材 ——
     * 所以出处写清楚，客户端会把它显示在详情页上。正式演示前应当由运营台
     * 换成有授权的河南实景图，并在这里改成真实署名。
     */
    public static final String DEMO_IMAGE_CREDIT = "占位示例图（Unsplash），非河南实景，待运营台替换为有授权照片";
    public static final String DEMO_IMAGE_SOURCE = "https://unsplash.com";

    public static List<TravelModels.Poi> pois() {
        // imageStatus 由 PoiImageAudit 的取值域给出，这里写死 PLACEHOLDER 是刻意的：
        // 这四张内置图**确实**是占位示例图，不能因为判断逻辑拿不到而变成"未标注"。
        return List.of(
            new TravelModels.Poi("longmen", "龙门石窟", "洛阳", "人文古迹", IMAGE_LONGMEN,
                "一壁看尽千年风物，石刻造像沿伊河两岸铺展。", 90, "3—4小时", "历史文化爱好者",
                "雨天仍可游览，建议穿舒适防滑鞋。", "演示数据", DEMO_IMAGE_CREDIT, DEMO_IMAGE_SOURCE,
                PoiImageAudit.PLACEHOLDER),
            new TravelModels.Poi("shaolin", "嵩山少林", "登封", "人文古迹", IMAGE_SHAOLIN,
                "少林、塔林与三皇寨，共同构成一条可慢慢阅读的文明长廊。", 80, "4—5小时", "文化与户外",
                "山路较多，雨天注意防滑。", "演示数据", DEMO_IMAGE_CREDIT, DEMO_IMAGE_SOURCE,
                PoiImageAudit.PLACEHOLDER),
            new TravelModels.Poi("yuntai", "云台山", "焦作", "山水秘境", IMAGE_YUNTAI,
                "红石峡碧水丹崖，泉瀑峡银链垂空，把大自然的层次留给脚步。", 120, "1—2天", "自然风光爱好者",
                "适合晴天和低降雨时段，出行前核对景区天气。", "演示数据", DEMO_IMAGE_CREDIT, DEMO_IMAGE_SOURCE,
                PoiImageAudit.PLACEHOLDER),
            new TravelModels.Poi("qingming", "清明上河园", "开封", "宋韵生活", IMAGE_KAIFENG,
                "一朝步入画卷，一日梦回千年，宋韵市井在此重新展开。", 120, "半天—1天", "城市漫游",
                "适合安排在下午至夜游时段，关注演出时间。", "演示数据", DEMO_IMAGE_CREDIT, DEMO_IMAGE_SOURCE,
                PoiImageAudit.PLACEHOLDER)
        );
    }    public static List<TravelModels.Corridor> corridors() {
        return List.of(
            new TravelModels.Corridor("zheng-kai", "郑州—开封", "古都烟火里的宋韵一日", "郑州 · 开封", "1—2天", "¥300起", IMAGE_KAIFENG,
                List.of("古都文化", "夜游美食", "城市漫游")),
            new TravelModels.Corridor("zheng-luo", "郑州—洛阳", "沿着伊河读懂千年中原", "郑州 · 洛阳", "2—3天", "¥680起", IMAGE_LONGMEN,
                List.of("龙门石窟", "博物馆", "古都深度游")),
            new TravelModels.Corridor("jiao-yun", "焦作—云台山", "把山水留给周末的脚步", "焦作 · 云台山", "1—2天", "¥520起", IMAGE_YUNTAI,
                List.of("红石峡", "自然风光", "轻户外"))
        );
    }
}
