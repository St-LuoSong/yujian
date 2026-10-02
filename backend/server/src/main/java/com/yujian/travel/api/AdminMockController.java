package com.yujian.travel.api;

import com.yujian.travel.service.DemoScenarioService;
import com.yujian.travel.service.OperationLogService;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestController;

import java.util.UUID;

/**
 * Mock 数据管理。
 *
 * 只管理“演示模式的覆盖数据”，不管理真实用户数据，也不允许把演示数据伪装成实时数据。
 */
@RestController
@RequestMapping("/api/admin/mock/scenarios")
public class AdminMockController {
    private final DemoScenarioService demoScenarioService;
    private final OperationLogService operationLog;

    public AdminMockController(DemoScenarioService demoScenarioService, OperationLogService operationLog) {
        this.demoScenarioService = demoScenarioService;
        this.operationLog = operationLog;
    }

    @GetMapping
    public DemoScenarioService.MockCatalogView catalog() {
        return demoScenarioService.catalog();
    }

    @PutMapping("/{scenarioKey}/{matchKey}")
    public DemoScenarioService.ScenarioView upsert(@PathVariable String scenarioKey,
                                                   @PathVariable String matchKey,
                                                   @Valid @RequestBody UpsertMockRequest request) {
        DemoScenarioService.ScenarioView saved = demoScenarioService.upsert(
            scenarioKey, matchKey, request.name(), request.payloadJson(), request.note(), request.enabled());
        operationLog.record("MOCK_SCENARIO_UPSERT", scenarioKey + "/" + matchKey,
            "保存演示数据覆盖：" + saved.name());
        return saved;
    }

    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable UUID id) {
        demoScenarioService.delete(id);
        operationLog.record("MOCK_SCENARIO_DELETE", id.toString(), "删除演示数据覆盖");
    }

    public record UpsertMockRequest(
        @NotBlank(message = "名称不能为空")
        @Size(max = 120, message = "名称不能超过 120 个字符")
        String name,
        @NotBlank(message = "JSON 内容不能为空")
        @Size(max = 50000, message = "JSON 内容不能超过 50000 个字符")
        String payloadJson,
        @Size(max = 300, message = "说明不能超过 300 个字符")
        String note,
        boolean enabled
    ) {
    }
}
