# T39–T42：移动端溢出、社区消息、图片生命周期与 APK 图标

日期：2026-10-03（Asia/Shanghai）

## T39 真机右侧溢出修复

### 现象

在真实手机打开已生成行程时，时间轴节点右侧出现：

```text
RIGHT OVERFLOWED BY ... PIXELS
```

溢出集中在节点底部的来源与数据状态元信息。长文本被放进 `Wrap`，但子项没有收到
实际时间轴列宽约束；在系统字体放大或较窄设备上，标签按自然宽度绘制到屏幕外。

### 修复

- `_StopRow` 的来源标签和数据状态标签通过 `LayoutBuilder` 获取实际内容列宽；
- 两个元信息项分别限制最大宽度，无法并排时由 `Wrap` 换到下一行；
- `TagPill` 文本增加单行省略；
- 不整体缩小正文，不裁剪风险说明，不隐藏数据来源。

### 验证

```text
flutter analyze
  No issues found

flutter test test/screens/trip_result_overflow_test.dart
  All tests passed

flutter test test/layout/phone_layout_test.dart
  All tests passed（360 / 390 / 412dp）
```

新增回归用例使用 360dp 与 1.3 倍系统字体，并注入长来源、长数据状态和风险说明，
直接覆盖用户真机反馈的布局模式。

## T40 社区审核消息闭环

### 原缺口

管理员审核旅记后，作者只能再次打开「我的旅记」查看状态；消息中心没有真实业务事件。

### 落地

管理员将旅记审核为以下状态时，服务端写入该作者的消息中心：

| 状态 | 消息 |
| --- | --- |
| `APPROVED` | 你的旅记已通过审核 |
| `REJECTED` | 你的旅记未通过审核，并附审核说明 |
| `TAKEN_DOWN` | 你的旅记已被下架，并附审核说明 |

不新增推送Token、不申请通知权限、不采集设备标识；用户下次打开已有消息中心即可看到，
符合首版隐私最小化策略。

### 验证

```text
mvn -o -B -Dtest=CommunityServiceTest,MessageCenterServiceTest test
  Tests run: 7, Failures: 0, Errors: 0
```

## T41 社区图片生命周期清理

### 原缺口

删除旅记或编辑后移除图片时，服务端只解除了数据库引用，磁盘上的图片文件继续存在：

- 孤儿文件会持续占用服务器磁盘；
- 已删除内容的图片仍可通过 `/media/xxx.jpg` 直接访问。

### 落地

`CommunityService` 在删除与编辑两条路径上，都会对“本次不再被引用的图片”做引用检查，
确认没有其它旅记使用后才调用 `MediaStorageService.delete`。

| 场景 | 行为 |
| --- | --- |
| 删除旅记 | 清理该旅记独有图片；被其它旅记复用的保留 |
| 编辑移除图片 | 只清理本次被移除且无人引用的图片 |
| 外链图片 | `fileNameOf` 返回 null，不做本地删除 |
| 删除失败 | 只记日志，不影响用户操作成功 |

地址解析只接受本站 `/media/` 且不含路径分隔符的文件名，避免越权删除。

### 验证

```text
mvn -o -B test
  Tests run: 119, Failures: 0, Errors: 0
```

新增三条用例覆盖：删除清理、被复用不清理、编辑只清理被移除的那一张。

## T42 APK 图标与启动页

### 落地

以设计稿 `yujianlogo.png` 为唯一源图，生成：

| 资源 | 密度 |
| --- | --- |
| `mipmap-*/ic_launcher.png` | 48 / 72 / 96 / 144 / 192 |
| `mipmap-*/ic_launcher_foreground.png` | 108 / 162 / 216 / 324 / 432 |
| `drawable-*/splash_logo.png` | 132dp 启动页 logo |

自适应图标使用纯白背景 + 居中前景。前景按 68dp 生成：这是让字标
「豫见智旅」完整落在圆形安全区内的临界值；再大一点，纯圆形遮罩会裁掉字标两端。

源图同时归档到 `flutter_app/assets/brand/`（未在 pubspec 声明，不进入 APK）。

### 验证

```text
flutter build apk --debug
  Built app-debug.apk

APK 内容核对
  res/mipmap-anydpi-v26/ic_launcher.xml
  res/mipmap-*/ic_launcher.png（5 档）
  res/mipmap-*/ic_launcher_foreground.png（5 档）
  res/drawable-*/splash_logo.png（5 档）
```
