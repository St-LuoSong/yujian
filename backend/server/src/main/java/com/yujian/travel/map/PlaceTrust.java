package com.yujian.travel.map;

import java.util.List;
import java.util.Optional;

/**
 * “这句话能不能当成一个可信的地点”的统一判据。
 *
 * 行程地图的打点和运营台的“解析坐标”按钮必须用同一份规则：判据只写一遍，
 * 才不会出现“地图上不敢画、运营台却存进库”这种自相矛盾的行为。
 */
public final class PlaceTrust {
    private PlaceTrust() {
    }

    /**
     * 只定位到行政区域的 level。
     *
     * 这是“要不要采信”的主判据：百度对“随便走走”“asdfghjkl”这类文本会返回
     * status=0、level=城市、confidence=20 —— 坐标其实是城市中心，存下来等于撒谎。
     * 反过来，白马寺、龙门石窟这类真实景点只给 25 分，却带 level=乡镇，必须放行。
     * 所以判据是 level，不是分数。
     */
    private static final List<String> COARSE_LEVELS = List.of("国家", "省", "直辖市", "城市", "区县");

    /** 河南主要城市，用于给地理编码一个城市限定。顺序即优先级。 */
    public static final List<String> HENAN_CITIES = List.of(
        "郑州", "洛阳", "开封", "焦作", "登封", "安阳", "南阳", "新乡", "许昌",
        "信阳", "商丘", "平顶山", "三门峡", "驻马店", "周口", "漯河", "濮阳", "鹤壁", "济源");

    /**
     * 返回不能采信的原因；能定位到具体地点时返回 null。
     *
     * @param level 百度地理编码返回的 level，例如“旅游景点”“乡镇”“城市”
     */
    public static String coarseLevelReason(String level) {
        if (level == null || level.isBlank()) {
            return null;
        }
        for (String coarse : COARSE_LEVELS) {
            if (level.equals(coarse)) {
                return "只定位到" + coarse + "级，无法确定具体位置";
            }
        }
        return null;
    }

    /**
     * 河南范围（含约 30 公里外扩）。
     *
     * 内容库只服务河南，所以落到这个范围之外的坐标几乎一定是错的。真实踩坑：
     * 输入"随便走走"且不限定城市时，百度会把它解析到深圳的一家餐厅，
     * level=餐饮、confidence=80 —— 光看 level 和分数完全看不出问题，
     * 只有坐标本身露馅。因此宁可拒绝并提示，也不要把一个广东的坐标
     * 写进河南的景点库、画到河南的行程地图上。
     */
    private static final double MIN_LNG = 110.0;
    private static final double MAX_LNG = 117.0;
    private static final double MIN_LAT = 31.0;
    private static final double MAX_LAT = 36.6;

    /**
     * 返回"不在河南范围内"的原因；在范围内时返回 null。
     */
    public static String outOfRegionReason(double lng, double lat) {
        if (lng >= MIN_LNG && lng <= MAX_LNG && lat >= MIN_LAT && lat <= MAX_LAT) {
            return null;
        }
        return "解析结果落在河南范围之外（" + round4(lng) + ", " + round4(lat) + "）";
    }

    private static double round4(double value) {
        return Math.round(value * 10_000d) / 10_000d;
    }

    /**
     * 标题里明确提到的河南城市。
     *
     * “洛阳博物馆”配郑州做限定会被解析成郑州市中心，所以标题自带城市时以标题为准。
     */
    public static Optional<String> cityInTitle(String title) {
        if (title == null || title.isBlank()) {
            return Optional.empty();
        }
        for (String city : HENAN_CITIES) {
            if (title.contains(city)) {
                return Optional.of(city);
            }
        }
        return Optional.empty();
    }
}
