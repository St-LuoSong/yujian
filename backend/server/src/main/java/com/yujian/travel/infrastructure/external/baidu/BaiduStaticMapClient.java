package com.yujian.travel.infrastructure.external.baidu;

import com.yujian.travel.config.AppProperties;
import com.yujian.travel.infrastructure.external.ExternalServiceException;
import com.yujian.travel.infrastructure.external.HttpJsonClient;
import com.yujian.travel.infrastructure.external.TtlCache;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;

/**
 * 百度静态底图适配器。
 *
 * 为什么用静态图接口，而不是在 APK 里塞百度 Android SDK：
 *
 * 1. 官方 Android SDK 与第三方 Flutter 插件都要求把 AK 打进安装包；
 *    本项目对外承诺"AK 只留在服务端"，两者直接冲突，而 AK 泄漏的成本是配额被别人刷光。
 * 2. 底层是同一份百度瓦片，画质与标注完全一致，只是由服务端取一张 1024 像素的图，
 *    再由客户端把自定义标记与折线画在上面 —— 视觉反而更统一。
 * 3. 不引入原生依赖，也就没有 32/64 位 ABI、插件常年失修、许可证不明这些风险。
 *
 * 代价必须说清楚：静态图没有手势连续缩放，也没有实时路况图层。
 * 客户端的做法是"拖动后重新取图 + 按钮缩放"，界面文案明确写"底图不含实时路况"。
 *
 * 底图本身变化极慢（道路与标注按天级别更新），因此做了小时级缓存：
 * 一个班次内的所有请求只会真正打到百度一次。
 */
@Component
public class BaiduStaticMapClient {
    private static final Logger log = LoggerFactory.getLogger(BaiduStaticMapClient.class);
    private static final int MIN_EDGE = 320;
    private static final int MAX_EDGE = 1024;
    private static final byte[] PNG_MAGIC = {(byte) 0x89, 'P', 'N', 'G'};

    private final HttpJsonClient httpJsonClient;
    private final AppProperties properties;
    private final TtlCache cache;

    public BaiduStaticMapClient(HttpJsonClient httpJsonClient, AppProperties properties, TtlCache cache) {
        this.httpJsonClient = httpJsonClient;
        this.properties = properties;
        this.cache = cache;
    }

    public boolean configured() {
        String key = properties.getTools().getBaidu().getApiKey();
        return key != null && !key.isBlank();
    }

    /** 一张底图，附带它是不是来自缓存。 */
    public record StaticImage(byte[] bytes, String contentType, boolean cached, Instant expiresAt) {
    }

    public StaticImage fetch(double lng, double lat, int zoom, int width, int height) {
        if (!configured()) {
            throw new ExternalServiceException("BAIDU_AK_MISSING", "未配置百度地图 AK，底图不可用");
        }
        int safeWidth = clampEdge(width);
        int safeHeight = clampEdge(height);
        int safeZoom = Math.max(3, Math.min(19, zoom));
        String key = cacheKey(lng, lat, safeZoom, safeWidth, safeHeight);

        TtlCache.CachedResult<StaticImage> hit = cache.get(key, StaticImage.class);
        if (hit != null) {
            return new StaticImage(hit.data().bytes(), hit.data().contentType(), true, hit.expiresAt());
        }

        Map<String, String> query = new LinkedHashMap<>();
        query.put("ak", apiKey());
        query.put("center", String.format(Locale.ROOT, "%.6f,%.6f", lng, lat));
        query.put("zoom", Integer.toString(safeZoom));
        query.put("width", Integer.toString(safeWidth));
        query.put("height", Integer.toString(safeHeight));
        // 不加 markers：标记与折线由客户端绘制，这样颜色、编号和命中区域都由本项目控制。

        HttpJsonClient.BinaryResponse response = httpJsonClient.getBinary(
            baseUrl() + properties.getTools().getBaidu().getStaticMapPath(),
            query,
            properties.getTools().getBaidu().getMapTimeoutSeconds());

        if (!response.successful()) {
            throw new ExternalServiceException("BAIDU_STATIC_HTTP_" + response.status(),
                "百度静态底图返回 " + response.status());
        }
        // 百度在鉴权或配额失败时会用 200 + JSON 正文回答，只检查状态码会把错误当成图片，
        // 最后表现为客户端"图片加载失败"这种看不出原因的故障。
        if (!looksLikePng(response.body())) {
            log.warn("Baidu static map answered without a PNG body ({} bytes): {}",
                response.body().length, response.bodyPreview());
            throw new ExternalServiceException("BAIDU_STATIC_NOT_IMAGE", "百度静态底图未返回图片");
        }

        Duration ttl = Duration.ofMinutes(Math.max(1, properties.getTools().getBaidu().getMapCacheMinutes()));
        StaticImage image = new StaticImage(response.body(),
            response.contentType() == null ? "image/png" : response.contentType(), false, Instant.now().plus(ttl));
        cache.put(key, image, "百度地图静态图", ttl);
        return image;
    }

    private static boolean looksLikePng(byte[] body) {
        if (body == null || body.length < PNG_MAGIC.length) {
            return false;
        }
        for (int i = 0; i < PNG_MAGIC.length; i++) {
            if (body[i] != PNG_MAGIC[i]) {
                return false;
            }
        }
        return true;
    }

    private static int clampEdge(int value) {
        return Math.max(MIN_EDGE, Math.min(MAX_EDGE, value));
    }

    private static String cacheKey(double lng, double lat, int zoom, int width, int height) {
        return String.format(Locale.ROOT, "baidu:static:%.6f,%.6f:%d:%dx%d", lng, lat, zoom, width, height);
    }

    private String baseUrl() {
        return properties.getTools().getBaidu().getBaseUrl();
    }

    private String apiKey() {
        return properties.getTools().getBaidu().getApiKey();
    }
}
