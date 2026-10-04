package com.yujian.travel.service;

import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.AppSettingEntity;
import com.yujian.travel.repository.AppSettingRepository;
import com.yujian.travel.security.SecuritySettings;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.Map;

/**
 * 运行时设置。读多写少，整份快照缓存在内存里，写入时整体作废。
 *
 * 缓存是有意的：限流每次请求都要读两三个值，直连数据库会把限流本身变成负担。
 * 代价是**单实例假设** —— 多实例部署时各进程各有一份快照，改完设置要过一会儿
 * 才在全部实例上生效（写入方自己的那份是立刻生效的）。真要多实例，这里换 Redis。
 */
@Service
public class AppSettingService {
    private final AppSettingRepository repository;
    private volatile Map<String, Long> cache;

    public AppSettingService(AppSettingRepository repository) {
        this.repository = repository;
    }

    public long longValue(String key) {
        SecuritySettings.Definition definition = SecuritySettings.find(key)
            .orElseThrow(() -> new IllegalArgumentException("未登记的设置：" + key));
        return snapshot().getOrDefault(definition.key(), definition.defaultValue());
    }

    public boolean enabled(String key) {
        return longValue(key) != 0;
    }

    @Transactional(readOnly = true)
    public Map<String, Long> values() {
        return snapshot();
    }

    @Transactional
    public Map<String, Long> update(Map<String, Long> updates) {
        for (Map.Entry<String, Long> entry : updates.entrySet()) {
            SecuritySettings.Definition definition = SecuritySettings.find(entry.getKey())
                .orElseThrow(() -> new ApiException(HttpStatus.BAD_REQUEST, "SETTING_UNKNOWN",
                    "不认识的设置项：" + entry.getKey()));
            long value = entry.getValue() == null ? definition.defaultValue() : entry.getValue();
            if (value < definition.min() || value > definition.max()) {
                throw new ApiException(HttpStatus.BAD_REQUEST, "SETTING_OUT_OF_RANGE",
                    definition.label() + " 必须在 " + definition.min() + "—" + definition.max() + " 之间");
            }
            AppSettingEntity entity = repository.findById(definition.key())
                .orElseGet(AppSettingEntity::new);
            entity.setKey(definition.key());
            entity.setValue(Long.toString(value));
            repository.save(entity);
        }
        cache = null;
        return snapshot();
    }

    /** 顺手把设置恢复成登记表里的默认值。 */
    @Transactional
    public Map<String, Long> resetToDefaults() {
        repository.deleteAll();
        cache = null;
        return snapshot();
    }

    private Map<String, Long> snapshot() {
        Map<String, Long> current = cache;
        if (current != null) {
            return current;
        }
        synchronized (this) {
            if (cache != null) {
                return cache;
            }
            Map<String, Long> loaded = new HashMap<>();
            for (SecuritySettings.Definition definition : SecuritySettings.definitions()) {
                loaded.put(definition.key(), definition.defaultValue());
            }
            for (AppSettingEntity entity : repository.findAll()) {
                SecuritySettings.find(entity.getKey()).ifPresent(definition ->
                    loaded.put(definition.key(), parse(entity.getValue(), definition)));
            }
            cache = Map.copyOf(loaded);
            return cache;
        }
    }

    /**
     * 脏值不让服务起不来：有人直接改数据库改坏了，这里回落到默认值并夹进合法区间，
     * 而不是在每次请求上抛异常。
     */
    private static long parse(String raw, SecuritySettings.Definition definition) {
        try {
            long value = Long.parseLong(raw == null ? "" : raw.trim());
            return Math.max(definition.min(), Math.min(definition.max(), value));
        } catch (NumberFormatException ignored) {
            return definition.defaultValue();
        }
    }
}
