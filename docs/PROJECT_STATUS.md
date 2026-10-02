# 项目现状与缺口清单

日期：2026-10-02（Asia/Shanghai）
范围：阶段一 ~ 阶段十一，外加 T12 数据一致性修复（日期 / 时长 / 预算 / 地图口径）
与 T13 出行条件表单重做（含历史行程）、T14 实时状态修复、T15 行程管理入口与交付材料文档、
T16 配图与版权闭环执行结果核对、T17 首页信息流分页与 MySQL 落地、
T18 登录时序修复与行程首页改版、T19 行程导航修复与河南底图落地、
T20 服务端接口文档（`docs/API.md`）、T21 定位 + 附近景点（全链路）、
T22 铁路票价与中转换乘进入规划链路、T23 公开测试与容器部署收口、
T24 管理台内容运营视图、T25 提示词版本管理、T26 APK 运行时服务器地址、
T27 Mock 数据管理、T28 个人信息与账号安全、T29 服务端消息中心、
T30 社区旅记后端底座、T31 社区 Flutter 浏览体验、T32 社区发布流程

> 这份文档只回答两个问题：**现在能演示什么**、**还差什么**。
> 所有"已完成"都指的是**本机实跑验证过**，不是"代码写了"。

## 1. 一句话现状

APK、后端、管理台三条线都能跑起来，主业务闭环（发现 → 规划 → 结果 → 调整 → 撤销 → 保存 → 分享）
已经打通，外部数据做到"能取真实就取真实、取不到带原因降级"。

大模型已真正启用（DeepSeek，实测 `engine=deepseek`），不再依赖 Mock 兜底。

行程地图（T11.2）已经兑现：底图由服务端代取、标记与折线由 APK 自绘，
 地图不可用时退回文字路线；运营台同时补上了景点坐标维护，可以直接在后台填/解析坐标。

交付材料已经补齐四份文档（技术架构与数据模型 / 系统说明书 / 测试说明 / 需求实现对照），
**但产品还没有到"可以直接拿去比赛"的程度**，剩余缺口集中在两处：
河南实景配图、演示视频与界面截图。详见第 4 节。

## 2. 阶段进度

| 阶段 | 内容 | 状态 | 说明 |
| --- | --- | --- | --- |
| 一 | 需求、信息架构、视觉与原型 | 完成 | 视觉方向随后经历 v0.2 → v0.3 两次修订 |
| 二 | Flutter 基础工程 | 完成 | Riverpod / Dio / Secure Storage / 本地缓存 / 统一主题 |
| 三 | 内容浏览 | 完成 | 首页、三条示范走廊、景区卡、详情、收藏 |
| 四 | AI 规划与行程 | 完成 | 自然语言输入 → 追问 → 生成 → 校验 → 调整 → 撤销 |
| 五 | 移动能力 | 完成 | 缓存与降级、行程地图 Tab、定位与附近景点均已实现；见第 15 节 |
| 六 | 后端与外部服务 | 完成 | 12306 / 百度地图 / Open-Meteo / 门票端口 / LLM 四家适配 |
| 七 | Vue 管理台 | 完成 | 6 个视图，`npm run build` 通过（608 模块） |
| 八 | 比赛交付 | **进行中** | APK 可构建；缺签名、图标、演示视频、截图、架构图、ER 图、测试说明 |
| 九 | 真实外部数据与降级口径 | 完成 | 见 `PHASE9_EXTERNAL_TOOLS.md` |
| 十 | 12306 实时车次 + 地图 AK 生效 + 门票评估 | 完成 | 见 `PHASE10_RAILWAY_AND_TICKETS.md` |
| — | UI v0.3 重做 | 完成 | 见 `UI_REDESIGN.md` v0.3 章节 |
| 十一 | T11.1 真正接上大模型 | 完成 | DeepSeek 已启用并实测；打开开关后暴露并修复了两个真实缺陷，见 `PHASE11_LLM_ENABLED.md` |
| 十二 | T11.2 行程地图 + 运营台坐标维护 | 完成 | 服务端代理静态底图、客户端自绘标记与折线、文字路线兜底；见 `PHASE11_MAP.md` |
| 十三 | T12 数据一致性修复 | 完成 | 出发日期全链路口径、时长解析与显示、预算科目拆分、地图状态文案；见 `PHASE12_DATA_CONSISTENCY.md` |
| 十四 | T13 出行条件表单重做 + 历史行程 | 完成 | 中文日历弹层、胶囊对比度、同行人数一行、交通方式弹层、可输入天数、起终点交换与城市搜索、全部行程列表；见 `PHASE13_PLANNER_FORM.md` |
| 十五 | T14 实时状态修复（起终点交换空白 / 登录按钮转圈） | 完成 | 见本文第 8 节；两处都是"数据已经对了、界面没跟上"，根因分别写在客户端动画与登录时序上；用户已在模拟器逐轮确认通过 |
| 十六 | T15 行程管理入口 + 图片来源可见 + 交付材料文档 | 完成 | 历史行程可重命名 / 删除；景点详情展示图片来源；`docs/DELIVERY/` 五份材料补齐。见本文第 9 节 |
| 十七 | T16 配图与版权闭环 | 完成 | 服务端统一配图合规判定，管理台出"待处理 N"面板与筛选，APK 对占位图明确标注；《配图作业单》交付。见本文第 10 节 |
| 十八 | T17 首页信息流分页 + MySQL 落地 | 完成 | 首页改为一页 6 张、滑到底续取、切回发现页回到初始态，新增"查看更多"独立列表；后端新增 `/api/pois/page`；`prod` profile + MySQL 8 首次真实跑通。见本文第 11 节 |
| 十九 | T18 登录时序修复 + 行程首页 / 消息中心 / 我的页改版 | 完成 | 登录"卡住不动"的真正原因是 Riverpod 循环依赖；行程页改成"我的行程"首页 + 最近一次行程 + 查看历史 + 你的足迹；见本文第 12 节 |
| 二十 | T19 行程导航"出不去"修复 + 河南底图落地 | 完成 | 显式返回按钮 + 防重复压栈；`henanmap.jpg` 进 `assets/images/` 并重新标定 18 个地市坐标；见本文第 13 节 |
| 二十一 | T20 服务端接口文档 | 完成 | 对照源码整理全部对外路径、鉴权矩阵、错误码、数据状态语义、管理端接口与已知缺口；见 `docs/API.md` |
| 二十二 | T21 定位 + 附近景点 | 完成 | 服务端 `GET /api/pois/nearby`（WGS-84 → BD-09 换算只做一次、只报直线距离、位置不落库）+ 客户端 `geolocator` 接入；拒绝授权退回「按城市浏览」；见本文第 15 节 |
| 二十三 | T22 铁路票价与中转 | 完成 | 12306 新增 `quoteRailFares` / `searchTransfer` 两条独立工具轨迹；票价进入提示词与预算下限校验；中转方案在直达之外作为可执行备选；见本文第 16 节 |
| 二十四 | T23 公开测试与容器部署收口 | 完成 | CORS 放行 `X-Device-Fingerprint`；admin 容器补 nginx 反代与 SPA 回落；见本文第 17 节 |
| 二十五 | T24 管理台内容运营视图 | 完成 | 新增「内容运营」页：城市/主题聚合、坐标与配图覆盖率、图片版权待办可直接跳到对应景点编辑；见本文第 18 节 |
| 二十六 | T25 提示词版本管理 | 完成 | `prompt_version` 表 + 管理台发布/启用/回滚；规划任务写入启用版本；见本文第 19 节 |
| 二十七 | T26 APK 运行时服务器地址 | 完成 | 设置页可测试并保存后端地址；release 只接受 HTTPS；见本文第 20 节 |
| 二十八 | T27 Mock 数据管理 | 完成 | `demo_scenario` 表 + 管理台覆盖编辑；精确匹配/默认兜底/内置回退；见本文第 21 节 |
| 二十九 | T28 个人信息与账号安全 | 完成 | 昵称/预设头像、修改密码、邮箱验证、退出所有设备、删除账号；收藏统一改为星标；见本文第 22 节 |
| 三十 | T29 服务端消息中心 | 完成 | 登录后消息与已读状态跟账号走；未登录仍使用本机说明；「我的」页只保留设置里的退出登录；见本文第 23 节 |
| 三十一 | T30 社区旅记后端底座 | 完成 | 旅记发布/编辑/删除、公开信息流、详情、点赞、举报和管理员审核接口；见本文第 24 节 |
| 三十二 | T31 社区 Flutter 浏览体验 | 完成 | 底部「旅记」入口、信息流分页、城市/主题筛选、详情、点赞和举报；见本文第 25 节 |
| 三十三 | T32 社区发布流程 | 完成 | 从本人行程发布旅记、1—9 张图片、公开范围、服务端去 EXIF、提交审核；见本文第 26 节 |

## 3. 现在真实可用的能力

### 3.1 APK（游客端）

- **免登录可用**：浏览首页、走廊、景区卡、景点详情；一次匿名规划体验；
- **一句话规划**：自然语言输入 → 条件卡 → 生成管线进度（6 步）→ 结构化结果；
- **行程结果页**：深色汇总卡、冲突提示、逐日卡 + 四项风险行（天气/体力/距离/开放）、
  时间轴、预算比例条、天气、路线依据；
- **行程地图（逐日）**：日期切换、拖动跟手、双指缩放、回到全览、点选站点与时间轴联动；
  底图由服务端代取（AK 不出服务器），标记与折线由 APK 自绘；未打点的安排单独列出原因；
- **局部调整与撤销**：5 个预设指令 + 自定义指令，展示改了什么、费用与强度变化；
- **保存 / 收藏 / 今日行程 / 下一站 / 只读分享（含 QR 与分享页）**；
- **数据状态如实标注**：实时 / 缓存 / 系统资料 / 演示 / 演示（降级）；
- **弱网与断网**：读取最近方案与景区库；图片走磁盘缓存；
- **导航**：底部 3 项（发现 / 行程 / 我的）——规划与行程已合并为一个 tab；
- **出行条件表单**（T13）：出发地 ⇄ 目的地左右布局（可一键交换、城市弹层可搜索并支持省外城市）、
  全中文日历弹层（今天 / 明天 / 后天 / 下周六）、可键盘输入的天数（1—7，与后端上限一致）、
  同行人数压成一行、带代价说明的交通方式弹层、兴趣与体力各带自定义入口；
- **历史行程**（T13）：「我的行程」列出全部已保存方案（标题 / 天数 / 人均 / 强度 / 数据状态 / 更新时间），
  点任意一行打开该行程，不再只有最近一份有入口；
- **首页信息流（T17）**：一次只取 6 张景区卡，滑到底自动续下一页；标题右侧"查看更多"进入独立的
  "河南景点"整页（每页 12）；切到别的 Tab 再回发现页时信息流回到初始态，加载失败时保留已取到的卡片并就近给重试。
- **在我附近**（T21）：首页入口 → 定位后按直线距离列出 3 公里内景点；
  拒绝授权或系统开关关闭都有明确出路（按城市浏览 / 去系统设置）；
  坐标只用于当次请求，客户端不缓存、服务端不落库。

### 3.2 后端

- 认证：注册 / 登录 / 刷新 / 登出 / `me` / 匿名会话 / 登录后合并匿名行程；
- 行程：创建、列表、详情、修改、删除、局部调整、撤销、今日行程、工具轨迹；
- 内容：景区库（运营台可维护）、图片上传与公开只读访问、公开分享页；
- 运营：统计、反馈、日志、景点增删改上下架、数据源健康度、LLM 供应商健康度、提示词版本管理、Mock 数据管理；
- SMTP：发送验证码 / 校验验证码接口已就绪，默认关闭（开发环境验证码写日志）；
- **LlmProvider 四家**：OpenAI / DeepSeek / Kimi / 通义千问，统一适配 + 按 priority 降级 + Mock 兜底。

### 3.3 外部数据（本机实测）

| 来源 | 状态 | 实测结果 |
| --- | --- | --- |
| Open-Meteo 天气 | 实时 | 洛阳 小雨 14—21℃，降水概率 92% |
| 百度地图路线 | 实时 | AK 生效后 `route=ready`，来源"百度地图 Web 服务" |
| 12306 车次 | 实时 | 郑州→洛阳 2026-10-03 返回 165 趟（官方车次与余票） |
| 景区内容库 | 系统资料 | 运营台维护 |
| 门票价格 | 系统资料 | 内容库参考价；比价数据源不存在，仅留端口 |

### 3.4 验证结果

```text
node scripts\verify-railway-mcp.mjs   通过 21 项，失败 0 项
node scripts\verify-tools.mjs         通过 37 项，失败 0 项
node scripts\verify-map.mjs           通过 23 项，失败 0 项
node scripts\verify-llm.mjs           通过 12 项，失败 0 项（只花 1 次模型调用）
mvn -o -B test                        Tests run: 110, Failures: 0, Errors: 0
flutter analyze                       No issues found
flutter test                          All tests passed (144)
npm run build（admin）                 608 modules transformed, built
flutter build apk --debug             app-debug.apk   194.1MB（T32 重新构建，见第 26 节）
flutter build apk --release           app-release.apk 52.6MB（未传 API_BASE_URL，启动即提示配置失败，属刻意设计）
```

数据库切换（T17）：

```text
prod + MySQL 8.4（docker，宿主 3306）
  · profile=prod，Hikari 连接 com.mysql.cj.jdbc.ConnectionImpl
  · JPA 建表 15 张，poi 种子数据 4 行
  · POST /api/auth/login → 200，roles=[ADMIN, USER]
```

## 4. 未实现 / 部分实现

按"是否挡住比赛演示"分级。

### 新增已完成

| 项 | 结果 |
| --- | --- |
| **大模型真正启用** | DeepSeek 已启用，实测 `engine=deepseek`、`dataStatus=AI 生成`、`ok=1 fail=0`。打开开关后暴露并修复了两个真实缺陷（解析器过严、`start_time` 列溢出），详见 `PHASE11_LLM_ENABLED.md` |
| **行程地图** | 每日 Tab 可用：底图走服务端代理（AK 不下发 APK），标记与折线由客户端自绘，`fallback=true` 时退回文字路线。投影、票据、降级口径详见 `PHASE11_MAP.md` |
| **运营台坐标维护** | 景点表单新增经纬度（BD09）与「按名称解析」，`POST /api/admin/pois/geocode` 只回参考值不落库；必须有城市限定，且结果必须落在河南范围内 |
| **出发日期成为一等输入** | 客户端选的日期随请求上来，服务端用它查天气/车次、写进提示词，并在生成后强制覆盖每一天的日期。此前方案标题写 10-02、风险提示引用 10-01。详见 `PHASE12_DATA_CONSISTENCY.md` |
| **时长与预算口径统一** | "3—4小时"不再变成 34 小时，界面不出现小数小时；预算按交通/景点/餐饮/住宿/活动/其他拆分，总价为 0 时也保留预算上限对比 |

### P0：挡住演示，必须做

| # | 缺口 | 现状 | 影响 |
| --- | --- | --- | --- |
| 1 | **景区配图仍是占位示例图**（工具链已就绪，只差照片） | T15 打通"图片来源"展示；T16 把配图合规做成闭环：管理台一眼看到"待处理 N"并可筛选、每条列出待办，APK 对占位图明确标注"非河南实景"。**剩余全部是人工活**：按《配图作业单》换成有授权的河南实拍图 | 版权风险 + 与"河南特色"的说服力 |
| 2 | **交付材料还差视频与截图**（**暂缓**） | 架构图、ER 图、AI 工具调用时序图、测试说明、系统说明、需求实现对照已补齐到 `docs/DELIVERY/`（T15）；演示视频与界面截图**按用户 2026-10-02 的要求暂缓**——内容还没定稿，等界面稳定后再录 | 作品要求第 (1) 条明确要求 |
| 3 | **Release 包没有可用的后端地址** | **已缓解（T26）**：release 支持在设置页运行时配置并测试服务器地址；仍然需要一个真正提供 HTTPS 的后端才能连上，明文 HTTP 继续被拒绝 | 部署腾讯云/其他 HTTPS 入口后即可直接切换 |

### P1：功能完整性，建议做

| # | 缺口 | 说明 |
| --- | --- | --- |
| 5 | 景点坐标需要逐条补齐 | 行程地图优先用内容库坐标（可信度 100），没有坐标才退到地理编码。目前四条预置景点有坐标，运营台新上传的景点需要在表单里点一次「按名称解析」并核对 |
| 6 | ~~定位与"附近景点"~~ **已完成（T21）** | 服务端 `GET /api/pois/nearby` + 客户端 `geolocator` 全链路打通；APK 声明粗/精两个定位权限，权限与调用代码同一轮出现；拒绝授权退回「按城市浏览」，位置不落库。见第 15 节 |
| 7 | 门票比价 | `TICKET_PROVIDER=smart-buy` 只是端口预留，没有真实数据源可用 |
| 8 | ~~12306 中转方案~~ **已完成（T22）** | `query-transfer` 已接入 `searchTransfer` 工具，直达与一次换乘都进入工具轨迹；见第 16 节 |
| 9 | ~~席别与票价未进入预算~~ **已完成（T22）** | `query-ticket-price` 已接入 `quoteRailFares`；席别与票价进入提示词，预算校验增加“低于铁路票价下限”的警告；见第 16 节 |
| 10 | SMTP 邮箱验证 | 接口与配置齐全，默认关闭。按原计划属于"预留"，不算缺陷 |
| 11 | ~~管理台覆盖度~~ **已完成（T24、T25、T27）** | 内容运营页覆盖城市/主题与图片版权；提示词版本可发布、启用、回滚；Mock 数据可结构化覆盖并回退 |
| 12 | ~~历史行程缺少删除 / 重命名~~ **已完成（T15）** | 历史行程行尾"更多"提供重命名与删除；重命名上限 40 字（前后端一致），空标题在客户端直接拦下不发请求，删除需二次确认 |

### P2：质量与验证

| # | 缺口 |
| --- | --- |
| 13 | 系统字体放大 1.3 倍的**真机**表现未验证（自动化已覆盖 360/390/412） |
| 14 | 断网 / 弱网下的 APK 实测未做 |
| 15 | 收藏、分享、今日行程的端到端真机验证未做 |
| 16 | 图片版权来源登记与 `THIRD_PARTY_NOTICES.md` 已同步 T21（新增 geolocator、重写权限清单）；图片版权仍待实拍替换后逐条核验 |
| 17 | 无 Git 版本库（本工作区未初始化），无法追溯变更 |
| 18 | T13 的表单改动与 T14 的两处修复的模拟器目视复核**已完成**（用户逐轮装包确认）；T15 的历史行程改名 / 删除仍待模拟器复核 |

## 5. 技术栈实际落地 vs 原计划

计划里的技术都要么落实、要么有明确理由替换。**没有"写了但没生效"的条目**——
本轮清理掉的正是这一类。

| 计划 | 实际 | 说明 |
| --- | --- | --- |
| Flutter + Riverpod + Dio | 一致 | — |
| GoRouter | **改用 `Navigator`** | 单栈导航，没有深链接需求；`go_router` 已从 pubspec 移除 |
| Drift | **改用 JSON 文件缓存** | 只缓存景区库与最近一份方案，一个目录一删即净；未引入 ORM |
| timeline_tile | **自绘 `_StopRail`** | 避免 `IntrinsicHeight` 在长列表的性能问题；依赖已移除 |
| FL Chart | **未使用** | 预算改用比例条（信息密度更适合竖屏）；依赖已移除 |
| Geolocator | **已接入（T21）** | 只服务「附近的景点」：粗/精权限、拒绝授权兜底、系统开关判定；坐标不缓存、不落库 |
| cached_network_image | **已接入** | `PhotoPlate` 走磁盘缓存，支撑弱网离线看图 |
| Spring Boot + JPA + MySQL 8 | 一致 | 开发用 H2 文件库，`prod` profile 连 MySQL 8 |
| MyBatis-Plus | 未采用 | 计划原文即为"`MyBatis-Plus` 或 `Spring Data JPA`"，选了 JPA |
| LangChain4j | **已接入并运行中** | 统一适配四家 OpenAI 兼容厂商；当前启用 DeepSeek，实测 `engine=deepseek` |
| Redis | 未引入 | 计划中标注"可选"；当前用内存缓存 + 表缓存，够用 |
| Vue3 + Pinia + ECharts | 一致 | — |
| Element Plus / Naive UI | **未使用，自研 CSS token** | 管理台只需要表格与统计，自研样式反而避免"模板感" |
| 12306 | **已接入 MCP 实时** | 原计划是参考时刻表，阶段十升级为官方车次与余票 |
| 百度地图 Android SDK / Flutter 插件 | **不用，改服务端代理静态底图** | SDK 要求把 AK 打进 APK，与"AK 只留服务端"冲突；三个候选 Flutter 插件长期未更新、许可证不明。客户端因此只画点与折线，不接触百度坐标系 |
| MCP 客户端 | 自研 HTTP 客户端 | 未引入通用 MCP SDK，协议三步握手在 `RailwayMcpClient` 内实现 |

## 6. 下一步优先级

1. ~~接一家真实大模型~~ **已完成**（DeepSeek，T11.1）；
2. ~~地图 Tab~~ **已完成**（T11.2）：服务端代理静态底图 + 客户端自绘标记，
   并在运营台补齐坐标维护；剩余的是模拟器/真机目视复核（由你去装包看）；
3. **河南实景配图**：换成真实照片即可，工具链已齐（T16）：管理台「景点管理」顶部看"待处理 N"、按行看待办，照 `docs/DELIVERY/配图作业单.md` 做；
4. ~~交付材料文档~~ **已完成**（`docs/DELIVERY/`）；**演示视频与界面截图暂缓**（用户 2026-10-02：“还没有设计好内容”），脚本仍留在 `docs/DELIVERY/README.md` 第 3 节；
5. **HTTPS 后端 + release 包**：`--dart-define=API_BASE_URL=https://...`；
6. ~~把 H2 换成 MySQL~~ **已完成**（T17）：`scripts\run-server-mysql.cmd` + `prod` profile 已实测建表、种子数据与运营账号登录；剩下的只是挑一条 MySQL 路径固化到演示环境（见第 11.3 节）。

## 7. 两套演示口径（沿用）

- **在线模式**：`APP_TOOLS_MODE=live`，天气 / 路线 / 车次都是真实数据；
- **稳定模式**：`APP_TOOLS_MODE=mock`，全部标注演示数据，断网也能讲完整流程。

两套都不能把演示数据说成实时——这条是全项目的硬约束。

## 8. T14 两处「状态更新不渲染」修复

两条反馈看起来都是"点了没反应，切页回来却是对的"，但根因完全不同。
两条都补了自动化断言，避免再退回去。

### 8.1 起终点交换后两边城市名一起消失

- **现象**：点中间的环形箭头，左侧「出发地」、右侧「目的地」的文字同时不见；离开这一屏再回来，
  交换结果是对的，字也回来了。
- **根因在客户端动画**：`route_selector.dart` 的 `AnimatedSwitcher.transitionBuilder` 用
  `FractionalTranslation` 计算位移。这个组件**不会监听动画**，位移只在建树那一帧按
  `animation.value` 算一次并固定下来。而新值恰好是在 `animation.value == 0` 的那一帧建出来的，
  于是"往外一个身位"被永久固定，文字被外层 `ClipRect` 裁掉——屏幕上就是空白。
  切页回来时 widget 重建，此时 value 已是 1，位移为 0，所以看起来"切页能修好"。
  （只有 `FadeTransition` 自己监听动画，所以透明度是好的，字其实还在，只是被裁到了裁剪框外。）
- **修法**：换成 `SlideTransition`（内部逐帧读取动画），透明度仍由 `FadeTransition` 负责，
  进出方向与"值从另一侧滑过来"的语义不变。
- **回归测试**：`planner_conditions_test.dart` 新增「交换之后两边城市名仍留在裁剪框里」，
  断言文字实际绘制矩形必须完整落在所属 `ClipRect` 内 —— 旧实现下这条会失败。

### 8.2 登录成功后按钮仍转圈

- **现象**：账号密码正确，点登录后按钮一直转圈；过一会儿/切页之后，账号其实已经登录成功。
- **根因在登录时序**：`AccountRepository._accept()` 在**存下 token 之后**还要再发一次
  `/auth/merge-anonymous`（匿名体验行程交接），并且要等它返回才把 token 交给会话层。
  也就是说"账号已经可用"和"按钮结束转圈"之间夹着一次用户根本不需要等的网络往返；
  这次往返一慢（或抛出的不是 `ApiFailure`，旧代码只 catch 了 `ApiFailure`），
  按钮就会一直转，而底下的会话状态迟早是对的。
- **修法**：
  1. 登录与交接拆开：`signIn() / register()` 只等一次凭据交换并立刻切换会话；
     `mergeAnonymousTrips()` 作为随后的独立一步，由登录页在 pop 之后后台执行并单独提示结果；
  2. 交接请求加重试上限：`AccountRepository.mergeTimeout`（8 秒）超时只报提示，
     体验行程仍留在历史记录里可见；
  3. 登录表单加 `finally` + 兜底 `catch`：任何异常路径都不会再把按钮留在 loading；
  4. `SessionStore` 的每次 keystore 读写加 4 秒上限（`storageTimeout`）：
     平台 keystore 卡住时按既有"存储失败不致命"的约定处理，内存快照仍然可用。
- **回归测试**：`account_repository_test.dart` 断言 `signIn` 只发出 `/auth/login` 一条请求、
  `mergePending` 为真，合并是单独调用发起；没有体验会话时合并连请求都不发。

## 9. T15 执行结果（行程管理入口 + 图片来源 + 交付材料）

### 9.1 历史行程可重命名、可删除

- 接口早就有（`PATCH` / `DELETE /api/trip-plans/{id}`），缺的是客户端入口；
- 客户端新增 `renameTripPlan` / `deleteTripPlan`；重命名**先在客户端 trim 并拦下空标题**，
  不发请求 —— 后端对空标题是静默保留旧值，不拦的话用户会以为改名成功了；
- 历史行程行尾由 `chevron_right` 改为"更多"，弹出重命名 / 删除；删除走二次确认，
  文案写明"逐日安排与调整记录一并删除，无法恢复"；
- 后端补 `@Size(max = 40)`，前后端上限一致。

### 9.2 图片来源在客户端可见

- `Poi` 载荷新增 `imageCredit` / `sourceUrl`，客户端模型同步；
- 景点详情页在"出行提示"之后展示"图片来源"小节，仅当两项都非空时出现；
- 内置兜底景点如实标注"占位示例图（Unsplash），非河南实景，待运营台替换为有授权照片"。

### 9.3 交付材料

新建 `docs/DELIVERY/`：

| 文档 | 内容 |
| --- | --- |
| `README.md` | 作品要求 → 材料对照、交付物清单、两套演示脚本、一键复现、"尚未完成"清单 |
| `技术架构与数据模型.md` | 三层架构图、AI 工具编排时序图、13 张表的 ER 图、接口清单、缓存与降级口径、密钥边界 |
| `系统说明书.md` | 目标用户、运行环境、信息架构、核心流程、页面与状态清单、隐私与合规、管理台 |
| `测试说明.md` | 后端 62 / 客户端 84 / 脚本断言、安全测试项、移动端适配清单、未覆盖项 |
| `需求实现对照.md` | 逐条对照比赛要求与立项计划，未做的直接写"未做" |

### 9.4 本轮顺带修掉的真实缺陷

`additional_screens.dart` 里三处 `setState(() => _future = _load())` —— 箭头函数把 `Future`
当成返回值交给 `setState`，debug 断言直接抛错（"callback argument returned a Future"）。
已全部改为代码块形式。这是组件测试抓出来的，不是读代码读出来的。

### 9.5 验证结果

```text
mvn -o -B test                        Tests run: 62, Failures: 0, Errors: 0
flutter analyze                       No issues found
flutter test                          All tests passed (84)
```

本轮新增用例：

| 用例 | 覆盖 |
| --- | --- |
| `travel_repository_test` 3 项 | 重命名 trim 后 PATCH / 空标题不发请求 / 删除打 204 |
| `travel_repository_test` 1 项 | 景点载荷带上运营台登记的图片来源 |
| `planner_conditions_test` 1 项 | 历史行程能重命名，也能在确认之后删除 |
| `TripPlanModelsTest` 2 项 | 行程标题长度上限校验（不启 Spring 上下文） |

## 10. T16 执行结果（配图与版权闭环）

P0 里"河南实景配图"是**唯一必须人工完成**的一项：图得有人去拿、去授权。
所以这一阶段做的不是"替你去拍照"，而是把**判断与待办**做成工具，
让你打开管理台就知道还差几张、每张差什么，换完立刻能看到状态转绿。

### 10.1 判定规则只写一处

新增 `com.yujian.travel.common.PoiImageAudit`，四种状态：

| 状态 | 触发条件 |
| --- | --- |
| `MISSING` 缺配图 | 没有图片地址 |
| `PLACEHOLDER` 占位示例图 | 图片域名是 Unsplash / Pexels / Pixabay，**或**版权说明里出现"占位 / 示例素材 / 非河南实景 / 待替换" |
| `UNLICENSED` 来源未登记 | 有图，但版权说明与来源链接都为空 |
| `REGISTERED` 已登记 | 有图 **且** 版权说明非空 |

两个刻意的取舍：

1. **域名命中优先于文字说明** —— 一段写得很漂亮的授权说明，也改变不了
   这张图来自 Unsplash 这个事实；
2. **来源链接缺失不算待办** —— 待办清单里放"可以不做的事"，列表就永远清不空。

状态是**派生字段，不落库**：改完图片下一次读就是新结论，不存在
"库里存着过期状态、界面照着它显示"。

### 10.2 管理台

「景点管理」页新增**配图与版权**面板：

- 顶部三档筛选：全部 / 待处理 / 已登记，各自带数量；
- 列表新增「配图」列：状态徽标 + 这一条要补什么，一眼可见；
- 编辑抽屉里显示"当前配图状态 + 待补项"，保存后自动重新判定，不需要额外点一次"重新审计"；
- 旧后端（载荷里没有这些字段）时退化成"未判定"并按待处理计 —— 拿不准的时候宁可多提醒一次。

### 10.3 APK

- `TravelModels.Poi` / `Destination` 新增 `imageStatus`；
- 景点详情页「图片来源」一节改为：**占位图 / 缺图 / 来源未登记时也照常出现**，
  并先给出状态说明（"当前为占位示例图，非河南实景，正式内容正在补充。"），
  再列已登记的出处；
- 已登记授权的实景图不贴任何标签 —— 正常的实拍照片不需要在页面上挂免责声明。

> 旧实现有个真问题：`imageCredit` 与 `sourceUrl` 都为空时整节消失。
> 那等于把"这个景点还没配图"藏起来，游客只会以为是加载失败。

### 10.4 交付文档

新增 `docs/DELIVERY/配图作业单.md`：现状盘点、每个景点要拍到什么、
图片技术规格（格式 / 体积 / 尺寸 / 构图）、上传与登记五步、
可用与不可用的图片来源、验收标准、判定规则。

### 10.5 验证结果

```text
mvn -o -B test        Tests run: 69, Failures: 0, Errors: 0
flutter analyze       No issues found
flutter test          All tests passed (91)
npm run build（admin） 608 modules transformed, built
```

本轮新增用例：

| 用例 | 覆盖 |
| --- | --- |
| `PoiImageAuditTest` 7 项 | 空地址 / Unsplash 域名 / 说明里写了"占位" / 版权与来源都空 / 只有来源链接 / 已登记 / `needsWork` 口径 |
| `destination_image_status_test` 6 项 | 四种配图状态的话术；旧服务端不下发状态时不凭空提示；什么都没有时整节不出现 |
| `travel_repository_test` 1 项 | 占位图载荷一路传到详情页，且 `imageNotice` 说明非河南实景 |

## 11. T17 执行结果（首页信息流分页 + MySQL 落地）

### 11.1 首页不再"一次拉全部"

原来首页把景区库整份拉下来一次渲染，景点越加越多，它就变成一个只会向下延伸的页面：
首屏要等全量数据、内存里存着全部卡片，内容库涨到几百条时第一次打开就会明显变慢。
现在改成**分页信息流**：

| 行为 | 结果 |
| --- | --- |
| 进入发现页 | 只请求 `page=1&size=6`，一次 6 张卡片 |
| 向下滑 | 距底部 480px 内自动请求下一页，按 `id` 去重追加 |
| 已经到底 | 显示"已经到底了 · 共 N 个景点"，不再发请求 |
| 切到行程 / 我的再切回发现 | 信息流**回到初始态**（重新从第 1 页开始） |
| 章节标题右侧 | 新增"查看更多"，进入独立的"河南景点"整页 |

后端新开 `GET /api/pois/page?city=&page=&size=`，返回 `{items, page, size, total, hasMore}`。
两个刻意的取舍：

1. **不改 `/api/pois`** —— 那个接口返回数组，还被"全部景点"与离线缓存复用；
   同一个地址在带不带参数时返回两种形状，是后面一定会踩的坑，所以另开一个路径；
2. **`hasMore` 由服务端算** —— 用 JPA 的 `Page.hasNext()`，
   不让客户端拿 `page × size` 跟 `total` 自己推（差一条就会多请求一次空页）。

非法页号 / 页大小一律**夹回合法区间而不是抛 400**：首页不该因为一个手滑的参数变成错误页。

### 11.2 客户端分页与离线降级

`TravelRepository.fetchDestinationPage()` 是唯一的取数口：

- 在线：请求 `/pois/page`，把拿到的这一页合并进离线缓存（按 `id` 去重，第 1 页放前面、后续页追加）；
- 断网：依次降级 **缓存 → 内置演示目录**，并对整份列表做同样的切片，
  所以离线状态下翻页的交互完全一致，`status` 如实标注"缓存 / 演示"；
- `total = 0` 表示没拿到可信总数，界面就不显示"共 N 个"，不编造数字。

"查看更多"进入的整页用**自己的分页器**（每页 12），与首页互不干扰。

### 11.3 MySQL 真正用上了

先说结论：**这类应用用 MySQL 是合理的，而且应该用**。

APK 本身**不存、也不连数据库**，它只通过 HTTP 访问后端；
所以"数据存在哪"从头到尾是后端的 Spring profile 决定的：

| profile | 存储 | 用途 |
| --- | --- | --- |
| `dev`（默认） | H2 文件库 `server\data\yujian.mv.db` | 开箱即跑，不需要装数据库 |
| `prod` | MySQL 8 | 交付、演示、真正落地 |

账号 + 行程 + 收藏 + 分享 + 内容库是一个典型的**服务端关系型**问题：
多表关联、事务、并发写入、后续的备份与权限，正是 MySQL 的强项。
H2 的定位是"开发期不用装东西就能跑"，不是交付形态。

本机实测（`prod` + MySQL 8.4 容器，宿主端口 3306）：

```text
The following 1 profile is active: "prod"
HikariPool-1 - Added connection com.mysql.cj.jdbc.ConnectionImpl@...
Initialized JPA EntityManagerFactory for persistence unit 'default'
Started YujianTravelApplication in 8.021 seconds
Seeded 4 POI rows into the content library
Operator account 'operator' is ready with the ADMIN role
```

MySQL 侧确认（`information_schema` + `select`）：

```text
15 张表   anonymous_session / email_verification / favorite / feedback /
          operation_log / poi / refresh_token / tool_invocation_log /
          trip_day / trip_item / trip_plan / trip_plan_warning /
          trip_share / user_account / user_role
poi       4 行（种子数据）
登录      POST /api/auth/login → 200，roles=[ADMIN, USER]
```

新增两个脚本：

| 脚本 | 作用 |
| --- | --- |
| `scripts\init-mysql.cmd` | 在本机 MySQL 上建库 `yujian_travel` + 账号 `yujian` + 授权；幂等，只需 root 口令一次 |
| `scripts\run-server-mysql.cmd` | 用 `prod` profile 启动后端，默认连本机 `3306`；`MYSQL_PORT` 可改，`scripts\local.env` 可覆盖 |

本机原本还装过一个原生 MySQL 8.2 服务（`MySQL82`），它和容器抢同一个 3306，
已经**停用**；现在**统一由 docker compose 的 `mysql` 容器占用 3306**
（compose 里加了 `restart: unless-stopped`，Docker Desktop 起来它就跟着起来），
`scripts\run-server-mysql.cmd` 默认就连它。
另需记住：**H2 里的旧数据不会自动迁到 MySQL** —— 两个存储互不相通，
切库后运营账号由 `ADMIN_USERNAME` / `ADMIN_PASSWORD` 重新引导。

### 11.4 本轮修掉的真实缺陷

1. **"查看更多"页面在无界宽度下崩布局** —— 顶部原来是 `Row` 套一个内部含 `Flexible` 的来源条，
   直接抛 `RenderFlex children have non-zero flex but incoming width constraints are unbounded`；
   改成上下排的 `Column`。这条是**测试先发现的**，不是靠肉眼；
2. **`/pois/page` 与 `/pois/{id}` 的路由歧义** —— Spring 里字面量路径优先于模板变量，
   `page` 不会被当成景点 id；虽然行为正确，仍在代码里写了注释说明，
   免得后面有人"顺手"把顺序改掉。

### 11.5 验证结果

```text
mvn -o -B test        Tests run: 69, Failures: 0, Errors: 0
flutter analyze       No issues found
flutter test          All tests passed (96)
```

本轮新增用例：

| 用例 | 覆盖 |
| --- | --- |
| `travel_repository_test` 2 项 | 分页请求参数（`/pois/page`、`page=2`、`size=6`）与 `hasMore` 直接取服务端值；断网时按页读完内置演示目录 |
| `discover_feed_test` 3 项 | 一次只取 6 张、滑到底才续取、到底后不再请求；切 Tab 再回来请求序列 `1 → 2 → 1`；"查看更多"用独立分页 |


## 12. T18 执行结果（登录假死修复 + 行程首页 / 消息中心 / 我的页改版）

### 12.1 登录、注册"卡住不动"的真正原因

现象：账号密码都对，点「登录」后按钮一直转，最后弹一句"登录没有完成，请稍后重试"；
切一下页面再看，其实已经登录成功了。

根因不在网络，而在 Riverpod 的依赖方向：

```text
favoritesProvider  ── watch ──▶  sessionProvider
        ▲                              │
        └──── invalidate（反向）────────┘     ← SessionController._adopt()
```

`favoritesProvider` 自己 `watch` 了 `sessionProvider`，而 `SessionController._adopt()`
又反过来 `ref.invalidate(favoritesProvider)` —— 这是一条**循环依赖**，
Riverpod 在 debug 构建里直接抛 `CircularDependencyError`。异常长在登录回调里，
被 `on Object catch` 当成"登录失败"吞掉，于是显示成"登录没有完成"。
release 构建不跑这条断言，所以以前表现为"切页之后状态是对的"。

修掉的是三处，不是一处：

| 文件 | 改动 | 为什么 |
| --- | --- | --- |
| `app/session_providers.dart` | 删掉反向 `invalidate`，只改 `state` | 依赖自己会生效：`state` 一变，`watch` 它的 `favoritesProvider` 自动重建，效果一样但没有反向依赖 |
| 同上 | 新增 `_adoptions` 计数 | 恢复会话（`/auth/me`）可能比登录慢；计数保证迟到的旧会话不会覆盖刚登录的账号 |
| `core/storage/session_store.dart` | `clearUserSession({ifToken})` | 迟到的 401 只允许清掉**它自己**那份凭据，不能删掉刚写入的新令牌 |
| `data/repositories/account_repository.dart` | `restore()` 传 `ifToken` | 同上，把保护接到唯一的危险调用点 |
| `screens/account_screen.dart` | 只有凭据交换能判"登录失败" | 关页面、弹提示、匿名行程交接都是表现层；它们失败不该把一次成功的登录报成失败 |

最后一条是关键：以前**任何**一步抛异常都会显示"登录没有完成，请稍后重试"，
于是真正的失败原因（一个断言、一次网络抖动）全被这句话盖住。现在非 `ApiFailure`
的异常会带上 `runtimeType` 打印到 logs，提示语也给得出可执行的信息。

### 12.2 一条测试基础设施的坑（记下来免得再踩）

`testWidgets` 的测试体跑在**假时钟**里。像 `await session.read()` 或
`await container.read(someProvider.future)` 这种"真异步"的 await，会让整条用例
**永远挂住**，连测试超时都不会触发 —— 超时计时器本身也在假时钟上，需要推帧才会走。
表现出来的现象是 `flutter test` 卡死、只能手动 taskkill，而且看不到任何失败信息。

因此本轮的解法是：

- 驱动 provider 状态一律用 `tester.pump(step)` 推固定帧数（`pushFrames` 辅助函数），
  不用 `pumpAndSettle` 去等"没有待处理帧"；
- 确实需要真异步的读（例如 `SessionStore.read()`）放进 `tester.runAsync()`。

这条经验写在 `test/screens/account_signin_test.dart` 的注释里，免得下一个人再花一次时间。

### 12.3 首页顶栏：头像 + 消息

| 元素 | 以前 | 现在 |
| --- | --- | --- |
| 消息铃铛 | `onPressed: null`，点不动，没有红点 | 可点，进消息中心；未读时带数字红点，tooltip 里也写了"几条未读" |
| 头像 | 不存在 | 圆形头像：未登录是空心人像，登录后是用户名首字，点击切到"我的" |

新增 `screens/messages_screen.dart`：4 条**本机生成的系统说明**（版本 / 数据来源 / 安全 / 行程），
未读用"描边 + 标题加粗 + 红点"三重信号，颜色不是唯一载体。

这里有一条刻意的边界：**首版没有服务端推送**，所以页面顶部直接写明
"消息保存在本机，尚未接入服务端推送"，也**没有编造"3 分钟前"这类时间戳**。

### 12.4 行程页：从"最新行程"改成"我的行程"首页

以前每次进"行程"都 `_restoreLatest()`，把最新那份方案直接摊开，
结果是：行程页永远只有一份行程，历史与足迹没有位置。现在分成两态：

| 状态 | 触发 | 内容 |
| --- | --- | --- |
| **我的行程首页**（默认） | 点底部"行程"进入 | 标题 + 副标题、最近一次行程、新建一个行程、查看历史行程、你的足迹 |
| 规划表单 | 点"新建一个行程"，或从首页带一句话过来 | 原有表单与结果页，AppBar 改成"规划行程"并带返回 |

首页的"最近一次行程"是渐变大卡（走廊 / 天数 / 人均 / 最后更新时间 / 继续查看），
两个入口用品牌实色与白卡区分主次，按压有 130ms 的回弹反馈。

**一处如实降级**：卡片标题是"最近一次行程"，不是"进行中的行程"。
原因是数据库里还没有存行程的出发日期（`trip_plan` 只有创建与更新时间），
凭更新时间猜"正在进行中"会给出一个说不清依据的判断 —— 宁可叫得准一点。

### 12.5 你的足迹：新接口 + 示意地图

新增 `GET /api/trip-plans/footprint`：

```json
{
  "cities": [{ "name": "洛阳", "tripCount": 2, "firstVisitAt": "...", "lastVisitAt": "..." }],
  "totalMeters": 51200,
  "totalDays": 5,
  "tripCount": 2,
  "generatedAt": "..."
}
```

聚合口径（`TripPlanService.footprintOf`，纯函数，可直接单测）：

1. 城市 = 每份行程的出发地与目的地，各自计数；两地相同只算一次；
2. 里程 = 只累计行程项里**真的带了距离**的那些（路线工具给过距离才写库）；
3. 天数 = 直接累加每份行程的天数，不做去重（两趟都去洛阳就是两天旅行）；
4. 归属与 `/trip-plans` 完全一致：登录账号与匿名体验各看各的，不串号。

客户端 `fetchFootprint()` 拿不到就返回**空足迹**，绝不在本地按天数估算公里数。
地图在 T19 起改为「河南底图 + 叠加记号」，见第 13.4 节（本节写下时还是手绘轮廓）。
原实现是 `CustomPainter` 手绘的河南省示意轮廓 + 18 个地市的相对坐标，
去过的地方用一次性的 900ms 点亮动画（光晕 → 朱砂点 → 白心），
并明确标注"示意地图，非精确 GIS 底图"—— 没有引入任何地图 SDK，离线也能画。

### 12.6 我的页改版

| 区域 | 内容 |
| --- | --- |
| 身份卡 | 圆形头像 + 用户名 + 邮箱 + [已登录] [未验证邮箱] [角色] 徽标；未登录时是登录入口 |
| 第一组 | 我的收藏 / 我的行程 / 消息通知（带未读角标）/ 设置 |
| 第二组 | 隐私与数据 / 第三方数据来源 / 关于豫见智旅 v0.3 |
| 底部 | 居中"退出登录"（朱砂色文字，二次确认） |

新增 `screens/profile_screens.dart`，把收藏、设置、隐私、数据来源、关于五个独立页面收在一处：

- **设置**：账号与安全（登录状态 / 邮箱 / 验证状态 / 角色）、个人基本信息、软件设置。
  还不能改的项直接写"规划中"，不放点不动的假开关；
- **隐私与数据**：我们保存什么 / 不采集什么 / 你的权利 / 密钥与日志，四条清单；
- **第三方数据来源**：百度地图、Open-Meteo、12306 适配层、大模型（OpenAI / DeepSeek / Kimi / Qwen）、图片版权；
- **关于**：版本、技术构成、这个版本的重点、免责说明、开源依赖。

"退出登录"抽成一个顶层函数 `confirmSignOut`，我的页与设置页共用同一份文案与逻辑。

### 12.7 验证结果

```text
mvn -o -B test        Tests run: 72, Failures: 0, Errors: 0   （+3：足迹聚合口径）
flutter analyze       No issues found
flutter test          All tests passed (106)                 （+10：登录 3 + 仓库 1 + 本轮 6）
```

本轮新增用例：

| 用例 | 覆盖 |
| --- | --- |
| `TripFootprintTest` 3 项 | 城市去重与计数、缺失距离不参与累计、空输入、最近到访排序 |
| `account_signin_test.dart` 3 项 | 登录成功关页 + 会话切换 + 收藏跟随重建；注册同一路径；迟到的 401 不冲掉新账号 |
| `account_repository_test.dart` +1 项 | 迟到的失效令牌不会删掉刚写入的新凭据 |
| `journey_hub_test.dart` 6 项 | 足迹 JSON 口径与空足迹；未读数增减；行程页默认停在首页、点新建才进表单；铃铛开消息中心并标记已读；点头像切到"我的" |

同时更新了三个受影响的老用例：
`planner_conditions_test.dart` 的表单用例改为"进首页 → 点新建 → 填表"的真实路径；
`phone_layout_test.dart` 的三档宽度检查补上"行程首页"这一态，
并把历史行程的入口改成首页上的"查看历史行程"。

### 12.8 已知边界

1. "进行中的行程"改叫"最近一次行程" —— 数据库还没存行程出发日期，见 12.4；
2. 消息中心是本机说明，没有服务端推送与已读同步（重启后会重新提示一次）；
3. 足迹地图是示意坐标，不参与任何距离或路线的计算；
4. 设置页的昵称、头像、主题等仍为"规划中"，没有做成假开关。

## 13. T19 执行结果（行程导航「出不去」修复 + 河南底图落地）

### 13.1 现场症状

用户实测：从「我的」进「我的行程」，点开一份行程之后，
「返回按钮组件和底部导航栏竟然全部消失，导致用户一直处于行程界面出不去」。

### 13.2 根因判定

先把能确定的和不能确定的分开：

| 结论 | 依据 |
| --- | --- |
| 不是有人拦返回 | 全项目 `PopScope` / `WillPopScope` / `SystemNavigator` / `automaticallyImplyLeading: false` 全部零命中 |
| 子页面没有底部导航是**设计如此** | 底部导航只属于根 `Scaffold`；行程详情、景区详情都是全屏深读页，push 之后必然盖住它（景区详情一直如此） |
| 返回按钮的存不存在，此前由框架的**隐式条件**决定 | `AppBar` 只在 `ModalRoute.impliesAppBarDismissal`（这条路由下面还有没有活动路由）为真时才生成 `BackButton`。条件跟着导航栈形态变，一旦不成立按钮就**静默消失**，不报错、不留痕 |
| 另一条「看起来像坏掉」的路径 | 连点两下入口会 push 两条一模一样的路由，用户按一次返回还停在「同一个」页面，以为返回失灵 |

复现探针（组件测试）在两条入口上都没能重现「按钮不存在」，
说明它更可能出在真机的栈形态与合成上，而不是某一层页面写错了。
既然如此，修法就不再依赖那个隐式条件。

### 13.3 修法：把「能不能退出」从隐式条件改成显式控件

新增 `lib/core/widgets/app_back_button.dart`，并在 `TripScreen`、`TripHomeScreen` 的
`AppBar.leading` 上写死：

1. **显式常驻** —— 按钮在不在，不再由 `impliesAppBarDismissal` 决定；
2. **点了一定有反应** —— `canPop()` 为真就 `maybePop()`；万一这一页真的成了栈底，
   用 `pushAndRemoveUntil` 重建主导航壳层（`fallback`），而不是点下去毫无反应；
3. **防重复压栈** —— 行程详情 `_open` 增加 `_openingId != null` 早退，「查看历史行程」
   两个入口各加一道 `_historyOpen` 闸，「我的」页的 `_push` 用当前路由引用比较挡住连点。

这三条各堵一类「出不去」，互相不替代。

### 13.4 河南底图落地（素材不再留在项目外）

用户提供的 `henanmap.jpg`（450×452，自带省界与 18 个地市名）移入
`flutter_app/assets/images/henan_map.jpg`，并在 `pubspec.yaml` 注册 `assets/images/`。
足迹卡从「手绘轮廓 + 网格」改成**底图 + 叠加记号**：

- 底图和地名是死的，所以只画状态：去过 = 金色光晕 + 白圈 + 朱砂点（一次性 900ms 点亮），
  记号落在城市名**上方**，不盖住字；
- 18 个地市的相对坐标按这张底图重新标定（`_HenanFootprintPainter._labels`），
  换底图要重新标一次，注释里写明了；
- 素材缺失时退成一块 `surfaceTint` 色块（`errorBuilder`），不会塌成红叉；
- 仍然标注「示意地图，非精确 GIS 底图」，仍然不引入任何地图 SDK，离线也能画。

坐标是渲染成 PNG 目视核对过的（临时探针渲染足迹卡再比对），核对完探针已删除。

### 13.5 验证结果

```text
mvn -o -B test        Tests run: 72, Failures: 0, Errors: 0
flutter analyze       No issues found
flutter test          All tests passed (110)        （+4：行程导航回归）
```

同时修掉一个被这次改动暴露出来的老测试问题：`phone_layout_test.dart` 用了
`tester.pageBack()`，它按英文 tooltip「Back」找按钮；行程页现在用的是产品自己的返回按钮
（tooltip「返回」），所以改成 `find.byType(AppBackButton)`。

### 13.6 已知边界

1. 行程详情、景区详情仍是全屏深读页，**不会**把底部导航一起带进来（当前设计）。
   这一轮保证的是「一定退得出去」，不是「任一页都能切 tab」；
2. 底部导航没有做成随时可调出的浮层，切 tab 仍然要先退回根页面；
3. `AppBackButton` 的兜底分支（重建导航壳层）在正常栈形态下不会触发，
   属于最后一道保险，自动化只覆盖了正常分支。

---

## 14. T20 执行结果（服务端接口文档）

### 14.1 做了什么

`docs/API.md` 首次成型：对照 `Controller` / `SecurityConfig` / `GlobalExceptionHandler` / `ToolResult`
逐条整理 —— 不是自动生成，也不是凭记忆写的。

覆盖范围：

- **17 个 Controller、全部对外路径**（含 `/share/**` 的 HTML 页与 `/media/**` 只读图片）；
- **鉴权矩阵**：把 `SecurityConfig` 的 `permitAll` 清单原样抄进文档，
  明确区分「完全公开 / 需要登录或匿名会话 / 需要 ADMIN」三档；
- **错误码表**：`code` 与 HTTP 状态的对应关系，并写明「归属校验统一回 404 而不是 403」的理由；
- **数据状态语义**：把 `ToolResult.dataStatus()` 的 5 种取值
  （实时数据 / 缓存数据 / 系统资料 / 演示数据 / 演示数据（降级））连同**判定顺序**一起写进文档 ——
  顺序错了就会出现"取不到真实数据、却被显示成普通演示数据"；
- **管理端接口**：景点 CRUD + geocode、图片上传、运行统计、工具健康度、LLM 供应商、反馈、操作日志；
- **环境变量速查**：只列与接口行为直接相关的那些。

顺带纠正了两处容易写错的事实：景点分页 `page` 从 **1** 开始（不是 0），
`/api/pois/page` 返回对象而 `/api/pois` 返回数组（因此不能把两者合成一个端点）。

### 14.2 顺带查出来的三个缺口（已记进 `API.md` §13.2，本轮未改代码）

1. **CORS 白名单缺 `X-Device-Fingerprint`（T23 已修复）**
   `SecurityConfig.corsConfigurationSource` 只放行了 `Authorization` / `Content-Type` / `X-Anonymous-Token`，
   而这个头在 `POST /api/anonymous/session` 与 `POST /api/trip-plans` 上都是接收的。
   影响面：浏览器跨域调用会 preflight 失败；**APK 不受影响**（不是浏览器）。
   修法是把该头追加进 `allowedHeaders`，纯追加、无兼容风险。

2. **管理台容器内 `/api` 没有反代（T23 已修复）**
   `backend/admin/Dockerfile` 目前只有 `nginx:alpine` + `dist`，没有 `nginx.conf`。
   后果是容器里管理台能打开、接口一律 404。修法是补一份 nginx.conf
   （`/api` → `http://server:8080`，前端路由回落 `index.html`）。

3. **没有自动生成的 OpenAPI**
   本机 Maven 是离线状态（`mvn -o`），新增 `springdoc-openapi` 依赖有拉不到的风险。
   顺序因此定为：先用这份手写文档保证公开测试可用，之后再评估能否换自动生成。

### 14.3 验证

本轮只新增/修改 `docs/` 下的 Markdown，没有动任何代码，因此不需要重跑编译与单测。

```text
node scripts\normalize-crlf.mjs docs\API.md   → 1 file(s) converted to CRLF
node scripts\normalize-crlf.mjs --check docs  → OK: 25 file(s) already CRLF.
```

### 14.4 下一步

按既定节奏进入第二轮：**定位 + 附近景点**
（权限、拒绝授权后的兜底、隐私说明、真机验证，并同步把 `/api/pois/nearby` 补进 `API.md`）。

---

## 15. T21 执行结果（定位 + 附近景点：全链路）

### 15.1 为什么服务端先做

第二轮的完整目标是「定位 + 附近景点」。其中设备定位那一半要引入 `geolocator` 插件，
而本机 pub cache（`tooling/.pub-cache`）原本**没有**这个包，离线加不了 ——
需要一次联网的 `flutter pub add geolocator`。服务端那一半不依赖任何新东西，
所以先把服务端做掉，两块互不阻塞；随后在用户选择「联网加 geolocator」后补齐客户端。

### 15.2 新增 `GET /api/pois/nearby`（免登录）

`lng` / `lat` 必填，`radius` 默认 3000（200—20000），`limit` 默认 10（1—50），
非法值夹回合法区间而不抛 400 —— 理由和分页一样："附近"是随手操作，
不该因为滑杆传了个 0 就变成一张错误页。

### 15.3 核心不是"能不能排序"，而是坐标系

内容库里的景点坐标是 **BD-09**（运营台手工核对或百度解析得来），
而设备 GNSS 给的是 **WGS-84**。两者在河南境内差 **1 公里上下** ——
直接相减，"附近景点"会把 800 米外的说成 300 米。这不是精度问题，是错误。

处理方式：新增 `common/GeoCoordinate`，把设备的 WGS-84 先换算到 BD-09 再比距离。
**换算只在这一个地方实现**，客户端拿到的始终是同一套坐标系下算出来的距离；
换底图或换数据源时，不需要所有已发布的 APK 跟着升版。

换算的完整链路是 `WGS-84 → GCJ-02 → BD-09`，两步的适用范围**不一样**，
这一点写进了类注释，也被测试钉住：

- GCJ-02 的偏移**只在中国大陆生效**，境外点原样通过；
- GCJ-02 → BD-09 是**恒定的小量平移**，对任何点都会加（这正是百度坐标系在全世界的定义方式）。

第一版测试把这两条混成了一句"境外坐标原样返回"，跑出来才发现是错的 ——
错的是**测试的预期**，不是实现。修正后两条各自成为一条用例。

### 15.4 距离口径与隐私

- `distanceMeters` 是**直线距离**（球面大圆距离），不是步行或驾车里程。
  没有路网数据就不拿它除以步速去编一个"步行 5 分钟"出来 —— 字段里没有这个数，界面也不该有；
- 服务端**不保存**这次查询的坐标，位置不落库，也就没有位置历史；
- 只返回**上架且确实配了坐标**的景点。没配坐标的不参与计算，也不拿城市中心凑数 ——
  那种"看起来能用"的坐标比没有坐标更坏。跳过了几个写在 `skippedWithoutCoordinate` 里，
  否则「附近没景点」和「附近景点都没配坐标」在界面上长得一模一样。

### 15.5 验证结果

```text
mvn -o -B test        Tests run: 86, Failures: 0, Errors: 0
                      （原 72；新增 GeoCoordinateTest 7 + NearbySearchTest 7）
```

两个新类都是纯函数，不依赖 Spring，因此能被直接测：

| 新文件 | 职责 |
| --- | --- |
| `common/GeoCoordinate.java` | WGS-84 → BD-09 换算 + 球面直线距离 |
| `common/NearbySearch.java` | 半径过滤、距离升序、并列按 id、截断 limit |

`NearbySearchTest` 覆盖 7 条规则：排序、半径过滤、先排序再截断、
并列顺序稳定（否则分页与缓存会变成玄学）、空输入、`null` 点位只跳过不失败、半径边界含在内。

### 15.6 客户端一半（本轮补齐）

用户选择「联网加 `geolocator`」。客户端新增 2 个模块 + 1 个页面，并接入首页入口。

| 新文件 | 职责 |
| --- | --- |
| `core/location/location_service.dart` | 系统开关 / 权限判定 + 取一次当前位置；不缓存、不记录、不上报 |
| `core/formatters/distance_text.dart` | 距离文案（<1km 报米、整公里不带小数、其余一位小数） |
| `screens/nearby_screen.dart` | 「在我附近」页面：定位 → 列表，失败/拒绝都有明确出路 |

`data/repositories/travel_repository.dart` 新增 `fetchNearby(...)`（走 `GET /pois/nearby`）
与 `NearbyHit` / `NearbySearchResult` 模型，并给 `fetchDestinations({String? city})` 加了城市筛选。

设计上的三个要点：

- **拒绝授权不是死路。** 页面第一选项永远是「按城市浏览」，
  只有「永久拒绝」和「系统总开关关着」才出现「去系统设置」按钮；
  用户按「在我附近」之前，应用不会预先弹权限框。
- **附近不降级。** 定位失败就如实说失败，不拿城市中心凑一份假列表；
  景点列表接口的离线/演示降级只作用于「内容浏览」，不作用于「附近」。
- **坐标系由服务端兜住。** 客户端只上报 WGS-84 原始坐标，
  BD-09 换算和距离口径全部在服务端（见 15.3），界面只能措辞为直线距离。

首页「发现」页在场景 chips 与三条示范走廊之间新增「在我附近」入口卡，
文案明确写了「需要一次定位授权；不授权也能按城市浏览」。

### 15.7 验证结果（本轮）

```text
flutter analyze       No issues found! (7.5s)
flutter test          All tests passed (131)        （原 110；新增 21）
flutter build apk --debug
                      √ Built build\app\outputs\flutter-apk\app-debug.apk
                      169436800 bytes（161.6 MB，首次拉 Gradle 依赖耗时约 597s）
```

新增测试 21 条，覆盖三块纯逻辑：
`location_readiness_test.dart`（10 条：系统开关 / 授权 / 永久拒绝的判定顺序）、
`distance_text_test.dart`（4 条）、`nearby_repository_test.dart`（7 条）。

构建警告（非阻塞）：`package_info_plus`、`share_plus` 使用了 KGP，
未来 Flutter 版本会影响，属于上游插件的迁移节奏，不影响当前交付。

### 15.8 已知边界

1. `distanceMeters` 是**直线距离**，不是步行或驾车里程，界面不换算成分钟；
2. 内容库里**没配坐标**的景点不参与「附近」计算，只在 `skippedWithoutCoordinate` 里计数，
   不拿城市中心凑数；
3. 位置只用于当次请求，客户端不缓存坐标，服务端不落库；
4. 权限被永久拒绝时，应用内无法再次唤起系统弹窗，只能引导到系统设置或改走「按城市浏览」。

### 15.9 下一步

真机验证（用户自行在模拟器完成）：

- 模拟器需**手动设一个河南定位点**（Extended controls → Location），
  例如郑州 `113.6254, 34.7466` 或洛阳 `112.4540, 34.6197`；
- 首次授权 → 看到附近列表；拒绝授权 → 看到「按城市浏览」面板；
- 系统定位开关关掉 → 看到「去系统设置」按钮；
- 首页新增的「在我附近」入口可正常进入。

---

## 16. T22 执行结果（铁路票价与中转换乘进入规划链路）

### 16.1 这一轮解决的两个缺口

此前 12306 只用了 `query-tickets`，结果是：

1. 车次能查到、余票能显示，但 `query-ticket-price` 从未调用，席别与票价没有进入提示词和预算；
2. `query-transfer` 虽然已在 MCP 服务里确认可用，却没有编排进规划，直达没有票时不会自动给换乘备选。

本轮把两者都拆成**独立工具**，而不是把票价塞进车次结果：
票价和余票来自不同接口、时效不同，混成一条结果会让“车次查到了、票价没查到”这种真实情况
失去来源与降级痕迹。工具名与职责如下：

| 工具 | 数据来源 | 职责 | 失败口径 |
| --- | --- | --- | --- |
| `searchTrain` | `query-tickets` | 车次、时刻、席别余票 | 降级到参考时刻表并标 `errorCode` |
| `quoteRailFares` | `query-ticket-price` | 各车次各席别票价（元） | 降级到参考价，不冒充官方实时价 |
| `searchTransfer` | `query-transfer` | 一次换乘方案、等待时间、总历时 | 无结果就是无结果，失败时带原因降级 |

### 16.2 代码改动

| 文件 | 改动 |
| --- | --- |
| `tools/ToolModels.java` | `TrainInfo` 增加结构化 `seats`；新增 `RailFare` / `RailTransfer` / `RailTransferSegment` |
| `tools/TravelToolPort.java` | 新增 `quoteRailFares` / `searchTransfer`，默认实现明确报“不支持”，不静默吞调用 |
| `infrastructure/external/railway/RailwayMcpClient.java` | 新增 `query-ticket-price` / `query-transfer` 两个 MCP 调用与解析；价格统一归一到整数元 |
| `infrastructure/external/CompositeTravelTools.java` | 两条新链路接入缓存、失败退避与降级标注 |
| `tools/ToolOrchestrator.java` | 同一日期、同一起终点并行编排直达、票价、中转；工具轨迹分别记录来源 |
| `ai/PlanningPromptFactory.java` | 提示词明确要求跨城交通只能引用票务工具数据，交通节点要按人数与往返核算 |
| `ai/TripPlanValidator.java` | 用最低铁路票价 × 人数 × 往返算出预算下限；方案总价低于它时给出可解释警告 |

### 16.3 预算口径

本轮**没有**让系统擅自改写模型生成的行程与金额，而是做确定性的“预算下限检查”：

```text
最低铁路票价（当前工具数据）
  × 同行人数
  × 往返（2 天及以上按往返）
= 铁路交通预算下限

方案总价 < 下限  →  警告“跨城交通预算可能不完整”
```

这样既避免模型把票价漏掉，也不会因为一次票价查询失败就把用户的行程价格改坏。
票价数据本身仍在工具轨迹里逐条展示来源与状态。

### 16.4 验证结果

```text
mvn -o -B test        Tests run: 92, Failures: 0, Errors: 0
                      （原 86；新增 RailwayMcpClientParsingTest 4
                        + TripPlanValidatorRailFareTest 2）
```

新增测试覆盖：结构化余票、票价小数归一、非法价格丢弃、中转两段行程解析、
预算低于铁路下限时报警、方案已覆盖铁路下限时不误报。

### 16.5 已知边界

1. 12306 票价是官方查询结果，但不等于最终支付金额；界面仍必须引导用户去官方渠道确认；
2. 中转方案只取一次换乘，且最多保留 3 条，避免把移动端结果页变成无穷列表；
3. 预算下限只计算跨城铁路，不含市内交通、景区接驳和住宿；
4. 若 12306 票价服务降级，预算下限会使用明确标注的参考价，并在工具轨迹显示降级原因。

---

## 17. T23 执行结果（公开测试与容器部署收口）

### 17.1 修了什么

这两项都写在 `docs/API.md` §13.2 的“已知缺口”里，属于公开测试和容器部署前必须收口的问题：

| 缺口 | 修复 | 影响 |
| --- | --- | --- |
| CORS 未放行 `X-Device-Fingerprint` | `SecurityConfig` 的 `allowedHeaders` 追加该头 | 浏览器跨域创建匿名会话、提交行程不再被 preflight 拦住 |
| admin 容器没有 `/api` 反代 | 新增 `backend/admin/nginx.conf`，Dockerfile 安装该配置 | 管理台容器不再“页面能打开、接口全 404” |

### 17.2 Nginx 配置内容

```text
/api/     → http://server:8080
/         → try_files $uri $uri/ /index.html
/healthz  → 200 ok
```

同时保留了 `proxy_set_header Host/X-Real-IP/X-Forwarded-For/X-Forwarded-Proto`，
这样后端日志与后续 HTTPS 反代能看到真实来源。

### 17.3 验证结果

```text
mvn -o -B test        Tests run: 93, Failures: 0, Errors: 0
                      （新增 SecurityConfigCorsTest 1 项）
node scripts\normalize-crlf.mjs --check ...
                      OK
```

### 17.4 剩余接口层事项

`docs/API.md` §13.2 仍保留一项：**没有自动生成的 OpenAPI**。
本机 Maven 离线，新增 `springdoc-openapi` 依赖有拉取风险；当前继续以手写 `docs/API.md`
作为公开测试接口清单，后续在可联网环境再评估自动生成。

---

## 18. T24 执行结果（管理台内容运营视图）

### 18.1 做了什么

管理台新增 `ContentOpsView.vue` 与侧栏入口「内容运营」，一个页面两条线：

1. **城市与主题**：按现有景点内容聚合城市覆盖、上架比例、坐标覆盖、主题标签分布；
2. **图片与版权**：聚合已登记 / 待处理 / 缺图 / 版权未登记四类数量，按缺口严重程度排序，
   点击「去处理」可以直接打开对应景点的编辑抽屉。

这不是静态看板：数据来自现有 `GET /api/admin/pois`，城市和主题没有再做一份重复的内容库，
所以不会出现“运营页数字和景点表对不上”的两套口径。

### 18.2 编辑闭环

`PoisView` 现在支持 `?focus=<poiId>`：内容运营页点击待办后跳到景点管理，
加载完成后自动打开该景点的编辑抽屉，运营人员不需要在一长串表格里再找一次。

### 18.3 验证结果

```text
npm run build（admin）
  ✓ 610 modules transformed
  dist/assets/ContentOpsView-…js  8.39 kB │ gzip: 3.09 kB

node scripts\normalize-crlf.mjs --check ...   OK
```

前端构建通过，新增视图已经进入 `backend/admin/dist`，容器构建时会自动带上。

### 18.4 仍缺的管理台视图

- ~~提示词版本视图~~ **已完成（T25）**：见第 19 节，支持发布、启用和回滚；
- Mock 数据管理视图：当前 Mock 数据仍由代码/配置决定，没有做成可编辑的资源。

---

## 19. T25 执行结果（提示词版本管理）

### 19.1 做了什么

提示词从代码常量升级为可管理版本：

| 层 | 变化 |
| --- | --- |
| 数据 | 新增 `prompt_version` 表：版本号、系统提示词、说明、启用状态、创建时间 |
| 服务 | 新增 `PromptVersionService`：空库时种入内置基线；发布新版本会原子取消旧版本；历史版本可重新启用 |
| 规划 | `PlanningPromptFactory` 读取当前启用版本；`TravelPlanningFacade` 把版本号写进 `prompt_version` 和工具轨迹 |
| 接口 | 新增 `/api/admin/llm/prompts`：列表、当前版本、发布、启用 |
| 管理台 | 新增「提示词版本」页：查看当前提示词、复制为模板、发布并启用、历史回滚 |
| 审计 | 发布与启用都会写 `OperationLog`，可在「操作日志」中追溯 |

### 19.2 为什么只管理“系统提示词”

用户请求、工具数据、JSON 输出契约和厂商无关解析仍由代码控制。运营台可以调整“角色、语气、
数据纪律和输出要求”，但不能一次误操作删掉工具调用约束或 JSON 字段契约。这个边界会在
管理台页面和 API 文档里都说明。

### 19.3 版本回退

每次发布都是新记录，不覆盖旧版本。新生成的行程记录当前版本号；如果某个版本导致输出质量下降，
管理台可以直接启用旧版本。历史上已经保存的行程不会被改写，仍然保留它生成时的版本号。

### 19.4 验证结果

```text
mvn -o -B test        Tests run: 95, Failures: 0, Errors: 0
                      （新增 PromptVersionServiceTest 2，并断言规划结果写入当前版本）
npm run build（admin）
  ✓ 612 modules transformed
  dist/assets/PromptVersionsView-…js  5.15 kB │ gzip: 2.35 kB
```

### 19.5 已知边界

1. 版本比较暂未做 side-by-side diff，只提供全文查看与历史切换；
2. 没有自动评估集，发布新版本前后不会自动跑一轮“方案质量打分”；
3. 版本号由运营人员填写，服务端只校验唯一性与长度，不替代团队的命名规范。

---

## 20. T26 执行结果（APK 运行时服务器地址）

### 20.1 解决的问题

此前 release APK 的服务器地址只能通过编译期 `--dart-define=API_BASE_URL=...` 固定：
测试者拿到包后，如果后端换到腾讯云或另一台机器，就必须重新打包。T26 把这件事改成
运行时可配置，同时不破坏原有编译期优先规则。

### 20.2 地址来源优先级

```text
编译期 API_BASE_URL（如果有）
  > 本机安全存储中的用户地址
  > debug 默认 10.0.2.2:8080/api
  > release 未配置（明确报配置失败，不静默连 localhost）
```

### 20.3 设置页能力

「我的 → 设置 → 软件设置 → 服务器地址」：

1. 显示当前地址与来源；
2. 输入域名时可自动补 `https://` 和 `/api`；
3. 「测试并保存」会真实请求 `GET /api/home`，成功才切换；
4. 后端暂时离线时可选「仅保存」，不会伪造“测试通过”；
5. 编译期固定地址时页面为只读，避免出现“设置保存了但实际没生效”。

Release 包只接受 HTTPS；debug 包允许 HTTP，方便 `10.0.2.2:8080` 与局域网调试。

### 20.4 客户端行为

- 地址写入 `ServerEndpointStore`，应用重启后继续生效；
- Riverpod 的 `AppConfigController` 更新后，Dio、Repository 与依赖页面自动重建；
- 修改地址会重新解析图片媒体地址，不会继续把图片指向旧服务器；
- 原有的匿名令牌与登录令牌不变，换地址后按新服务的会话规则重新建立身份。

### 20.5 验证结果

```text
flutter analyze                       No issues found! (47.1s)
flutter test                          All tests passed (137)（新增 6 项地址解析测试）
flutter build apk --debug
  √ Built build\app\outputs\flutter-apk\app-debug.apk
  Gradle assembleDebug 103.0s，193,861,786 bytes
```

### 20.6 已知边界

1. 运行时地址解决“指向哪个后端”，不替代 HTTPS 证书与域名部署；
2. 修改服务器地址后，不同后端之间的账号与行程不会自动迁移；
3. 正式包仍然必须使用 HTTPS；HTTP 在 release 模式下会被配置校验拒绝。

---

## 21. T27 执行结果（Mock 数据管理）

### 21.1 做了什么

管理台新增「Mock 数据」页，后端新增 `demo_scenario` 表与 `/api/admin/mock/scenarios`：

- 支持 `weather`、`route`、`train`、`railFare`、`transfer` 五类演示数据；
- 匹配键支持精确值（如 `洛阳`、`郑州>洛阳`）和 `default` 兜底；
- 保存前按目标返回类型反序列化校验，坏 JSON 直接拒绝，不会进入运行时；
- 运营台可以启用、停用、修改、删除覆盖；
- `MockTravelTools` 只有在记录启用时才使用覆盖，否则回退代码内置样例。

### 21.2 为什么不做“任意 JSON”

如果允许任意 JSON，演示模式会在真正生成方案时才炸，错误位置离保存动作很远。
这里按 `WeatherInfo`、`RouteInfo`、`TrainInfo[]`、`RailFare[]`、`RailTransfer[]`
五种真实工具形状校验，运营人员保存时就能看到问题。

### 21.3 数据安全边界

- 只保存演示数据，不接收真实用户输入、不保存位置、证件或支付信息；
- 覆盖项只影响 mock 分支，不会把演示数据标成实时数据；
- 删除覆盖后立即回退内置样例，不留半截状态；
- 增删改都写 `OperationLog`。

### 21.4 验证结果

```text
mvn -o -B test        Tests run: 98, Failures: 0, Errors: 0
                      （新增 DemoScenarioServiceTest 3 项）
npm run build（admin）
  ✓ 614 modules transformed
  dist/assets/MockDataView-…js  7.14 kB │ gzip: 3.09 kB
```

### 21.5 已知边界

1. 覆盖是按“类型 + 匹配键”精确匹配，不做模糊匹配；需要兜底时主动配置 `default`；
2. 行程模板本身仍由 `TripPlanFactory` 提供，不在这次 Mock 数据覆盖范围内；
3. 管理台不提供在线测试调用，保存后通过下一次规划或工具轨迹验证。

---

## 22. T28 执行结果（个人信息与账号安全）

### 22.1 个人信息

- `user_account` 新增 `nickname` 与 `avatar_key`；
- 「我的 → 设置 → 个人信息」可以编辑昵称；
- 头像使用 5 个预设图案（山河 / 古建 / 日光 / 河流 / 灵感）和首字回退；
- 不提供照片上传：图片目录是公开只读地址，避免把用户照片变成可访问的公开资源；
- 顶部身份卡显示昵称、用户名、邮箱和当前头像。

### 22.2 账号与安全

| 功能 | 实现 |
| --- | --- |
| 修改密码 | 校验当前密码，BCrypt 保存新密码，撤销所有刷新令牌，本机重新登录 |
| 邮箱验证 | 复用 SMTP 预留接口；验证成功后刷新 `/auth/me` |
| 退出所有设备 | 撤销所有 refresh token；当前 access token 到期前仍有效，界面明确提示 |
| 删除账号 | 密码确认后级联删除分享、行程、收藏、刷新令牌和账号 |
| 账号资料接口 | `PATCH /api/auth/me` |

删除账号是事务操作，顺序固定为：分享 → 行程 → 收藏 → 刷新令牌 → 账号；
任一步失败都会整体回滚。

### 22.3 收藏交互

- 景区详情页收藏按钮改为 `star_border` / `star`；
- 收藏成功后使用麦穗色实心星；
- 「我的收藏」列表与入口同步使用星标；
- 收藏状态仍由服务端列表驱动，不在本地伪造。

### 22.4 软件设置

- 服务器地址：测试并保存；
- 离线缓存：显示当前占用，可一键清除；
- 外观 / 字体 / 动效：继续跟随系统设置，不提供无效开关。

### 22.5 验证结果

```text
mvn -o -B test        Tests run: 102, Failures: 0, Errors: 0
                      （新增 AuthServiceAccountTest 3 + AccountDeletionServiceTest 1）
flutter analyze       No issues found
flutter test          All tests passed (140)（新增账号仓库测试 3）
flutter build apk --debug
  √ app-debug.apk，193,887,626 bytes，Gradle assembleDebug 24.1s
```

### 22.6 已知边界

1. 退出所有设备撤销的是 refresh token，已签发的短时 access token 到期前仍有效；
2. 头像为预设图案，照片上传留到有独立对象存储和隐私策略后再评估；
3. 删除账号不可恢复，界面已做密码确认和红色危险操作提示。

---

## 23. T29 执行结果（服务端消息中心 + 退出入口收口）

### 23.1 服务端消息

新增 `user_message` 表与 `/api/messages`：

- 登录用户首次打开消息中心时种入产品、数据、隐私、行程同步四类系统消息；
- 已读状态保存在服务端，跨设备同步；
- 支持单条已读、全部已读和未读数查询；
- 未登录仍显示本机产品说明，登录后自动切换到账号消息；
- 消息只保存标题、正文、类型与已读时间，不保存推送令牌或设备标识。

### 23.2 退出入口

「我的」页底部的重复“退出登录”已移除；现在只在
「我的 → 设置 → 退出登录」保留一个入口。

### 23.3 验证结果

```text
mvn -o -B test        Tests run: 104, Failures: 0, Errors: 0
                      （新增 MessageCenterServiceTest 2 项）
flutter analyze       No issues found
flutter test          All tests passed (140)
flutter build apk --debug
  √ app-debug.apk，193,891,778 bytes，Gradle assembleDebug 13.6s
```

### 23.4 已知边界

1. 当前是站内消息，不接 APNs / FCM，不承诺后台实时推送；
2. 消息的生成以账号首次读取和系统说明为主，尚未接入邮件或运营后台群发；
3. 未登录状态的消息只存在本机内存，重启后按未读重新展示。

---

## 24. T30 执行结果（社区旅记后端底座）

> 社区功能是分阶段推进。本轮只完成第 1 阶段后端，Flutter 社区页和管理台审核页
> 仍未开发，不能把当前状态描述成“社区已上线”。

### 24.1 新增数据模型

| 表 | 用途 |
| --- | --- |
| `community_post` | 旅记主体、作者、关联行程、公开范围、审核状态、点赞和浏览量 |
| `community_post_image` | 旅记图片 URL 与排序 |
| `community_like` | 用户对旅记的点赞，唯一约束防止重复 |
| `community_report` | 用户举报与管理员处理状态 |

### 24.2 新增接口

- `GET /api/community/posts`：公开已通过旅记，分页、城市/标签筛选；
- `GET /api/community/posts/{id}`：公开详情，作者可查看自己的未通过旅记；
- `GET /api/community/posts/mine`：自己的全部旅记；
- `POST/PATCH/DELETE /api/community/posts`：发布、编辑、删除；
- `POST/DELETE /api/community/posts/{id}/like`：点赞与取消；
- `POST /api/community/posts/{id}/report`：举报；
- `/api/admin/community/posts`：待审核、通过、驳回、下架；
- `/api/admin/community/reports`：举报处理。

### 24.3 安全与边界

- 浏览公开旅记不需要登录，发布、编辑、点赞和举报必须登录；
- 只能关联本人行程；
- 只有 `APPROVED + PUBLIC` 的旅记可以被点赞和举报；
- 同一用户不能重复点赞、重复举报同一旅记；
- 不能举报自己的旅记；
- 图片数量最多 9 张，图片地址只允许 HTTPS、HTTP 或 `/media/`；
- 审核动作写操作日志；
- 本轮不实现图片上传和 EXIF 清理：真正接 Flutter 发布流程前必须补上，
  否则用户照片的拍摄位置可能泄露。

### 24.4 验证结果

```text
mvn -o -B test        Tests run: 108, Failures: 0, Errors: 0
                      （新增 CommunityServiceTest 4 项）
```

### 24.5 下一阶段

按 [`docs/COMMUNITY_PLAN.md`](COMMUNITY_PLAN.md) 进入第 2 阶段：

- 先做 Flutter 社区信息流和详情页；
- 再做发布流程；
- 最后做管理台审核页；
- 发布流程前补图片上传、EXIF 清理和发布频率限制。

---

## 25. T31 执行结果（社区 Flutter 浏览体验）

### 25.1 新增页面与入口

- 底部导航改为：发现 / 旅记 / 行程 / 我的；
- 旅记页首次切换进入时才加载，避免后台无意义请求；
- 信息流支持城市与主题筛选、下拉刷新和滚动分页；
- 详情页展示多图、正文、作者、城市、主题、发布时间；
- 点赞使用星标实心 / 空心反馈，未登录时先进入登录；
- 举报使用底部原因选择器，提交后由管理员处理。

### 25.2 代码落点

| 文件 | 职责 |
| --- | --- |
| `models/community_models.dart` | CommunityPost / CommunityPage 解析 |
| `data/repositories/community_repository.dart` | 信息流、详情、点赞、举报请求 |
| `screens/community_screen.dart` | 旅记信息流与详情页 |
| `screens/home_screen.dart` | 四入口底部导航与旅记 tab |
| `app/providers.dart` | communityRepositoryProvider |

### 25.3 验证结果

```text
flutter analyze       No issues found
flutter test          All tests passed (144)
flutter build apk --debug
  √ app-debug.apk，194,087,481 bytes，Gradle assembleDebug 151.9s
                      （新增社区仓库测试 3 + 社区页面 widget 测试 1）
flutter build apk --debug
  √ app-debug.apk，193,919,585 bytes，Gradle assembleDebug 15.2s
```

### 25.4 当前边界

1. 旅记图片仍依赖 `/media/` 或 HTTPS URL，尚未开放用户端上传；
2. 发布旅记表单尚未实现，下一阶段补；
3. 管理台审核页尚未实现，下一阶段补；
4. 社区信息流当前不做本地离线缓存，失败时明确提示；
5. 评论、关注、私信不进入首版范围。

---

## 26. T32 执行结果（社区发布流程）

### 26.1 发布入口

- 「旅记」页右上角新增「写旅记」；
- 未登录先进入登录，不伪造发布成功；
- 发布页必须选择本人已保存的行程，不能脱离行程凭空发帖。

### 26.2 发布内容

- 标题、正文、城市、标签；
- 公开 / 仅自己可见；
- 1—9 张图片，Android 系统相册多选；
- 图片先上传服务端，再随旅记提交；
- 提交后状态为 `PENDING`，不会直接出现在公开信息流。

### 26.3 图片隐私

新增 `POST /api/community/media/images`：

- 只接受 JPEG / PNG；
- 最长边不超过 3000 像素；
- 服务端重新解码再编码，主动去除 EXIF 位置信息；
- GIF 不进入用户旅记图片入口；
- 上传动作记录操作日志，但不记录图片内容。

### 26.4 验证结果

```text
mvn -o -B test        Tests run: 110, Failures: 0, Errors: 0
                      （新增 MediaStorageServiceTest 2 项）
flutter analyze       No issues found
flutter test          All tests passed (144)
```

### 26.5 下一阶段

按 `COMMUNITY_PLAN.md` 进入第 4 阶段：

- 管理台旅记审核列表；
- 通过、驳回、下架、恢复；
- 举报处理；
- 审核操作日志；
- 真正打通“用户发布 → 管理台审核 → 公开信息流”。
