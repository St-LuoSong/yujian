package com.yujian.travel.api;

import com.yujian.travel.service.OperationLogService;
import com.yujian.travel.service.PromptVersionService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PatchMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.UUID;

/**
 * 系统提示词版本管理。
 *
 * 这里管理的是“厂商无关的系统提示词”；用户请求、工具结果和解析规则仍由代码组装，
 * 避免运营人员一次误操作把工具调用约束或 JSON 契约删掉。
 */
@RestController
@RequestMapping("/api/admin/llm/prompts")
public class AdminPromptController {
    private final PromptVersionService promptVersionService;
    private final OperationLogService operationLog;

    public AdminPromptController(PromptVersionService promptVersionService, OperationLogService operationLog) {
        this.promptVersionService = promptVersionService;
        this.operationLog = operationLog;
    }

    @GetMapping
    public List<PromptVersionService.PromptVersionView> list() {
        return promptVersionService.list();
    }

    @GetMapping("/current")
    public PromptVersionService.PromptVersionView current() {
        return promptVersionService.current();
    }

    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    public PromptVersionService.PromptVersionView create(@Valid @RequestBody CreatePromptRequest request) {
        PromptVersionService.PromptVersionView created = promptVersionService.create(
            request.version(), request.systemPrompt(), request.note());
        operationLog.record("PROMPT_VERSION_CREATE", created.version(),
            "发布并启用系统提示词版本：" + created.version());
        return created;
    }

    @PatchMapping("/{id}/activate")
    public PromptVersionService.PromptVersionView activate(@PathVariable UUID id) {
        PromptVersionService.PromptVersionView activated = promptVersionService.activate(id);
        operationLog.record("PROMPT_VERSION_ACTIVATE", activated.version(),
            "启用系统提示词版本：" + activated.version());
        return activated;
    }

    public record CreatePromptRequest(
        @NotBlank(message = "版本号不能为空")
        @Size(max = 64, message = "版本号不能超过 64 个字符")
        String version,
        @NotBlank(message = "系统提示词不能为空")
        @Size(max = 20000, message = "系统提示词不能超过 20000 个字符")
        String systemPrompt,
        @Size(max = 200, message = "版本说明不能超过 200 个字符")
        String note
    ) {
    }
}
