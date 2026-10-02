# 阶段三：AI 规划引擎与工具编排

## 已完成范围

- 抽象 `PlanningEngine` 规划端口，业务层不直接依赖具体模型。
- 接入 LangChain4j 0.35.0 与 `langchain4j-open-ai`。
- 支持三级规划策略：
  1. LangChain4j 主引擎；
  2. OpenAI 兼容 HTTP 引擎备选；
  3. Mock 规划引擎稳定降级。
- 抽象统一工具结果 `ToolResult`：
  - `data`
  - `source`
  - `queriedAt`
  - `isRealtime`
  - `isCached`
  - `isMock`
  - `expiresAt`
  - `errorCode`
  - `errorMessage`
- 实现五类工具编排：
  - 景点检索；
  - 天气查询；
  - 路线查询；
  - 车次查询；
  - 景区开放时间查询。
- 增加行程可执行性校验：
  - 每日景点数量；
  - 预算上限；
  - 降水与户外活动；
  - 外部工具失败降级；
  - 节点风险提示。
- 增加工具调用轨迹持久化与查询接口。
- 增加今日行程天气说明。
- LLM 未配置或调用失败时自动回退 Mock，不影响演示。

## LLM 多供应商配置

> 本节已按阶段五更新。旧版的 `LLM_BASE_URL` / `LLM_API_KEY` / `LLM_MODEL` /
> `LLM_CHAT_PATH` 四个变量已废弃，改为每个供应商一组变量。

四家供应商都提供 OpenAI 兼容的 chat completions 接口，因此共用一套引擎实现，
差异全部落在配置里。按 `priority` 从小到大尝试，某家失败自动降级到下一家，
全部失败后由 Mock 引擎兜底并标注“演示数据（AI 降级）”。

```text
LLM_ENABLED=true              # 总开关
LLM_TEMPERATURE=0.3           # 全局默认，可被单个供应商覆盖
LLM_TIMEOUT_SECONDS=60

LLM_OPENAI_ENABLED=true       LLM_OPENAI_API_KEY=...   LLM_OPENAI_MODEL=gpt-4o-mini
                              LLM_OPENAI_BASE_URL=https://api.openai.com/v1
                              LLM_OPENAI_PRIORITY=10

LLM_DEEPSEEK_ENABLED=true     LLM_DEEPSEEK_API_KEY=... LLM_DEEPSEEK_MODEL=deepseek-chat
                              LLM_DEEPSEEK_BASE_URL=https://api.deepseek.com/v1
                              LLM_DEEPSEEK_PRIORITY=20

LLM_KIMI_ENABLED=true         LLM_KIMI_API_KEY=...     LLM_KIMI_MODEL=moonshot-v1-8k
                              LLM_KIMI_BASE_URL=https://api.moonshot.cn/v1
                              LLM_KIMI_PRIORITY=30

LLM_QWEN_ENABLED=true         LLM_QWEN_API_KEY=...     LLM_QWEN_MODEL=qwen-plus
                              LLM_QWEN_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
                              LLM_QWEN_PRIORITY=40
```

要求：

- 密钥只能保存在服务端环境变量中，不写入 APK、管理台或代码仓库；
- 只启用一家也能正常工作；未填 `api-key` 的供应商会被跳过，并在运营接口里显示为
  “已启用但未配置”，而不是被静默尝试；
- `base-url` 必须包含版本段（如 `/v1`），聊天路径由客户端自动追加；
- LLM 只能使用工具编排返回的数据，不得伪造实时票价、车次、天气或购票状态；
- LLM 输出必须是严格 JSON，解析失败会自动降级。

### 运营可见性

`GET /api/admin/llm/providers`（需要 `ADMIN` 角色）返回：

- 总开关状态与当前生效的供应商；
- 按优先级排列的实际选择顺序；
- 每个供应商的 `enabled` / `configured` / `model` / `priority` / `baseUrl`；
- 每个供应商的成功次数、失败次数、最近耗时、最近错误。

响应中**不包含任何密钥**（已有测试覆盖）。运营账号通过 `ADMIN_USERNAME` /
`ADMIN_PASSWORD` 在启动时创建或提升，留空则不创建特权账号。

## 关键文件

```text
server/src/main/java/com/yujian/travel/
├── ai/
│   ├── PlanningEngine.java
│   ├── LangChain4jPlanningEngine.java
│   ├── OpenAiCompatiblePlanningEngine.java
│   ├── MockPlanningEngine.java
│   ├── TravelPlanningFacade.java
│   ├── PlanningPromptFactory.java
│   ├── LlmPlanParser.java
│   └── TripPlanValidator.java
└── tools/
    ├── ToolResult.java
    ├── ToolCollection.java
    ├── ToolModels.java
    ├── MockTravelTools.java
    └── ToolOrchestrator.java
```

## 查询行程依据

新增接口：

```text
GET /api/trip-plans/{id}/trace
```

返回内容：

- 使用的规划引擎；
- 提示词版本；
- 行程数据状态；
- Mock 工具数量；
- 行程风险提示；
- 每个工具的来源、数据状态、成功情况、输出摘要和耗时。

## 下一阶段

1. 将 Mock 工具替换为百度地图 MCP 客户端。
2. 将 12306 适配从 Mock 替换为授权接口或演示服务。
3. 增加 Redis 缓存与工具结果 TTL。
4. 管理台增加 AI 运行、工具成功率、Mock 降级次数和错误趋势图表。
5. Flutter 行程页增加“查看依据”和工具数据来源展示。
