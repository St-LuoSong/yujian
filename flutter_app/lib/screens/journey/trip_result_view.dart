import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/session_providers.dart';
import '../../core/network/api_failure.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_typography.dart';
import '../../core/widgets/data_status_badge.dart';
import '../../core/widgets/data_status_legend.dart';
import '../../core/widgets/key_value_row.dart';
import '../../core/widgets/section_header.dart';
import '../../core/widgets/stat_tile.dart';
import '../../core/widgets/surface_card.dart';
import '../../core/widgets/tag_pill.dart';
import '../../models/account_models.dart';
import '../../models/travel_models.dart';
import '../../models/trip_models.dart';
import 'day_card.dart';
import 'route_map_card.dart';

/// The whole "this is your plan" surface: summary, adjustment, the stacked day
/// cards, the budget reading and the evidence trail.
///
/// Both entrances share it on purpose. A plan that was just generated in the
/// journey page and the same plan reopened from 我的行程 are the same object,
/// so they must not drift into two different renderings.
class TripResultView extends ConsumerStatefulWidget {
  const TripResultView({
    super.key,
    required this.plan,
    this.budgetPerPerson,
    this.startDate,
    this.images = const <String, String>{},
    this.onPlanChanged,
    this.showAdjust = true,
  });

  final TravelPlan plan;

  /// The traveller's own ceiling, when the journey form supplied one. Used for
  /// the 结余 tile; without it the tile falls back to a per person reading.
  final int? budgetPerPerson;

  /// Chosen departure date, used to label each day when the plan carries a
  /// theme name instead of a calendar date.
  final DateTime? startDate;

  /// Attraction name to photograph, joined from the content library.
  final Map<String, String> images;

  /// Lets the parent keep its own copy in step after an adjustment or undo.
  final ValueChanged<TravelPlan>? onPlanChanged;

  final bool showAdjust;

  @override
  ConsumerState<TripResultView> createState() => _TripResultViewState();
}

class _TripResultViewState extends ConsumerState<TripResultView> {
  final TextEditingController _adjustInput = TextEditingController();
  late TravelPlan _plan;
  bool _adjusting = false;
  bool _undoing = false;
  bool _sharing = false;

  /// 地图上选中的站点，用来在对应那一天的行程里同步高亮。
  int? _mapDay;
  String? _mapStop;
  bool _canUndo = false;
  List<String> _changes = const <String>[];
  TraceInfo? _trace;
  String? _traceError;
  bool _loadingTrace = false;

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    _canUndo = false;
  }

  @override
  void didUpdateWidget(TripResultView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A brand new plan (regenerated, or opened from the list) replaces the
    // local copy and clears the adjustment history that belonged to the old
    // one.
    if (!identical(oldWidget.plan, widget.plan) &&
        oldWidget.plan.id != widget.plan.id) {
      _plan = widget.plan;
      _canUndo = false;
      _changes = const <String>[];
      _trace = null;
      _traceError = null;
    }
  }

  @override
  void dispose() {
    _adjustInput.dispose();
    super.dispose();
  }

  bool get _canEdit => _plan.isPersisted;

  void _apply(TravelPlan next, {List<String>? changes, bool? canUndo}) {
    setState(() {
      _plan = next;
      if (changes != null) {
        _changes = changes;
      }
      if (canUndo != null) {
        _canUndo = canUndo;
      }
    });
    widget.onPlanChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final List<PlanDay> days = _plan.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _PlanSummaryCard(
          plan: _plan,
          budgetPerPerson: widget.budgetPerPerson,
          sharing: _sharing,
          onShare: _share,
        ),
        if (_plan.warnings.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _WarningCard(warnings: _plan.warnings),
        ],
        if (widget.showAdjust) ...<Widget>[
          const SizedBox(height: 14),
          _AdjustCard(
            controller: _adjustInput,
            enabled: _canEdit,
            busy: _adjusting,
            canUndo: _canUndo && !_undoing,
            changes: _changes,
            onAdjust: _adjust,
            onUndo: _undo,
          ),
        ],
        const SizedBox(height: 26),
        // 地图放在时间轴之前：先给"这一天在哪儿、怎么串起来"的整体印象，
        // 再看逐条安排。地图选中某一站时会把高亮交给对应那一天的卡片。
        RouteMapCard(
          planId: _plan.id,
          days: days,
          onLocateStop: _locateStop,
        ),
        const SizedBox(height: 26),
        SectionHeader(
          title: '每日行程',
          subtitle: '点击日期可折叠当天安排；每天末尾是四项风险核对。',
          icon: Icons.calendar_month_outlined,
          trailing: TagPill(
            '${days.length} 天',
            tone: TagTone.neutral,
            dense: true,
          ),
        ),
        const SizedBox(height: 14),
        for (int i = 0; i < days.length; i++) ...<Widget>[
          DayCard(
            day: days[i],
            index: i,
            startDate: widget.startDate,
            city: cityForDay(_plan, days[i]),
            imageUrl: _imageFor(days[i]),
            highlightStop: _mapDay == i ? _mapStop : null,
          ),
          if (i != days.length - 1) const SizedBox(height: 14),
        ],
        const SizedBox(height: 26),
        _BudgetCard(plan: _plan, budgetPerPerson: widget.budgetPerPerson),
        const SizedBox(height: 14),
        _EvidenceCard(
          loading: _loadingTrace,
          error: _traceError,
          trace: _trace,
          persisted: _canEdit,
          onOpen: _loadTrace,
        ),
        if (_plan.statusDetail != null && _plan.statusDetail!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _Note(
            text: _plan.statusDetail!,
            tone: _NoteTone.caution,
          ),
        ],
      ],
    );
  }

  /// 地图上点了某一站：把高亮交给对应那一天的卡片。
  ///
  /// 再点一次同一站会取消高亮，避免高亮一直留在页面上却忘了它从哪来。
  void _locateStop(int dayIndex, String title) {
    setState(() {
      if (_mapDay == dayIndex && _mapStop == title) {
        _mapDay = null;
        _mapStop = null;
        return;
      }
      _mapDay = dayIndex;
      _mapStop = title;
    });
  }

  /// The first attraction photo of the day, resolved by name against the
  /// content library. Returns null when the catalog has no match, which keeps
  /// the card text only rather than showing an unrelated picture.
  String? _imageFor(PlanDay day) {
    for (final PlanStop stop in day.stops) {
      final String? url = widget.images[stop.title];
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  Future<void> _adjust() async {
    final String instruction = _adjustInput.text.trim();
    if (instruction.isEmpty) {
      _notify('请先写下想怎么调整，例如“第二天轻松一点”。');
      return;
    }
    if (!_canEdit) {
      _notify('当前是本地演示方案，调整需要连接服务器。');
      return;
    }
    setState(() => _adjusting = true);
    try {
      final AdjustmentResult result =
          await ref.read(travelRepositoryProvider).adjustTripPlan(
                planId: _plan.id!,
                instruction: instruction,
              );
      if (!mounted) {
        return;
      }
      setState(() => _adjusting = false);
      _adjustInput.clear();
      _apply(result.plan, changes: result.changes, canUndo: true);
      FocusScope.of(context).unfocus();
      _notify('已按你的要求更新行程。');
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _adjusting = false);
      _notify(failure.message);
    }
  }

  Future<void> _undo() async {
    if (!_canEdit) {
      return;
    }
    setState(() => _undoing = true);
    try {
      final TravelPlan restored =
          await ref.read(travelRepositoryProvider).undoTripPlan(_plan.id!);
      if (!mounted) {
        return;
      }
      setState(() => _undoing = false);
      _apply(restored, changes: const <String>[], canUndo: false);
      _notify('已撤销上一次调整。');
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _undoing = false);
      _notify(failure.message);
    }
  }

  Future<void> _loadTrace() async {
    if (_trace != null || _loadingTrace) {
      return;
    }
    if (!_canEdit) {
      setState(() => _traceError = '依据需要从服务器读取，当前是本地演示方案。');
      return;
    }
    setState(() {
      _loadingTrace = true;
      _traceError = null;
    });
    try {
      final TraceInfo loaded =
          await ref.read(travelRepositoryProvider).fetchTrace(_plan.id!);
      if (!mounted) {
        return;
      }
      setState(() {
        _trace = loaded;
        _loadingTrace = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() {
        _traceError = failure.message;
        _loadingTrace = false;
      });
    }
  }

  /// Sharing needs a signed in owner: the server only issues a link for a plan
  /// that belongs to the caller. An anonymous visitor is told why rather than
  /// being handed a 404.
  Future<void> _share() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    if (ref.read(sessionProvider).valueOrNull == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('分享需要登录。请到「我的」登录后重试。')),
        );
      return;
    }
    if (!_canEdit) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('本地演示方案不在服务器上，无法生成分享链接。')),
        );
      return;
    }
    setState(() => _sharing = true);
    try {
      final TripShareLink link = await ref
          .read(travelRepositoryProvider)
          .createShareLink(planId: _plan.id!);
      if (!mounted) {
        return;
      }
      setState(() => _sharing = false);
      await showModalBottomSheet<void>(
        context: context,
        builder: (_) => _ShareSheet(link: link, planTitle: _plan.title),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _sharing = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The city a day is spent in, taken from the plan's corridor and the day's own
/// place names. Returns null when nothing matches instead of guessing.
String? cityForDay(TravelPlan plan, PlanDay day) {
  const List<String> known = <String>[
    '郑州',
    '洛阳',
    '开封',
    '焦作',
    '云台山',
    '登封',
    '安阳',
    '南阳',
  ];
  for (final PlanStop stop in day.stops) {
    for (final String city in known) {
      if (stop.title.contains(city) || stop.detail.contains(city)) {
        return city;
      }
    }
  }
  for (final String city in known) {
    if (plan.corridor.contains(city)) {
      return city;
    }
  }
  return null;
}

/// Highest risk across every derived row, used by the summary tile.
RiskLevel worstRisk(TravelPlan plan) {
  final List<RiskLevel> levels = <RiskLevel>[];
  for (final PlanDay day in plan.days) {
    for (final RiskLine line in deriveDayRisks(day)) {
      levels.add(line.level);
    }
  }
  return RiskLevel.worst(levels);
}

/// Largest mileage figure mentioned anywhere in the plan, when there is one.
int? intercityKm(TravelPlan plan) {
  int best = 0;
  final RegExp mileage = RegExp(r'(\d+(?:\.\d+)?)\s*公里');
  for (final PlanDay day in plan.days) {
    for (final PlanStop stop in day.stops) {
      final String haystack = '${stop.detail} ${stop.transport} ${stop.title}';
      for (final Match m in mileage.allMatches(haystack)) {
        final int value = double.parse(m.group(1)!).round();
        if (value > best) {
          best = value;
        }
      }
    }
  }
  return best == 0 ? null : best;
}

class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({
    required this.plan,
    required this.budgetPerPerson,
    required this.sharing,
    required this.onShare,
  });

  final TravelPlan plan;
  final int? budgetPerPerson;
  final bool sharing;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final RiskLevel risk = worstRisk(plan);
    final int? km = intercityKm(plan);
    final int? budget = budgetPerPerson;
    final int? balance =
        budget == null ? null : budget * plan.people - plan.totalCost;
    final String transportMode = _transportMode(plan);

    return SurfaceCard(
      color: AppColors.celadonDeep,
      shadow: const <BoxShadow>[
        BoxShadow(
          color: Color(0x33204F49),
          blurRadius: 22,
          offset: Offset(0, 10),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      plan.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onInk,
                        height: AppTypography.headingHeight,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      plan.corridor,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.onInkMuted,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              DataStatusBadge(status: plan.status, dense: true),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: '行程主题',
                  value: plan.intensity,
                  caption: '${plan.days.length} 天 · ${plan.stopCount} 个节点',
                  tone: StatTone.brand,
                  icon: Icons.auto_awesome_motion_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StatTile(
                  label: balance == null ? '人均费用' : '总费用 / 结余',
                  value: balance == null
                      ? '¥${plan.perPerson}'
                      : '¥${plan.totalCost}',
                  unit: balance == null ? '/人' : null,
                  caption: balance == null
                      ? '服务器按人数折算'
                      : (balance >= 0 ? '结余 ¥$balance' : '超出 ¥${-balance}'),
                  tone: StatTone.brand,
                  icon: Icons.savings_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: '跨城交通',
                  value: km == null ? '未标注' : '约 $km',
                  unit: km == null ? null : '公里',
                  caption: transportMode,
                  tone: StatTone.brand,
                  icon: Icons.train_outlined,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: StatTile(
                  label: '最高风险',
                  value: risk == RiskLevel.unknown ? '待确认' : '${risk.label}风险',
                  caption: risk == RiskLevel.unknown
                      ? '方案未包含天气结论'
                      : '见每天末尾的风险雷达',
                  tone: StatTone.brand,
                  icon: Icons.shield_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: sharing ? null : onShare,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.onInk,
                    backgroundColor: Colors.white10,
                    side: const BorderSide(color: Color(0x55FFFFFF)),
                  ),
                  icon: const Icon(Icons.ios_share, size: 16),
                  label: Text(sharing ? '正在生成…' : '只读分享'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _transportMode(TravelPlan plan) {
    for (final PlanDay day in plan.days) {
      for (final PlanStop stop in day.stops) {
        if (stop.kind == '交通' && stop.transport != null) {
          return stop.transport!;
        }
      }
    }
    return '按方案内交通节点汇总';
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.riskSurface,
        shadow: const <BoxShadow>[],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(Icons.priority_high_rounded,
                    size: 16, color: AppColors.riskText),
                SizedBox(width: 6),
                Text(
                  '行程冲突提示',
                  style: TextStyle(
                    fontSize: AppTypography.secondary,
                    fontWeight: FontWeight.w700,
                    color: AppColors.riskText,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final String warning in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: SizedBox(
                        width: 4,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: AppColors.riskText,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        warning,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.riskText,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _AdjustCard extends StatelessWidget {
  const _AdjustCard({
    required this.controller,
    required this.enabled,
    required this.busy,
    required this.canUndo,
    required this.changes,
    required this.onAdjust,
    required this.onUndo,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool busy;
  final bool canUndo;
  final List<String> changes;
  final VoidCallback onAdjust;
  final VoidCallback onUndo;

  /// One tap presets, so the adjustment box is usable without inventing a
  /// sentence first.
  static const List<String> _presets = <String>[
    '第二天轻松一点',
    '多安排博物馆',
    '增加当地美食',
    '预算再省一点',
    '下雨给室内替代',
  ];

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: '动态调整',
              subtitle: '改完会显示变化明细，并且可以撤销。',
              icon: Icons.tune,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String preset in _presets)
                  ActionChip(
                    label: Text(preset),
                    onPressed: enabled && !busy
                        ? () {
                            controller.text = preset;
                            onAdjust();
                          }
                        : null,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              enabled: enabled && !busy,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: enabled
                    ? '用自己的话说明想改什么…'
                    : '本地演示方案不支持调整',
                suffixIcon: IconButton(
                  onPressed: enabled && !busy ? onAdjust : null,
                  tooltip: '应用调整',
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded, size: 18),
                ),
              ),
              onSubmitted: (_) => onAdjust(),
            ),
            if (!enabled) ...<Widget>[
              const SizedBox(height: 10),
              const Text(
                '连接服务器后可以修改、撤销，并查看每一步的依据。',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.5,
                ),
              ),
            ],
            if (changes.isNotEmpty) ...<Widget>[
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  const Text(
                    '本次改了什么',
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const Spacer(),
                  if (canUndo)
                    TextButton.icon(
                      onPressed: onUndo,
                      icon: const Icon(Icons.undo, size: 16),
                      label: const Text('撤销'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final String change in changes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.check_circle_outline,
                            size: 14, color: AppColors.settled),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          change,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.inkSoft,
                            height: 1.55,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      );
}

/// 预算拆解里的一行科目。
///
/// 用具名类型而不是 record：堆叠条、明细行、合计三处都要读它的字段，
/// record 会把字段形状重复写在每个调用点上。
class BudgetSlice {
  const BudgetSlice({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.plan, required this.budgetPerPerson});

  final TravelPlan plan;
  final int? budgetPerPerson;

  /// 科目配色。颜色只是辅助，每一行都带文字标签，不靠颜色区分科目。
  static const Map<StopCategory, Color> _categoryColors = <StopCategory, Color>{
    StopCategory.transport: AppColors.celadon,
    StopCategory.attraction: AppColors.celadonDeep,
    StopCategory.meal: AppColors.amber,
    StopCategory.hotel: AppColors.celadonPale,
    StopCategory.activity: AppColors.settled,
    StopCategory.other: AppColors.crackle,
  };

  /// 按节点汇总金额。
  ///
  /// 真实故障：这里原来用 `switch (stop.kind)` 硬匹配中文 '交通'/'景点'/'餐饮'，
  /// 而模型返回的 type 是 transport / attraction，于是每一笔都落进 default，
  /// 预算卡上只剩一条"其他 ¥90 100%"。分类统一走 StopCategory 之后，
  /// 中文、英文与只能靠标题判断的节点都能归到正确科目。
  ///
  /// cost == 0 的节点不再被折叠成"其他 0 元"，而是单独提示"未计价"：
  /// "门票没返回价格"和"这一项本来就免费"对用户是两件不同的事。
  List<BudgetSlice> get _slices {
    final Map<StopCategory, int> totals = <StopCategory, int>{};
    for (final PlanDay day in plan.days) {
      for (final PlanStop stop in day.stops) {
        if (stop.cost <= 0) {
          continue;
        }
        final StopCategory category = StopCategory.of(stop);
        totals[category] = (totals[category] ?? 0) + stop.cost;
      }
    }
    return <BudgetSlice>[
      for (final StopCategory category in StopCategory.values)
        if ((totals[category] ?? 0) > 0)
          BudgetSlice(
            label: category.label,
            value: totals[category]!,
            color: _categoryColors[category] ?? AppColors.crackle,
          ),
    ];
  }

  int get _unpricedStops => plan.days.fold<int>(
        0,
        (int sum, PlanDay day) =>
            sum + day.stops.where((PlanStop stop) => stop.cost <= 0).length,
      );

  @override
  Widget build(BuildContext context) {
    final List<BudgetSlice> slices = _slices;
    final int total =
        slices.fold<int>(0, (int sum, BudgetSlice s) => sum + s.value);
    final int? budget = budgetPerPerson;
    final int travellers = plan.people < 1 ? 1 : plan.people;
    final int cap = budget == null ? 0 : budget * travellers;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionHeader(
            title: '预算拆解',
            subtitle: total == 0
                ? '这份行程的节点都还没有金额，下面是预算上限对比。'
                : '按行程节点的金额科目自动汇总。',
            icon: Icons.pie_chart_outline,
            trailing: TagPill(
              '¥$total',
              tone: TagTone.sand,
              dense: true,
            ),
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: SizedBox(
                height: 10,
                child: Row(
                  children: <Widget>[
                    for (final BudgetSlice slice in slices)
                      Expanded(
                        flex: slice.value,
                        child: ColoredBox(color: slice.color),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final BudgetSlice slice in slices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        slice.label,
                        style: const TextStyle(
                          fontSize: AppTypography.secondary,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                    Text(
                      '¥${slice.value}',
                      style: const TextStyle(
                        fontSize: AppTypography.secondary,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 38,
                      child: Text(
                        '${(slice.value * 100 / total).round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.crackle,
                          fontFeatures: AppTypography.tabularFigures,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(),
            const SizedBox(height: 10),
            KeyValueRow(label: '合计', value: '¥$total'),
            KeyValueRow(
              label: '人均',
              value: '¥${(total / travellers).round()}（$travellers 人）',
            ),
          ],
          if (_unpricedStops > 0)
            KeyValueRow(
              label: '未计价节点',
              value: '$_unpricedStops 个（未返回价格）',
            ),
          if (budget != null) ...<Widget>[
            SizedBox(height: total > 0 ? 6 : 12),
            KeyValueRow(
              label: '预算上限',
              value: '¥$cap（¥$budget × $travellers 人）',
            ),
            KeyValueRow(
              label: total == 0 ? '预算对比' : '余额',
              value: total == 0
                  ? '节点还没有金额，暂时无法与上限比较'
                  : (cap - total >= 0 ? '¥${cap - total}' : '超出 ¥${total - cap}'),
              danger: total > cap,
            ),
          ],
        ],
      ),
    );
  }
}

/// Engine, prompt version and per tool evidence, loaded on first expand so the
/// plan page does not pay for a trace request the reader never looks at.
class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    required this.loading,
    required this.error,
    required this.trace,
    required this.persisted,
    required this.onOpen,
  });

  final bool loading;
  final String? error;
  final TraceInfo? trace;
  final bool persisted;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: EdgeInsets.zero,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          iconColor: AppColors.celadonDeep,
          collapsedIconColor: AppColors.crackle,
          tilePadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.cardPadding,
            vertical: 4,
          ),
          childrenPadding: const EdgeInsets.fromLTRB(
            AppSpacing.cardPadding,
            0,
            AppSpacing.cardPadding,
            AppSpacing.cardPadding,
          ),
          onExpansionChanged: (bool open) {
            if (open) {
              onOpen();
            }
          },
          title: const Text(
            '方案依据',
            style: TextStyle(
              fontSize: AppTypography.cardTitle,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          subtitle: const Text(
            '规划引擎、数据来源与工具调用记录',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          ),
          children: <Widget>[
            if (!persisted)
              const _Note(
                text: '依据需要从服务器读取。当前是本地演示方案，连接后可查看规划引擎、提示词版本与每个工具的来源。',
                tone: _NoteTone.caution,
              )
            else if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              _Note(text: error!, tone: _NoteTone.risk)
            else if (trace != null) ...<Widget>[
              KeyValueRow(
                label: '规划引擎',
                value: trace!.engine.isEmpty ? '未知' : trace!.engine,
              ),
              KeyValueRow(label: '提示词版本', value: trace!.promptVersion),
              KeyValueRow(
                label: '工具调用',
                value: '${trace!.invocations.length} 次，其中演示工具 ${trace!.toolMockCount} 次',
              ),
              const SizedBox(height: 10),
              DataStatusBadge(status: trace!.dataStatus, dense: true),
              const SizedBox(height: 14),
              DataStatusLegend(
                counts: trace!.statusCounts,
                total: trace!.invocations.length,
              ),
              if (trace!.isFullyMock) ...<Widget>[
                const SizedBox(height: 12),
                const _Note(
                  text: '本次规划由演示工具提供数据，已如实标注，不代表实时路况、天气或车次。',
                ),
              ],
              const SizedBox(height: 16),
              for (int i = 0; i < trace!.invocations.length; i++) ...<Widget>[
                if (i > 0) const Divider(),
                _TraceRow(trace: trace!.invocations[i]),
              ],
            ],
          ],
        ),
      );
}

class _TraceRow extends StatelessWidget {
  const _TraceRow({required this.trace});

  final ToolTrace trace;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  trace.success
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 15,
                  color: trace.success ? AppColors.settled : AppColors.kilnRed,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    trace.toolName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                if (trace.durationMs != null)
                  Text(
                    '${trace.durationMs} 毫秒',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      fontFeatures: AppTypography.tabularFigures,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              trace.outputSummary == null || trace.outputSummary!.isEmpty
                  ? '来源：${trace.source.isEmpty ? '未标注' : trace.source}'
                  : trace.outputSummary!,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.inkSoft,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '来源：${trace.source.isEmpty ? '未标注' : trace.source}',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                    ),
                  ),
                ),
                DataStatusBadge(status: trace.dataStatus, dense: true),
              ],
            ),
            if (trace.errorCode != null && trace.errorCode!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                '错误码：${trace.errorCode}',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.kilnRed,
                ),
              ),
            ],
          ],
        ),
      );
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.link, required this.planTitle});

  final TripShareLink link;
  final String planTitle;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  bool _revoking = false;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                '只读分享链接',
                style: TextStyle(
                  fontSize: AppTypography.sectionTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '收到链接的人只能查看这份行程，不能修改。分享内容会按设置隐藏预算。',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceTint,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                ),
                child: SelectableText(
                  widget.link.url,
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.ink,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制链接'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _share,
                      icon: const Icon(Icons.ios_share, size: 16),
                      label: const Text('系统分享'),
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _revoking ? null : _revoke,
                  child: Text(_revoking ? '正在关闭…' : '关闭这条分享'),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.link.url));
    if (!mounted) {
      return;
    }
    _notify('链接已复制。');
  }

  Future<void> _share() async {
    await Share.share('${widget.planTitle}\n${widget.link.url}');
  }

  /// Captures the messenger before popping, otherwise the snack bar would be
  /// requested on a widget that is already gone.
  Future<void> _revoke() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _revoking = true);
    try {
      await ref.read(travelRepositoryProvider).revokeShareLink(widget.link.id);
      if (!mounted) {
        return;
      }
      navigator.pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('分享链接已关闭。')));
    } on ApiFailure {
      if (!mounted) {
        return;
      }
      setState(() => _revoking = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('关闭失败，请稍后重试。')));
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

enum _NoteTone { plain, caution, risk }

class _Note extends StatelessWidget {
  const _Note({required this.text, this.tone = _NoteTone.plain});

  final String text;
  final _NoteTone tone;

  @override
  Widget build(BuildContext context) {
    final Color background = switch (tone) {
      _NoteTone.plain => AppColors.surfaceTint,
      _NoteTone.caution => AppColors.cautionSurface,
      _NoteTone.risk => AppColors.riskSurface,
    };
    final Color foreground = switch (tone) {
      _NoteTone.plain => AppColors.inkSoft,
      _NoteTone.caution => AppColors.cautionText,
      _NoteTone.risk => AppColors.riskText,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: AppTypography.caption,
          color: foreground,
          height: 1.55,
        ),
      ),
    );
  }
}
