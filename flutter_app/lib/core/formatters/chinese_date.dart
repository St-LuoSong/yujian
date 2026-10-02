/// 中文日期与时间的唯一实现。
///
/// 这个项目**没有**引入 `flutter_localizations`：它依赖的 `intl` 不在离线
/// pub 缓存里，加上去 `flutter pub get` 会直接失败，所以中文日期不作为本地化
/// 框架的一部分，而是收成一个纯函数模块。表单、日历弹层、历史行程列表都从这里取，
/// 同一个日期在界面上只有一种写法。
///
/// 时区口径：全部按设备本地时区展示。服务端给的是 UTC Instant，
/// 展示前一定先 `toLocal()`，否则晚上八点存的行程会显示成中午十二点。
library;

const List<String> _weekdayNames = <String>['一', '二', '三', '四', '五', '六', '日'];

/// 去掉时分秒，只留年月日。日期比较与求差都先过这一层。
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 今天的零点。传入 `now` 只为测试可注入，业务代码不要传。
DateTime todayDate([DateTime? now]) => dateOnly(now ?? DateTime.now());

/// 「周一」…「周日」
String chineseWeekday(DateTime date) => '周${_weekdayNames[date.weekday - 1]}';

/// 「2026年10月3日 周六」
String formatChineseDate(DateTime date) =>
    '${date.year}年${date.month}月${date.day}日 ${chineseWeekday(date)}';

/// 「10月3日 周六」——半宽控件里放不下年份时用这个。
String formatChineseDateCompact(DateTime date) =>
    '${date.month}月${date.day}日 ${chineseWeekday(date)}';

/// 「2026年10月」——日历弹层的月份标题。
String formatChineseMonth(DateTime month) =>
    '${month.year}年${month.month}月';

/// 距今天的自然日数，不看时分秒。今天为 0，昨天为 -1。
int daysFromToday(DateTime date, {DateTime? now}) =>
    dateOnly(date).difference(todayDate(now)).inDays;

/// 「今天 / 明天 / 后天」，超过这个范围返回 null（由调用方决定要不要显示）。
String? relativeDayLabel(DateTime date, {DateTime? now}) =>
    switch (daysFromToday(date, now: now)) {
      0 => '今天',
      1 => '明天',
      2 => '后天',
      _ => null,
    };

/// 列表里的时间戳：「今天 20:15」「昨天 09:30」「10月2日 20:15」「2025年12月31日 20:15」。
///
/// 服务端 `updatedAt` 是 UTC Instant，这里统一转成本地时区再展示。
String formatChineseTimestamp(DateTime? value, {DateTime? now}) {
  if (value == null) {
    return '时间未知';
  }
  final DateTime local = value.toLocal();
  final DateTime reference = todayDate(now);
  final String clock = '${_pad(local.hour)}:${_pad(local.minute)}';
  final int offset = dateOnly(local).difference(reference).inDays;
  return switch (offset) {
    0 => '今天 $clock',
    -1 => '昨天 $clock',
    1 => '明天 $clock',
    _ when local.year == reference.year =>
      '${local.month}月${local.day}日 $clock',
    _ => '${local.year}年${local.month}月${local.day}日 $clock',
  };
}

String _pad(int part) => part.toString().padLeft(2, '0');
