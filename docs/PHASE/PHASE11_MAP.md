# 阶段十一 · T11.2 行程地图与运营台坐标维护

> 交付物：行程结果页的**逐日地图 Tab**，以及运营台维护景点坐标的能力。
> 一句话结论：**不引入百度 SDK/插件，改由服务端代取静态底图、客户端自绘标记与折线**；
> 任何一环不可用时退回文字路线，绝不出现空白地图。

## 1. 为什么不用百度 Android SDK / Flutter 插件

| 候选 | 结论 | 理由 |
| --- | --- | --- |
| 百度官方 Android SDK | 出局 | 必须把 AK 打进 APK，与全项目「AK 只留在服务端」的承诺直接冲突；AK 泄漏的代价是配额被刷光 |
| 第三方 Flutter 插件（ducafecat / baidu_map_flutter / flutter_bmflocation） | 出局 | 长期未更新、部分许可证不明、Flutter 新版本兼容性未知 |
| WebView 承载百度 JS 地图 | 出局 | 同样要在前端暴露 AK；且 WebView 与 Flutter 的手势、返回键、缓存难以做干净 |
| **服务端代理静态底图** | **采用** | AK 永不出服务器；无原生依赖；投影公式只写一份（Java，可单测）；画质与官方瓦片一致 |

必须说清的代价：静态底图**没有手势连续缩放，也没有实时路况图层**。
客户端的补偿做法是「拖动跟手预览 → 松手重取图」「±按钮缩放」，
并在界面右下角常驻一行「静态底图·不含实时路况」。

## 2. 数据流

```text
APK                      Spring Boot                       百度地图开放平台
 │                            │                                  │
 │  GET /trip-plans/{id}/map  │                                  │
 │ ─────────────────────────► │  1 取当日安排                    │
 │                            │  2 解析坐标（内容库 → 地理编码）──►│ /geocoding/v3
 │                            │  3 算窗口 + 算像素                │
 │                            │  4 取 1024px 底图（带 AK）  ─────►│ /staticimage/v2
 │                            │  5 签票据                        │
 │ ◄───────────────────────── │                                  │
 │  视窗 + 标记像素坐标 + 折线 + imageUrl（带票据）              │
 │                            │                                  │
 │  GET /api/map/image?ticket=│                                  │
 │ ─────────────────────────► │  验票 → 命中缓存或回源 ─────────►│
 │ ◄────────────── PNG ───────│                                  │
```

关键点：**客户端只收到"已经算好的像素坐标"**，不需要理解百度坐标系；
拖动时客户端先本地平移做跟手预览，松手后只把「视野中心移动了多少像素」交给服务端换算（`panX/panY`）。

## 3. 投影：百度静态底图内部是 BD09 墨卡托

实现见 `server/src/main/java/com/yujian/travel/map/WebMercator.java`，守护测试见 `WebMercatorTest`。

三条已用真实接口反证的事实：

1. **x 与经度成正比**：比例系数对应地球半径 6378137 米（球面墨卡托）；
2. **y 是墨卡托拉伸**：直接用 `R·ln(tan(π/4 + φ/2))`；
   同一基准里纬度差 0.04° 实测 84.7 像素，按等距圆柱只会得到 69.6 像素，
   比值 1.217 与 `1/cos(34.76°)` 一致 —— 说明确实是墨卡托，不是等距圆柱；
3. **zoom=18 时 1 像素 = 1 米**，每降一级分辨率翻倍（zoom=12 → 64 米/像素）。

反证方法（可复现，已固化进测试）：

```text
1. 请求 staticimage/v2，center=113.65,34.76&zoom=12&width=256&height=256，并带 markers=113.70,34.80；
2. 再取一张完全相同但不带 markers 的图，两图做像素差分（阈值 12）；
   唯一连通的大块差异就是图钉本身，实测为 18x25 的色块；
3. 用同样方法在中心点打点：图钉 bbox 中心是 (127.5, 120)，而该点真实像素是 (127.5, 127.5)，
   得出「图钉 bbox 中心比锚点高 7.5 像素」；
4. 把第 2 步的 bbox 中心换算成锚点，实测约 (215.0, 44.0)；
   本项目公式给出 (215.x, 44.x)，误差 < 1.5 像素。
```

顺带记一条踩坑：`markers=` **只支持纯坐标**，加样式语法（如 `mid,0x00FF00|113.7,34.8`）会返回 154 字节的空图。
所以本项目**不使用百度图钉**，编号圆点全部由客户端自绘，视觉反而更统一。

## 4. 底图票据（为什么取图接口能免登录还不被刷）

实现见 `map/MapTicketService.java`。

- 底图接口 `/api/map/image` 是 `permitAll`：`CachedNetworkImage` 带不了 `Authorization` 头；
- 因此改用 **HMAC-SHA256 短时票据**：票据只对「同一组参数」有效，改中心点 / 缩放 / 尺寸立即失效（实测 403）；
- 票据**按整点分桶**签发，桶内 URL 完全一致 → 客户端的磁盘缓存仍然有效；
- 签发时给出两个桶的有效期，跨桶瞬间不会立刻失效；
- 票据里只有「参数签名 + 过期时间」，**不含用户身份，也不含 AK**；
- 响应带 `Cache-Control: public, max-age=…`（上限 1800 秒）。

## 5. 地理编码：什么坐标才敢画、才敢存

判据收敛在 `server/src/main/java/com/yujian/travel/map/PlaceTrust.java`，
**行程地图与运营台共用同一份**，避免出现「后台存得下、地图画不出」。

| 判据 | 规则 | 为什么 |
| --- | --- | --- |
| 主判据是 level，不是分数 | `国家/省/直辖市/城市/区县` 一律拒绝 | 百度对「随便走走」「asdfghjkl」会返回 `level=城市, confidence=20`（坐标是城市中心，画上去等于撒谎）；而白马寺、龙门石窟这类真实景点只给 25 分，却带 `level=乡镇` |
| confidence 只作兜底 | 低于 `BAIDU_MAP_MIN_CONFIDENCE`（默认 20）不采信 | 挡住明显异常的响应，不承担主判据职责 |
| 移动类描述拦截 | 含「前往/出发/返回/返程/抵达/换乘/乘车/自驾/路上/途经」或 `→` 的标题不打点 | 「郑州出发前往洛阳」曾被解析到一个村庄（conf=50） |
| 城市限定优先标题 | 标题自带城市时以标题为准 | 「洛阳博物馆」配郑州做限定会被解析到郑州市中心 |
| 必须有城市限定 | 没有城市（也没写在标题里）时**拒绝解析** | 实测「随便走走」不带城市限定会被解析到**深圳的一家餐厅**，`level=餐饮、confidence=80`，光看判据完全看不出问题 |
| 河南范围校验 | 落在 `110.0—117.0 / 31.0—36.6`（含约 30 公里外扩）之外一律拒绝，并回显实际落点 | 内容库只服务河南，跑到别的省份几乎一定是错的 |

另外两条产品纪律：

- 内容库坐标优先（`coordinateSource=景点库坐标（运营台维护）`，confidence=100）；只有内容库没坐标时才走地理编码；
- 低可信度不假装板上钉钉：confidence < 60 时提示「可信度偏低，请在地图上核对后再保存」。

## 6. 降级口径（什么时候变成文字路线）

以下情况**一律返回** `fallback=true` + 一句人话原因，客户端换成文字路线，不留空白：

| 情况 | message 示例 |
| --- | --- |
| 未配置 AK | 服务端未配置百度地图 AK，地图暂不可用，已切换为文字路线。 |
| 没有任何可信坐标 | 没有解析到可信的站点坐标，已切换为文字路线。 |
| 取底图失败（配额/鉴权/超时） | 底图暂时拉取失败（…），已切换为文字路线。 |
| 行程没有任何一天 | 这份行程还没有安排任何一天，暂时没有可展示的路线。 |

服务端会**先自己取一次底图**，取到才把 URL 下发：这样不会出现「接口成功、客户端裂图」的半失败状态。

## 7. 客户端实现

组件：`flutter_app/lib/screens/journey/route_map_card.dart`（插在时间轴之前），模型：`lib/models/map_models.dart`。

| 能力 | 做法 |
| --- | --- |
| 日期切换 | chip 切换当日；切天即重新取快照 |
| 拖动 | 本地平移跟手 → 松手把像素位移交给服务端重投影 |
| 缩放 | 双指 + `±` 按钮；「回到全览」复位到服务端自动框选的视窗 |
| 点选站点 | 点标记 → 定位到时间轴对应节点（时间轴高亮用色 + 文字双重表达，不靠颜色单一通道） |
| 未打点清单 | 明确列出「哪一条没打点 + 为什么」，而不是悄悄丢掉 |
| 出处与局限 | 右下角常驻「静态底图·不含实时路况」，刻意避开左下角的百度水印 |
| 兜底 | 没有底图时把当天安排按时间排成一份仍然可读的文字路线 |

## 8. 运营台坐标维护

地图能不能打点，取决于内容库里有没有可信坐标，因此同批次把坐标做成运营能力：

| 项 | 说明 |
| --- | --- |
| 接口 | `POST /api/admin/pois/geocode`（ADMIN 专用，解析会消耗配额，不能给游客端） |
| 输入 | `{ name, city }` |
| 输出 | `{ query, cityHint, lng, lat, level, confidence, trusted, source, message }` |
| 只解析不落库 | 结果只回填表单，点「保存」才写库，可以放心反复试 |
| 不采信时不给半成品 | `trusted=false` 时 `lng/lat` **一律为 null** |
| 表单 | 景点表单新增经纬度（百度 BD09）+ 「按名称解析」+「清除」；列表新增「坐标」列（未配置时明确显示） |
| 前端校验 | 经纬度要么都填要么都留空；必须是数字；必须落在中国大陆范围内（经度 73—136、纬度 3—54） |

## 9. 配置项

```text
BAIDU_MAP_AK=                  # 只写服务端；为空时地图整体降级为文字路线
BAIDU_MAP_BASE_URL=https://api.map.baidu.com
BAIDU_MAP_STATIC_MAP_PATH=/staticimage/v2
BAIDU_MAP_CACHE_MINUTES=720    # 底图按天级更新，缓存久一点能省大量配额
BAIDU_MAP_WIDTH=1024           # 客户端请求会被收窄到 320—1024
BAIDU_MAP_HEIGHT=768
BAIDU_MAP_TIMEOUT_SECONDS=8    # 二进制大响应，比 JSON 工具宽松
BAIDU_MAP_MAX_MARKERS=12       # 单日打点上限，避免配额被一次规划打光
BAIDU_MAP_MIN_CONFIDENCE=20    # 兜底下限；主判据是 level
```

## 10. 验证证据

本机实测（命令可复现，注意先启动本地后端）：

```text
node scripts\verify-map.mjs    通过 23 项，失败 0 项
mvn -o -B test                 Tests run: 44, Failures: 0, Errors: 0
flutter analyze                No issues found
flutter test                   All tests passed (57)
flutter build apk --debug      app-debug.apk 181.0MB
```

覆盖到的关键断言：底图是真 PNG（102139 字节）、带 `max-age=1800`、
票据被改动即 403、换 zoom 即 403、重复取图字节一致（缓存命中）、
未登录访问快照 401、不存在的行程 404、非法中心点 400、
标记与折线数量一致、未打点条目都带原因、`fallback=false`。

人工目视复核：把服务端返回的标记合成到底图上，龙门石窟与洛阳博物馆的圆点精确落在百度地图对应位置。

外部调用遵循「最小有效测试」：解析坐标只实测两条（一条在本地被拒绝、不产生请求；一条产生 1 次地理编码调用）。

## 11. 已知局限与下一步

| 局限 | 说明 / 下一步 |
| --- | --- |
| 无实时路况 | 静态底图不含路况图层，界面已如实标注；若后续要路况，需要单独评估官方 SDK 与 AK 下发策略 |
| 拖动是「重取图」而非连续瓦片 | 有 720 分钟缓存兜底，配额可控；但弱网下拖动会有明显等待 |
| 单日最多 12 个点 | `BAIDU_MAP_MAX_MARKERS`，超出部分进「未打点」清单并说明原因 |
| 内容库坐标需要逐条补齐 | 预置 4 个景点有坐标；运营台新增景点需点一次「按名称解析」并核对，否则该景点不会打点 |
| 地图只有河南范围校验 | 不会画出外省坐标（这是刻意的），因此这份地图天然只服务本项目的内容范围 |

## 12. 相关文件

```text
server/src/main/java/com/yujian/travel/map/WebMercator.java              投影与反投影
server/src/main/java/com/yujian/travel/map/MapTicketService.java        票据签发与校验
server/src/main/java/com/yujian/travel/map/PlaceTrust.java              可信地点判据（地图与运营台共用）
server/src/main/java/com/yujian/travel/api/MapController.java           三个地图端点
server/src/main/java/com/yujian/travel/service/MapSnapshotService.java  快照、打点、降级
server/src/main/java/com/yujian/travel/service/PoiGeocodeService.java   运营台解析坐标
server/src/main/java/com/yujian/travel/infrastructure/external/baidu/BaiduStaticMapClient.java
flutter_app/lib/models/map_models.dart
flutter_app/lib/screens/journey/route_map_card.dart
admin/src/views/PoisView.vue                                           坐标字段与「按名称解析」
scripts/verify-map.mjs                                                 端到端验证脚本
```
