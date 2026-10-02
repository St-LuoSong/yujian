# 阶段十一 T11.1：真正接上大模型

> 目标：把"项目定位是联动 LLM，但一家都没启用"这个 P0 缺口补掉，
> 并且**用真实调用验证**，而不是把开关改成 true 就宣布完成。
>
> 这一阶段最有价值的产出不是"配置好了"，而是**打开开关后立刻暴露的两个真实缺陷**——
> 它们只有在真正调用模型时才会出现，之前用不可达端口做的降级测试永远测不到。

## 1. 起点：开关一直是关的

| 项 | 状态 |
| --- | --- |
| 四家 provider 代码 | 就绪（OpenAI / DeepSeek / Kimi / Qwen，统一适配 + 按 priority 降级） |
| `LLM_ENABLED` | `false` |
| 系统里的 `LLM_*` 环境变量 | 一个都没有 |
| 实际生成方案的是 | 确定性 Mock 引擎（工具数据仍为真实：天气 / 路线 / 车次） |

所以界面上一直显示"演示数据（AI 降级）"，那是**如实标注**，不是 bug。

## 2. 配置位置的第二次踩坑

用户把新申请的百度 AK 与 DeepSeek Key 都写进了 `.env.example`。

`.env.example` 是**随仓库分发的模板**（`.gitignore` 里 `!.env.example` 显式放行），
启动脚本加载的是 `scripts\local.env`。后果与阶段十那次完全一样：
配置不生效 + 密钥进入版本库。

处置：

1. 把 AK 与 Key 迁到 `scripts\local.env`（git-ignored）；
2. 打开 `LLM_ENABLED=true` 与 `LLM_DEEPSEEK_ENABLED=true`；
3. 模板恢复空占位，并在两个易错位置加上显式警告注释；
4. **提交前自检**：任何模板文件里都不该出现 `sk-` 或 32 位 AK 形态的字符串。

## 3. 凭据先单独验证，再进主链路

按"最小有效测试"原则，先用一次直连请求确认凭据有效，避免把"密钥错"误判成"代码错"：

```text
百度 AK   GET place/v2/search?query=龙门石窟
          -> HTTP 200 status=0 msg=ok results[0]=龙门石窟

DeepSeek  POST /v1/chat/completions  max_tokens=16
          -> HTTP 200  content="可用"  （只花 1 个 completion token）
```

两个都通过，才重启后端加载新配置。

## 4. 打开开关后暴露的第一个缺陷：解析器太严格

第一次真实规划的结果：

```text
engine       = mock-fallback
dataStatus   = 演示数据（AI 降级）
deepseek     = ok=0 fail=1  lastError="LLM 返回的行程 JSON 无法解析"
耗时          = 6356ms
```

耗时 6 秒说明**调用是成功的**，模型也返回了内容；问题在解析。

原实现用 `ObjectMapper.readValue(..., LlmPlan.class)` 做严格对象绑定。
真实模型不会像单元测试那样听话：

| 模型的实际写法 | 严格绑定的后果 |
| --- | --- |
| `"cost": "约120元"` | 无法转成 `Integer` → 整份方案报废 |
| `"warnings": "门票仅供参考"` | 无法转成 `List<String>` → 整份方案报废 |
| `"time": "建议上午出发…"` | 能解析，但后面落库时爆（见第 5 节） |
| 用 ```json 包住 / 前后加一句说明 | 已被裁剪逻辑容错 |

**修法**：重写为基于 `JsonNode` 的**逐字段宽松解析**。

- 字符串字段：数字、布尔也当文本取出；
- `cost`：数字直接取；文本则扫描出第一个整数字串（`"约120元"` → 120，`"免费"` → 0）；
- `warnings`：数组或单句都接受；
- 容忍 Markdown 代码块、前后说明文字、对象/数组末尾的多余逗号
  （去逗号时会跟踪字符串状态，不会破坏字符串里的逗号）；
- 必填项只有 `days`；缺失时抛出的异常**带上原始输出片段**，便于定位是提示词问题还是模型问题。

## 5. 打开开关后暴露的第二个缺陷：一次超长字符串让生成变 500

宽松解析之后，DeepSeek 调用成功（`ok=1 fail=0`），但 `POST /api/trip-plans` 返回 **500**：

```text
H2: Value too long for column "start_time CHARACTER VARYING(16)":
    "建议上午出发，具体车次以铁路官方为准"
```

模型把一句建议写进了 `time` 字段，而该列宽 16。
一次本该成功的生成，用户什么都没拿到。

**两层修法：**

1. **语义纠正（解析层）**：`time` 是时钟值，不是句子。
   `normalizeTime()` 从文本里抽取 `H:mm`/`HH:mm`（`"9:5"` → `09:05`，`"18:30 左右"` → `18:30`），
   抽不出才退回默认值。
2. **长度兜底（落库边界）**：新增 `ColumnText.clamp(value, maxLength)`，
   在 `TripPlanService` 写库前按实体声明的列宽统一截断
   （方案标题/摘要/走廊/强度/提示词/引擎名、每日 label、每个节点的类型/标题/描述/
   起止时间/交通/来源/状态/风险、以及每条 warning）。
   截断时不会把 emoji 的代理对从中间切开。

原则：**宁可截断一个字段，也不能让整份方案 500。**

## 6. 验证证据

```text
node scripts\verify-llm.mjs
  通过 12 项，失败 0 项
  llmEnabled=true
  selectionOrder=["deepseek"]
  deepseek enabled=true configured=true model=deepseek-chat
  生成行程 -> status=201 dataStatus=AI 生成
  规划引擎是真实模型，不是 Mock 兜底 -> engine=deepseek
  方案未被标注为 AI 降级 -> dataStatus=AI 生成
  deepseek 调用统计 -> ok=1 fail=0
  供应商响应里不含任何密钥 -> ok

mvn -o -B test
  Tests run: 25, Failures: 0, Errors: 0

数据源健康度（不消耗 token）
  weather = ready   route = ready   railway = ready   ticket = ready
```

`scripts\verify-llm.mjs` 是本次新增的**最小化**校验脚本：
除第 2 节那次真实规划外，其余断言都不消耗 token。
它同时修掉了一个自身缺陷——调用统计原本在规划**之前**读取，导致永远显示"无记录"，
把真正的失败原因藏掉了。

## 7. 新增/修改文件

| 文件 | 动作 |
| --- | --- |
| `server/.../ai/LlmPlanParser.java` | 重写为宽松解析 + 时间归一化 + 错误带原文片段 |
| `server/.../ai/LangChain4jPlanningEngine.java` | 显式设置 `maxTokens=4096`，避免各家默认值不同导致截断 |
| `server/.../service/ColumnText.java` | 新增列宽兜底工具 |
| `server/.../service/TripPlanService.java` | 26 处写库调用统一按列宽截断 |
| `server/.../ai/LlmPlanParserTest.java` | 新增 12 项用例，全部对真实模型的写法建模 |
| `server/.../service/ColumnTextTest.java` | 新增 4 项用例 |
| `scripts/verify-llm.mjs` | 新增最小化 LLM 校验 |
| `scripts/local.env` | 启用 DeepSeek（git-ignored，不进入仓库） |
| `.env.example` | 恢复空占位 + 两处防误填警告 |

## 8. 遗留

- 只有 DeepSeek 一家启用。按计划"不能只接一家"，OpenAI / Kimi / Qwen 保持
  `enabled=false` 但配置项与降级顺序完整，需要时打开即可；
- 降级路径（把密钥改错 → 逐级降级 → 全部失败仍返回可用方案）本次未再跑，
  已有单元测试覆盖（`TravelPlanningFacadeTest`）；
- LLM 生成内容的**事实性**仍需依赖工具层约束：提示词已明确"只能使用提供的工具数据，
  不得编造票价/车次/天气"，但模型仍可能偏离，行程校验器（`TripPlanValidator`）是第一道闸。
