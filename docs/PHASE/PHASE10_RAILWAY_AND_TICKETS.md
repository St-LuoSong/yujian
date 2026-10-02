# 阶段十：跨城交通真实化、地图 AK 生效与门票比价评估

> 目标：把"跨城怎么走"从参考时刻表换成官方车次与余票，
> 把已经申请到的百度地图 AK 真正接上，并把门票比价这件事查清楚——
> 能接就接，接不上就如实留下端口，不编造数据源。
>
> 本阶段的硬纪律仍然是那一条：**取到什么就标什么，取不到必须带原因降级**。

## 1. 四个外部数据源的职责分层

用户明确提出"不要都堆到前端"，本轮把职责固定成下面这张表。
分层的判据是**数据实时性与失败形态**，而不是接口好不好接。

| 工具 | 核心能力 | 实时性 | 在本项目里负责什么 | 失败时怎么办 |
| --- | --- | --- | --- | --- |
| 12306（mcp-server-12306） | 车次、余票、票价、经停、中转 | 实时（官方接口） | **跨城交通方案**：郑州到洛阳坐哪趟、有没有票、多久、多少钱 | 带 `RAILWAY_DEGRADED` 降级为明确标注"非实时"的参考时刻表 |
| 百度地图 Web 服务 | POI 检索、路线规划、距离/耗时、逆地理编码 | 准实时（含路况） | **市内交通方案**：车站到景点、景点到景点怎么走 | 带 `BAIDU_NOT_CONFIGURED` / `BAIDU_*` 降级为演示路线 |
| Open-Meteo | 温度、降水、风速、预报 | 实时 + 预报 | **出行可行性判断**：那天下雨吗、适不适合爬山 | 带 `WEATHER_*` 降级为演示天气 |
| 门票价格（候选） | 门票比价 | 视数据源而定 | 只作为行程预算的补充参考 | 回落景区内容库参考价，并标注"系统资料" |

### 1.1 APK 前端为什么一个都不直接调

- 12306 有反爬与频率限制，直连等于把失败面交给客户端；
- 百度地图 AK 放在 APK 里等于公开泄漏，且无法按调用量限额；
- Open-Meteo 虽然免费且无需密钥，统一走后端才能共享缓存与统计口径；
- 三个来源的降级口径必须一致，前端各自实现必然出现"同一个方案三种说法"。

因此 APK 只认自己后端的统一契约。**这部分有自动化断言**（见第 5 节）。

## 2. 12306 MCP 接入

### 2.1 选型

采用 [drfccv/mcp-server-12306](https://github.com/drfccv/mcp-server-12306) 提供的官方镜像
`drfccv/mcp-server-12306:latest`，独立进程部署，**不抓取 12306 网页**，
不发验证码、不保存证件信息、不在平台内购票。

两种启动方式等价：

```cmd
rem 方式一：本地单容器（当前开发机的实际用法）
docker run -d --name yujian-mcp-12306 -p 8000:8000 drfccv/mcp-server-12306:latest

rem 方式二：compose 的 railway profile
docker compose --profile railway up -d mcp-12306
```

### 2.2 协议事实（实测，非推测）

Streamable HTTP，入口 `POST http://localhost:8000/mcp`，响应是 SSE：

```text
event: message
data: {"jsonrpc":"2.0","id":1,"result":{...}}
```

握手必须三步：

1. `initialize` → 200，服务端下发 `Mcp-Session-Id`；
2. `notifications/initialized` → **202**（不是 200）；
3. `tools/call`，并带上会话头。

三个只有真接上才会知道的事实，都已在代码里处理：

| 事实 | 处理方式 |
| --- | --- |
| 缺少 `Mcp-Session-Id` 时服务端返回 **400**（协议替身 mock 返回 404） | `RailwayMcpClient.isSessionFailure()` 同时接受 4xx 中的会话失效场景，收到后自动重新握手并重试一次 |
| `notifications/initialized` 返回 202 | 不把 202 当成失败 |
| 工具名是连字符风格，不是驼峰 | 直接使用 `query-tickets` 等原始工具名 |

可用工具：

```text
query-tickets                 车次与余票
query-ticket-price            票价
search-stations               车站检索
query-transfer                中转方案
get-train-route-stations      经停站
get-train-no-by-train-code    按车次编码查车次号
get-current-time              服务端当前时间
```

`query-tickets` 参数：`from_station` / `to_station` / `train_date`（`YYYY-MM-DD`）。

### 2.3 实测证据

```text
GET  http://localhost:8000/health
     -> {"status":"healthy","stations":3404,"active_sessions":N}

tools/call query-tickets  郑州 -> 洛阳  2026-10-03
     -> trains=165
     -> Z293 郑州 → 洛阳 00:34-01:59; Z273 郑州 → 洛阳 01:00-02:26; ...
```

后端规划链路里，车次调用被如实标注为实时数据：

```text
status = 实时数据
source = 12306 MCP（官方车次与余票）
error  = null
```

## 3. 百度地图 AK：从"已配置"到"真生效"

用户反馈 AK 已经申请好，但联调时路线仍然是演示数据。排查结果是**配置位置错了**，
而不是 AK 无效：

| 现象 | 结论 |
| --- | --- |
| `scripts/local.env` 里 `BAIDU_MAP_AK` 为空 | 启动脚本加载的是这个文件，所以后端确实没拿到 AK |
| AK 实际写在 `.env.example` 第 26 行 | 这是**随仓库分发的模板文件**（`.gitignore` 里 `!.env.example` 显式放行），既不生效，还会把密钥提交出去 |

处置：

1. 把 AK 迁到 `scripts/local.env`（git-ignored，启动脚本会加载）；
2. `.env.example` 恢复成空占位，避免模板继续携带真实密钥；
3. 重启后端，确认启动行变成 `[dev-server] baidu map ak: configured`。

AK 有效性用一次独立请求验证（不经过本项目）：

```text
GET https://api.map.baidu.com/place/v2/search?query=龙门石窟&region=洛阳市&output=json&ak=***
-> status=0 message=ok
-> 龙门石窟  lat=34.555862 lng=112.485337  河南省洛阳市洛龙区龙门中街13号
```

生效后同一条规划链路里的路线调用：

```text
修复前  status = 演示数据（降级）  source = 路线演示数据        error = BAIDU_NOT_CONFIGURED
修复后  status = 实时数据          source = 百度地图 Web 服务   error = null
```

### 3.1 顺带修掉的一个前端缺陷

AK 生效后立刻暴露了配图问题：运营台在**桌面浏览器**上传的景区图片，
后端按"上传者所在的主机"推导出 `http://localhost:8080/media/...`。
这个地址在浏览器里是对的，在 Android 模拟器里 `localhost` 指向模拟器自身，
图片必然加载失败。

处理方式不是让运营同学再维护一份 base url，而是在客户端唯一入口重写：

- `AppConfig.resolveMediaUrl()`：回环主机（`localhost` / `127.0.0.1` / `0.0.0.0` / `::1`）
  换成客户端已经在用的 API 主机；相对路径与协议相对地址同样拼接；
  其它绝对地址（例如内置图库的外链）原样返回；没有配置 endpoint 时不做任何改写。
- 接入点是 `TravelRepository._reachablePhoto()`，也就是**所有景点都必经的那一处**：
  发现页宫格、景点详情头图、行程日卡封面共用同一个模型。

这样一份数据同时满足两个消费者：浏览器预览仍然走 `localhost`，手机走 API 主机。

## 4. 门票比价：`@travel-skills/attraction-smart-buy`

用户提到有"直连即用、无需 API Key"的门票比价工具，希望接入作为票务数据。

核查结论：**该工具在公开渠道不存在，本轮不接入。** 依据：

| 核查动作 | 结果 |
| --- | --- |
| npm registry 查询 `@travel-skills/attraction-smart-buy` | 404，包不存在 |
| GitHub 搜索同名/相似项目 | 0 个可用结果 |
| 项目内既有依赖 | 无任何相关声明 |

在找不到真实数据源的前提下，只有两种做法是诚实的：

1. 直接把"比价"写进页面 —— 那就是编数据，违反本项目贯穿始终的口径；
2. 留出端口，接不上时如实回落并说明原因 —— 本轮采用这一条。

因此保留 `TicketPricePort` 端口与 `TICKET_PROVIDER=smart-buy` 取值：

```text
TICKET_PROVIDER=catalog     景区内容库参考价（当前生效），标注为"系统资料"
TICKET_PROVIDER=smart-buy   预留；没有适配器时带原因降级为内容库价
```

**如果后续拿到真实可用的比价服务**，只需要新增一个 `TicketPricePort` 实现，
前端契约与行程预算逻辑都不用改，唯一变化的是 `ToolResult` 里的 `source` 与 `dataStatus`。

## 5. 验证证据

全部命令都在本机实跑，结果如实记录。

### 5.1 12306 端到端：`node scripts\verify-railway-mcp.mjs`

```text
通过 21 项，失败 0 项
  MCP 服务 /health 可读
  initialize 成功 / 下发会话头 / 缺会话头被拒（400）
  tools/call 以 SSE 返回且能解析
  车次内容可解析 -> trains=165
  后端到 MCP 的端到端链路：车次标注为实时数据
  分层边界：轨迹与行程响应都不含 MCP 地址、不含 12306 会话头
  数据源健康度：provider=12306-mcp
```

### 5.2 工具层全量：`node scripts\verify-tools.mjs`

```text
通过 37 项，失败 0 项
  轨迹记录 6 项工具调用：searchPoi / getWeather / getRoute / searchTrain /
                          checkAttractionOpening / quoteTicketPrices
  车次 -> status=实时数据   source=12306 MCP（官方车次与余票）  error=null
  天气 -> status=实时数据   source=Open-Meteo 实时天气        error=null
  路线 -> status=实时数据   source=百度地图 Web 服务          error=null
  不变量：标为实时的调用都没有 errorCode            live=3 degraded=0
  不变量：轨迹里没有出现百度 AK / 没有完整外网请求地址
  健康度：weather=ready route=ready railway=ready ticket=ready
  健康度不含任何密钥内容
```

修复前同一条脚本的数字是 `route=not-configured`、`live=0 degraded=1`，
两次结果对照即为 AK 生效的直接证据。

### 5.3 后端回归：`mvn -o -B test`

```text
Tests run: 9, Failures: 0, Errors: 0
BUILD SUCCESS
```

### 5.4 本轮脚本自身修掉的两个缺陷

验证脚本失败本身也是缺陷，一并记录：

1. `verify-railway-mcp.mjs` 里 `const call = ...` 遮蔽了同名的 HTTP helper，
   导致调用直接抛错 —— 改名为 `ticketCall`；
2. 查询日期写死成 `2099-01-01`，落在预售窗口之外必然查不到车次 ——
   改成"今天 + 2 天"，并对缺会话断言从 `=== 404` 放宽为 `4xx`，
   因为官方镜像返回的是 400。

## 6. 环境变量

```text
# 跨城车次
RAILWAY_PROVIDER=12306-mcp        reference | 12306-mcp
RAILWAY_MCP_URL=http://localhost:8000/mcp
RAILWAY_CACHE_MINUTES=30          余票变化快，实时车次必须短缓存

# 市内路线（密钥只在服务端）
BAIDU_MAP_AK=<在 scripts\local.env 里填写，不要写进 .env.example>
BAIDU_MAP_BASE_URL=https://api.map.baidu.com

# 天气
WEATHER_PROVIDER=open-meteo

# 门票
TICKET_PROVIDER=catalog           catalog | smart-buy（预留）
TICKET_BASE_URL=
```

配置读取顺序：`scripts\local.env`（只应用非空值，已被 .gitignore 忽略）
→ 系统环境变量。留空的键会退回系统环境变量，不会被空值覆盖。

## 7. 安全与合规边界

- 12306 只作为**查询参考**：不抓网页、不发验证码、不保存证件与支付信息、不代购；
- 余票信息只陈述查询结果，界面不承诺"一定能买到"；
- 百度 AK、MCP 地址只存在于服务端，APK 与管理台都不持有；
- 规划轨迹（`/api/trip-plans/{id}/trace`）与健康度接口都不含密钥、不含完整外网请求地址；
- 运营台图片上传的地址重写在客户端完成，不引入第二份密钥或第二个 base url。

## 8. 遗留

- 门票比价仍无真实数据源，`smart-buy` 只是端口预留；
- 12306 的席别与票价已拆成独立工具 `quoteRailFares`，进入工具轨迹、提示词与预算下限校验；
  票价仍不能替代官方购票页，最终支付金额以 12306 为准；
- 百度地图在 APK 内的**地图 Tab**（可视化路线）仍未接入，属于独立 SDK 验证任务；
- 跨城车次已覆盖"直达 + 一次中转换乘"：`searchTrain` 查直达，`searchTransfer` 在同日期同区间查中转；
  直达不是强制，最终是否换乘由用户在官方渠道决定。
