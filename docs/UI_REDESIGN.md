# UI 重设计记录

日期：2026-10-01（Asia/Shanghai）

## 资料边界

用户在本轮提供了 `D:\DESKTOP\ProWeb\UI设计.md`，但该路径在工作区中不存在，读取返回 ENOENT，因此本轮没有把它当作已读取的约束。实际审查依据是：

- `D:\DESKTOP\ProWeb\UI预览图\1.png` 至 `4.png` 的模拟器截图；
- 当前 Flutter 页面实现；
- `frontend-design`、`ui-visual-composition`、`interaction-patterns-components`、`ux-usability-foundations` 设计技能约束；
- 之前已经冻结的产品计划、数据状态和移动端尺寸规范。

## 截图审查结论

原界面存在这些具体问题：

1. **首页**：品牌区、英雄区、走廊区、景区区、底部导航都在使用相似的直角/浅描边块，层级没有拉开；景区横滑卡片像模板轮播，真正的河南内容反而被裁切在窄卡片里。
2. **规划页**：大面积留白；输入、信息块和 CTA 的视觉权重接近；“AI 旅行规划”与魔法棒图标制造了明显的 AI 产品模板感；操作完成后没有足够的结果依据。
3. **行程页**：节点虽然有时间轴，但节点内容仍然是卡片化文本堆叠；来源/状态重复出现；预算与天气是独立装饰块，和“为什么这份计划走得通”没有形成整体关系。
4. **我的 / 空行程页**：空状态只有一段说明与一个按钮，页面大面积空白，缺少“为什么值得保存”“最近状态”“下一步”这类有助于回到主任务的引导。
5. **交互**：多个入口此前是视觉按钮或空操作；信息状态靠颜色和固定标签表达；网络/Mock/缓存的边界没有在第一眼讲清楚。

## 新视觉方向

> **天地之中 · 行程是一条测量过的线。**

设计材料不再是泛化的“古建 + 印章 + 米色”，而是来自河南的具体对象：汝瓷天青、登封测影、龙门窟龛、郑州列车运行图。

### 设计语言

- 行程：时间轴 + 刻度 + 数字对齐；
- 景区库：两列窟龛图块；
- 首页：一句话规划入口 + 走廊测量账 + 窟龛网格；
- 详情：图片只属于景区，事实用标签-值列表；
- 状态：色块小钥匙 + 文字，不重复给每个节点刷徽标；
- 颜色：釉白 `#EFF1EE`、匣钵墨 `#1B2422`、天青 `#3F6F6A`、天青淡 `#C9D8D3`、开片灰 `#7C8B87`、窑变朱 `#A8341E`；
- 窑变朱在单屏原则上只出现一次，只表示当前位置、下一站或高风险；
- 不引入网络字体，数字启用等宽数字特性，让时间、价格、里程能对齐。

## 实现文件

- `flutter_app/lib/core/theme/app_colors.dart`
- `flutter_app/lib/core/theme/app_spacing.dart`
- `flutter_app/lib/core/theme/app_typography.dart`
- `flutter_app/lib/core/theme/app_theme.dart`
- `flutter_app/lib/core/widgets/route_gauge.dart`
- `flutter_app/lib/core/widgets/niche_tile.dart`
- `flutter_app/lib/core/widgets/section_rule.dart`
- `flutter_app/lib/core/widgets/measure_value.dart`
- `flutter_app/lib/core/widgets/key_value_row.dart`
- `flutter_app/lib/core/widgets/data_status_badge.dart`
- `flutter_app/lib/screens/home_screen.dart`
- `flutter_app/lib/screens/planner_screen.dart`
- `flutter_app/lib/screens/trip_screen.dart`
- `flutter_app/lib/screens/additional_screens.dart`

## 本轮验证

```text
flutter analyze              -> No issues found
flutter test                 -> All tests passed (26)
flutter build apk --release  -> Built app-release.apk (51.3MB)
```

模拟器预览由用户自行安装 APK 验证。本轮不伪造设备截图结论；用户反馈的问题将作为下一轮视觉修正输入。

---

# v0.3：推翻 v0.2 的线框风，回到"现代中原文化 × 山河旅行影像"

日期：2026-10-01（Asia/Shanghai）

## 1. 为什么必须重做

用户把 v0.2 装进模拟器后给了四条具体反馈，逐条都能对上代码：

| 用户反馈 | v0.2 的实际做法 | 结论 |
| --- | --- | --- |
| "AI 味太重了" | 冷釉白 + 零圆角 + 细线分栏 + 密集排版 | v0.2 在"避免暖米色 AI 味"时落进了另一个生成式默认：**杂志式线框风**。DESIGN_DIRECTION 第 4 节自己就预警过这条风险，结果真的踩了 |
| "组件边界几乎都是直角" | `radiusCard` 等圆角 Token 被压到 0–4px | 全直角在移动端既不像消费级 App，也让"可点"和"只是分隔线"难以区分 |
| "布局怪怪的" | 首页是"走廊刻度带 + 窟龛网格"的编辑排版 | 编辑式排版适合 iPad/桌面，不 适合 360dp 竖屏拇指操作 |
| "交互性不强" | 关掉了 `InkSparkle`，多个入口是视觉按钮 | 点按没有水波、没有缩放、没有状态反馈 = 交互生硬 |

v0.2 的问题不是配色不好看，而是**把设计语言的抽象层级选错了**：它把"测量"当成界面结构，
于是每个模块都要用线来表达关系，页面自然变成线框图。

## 2. v0.3 的设计方向

> **现代中原文化 × 山河旅行影像 × 实测路线**

河南特征重新回到"看得见"的层面而不是"结构"层面：

- **影像**：景区大图是第一信息载体（首页 Hero、走廊卡、景区卡、日卡封面）；
- **色彩**：釉白、匣钵墨、汝瓷天青、窑变朱、麦穗金——克制的冷调青绿打底，
  朱只用于价格与风险，金只用于价格数字；
- **信息**：行程用时间轴承载，预算用比例条承载，天气与强度用可解释的行承载。

### 2.1 颜色

| 用途 | v0.2 | v0.3 |
| --- | --- | --- |
| 底色 | 釉白 `#EFF1EE` | 釉白 `#F1F3EF` |
| 主文字/深色面 | 匣钵墨 `#1B2422` | 匣钵墨 `#16211F` |
| 品牌主色 | 天青 `#3F6F6A` | 天青 `#2F6F68` + **天青深 `#1C4B46`**（品牌深色面） |
| 强调 | 窑变朱 `#A8341E` | 窑变朱 `#B23A22` |
| 价格 | — | 麦穗金 `#B98A3C`（**仅价格**） |
| 深度 | 无 | `cardShadow` / `chipShadow` 软阴影 |

### 2.2 形状与间距

```text
radiusCard     18   分组单元（SurfaceCard）
radiusControl  14   按钮、输入框、下拉
radiusSmall    10   缩略图、小标签
radiusPill     999  场景 Chip、状态标签
heroHeight     258  首页主视觉
photoHeight    132  景区卡图片
```

### 2.3 动效与反馈

- 重新打开 `InkSparkle`（v0.2 关闭它是"交互生硬"的直接原因之一）；
- 新增 `PressScale`：按下缩放，用 `Listener` 实现，**不吞掉点击事件**；
- `CardTheme` / `BottomSheetTheme` / `DialogTheme` 统一圆角与阴影；
- 指标与图片加载不再用无限动画掩盖等待（详见第 5 节）。

## 3. 信息架构：规划与行程合并

用户指出"规划和行程明明一个功能，用不着分开"。v0.3 采纳：

```text
v0.2  底部 4 项：发现 / 规划 / 行程 / 我的     规划页与行程页各自维护一套输入与状态
v0.3  底部 3 项：发现 / 行程 / 我的             条件卡 → 生成 → 结果，同一页内完成
```

- `planner_screen.dart` 重写为 `JourneyScreen`；
- 进入时自动恢复最近方案，避免"我明明规划过却看到空表单"；
- 已有方案时条件卡折叠成一行摘要，需要改条件再展开；
- `trip_screen.dart` 从 1003 行缩到 86 行，只负责取数据与错误态，
  渲染统一交给新的 `screens/journey/trip_result_view.dart`。

## 4. 组件与页面落地

### 4.1 新增组件

| 文件 | 作用 |
| --- | --- |
| `core/widgets/surface_card.dart` | 白卡 + 大圆角 + 软阴影，唯一的分组单元 |
| `core/widgets/press_scale.dart` | 按下缩放反馈 |
| `core/widgets/photo_plate.dart` | 固定高度图 + 渐变 scrim + 主题化失败占位（山河渐变，不是灰块） |
| `core/widgets/tag_pill.dart` | `TagTone{neutral,brand,risk,caution,settled,sand}` 全圆角标签 |
| `core/widgets/stat_tile.dart` | KPI 瓦片，等宽数字 |
| `core/widgets/section_header.dart` | 标题 + 副标题 + trailing，取代 v0.2 的分隔细线 |
| `screens/journey/day_card.dart` | 逐日卡 + 四项风险行 + 时间轴 |
| `screens/journey/trip_result_view.dart` | 结果页统一渲染 |
| `screens/account_screen.dart` | 独立登录/注册页 |

### 4.2 逐日风险行：`deriveDayRisks()`

参考用户提供的行程卡样式，每张日卡底部固定四行：天气 / 体力 / 距离 / 开放。

关键约束：**四项全部由方案里已有的字段推导，缺证据时如实标"未获取"，不标"低风险"。**
例如没有天气数据时显示"未获取"，而不是绿色的"适宜"——这条和全项目的降级口径一致。

时间轴 `_StopRail` 用 `Stack` 画竖线，避开了 `IntrinsicHeight` 在长列表里的性能问题。

### 4.3 行程结果页

- 深色汇总卡：行程主题 / 总费用与结余 / 跨城交通 / 最高风险 / 只读分享；
- 冲突提示：直接说明"为什么这份计划走得通"，而不是只给一段好看的文案；
- 动态调整卡：5 个预设 ActionChip + 撤销 + 变化明细（改了什么、费用与强度怎么变）；
- 预算拆解用比例条（不用饼图）；
- 「方案依据」用 `ExpansionTile` 懒加载 trace，避免打开页面就打一堆请求。

### 4.4 登录页

v0.2 的"我的"页是一个直白表单。v0.3：

- 深色 Hero 说明注册能得到什么，而不是先摆输入框；
- **动画双段切换器**（登录/注册）代替文字链接；
- 密码显隐、字段级错误、`AnimatedSize` 切换，切换不跳版；
- 隐私声明就近展示。

## 5. 本轮修掉的两个真实缺陷

两个问题都是"改完主流程以后才暴露"的，值得记下来。

### 5.1 运营台上传的图片在手机上加载不出来

运营台在桌面浏览器上传景区图片，后端按上传者主机推导出
`http://localhost:8080/media/...`。浏览器里正常，模拟器里 `localhost` 是模拟器自己，
图片必然失败。

修法见 `docs/PHASE10_RAILWAY_AND_TICKETS.md` 第 3.1 节：
在 `AppConfig.resolveMediaUrl()` 重写回环主机，接入点是所有景点必经的
`TravelRepository._reachablePhoto()`。

### 5.2 图片占位符的无限动画会卡住布局测试

`PhotoPlate` 改用 `CachedNetworkImage` 做磁盘缓存后，
`test/layout/phone_layout_test.dart` 立刻出现 `pumpAndSettle timed out`。

原因：未知进度时渲染的 `CircularProgressIndicator(value: null)` 是**不确定动画**，
它会一直调度新帧，`pumpAndSettle` 永远等不到收敛。

修法不是放宽测试，而是改设计：**只在拿到真实进度时才画进度环**，
未知长度时只显示渐变占位。这样既没有"假装在动"的动画，测试也能收敛。

顺带收益：图片现在走磁盘缓存，已经看过的景区在弱网或断网时仍然显示，
直接补上了"弱网可用"这条要求。

## 6. 本轮验证

```text
flutter analyze              -> No issues found
flutter test                 -> All tests passed (54)
flutter build apk --debug    -> app-debug.apk   (180.9MB)
flutter build apk --release  -> app-release.apk (53.4MB)
```

`test/layout/phone_layout_test.dart` 已按新导航重写，
覆盖 360 / 390 / 412 dp × 发现 / 行程 / 我的+登录 / 保存行程，
每个宽度都会滚到底并展开"方案依据"卡。

模拟器预览仍由用户自行安装验证。**本轮没有伪造任何设备截图结论。**

## 7. 遗留

- 首页与景区图仍使用外链示例图，正式版需替换为有授权的河南实景照片；
- 地图 Tab（可视化路线）尚未实现，保留文字化路线；
- 系统字体放大 1.3 倍的实机表现仍待用户确认（自动化里已覆盖，真机未验证）。
