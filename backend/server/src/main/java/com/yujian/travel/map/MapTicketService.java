package com.yujian.travel.map;

import com.yujian.travel.config.AppProperties;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.Locale;

/**
 * 底图取图票据。
 *
 * 底图由服务端拿着 AK 去百度取，再把 PNG 转发给客户端 —— 这是本项目
 * "AK 只留在服务端" 原则的直接结果。但这样会带来一个新的风险：
 * 如果取图接口完全公开，任何人都能拿它当免费代理刷百度的配额。
 *
 * 所以取图必须带票：票据由登录态（含匿名会话）拿到快照时签发，
 * 内容只有"这组参数的签名 + 过期时间"，不含用户身份，也不含 AK。
 *
 * 票据按整点分桶签发，同一小时内同一组参数的 URL 完全一致，
 * 客户端的磁盘缓存因此仍然有效；换钟点只是换一次 URL，代价很小。
 */
@Service
public class MapTicketService {
    /** 一小时一个桶：桶内 URL 稳定，便于客户端缓存。 */
    private static final long WINDOW_SECONDS = 3600;
    /** 签发时给出两个桶的有效期，保证跨桶瞬间不会立刻失效。 */
    private static final long WINDOWS_PER_TICKET = 2;
    private static final String ALGORITHM = "HmacSHA256";

    private final byte[] secret;

    public MapTicketService(AppProperties properties) {
        String configured = properties.getJwt().getSecret();
        this.secret = (configured == null || configured.isBlank()
            ? "yujian-travel-map-ticket"
            : configured).getBytes(StandardCharsets.UTF_8);
    }

    /** 一组底图参数的规范串，签名与校验必须用同一个。 */
    public static String canonical(double centerLng, double centerLat, int zoom, int width, int height) {
        return String.format(Locale.ROOT, "%.6f,%.6f|%d|%d|%d",
            centerLng, centerLat, zoom, width, height);
    }

    /** 当前时刻应使用的票据值。 */
    public String issue(String canonical, long epochSeconds) {
        long expiresAt = (epochSeconds / WINDOW_SECONDS + WINDOWS_PER_TICKET) * WINDOW_SECONDS;
        return expiresAt + "." + signature(canonical, expiresAt);
    }

    /** 票据是否可用于这组参数。 */
    public boolean verify(String canonical, String ticket, long epochSeconds) {
        if (canonical == null || ticket == null) {
            return false;
        }
        int dot = ticket.indexOf('.');
        if (dot <= 0 || dot == ticket.length() - 1) {
            return false;
        }
        long expiresAt;
        try {
            expiresAt = Long.parseLong(ticket.substring(0, dot));
        } catch (NumberFormatException invalid) {
            return false;
        }
        if (expiresAt <= epochSeconds) {
            return false;
        }
        // 上限只是缩小伪造面：即便有人拿到一个很旧的合法票据，也不能长期复用。
        if (expiresAt > epochSeconds + 3 * WINDOW_SECONDS) {
            return false;
        }
        byte[] expected = signature(canonical, expiresAt).getBytes(StandardCharsets.UTF_8);
        byte[] presented = ticket.substring(dot + 1).getBytes(StandardCharsets.UTF_8);
        return MessageDigest.isEqual(expected, presented);
    }

    /** 票据有效期（秒），用于给客户端设置缓存时长。 */
    public long remainingSeconds(String ticket, long epochSeconds) {
        int dot = ticket == null ? -1 : ticket.indexOf('.');
        if (dot <= 0) {
            return 0;
        }
        try {
            return Math.max(0, Long.parseLong(ticket.substring(0, dot)) - epochSeconds);
        } catch (NumberFormatException invalid) {
            return 0;
        }
    }

    private String signature(String canonical, long expiresAt) {
        try {
            Mac mac = Mac.getInstance(ALGORITHM);
            mac.init(new SecretKeySpec(secret, ALGORITHM));
            byte[] digest = mac.doFinal((canonical + "|" + expiresAt).getBytes(StandardCharsets.UTF_8));
            return HexFormat.of().formatHex(digest);
        } catch (Exception failure) {
            throw new IllegalStateException("无法为底图票据签名", failure);
        }
    }
}
