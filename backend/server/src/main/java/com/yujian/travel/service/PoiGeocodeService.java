package com.yujian.travel.service;

import com.yujian.travel.api.PoiModels;
import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.baidu.BaiduMapClient;
import com.yujian.travel.map.PlaceTrust;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.Optional;

/**
 * 运营台的“解析坐标”能力：把景点名解析成一个**可以采信**的百度坐标。
 *
 * 三件事必须说清楚：
 *
 * 1. 只解析、不落库。运营人员点“解析坐标”，结果只是回填到表单里，
 *    是否保存由人决定，因此可以放心地反复试。
 * 2. 判据与行程地图完全一致（{@link PlaceTrust}）。地图上不敢画的坐标，
 *    运营台也不会替运营人员填进去 —— 两边一旦不一致，就会出现
 *    “后台存了坐标、地图却不肯打点”的怪现象。
 * 3. 不采信时不给半成品：只定位到城市、可信度不足、外部服务不可用，
 *    lng/lat 一律返回空，只带回一句人话解释。
 */
@Service
public class PoiGeocodeService {
    private static final Logger log = LoggerFactory.getLogger(PoiGeocodeService.class);

    /** 数据来源口径：界面与文档都按这个字符串展示。 */
    private static final String SOURCE = "百度地图地理编码";

    private final BaiduMapClient baiduMapClient;
    private final AppProperties properties;

    public PoiGeocodeService(BaiduMapClient baiduMapClient, AppProperties properties) {
        this.baiduMapClient = baiduMapClient;
        this.properties = properties;
    }

    /**
     * 解析一个景点名。
     *
     * @param name 景点名称，必填
     * @param city 运营台当前选填的城市，用作地理编码的城市限定
     */
    public PoiModels.GeocodePreview preview(String name, String city) {
        String query = name == null ? "" : name.trim();
        String hint = city == null ? "" : city.trim();

        if (query.isEmpty()) {
            return rejected(query, hint, "请先填写景点名称，再解析坐标。");
        }
        if (!baiduMapClient.configured()) {
            return rejected(query, hint, "服务端未配置百度地图 AK，无法解析坐标，请手工填写经纬度。");
        }
        // 标题自带城市时以标题为准：“洛阳博物馆”配郑州做限定会被解析成郑州市中心。
        if (hint.isEmpty()) {
            hint = PlaceTrust.cityInTitle(query).orElse("");
        }
        if (hint.isEmpty()) {
            // 没有城市限定就等于让百度在全国范围内猜：实测"随便走走"会被解析到
            // 深圳的一家餐厅。宁可让运营人员多填一格，也不给一个别的省份的坐标。
            return rejected(query, hint, "请先填写所属城市（或让景点名带上城市），再解析坐标。");
        }

        Optional<BaiduMapClient.GeocodeResult> resolved;
        try {
            resolved = baiduMapClient.geocodePlace(query, hint);
        } catch (ExternalServiceException failure) {
            log.warn("Operator geocode failed for '{}': {}", query, failure.getMessage());
            return rejected(query, hint,
                "百度地图暂时不可用（" + failure.getMessage() + "），请稍后重试或手工填写经纬度。");
        }
        if (resolved.isEmpty()) {
            return rejected(query, hint, "百度地图没有返回可用坐标，请检查景点名称，或手工填写经纬度。");
        }

        BaiduMapClient.GeocodeResult result = resolved.get();
        String coarse = PlaceTrust.coarseLevelReason(result.level());
        if (coarse != null) {
            return rejected(query, hint, coarse + "，请补充更具体的名称，或直接手工填写经纬度。");
        }
        String outOfRegion = PlaceTrust.outOfRegionReason(result.lng(), result.lat());
        if (outOfRegion != null) {
            return rejected(query, hint, outOfRegion + "，请检查景点名称与所属城市。");
        }
        int minConfidence = Math.max(0, properties.getTools().getBaidu().getMapMinConfidence());
        if (result.confidence() < minConfidence) {
            return rejected(query, hint,
                "坐标可信度不足（" + result.confidence() + "），请手工确认后再保存。");
        }

        String level = result.level() == null ? "" : result.level().trim();
        // 低可信度不代表不能用（白马寺、龙门石窟这类景点百度只给 25 分），
        // 但必须如实告诉运营人员"这是参考值，请核对"，不能让人以为已经板上钉钉。
        String nextStep = result.confidence() < 60
            ? "。可信度偏低，请在地图上核对后再保存。"
            : "。保存后行程地图会优先使用这个坐标。";
        return new PoiModels.GeocodePreview(
            query,
            blankToNull(hint),
            round6(result.lng()),
            round6(result.lat()),
            level,
            result.confidence(),
            true,
            SOURCE,
            "已解析到" + (level.isEmpty() ? "可信坐标" : level) + "，可信度 " + result.confidence() + nextStep);
    }

    private static PoiModels.GeocodePreview rejected(String query, String hint, String message) {
        return new PoiModels.GeocodePreview(
            query, blankToNull(hint), null, null, "", 0, false, SOURCE, message);
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value;
    }

    private static double round6(double value) {
        return Math.round(value * 1_000_000d) / 1_000_000d;
    }
}
