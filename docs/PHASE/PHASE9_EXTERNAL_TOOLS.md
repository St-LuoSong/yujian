# 阶段九：真实外部服务适配与降级口径

> 目标：把"外部数据全是 Mock"的占位链路换成"能取真实数据就取真实数据，
> 取不到必须带原因降级，并且用户、运营台、工具轨迹三处口径完全一致"。
>
> 本阶段先做**工具层与数据真实性**；APK 地图 Tab、定位与附近景点属于下一段，
> 因为它们需要独立的 SDK 验证，不适合和工具层改造一起上线。

## 1. 为什么先做这一层

比赛最容易被追问的一句话是：

> "你这个行程里的天气、路线和车次，是真的还是编的？"

阶段七之前，服务端所有外部数据都来自 `MockTravelTools`，前端只能在页面上写
"演示数据"四个字。这一段的全部目的，就是让这句话有可验证的答案：

| 数据 | 之前的来源 | 现在的来源 |
| --- | --- | --- |
| 景点检索 | 内置 Mock 列表 | 运营台维护的内容库（`poi` 表） |
| 景区开放时间 | 内置 Mock 列表 | 系统整理的公开资料 |
| 天气 | 内置 Mock | **Open-Meteo 实时预报**（免费、无需密钥） |
| 城际路线 | 内置 Mock | 百度地图 Web 服务（配置 AK 后启用） |
| 铁路车次 | 内置 Mock | 参考时刻表，明确标注“非实时”；接上 12306 MCP 后为官方实时车次（见阶段十） |

没有配置百度 AK 时**不会发网络请求**，直接返回带 `BAIDU_NOT_CONFIGURED` 的降级结果。
这样现场演示既不会因为没配 AK 卡住，也不会把演示路线说成实时路况。

> 阶段十补充（2026-10-01）：百度 AK 已配置并实测生效，路线状态从
> “演示数据（降级）/ BAIDU_NOT_CONFIGURED”变为“实时数据 / 百度地图 Web 服务”；
> 跨城车次已接入 12306 MCP。细节与证据见 `docs/PHASE10_RAILWAY_AND_TICKETS.md`。

## 2. 代码结构

```text
tools/
  TravelToolPort.java        工具端口：业务层只依赖它
  ToolResult.java            统一结果：data / source / 实时 / 缓存 / 演示 / 降级原因
  ToolModels.java            天气、路线、车次、开放时间
  ToolCollection.java        一次规划的汇总 + 来源计数
  ToolOrchestrator.java      编排、如实记录、如实提示
  CatalogTravelTools.java    系统自有资料（景点库、开放时间）
  MockTravelTools.java       兜底演示数据（只在降级时使用）

infrastructure/external/
  HttpJsonClient.java        JDK HttpClient + Jackson，无新增依赖
  TtlCache.java              TTL 缓存 + 失败短路
  ExternalServiceException.java  带错误码，消息不含完整 URL（AK 在 query 里）
  CompositeTravelTools.java  端口总入口：真实 → 缓存 → 降级
  weather/OpenMeteoWeatherClient.java
  baidu/BaiduMapClient.java
```

### 关键设计

1. **端口而不是具体实现**。`ToolOrchestrator` 只注入 `TravelToolPort`，
   "这一份数据到底从哪来"由端口实现负责，编排层只负责如实记录。
2. **错误码优先于错误消息**。所有失败都带 `errorCode`（`BAIDU_NOT_CONFIGURED`、
   `WEATHER_BACKOFF`、`BAIDU_3`……），消息只做人类可读解释，且不含完整请求地址。
3. **失败短路**。外部服务刚失败过，会在 2 分钟内直接走降级，
   避免每次规划都等一次 4 秒超时——这对比赛现场是能不能讲完的风险。
4. **缓存有 TTL**。天气 30 分钟、路线 24 小时、地理编码进程内常驻。
   第二次规划会如实显示"缓存数据"，而不是继续标"实时数据"。

## 3. 数据状态口径（唯一真源）

| 状态 | 含义 | 出现条件 |
| --- | --- | --- |
| 实时数据 | 本次请求真实调用了外部接口并成功 | 天气、路线的真实返回 |
| 缓存数据 | 命中仍在有效期内的缓存 | TTL 未过期 |
| 系统资料 | 运营台或系统整理的公开资料 | 景点库、开放时间 |
| 演示数据 | 确定性兜底数据，非实时 | Mock 模式、车次参考 |
| 演示数据（降级） | **本该取真实数据，但失败了**，同时带 `errorCode` | 无 AK、超时、配额用尽 |

前端的 `DataStatus.fromServer` 会把服务端字符串归一化成枚举，
所以"演示数据（降级）"在 APK 上显示为红色的降级标记，不会和实时数据混淆。

## 4. 用户可见的三处一致性

1. **行程提示（warnings）**：由工具的实际状态生成，不再写死文案。
   例如"本次方案中路线未取到实时数据，已用演示数据兜底，原因见「依据」页"。
2. **依据页（trace）**：每个工具一行的来源、状态、错误码、耗时、人类可读输出摘要
   （"洛阳 2026-10-01 小雨 14—21℃，降水概率 92%"），下方是来源构成统计。
3. **运营台总览**：工具调用总数、标记为演示、标记为实时、其中降级兜底。

> 输出摘要从 `WeatherInfo[city=...]` 这种 record toString 换成了人类可读的一行：
> 轨迹页是给评委看的，原样打印对象既难读也没有信息量。

## 5. 验证证据

`scripts/verify-tools.mjs`（**28 项通过，0 项失败**）：

```text
== 1. 真实天气数据源可达性 ==
  OK   Open-Meteo 可直接取到未来 3 天预报            status=200
== 3. 一次真实规划的工具轨迹 ==
  OK   景点检索标注为系统资料                        status=系统资料
  OK   开放时间标注为系统资料                        status=系统资料
  OK   车次不冒充实时                                status=演示数据
  OK   天气要么是真实来源、要么带原因降级            status=实时数据 source=Open-Meteo 实时天气
  OK   天气未编造未来日期                            summary=洛阳 2026-10-01 小雨 14—21℃，降水概率 92%
  OK   路线要么是百度地图真实结果、要么带原因降级    status=演示数据（降级）error=BAIDU_NOT_CONFIGURED
== 4. 全量不变量 ==
  OK   标为实时的调用都没有 errorCode                live=1
  OK   带 errorCode 的调用都标注了演示或降级         degraded=1
  OK   轨迹里没有出现百度 AK
  OK   轨迹里没有出现完整外网请求地址
== 6. 缓存与失败短路 ==
  OK   第二次规划的天气命中缓存或短路降级            status=缓存数据
== 7. 运营统计的降级口径 ==
  OK   降级兜底单独计数且不超过演示总数              degraded=2 mock=49
```

后端单元测试 9 项通过（`mvn -o test`），其中 `TravelPlanningFacadeTest` 改用离线端口替身，
不再因为"这台机器有没有网"而变成不确定结果。

## 6. 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `APP_TOOLS_MODE` | `live` | `mock` 表示全部走本地演示数据（无外网演示用） |
| `TOOLS_TIMEOUT_SECONDS` | `4` | 单次外部调用超时 |
| `BAIDU_MAP_AK` | 空 | 留空时路线直接降级，不发请求 |
| `BAIDU_MAP_BASE_URL` | `https://api.map.baidu.com` | 保留代理网关替换空间 |
| `WEATHER_PROVIDER` | `open-meteo` | `none` 表示只用演示数据 |
| `WEATHER_CACHE_MINUTES` | `30` | 天气缓存时长 |
| `RAILWAY_PROVIDER` | `reference` | `reference` 只给参考车次并标注非实时；`12306-mcp` 走官方车次与余票（详见阶段十） |

容器演示同样支持：`docker-compose.yml` 已经把 `APP_TOOLS_MODE`、`BAIDU_MAP_AK`、
`WEATHER_PROVIDER` 与 `MEDIA_BASE_URL` 透传进 server 服务，缺省值与本机开发一致。

验证脚本（先启动后端，再执行）：

```cmd
cd /d D:\DESKTOP\ProWeb
node scripts\verify-tools.mjs
```

### 演示前的两套口径

- **在线模式**：`APP_TOOLS_MODE=live`。天气是真的，路线看有没有配 AK。
- **稳定模式**：`APP_TOOLS_MODE=mock`。全部标注为演示数据，断网也能讲完整流程。

## 7. 明确不做的事

- 不抓取 12306 网页，不保存身份证号与支付信息，不在平台内购票；
- 不把百度 AK 下发到 APK 或管理台；
- 不在没有 AK 时伪造"实时路线"；
- 不因为外部服务不可用就让整个规划失败——降级必须可用，但必须可见。

## 8. 下一步

1. APK 内反馈入口（服务端 `POST /api/feedback` 已就绪，客户端还没有调用点）；
2. APK 地图独立验证（百度地图 SDK 或 WebView，先验证再耦合）；
3. 定位与"附近景点"（`geolocator` 已声明但零调用）；
4. 主题路线（三条走廊）从硬编码迁到运营台维护。

