import 'package:flutter/material.dart';

import '../formatters/chinese_date.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'form_controls.dart';

/// 打开中文日期弹层，返回用户确认的日期；取消返回 null。
///
/// 这里换掉了 Material 的 `showDatePicker`。原因是实机弹出的是
/// 「Sat, Oct 3 / October 2026 / CANCEL / OK」——项目没有引入
/// `flutter_localizations`（离线 pub 缓存里没有它依赖的 intl），
/// Material 自带的日期组件就只有英文一种写法。
///
/// 与其为了一个弹层把本地化依赖加回来，不如把日历做成产品自己的一套语言：
/// 全中文、和卡片同一个圆角与配色，顺带补上「今天 / 明天 / 后天 / 下周六」
/// 四个快捷入口——旅行日期大多是这几天，翻日历反而是多余的步骤。
Future<DateTime?> showChineseDateSheet(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String title = '选择出行日期',
}) {
  final DateTime first = dateOnly(firstDate ?? DateTime.now());
  final DateTime last = dateOnly(lastDate ?? DateTime.now().add(const Duration(days: 365)));
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) => _DateSheet(
      initialDate: initialDate,
      first: first,
      last: last,
      title: title,
    ),
  );
}

class _DateSheet extends StatefulWidget {
  const _DateSheet({
    required this.initialDate,
    required this.first,
    required this.last,
    required this.title,
  });

  final DateTime initialDate;
  final DateTime first;
  final DateTime last;
  final String title;

  @override
  State<_DateSheet> createState() => _DateSheetState();
}

class _DateSheetState extends State<_DateSheet> {
  /// 每周的第一列是周一，和国内的日历习惯一致。
  static const List<String> _weekdayHeader = <String>['一', '二', '三', '四', '五', '六', '日'];

  /// 固定六行。月份之间行数会差一行，高度跟着跳会让切换月份显得毛躁。
  static const int _gridCells = 42;

  late DateTime _selected;
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _selected = _clamp(dateOnly(widget.initialDate));
    _month = DateTime(_selected.year, _selected.month);
  }

  DateTime _clamp(DateTime value) {
    if (value.isBefore(widget.first)) {
      return widget.first;
    }
    if (value.isAfter(widget.last)) {
      return widget.last;
    }
    return value;
  }

  bool get _canGoPrevious =>
      DateTime(_month.year, _month.month).isAfter(
        DateTime(widget.first.year, widget.first.month),
      );

  bool get _canGoNext => DateTime(_month.year, _month.month).isBefore(
        DateTime(widget.last.year, widget.last.month),
      );

  void _shiftMonth(int delta) {
    setState(() => _month = DateTime(_month.year, _month.month + delta));
  }

  void _select(DateTime day) => setState(() => _selected = _clamp(day));

  /// 快捷入口。落在可选范围外的直接不显示，不做「置灰的今天」这种摆设。
  List<MapEntry<String, DateTime>> get _shortcuts {
    final DateTime now = todayDate();
    final int delta = (DateTime.saturday - now.weekday + 7) % 7;
    final List<MapEntry<String, DateTime>> all = <MapEntry<String, DateTime>>[
      MapEntry<String, DateTime>('今天', now),
      MapEntry<String, DateTime>('明天', now.add(const Duration(days: 1))),
      MapEntry<String, DateTime>('后天', now.add(const Duration(days: 2))),
      MapEntry<String, DateTime>(
        '下周六',
        now.add(Duration(days: delta == 0 ? 7 : delta)),
      ),
    ];
    final Set<String> seen = <String>{};
    final List<MapEntry<String, DateTime>> visible = <MapEntry<String, DateTime>>[];
    for (final MapEntry<String, DateTime> entry in all) {
      final DateTime day = dateOnly(entry.value);
      if (day.isBefore(widget.first) || day.isAfter(widget.last)) {
        continue;
      }
      if (seen.add(day.toIso8601String())) {
        visible.add(MapEntry<String, DateTime>(entry.key, day));
      }
    }
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    final String? relative = relativeDayLabel(_selected);
    final String selection = relative == null
        ? '已选 ${formatChineseDateCompact(_selected)}'
        : '已选 ${formatChineseDateCompact(_selected)} · $relative';
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            10,
            AppSpacing.page,
            16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SheetHandle(),
              const SizedBox(height: 16),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: AppTypography.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                selection,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final MapEntry<String, DateTime> entry in _shortcuts)
                    SelectChip(
                      label: entry.key,
                      selected: dateOnly(entry.value) == _selected,
                      onTap: () => _select(entry.value),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _monthHeader(),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  for (final String label in _weekdayHeader)
                    Expanded(
                      child: Center(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            fontWeight: FontWeight.w600,
                            color: AppColors.crackle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              _grid(),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selected),
                      child: const Text('确定'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _monthHeader() => Row(
        children: <Widget>[
          IconButton(
            onPressed: _canGoPrevious ? () => _shiftMonth(-1) : null,
            tooltip: '上一个月',
            icon: const Icon(Icons.chevron_left, size: 22),
          ),
          Expanded(
            child: Center(
              child: Text(
                formatChineseMonth(_month),
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _canGoNext ? () => _shiftMonth(1) : null,
            tooltip: '下一个月',
            icon: const Icon(Icons.chevron_right, size: 22),
          ),
        ],
      );

  Widget _grid() {
    final DateTime firstOfMonth = DateTime(_month.year, _month.month);
    // 周一为第一列：weekday 里周一是 1，正好等于要空出来的格子数减去 1。
    final int leading = firstOfMonth.weekday - 1;
    final int daysInMonth =
        DateTime(_month.year, _month.month + 1, 0).day;
    final DateTime today = todayDate();

    final List<Widget> cells = <Widget>[];
    for (int i = 0; i < leading; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (int day = 1; day <= daysInMonth; day++) {
      final DateTime date = DateTime(_month.year, _month.month, day);
      cells.add(
        _DayCell(
          date: date,
          selected: date == _selected,
          isToday: date == today,
          enabled: !date.isBefore(widget.first) && !date.isAfter(widget.last),
          onTap: () => _select(date),
        ),
      );
    }
    while (cells.length < _gridCells) {
      cells.add(const SizedBox.shrink());
    }

    return GridView(
      shrinkWrap: true,
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        mainAxisExtent: 42,
      ),
      children: cells,
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  final DateTime date;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background =
        selected ? AppColors.celadonDeep : Colors.transparent;
    // 状态不只靠颜色：今天有描边，选中是实心，两者都可以没有颜色也能分辨。
    final Color foreground = !enabled
        ? AppColors.crackle.withValues(alpha: 0.45)
        : selected
            ? AppColors.onInk
            : isToday
                ? AppColors.celadonDeep
                : AppColors.ink;
    final BorderSide outline = !selected && isToday && enabled
        ? const BorderSide(color: AppColors.celadon, width: 1.5)
        : BorderSide.none;

    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: formatChineseDate(date) + (isToday ? '，今天' : ''),
      child: Center(
        child: SizedBox(
          width: 38,
          height: 38,
          child: Material(
            color: background,
            shape: CircleBorder(side: outline),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: enabled ? onTap : null,
              child: Center(
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: selected || isToday
                        ? FontWeight.w700
                        : FontWeight.w500,
                    color: foreground,
                    fontFeatures: AppTypography.tabularFigures,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

