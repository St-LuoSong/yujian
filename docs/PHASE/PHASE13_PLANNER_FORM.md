# 阶段十三（T13）：出行条件表单重做 + 历史行程

日期：2026-10-02
触发：模拟器实测截图，七条具体问题

## 1. 用户提出的七个问题

| # | 问题 | 现状 | 影响 |
| --- | --- | --- | --- |
| 1 | 出行日期是英文的 | 用的是 Material `showDatePicker`，弹出 `Sat, Oct 3 / October 2026 / CANCEL / OK` | 与全中文界面割裂 |
| 2 | 兴趣 / 体力选中后字看不见 | `FilterChip` / `ChoiceChip` 在 M3 下的选中色由组件推断，深底配深字 | 功能不可用 |
| 2 | 兴趣 / 体力不能自定义 | 只有固定几个选项 | 真实需求填不进去 |
| 3 | 同行人数占两行 | 成人、儿童各占一个 56 高的整行 | 表单被无意义拉长 |
| 4 | 交通方式展开是没样式的矩形列表 | `DropdownButtonFormField` 的默认弹层 | 展开前后不像同一个产品 |
| 5 | 行程天数是 Slider | 可拖范围 1—3 天，停在中点说不清选了几 | 无法自定义，和需求相反 |
| 6 | 出发地 / 目的地是两组胶囊 | 四个写死的出发城市 + 三个目的地 | 省外游客用不了；没有交换入口 |
| 7 | 历史行程只剩最近一份 | 列表接口读了 `items.first`，其余行程没有入口 | 数据在库里，用户找不回来 |

## 2. 逐条处理

### 2.1 中文日历（问题 1）

新增 `core/widgets/date_picker_sheet.dart`，换掉 `showDatePicker`。

**为什么不是加 `flutter_localizations`**：它依赖的 `intl` 不在本项目的离线 pub 缓存里
（`D:\DESKTOP\ProWeb\.pub-cache`），加进 `pubspec.yaml` 会让 `flutter pub get` 直接失败。
为了一个弹层引入一个装不上的依赖不划算，所以日历自己做：

- 全中文：`2026年10月` 月份标题、`一 二 三 四 五 六 日` 表头、`取消 / 确定`；
- 快捷入口「今天 / 明天 / 后天 / 下周六」，落在同一天的自动合并（周五的「明天」就是「下周六」）；
- 固定六行网格，切月份不会因为行数变化而跳动；
- 过去日期与超出范围的日期置灰，今天用描边 + 加粗双重信号。

### 2.2 中文日期口径（问题 1 的根）

新增 `core/formatters/chinese_date.dart`，是中文日期与时间的**唯一实现**：

```text
formatChineseDate         2026年10月3日 周六
formatChineseDateCompact  10月3日 周六        （半宽控件）
formatChineseMonth        2026年10月          （日历标题）
relativeDayLabel          今天 / 明天 / 后天
formatChineseTimestamp    今天 20:15 / 昨天 09:30 / 10月2日 20:15
```

时间戳一律先 `toLocal()`：服务端给的是 UTC Instant，直接显示会出现"晚上八点存的行程写成中午十二点"。

### 2.3 选择胶囊（问题 2）

新增 `core/widgets/form_controls.dart` 里的 `SelectChip`，**不再使用 Material 的 Chip**。

原因写在组件注释里：`ChoiceChip` / `FilterChip` 在 M3 下的选中底色与文字色分别取自
colorScheme 的不同角色，主题里只改其中一个（原来设了 `secondaryLabelStyle`）就会出现
深底 + 深字。`SelectChip` 把两种状态的前景色和背景色**成对写死**，对比度不再依赖组件推断：

- 未选中：白底 + 浅边框 + 深灰字；
- 选中：天青深底 + 宣纸白字，多选额外补一个对勾；
- 语义上带 `Semantics(selected:)`，读屏能读出选中状态。

### 2.4 自定义兴趣 / 体力（问题 2）

`_ChipGroup` 在每组末尾固定一个「自定义」胶囊，点开在**胶囊组下方独立成行**展开输入框。

不把输入框塞进 `Wrap` 的原因：一个较长的自定义值会把最后一行胶囊挤得重新折行，
输入框自己也会随字数变形。独立成行之后，无论加多少值，胶囊区只是多折一行。

自定义值存在页面状态（`_customInterests` / `_customPaces`）而不是组件内部，
所以卡片折叠再展开、生成方案之后再回来，用户自己加的值都还在。

### 2.5 同行人数一行（问题 3）

`_TravelersRow`：一个圆角容器里放两组「标签 + − 数字 +」，中间一道细分隔线。
`−` / `+` 是 32 直径的自绘按钮（不用 `IconButton` 的 48 最小尺寸），
整条高度 40。原先两条各 56 的灰条被压成一条。

### 2.6 交通方式（问题 4）

新增 `core/widgets/option_sheet.dart`：`PickerField`（收起态）+ 底部弹层（展开态）。

- 收起态展示的就是最终会被提交的那个字符串；
- 展开态每一项有一行**代价说明**（「自驾」意味着停车与油费），选中项青底 + 勾；
- 点一项立刻选中并回填，不存在"展开前和展开后对不上"。

### 2.7 行程天数（问题 5）

`_DayInput`：`−  2 天  +`，中间是可输入的 `TextField`。

- 拿到焦点自动全选，敲一下就能替换；
- 范围 1—7，与后端 `PlanDates.resolveDays` 的 `MAX_DAYS` 一致（两边不同步会出现
  "填了 10 天、出来 7 天"）；
- 输入越界**当场夹回并把框里的字一起改掉**，而不是等生成完才发现；
- 失焦时把文字拉回真实值，杜绝"框里写着 9、实际按 2 天生成"。

### 2.8 出发地 ⇄ 目的地（问题 6）

新增 `core/widgets/route_selector.dart`：左右两栏大字城市名，中间一个环形箭头。

- 点箭头真的交换两侧的值；
- 交换动画是**方向性**的：左侧的字往右滑走、右侧的字往左滑进来，
  方向就是值移动的方向，而不是让两个地名瞬间对调；
- 箭头每点一次转半圈（`Icons.sync` 是二重对称图形，转 180° 与自身重合，看不到回弹）；
- 系统开启"移除动画"时只换值不转圈。

城市选择弹层 `core/widgets/city_picker_sheet.dart` 参考 12306 的「选择出发」：

- 顶部搜索框（可清空）；
- 最近使用（本次会话选过的城市，最多 6 个）；
- 热门推荐（河南 12 城，3 列网格）；
- 河南省内按拼音首字母分组（A/H/J/K/L/N/P/S/X/Z）+ 右侧字母索引，点击滚动到分组；
- 省外热门 18 城——河南本地的产品也得让省外游客找得到自己从哪里出发；
- 搜不到时给一个「使用『XX』」的出口，省外小地名与县级市不会被挡住。

另外补了一条规则：**选成与另一边相同的城市时两边直接对调**，而不是留下一份"从郑州到郑州"。

### 2.9 历史行程（问题 7）

`TripHomeScreen` 原来只读 `list.items.first`，生成了第二份方案之后第一份就没有入口了。
现在：

- `_TripHomeData` 持有全部 `items`；
- 顶部仍是"下一站"卡片（只对最近一份拉 `/today`，其余行程不需要）；
- 下面新增「全部行程 · 共 N 份」列表，每行给出标题、天数、人均、强度、数据状态、更新时间；
- 点任意一行拉取该行程详情并打开 `TripScreen`；
- 只有正在打开的那一行显示进度，不整页盖遮罩。

## 3. 改动文件

```text
新增  flutter_app/lib/core/formatters/chinese_date.dart
新增  flutter_app/lib/core/widgets/form_controls.dart        FieldLabel / PickerField / SelectChip / SheetHandle
新增  flutter_app/lib/core/widgets/date_picker_sheet.dart     中文日历弹层
新增  flutter_app/lib/core/widgets/option_sheet.dart          通用单选弹层
新增  flutter_app/lib/core/widgets/city_picker_sheet.dart     城市选择弹层
新增  flutter_app/lib/core/widgets/route_selector.dart        出发地 ⇄ 目的地
改    flutter_app/lib/screens/planner_screen.dart             条件卡重排 + 城市/日期/交通/天数接线
改    flutter_app/lib/screens/additional_screens.dart         历史行程列表
新增  flutter_app/test/screens/planner_conditions_test.dart   13 个用例
```

## 4. 验证

```text
flutter analyze                       No issues found
flutter test                          全部通过（新增 13 个用例）
flutter build apk --debug             build/app/outputs/flutter-apk/app-debug.apk
node scripts\normalize-crlf.mjs --check   OK
```

新增用例覆盖：中文日期口径（4）、同行人数同行（1）、天数输入与夹取（1）、
自定义兴趣（1）、交通弹层联动（1）、中文日历弹层（1）、起终点交换（1）、
同城自动对调（1）、城市选择器搜索与自定义（1）、历史行程列表与打开（1）。

## 5. 仍然没做的

- 历史行程没有"删除 / 重命名 / 归档"入口（后端有 `DELETE /api/trip-plans/{id}`，界面未接）；
- 城市选择器的"最近使用"只活在本次会话，没有落本地存储；
- 兴趣 / 体力自定义值没有进后端词表，只随这一次请求的 `interests` / `pace` 字段上传。
