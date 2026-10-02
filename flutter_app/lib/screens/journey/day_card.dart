import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/data_status_badge.dart';
import '../../core/widgets/photo_plate.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/tag_pill.dart';
import '../../models/travel_models.dart';

/// How exposed one day of the plan is.
enum RiskLevel {
  low('低'),
  medium('中'),
  high('高'),

  /// The plan does not carry the evidence this row needs. Rendered in grey and
  /// worded as "未获取" — never silently upgraded to 低.
  unknown('未获取');

  const RiskLevel(this.label);

  final String label;

  static RiskLevel worst(Iterable<RiskLevel> levels) {
    RiskLevel result = RiskLevel.low;
    for (final RiskLevel level in levels) {
      if (_rank(level) > _rank(result)) {
        result = level;
      }
    }
    return result;
  }

  static int _rank(RiskLevel level) => switch (level) {
        RiskLevel.low => 0,
        RiskLevel.unknown => 1,
        RiskLevel.medium => 2,
        RiskLevel.high => 3,
      };
}

/// One row of 出行风险雷达.
///
/// [source] always names where the judgement came from, because the product
/// rule is that a derived assessment must never look like a measured one.
class RiskLine {
  const RiskLine({
    required this.icon,
    required this.title,
    required this.level,
    required this.reason,
    required this.source,
  });

  final IconData icon;
  final String title;
  final RiskLevel level;
  final String reason;
  final String source;
}

/// Derives the four risk rows for a day from the plan's own fields.
///
/// This is a presentation-layer reading of data the plan already contains, not
/// a new data source: weather is only reported when an item actually mentions
/// weather, distance only when a leg actually carries a mileage figure. When
/// the plan is silent the row says so.
List<RiskLine> deriveDayRisks(PlanDay day) {
  return <RiskLine>[
    _weatherRisk(day),
    _effortRisk(day),
    _distanceRisk(day),
    _openingRisk(day),
  ];
}

const List<String> _weatherWords = <String>[
  '雨',
  '雪',
  '大风',
  '强风',
  '高温',
  '低温',
  '降温',
  '寒潮',
  '雾',
];

RiskLine _weatherRisk(PlanDay day) {
  final List<String> hits = <String>[];
  for (final PlanStop stop in day.stops) {
    for (final String word in _weatherWords) {
      final bool mentioned = stop.risk?.contains(word) == true ||
          stop.detail.contains(word) ||
          stop.title.contains(word);
      if (mentioned && !hits.contains(word)) {
        hits.add(word);
      }
    }
  }
  if (hits.isEmpty) {
    return const RiskLine(
      icon: Icons.cloud_outlined,
      title: '天气',
      level: RiskLevel.unknown,
      reason: '这份方案没有返回当天的天气结论，出行前请查看实时预报。',
      source: '方案未包含天气结论',
    );
  }
  final bool blocking = hits.any(
    (String word) => const <String>['大风', '强风', '高温', '寒潮', '雪'].contains(word),
  );
  final String joined = hits.join('、');
  return RiskLine(
    icon: Icons.cloud_outlined,
    title: '天气',
    level: blocking ? RiskLevel.high : RiskLevel.medium,
    reason: '当天安排提到「$joined」，户外节点建议准备备用方案。',
    source: '来自节点风险提示',
  );
}

/// Roughly how long the day runs, in minutes, from the per item durations.
int _dayMinutes(Iterable<PlanStop> stops) =>
    stops.fold<int>(0, (int sum, PlanStop s) => sum + parseMinutes(s.duration));

/// Parses "180 分钟", "约2小时", "约2小时30分钟" and bare numbers into minutes.
///
/// Hours and minutes are read separately and then added: matching only the hour
/// part turned the server's canonical "约2小时30分钟" into a flat 2 hours.
int parseMinutes(String? raw) {
  if (raw == null || raw.isEmpty) {
    return 0;
  }
  final RegExpMatch? hours =
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:小时|h|H)').firstMatch(raw);
  final RegExpMatch? minutes =
      RegExp(r'(\d+(?:\.\d+)?)\s*(?:分钟|min|分)').firstMatch(raw);
  if (hours != null || minutes != null) {
    final double hourValue =
        hours == null ? 0 : double.parse(hours.group(1)!);
    final double minuteValue =
        minutes == null ? 0 : double.parse(minutes.group(1)!);
    return (hourValue * 60 + minuteValue).round();
  }
  final RegExpMatch? bare = RegExp(r'^\s*(\d+)\s*$').firstMatch(raw);
  if (bare != null) {
    return int.parse(bare.group(1)!);
  }
  return 0;
}

/// Minutes as a phrase a traveller would actually say: "2小时30分钟".
///
/// The risk radar used to print a one-decimal hour figure, which is where
/// "当天 3 个节点，约 59.1 小时" came from on the device screenshot.
/// Nothing here may ever emit a fraction.
String formatMinutes(int minutes) {
  final int safe = minutes < 0 ? 0 : minutes;
  if (safe < 60) {
    return '$safe分钟';
  }
  final int hours = safe ~/ 60;
  final int rest = safe % 60;
  return rest == 0 ? '$hours小时' : '$hours小时$rest分钟';
}

RiskLine _effortRisk(PlanDay day) {
  // 交通节点是"过程"而不是"停留"：它不该算进这一天的游玩节点与体力时长。
  // 这里原来按中文字面量 '交通' 比较，模型返回 transport 时每个交通节点都被
  // 算成了景点，叠加时长解析的错误后一天能报出 59.1 小时。
  final List<PlanStop> visiting = day.stops
      .where((PlanStop s) => StopCategory.of(s) != StopCategory.transport)
      .toList();
  final int stops = visiting.length;
  final int minutes = _dayMinutes(visiting);
  final RiskLevel level;
  if (stops >= 6 || minutes >= 600) {
    level = RiskLevel.high;
  } else if (stops >= 4 || minutes >= 420) {
    level = RiskLevel.medium;
  } else {
    level = RiskLevel.low;
  }
  final String durationText =
      minutes == 0 ? '停留时长未标注' : '停留约 ${formatMinutes(minutes)}';
  return RiskLine(
    icon: Icons.directions_walk,
    title: '体力',
    level: level,
    reason: '当天 $stops 个节点，$durationText。按节点数量与停留时长推算。',
    source: '按方案内节点推算',
  );
}

RiskLine _distanceRisk(PlanDay day) {
  int total = 0;
  bool crossCity = false;
  final RegExp mileage = RegExp(r'(\d+(?:\.\d+)?)\s*公里');
  for (final PlanStop stop in day.stops) {
    final String haystack = '${stop.detail} ${stop.transport}';
    for (final Match m in mileage.allMatches(haystack)) {
      total += double.parse(m.group(1)!).round();
    }
    if (stop.detail.contains('跨城') || stop.title.contains('返程')) {
      crossCity = true;
    }
  }
  if (total == 0 && !crossCity) {
    return const RiskLine(
      icon: Icons.route_outlined,
      title: '距离',
      level: RiskLevel.unknown,
      reason: '路段里程未随方案返回，无法给出距离结论。',
      source: '方案未包含里程',
    );
  }
  final RiskLevel level = total >= 120
      ? RiskLevel.high
      : (total >= 50 || crossCity ? RiskLevel.medium : RiskLevel.low);
  return RiskLine(
    icon: Icons.route_outlined,
    title: '距离',
    level: level,
    reason: total == 0
        ? '当天含跨城移动，建议预留换乘缓冲时间。'
        : '当天路段合计约 $total 公里，按行程内标注里程估算。',
    source: '按方案内标注里程估算',
  );
}

RiskLine _openingRisk(PlanDay day) {
  final List<String> notes = day.stops
      .map((PlanStop s) => s.risk ?? '')
      .where((String s) => s.contains('闭馆') || s.contains('开放') || s.contains('预约'))
      .toList();
  if (notes.isEmpty) {
    return const RiskLine(
      icon: Icons.schedule_outlined,
      title: '开放',
      level: RiskLevel.low,
      reason: '当天节点在生成时已按内容库核过开放时间，未发现冲突。',
      source: '运营台内容库',
    );
  }
  return RiskLine(
    icon: Icons.schedule_outlined,
    title: '开放',
    level: RiskLevel.medium,
    reason: notes.first,
    source: '节点风险提示',
  );
}

/// One day of the itinerary as a stacked card.
///
/// The v0.2 trip page split days across a chip row, so the reader could only
/// ever see one day at a time and could not compare them. Stacking the days with
/// their risk radar answers "which day is the hard one" at a glance.
class DayCard extends StatefulWidget {
  const DayCard({
    super.key,
    required this.day,
    required this.index,
    this.startDate,
    this.imageUrl,
    this.city,
    this.highlightStop,
  });

  final PlanDay day;
  final int index;

  /// 地图上选中的站点标题，命中时这一行会高亮并改变圆点颜色。
  ///
  /// 保持为标题而不是下标：地图和时间轴分别由服务端与方案数据生成，
  /// 两边唯一稳定一致的字段就是站点名。
  final String? highlightStop;

  /// The date the traveller picked, used to label the day when the plan itself
  /// carries a theme name instead of a calendar date.
  final DateTime? startDate;

  final String? imageUrl;
  final String? city;

  @override
  State<DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<DayCard> {
  bool _open = true;

  /// The plan's own date field when it is a real date, otherwise the traveller's
  /// start date advanced by this day's index.
  DateTime? get _resolvedDate {
    final DateTime? own = DateTime.tryParse(widget.day.subtitle);
    if (own != null) {
      return own;
    }
    final DateTime? start = widget.startDate;
    return start?.add(Duration(days: widget.index));
  }

  int get _dayCost =>
      widget.day.stops.fold<int>(0, (int sum, PlanStop s) => sum + s.cost);

  String get _dateLabel {
    final DateTime? date = _resolvedDate;
    if (date == null) {
      return widget.day.subtitle;
    }
    const List<String> week = <String>['一', '二', '三', '四', '五', '六', '日'];
    final String month = date.month.toString().padLeft(2, '0');
    final String day = date.day.toString().padLeft(2, '0');
    return '$month-$day 周${week[date.weekday - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final List<RiskLine> risks = deriveDayRisks(widget.day);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _header(),
          if (_open) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                0,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (widget.imageUrl != null &&
                      widget.imageUrl!.isNotEmpty) ...<Widget>[
                    PhotoPlate(
                      url: widget.imageUrl!,
                      height: AppSpacing.photoHeight,
                      radius: AppSpacing.radiusSmall,
                      fallbackLabel: widget.day.stops.isEmpty
                          ? null
                          : widget.day.stops.first.title,
                      semanticLabel: widget.day.subtitle,
                    ),
                    const SizedBox(height: 14),
                  ],
                  _StopRail(
                    stops: widget.day.stops,
                    highlightStop: widget.highlightStop,
                  ),
                  const SizedBox(height: 12),
                  _RiskRadar(risks: risks),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header() => InkWell(
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.cardPadding,
            AppSpacing.cardPadding,
            AppSpacing.cardPadding,
            AppSpacing.content,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              TagPill(
                'DAY ${(widget.index + 1).toString().padLeft(2, '0')}',
                tone: TagTone.brand,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.day.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        _dateLabel,
                        if (widget.city != null) widget.city!,
                      ].where((String s) => s.isNotEmpty).join(' · '),
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    '¥$_dayCost',
                    style: const TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.amber,
                      fontFeatures: AppTypography.tabularFigures,
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColors.crackle,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

class _StopRow extends StatelessWidget {
  const _StopRow({required this.stop, required this.last, this.highlighted = false});

  final PlanStop stop;
  final bool last;

  /// 由地图选中的那一站。这里不高亮整行（会挤出横向空间），
  /// 而是让圆点、标题与时间一起变色——颜色之外还有图标填充的变化，
  /// 不依赖颜色单一通道传达信息。
  final bool highlighted;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 44,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                stop.time,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: AppTypography.secondary,
                  fontWeight: FontWeight.w700,
                  color: highlighted ? AppColors.kilnRed : AppColors.ink,
                  fontFeatures: AppTypography.tabularFigures,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _Rail(category: StopCategory.of(stop), highlighted: highlighted),
          const SizedBox(width: 10),
          Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 2 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      stop.title,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                        color: highlighted ? AppColors.kilnRed : AppColors.ink,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      <String>[
                        StopCategory.of(stop).label,
                        if (stop.duration != null && stop.duration!.isNotEmpty)
                          stop.duration!,
                        if (stop.transport != null &&
                            stop.transport!.isNotEmpty)
                          stop.transport!,
                        if (stop.cost > 0) '¥${stop.cost}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        height: 1.45,
                      ),
                    ),
                    if (stop.detail.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        stop.detail,
                        style: const TextStyle(
                          fontSize: AppTypography.secondary,
                          color: AppColors.inkSoft,
                          height: 1.5,
                        ),
                      ),
                    ],
                    if (stop.risk != null && stop.risk!.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.info_outline,
                              size: 13,
                              color: AppColors.cautionText,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              stop.risk!,
                              style: const TextStyle(
                                fontSize: AppTypography.caption,
                                color: AppColors.cautionText,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        TagPill(stop.source, dense: true),
                        DataStatusBadge(
                          status: stop.dataStatus,
                          dense: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
}

/// The dots plus the connecting hairline: the itinerary reads as one continuous
/// measured line instead of a pile of rows.
class _StopRail extends StatelessWidget {
  const _StopRail({required this.stops, this.highlightStop});

  final List<PlanStop> stops;
  final String? highlightStop;

  @override
  Widget build(BuildContext context) => Stack(
        children: <Widget>[
          // Centre of the 22dp dot column: 44 (time) + 10 (gap) + 11 (radius).
          Positioned(
            left: 64.5,
            top: 12,
            bottom: 12,
            child: Container(width: 1, color: AppColors.hairline),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (int i = 0; i < stops.length; i++)
                _StopRow(
                  stop: stops[i],
                  last: i == stops.length - 1,
                  highlighted: highlightStop != null && stops[i].title == highlightStop,
                ),
            ],
          ),
        ],
      );
}

class _Rail extends StatelessWidget {
  const _Rail({required this.category, this.highlighted = false});

  final StopCategory category;
  final bool highlighted;

  IconData get _icon => switch (category) {
        StopCategory.transport => Icons.directions_transit,
        StopCategory.meal => Icons.restaurant,
        StopCategory.hotel => Icons.hotel,
        StopCategory.activity => Icons.local_activity_outlined,
        StopCategory.attraction || StopCategory.other => Icons.place,
      };

  @override
  Widget build(BuildContext context) => Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: highlighted ? AppColors.kilnRed : AppColors.surfaceTint,
          shape: BoxShape.circle,
        ),
        child: Icon(
          _icon,
          size: 12,
          color: highlighted ? Colors.white : AppColors.celadonDeep,
        ),
      );
}

class _RiskRadar extends StatelessWidget {
  const _RiskRadar({required this.risks});

  final List<RiskLine> risks;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(AppSpacing.content),
        decoration: BoxDecoration(
          color: AppColors.ground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.shield_moon_outlined,
                  size: 15,
                  color: AppColors.celadonDeep,
                ),
                const SizedBox(width: 6),
                const Text(
                  '出行风险雷达',
                  style: TextStyle(
                    fontSize: AppTypography.secondary,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const Spacer(),
                Text(
                  '4 项',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    fontFeatures: AppTypography.tabularFigures,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (int i = 0; i < risks.length; i++) ...<Widget>[
              if (i > 0) const Divider(),
              _RiskRow(line: risks[i]),
            ],
          ],
        ),
      );
}

class _RiskRow extends StatelessWidget {
  const _RiskRow({required this.line});

  final RiskLine line;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(line.icon, size: 16, color: AppColors.celadonDeep),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    line.title,
                    style: const TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    line.reason,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.inkSoft,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '来源：${line.source}',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _levelTag(line.level),
          ],
        ),
      );

  static Widget _levelTag(RiskLevel level) {
    final String text =
        level == RiskLevel.unknown ? level.label : '${level.label}风险';
    return TagPill(
        text,
        dense: true,
        tone: switch (level) {
          RiskLevel.low => TagTone.settled,
          RiskLevel.medium => TagTone.caution,
          RiskLevel.high => TagTone.risk,
          RiskLevel.unknown => TagTone.neutral,
        },
      );
  }
}

