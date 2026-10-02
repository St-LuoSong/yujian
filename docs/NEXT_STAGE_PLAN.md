# 下一阶段执行计划（当前有效：阶段十一）

> 阶段名称：阶段十一 · 从"能演示"到"能交付"
> 依据：`docs/PROJECT_STATUS.md` 第 4 节的 P0 清单
>
> 本文档顶部是**当前有效计划**；下面标记为"历史"的部分是阶段四的计划与执行记录，
> 已完成，保留用于追溯，**不要按它继续排期**。

## 为什么要单开一个阶段

阶段十结束时，主业务闭环已经跑通，外部数据也有真实来源。但对照比赛评分项
（需求分析 / 功能完成度 / 技术路线 / 交互体验 / 系统稳定性 / 数据安全意识 / 应用推广价值），
还差五件事是**必须补齐**的，而且它们都无法靠改代码量堆出来：

1. 项目定位是"联动 LLM"，但当前没有任何 provider 被启用；
2. 计划里的"地图与时间轴联动"没有兑现；
3. 景区配图仍是外链示例图，既有版权风险也削弱河南特色；
4. 作品要求第 (1) 条列出的交付材料（演示视频、截图、架构图、ER 图、测试说明）基本为空；
5. release 包没有可用后端，且刻意禁止明文流量。

## T11.1 接入真实大模型（最高优先）

**为什么先做这个**：它是项目定位的核心，也是答辩第一个问题。

| 项 | 做法 |
| --- | --- |
| 选哪家 | 先从 DeepSeek 或通义千问里选一家启用（成本最低、OpenAI 兼容） |
| 怎么配 | `LLM_ENABLED=true` + `LLM_<厂商>_ENABLED=true` + `LLM_<厂商>_API_KEY=...`，写进 `scripts\local.env` |
| 密钥位置 | **只写服务端**，不进 APK、不进管理台、不进 `.env.example` |
| 验收一 | `GET /api/admin/llm/providers` 显示该厂商 `enabled=true configured=true`，且不泄漏密钥 |
| 验收二 | 用一句真实需求生成方案，工具轨迹里引擎不再是 Mock，且界面**不再**显示"演示数据（AI 降级）" |
| 验收三 | 故意把密钥改错，验证按 priority 降级到下一家，全部失败时仍然返回可用方案 |

**降级纪律不变**：降级必须可见，不许把 Mock 生成的方案说成 LLM 生成。

## T11.2 地图 Tab 独立验证（已完成）

先做独立验证，验证不过就不耦合进行程页。

| 步骤 | 验收证据 |
| --- | --- |
| 1. 选型 | 百度官方 Android SDK / Flutter 插件 / WebView 承载，三选一并记录理由与许可证 |
| 2. 静态地图 | 模拟器上显示河南地图区域，无密钥时给出明确错误而不是白屏 |
| 3. 打点 | 显示当日景点标记，点击标记能回传景点 id |
| 4. 画线 | 按方案里的路线画折线，顺序与时间轴一致 |
| 5. 降级 | 地图不可用（无 AK / 无网络 / SDK 失败）时退回现有文字路线，**不出现空白 Tab** |

### 执行结果

**选型结论：不引入任何百度 Android SDK 或 Flutter 插件**，改为「服务端代理静态底图 +
客户端自绘标记」。理由：SDK 要求把 AK 打进 APK，与全项目"AK 只留服务端"的承诺直接冲突；
三个候选 Flutter 插件长期未更新、许可证不明。当前方案下 AK 永远不出服务器，
投影公式只有 `map/WebMercator` 一份实现（Java，可单元测试），APK 不需要理解百度坐标系。

| 原步骤 | 落地情况 |
| --- | --- |
| 1. 选型 | 出局 SDK 与插件，改服务端代理静态底图（1024px，尺寸收敛到 320—1024） |
| 2. 静态图 | `/api/map/image` 返回真 PNG（实测 102139 字节，带 `max-age=1800`）；未配置 AK 时返回 `fallback=true` 与明确说明，不白屏 |
| 3. 打点 | 标记由服务端算好像素坐标下发，APK 自绘编号圆点；点选站点与时间轴双向联动 |
| 4. 画线 | 折线按行程顺序连接，与时间轴一致；拖动时客户端本地跟手，松手才向服务端要新视野 |
| 5. 降级 | 无 AK / 取图失败 / 无可信坐标 / 外部服务异常，一律返回文字路线（`fallback=true`） |

新增接口：

```text
GET /api/trip-plans/{id}/map?day=&center=&zoom=&panX=&panY=   需登录（含匿名会话）
GET /api/map/image?center=&zoom=&width=&height=&ticket=      免登录 + HMAC 短时票据
GET /api/map/size                                            默认尺寸
```

设计细节（投影反证、票据机制、地理编码判据、降级口径）见 `docs/PHASE11_MAP.md`。

### 同批次补齐：运营台坐标维护

地图能不能打点，取决于内容库里有没有可信坐标。因此这一批同时把坐标做成了运营能力：

| 项 | 说明 |
| --- | --- |
| 字段 | 景点表单新增经纬度（百度 BD09），列表显示坐标或「未配置」 |
| 解析按钮 | `POST /api/admin/pois/geocode`，只回参考值、不落库，可以放心反复试 |
| 第一道闸 | 必须有城市限定（或景点名自带城市），否则拒绝 —— 无城市限定时"随便走走"会被解析到深圳的一家餐厅 |
| 第二道闸 | 结果必须落在河南范围（含约 30 公里外扩），否则拒绝并说明实际落点 |
| 判据一致 | 与行程地图共用 `map/PlaceTrust`，不会出现"后台存得下、地图画不出" |
| 如实标注 | 可信度低于 60 时提示"请在地图上核对后再保存"，不假装板上钉钉 |

### 验证证据

```text
node scripts\verify-map.mjs   通过 23 项，失败 0 项（含底图 PNG、票据篡改 403、缓存命中、401/404/400）
mvn -o -B test                Tests run: 44, Failures: 0, Errors: 0
flutter analyze               No issues found
flutter test                  All tests passed (57)
flutter build apk --debug     app-debug.apk 181.0MB
```

最小化外部调用（遵循"不浪费配额"）：解析坐标只实测两条 —— 一条无城市限定（在本地就被拒绝，
不产生百度请求）、一条"龙门石窟 + 洛阳"（产生 1 次地理编码调用）。

## T11.3 河南实景配图与版权

- 全部通过运营台上传，不再改后端代码或改数据库；
- 每张图登记：来源、授权方式、拍摄地、审核日期；
- 首页 Hero、三条走廊、景区卡、日卡封面统一替换；
- 同步更新 `THIRD_PARTY_NOTICES.md` 与图片版权清单。

**验收**：模拟器上所有图片来自运营台或已登记图库，网络断开时显示磁盘缓存或主题化占位，
不出现灰块或裂图。

## T11.4 交付材料

按作品要求第 (1) 条逐项产出：

```text
系统说明          架构、模块划分、技术选型理由
功能演示视频       一次完整的"发现 → 规划 → 调整 → 撤销 → 分享"导航
界面截图           360 / 390 / 412 三档，关键页面
技术架构图         三层（APK / 后端 / 管理台）+ 外部数据源分层
数据库 ER 图       user / poi / trip_plan / trip_item / trip_share / ...
AI 工具调用图       一次规划里 6 个工具的编排与降级路径
测试说明           本仓库所有验证脚本 + 自动化测试 + 真机矩阵
安全与隐私说明      数据最小化、权限清单、密钥边界、分享脱敏
第三方依赖声明       THIRD_PARTY_NOTICES.md
```

## T11.5 HTTPS 后端与 release 包

release 包禁止明文流量且不带 HTTP 回退（刻意设计）。交付前需要：

1. 部署后端到有域名的 HTTPS 环境（或用反向代理终止 TLS）；
2. `flutter build apk --release --dart-define=API_BASE_URL=https://<host>/api`；
3. 在模拟器与至少一台真机上验证 release 包可正常登录、规划、看方案；
4. 准备**离线演示兜底**：`APP_TOOLS_MODE=mock` + 预置数据，断网也能讲完整流程。

## T11.6 版本发布与 APK 在线更新

**目标：**在不引入应用市场的前提下，形成一条受控的“管理台发布 → 服务端记录 → APK 检查 → 下载 → 系统安装器安装”闭环，服务于当前公网 HTTPS 临时部署和后续正式部署。版本更新不能替代签名校验：所有可更新 APK 必须使用与当前安装包一致的正式发布签名。

### 方案选型

采用“元数据由 API 管理、APK 文件由 Nginx 静态目录分发”的轻量方案：

```text
管理台版本发布页
  ├── 上传 APK + versionName + versionCode + 更新说明
  └── 置为最新（一次只允许一个最新版本）
          ↓
Spring Boot：记录发布元数据、校验文件、写操作日志
          ↓
Nginx /download/<artifact>.apk：仅 HTTPS 静态下载
          ↓
APK：GET /api/app/version → 比较 versionCode → 下载 → Android 系统安装器
```

不把 APK 二进制长期放在 MySQL，也不让 APK 下载经过 Spring Boot 业务线程。发布文件使用独立的 `download` 目录或共享卷；目录只允许管理员发布流程写入，Nginx 只读暴露 `/download/`。

### 服务端与发布数据

新增 `app_release`（或等价的版本发布表），至少包含：

- `version_code`：严格为正整数，作为唯一比较依据；
- `version_name`：展示版本号，例如 `0.2.0`；
- `release_notes`：更新说明，限制长度并按纯文本展示；
- `artifact_file_name` / `download_url`：只保存服务端生成的文件名和 HTTPS 下载地址，不接受用户提供的任意路径；
- `sha256`、`size_bytes`：下载完成后的完整性校验信息；
- `published`、`published_at`、`created_by`；
- 可选 `force_update`：只有确有兼容性或安全原因时才启用强制更新。

约束：

1. `version_code` 必须大于 0；同一 `version_code` 不允许覆盖已发布文件；
2. “置为最新”在事务中完成，先取消旧版本 `published`，再发布新版本，避免出现两个最新版本；
3. 最新版本接口只返回公开字段，不返回管理员、存储路径或内部日志；
4. 发布前校验 APK 后缀、大小上限、SHA-256，并使用临时文件写入后原子移动，禁止直接覆盖正在下载的文件；
5. 发布和撤销都写入 `OperationLog`，不记录 APK 内容、Token 或密钥；
6. 删除/撤销版本不能删除当前线上仍被引用的文件，至少保留可回滚的上一版本。

新增接口建议：

```text
GET  /api/app/version              公开，返回当前最新版本；无新版本时也返回 200
POST /api/admin/releases           ADMIN，multipart 上传 APK + 版本信息
GET  /api/admin/releases           ADMIN，查看发布历史
PATCH /api/admin/releases/{id}/publish  ADMIN，置为最新
PATCH /api/admin/releases/{id}/revoke   ADMIN，撤销版本（不立即删除文件）
```

`GET /api/app/version` 的响应至少包含：

```json
{
  "versionCode": 12,
  "versionName": "0.2.0",
  "releaseNotes": "修复登录与地图显示问题。",
  "downloadUrl": "https://<host>/download/yujian-0.2.0-12.apk",
  "sha256": "…",
  "sizeBytes": 52428800,
  "forceUpdate": false,
  "publishedAt": "2026-10-02T12:00:00Z"
}
```

### 管理台“版本发布”页面

新增 `admin/src/views/ReleasesView.vue` 与对应路由、侧栏入口和 API 类型：

1. 选择 `.apk` 文件；
2. 填写 `versionName`、`versionCode`、更新说明；
3. 显示文件大小、上传进度、SHA-256（服务端最终结果为准）；
4. 上传后先显示“草稿/未发布”，明确区分“上传成功”和“已置为最新”；
5. 点击“置为最新”前展示版本号、文件名、大小和更新说明，二次确认只用于这个不可逆的对外发布动作；
6. 展示当前最新版本和历史版本，支持撤销但不提供物理删除；
7. 失败时保留已填写内容，明确显示大小超限、格式错误、版本冲突、网络中断等原因；
8. 上传与发布按钮在请求中禁用，避免重复创建版本。

页面需复用现有管理台 token、表格、表单、状态标签和操作日志风格；移动窄屏时表格转为卡片列表，不依赖 hover 才能看到操作。

### APK 端更新闭环

新增版本检查服务和模型，使用现有 Dio / Riverpod / `AppConfig`，不新增第二套 HTTP 客户端：

- 启动后非阻塞检查一次；网络失败不得阻塞首页，也不得清空离线数据；
- “我的 → 设置”提供“检查更新”，显示当前 `versionName (versionCode)`、检查结果和最近一次检查时间；
- 使用 `package_info_plus` 读取本机 `versionName` / `buildNumber`，服务端只比较整数 `versionCode`；
- 当服务端版本更高时弹出原生风格更新卡片：版本号、更新说明、包大小、“立即更新”“稍后再说”；
- `forceUpdate=true` 时不提供绕过主流程的“稍后再说”，但仍须在网络失败、下载失败或安装权限不足时给出可恢复的错误路径；
- 点击“立即更新”后下载到应用专用临时目录，显示进度、已下载大小和取消操作；使用临时文件下载完成后再原子改名，禁止拉起半包；
- 下载完成后校验服务端 `sha256` 和文件大小，失败则删除文件并提示重试；
- 通过 Android `FileProvider` 以 `content://` URI 拉起系统安装器，不能使用 `file://`；
- Android 8+ 若未允许“安装未知应用”，引导用户打开本应用的安装权限页；返回应用后重新拉起安装器；
- 安装器最终由用户确认安装，APK 不静默安装、不绕过系统安全提示；
- 新包必须使用与当前包一致的签名，否则系统会拒绝覆盖安装；更新文案中明确“来自官方发布入口”。

推荐拆分：

```text
lib/services/app_update_service.dart
lib/models/app_release_models.dart
lib/providers/app_update_provider.dart
lib/core/widgets/app_update_card.dart
```

Android 侧补齐 `FileProvider`、专用 `file_paths.xml` 和安装 Intent；只授予临时 URI 读取权限，不暴露应用私有目录。若采用插件封装，也必须保留同样的权限、校验和错误状态。

### 安全、兼容与回滚

- 更新接口和下载地址只允许 HTTPS；Release APK 继续禁止明文流量；
- 下载域名/公网 IP 必须与当前 API 的可信 TLS 入口一致，禁止服务端返回用户可注入的 URL；
- 更新接口设置短缓存或 `no-store`，发布后 APK 通过带版本文件名避免缓存拿到旧包；
- Nginx 对 `/download/` 只读、限制单文件大小和下载速率，并记录访问日志；
- 生产发布前必须确认 APK 已使用固定 release keystore 签名，禁止沿用当前 Gradle 在缺少 `key.properties` 时的 debug 签名回退；
- 版本号只增不减；如需回滚，发布旧代码对应的更高 `versionCode` 修复包，不直接发布较低版本号；
- 用户取消、断网、磁盘不足、校验失败、安装权限关闭、签名不匹配均须可恢复，并保留当前可用版本。

### 验收证据

```text
管理台：上传草稿 → 置为最新 → 查看历史 → 撤销，重复点击不会生成重复发布记录
API：无发布版本 / 有发布版本 / 版本冲突 / 非 ADMIN / 文件过大 / 非 APK 均有明确结果
APK：当前版本等于最新不弹窗；低于最新弹卡片；手动检查可用；启动检查不阻塞首页
下载：进度可见、取消可恢复、断网重试、SHA-256/大小校验失败不会安装半包
安装：Android 8+ 权限引导、系统安装器确认、同签名覆盖安装、版本号升级成功
回归：匿名规划、登录、图片、分享、地图和离线缓存不受更新检查失败影响
```

## T11.7 真机回归矩阵

| 项 | 需要用户配合的部分 |
| --- | --- |
| 系统字体 1.3x | 安装后调大系统字体，看主要流程是否仍可用 |
| 断网 | 关掉网络，确认最近方案与景区库仍可读且标注"缓存数据" |
| 权限 | 确认安装时不再索要定位权限（当前 APK 已移除） |
| 返回键 | 生成中返回、详情返回、分享取消 |
| 弱网 | 限速下确认图片与方案不白屏 |

## 阶段完成定义（DoD）

只有同时满足以下条件才算阶段十一完成：

- `LLM_ENABLED=true` 下一家真实厂商跑通，且降级路径仍然可见；
- 地图 Tab 可用，且在地图失败时能退回文字路线；
- 所有展示图片均有来源与授权登记；
- release 包指向 HTTPS 后端并在真机验证通过；
- 第 T11.4 节的材料齐备；
- `flutter analyze` 0 问题、`flutter test` 全通过、
  `verify-tools.mjs` / `verify-railway-mcp.mjs` / `verify-map.mjs` / `mvn test` 全部通过；
- README 与 PROJECT_STATUS 能准确区分"已完成 / Mock / 待接入"。

---

# 历史：阶段四执行计划与记录（已完成）

> 以下内容为阶段四的计划与执行证据，保留用于追溯。
> 其中的测试数量（26）、APK 体积（51.3MB）等数字已被后续阶段取代，
> 当前数字见 `docs/PROJECT_STATUS.md`。
>
> 该节列出的"遗留"大多已经解决，不要当成现行缺陷：
> 分享页 401 已修复（`/share/**` 现为 `permitAll`，见 `config/SecurityConfig.java`）；
> 规划页与行程页已合并；阶段九、阶段十已把外部数据换成真实来源。

> 阶段名称：阶段四（客户端基础设施、响应式布局、数据状态）
> 目标：把“能运行的 Flutter 页面原型”推进为“在常见手机上稳定、可解释、可恢复的 APK 主体”。
> 
> 本阶段暂不深度接入百度地图 SDK，也不实现完整实时导航。地图和真实外部服务需要独立验证，避免把不稳定 SDK 带入主流程。

## 执行进度

| 任务 | 状态 | 说明 |
| --- | --- | --- |
| T4.1 冻结跨端数据契约 | 客户端已落地 | `DataStatus` 枚举、`ApiFailureKind` 错误分类、`ApiFailure` 归一化已完成；服务端仍发送中文状态字符串，由客户端解析，服务端枚举化待办 |
| T4.2 Flutter 环境与网络层 | 核心已落地 | `AppConfig`（debug/release 端点策略）、Dio 工厂、`SessionInterceptor`（令牌注入 + 匿名令牌捕获 + 单飞刷新）、`ApiClient`、`SessionStore`、`LocalCache` |
| T4.2 仓库层 | 已落地 | `TravelRepository` 实现 remote → cache → demo 三级读取，并把 `DataStatus` 与 `ApiFailure` 回传 UI |
| T4.3 设计系统 Token | 已落地 | 颜色/间距/字体 Token 与 `DataStatusBadge` 已建立，四个页面已改用 `AppColors` / `AppSpacing` / `AppTypography`，页面内颜色常量已删除 |
| T4.4 360/390/412dp 响应式适配 | 已落地（自动化守护） | 自适应页面边距与卡片宽度、关键 Row 溢出保护、竖屏锁定、键盘拖拽收起；360/390/412 三档由 widget 测试守护 |
| T4.5 接通阶段二接口 | 已落地 | 游客端已接 `/pois`、行程创建/列表/详情、`/adjust`、`/undo`、`/trace`、`/today`、`/auth/*`、`/merge-anonymous`、`/favorites`、`/share`，并逐字段核对过真实响应 |
| T4.6 移动测试矩阵 | 部分落地 | 26 项自动化测试：三档尺寸 × 三条主流程布局回归，加仓库层请求、降级、账号与分享契约；真机返回键、权限、断网与截图仍需设备 |

### 本次验证证据

```text
flutter analyze                       -> No issues found
flutter test                          -> All tests passed (26)
flutter build apk --release           -> √ Built app-release.apk (51.3MB)
```

### 真实后端契约验证

启动 Spring Boot 后跑通 `创建 → 调整 → 依据 → 撤销`，逐字段核对了客户端读取的 JSON：

```text
create  201  anonToken=true  keys=corridor,dataStatus,days,id,intensity,perPersonCost,summary,title,totalCost,warnings
adjust  200  keys=changes,plan,version        changes=3 版本号自增到 2
trace   200  keys=dataStatus,engine,promptVersion,toolInvocations,toolMockCount,tripId,warnings
             engine=mock-trip-factory toolMockCount=5 tools=5（全部为演示工具）
undo    200  回到 days=2 totalCost=385 的原始版本
```

行程列表与今日行程同样逐字段核对：

```text
list   200  count=1  keys=corridor,dataStatus,daysCount,id,intensity,perPersonCost,summary,title,totalCost,updatedAt
today  200  keys=arrival,date,nextStop,remainingItems,status,tripId,weather
            nextStop=龙门石窟 arrival=09:00 remaining=3
无令牌访问 list -> 401（客户端必须携带匿名令牌，由 SessionInterceptor 负责）
```

账号阶段的端到端核对（`注册 → 匿名合并 → 分享 → 收藏 → 撤销`）：

```text
1 anonymous plan   201 anonToken=true
2 register         201 user=tester53798797 verified=false
3 merge anonymous  200 {"merged":true,...}
  不带匿名请求头   400 ANONYMOUS_SESSION_REQUIRED   ← 客户端必须显式带该头
4 account trips    200 count=1 first=merged plan     ← 合并确实转移了归属
5 create share     200 keys=expiresAt,hideBudget,id,token,url hideBudget=true
6 view (no auth)   200 keys=hideBudget,plan totalCost=0   ← 预算已隐藏
7 add/list/remove favourite  201 / 200 / 204
8 revoke share     204 then view -> 404 SHARE_NOT_FOUND
9 share as anon    401                               ← 服务端强制要求真实账号
```

验证过程中发现并修正了一处真实偏差：服务端 `perPersonCost` 采用整数截断（385/2 = 192），
客户端原先用 `round()` 会算出 193。现在客户端优先采用服务端数值，本地计算只作为演示方案的兜底。

### 本次遗留

1. Release 包未传 `--dart-define=API_BASE_URL=...` 时不再回退到明文 HTTP，而是报告"未配置服务器地址"并展示本地演示内容。
2. 刷新令牌的单飞逻辑已实现，但缺少端到端运行验证，需要登录界面就绪后配合真实后端确认。
3. 页面仍在 `lib/screens/`，`features/` 目录迁移留到接通更多接口时一并做；Token 替换已在 T4.3 完成。
4. 布局回归测试只覆盖静态布局（无键盘、无系统字体放大、无断网）。这三类状态需要真机或模拟器截图补充。
5. **分享链接目前打不开。** `GET /share/{token}` 落进 Spring Security 的
   `anyRequest().authenticated()`，实测返回 **401**；只有公开 JSON 接口
   `GET /api/trip-shares/{token}` 可用。要让收到链接的人真正看到行程，需要服务端提供一个公开的
   分享查看页，或由 APK 做深链接管。这是本阶段唯一未闭合的用户可见缺口。

## 1. 本阶段目标

### 用户侧目标

游客在 360–412dp 手机上可以：

1. 不登录浏览首页、走廊、景区详情；
2. 输入一句自然语言需求并生成一次匿名方案；
3. 看懂方案是实时、缓存、系统资料还是演示数据；
4. 网络失败时保留输入并能查看最近成功方案；
5. 使用 Android 返回键、键盘、系统字体放大和权限拒绝，不被卡死；
6. 不依赖地图或定位也能完成比赛主流程。

### 工程侧目标

1. 统一 API 错误、数据状态和环境配置；
2. 匿名令牌安全存储，应用重启后仍能继续当前匿名会话；
3. 将页面数据访问从 Widget 中抽离到 Repository/Provider；
4. 为 360dp、390dp、412dp 建立可重复的布局验收；
5. 形成清晰的目录边界，为真实地图/天气适配预留 Port/Adapter。

## 2. 不纳入本阶段

- 在线购票、支付、酒店预订；
- 完整实时导航和后台持续定位；
- 多人协同编辑；
- 全省景区内容扩展；
- 真实 12306 抓取；
- 强制 SMTP 验证；
- 先做复杂地图 UI 再补网络基础设施；
- 为了目录“好看”而一次性搬迁所有 Java/Dart 文件。

## 3. 任务分解与验收证据

### T4.1 冻结跨端数据契约

**内容：**

- 固定 `dataStatus` 枚举语义：`REALTIME`、`CACHED`、`SYSTEM`、`MOCK`、`EXPIRED`、`UNAVAILABLE`；
- 固定错误结构：`code`、`message`、`timestamp`、可选 `requestId`；
- 行程节点保留 `source`、`dataStatus`、`risk`、`updatedAt`；
- 客户端模型不能把 `AI 生成` 当作工具数据状态；
- 记录 API 契约变更表。

**验收：**

- Java DTO、Dart model、文档三处含义一致；
- Mock 和真实适配器都能显示同一套状态 Badge；
- 不再用任意中文字符串判断状态。

### T4.2 Flutter 环境与网络层

**文件范围：**`flutter_app/lib/core/`、`flutter_app/lib/data/`、`pubspec.yaml`。

**内容：**

- 建立 `AppConfig`：debug emulator、debug LAN、release HTTPS 三种 API 地址策略；
- Dio 统一连接/读取超时、状态码映射、请求 ID、重试边界；
- 匿名令牌放入 `FlutterSecureStorage`，禁止日志输出；
- 处理 401：刷新令牌或引导登录；匿名令牌失效时创建新会话并提示；
- `TravelRepository` 保留 Mock datasource，网络失败不静默吞掉；
- UI 显示 `在线 / 网络较弱 / 使用缓存 / 演示数据 / 数据已过期`。

**验收：**

- 杀进程重启后匿名规划仍能识别会话；
- 断网时首页和最近行程可查看；
- 规划失败时输入不丢失，错误附近有重试；
- Release 不再默认使用 HTTP 地址。

### T4.3 移动端 Token 与设计系统

**文件范围：**`flutter_app/lib/core/theme/`、`core/widgets/`、`app.dart`。

**内容：**

- 将颜色、间距、字体、圆角、触控尺寸集中成 token；
- 统一主按钮、次按钮、状态标签、异步状态、空态、错误态；
- 清理不存在的 `'sans'` 字体族，使用可用 fallback 或正式资产；
- 所有图标操作提供 tooltip/semantics；
- 不让颜色成为唯一的状态表达。

**验收：**

- 页面不再散落品牌色和关键尺寸；
- 360dp 下主操作仍达到 48dp 命中区；
- 系统字体 1.3 倍不出现 Overflow。

### T4.4 390dp 主稿与 360/412dp 响应式适配

**文件范围：**当前 `screens/`，逐页迁移到 `features/` 可后置。

**内容：**

- 首页、规划、详情、行程、今日行程按 `MOBILE_LAYOUT_SPEC.md` 调整；
- 移除会造成横向溢出的固定宽度/固定高度；
- 目的地 Chips 使用 Wrap；长标题、预算、来源和风险允许换行；
- 键盘打开时主按钮可见；
- 把 `IntrinsicHeight`、过度嵌套滚动和长单行 Row 作为重点审查对象；
- 每个网络图片设定比例和错误占位。

**验收：**

- 360×800dp、390×844dp、412×915dp portrait 均无 overflow；
- 生成、详情、行程三条主流程各保存截图；
- 记录字体 1.0x / 1.3x、在线 / 断网结果。

### T4.5 接通阶段二已有接口

**接口优先级：**

1. `GET /api/home`、`GET /api/pois`、`GET /api/pois/{id}`；
2. `POST /api/anonymous/session`；
3. `POST /api/trip-plans/preview`；
4. `POST /api/trip-plans`；
5. `GET /api/trip-plans`、`GET /api/trip-plans/{id}`；
6. `POST /api/trip-plans/{id}/adjust`、`POST /api/trip-plans/{id}/undo`；
7. `GET /api/trip-plans/{id}/today`、`GET /api/trip-plans/{id}/trace`；
8. 登录、刷新、合并、收藏、分享。

**验收：**

- 客户端产生的方案与服务端 id、状态、风险一致；
- 调整前后变化有结构化展示；
- 撤销能够恢复服务端版本；
- 分享只读且预算隐藏选项有明确反馈；
- Mock fallback 必须在 UI 中标识。

### T4.6 基础移动测试矩阵

| 类别 | 场景 | 通过条件 |
| --- | --- | --- |
| 尺寸 | 360/390/412dp | 无横向 overflow，文字不裁切 |
| 输入 | 键盘弹出、长需求、空需求 | 输入保留，错误靠近输入，按钮可见 |
| 网络 | 在线、断网、超时、恢复 | 有状态提示，可重试，不重复保存 |
| 会话 | 匿名、重启、登录合并、过期 | 不泄漏令牌，归属正确 |
| 权限 | 定位允许、拒绝、稍后再说 | 拒绝后可手动输入城市 |
| 返回 | 详情返回、生成中返回、分享取消 | 不丢输入，不出现空白页 |
| 字体 | 系统字体 1.0x / 1.3x | 主流程仍可用 |
| 图片 | 慢网、失败、无网络 | 固定占位、文字信息仍可读 |
| 数据 | 实时、缓存、Mock、过期 | 状态文字和图标一致 |

## 4. 推荐提交顺序

### Commit 1：规范与契约

- `PHASE_AUDIT.md`
- `PROJECT_STRUCTURE.md`
- `MOBILE_LAYOUT_SPEC.md`
- `NEXT_STAGE_PLAN.md`
- 状态枚举与接口错误说明

### Commit 2：客户端核心基础设施

- `core/config`
- `core/network`
- `core/storage`
- `data/models`
- Secure Storage 与 Dio 拦截器

### Commit 3：390dp 主视觉与响应式

- 首页、规划、景区详情、行程、今日页
- 状态、错误、空态、加载态
- 360/412 补偿规则

### Commit 4：客户端接通现有后端

- 匿名规划、列表、详情、调整、撤销、分享
- trace 数据依据展示
- 断网缓存与明确降级

### Commit 5：设备矩阵与演示包

- 设备截图、录屏和缺陷清单
- Debug APK、Release APK
- 比赛在线模式 / 稳定 Mock 模式说明

## 5. 阶段完成定义（Definition of Done）

只有同时满足以下条件，才宣布阶段四完成：

- `flutter analyze` 通过；
- APK Release 可构建；
- 360dp/390dp/412dp 三档 portrait 无布局溢出；
- 断网不白屏，用户输入和最近行程不丢；
- 匿名令牌不以明文写入日志或普通缓存；
- 客户端显示数据状态，不把 Mock 冒充实时；
- 至少完成匿名规划、查看结果、调整、撤销、查看依据四条端到端路径；
- 形成截图、设备矩阵和问题清单；
- README 和交付说明能准确区分“已完成、Mock、待接入”。

## 6. 下一阶段之后

阶段四完成后再进入：

1. 阶段五：真实外部服务适配（百度地图/天气/授权交通）与缓存 TTL；
2. 阶段六：管理台真实内容管理、AI 运行统计和错误趋势；
3. 阶段七：地图独立验证、真机安装、签名和比赛交付测试。

## 7. 后续阶段的硬性约束

### 7.1 LLM 多供应商（已完成）

进入 LLM Provider 阶段时，**不能只接一家**。至少同时支持：

- OpenAI
- DeepSeek
- Kimi（Moonshot）
- 通义千问 Qwen

实现要求：

- 统一 provider 抽象，业务层只依赖 `PlanningEngine`，不感知具体厂商；
- 通过环境变量或数据库配置选择 provider、模型名、base url、超时与温度；
- 每个 provider 独立记录可用性、耗时、失败率，失败可按优先级降级到下一个；
- 密钥只存在于服务端环境变量，客户端与管理台都不得持有；
- 管理台需要能看到"当前生效 provider / 各 provider 健康度 / 最近切换原因"；
- 提示词与解析层保持厂商无关，禁止在业务代码里出现厂商专有字段。

**落地方式**

| 要求 | 实现 |
| --- | --- |
| 统一抽象 | `LlmProvider` 记录 + 一个 `LangChain4jPlanningEngine` 服务四家，差异全在配置 |
| 配置驱动 | `app.llm.providers.*`，每家一组 `*_ENABLED / _API_KEY / _MODEL / _BASE_URL / _PRIORITY` |
| 优先级降级 | `PlanningEngineRegistry` 按 `priority` 排序，`TravelPlanningFacade` 逐家尝试，Mock 永远最后 |
| 独立健康度 | `ProviderHealth` 记录每家成功/失败次数、最近耗时、最近错误 |
| 运营可见 | `GET /api/admin/llm/providers`（`ADMIN` 角色），响应不含密钥 |
| 厂商无关 | `PlanningPromptFactory` / `LlmPlanParser` 完全不感知供应商 |

同时删掉了与 LangChain4j 重复的手写 `OpenAiCompatiblePlanningEngine`：四家都是 OpenAI 兼容
接口，两条等价的传输路径只会让失败面翻倍。旧变量 `LLM_BASE_URL / LLM_API_KEY / LLM_MODEL /
LLM_CHAT_PATH` 已废弃。

**运行时验证**（两家供应商故意指向不可达端口，验证降级与运营可见性）

```text
1 anonymous plan   201 dataStatus=演示数据（AI 降级）
  warnings         AI 规划服务暂时不可用，已自动使用稳定演示方案。
2 operator login   200 roles=["ADMIN","USER"]
3 vendor report    200
  selectionOrder   ["openai","deepseek"]
  vendor openai    enabled=true configured=true priority=10 model=gpt-4o-mini
  vendor deepseek  enabled=true configured=true priority=20 model=deepseek-chat
  vendor kimi      enabled=false configured=false priority=30 model=moonshot-v1-8k
  vendor qwen      enabled=false configured=false priority=40 model=qwen-plus
  attempt deepseek ok=0 fail=1 error=java.net.ConnectException…
  attempt openai   ok=0 fail=1 error=java.net.ConnectException…
4 leaks key?       false
5 access control   no token -> 401   normal user -> 403
```

后端新增 9 项单元测试（`PlanningEngineRegistryTest` / `TravelPlanningFacadeTest`），
覆盖“未配置的供应商被跳过”“按优先级排序且 Mock 最后”“失败逐级降级”“全部失败仍产出可用方案”
“参数继承与覆盖”。

运行期还抓到两个只有真正启动才会暴露的问题，已修复：

1. 类里存在多个构造器时，Spring 不再按“唯一构造器”推断，直接报 `No default constructor found`
   —— 已给目标构造器加 `@Autowired`，测试接缝改为静态工厂；
2. 旧的 `OpenAiCompatiblePlanningEngine` 与 LangChain4j 使用不同的 `chat-path` 约定，
   同一份配置会让两条路径请求不同 URL —— 已通过删除重复路径并统一 `base-url` 含版本段解决。
