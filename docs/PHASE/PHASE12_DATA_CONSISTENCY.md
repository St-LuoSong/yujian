# T12 数据一致性修复：日期 / 时长 / 预算 / 地图口径

日期：2026-10-02（Asia/Shanghai）
触发：真机（模拟器）截图复核，方案能返回数据，但**细节数字对不上**。

> 这一轮修的不是"新功能"，而是四处**让用户不敢相信方案**的显示与口径缺陷。
> 每一处都可以在截图上指出具体位置，也都补了自动化用例锁住。

## 1. 四个缺陷与根因

| # | 截图上的现象 | 根因 |
| --- | --- | --- |
| 1 | 卡片标题写 `2026-10-02`，风险提示却写"**2026-10-01** 洛阳天气为小雨" | 客户端选了出发日期，但请求体里没有这个字段；服务端天气按写死的"周末"口径取，取了预报的第一天（今天）；模型又自己猜了日期 |
| 2 | 龙门石窟"约 **34** 小时"、洛阳博物馆"约 **23** 小时" | 时长解析把"3—4小时"里的非数字字符全删掉，`"3—4"` → `34` |
| 3 | 铁路节点"约 **2.0833333333333335** 小时"；体力风险"约 **59.1** 小时" | 格式化用 `minutes / 60.0` 直接拼双精度；风险雷达再叠加缺陷 2 被放大 |
| 4 | 预算拆解只有一条"**其他 ¥90 100%**"，明明有铁路与景点节点 | 分类用 `switch (stop.kind)` 硬匹配中文 `'交通'/'景点'/'餐饮'`，而模型返回的 `type` 是 `transport`/`attraction`，全部落进 default |

附带修掉的一处口径问题：地图卡的"**实时数据（23:49 更新）**"。
那张底图是**静态**底图 + 地理编码坐标，不含实时路况，那个时刻只是"用户打开地图的时间"。
现在状态是"系统资料"，不再把生成时刻伪装成数据新鲜度。

## 2. 服务端改动

| 文件 | 改动 |
| --- | --- |
| `service/PlanDates.java`（新增） | 统一日期口径：`today()`、`resolveStartDate()`（缺失/过去 → 明天）、`resolveDays()`（1—7，缺省 2）、`describe()`、`applyDates()` |
| `service/DurationText.java`（新增） | 时长解析与格式化的唯一实现：区间取上界、"2小时30分钟"分两段读、半天/全天/中文数字兜底、收敛到 5 分钟—12 小时；输出永远是"约2小时30分钟"，不出现小数 |
| `api/TravelModels.java` / `api/TravelController.java` | `PlanRequest` 与预览请求体增加 `startDate`（yyyy-MM-dd） |
| `api/TripPlanModels.java` | `CreateRequest` 增加 `startDate` |
| `tools/ToolOrchestrator.java` | 删掉 `DEFAULT_DATE = "周末"`；按出发日**逐日**查天气（`getWeather`、`getWeather:第2天`…），车次按出发日查 |
| `ai/PlanningPromptFactory.java` | 提示词写明"今天 / 出发日 / 结束日"，要求 `days.date` 落在该区间内，禁止引用区间外日期；要求 duration 用中文、cost 用整数、type 用中文 |
| `ai/TravelPlanningFacade.java` | 生成后、校验前调用 `PlanDates.applyDates()`：**日期由用户决定，不由模型决定** |
| `ai/TripPlanValidator.java` | 逐日检查降水风险，提示语带上城市与日期；`景点`计数不再只认中文 type |
| `infrastructure/external/weather/OpenMeteoWeatherClient.java` | 预报窗口按出发日计算（3—16 天）；**匹配不到那一天就降级，不再静默回退到今天** |
| `service/MapSnapshotService.java` | 地图数据状态由"实时数据"改为"系统资料"，来源写明"静态底图 + 地理编码（不含实时路况）" |

## 3. 客户端改动

| 文件 | 改动 |
| --- | --- |
| `data/repositories/travel_repository.dart` | `createPlan()` 增加 `startDate` 并写入请求体 |
| `screens/planner_screen.dart` | 提交规划时带上用户选的出发日期；`_formatDate` 提升为文件级函数，页头与请求体共用同一份格式化 |
| `models/travel_models.dart` | 新增 `StopCategory`：交通 / 景点 / 餐饮 / 住宿 / 活动 / 其他，兼容中文与英文 type，并支持按标题兜底 |
| `screens/journey/day_card.dart` | 时长解析支持"2小时30分钟"；新增 `formatMinutes`（绝不输出小数）；体力风险按"非交通节点"统计；节点行显示中文科目而不是 `attraction` |
| `screens/journey/trip_result_view.dart` | 预算拆解按 `StopCategory` 分科目；增加合计 / 人均 / 未计价节点；**总价为 0 时也保留预算上限对比** |
| `screens/journey/route_map_card.dart` | 地图状态不再带"（HH:mm 更新）" |

## 4. 验证

```text
cd server && mvn -o -B test          → Tests run: 60, Failures: 0, Errors: 0
cd flutter_app && flutter analyze    → No issues found!
cd flutter_app && flutter test       → All tests passed! (65)
cd flutter_app && flutter build apk --debug
                                     → build\app\outputs\flutter-apk\app-debug.apk
node scripts/normalize-crlf.mjs --check ...   → OK: 218 file(s) already CRLF
```

新增用例：

- `DurationTextTest`（6）："3—4小时"→240 分钟、`format(125)`→"约2小时5分钟"、半天/全天/中文数字/越界收敛；
- `PlanDatesTest`（7）：未来日期保留、过去日期不早于今天、缺失回退明天、`applyDates` 只改日期保留主题名；
- `TravelControllerPayloadTest`（2）：请求体里的 `startDate` 能被绑定；
- `TravelPlanningFacadeTest.daysFollowTheTravellersStartDate`：每天日期 = 出发日 + 第 N 天；
- Flutter `stop_category_test.dart`（8）：中英文 type 分类、标题兜底、交通节点不计入游玩节点、时长文案无小数。

## 5. 本轮**没有**做的事

- 没有跑一次真实 LLM 全链路生成（按"最小有效请求"原则省 token），日期与时长的修复由单元测试与 APK 构建保证；
- 景区配图仍是外链示例素材（含与景点不符的占位图），需要按管理台的图片上传流程逐条替换为有授权的河南实景图；
- 12306 席别票价仍未进入预算拆分（属于既有 P1 缺口，不是本轮回归）。
