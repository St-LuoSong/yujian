package com.yujian.travel.security;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.service.AppSettingService;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 固定窗口限流。
 *
 * 选固定窗口而不是滑动窗口或令牌桶：这里的目的是"别让一个人把上游额度吃光"，
 * 不需要毫秒级平滑。固定窗口只在窗口交界处可能放进接近两倍的量，对防护目标无影响，
 * 但实现的复杂度低一个量级。
 *
 * 计数放在进程内存里 —— 与 AppSettingService 一样是单实例假设。多实例部署时
 * 每个实例各限一份，实际总量会翻倍；真要精确，这里换成 Redis。
 */
@Service
public class RateLimitService {
    /** 超过这个条目数就顺手清理一次过期窗口，避免被大量 IP 撑爆内存。 */
    private static final int PRUNE_THRESHOLD = 4096;

    private final AppSettingService settings;
    private final Map<String, Window> windows = new ConcurrentHashMap<>();
    private final AtomicLong lastPruneAt = new AtomicLong();

    public RateLimitService(AppSettingService settings) {
        this.settings = settings;
    }

    public record Decision(String bucket, boolean allowed, long limit, long remaining,
                           long retryAfterSeconds) {
    }

    private record Window(long startMillis, long count) {
    }

    /**
     * 依次检查多个桶，任意一个超限就拒绝。
     *
     * 「生成行程」同时挂每分钟与每日两个桶：前者防连点，后者是成本上限。
     * 两个都查过才计数，避免第一个桶放行、第二个桶拒绝时白扣一次额度。
     */
    public Decision check(List<String> bucketNames, String identity) {
        if (!settings.enabled(SecuritySettings.RATE_ENABLED)) {
            return new Decision("off", true, 0, 0, 0);
        }
        Decision denied = null;
        for (String bucketName : bucketNames) {
            Decision decision = checkOne(bucketName, identity);
            if (!decision.allowed()) {
                denied = decision;
                break;
            }
        }
        pruneIfNeeded();
        return denied == null
            ? new Decision(bucketNames.isEmpty() ? "none" : bucketNames.get(0), true, 0, 0, 0)
            : denied;
    }

    private Decision checkOne(String bucketName, String identity) {
        SecuritySettings.Bucket bucket = SecuritySettings.BUCKETS.stream()
            .filter(item -> item.name().equals(bucketName))
            .findFirst()
            .orElseThrow(() -> new IllegalArgumentException("未登记的限流桶：" + bucketName));
        long limit = Math.max(1, settings.longValue(bucket.limitKey()));
        long windowSeconds = Math.max(1, settings.longValue(bucket.windowKey()));
        long windowMillis = windowSeconds * 1000L;
        long now = System.currentTimeMillis();
        String key = bucketName + '|' + identity;
        Window window = windows.compute(key, (ignored, current) ->
            current == null || now - current.startMillis() >= windowMillis
                ? new Window(now, 1)
                : new Window(current.startMillis, current.count + 1));
        boolean allowed = window.count() <= limit;
        long retryAfter = Math.max(1,
            (window.startMillis() + windowMillis - now + 999) / 1000);
        return new Decision(bucketName, allowed, limit,
            Math.max(0, limit - window.count()), allowed ? 0 : retryAfter);
    }

    /** 过期窗口只是内存垃圾，不影响判断；这里只做最省事的一次性清理。 */
    private void pruneIfNeeded() {
        if (windows.size() < PRUNE_THRESHOLD) {
            return;
        }
        long now = System.currentTimeMillis();
        if (now - lastPruneAt.get() < 60_000L) {
            return;
        }
        lastPruneAt.set(now);
        long widest = SecuritySettings.BUCKETS.stream()
            .mapToLong(bucket -> Math.max(1, settings.longValue(bucket.windowKey())))
            .max()
            .orElse(3600) * 1000L;
        windows.entrySet().removeIf(entry -> now - entry.getValue().startMillis() >= widest);
    }

    /** 给管理台看的实时快照：当前有多少个活跃窗口。 */
    public int activeWindowCount() {
        return windows.size();
    }

    public ApiException tooManyRequests(Decision decision) {
        return new ApiException(HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED",
            "请求过于频繁，请 " + decision.retryAfterSeconds() + " 秒后再试");
    }
}
