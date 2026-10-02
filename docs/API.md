# 豫见智旅 · 服务端接口说明（API）

> 版本：v0.3.0-apis　|　日期：2026-10-02（Asia/Shanghai）
> 基线代码：`backend/server`（Spring Boot / Java 17 / Spring Security + JWT / MySQL 8）
> 面向读者：APK 客户端、Vue 管理台、后续公开测试的接入方

本文档由人工对照源码整理（`Controller`、`SecurityConfig`、`GlobalExceptionHandler`、`ToolResult`），
不是自动生成的 OpenAPI。**所有路径、鉴权要求、字段名以当前源码为准**；
如果文档与代码不一致，那是文档的错，请按代码修文档。

维护约定：**已经对外可用的接口不删、不改语义，只做向后兼容的追加**；
每次改动在文末「§15 变更记录」补一行。

## 0. 怎么用这份文档

| 你想知道 | 去看 |
| --- | --- |
| 这个接口能不能不登录调 | §2.3 免登录清单 |
| 这个数据是真数据还是演示数据 | §4 数据状态语义 |
| 行程主流程怎么接 | §6 行程接口 |
| 管理台怎么接 | §10 管理端接口 |
| 还有哪些接口没做 | §13 未实现与已知缺口 |

---

## 1. 通用约定

### 1.1 服务地址

| 场景 | Base URL |
| --- | --- |
| 本机后端 | `http://localhost:8080` |
| Android 模拟器访问宿主机 | `http://10.0.2.2:8080` |
| 真机（同一局域网） | `http://<开发机局域网IP>:8080` |
| 生产 | `https://<域名>`（**必须 HTTPS**，release APK 已禁明文） |

APK 支持两种地址来源：

1. **编译期**：`--dart-define=API_BASE_URL=...`，优先级最高，设置页会锁定该地址；
2. **运行时**：未使用编译期地址时，可在「我的 → 设置 → 服务器地址」里填写并测试连接，
   地址保存在本机安全存储中，换后端不需要重新打包。

正式交付的 release 包只接受 HTTPS；debug 包可用 `http://10.0.2.2:8080/api`
访问模拟器宿主机。

### 1.2 请求与响应格式

- 除 `GET /share/{token}` 返回 HTML 外，所有接口的请求体/响应体都是 `application/json;charset=UTF-8`；
- 图片上传是 `multipart/form-data`；地图底图返回 `image/png`；
- 字段命名统一 `lowerCamelCase`；
- Jackson 忽略未知字段，客户端多传字段不会报错。

### 1.3 时间、金额与小数

- **时间戳**：ISO-8601 UTC，如 `2026-10-02T06:30:00Z`（Java `Instant`）；
- **日期**：`yyyy-MM-dd`，如 `2026-10-03`。它表示"出发日期"这一业务概念，**不带时区**，不是某一瞬间；
- **金额**：整数，单位人民币元。服务端不返回小数金额；客户端也不要把 `800` 显示成 `800.00`；
- **时长**：`durationMinutes` 为整数分钟，展示层再格式化成"1 小时 20 分"；
- **经纬度**：`lng` / `lat` 为 `double`，**百度坐标系（BD-09）**，不是 GPS 原始 WGS-84。

### 1.4 分页

目前只有 `GET /api/pois/page` 是分页接口：

- 请求参数：`page`（**从 1 开始**）、`size`（默认 6，服务端上限 50）；
- 响应：`{ items, page, size, total, hasMore }`；
- 非法值（`page=0`、`page=-1`、`size=0`）**一律夹回合法区间，不返回 400** ——
  首页只是想把内容铺出来，一次手滑不该变成一张错误页；
- `hasMore` 由服务端算好（用的是 JPA 的 `hasNext`）。客户端**不要**用 `page*size < total` 自己推，那种推算在边界上最容易出错。

---

## 2. 身份与鉴权

### 2.1 四种身份

| 身份 | 凭证 | 能力 |
| --- | --- | --- |
| 游客（完全匿名） | 无 | 浏览内容、一次规划预览 |
| 匿名会话 | `X-Anonymous-Token` | 上面全部 + 在试用额度内保存行程 |
| 登录用户 | `Authorization: Bearer <accessToken>` | 上面全部 + 收藏、分享、历史行程、足迹 |
| 管理员 | 同上，但 JWT 带 `ROLE_ADMIN` | 额外的 `/api/admin/**` |

### 2.2 请求头

| 头 | 何时带 | 说明 |
| --- | --- | --- |
| `Authorization` | 已登录 | `Bearer <accessToken>` |
| `X-Anonymous-Token` | 匿名体验 | 服务端首次创建行程时通过**响应头** `X-Anonymous-Token` 下发 |
| `X-Device-Fingerprint` | 可选 | 匿名会话的弱去重依据，**服务端只存哈希**，不存原始设备标识 |

> `X-Device-Fingerprint` 已加入 CORS 白名单（T23），浏览器跨域创建匿名会话不会再被
> preflight 拦住；服务端仍然只保存该值的哈希。

### 2.3 免登录清单（以 `SecurityConfig` 为准）

**完全公开（permitAll）：**

- `POST /api/auth/**`（register / login / refresh / logout）
- `GET /api/home`、`/api/pois/**`
- `POST /api/anonymous/session`
- `POST /api/email/**`
- `POST /api/trip-plans/preview`、`POST /api/trip-plans`
- `POST /api/feedback`
- `GET /api/trip-shares/*`
- `GET /share/**`（HTML 只读分享页）
- `GET /media/**`（运营台上传的景点配图，只读）
- `GET /api/map/image`（访问控制不是登录态，而是「一次性短时票据」，见 §8.2）
- `GET /actuator/health`

**需要登录或有效匿名会话：** 其余全部，包括
`GET /api/trip-plans`、`GET /api/trip-plans/{id}`、`/{id}/adjust`、`/{id}/undo`、
`/{id}/today`、`/{id}/trace`、`/api/trip-plans/{id}/map`、
`/api/favorites/**`、`GET /api/anonymous/session`、`GET /api/auth/me`、`POST /api/auth/merge-anonymous`。

**需要管理员：** `/api/admin/**`（安全链统一收口，不在每个方法上单独判角色）。

### 2.4 匿名会话

```
POST /api/anonymous/session
X-Device-Fingerprint: <可选，服务端只存哈希>

→ 201
{ "sessionId": "…", "token": "…", "expiresAt": "2026-10-02T08:00:00Z", "trialLimit": 1 }
```

- `trialLimit` 默认 1，由 `TRIAL_LIMIT` 控制；
- 查询当前额度：`GET /api/anonymous/session`（需带 token）→
  `{ sessionId, planningCount, trialLimit, expiresAt }`；
- **也可以不主动创建**：直接 `POST /api/trip-plans`，服务端会自动开一个匿名会话，
  并把 token 放在响应头 `X-Anonymous-Token` 里（该响应头已在 CORS `exposedHeaders` 中放行）。

### 2.5 登录 / 刷新 / 登出

`register`、`login`、`refresh` 返回同一个 `AuthResponse`：

```json
{
  "accessToken": "…",
  "refreshToken": "…",
  "expiresIn": 7200,
  "user": {
    "id": "3f1c…",
    "username": "user1",
    "nickname": "河洛旅人",
    "email": "user@example.com",
    "avatarKey": "celadon",
    "emailVerified": false,
    "roles": ["ROLE_USER"]
  }
}
```

- `expiresIn` 单位是**秒**（`JWT_ACCESS_MINUTES` 默认 120 分钟）；
- refresh token 有效期由 `JWT_REFRESH_DAYS` 控制，默认 7 天；
- 注册约束：用户名 3—32 字符、邮箱格式合法、密码 8—72 字符；
- 登录的 `identifier` 可以是**用户名或邮箱**；
- `POST /api/auth/logout` → `204`（body 可选 `{ refreshToken }`）；
- `GET /api/auth/me` → `UserSummary`。

账号资料与安全接口（全部需要登录）：

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| PATCH | `/api/auth/me` | `{ nickname, avatarKey }` | 更新后的 `UserSummary` |
| POST | `/api/auth/change-password` | `{ currentPassword, newPassword }` | `204` |
| POST | `/api/auth/logout-all` | 无 | `204`，撤销所有刷新令牌 |
| DELETE | `/api/auth/me` | `{ password }` | `204`，级联删除账号数据 |

- `nickname` ≤ 40，可留空表示回退显示用户名；
- `avatarKey` 只接受 `celadon / kiln / amber / river / ink`，不保存用户照片；
- 修改密码会撤销所有刷新令牌，本机应重新登录；
- 删除账号会删除行程、收藏、分享和刷新令牌；操作不可恢复；
- 邮箱验证继续使用 §9.3 的 `send-code` / `verify-code`，验证成功后服务端会把
  `emailVerified` 置为 `true`，客户端重新读取 `/api/auth/me` 即可刷新状态。

### 2.6 匿名转正（账号合并）

```
POST /api/auth/merge-anonymous
Authorization: Bearer <accessToken>
X-Anonymous-Token: <匿名 token>

→ { "merged": true, "userId": "3f1c…" }
```

把匿名期间的行程归到账号下。**只有登录后主动调用才合并**，不会静默吞掉匿名数据。

---

## 3. 统一响应与错误

### 3.1 错误对象

`GlobalExceptionHandler` 保证任何错误都是同一个形状：

```json
{
  "code": "VALIDATION_ERROR",
  "message": "请描述你的旅行需求",
  "timestamp": "2026-10-02T06:30:00Z"
}
```

`message` 是**可以直接展示给用户**的中文文案；
**不要拿它做程序分支**，分支请用 `code`。

### 3.2 错误码表

| code | HTTP | 触发场景 |
| --- | --- | --- |
| `VALIDATION_ERROR` | 400 | Bean Validation 失败（`message` 取第一条字段错误） |
| `AUTH_REQUIRED` | 401 | 未带凭证、token 过期或无效 |
| `ANONYMOUS_SESSION_REQUIRED` | 401 | 匿名接口没带有效 `X-Anonymous-Token` |
| `ACCESS_DENIED` | 403 | 已登录但越权（含普通用户访问 `/api/admin/**`） |
| `MAP_CENTER_INVALID` | 400 | 地图中心点格式或范围不合法 |
| `POI_ID_REQUIRED` | 400 | 管理端缺少景点标识 |
| `POI_NOT_FOUND` | 404 | 管理端景点不存在 |
| `EXTERNAL_*` | 503 | 外部数据源不可用（`ExternalServiceException`，码值由各适配器给出） |
| `INTERNAL_ERROR` | 500 | 未预期异常，**不回显内部细节** |

业务层还可能抛出其它 `ApiException`（例如行程不存在 → `404`），以 `code` + HTTP 状态为准。

### 3.3 状态码语义

- `200` 成功；`201` 已创建；`204` 成功且无响应体；
- `400` 你传错了；`401` 你没资格（先登录或建匿名会话）；
- `403` 你有身份但没权限；`404` 资源不存在，**或存在但不属于你**；
- `503` 外部依赖不可用，稍后重试有意义。

> 归属校验统一返回 **404 而不是 403**：不告诉调用方"这个 id 是存在的，只是不是你的"。

---

## 4. 数据状态语义 ⭐

这是本项目的**产品级硬规则**，也是评审关注「数据安全意识 / 应用价值」时的落点之一。

服务端所有工具结果都归到 5 种状态之一（见 `ToolResult.dataStatus()`）：

| 界面显示 | 含义 | 产生条件 |
| --- | --- | --- |
| `实时数据` | 真实外部接口本次返回 | `isRealtime = true` |
| `缓存数据` | 真实数据的缓存 | `isCached = true` |
| `系统资料` | 运营台维护的内容库 / 公开资料 | 既非实时也非演示 |
| `演示数据` | 本地演示数据（`APP_TOOLS_MODE=mock`、未配 AK 等） | `isMock = true` 且 `errorCode == null` |
| `演示数据（降级）` | 真实源调用失败后退回演示数据 | `isMock = true` 且 `errorCode != null` |

**判定顺序不可调整**：`isMock && errorCode != null` 必须排在纯 `isMock` 之前，
否则"取不到真实数据"会被显示成普通的演示数据。客户端 `DataStatus.fromServer` 按同一张表解析。

**两条纪律：**

1. **绝不**把演示数据说成实时；
2. 降级必须带原因（`errorCode` / `errorMessage`），而不是静默吞掉。

---

## 5. 内容接口（公开）

### 5.1 `GET /api/home`

首页聚合。免登录。

```json
{
  "corridors": [
    { "id": "zhengzhou-luoyang", "title": "郑州—洛阳", "subtitle": "古都深读",
      "cities": "郑州,洛阳", "duration": "2天", "budget": "800-1200",
      "imageUrl": "https://…", "highlights": ["龙门石窟", "洛阳博物馆"] }
  ],
  "featuredPois": [ { "id": "poi-…", "name": "龙门石窟" } ],
  "headline": "一句话，规划你的河南之旅",
  "subline": "从第一站到最后一程，把中原风物安排得刚刚好。"
}
```

### 5.2 `GET /api/pois?city=<可选>`

返回**数组** `[Poi]`，用于「全部景点」列表与离线缓存。

> **不要**给它加参数去改变响应形状 —— 把同一个地址在有参数/无参数时变成两种形状，
> 是那种过半年一定会踩到的坑。首页信息流用的是下面那个独立端点。

### 5.3 `GET /api/pois/page?city=&page=1&size=6`

首页信息流分页，返回**对象**：

```json
{ "items": [ Poi ], "page": 1, "size": 6, "total": 23, "hasMore": true }
```

`page` 从 1 开始、`size` 上限 50（见 §1.4）。
首页一次 6 张、滑到底续取，用的就是这个接口。

### 5.4 `GET /api/pois/{id}`

单个景点 → `Poi`；不存在（或未上架）→ `404`，无响应体。

`Poi` 字段：

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 如 `poi-17c4…` |
| `name` / `city` / `category` | string | 名称 / 所属城市 / 主题分类 |
| `imageUrl` | string? | 可为空（空时客户端用主题占位图） |
| `description` | string | 一句话文化介绍 |
| `ticketFrom` | int | **参考起步价**，不是实时票价（对应 §4 的 `系统资料`） |
| `duration` | string | 建议游玩时长，如 `"2-3小时"` |
| `suitability` / `weatherTip` | string? | 适合人群 / 天气提示 |
| `dataStatus` | string | §4 的 5 种之一 |
| `imageCredit` / `sourceUrl` | string? | 图片出处与资料链接 |
| `imageStatus` | string | 配图合规派生状态 |

- `imageCredit` / `sourceUrl` 是运营台填写的出处。景区照片要么是**有授权的实景图**，
  要么是**明确标注的占位图**，客户端要能把这句话显示出来，而不是让"这张图从哪来"只存在于后台；
- `imageStatus` 是**派生字段，不落库**：由服务端 `PoiImageAudit` 按当前图片与来源信息现算。
  这样"配图能不能交付"这件事只有一处规则，管理台不需要自己再判一遍。

### 5.5 媒体地址

运营台上传的图片通过 `GET /media/**` **只读公开**（写入只在 `/api/admin/**` 下）。

`MEDIA_BASE_URL` 未配置时，服务端会从请求推导绝对地址；
**模拟器（`10.0.2.2`）或反向代理场景必须显式配置**，
否则会推导出 `localhost` 而客户端根本加载不到。

### 5.6 `GET /api/pois/nearby?lng=&lat=&radius=&limit=`（免登录）

附近的景点。`lng` / `lat` **必填**，是设备定位的原始 **WGS-84** 坐标。

| 参数 | 必填 | 默认 | 范围 |
| --- | --- | --- | --- |
| `lng` / `lat` | 是 | —— | 合法经纬度；缺失或越界 → `400 COORDINATE_INVALID` |
| `radius` | 否 | 3000 | 200—20000（米），越界夹回 |
| `limit` | 否 | 10 | 1—50，越界夹回 |

```json
{ "items": [ { "poi": { "id": "poi-17c4…", "name": "二七纪念塔", "city": "郑州" },
               "distanceMeters": 420 } ],
  "radiusMeters": 3000,
  "coordinateSystem": "入参 WGS-84，服务端换算到 BD-09 后比较",
  "skippedWithoutCoordinate": 3,
  "dataStatus": "系统资料" }
```

三条要说清楚的事：

1. **坐标系由服务端兜住。** 内容库里的景点坐标是 BD-09，设备给的是 WGS-84，
   两者在河南境内相差 **1 公里上下**（GCJ-02 偏移数百米 + BD-09 恒定平移约 890 米）。
   服务端先换算再比距离 —— 换算只在这一处实现，换底图或换数据源时不需要所有已发布的 APK 跟着升版。
2. **`distanceMeters` 是直线距离**，不是步行或驾车里程。
   界面必须照这个口径措辞，不能拿它除以步速编一个"步行 5 分钟"。
3. **服务端不保存这次查询的坐标** —— 位置不落库，也就没有位置历史。
   `skippedWithoutCoordinate` 是"上架了但没配坐标、因此没能参与计算"的景点数：
   少了它，「附近没景点」和「附近景点都没配坐标」在界面上长得一模一样，运营排查也就没了线索。

排序规则：距离升序；距离相同时按 `id` 升序（否则同一份请求两次可能给出不同顺序）。

---

## 6. 行程接口

### 6.1 `POST /api/trip-plans/preview`（免登录）

把一句话需求解析成结构化条件，**不落库、不调 LLM 生成行程**。

```jsonc
// 请求
{ "prompt": "两个人周末从郑州去洛阳，看历史文化，预算每人1000",
  "startDate": null, "origin": null, "destination": null,
  "days": null, "travelers": null, "budgetPerPerson": null,
  "interests": null, "pace": null, "transport": null }

// 响应
{ "sessionId": "…",
  "request": { "prompt": "…", "origin": "郑州", "destination": "洛阳", "interests": "历史文化", "pace": "适中" },
  "extracted": ["出发地：郑州", "目的地：洛阳", "兴趣：历史文化", "节奏：适中"],
  "missing": ["计划游玩几天？"],
  "requiresConfirmation": true,
  "dataStatus": "演示数据" }
```

`missing` 非空时，客户端应该**只追问缺失项**，而不是弹出一整个表单。

### 6.2 `POST /api/trip-plans`（免登录，可匿名）

创建行程。这是唯一「游客也能写业务数据」的接口。

```jsonc
// 请求
{ "prompt": "两个人周末从郑州去洛阳，看历史文化，预算每人1000",
  "startDate": "2026-10-03", "origin": "郑州", "destination": "洛阳",
  "days": 2, "travelers": 2, "budgetPerPerson": 1000,
  "interests": "历史文化", "pace": "适中", "transport": "高铁" }

// 响应
201 Created
X-Anonymous-Token: <仅在首次匿名访问、服务端新开会话时出现>
{ TripPlan }
```

- `startDate` 为空 → 按「**明天**」处理，绝不静默改成别的日期。
  它是天气、车次与方案里每一天的**唯一时间口径**；
- `days` 上限 7（与 APK 输入框一致）；
- 未登录时受 `trialLimit` 限制，超限返回业务错误。

### 6.3 `GET /api/trip-plans`

当前身份的全部行程摘要 `[Summary]`：

```json
[{ "id": "…", "title": "…", "summary": "…", "corridor": "郑州—洛阳",
   "intensity": "适中", "totalCost": 1900, "perPersonCost": 950,
   "daysCount": 2, "dataStatus": "实时数据", "updatedAt": "2026-10-02T06:30:00Z" }]
```

### 6.4 `GET /api/trip-plans/footprint`

「你的足迹」聚合。**只由真实落库的行程聚合而来，不做任何估算。**

```json
{ "cities": [ { "name": "洛阳", "tripCount": 2,
                "firstVisitAt": "…", "lastVisitAt": "…" } ],
  "totalMeters": 3240000, "totalDays": 28, "tripCount": 12,
  "generatedAt": "2026-10-02T06:30:00Z" }
```

> ⚠️ `totalMeters` 只累计行程项里**确实带距离**的那些（路线工具返回时才写入），
> 所以它是「**已记录里程**」而不是「实际走过的里程」。
> 界面必须照这个口径措辞，不能写成"你走了 3240 公里"。

### 6.5 `GET /api/trip-plans/{id}` → `TripPlan`

```json
{ "id": "…", "title": "…", "summary": "…", "corridor": "郑州—洛阳",
  "intensity": "适中", "totalCost": 1900, "perPersonCost": 950,
  "days": [ { "label": "第1天", "date": "2026-10-03",
              "items": [ { "type": "sight", "title": "龙门石窟", "time": "09:00",
                           "duration": "3小时", "transport": "地铁",
                           "description": "…", "cost": 90,
                           "source": "百度地图", "dataStatus": "实时数据",
                           "risk": null } ] } ],
  "warnings": ["第2天户外安排遇雨概率较高"],
  "dataStatus": "实时数据" }
```

不是本人（也不属于当前匿名会话）的 id → **404**。

### 6.6 `PATCH /api/trip-plans/{id}`

`{ "title": "洛阳两日", "summary": "…", "intensity": "轻松" }` → `TripPlan`。
`title` 上限 **40 字**（与 APK 的重命名输入框一致，免得客户端能输入、服务端才炸）。

### 6.7 `DELETE /api/trip-plans/{id}` → `204`

### 6.8 `POST /api/trip-plans/{id}/adjust`

```jsonc
// 请求
{ "instruction": "第二天轻松一点，并增加当地美食" }
// 响应
{ "plan": { TripPlan }, "changes": ["第2天减少 1 个景点", "新增 1 家本地餐馆"], "version": 3 }
```

`changes` 是**给用户看的改动说明**（删/换/移了什么），不是内部 diff。
客户端要能据此渲染"调整前 → 调整后"的对比。

### 6.9 `POST /api/trip-plans/{id}/undo` → `TripPlan`

### 6.10 `GET /api/trip-plans/{id}/today`

```json
{ "tripId": "…", "date": "2026-10-03", "nextStop": "龙门石窟",
  "arrival": "09:00", "weather": "多云 18-24℃", "status": "进行中",
  "remainingItems": [ TripItem ] }
```

### 6.11 `GET /api/trip-plans/{id}/trace`

AI 工具调用轨迹 —— **答辩与运营排查用**，也是"不伪造工具调用"的直接证据：

```json
{ "tripId": "…", "engine": "deepseek", "promptVersion": "planner-v3",
  "dataStatus": "实时数据", "toolMockCount": 0, "warnings": [],
  "toolInvocations": [ { "toolName": "searchTrain", "source": "12306-mcp",
                         "dataStatus": "实时数据", "success": true,
                         "outputSummary": "郑州→洛阳 12 趟", "errorCode": null,
                         "durationMs": 812, "createdAt": "…" },
                       { "toolName": "quoteRailFares", "source": "12306 MCP（2026-10-03 官方票价）",
                         "dataStatus": "实时数据", "success": true,
                         "outputSummary": "G1903 郑州东 → 洛阳龙门 二等座 ¥65 / 一等座 ¥104",
                         "errorCode": null, "durationMs": 620, "createdAt": "…" },
                       { "toolName": "searchTransfer", "source": "12306 MCP（2026-10-03 官方中转换乘）",
                         "dataStatus": "实时数据", "success": true,
                         "outputSummary": "郑州东 中转，等待 约35分钟，全程 约2小时",
                         "errorCode": null, "durationMs": 700, "createdAt": "…" } ] }
```

---

## 7. 分享

### 7.1 `POST /api/trip-plans/{id}/share`

```jsonc
// 请求（body 可省略）
{ "hideBudget": true, "expireDays": 7 }
// 响应
{ "id": "…", "token": "k7Qm…", "url": "http://localhost:8080/share/k7Qm…",
  "expiresAt": "2026-10-09T06:30:00Z", "hideBudget": true }
```

`url` 由 `SHARE_BASE_URL` 拼出 —— **换域名必须改这个环境变量**，否则分享链接会指向本机。

### 7.2 `GET /api/trip-shares/{token}`（免登录）

→ `{ "plan": TripPlan, "hideBudget": true }`

> ⚠️ 服务端已按 `hideBudget` **把金额置 0** 之后再返回，
> 不是靠前端"不显示"。分享内容不含密码、Token、精确位置历史、私人备注。

### 7.3 `DELETE /api/trip-shares/{id}` → `204`

分享者可以随时关掉一条分享。

### 7.4 `GET /share/{token}` → HTML

给**手机浏览器**直接看的只读页：不需要登录、不需要装 App。

- 只渲染服务端已脱敏的内容；
- 所有文本做 HTML 转义（行程标题也是用户输入，不能成为注入点）；
- 不输出令牌、账号、备注或任何第三方密钥；
- 响应头带 `noindex,nofollow`，不被搜索引擎收录。

---

## 8. 地图

设计要点：**AK 不出服务器**。底图由服务端带 AK 取回再转发给客户端。

### 8.1 `GET /api/trip-plans/{id}/map`（需登录/匿名 + 归属校验）

查询参数：`day`（第几天，可选）、`center=lng,lat`、`zoom`、`panX`、`panY`

```json
{ "tripId": "…", "dayIndex": 0, "dayLabel": "第1天", "dayDate": "2026-10-03",
  "viewport": { "centerLng": 112.45, "centerLat": 34.62, "zoom": 12,
                "width": 1024, "height": 768, "fitted": true },
  "imageUrl": "/api/map/image?center=…&zoom=12&width=1024&height=768&ticket=…",
  "imageLifetimeSeconds": 900,
  "markers": [ { "index": 1, "title": "龙门石窟", "itemType": "sight", "time": "09:00",
                 "lng": 112.47, "lat": 34.55, "x": 512.0, "y": 384.0,
                 "inside": true, "coordinateSource": "baidu-geocode", "confidence": 90 } ],
  "polyline": [[512.0, 384.0], [540.5, 400.2]],
  "unplaced": [ { "title": "某小吃街", "reason": "未能可信定位" } ],
  "attribution": ["百度地图"],
  "dataStatus": "系统资料", "source": "百度地图静态底图 + 地理编码（不含实时路况）",
  "queriedAt": "…", "expiresAt": "…", "fallback": false, "message": null }
```

- `x` / `y` **已经投影好**：原点是底图左上角，单位是底图像素。
  客户端按显示宽度等比换算即可 —— 这样投影公式只有 Java 侧一份实现（可单元测试），
  不会把百度坐标系的换算知识散落到 APK 里；
- `inside=false` 表示这个点在当前窗口外（用户拖动或放大后很常见）。
  客户端**不应**把它画在边缘，而是提示"还有几个站点在画面外"；
- `unplaced` 是**没能可信定位的站点，明确列出来，而不是悄悄丢掉**。

### 8.2 `GET /api/map/image?center=&zoom=&width=&height=&ticket=`（免登录）

返回 `image/png`，给客户端 `CachedNetworkImage` 直接消费（它带不了 `Authorization` 头）。

访问控制不是"登录"，而是**服务端签发的一次性短时票据**：
票据只对同一组参数有效，过期即失效。
`width` / `height` 会被夹到 **320—1024**。票据不匹配即拒绝 ——
否则这个端点会变成任何人都能刷的百度代理。

### 8.3 `GET /api/map/size` → `{ "width": 1024, "height": 768 }`

---

## 9. 我的数据

### 9.1 收藏（需登录）

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/favorites` | `{ poiId, poiName, city, imageUrl }` → `201 FavoriteResponse` |
| GET | `/api/favorites` | → `[{ id, poiId, poiName, city, imageUrl, createdAt }]` |
| DELETE | `/api/favorites/{id}` | → `204` |
| DELETE | `/api/favorites/poi/{poiId}` | → `204`（按景点反查删除，供"取消收藏"用） |

### 9.2 反馈（免登录提交）

`POST /api/feedback`

```jsonc
{ "content": "…", "category": "内容纠错", "contact": "…", "page": "poi/poi-17c4" }
→ 201 { "id": "…", "status": "PENDING", "createdAt": "…" }
```

- `content` ≤ 1000 字、`contact` ≤ 160、`page` ≤ 120；
- 服务端**只保存内容、可选联系方式与来源页面，不采集设备标识**。

### 9.3 邮箱验证码（免登录，SMTP 预留）

| 方法 | 路径 | 请求 | 响应 |
| --- | --- | --- | --- |
| POST | `/api/email/send-code` | `{ email, purpose }` | `{ message, debugCode }` |
| POST | `/api/email/verify-code` | `{ email, code, purpose }` | `{ message, debugCode }` |

`debugCode` **只在 SMTP 未启用（`SMTP_ENABLED=false`）时**返回，用于本机联调；
生产环境必须关掉。验证码有发送频率限制、短期有效、不明文存储，
错误信息也不用于枚举用户账号。

### 9.4 匿名会话

见 §2.4。

### 9.5 消息中心（需登录）

消息保存在账号下，已读状态跨设备同步；未登录时客户端仍显示本机产品说明。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/api/messages` | `{ items: Message[], unread }`；首次读取时为账号种入系统说明 |
| GET | `/api/messages/unread-count` | `{ unread }` |
| PATCH | `/api/messages/{id}/read` | 标记单条已读 |
| PATCH | `/api/messages/read-all` | 全部已读 |

`Message` 只包含 `id / type / title / body / read / createdAt / readAt`，
不保存推送令牌、设备标识或聊天内容。

---

## 10. 管理端接口（全部需要 `ROLE_ADMIN`）

> 部署提示见 §13.2：管理台的 `/api` 请求应由 nginx 反代到 `server:8080`。

### 10.1 景点内容 `/api/admin/pois`

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/` | 列表，支持 `?keyword=`（匹配名称/城市/分类） |
| GET | `/{id}` | 详情（含坐标、发布状态、`imageStatus`） |
| POST | `/geocode` | 景点名 → 候选坐标，**只回参考值、不落库** |
| POST | `/` | 新建 → `201` |
| PUT | `/{id}` | 更新（**id 不变**：行程文本、收藏、分享链接都引用它） |
| PATCH | `/{id}/publish` | `{ "published": true }` |
| DELETE | `/{id}` | `204` |

**所有写操作都会落一条操作日志**（谁、什么时候、改了什么），
交付时可以直接展示这条审计链。

`POST /geocode` 的 `trusted=false` 时 **`lng` / `lat` 一律为空**：
只定位到城市中心、可信度不足、或外部服务不可用，都不给出一个"看起来能用"的坐标。
宁可让运营人员手工填写，也不允许一个错误的坐标顺着界面流进数据库。

坐标越界值在保存时**一律当作"没填"**（而不是抛错）：拒绝写库比悄悄存一个错坐标安全，
而地图对空坐标本就有降级路径（按名称解析）。

### 10.2 图片上传 `/api/admin/media`

```
POST /api/admin/media/images
Content-Type: multipart/form-data
file=<二进制>

→ 201 { "fileName": "…", "url": "http://…/media/…", "relativeUrl": "/media/…",
        "format": "jpg", "sizeBytes": 512345, "width": 1600, "height": 900 }
```

- `url` 可以直接写进景点内容的 `imageUrl`；
- **日志只记尺寸与体积，不记原始文件名**（可能包含个人信息）；
- 限制：单文件 10MB（`MEDIA_MAX_FILE_SIZE`）、应用层再按 `MEDIA_MAX_SIZE_MB`（默认 8MB）校验、最长边 6000px。

### 10.3 运行统计 `GET /api/admin/stats/overview`

```jsonc
{ "generatedAt": "…",
  "users":   { "total": 12, "verified": 3, "newLast7Days": 5 },
  "trips":   { "total": 34, "registered": 20, "anonymous": 14, "newLast7Days": 9, "avgDays": 2.1 },
  "content": { "publishedPois": 23, "totalPois": 26, "openFeedback": 2 },
  "tools":   { "total": 210, "succeeded": 198, "failed": 12, "successRate": 94.3,
               "mockCalls": 8, "realtimeCalls": 180, "cachedCalls": 18, "degradedCalls": 4 },
  "shares":  { "total": 7, "active": 5, "views": 41 },
  "daily":   [ { "date": "2026-10-01", "plans": 4, "toolCalls": 26 } ],
  "llm":     { "enabled": true, "lastSuccessfulEngine": "deepseek",
               "selectionOrder": ["deepseek", "kimi"],
               "providers": [ { "id": "deepseek", "displayName": "DeepSeek", "model": "deepseek-chat",
                                "priority": 20, "enabled": true, "configured": true,
                                "successCount": 30, "failureCount": 1,
                                "lastError": null, "lastLatencyMs": 4200 } ] } }
```

`tools.degradedCalls` 是 `mockCalls` 的**子集**：单独统计才能说明"外部服务到底有没有接上"。

### 10.4 外部数据源健康度 `GET /api/admin/tools/health`

与统计的区别：统计看「用了多少」，这里看「**接上没有**」。
覆盖百度地图 AK、天气提供方、12306 提供方、门票比价提供方，以及当前的 `live` / `mock` 模式。

### 10.5 LLM 供应商 `GET /api/admin/llm/providers`

```json
{ "llmEnabled": true, "activeEngine": "deepseek", "selectionOrder": ["deepseek"],
  "providers": [ { "id": "deepseek", "displayName": "DeepSeek", "model": "deepseek-chat",
                   "priority": 20, "enabled": true, "configured": true,
                   "baseUrl": "https://api.deepseek.com/v1",
                   "timeoutSeconds": 60, "temperature": 0.3 } ],
  "attempts": [ "…ProviderHealth.Snapshot…" ] }
```

- **API Key 永远不在响应里**。管理台只需要知道"启没启、配没配、最近表现如何"；
- 四家适配：`openai` / `deepseek` / `kimi` / `qwen`，按 `priority` 升序尝试，
  第一个答的胜出，mock 引擎永远排在最后。

### 10.6 反馈管理 `/api/admin/feedback`

`GET /`（支持 `?status=`）、`PATCH /{id}` `{ "status": "…", "handlerNote": "…" }`

### 10.7 操作日志 `GET /api/admin/logs?limit=50`

`limit` 会被夹到 **1—200**。

### 10.8 提示词版本 `/api/admin/llm/prompts`

系统提示词版本与供应商解耦：OpenAI / DeepSeek / Kimi / Qwen 共用同一份当前启用提示词。
管理台可以查看历史、发布新版本并回滚；**发布即启用**，任一时刻最多一个 active 版本。

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/` | 版本列表（含系统提示词全文、说明、启用状态、创建时间） |
| GET | `/current` | 当前启用版本 |
| POST | `/` | `{ version, systemPrompt, note }` → `201`，发布并启用新版本 |
| PATCH | `/{id}/activate` | 启用历史版本（回滚） |

约束与边界：

- `version` ≤ 64、`systemPrompt` ≤ 20000、`note` ≤ 200；
- 版本号重复返回 `409 PROMPT_VERSION_EXISTS`；
- 只管理系统提示词；用户请求、工具数据、JSON 输出契约和厂商无关解析仍由代码控制；
- 新生成的行程会把当前版本号写入 `prompt_version`，工具轨迹接口 (§6.11) 可直接核对；
- 发布与启用都会写操作日志。

### 10.9 Mock 数据覆盖 `/api/admin/mock/scenarios`

稳定演示模式下的结构化覆盖数据。**只管理演示数据，不接触真实用户数据，也不冒充实时数据。**

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/` | 返回支持的数据类型与已保存覆盖项 |
| PUT | `/{scenarioKey}/{matchKey}` | 新建或更新覆盖；保存前按类型严格校验 JSON |
| DELETE | `/{id}` | 删除覆盖，回退到代码内置样例 |

支持的类型：

| `scenarioKey` | 匹配键示例 | JSON 形状 |
| --- | --- | --- |
| `weather` | `洛阳` / `default` | `WeatherInfo` 对象 |
| `route` | `郑州>洛阳` / `default` | `RouteInfo` 对象 |
| `train` | `郑州>洛阳` / `default` | `TrainInfo[]` |
| `railFare` | `郑州>洛阳` / `default` | `RailFare[]` |
| `transfer` | `郑州>洛阳` / `default` | `RailTransfer[]` |

匹配顺序：精确匹配优先，其次 `default`，都没有则回退内置样例。JSON 无法按目标类型
反序列化时返回 `400 MOCK_PAYLOAD_INVALID`，不会把坏数据写进运行时。

---

## 11. 数据模型速查

### 11.1 `TripPlan`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | string | 行程标识 |
| `title` / `summary` | string | 标题（≤40 字）/ 摘要 |
| `corridor` | string? | 所属走廊，如 `郑州—洛阳` |
| `intensity` | string? | 行程强度：轻松 / 适中 / 紧凑 |
| `totalCost` / `perPersonCost` | int | 元 |
| `days` | TripDay[] | 逐日安排 |
| `warnings` | string[] | 出行提醒 |
| `dataStatus` | string | §4 的 5 种之一 |

### 11.2 `TripDay` / `TripItem`

| TripDay | 类型 | 说明 |
| --- | --- | --- |
| `label` | string | 如 `第1天` |
| `date` | string? | `yyyy-MM-dd` |
| `items` | TripItem[] | 时间轴节点 |

| TripItem | 类型 | 说明 |
| --- | --- | --- |
| `type` | string | 节点类型（景点 / 交通 / 餐饮 / 休息） |
| `title` | string | 名称 |
| `time` | string? | 开始时间 `HH:mm` |
| `duration` | string? | 展示用时长文案 |
| `transport` | string? | 到达方式 |
| `description` | string? | 说明 / 推荐理由 |
| `cost` | int | 元（可能为 0） |
| `source` | string? | 数据来源 |
| `dataStatus` | string | 该节点的数据状态 |
| `risk` | string? | 风险提示 |

### 11.3 `Summary` / `Footprint`

`Summary` = `TripPlan` 的列表视图（`id, title, summary, corridor, intensity, totalCost, perPersonCost, daysCount, dataStatus, updatedAt`）。
`Footprint` 见 §6.4。

### 11.4 `PromptVersion`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | UUID? | 内置兜底版本没有 id；数据库版本有 |
| `version` | string | 版本号，唯一 |
| `systemPrompt` | string | 厂商无关的系统提示词全文 |
| `note` | string? | 版本说明 |
| `active` | boolean | 当前是否启用 |
| `createdAt` | Instant | 创建时间 |

### 11.5 `DemoScenario`

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `id` | UUID | 覆盖项标识 |
| `scenarioKey` | string | weather / route / train / railFare / transfer |
| `matchKey` | string | 精确匹配键，或 `default` |
| `name` | string | 运营台展示名称 |
| `payloadJson` | string | 已通过类型校验的结构化 JSON |
| `note` | string? | 运营说明，不进入工具响应 |
| `enabled` | boolean | 停用后回退内置样例 |
| `updatedAt` | Instant | 更新时间 |

---

## 12. 客户端接入约定

1. **401** → 清凭证、回登录页，**不要无限重试**；
2. **503** → 是「外部依赖不可用」，可重试；展示时带上 `code` 便于排查；
3. **`dataStatus` 一定要显示**，且按 §4 原样显示，不要自己映射成"实时"；
4. 行程 `id` 不存在或不属于当前身份 → **404**，按"没找到"处理，不要提示"无权限"；
5. **不要把 `ticketFrom` 当成实时票价**，它是参考起步价（`系统资料`）；
6. 分页接口的 `page` 从 **1** 开始；
7. 匿名创建行程后，记得保存响应头里的 `X-Anonymous-Token` —— 丢了就找不回那份行程。

---

## 13. 未实现与已知缺口

### 13.1 还没做的接口

| 能力 | 计划中的接口 | 现状 |
| --- | --- | --- |
| 定位 + 附近景点 | `GET /api/pois/nearby?lng=&lat=&radius=&limit=` | 服务端**已实现**（§5.6）；APK 端**已接入**设备定位（`screens/nearby_screen.dart`），拒绝授权退回「按城市浏览」 |
| 消息中心服务端化 | `GET /api/messages`、`PATCH /api/messages/{id}/read` | **已实现（T29）**；未登录仍使用本机说明，登录后切换为账号消息 |
| 设置页真实可改 | `PATCH /api/auth/me`（昵称 / 预设头像） | **已实现（T28）**；改密、邮箱验证、退出所有设备、删除账号见 §2.5 |
| 行程地图多日合并视图 | `GET /api/trip-plans/{id}/map?day=all` | **未实现**（当前逐日） |
| 门票比价 | 由 `TICKET_PROVIDER=smart-buy` 的适配器提供 | **未接**，当前降级到内容库参考价 |
| 12306 中转方案 | 由 `RAILWAY_PROVIDER=12306-mcp` + `mcp-server-12306` 提供 | **已接入**规划工具链（`searchTransfer`），是否可用取决于外部 MCP 服务 |
| APK 自更新 | `GET /api/app/version` | **未实现**（已记入 backlog，用户暂缓） |
| 购买 / 支付 / 预约 | —— | **不计划实现**（明确写在范围边界外） |

### 13.2 接口层已知缺口（T23 已收口两项）

1. **CORS 白名单缺 `X-Device-Fingerprint`（已修复，T23）**
   位置：`SecurityConfig.java` → `corsConfigurationSource`，
   `allowedHeaders` 现在同时包含 `Authorization`、`Content-Type`、`X-Anonymous-Token`、
   `X-Device-Fingerprint`。`SecurityConfigCorsTest` 已覆盖这条回归。

2. **管理台容器内 `/api` 没有反代（已修复，T23）**
   位置：`backend/admin/nginx.conf` + `backend/admin/Dockerfile`。
   容器内 Nginx 现在把 `/api/` 代理到 `http://server:8080`，前端路由回落 `index.html`，
   并提供 `/healthz`；管理台容器不再出现“页面能打开、接口全 404”的情况。

3. **没有自动生成的 OpenAPI**
   本机 Maven 处于**离线**状态（`mvn -o`），新增 `springdoc-openapi` 依赖有拉不到的风险。
   顺序：**先用手写本文档保证公开测试可用**，之后再评估能否换成自动生成。

### 13.3 环境变量速查（与接口行为直接相关的）

| 变量 | 默认 | 影响 |
| --- | --- | --- |
| `PORT` | 8080 | 服务端口 |
| `APP_TOOLS_MODE` | `live` | `live` 优先真实数据源、失败降级；`mock` 全部用本地演示数据 |
| `TRIAL_LIMIT` | 1 | 匿名会话可创建的行程数 |
| `JWT_ACCESS_MINUTES` / `JWT_REFRESH_DAYS` | 120 / 7 | 令牌有效期 |
| `CORS_ALLOWED_ORIGINS` | `http://localhost:5173` | 管理台跨域来源 |
| `SHARE_BASE_URL` | `http://localhost:8080/share` | 分享链接前缀 |
| `MEDIA_BASE_URL` | 空 | 图片绝对地址前缀（**模拟器/反代必须显式配**） |
| `BAIDU_MAP_AK` | 空 | 空则路线与底图直接用演示数据，且**不发网络请求** |
| `WEATHER_PROVIDER` | `open-meteo` | 天气源 |
| `RAILWAY_PROVIDER` | `reference` | `mcp` 走 `mcp-server-12306`；`reference` 为内置参考时刻表（标注**非实时**） |
| `TICKET_PROVIDER` | `catalog` | 门票价来源 |
| `LLM_ENABLED` + `LLM_{OPENAI,DEEPSEEK,KIMI,QWEN}_*` | 关闭 | 四家 LLM 适配与优先级 |
| `SMTP_ENABLED` | false | 关闭时 `/api/email/*` 会回 `debugCode` 供联调 |

---

## 14. 社区接口

社区旅记。浏览公开内容不要求登录；发布、编辑、删除、点赞和举报必须登录。

### 14.1 公开信息流 `GET /api/community/posts`

查询参数：

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `city` | 无 | 按城市筛选 |
| `tag` | 无 | 按标签包含匹配 |
| `page` | 1 | 从 1 开始 |
| `size` | 10 | 服务端夹到 1—50 |

只返回 `status=APPROVED` 且 `visibility=PUBLIC` 的旅记。响应：

```json
{
  "items": [
    {
      "id": "…",
      "authorName": "河洛旅人",
      "authorAvatarKey": "celadon",
      "tripPlanId": "…",
      "title": "洛阳两日：沿着伊河看石窟",
      "content": "…",
      "city": "洛阳",
      "tags": "历史文化,博物馆",
      "visibility": "PUBLIC",
      "status": "APPROVED",
      "imageUrls": ["/media/…"],
      "likeCount": 12,
      "viewCount": 80,
      "likedByMe": false,
      "createdAt": "…",
      "publishedAt": "…"
    }
  ],
  "page": 1,
  "size": 10,
  "total": 1,
  "hasMore": false
}
```

### 14.2 旅记详情 `GET /api/community/posts/{id}`

- 已通过的公开旅记所有人可看；
- 作者可以查看自己处于 `PENDING / REJECTED / TAKEN_DOWN` 的旅记；
- 其他用户看不到未公开内容，统一返回 404。

### 14.3 我的旅记 `GET /api/community/posts/mine`

需要登录，返回当前用户的全部旅记，包括待审核、驳回和下架状态。

### 14.4 发布与编辑

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/community/posts` | 发布旅记，初始状态 `PENDING` |
| PATCH | `/api/community/posts/{id}` | 作者编辑，重新进入 `PENDING` |
| DELETE | `/api/community/posts/{id}` | 作者删除 |

请求示例：

```json
{
  "title": "洛阳两日：沿着伊河看石窟",
  "content": "把行程里的时间和预算都收起来，只留下路线与感受。",
  "city": "洛阳",
  "tags": "历史文化,博物馆",
  "visibility": "PUBLIC",
  "tripPlanId": "…",
  "imageUrls": ["/media/…"]
}
```

约束：

- 标题 ≤ 80，正文 ≤ 3000，城市 ≤ 80，标签 ≤ 200；
- 最多 9 张图片；
- `visibility` 只允许 `PUBLIC / PRIVATE`；
- 关联行程必须是本人行程，否则返回 404；
- 图片地址只允许 `https://`、`http://` 或 `/media/`。

### 14.5 旅记图片上传 `POST /api/community/media/images`

需要登录，`multipart/form-data`，字段名为 `file`。服务端会：

- 只接受 JPEG / PNG；
- 单张不超过现有媒体大小限制；
- 最长边不超过 3000 像素；
- 重新解码并编码，主动去除 EXIF（包括拍摄位置）；
- 返回与运营台图片上传相同的 `ImageUploadResult`。

不能用 `GIF`，因为它会保留帧和元数据，不适合作为公开旅记图片入口。

### 14.6 点赞与举报

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| POST | `/api/community/posts/{id}/like` | 点赞，重复调用不重复计数 |
| DELETE | `/api/community/posts/{id}/like` | 取消点赞 |
| POST | `/api/community/posts/{id}/report` | `{ "reason": "…" }`，同一用户对同一旅记只允许一次 |

- 只有已通过且公开的旅记可以被点赞 / 举报；
- 不能举报自己的旅记。

### 14.7 管理端审核 `/api/admin/community`

| 方法 | 路径 | 说明 |
| --- | --- | --- |
| GET | `/posts?status=PENDING&page=1&size=10` | 按状态查看待审核旅记 |
| PATCH | `/posts/{id}/status` | `{ "status": "APPROVED|REJECTED|TAKEN_DOWN|PENDING", "note": "…" }` |
| GET | `/reports?status=OPEN&page=1&size=10` | 查看举报 |
| PATCH | `/reports/{id}` | `{ "status": "HANDLED|IGNORED", "note": "…" }` |

审核通过时写入 `publishedAt`；所有审核和处理动作写入管理员操作日志。

---

## 15. 变更记录

| 日期 | 版本 | 变更 |
| --- | --- | --- |
| 2026-10-02 | v0.3.0-apis | 首次整理：全部对外路径、鉴权矩阵、错误码表、数据状态语义、管理端接口、环境变量速查、已知缺口 |
| 2026-10-02 | v0.3.1-apis | 新增 `GET /api/pois/nearby`（§5.6）：WGS-84 → BD-09 服务端换算、直线距离口径、位置不落库 |
| 2026-10-02 | v0.3.2-apis | 新增提示词版本管理（§10.8）与 `PromptVersion` 数据模型（§11.4） |
| 2026-10-02 | v0.3.3-apis | 客户端服务器地址改为编译期优先、运行时可在设置页配置；release 仍只接受 HTTPS |
| 2026-10-02 | v0.3.4-apis | 新增 Mock 数据覆盖管理（§10.9）与 `DemoScenario` 数据模型（§11.5） |
| 2026-10-02 | v0.3.5-apis | 账号资料、改密、邮箱验证、退出所有设备与删除账号接口（§2.5） |
| 2026-10-02 | v0.3.6-apis | 新增服务端消息中心（§9.5）；登录后已读状态跟账号同步 |
| 2026-10-02 | v0.3.7-apis | 新增社区旅记后端底座（§14）：发布、浏览、点赞、举报与管理员审核 |
| 2026-10-02 | v0.3.8-apis | 新增旅记图片上传（§14.5）：JPEG/PNG 重编码、去 EXIF、限制尺寸 |

---

**文档之外的两件事：**

1. 本文档是「公开测试」的契约。任何接口在对外可用之后，**只准追加、不准改语义**；
2. 与本文档配套的运行时自查入口：`GET /actuator/health`（免登录），
   管理台的「工具健康度」页对应 §10.4。
