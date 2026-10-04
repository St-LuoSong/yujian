# Third-party notices

本文件记录实际引入的第三方依赖、许可证与当前使用状态。状态列区分“已在代码中调用”和“已声明但尚未接入”，
避免在答辩或交付材料里把未使用的库算作技术路线。

## Flutter 客户端（APK）

| 依赖 | 许可证 | 用途 | 状态 |
|---|---|---|---|
| flutter_riverpod | MIT | 状态管理与依赖注入 | 已使用（8 个文件） |
| dio | MIT | HTTP 客户端与拦截器 | 已使用（网络层 7 个文件） |
| flutter_secure_storage | BSD-3-Clause | 访问令牌安全存储 | 已使用（`core/storage/session_store.dart`） |
| path_provider | BSD-3-Clause | 本地缓存目录 | 已使用（`core/storage/local_cache.dart`） |
| share_plus | BSD-3-Clause | 系统分享行程链接 | 已使用（`screens/trip_screen.dart`） |
| cached_network_image | MIT | 图片磁盘缓存与加载占位 | 已使用（`core/widgets/photo_plate.dart`） |
| geolocator | MIT | 系统定位权限与当前位置（「附近的景点」） | 已使用（`core/location/location_service.dart`） |
| image_picker | BSD-3-Clause | 从系统相册选择旅记图片 | 已使用（`screens/community_publish_screen.dart`） |

### 已移除的 Flutter 依赖

以下依赖曾声明但**在代码中没有任何调用点**，已从 `pubspec.yaml` 移除。
"声明了却没用"会让技术路线的描述失实，也会让依赖审计失去意义，因此不做长期保留。

| 依赖 | 移除原因 |
| --- | --- |
| go_router | 单栈导航，未使用深链接，实际使用 `Navigator` |
| fl_chart | 预算改用自研比例条，无调用点 |
| timeline_tile | 时间轴改为自绘 `_StopRail`（避开 `IntrinsicHeight` 的长列表性能问题） |
| cupertino_icons | 模板残留，未使用任何 Cupertino 图标 |

### Android 权限清单（证书/隐私声明用）

release 包声明**三个权限**：`android.permission.INTERNET`、
`android.permission.ACCESS_COARSE_LOCATION`、`android.permission.ACCESS_FINE_LOCATION`。

两个定位权限**只服务于「附近的景点」这一个功能**，并且权限与调用代码是**同一轮**出现的：

- `core/location/location_service.dart` 是唯一读取位置的地方，只在用户主动点「在我附近」后才申请；
- 粗、精两项都声明：Android 12+ 用户可以在系统弹窗里只给「大致位置」，
  3 公里半径的判断有粗略权限就够用，精确权限不是硬门槛；
- 拒绝授权不会让应用变残：附近页退回「按城市浏览」，手动选城市同样能看景点；
- 位置只用于当次 `/api/pois/nearby` 请求，**服务端不保存查询坐标**，客户端也不缓存坐标，
  因此没有位置历史。

历史上（阶段十前后）清单里曾有过定位权限而代码里没有定位调用，
那次的处理是「权限与代码一起删」。这一轮反过来：**权限与代码一起加**，
规则始终是「申请的权限必须在代码里有真实、唯一、可解释的用途」。

## Vue 3 管理台

| 依赖 | 许可证 | 用途 | 状态 |
|---|---|---|---|
| Vue 3 | MIT | 视图层 | 已使用 |
| Vue Router | MIT | 管理台路由与登录守卫 | 已使用 |
| Pinia | MIT | 管理员会话状态 | 已使用 |
| ECharts | Apache-2.0 | 运营趋势图（按需注册 LineChart） | 已使用 |
| Vite | MIT | 开发与构建 | 已使用 |
| TypeScript | Apache-2.0 | 类型检查 | 已使用 |

界面样式为项目自研（`styles/tokens.css` 与 `styles/admin.css`），未引入任何 UI 组件库，
以避免默认组件库外观与品牌设计冲突。

## Spring Boot 服务端

| 依赖 | 许可证 | 用途 |
|---|---|---|
| Spring Boot | Apache-2.0 | 服务端基础框架 |
| Spring Security | Apache-2.0 | 认证、授权与过滤器链 |
| Spring Data JPA | Apache-2.0 | 领域模型持久化 |
| JJWT | Apache-2.0 | JWT 签发与校验 |
| LangChain4j | Apache-2.0 | LLM 供应商适配（OpenAI / DeepSeek / Kimi / Qwen） |
| MySQL Connector/J | GPL-2.0 with FOSS exception | MySQL 8 驱动，按官方例外合规使用 |
| H2 Database | MPL-2.0 or EPL-1.0 | 本地开发与演示数据库 |
| Lombok | MIT | 减少实体样板代码 |

## 未直接复制的参考项目

GPL 或许可证不明确的旅行项目仅用于交互与数据建模研究，不复制源码、图片、字体或品牌资源。

MySQL Connector/J 的使用遵循其 FOSS License Exception：本项目以开源/竞赛演示方式使用，不修改驱动，
并在交付材料中保留许可证说明。

## 外部服务与数据源

APK 与这三个服务之间**没有直连**，全部经后端统一端口；密钥与地址只存在于服务端。

| 服务 | 许可证 / 条款 | 用途 | 状态 |
| --- | --- | --- | --- |
| [mcp-server-12306](https://github.com/drfccv/mcp-server-12306) | MIT | 12306 官方车次与余票（MCP 独立进程，`docker run` 或 compose `railway` profile） | 已接入，实测通过（21 项） |
| 百度地图 Web 服务 | 百度开放平台服务条款，AK 申请使用 | POI 检索、路线距离与耗时 | 已接入，AK 只在服务端 |
| Open-Meteo | CC-BY-4.0 / 免费非商业条款 | 天气与预报 | 已接入，无需密钥 |

该项目不抓取 12306 网页、不发验证码、不保存证件与支付信息、不在平台内代购；
余票信息只作为查询参考，界面不承诺"一定能买到"。

## 素材授权状态

- 景点图片当前为 Unsplash 示例素材，服务端在 `image_credit` 字段标记为“交付前需替换为河南实拍授权图”。
- 管理台支持逐条维护图片版权与数据来源链接，交付前必须完成替换并逐条核验。
