# 阶段二、阶段三执行审计与下一阶段入口

> 审计日期：2026-10-01（Asia/Shanghai）
> 审计范围：仓库中已经形成执行记录的 `PHASE2_BACKEND.md` 与 `PHASE3_AI_TOOLS.md`，并补充检查 Flutter APK 与 Vue 管理台的实际接入状态。

## 1. 审计口径

原始计划书中的“阶段一、阶段二”与当前仓库文档的命名并不完全一致。本次不按名称猜测，而是按**已经提交执行记录、并有源代码证据的两个阶段**审计：

1. **阶段二：服务端持久化、认证与业务闭环**
2. **阶段三：AI 规划引擎与工具编排**

原始计划书中的 Flutter 基础工程、内容浏览、移动能力、管理台等内容，当前只能视为部分原型或待接入项，不能因为页面已经存在就判定为完成。

状态含义：

- **已达标**：代码与文档互相印证，能够作为当前版本能力交付。
- **部分达标**：主路径存在，但存在明显边界、降级或未验证项。
- **未达标**：计划要求的能力尚未真正实现，或当前实现与对外描述不一致。
- **风险项**：不一定阻塞 Mock 演示，但会影响真实运行、安全或比赛可信度。

## 2. 总体结论

| 维度 | 结论 | 说明 |
| --- | --- | --- |
| 服务端核心闭环 | 部分达标 | 认证、匿名体验、行程、调整、撤销、分享、收藏的服务端骨架已经形成。 |
| AI 引擎抽象 | 已达标 | `PlanningEngine`、LangChain4j、HTTP 备选和 Mock 降级分层清晰。 |
| 真实工具联动 | 未达标 | 当前 `ToolOrchestrator` 全部调用 `MockTravelTools`，尚未接入百度地图 MCP、天气接口或授权交通接口。 |
| 行程可执行性校验 | 部分达标 | 有景点数量、预算、降雨和风险提示，但没有真正完成时间冲突、开放时间、路线耗时和换乘缓冲校验。 |
| Flutter APK | 原型可运行，业务接入不足 | 已可构建 APK，但客户端尚未接通登录、持久化匿名令牌、行程调整、撤销、分享、依据追踪和离线缓存。 |
| 管理台 | 视觉原型 | 总览页有演示图表，但模块页和统计数据仍主要是静态或本地回退数据。 |
| 生产安全 | 未达标 | 配置文件仍有开发默认密钥、默认数据库密码和 `useSSL=false`，不能直接作为生产部署配置。 |
| 下一阶段建议 | 可以进入 | 进入“客户端基础设施 + 移动端响应式适配”阶段；真实外部服务应作为独立适配阶段，不与 UI 重构混做。 |

**最终判断：**当前版本可以作为比赛早期的“稳定演示底座”，但答辩时必须明确标注“演示数据 / Mock 工具”。不能把 Mock 结果包装成实时百度地图、实时天气或真实 12306 车次。

## 3. 阶段二审计：服务端持久化、认证与业务闭环

### 3.1 已经完成且有证据的内容

| 检查项 | 结果 | 证据位置 |
| --- | --- | --- |
| 注册、登录、当前用户 | 已达标 | `server/src/main/java/com/yujian/travel/service/AuthService.java`、`api/AuthController.java` |
| BCrypt 密码哈希 | 已达标 | `AuthService` 使用 `PasswordEncoder`，`config/SecurityConfig.java` 注册 BCrypt |
| JWT 访问令牌 | 已达标 | `security/JwtService.java`、`JwtAuthenticationFilter.java` |
| 刷新令牌轮换 | 已达标 | `AuthService.refresh()` 会校验存储哈希、过期和撤销状态，并记录替换令牌 |
| 匿名体验 | 已达标 | `AnonymousSession` 只保存令牌哈希；`OwnerResolver` 支持无登录创建行程 |
| 匿名规划额度 | 已达标 | `AnonymousSessionService.reservePlanning()` 返回 `429 TRIAL_LIMIT_REACHED` |
| 行程归属校验 | 基本达标 | `TripPlanService.requireOwned()` 按用户或匿名会话查询，不直接按 ID 放行 |
| 行程 CRUD | 已达标 | `TripPlanController` 与 `TripPlanService` 已覆盖创建、列表、详情、修改、删除 |
| 调整、撤销、今日行程 | 部分达标 | 服务端接口和快照恢复存在，但客户端尚未接入；今日行程仍使用 Mock 天气 |
| 只读分享 | 基本达标 | 分享有效期、预算隐藏、访问计数、关闭分享均有服务端实现 |
| 收藏 | 已达标 | `FavoriteService` 与控制器存在，仍需客户端接入 |
| SMTP 预留 | 部分达标 | 验证码哈希、有效期、频率和失败次数存在；尚未作为注册强制流程 |
| H2 演示 / MySQL 生产 profile | 部分达标 | `application.yml` 与 `application-prod.yml` 均存在，但生产配置仍需收紧 |
| 阶段 HTTP 冒烟记录 | 有记录 | `docs/PHASE2_BACKEND.md` 记录了匿名、认证、合并、收藏和分享链路 |

### 3.2 阶段二遗留问题

#### P0：发布前必须处理

1. **客户端 Release 默认地址是 HTTP，和 Release 网络安全策略冲突。**
   - `flutter_app/lib/services/travel_service.dart` 默认使用 `http://10.0.2.2:8080/api`。
   - `flutter_app/android/app/src/main/res/xml/network_security_config.xml` 对 Release 禁止明文 HTTP。
   - 结果是 Release APK 默认无法访问后端，随后被客户端静默降级为 Mock，容易误判为“后端正常”。
   - 下一阶段必须区分 `debug`、模拟器演示、真机局域网和 Release HTTPS 配置，并在界面明确显示降级状态。

2. **生产配置仍包含开发默认值。**
   - `application.yml` 有默认 JWT secret。
   - `application-prod.yml` 有默认 MySQL 密码，且连接串显式 `useSSL=false`。
   - 比赛提交前至少要改为启动时强制校验环境变量；生产 profile 不允许使用示例默认值。

3. **匿名令牌只保存在 Flutter 内存。**
   - `TravelService._anonymousToken` 在进程内有效，应用重启后丢失。
   - 计划书要求使用 `Flutter Secure Storage`，当前尚未实现。
   - 应完成匿名会话创建、令牌安全存储、恢复、过期清理和登录后合并。

#### P1：下一阶段应处理

1. **数据库迁移没有形成版本化机制。** 当前使用 JPA `ddl-auto: update`，没有 Flyway/Liquibase。比赛演示可以接受，交付包和正式部署不建议继续依赖自动改表。
2. **登录、验证码和匿名创建没有统一限流策略。** SMTP 有发送频率控制，但登录失败、刷新令牌、分享读取、规划接口仍需限流和审计。
3. **自动化测试证据不足。** 现有文档记录的是编译和 HTTP 冒烟，没有在仓库中看到覆盖权限、越权、令牌轮换、额度并发和分享过期的测试套件。
4. **请求校验不够细。** `days`、`travelers`、`budgetPerPerson` 等字段缺少明确的 `Min/Max` 约束，异常输入依赖业务层兜底。
5. **CORS 默认只允许 `http://localhost:5173`。** 真机、局域网管理台和部署域名必须通过环境变量显式配置，不能扩大为 `*`。
6. **匿名设备指纹不是当前客户端必需数据。** 后端只保存哈希是正确方向，但应进一步明确用途、保留期限和删除策略，若没有反滥用需求则不要采集。

## 4. 阶段三审计：AI 规划引擎与工具编排

### 4.1 已经完成且有证据的内容

| 检查项 | 结果 | 证据位置 |
| --- | --- | --- |
| 规划端口抽象 | 已达标 | `ai/PlanningEngine.java` |
| LangChain4j 主引擎 | 部分达标 | `ai/LangChain4jPlanningEngine.java` 可按环境变量启用 |
| OpenAI 兼容 HTTP 备选 | 部分达标 | `ai/OpenAiCompatiblePlanningEngine.java` |
| Mock 稳定降级 | 已达标 | `ai/TravelPlanningFacade.java`、`MockPlanningEngine.java` |
| 严格 JSON 解析 | 基本达标 | `ai/LlmPlanParser.java` 支持代码围栏清理和基础字段兜底 |
| 工具统一结果字段 | 已达标 | `tools/ToolResult.java` |
| 五类工具抽象 | 部分达标 | POI、天气、路线、车次、开放时间接口结构存在 |
| 工具调用轨迹 | 部分达标 | `ToolInvocationLog`、`/api/trip-plans/{id}/trace` 存在 |
| 基础可执行性校验 | 部分达标 | `ai/TripPlanValidator.java` |
| 初始规划失败降级 | 已达标 | Facade 会按主引擎、HTTP、Mock 顺序尝试 |

### 4.2 阶段三与计划书的关键差距

#### P0：答辩表述必须修正

1. **当前不是 MCP/百度地图真实工具调用。**
   - `ToolOrchestrator.collect()` 只调用 `MockTravelTools`。
   - 所有结果都会带 `isMock=true`，没有百度地图、天气、12306 授权接口的真实响应。
   - 当前正确表述应为“完成统一工具编排接口和 Mock 适配层，真实适配器待接入”。

2. **LLM 并没有自主进行工具调用。**
   - 工具先由后端统一收集，再把结果拼入 Prompt。
   - 这是一种可控的“后端预取 + LLM 结构化生成”，不是 LangChain4j/MCP function calling。
   - 这不是坏架构，但产品说明必须准确，避免评委追问时出现能力夸大。

#### P1：下一阶段应处理

1. **校验器还不是完整可执行性校验。** 当前没有真正计算节点时间重叠、景点开放窗口、路线耗时、步行和换乘缓冲，也没有将车次时间与行程节点绑定。
2. **局部调整绕过了重新规划与校验。** `AdjustmentEngine` 是关键词规则替换；调整后没有重新调用工具，也没有重新运行 `TripPlanValidator` 并把差异结构化返回。
3. **LLM 生成节点的数据状态语义不准确。** `LlmPlanParser` 将节点状态固定成 `AI 生成`，没有保留工具数据的实时、缓存、演示来源。数据来源和生成来源应分开表示。
4. **工具耗时记录不准确。** `ToolOrchestrator` 只记录整个收集过程的总耗时到每一条日志；没有单工具开始、结束和耗时。
5. **`inputSummary` 参数没有真正写入。** `measure()` 接收了输入摘要，但 `record()` 使用的是 `result.source()`，会降低追踪和排障价值。
6. **规划预览仍是硬编码提取。** `TravelController.preview()` 主要根据字段和关键词推断目的地，只把“天数缺失”作为追问，尚未完成计划书中的自然语言条件提取与必要追问闭环。
7. **工具缓存字段只是模型，没有缓存实现。** `isCached`、`expiresAt` 结构存在，但当前没有 Redis/数据库 TTL 缓存和命中率统计。
8. **管理台没有消费 AI 运行数据。** 页面中的趋势、成功率和工具可用率仍是静态演示值，不能称为真实运营统计。

## 5. Flutter APK 当前专项审计

### 5.1 已完成

- Flutter Android 工程已补齐 Gradle、Manifest、启动资源和 Release 构建链路。
- 包名 `com.yujian.travel`、应用名“豫见智旅”、`minSdk 29`、`targetSdk 36` 已校验。
- 四个一级入口“发现 / 规划 / 行程 / 我的”已经出现。
- 首页、景区卡片、景点详情、规划预览、行程时间轴、预算图和天气页已有可演示 UI。
- Release APK 已实际构建，`flutter analyze` 无问题。
- **尚未完成 Android 真机/模拟器运行验收。** 当前工具链诊断中连接设备是 Windows、Chrome、Edge，尚未形成 Android 设备截图、返回键、键盘、权限和断网运行证据；因此“APK 可构建”不能等同于“移动端已验收”。

### 5.2 尚未完成

- `go_router`、Riverpod、Secure Storage、Cached Network Image、Timeline Tile 等依赖已声明，但实际页面仍以本地 State、`Image.network` 和手写组件为主。
- `TravelService` 没有登录、刷新令牌、匿名令牌安全存储、收藏、调整、撤销、分享、今日行程和 trace 接口。
- 网络异常时直接静默返回 Mock，不展示“在线 / 缓存 / 演示数据 / 数据过期”状态。
- 行程预算图的分类金额是静态常量，不能证明与当前计划的总费用一致。
- 分享按钮、通知按钮、“先逛河南”、部分管理台操作目前是空操作或仅视觉反馈。
- 地图、定位、弱网离线缓存、图片版权信息和本地资源目录尚未形成闭环。
- 首页和行程页存在固定宽度、固定高度和小字号，尚未完成 360dp—430dp 手机宽度的系统适配。

## 6. 阶段出口判断

### 当前可以对外展示的说法

> “豫见智旅已经完成服务端认证、匿名体验、行程持久化、调整撤销、分享和 AI 规划引擎的可替换架构；当前使用结构化 Mock 工具保证稳定演示，真实地图、天气和交通适配正在按独立接口接入。”

### 当前不能对外承诺的说法

- “已经接入百度地图 MCP 并返回实时路线。”
- “已经接入 12306 实时车次。”
- “AI 会自主调用所有外部工具。”
- “APK 已经支持完整离线、登录同步和实时导航。”
- “管理台统计就是线上真实数据。”

## 7. 下一阶段进入条件

下一阶段定义为：**游客端基础设施、移动端响应式适配与真实数据状态呈现**。

进入前只需要冻结三件事，不需要先接入真实地图：

1. 冻结 `TripPlan`、`TripItem`、`ToolResult`、错误响应和数据状态枚举。
2. 确认 APK 的 390dp 参考稿、360dp 小屏稿和 412dp 宽屏稿均不溢出。
3. 确认 Release 使用 HTTPS 地址，Debug 使用模拟器/局域网地址，禁止客户端内置第三方密钥。

下一阶段完成标准见：

- `docs/PROJECT_STRUCTURE.md`
- `docs/MOBILE_LAYOUT_SPEC.md`
- `docs/NEXT_STAGE_PLAN.md`
