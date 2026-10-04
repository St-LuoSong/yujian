# T43：元信息流组件与社区详情页重构

日期：2026-10-03（Asia/Shanghai）

## 一、横向溢出：为什么第二次还会出现

两次报错（34px、4.4px）表现形式不同，根因是同一个：

```text
Wrap / Row 给非弹性子项「无限宽」的主轴约束
+ 子项里是一段没有 maxLines/省略的 Text
= 文本按自然宽度绘制，直接画到手机外
```

第一次在行程时间轴的来源/状态标签；第二次在今日行程 `RouteGauge` 的
`_Unit`（`Row(mainAxisSize: min)` + 无约束 `Text`）。

## 二、结构性修复

新增 `lib/core/widgets/meta_flow.dart`：

| 组件 | 职责 |
| --- | --- |
| `MetaUnit` | 图标 + 文本的元信息单元，文本用 `Flexible` + 单行省略，**天然不会撑破父级** |
| `MetaFlow` | 统一承载元信息流的 `Wrap`，约定子项必须自带宽度收敛 |

调用侧改为：

- `RouteGauge._StopDetail` → `MetaFlow(children: [MetaUnit, MetaUnit, MetaUnit])`；
- `DayCard._StopRow` → `MetaFlow(children: [TagPill, DataStatusBadge])`；
- 删除旧的 `_Unit` 与页面内联的 `LayoutBuilder + ConstrainedBox`。

### 一个必须记录的实现约束

`MetaFlow` **不能**用 `LayoutBuilder` 实现。行程页的 `RouteGauge` 依赖
`IntrinsicHeight` 绘制轨道，而 `LayoutBuilder` 无法提供内在尺寸，
会在布局阶段直接抛 `LayoutBuilder does not support returning intrinsic dimensions`。
这一点由新增回归测试当场抓到，最终实现改为纯 `Wrap`。

## 三、社区详情页重构

参考朋友圈式的信息流表达，顺序调整为：

```text
作者栏（头像 / 昵称 / 发布时间 / 城市）
标题
正文
标签
图片宫格：1 张大图；2、4 张两列；其余三列
互动栏：点赞（真实）/ 收藏（待开放）/ 评论（待开放）
举报（访客）或 审核状态 + 获赞/浏览（作者）
```

交互补充：

- 宫格图片点击进入全屏查看器，支持左右滑动与双指缩放；
- `AppBackButton` 增加 `dark` 变体，深色底上仍保留显式返回出口；
- 作者模式不再展示点赞/举报按钮，改为只读的获赞与浏览数据；
- 收藏与评论**不放假数字**，如实标注「待开放」。

## 四、验证

```text
flutter analyze        No issues found
flutter test           All tests passed (157)
flutter build apk --debug
  Built app-debug.apk
```

新增两条回归用例：

- 今日行程元信息在 360dp + 1.3 倍字体 + 长来源下不横向溢出；
- 详情页 6 图宫格 + 互动栏在 360dp + 1.3 倍字体下不溢出。
