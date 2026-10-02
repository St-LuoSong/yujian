# 项目目录规划与迁移规则

> 版本：v0.1 / 2026-10-01
> 
> 本文同时记录当前实际目录和下一阶段目标目录。目标不是为了“看起来像大型项目”而拆分，而是让 APK、服务端和管理台的边界清楚，后续真实接口接入时不再把网络、Mock、页面和领域规则混在一起。

## 1. 顶层目录职责

```text
ProWeb/
├── flutter_app/                 # 游客端：Flutter Android APK，唯一主交付形态
├── backend/                     # 后端相关服务集中目录
│   ├── server/                  # Spring Boot API、AI 编排、数据与安全
│   ├── admin/                   # 管理台：Vue 3 + Vite，仅浏览器访问
│   ├── docker-compose.yml       # 后端本地/演示编排
│   └── .env.example             # 后端环境变量模板，不放真实密钥
├── tooling/                     # 本机 SDK 与缓存，忽略，不提交
│   ├── flutter/                 # Flutter SDK
│   ├── android-sdk/             # Android SDK
│   ├── .gradle/                 # 本机 Gradle 缓存
│   ├── .android/                # 本机 Android 用户目录
│   └── .pub-cache/              # 本机 Pub 缓存
├── docs/                        # 产品、架构、审计、测试、交付说明
├── scripts/                     # 可复现的环境、构建、检查脚本
├── README.md                    # 项目入口与快速开始
├── SCHEME.md                    # 产品总计划书
├── THIRD_PARTY_NOTICES.md       # 第三方依赖与许可证清单
└── toolchain.cmd                # 项目内工具链环境入口
```

> 顶层只保留三类内容：交付端（`flutter_app`）、后端服务（`backend`）、
> 本机工具链（`tooling`）。`tooling` 全部在 `.gitignore` 中忽略，不随仓库分发。

### docs 目录索引

| 文档 | 作用 |
| --- | --- |
| `../SCHEME.md` | 产品总计划书 |
| `PROJECT_STATUS.md` | 现在能演示什么、还差什么；T 系列执行记录 |
| `PROJECT_STRUCTURE.md` | 本文件：目录职责与迁移规则 |
| `API.md` | **服务端接口契约**：路径、鉴权矩阵、错误码、数据状态语义、管理端接口 |
| `DEVELOPMENT_ENVIRONMENT.md` | 本机环境、SDK、构建与运行方式 |
| `MOBILE_LAYOUT_SPEC.md` | 移动端布局与分辨率基线 |
| `DESIGN_DIRECTION.md`、`UI_REDESIGN.md` | 视觉方向与改版记录 |
| `PHASE*.md` | 各阶段执行记录与验证证据 |
| `DELIVERY/` | 交付材料：系统说明书、技术架构、测试说明、需求实现对照、配图作业单 |

> `API.md` 是「公开测试」的契约。接口一旦对外可用，**只准追加、不准改语义**。

### 目录边界原则

1. `flutter_app` 不保存服务端密钥、数据库文件或管理台代码。
2. `backend/server` 是唯一持有 LLM、地图、天气、SMTP 等服务端密钥的位置。
3. `backend/admin` 只持有浏览器端 API 地址和管理员会话，不复制游客端业务逻辑。
4. `tooling` 只放 Flutter / Android SDK 与构建缓存，不提交、不作为交付物。
5. `docs` 保存“为什么这样设计”和验收证据；不要把临时日志当正式文档。
6. `build/`、`.dart_tool/`、`node_modules/`、`target/`、本地数据库和缓存只属于本机产物。
7. 第三方资源、图片和字体必须记录来源、许可证、授权状态和替代方案。

## 2. 当前实际结构审计

### 2.1 Flutter APK 当前结构

```text
flutter_app/
├── android/                    # 已补齐的 Flutter Android Gradle 工程
├── lib/
│   ├── app.dart                # MaterialApp 与品牌主题
│   ├── main.dart               # Flutter 入口
│   ├── data/mock_catalog.dart  # 本地演示内容
│   ├── models/travel_models.dart
│   ├── screens/                # 当前页面与页面内组件集中在此
│   └── services/travel_service.dart
├── pubspec.yaml
└── pubspec.lock
```

当前结构可以继续演示，但存在三个问题：

- 页面同时承担路由、状态、布局和数据回退，下一步接入登录/缓存后会快速变重；
- `TravelService` 目前只覆盖景点列表和创建行程，服务端其余接口未形成客户端 API 层；
- 主题常量、通用状态组件、网络错误和数据状态没有独立目录。

**迁移策略：**不要在一次提交中重写整个 Flutter 工程。先完成移动端布局基线，再按 feature 迁移页面；每迁移一个 feature 都保留可构建 APK。

### 2.2 Spring Boot 当前结构

```text
backend/server/src/main/java/com/yujian/travel/
├── api/          # Controller、DTO 与对外契约
├── ai/           # 规划端口、LLM 多供应商、提示词与校验
├── common/       # 通用异常
├── config/       # 配置与安全配置
├── domain/       # JPA 实体
├── infrastructure/external/   # 外部适配器：百度地图、Open-Meteo、HTTP 客户端、TTL 缓存
├── repository/   # JPA Repository
├── security/     # JWT、匿名会话认证、当前用户
├── service/      # 认证、行程、分享、收藏等业务服务
└── tools/        # 工具端口、统一结果、编排与兜底演示数据
```

外部适配器已经按预案落在 `infrastructure/external`：`HttpJsonClient` 负责统一的 JSON 调用与错误码，
`TtlCache` 负责缓存与失败短路，`weather/` 与 `baidu/` 各自封装一家服务。
`tools` 只保留端口（`TravelToolPort`）、统一结果（`ToolResult`）和编排（`ToolOrchestrator`），
不允许出现任何厂商专有的字段或 URL —— 换数据源时只替换 `infrastructure/external` 下的适配器。

### 2.3 Vue 管理台当前结构

```text
admin/
├── src/App.vue                 # 当前包含布局、导航、总览和模块占位
├── src/main.ts
└── src/style.css               # 当前为单文件视觉原型
```

这符合“先验证视觉方向”的原型阶段，但不适合继续堆管理功能。**阶段七已完成工程化拆分**，当前实际结构为：

```text
admin/src/
├── main.ts                  挂载 Pinia + Router
├── App.vue                  只保留 router-view
├── router/index.ts          路由、登录守卫
├── layouts/AdminLayout.vue  侧边导航 + 顶栏
├── views/                   Login / Overview / Pois / ContentOps / AiRuns / PromptVersions / MockData / Feedback / Logs
├── components/              DataState / MetricCard / TrendChart
├── api/                     token / http / endpoints / types
├── stores/session.ts        管理员会话
└── styles/                  tokens.css + admin.css（自研，无 UI 组件库）
```

细节与验证证据见 `docs/PHASE7_ADMIN_CONSOLE.md`。

## 3. Flutter 目标结构（下一阶段开始迁移）

```text
flutter_app/lib/
├── main.dart
├── app.dart
├── app/
│   ├── router.dart              # GoRouter；统一处理返回、深链和分享入口
│   ├── providers.dart           # Riverpod Provider 组合入口
│   └── bootstrap.dart           # 本地存储、网络、错误上报初始化
├── core/
│   ├── config/
│   │   ├── app_config.dart      # API 地址、构建模式、功能开关
│   │   └── build_flavor.dart
│   ├── network/
│   │   ├── api_client.dart      # Dio 实例、超时、重试、错误映射
│   │   ├── auth_interceptor.dart
│   │   └── api_failure.dart
│   ├── storage/
│   │   ├── secure_store.dart    # JWT、匿名令牌；不存普通缓存
│   │   ├── local_cache.dart     # 轻量 JSON/SQLite 缓存边界
│   │   └── server_endpoint_store.dart # 用户选择的 API 地址；不存第三方密钥
│   ├── theme/
│   │   ├── app_theme.dart
│   │   ├── app_colors.dart
│   │   ├── app_spacing.dart
│   │   └── app_typography.dart
│   ├── widgets/
│   │   ├── data_status_badge.dart
│   │   ├── async_state_view.dart
│   │   ├── section_heading.dart
│   │   └── primary_button.dart
│   ├── location/
│   │   └── location_service.dart # 系统开关 / 定位权限判定 + 取一次当前位置；坐标不缓存、不上报
│   ├── formatters/
│   │   └── distance_text.dart    # 距离文案：<1km 报米、整公里不带小数、其余一位小数
│   └── utils/
├── data/
│   ├── models/                  # API DTO / JSON 映射模型
│   ├── datasources/
│   │   ├── remote_api.dart
│   │   ├── local_cache.dart
│   │   └── mock_datasource.dart
│   └── repositories/
│       ├── catalog_repository.dart
│       ├── trip_repository.dart
│       └── auth_repository.dart
├── features/
│   ├── discover/
│   │   ├── presentation/
│   │   └── data/
│   ├── planner/
│   │   ├── presentation/
│   │   └── data/
│   ├── trip/
│   │   ├── presentation/
│   │   └── data/
│   ├── auth/
│   ├── profile/
│   ├── share/
│   └── location/                # 「附近的景点」页面与状态；平台能力在 core/location
└── l10n/                        # 如后续需要多语言再启用
```

> 上面是**目标**结构，不是当前实际布局，避免误读。当前客户端是更扁平的形态：
> `lib/screens/`（页面）、`lib/data/repositories/travel_repository.dart`（唯一仓库）、
> `lib/core/{theme,network,storage,location,formatters,widgets}/`。
> 迁移到 feature-first 属于重构项，不在 T21 范围内；新增的
> `core/location/location_service.dart` 与 `core/formatters/distance_text.dart` 已落在实际结构中。

### Flutter 迁移顺序

1. `core/theme`：先把颜色、字体、间距和触控尺寸集中，页面视觉不变。
2. `core/network` + `core/storage`：接入匿名令牌、错误类型和数据状态。
3. `data/models` + `repositories`：把 `TravelService` 拆为仓库，保留 Mock datasource。
4. `features/discover`：首页、走廊、景点详情。
5. `features/planner`：预览、确认、生成状态。
6. `features/trip`：时间轴、预算、天气、依据、调整和撤销。
7. `features/auth/profile/share`：登录、合并、收藏和分享。
8. `core/location` + `features/nearby`：定位与附近景点（T21 已完成）；权限与调用代码必须同轮出现，
   拒绝授权退回「按城市浏览」，坐标不缓存、不落库。

每一步的完成条件都是：`flutter analyze` 通过、APK 能构建、已有演示路径没有退化。

## 4. Spring Boot 目标结构

```text
backend/server/src/main/java/com/yujian/travel/
├── api/
│   ├── auth/
│   ├── anonymous/
│   ├── catalog/
│   ├── trip/
│   ├── share/
│   ├── feedback/
│   └── admin/
├── application/
│   ├── auth/
│   ├── planning/
│   ├── trip/
│   └── catalog/
├── domain/
│   ├── model/
│   ├── repository/
│   └── service/
├── infrastructure/
│   ├── persistence/
│   ├── security/
│   ├── ai/
│   ├── tools/
│   └── external/
│       ├── baidu/
│       ├── weather/
│       ├── railway/
│       └── smtp/
├── config/
└── common/
```

阶段四前不强制搬迁现有类；只要求新增适配器遵守以下规则：

```text
Controller -> Application Service -> Port(interface) -> Adapter
                                      ├── Mock Adapter
                                      ├── Baidu Adapter
                                      ├── Weather Adapter
                                      └── Railway Adapter
```

LLM 只能消费 `ToolResult`，不能直接读取 SDK、数据库或环境变量。管理员统计只能消费脱敏后的聚合指标。

## 5. Vue 管理台目标结构

```text
admin/src/
├── main.ts
├── App.vue
├── router/
│   └── index.ts
├── layouts/
│   └── AdminLayout.vue
├── views/
│   ├── OverviewView.vue
│   ├── PoisView.vue
│   ├── RoutesView.vue
│   ├── AiRunsView.vue
│   ├── FeedbackView.vue
│   └── LogsView.vue
├── components/
│   ├── DataState.vue
│   ├── MetricCard.vue
│   ├── TrendChart.vue
│   └── SourceBadge.vue
├── api/
│   ├── http.ts
│   ├── catalog.ts
│   ├── ai.ts
│   └── stats.ts
├── stores/
├── types/
├── composables/
└── styles/
    ├── tokens.css
    └── admin.css
```

## 6. 不应进入源码仓库的内容

```text
flutter_app/build/
flutter_app/.dart_tool/
backend/admin/node_modules/
backend/admin/dist/
backend/server/target/
backend/server/data/
tooling/.gradle/
tooling/.android/
tooling/.pub-cache/
tooling/android-sdk/
tooling/flutter/
*.jks
*.keystore
key.properties
真实 .env 文件
```

Release APK 可以作为比赛交付附件单独归档，但不建议提交到源码仓库历史。

## 7. 本阶段不做的目录重构

- 不把三个工程合并成一个 Gradle/Maven/Node workspace。
- 不为了“Clean Architecture”复制大量空接口。
- 不在真实地图服务未验证前创建地图 SDK 专属页面目录。
- 不移动已经通过构建验证的 Android 工程文件，除非先复制模板并重新验证 APK。
- 不把 Mock 数据伪装成 `production` 目录；Mock 必须有明确命名和状态标记。
