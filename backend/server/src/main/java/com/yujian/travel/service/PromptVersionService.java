package com.yujian.travel.service;

import com.yujian.travel.ai.PromptDefaults;
import com.yujian.travel.common.ApiException;
import com.yujian.travel.domain.PromptVersionEntity;
import com.yujian.travel.repository.PromptVersionRepository;
import jakarta.annotation.PostConstruct;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.List;
import java.util.UUID;

/**
 * 系统提示词版本目录。
 *
 * 没有数据库版本时回退到 {@link PromptDefaults}，因此测试和空数据库都不会让规划失效。
 * 发布新版本会原子地取消旧版本启用状态，保证任一时刻最多只有一个 active 版本。
 */
@Service
public class PromptVersionService {
    private final PromptVersionRepository repository;

    public PromptVersionService(PromptVersionRepository repository) {
        this.repository = repository;
    }

    @PostConstruct
    void seedDefault() {
        if (repository == null || repository.count() > 0) {
            return;
        }
        PromptVersionEntity entity = new PromptVersionEntity();
        entity.setVersion(PromptDefaults.CURRENT_VERSION);
        entity.setSystemPrompt(PromptDefaults.SYSTEM_PROMPT);
        entity.setNote("系统内置基线版本");
        entity.setActive(true);
        repository.save(entity);
    }

    public String currentVersion() {
        return current().version();
    }

    public String currentSystemPrompt() {
        return current().systemPrompt();
    }

    public PromptVersionView current() {
        if (repository == null) {
            return defaultView();
        }
        return repository.findFirstByActiveTrueOrderByCreatedAtDesc()
            .map(this::view)
            .orElseGet(this::defaultView);
    }

    public List<PromptVersionView> list() {
        if (repository == null) {
            return List.of(defaultView());
        }
        List<PromptVersionView> versions = repository.findAllByOrderByCreatedAtDesc().stream()
            .map(this::view)
            .toList();
        return versions.isEmpty() ? List.of(defaultView()) : versions;
    }

    @Transactional
    public PromptVersionView create(String version, String systemPrompt, String note) {
        if (repository == null) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PROMPT_STORAGE_UNAVAILABLE",
                "当前运行环境没有启用提示词版本存储");
        }
        String cleanVersion = clean(version, "版本号不能为空");
        String cleanPrompt = clean(systemPrompt, "系统提示词不能为空");
        if (cleanVersion.length() > 64) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PROMPT_VERSION_TOO_LONG", "版本号不能超过 64 个字符");
        }
        if (cleanPrompt.length() > 20000) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "PROMPT_TOO_LONG", "系统提示词不能超过 20000 个字符");
        }
        if (repository.existsByVersion(cleanVersion)) {
            throw new ApiException(HttpStatus.CONFLICT, "PROMPT_VERSION_EXISTS", "版本号已存在，请换一个");
        }
        deactivateAll();
        PromptVersionEntity entity = new PromptVersionEntity();
        entity.setVersion(cleanVersion);
        entity.setSystemPrompt(cleanPrompt);
        entity.setNote(truncate(note, 200));
        entity.setActive(true);
        return view(repository.save(entity));
    }

    @Transactional
    public PromptVersionView activate(UUID id) {
        if (repository == null) {
            throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE, "PROMPT_STORAGE_UNAVAILABLE",
                "当前运行环境没有启用提示词版本存储");
        }
        PromptVersionEntity target = repository.findById(id)
            .orElseThrow(() -> new ApiException(HttpStatus.NOT_FOUND, "PROMPT_VERSION_NOT_FOUND",
                "提示词版本不存在"));
        if (!target.isActive()) {
            deactivateAll();
            target.setActive(true);
            target = repository.save(target);
        }
        return view(target);
    }

    private void deactivateAll() {
        if (repository == null) {
            return;
        }
        List<PromptVersionEntity> active = repository.findAllByActiveTrue();
        active.forEach(item -> item.setActive(false));
        repository.saveAll(active);
    }

    private PromptVersionView view(PromptVersionEntity entity) {
        return new PromptVersionView(entity.getId(), entity.getVersion(), entity.getSystemPrompt(),
            entity.getNote(), entity.isActive(), entity.getCreatedAt());
    }

    private PromptVersionView defaultView() {
        return new PromptVersionView(null, PromptDefaults.CURRENT_VERSION, PromptDefaults.SYSTEM_PROMPT,
            "系统内置基线版本", true, Instant.EPOCH);
    }

    private static String clean(String value, String message) {
        if (value == null || value.isBlank()) {
            throw new ApiException(HttpStatus.BAD_REQUEST, "VALIDATION_ERROR", message);
        }
        return value.trim();
    }

    private static String truncate(String value, int maxLength) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() <= maxLength ? trimmed : trimmed.substring(0, maxLength);
    }

    public record PromptVersionView(UUID id, String version, String systemPrompt, String note,
                                    boolean active, Instant createdAt) {
    }
}
