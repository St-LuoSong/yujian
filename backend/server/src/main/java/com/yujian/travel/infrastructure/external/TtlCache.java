package com.yujian.travel.infrastructure.external;

import org.springframework.stereotype.Component;

import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * 极简的进程内 TTL 缓存。
 *
 * 外部服务（天气、地图）都有配额与延迟，重复调用既慢又浪费额度。
 * 这里刻意不引入 Caffeine 之类的依赖：比赛演示规模下，一个 ConcurrentHashMap 足够，
 * 而且失败短路的语义比完整的缓存库更直观。
 */
@Component
public class TtlCache {
    private final Map<String, Slot> values = new ConcurrentHashMap<>();
    private final Map<String, Instant> suppressed = new ConcurrentHashMap<>();

    public <T> CachedResult<T> get(String key, Class<T> type) {
        Slot slot = values.get(key);
        if (slot == null) {
            return null;
        }
        if (slot.expiresAt().isBefore(Instant.now())) {
            values.remove(key);
            return null;
        }
        return new CachedResult<>(type.cast(slot.value()), slot.source(), slot.expiresAt());
    }

    public void put(String key, Object value, String source, Duration ttl) {
        values.put(key, new Slot(value, source, Instant.now().plus(ttl)));
        suppressed.remove(key);
    }

    /** 外部服务刚失败过：在一个短窗口内直接走降级，避免每次规划都等超时。 */
    public boolean isSuppressed(String key) {
        Instant until = suppressed.get(key);
        if (until == null) {
            return false;
        }
        if (until.isBefore(Instant.now())) {
            suppressed.remove(key);
            return false;
        }
        return true;
    }

    public void suppress(String key, Duration window) {
        suppressed.put(key, Instant.now().plus(window));
    }

    public int size() {
        return values.size();
    }

    public record Slot(Object value, String source, Instant expiresAt) {
    }

    public record CachedResult<T>(T data, String source, Instant expiresAt) {
    }
}
