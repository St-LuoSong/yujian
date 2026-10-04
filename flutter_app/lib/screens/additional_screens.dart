import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/formatters/chinese_date.dart';
import '../core/icons/app_icons.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/data_status_badge.dart';
import '../core/widgets/key_value_row.dart';
import '../core/widgets/measure_value.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/route_gauge.dart';
import '../core/widgets/section_rule.dart';
import '../core/widgets/surface_card.dart';
import '../models/account_models.dart';
import '../models/travel_models.dart';
import '../models/trip_models.dart';
import 'home_screen.dart';
import 'planner_screen.dart';
import 'trip_screen.dart';

/// "行程" tab: the most recent trip plus today's next stop.
///
/// Reads `GET /api/trip-plans` and `GET /api/trip-plans/{id}/today`. When the
/// server is unreachable the repository replays the cached plan and this page
/// labels it as cached instead of presenting it as live data.
class TripHomeScreen extends ConsumerStatefulWidget {
  const TripHomeScreen({super.key, this.onPlan});

  /// Switches to the planner tab. Null when the caller cannot navigate.
  final VoidCallback? onPlan;

  @override
  ConsumerState<TripHomeScreen> createState() => _TripHomeScreenState();
}

class _TripHomeScreenState extends ConsumerState<TripHomeScreen> {
  late Future<_TripHomeData> _future;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    final page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        // 同 TripScreen：显式 leading，不让"下面还有没有活动路由"决定用户
        // 能不能退出这一页。
        leading: AppBackButton(
          fallback: (BuildContext context) => const HomeScreen(),
        ),
        title: const Text('我的行程'),
        actions: <Widget>[
          IconButton(
            // 用代码块而不是箭头：setState 的回调不允许返回 Future，
            // `() => _future = _load()` 会把 Future 当成返回值传出去，debug 下直接断言失败。
            onPressed: () => setState(() {
              _future = _load();
            }),
            tooltip: '刷新行程',
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      body: FutureBuilder<_TripHomeData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null || data.isEmpty) {
            return _EmptyTrips(failure: data?.failure, onPlan: widget.onPlan);
          }
          return _TripContent(
            data: data,
            page: page,
            openingId: _openingId,
            onOpen: _open,
            onActions: _showActions,
          );
        },
      ),
    );
  }

  Future<_TripHomeData> _load() async {
    final repository = ref.read(travelRepositoryProvider);
    final list = await repository.fetchTripPlans();
    if (list.isEmpty) {
      return _TripHomeData(
        items: const <TripSummary>[],
        today: null,
        failure: list.failure,
      );
    }
    // 只有最近一份需要「今天的安排」；其余行程在这一页只需要列表信息，
    // 逐份去拉 today 会让打开这一页变慢，而且它们本来也不是今天的行程。
    final summary = list.items.first;
    try {
      final today = await repository.fetchToday(summary.id);
      return _TripHomeData(
        items: list.items,
        today: today,
        failure: list.failure,
      );
    } on ApiFailure catch (failure) {
      return _TripHomeData(items: list.items, today: null, failure: failure);
    }
  }

  /// Opens the row actions.
  ///
  /// 重命名与删除放在弹层里，而不是直接摆在行上：这一行的主要动作是"打开行程"，
  /// 误触的代价不能是删掉一份方案。弹层里也各带一句说明，写清改什么、删什么。
  Future<void> _showActions(TripSummary summary) async {
    final _TripAction? action = await showModalBottomSheet<_TripAction>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.ground,
      builder: (BuildContext context) => _TripActionsSheet(summary: summary),
    );
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _TripAction.rename:
        await _rename(summary);
      case _TripAction.delete:
        await _delete(summary);
    }
  }

  Future<void> _rename(TripSummary summary) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? title = await showDialog<String>(
      context: context,
      builder: (BuildContext context) =>
          _RenameTripDialog(initialTitle: summary.title),
    );
    if (title == null || !mounted) {
      return;
    }
    try {
      await ref
          .read(travelRepositoryProvider)
          .renameTripPlan(planId: summary.id, title: title);
      if (!mounted) {
        return;
      }
      // 服务端改了标题，列表就以服务端为准重新拉一次，不在本地假装同步。
      setState(() {
        _future = _load();
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('行程名称已更新。')));
    } on ApiFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _delete(TripSummary summary) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool confirmed = await _confirmDelete(summary.title);
    if (!confirmed || !mounted) {
      return;
    }
    try {
      await ref.read(travelRepositoryProvider).deleteTripPlan(summary.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _future = _load();
      });
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('行程已删除。')));
    } on ApiFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// 删除是不可撤销的，所以先把"删掉的是哪一份、连带删掉什么"说清楚。
  Future<bool> _confirmDelete(String title) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这份行程？'),
        content: Text(
          '「$title」的逐日安排与调整记录会一并删除，删除后无法恢复。',
          style: const TextStyle(height: 1.6),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.kilnRed),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _open(TripSummary summary) async {
    // 一次只开一份行程。没有这道闸，连点两下会 push 两条一模一样的路由：
    // 用户按一次返回还停在"同一个"页面，看起来就是返回按钮坏掉了。
    if (_openingId != null) {
      return;
    }
    // Resolved before the await so navigation cannot target a disposed element.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _openingId = summary.id);
    try {
      final result =
          await ref.read(travelRepositoryProvider).fetchTripPlan(summary.id);
      if (!mounted) return;
      setState(() => _openingId = null);
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => TripScreen(plan: result.plan)),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _openingId = null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _TripHomeData {
  const _TripHomeData({
    required this.items,
    required this.today,
    this.failure,
  });

  /// 全部已保存行程，最新的排在前面（服务端已按 updatedAt 倒序）。
  /// 首屏顶部那条「下一站」只读 `items.first`，下面的列表把每一份都列出来。
  final List<TripSummary> items;

  final TodayInfo? today;

  /// Set when the data came from the offline cache rather than the server.
  final ApiFailure? failure;

  bool get isEmpty => items.isEmpty;
}

class _TripContent extends StatelessWidget {
  const _TripContent({
    required this.data,
    required this.page,
    required this.openingId,
    required this.onOpen,
    required this.onActions,
  });

  final _TripHomeData data;
  final double page;

  /// 正在打开的那一份行程的 id。列表里只有这一行显示进度，
  /// 而不是整页盖一层遮罩。
  final String? openingId;

  final ValueChanged<TripSummary> onOpen;

  /// 打开某一行的重命名 / 删除入口。
  final ValueChanged<TripSummary> onActions;

  @override
  Widget build(BuildContext context) {
    final List<TripSummary> items = data.items;
    final TripSummary summary = items.first;
    final TodayInfo? today = data.today;
    final ApiFailure? failure = data.failure;
    final List<PlanStop> stops = today?.remaining ?? const <PlanStop>[];
    final bool openingLatest = openingId == summary.id;

    return ListView(
      padding: EdgeInsets.fromLTRB(page, 4, page, 36),
      children: <Widget>[
        // Next stop strip: the only heavy surface on the page, and the only
        // place the accent dot appears. Tapping it opens the newest plan.
        Material(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: openingLatest ? null : () => onOpen(summary),
            splashColor: AppColors.onInk.withValues(alpha: 0.08),
            highlightColor: AppColors.onInk.withValues(alpha: 0.04),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(
                          color: AppColors.kilnRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        '下一站',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.onInkMuted,
                        ),
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: AppColors.onInkMuted,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    today?.nextStop ?? '暂无安排',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.pageTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onInk,
                      height: AppTypography.headingHeight,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    today == null
                        ? '连接服务器后可查看今天的出发时间与天气'
                        : '${today.weather}  预计 ${today.arrival} 出发',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.onInkMuted,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: MeasureValue(
                value: '${summary.perPersonCost}',
                unit: '元/人',
                label: '人均预算',
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: MeasureValue(
                value: '${summary.daysCount}',
                unit: '天',
                label: '行程',
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: MeasureValue(value: summary.intensity, label: '行程强度'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                summary.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: DataStatusBadge(
                status: today?.status ?? summary.status,
                dense: true,
              ),
            ),
          ],
        ),
        if (failure != null) ...<Widget>[
          const SizedBox(height: 18),
          _Note(text: '${failure.message}当前显示本地缓存内容。', danger: true),
        ],
        const SizedBox(height: 30),
        const SectionRule(label: '今天的安排'),
        const SizedBox(height: 20),
        if (stops.isEmpty)
          const Text(
            '今天还没有具体安排。',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          )
        else
          RouteGauge(stops: stops, planStatus: today?.status ?? summary.status),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: openingLatest ? null : () => onOpen(summary),
            child: Text(openingLatest ? '正在打开…' : '打开完整行程'),
          ),
        ),
        const SizedBox(height: 30),
        // 历史行程。之前这一页只认 `list.items.first`，
        // 生成了第二份方案之后，第一份在界面上就没有入口了 —— 数据在服务端，
        // 但用户找不回来。这里是那个缺口。
        SectionRule(
          label: '全部行程',
          trailing: Text(
            '共 ${items.length} 份',
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          ),
        ),
        const SizedBox(height: 14),
        for (final TripSummary item in items) ...<Widget>[
          _TripRow(
            summary: item,
            opening: openingId == item.id,
            // 有别的行程正在打开时，先不让点，避免同时发起两次请求。
            onTap: openingId == null ? () => onOpen(item) : null,
            onActions: openingId == null ? () => onActions(item) : null,
          ),
          if (item != items.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

/// 历史列表里的一行。列表要能回答「这是哪一趟、多久、贵不贵、什么时候存的」，
/// 所以标题下面留了两行元信息，而不是只给一个标题。
class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.summary,
    required this.opening,
    required this.onTap,
    required this.onActions,
  });

  final TripSummary summary;
  final bool opening;
  final VoidCallback? onTap;

  /// Null while another row is being fetched, so two actions cannot overlap.
  final VoidCallback? onActions;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    summary.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${summary.daysCount} 天 · 人均 ¥${summary.perPersonCost}'
                    ' · 强度 ${summary.intensity}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: DataStatusBadge(
                          status: summary.status,
                          dense: true,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          formatChineseTimestamp(summary.updatedAt),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (opening)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              // 这一行有两个动作（打开 / 管理），所以末尾给的是"更多"而不是
              // 单纯的箭头：点卡片本身仍然是打开行程，箭头留在这里只会让人以为
              // 除了打开没有别的入口。
              IconButton(
                onPressed: onActions,
                tooltip: '重命名或删除这份行程',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                color: AppColors.crackle,
                icon: const Icon(Icons.more_horiz),
              ),
          ],
        ),
      );
}

/// What the row actions sheet can ask for.
enum _TripAction { rename, delete }

/// 一份行程能做的两件事。
///
/// 放在弹层里而不是行内：这一行的主要动作是"打开"，误触的代价不能是删掉一份方案。
/// 每条动作都带一句说明，讲清改什么、删掉的是什么 —— 删除不可撤销，
/// 用户有权在按下去之前知道代价。
class _TripActionsSheet extends StatelessWidget {
  const _TripActionsSheet({required this.summary});

  final TripSummary summary;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            4,
            AppSpacing.page,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                summary.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${summary.daysCount} 天 · 人均 ¥${summary.perPersonCost}'
                ' · ${summary.status}',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
              const SizedBox(height: 14),
              _SheetAction(
                icon: Icons.edit_outlined,
                label: '重命名',
                detail: '只改列表里的名字，逐日安排不动',
                onTap: () => Navigator.of(context).pop(_TripAction.rename),
              ),
              const SizedBox(height: 8),
              _SheetAction(
                icon: Icons.delete_outline,
                label: '删除这份行程',
                detail: '逐日安排与调整记录一并删除，无法恢复',
                danger: true,
                onTap: () => Navigator.of(context).pop(_TripAction.delete),
              ),
            ],
          ),
        ),
      );
}

/// One tappable row inside [_TripActionsSheet].
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String detail;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final Color accent = danger ? AppColors.kilnRed : AppColors.celadonDeep;
    final Color labelColor = danger ? AppColors.cautionText : AppColors.ink;
    return Material(
      color: danger ? AppColors.cautionSurface : AppColors.surfaceTint,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                        color: labelColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renames one plan. Returns the new title, or null when cancelled.
class _RenameTripDialog extends StatefulWidget {
  const _RenameTripDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameTripDialog> createState() => _RenameTripDialogState();
}

class _RenameTripDialogState extends State<_RenameTripDialog> {
  /// Kept in sync with the server side limit (`PatchRequest.title`),
  /// so a long paste fails in the field instead of on save.
  static const int _maxLength = 40;

  late final TextEditingController _controller =
      TextEditingController(text: widget.initialTitle);
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final String title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '名称不能为空。');
      return;
    }
    if (title.length > _maxLength) {
      setState(() => _error = '名称最多 $_maxLength 个字。');
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('重命名行程'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              key: const Key('trip-rename-field'),
              controller: _controller,
              autofocus: true,
              maxLength: _maxLength,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '行程名称',
                errorText: _error,
              ),
            ),
            const Text(
              '只改这一份行程在列表里的名字，逐日安排不受影响。',
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
                height: 1.5,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submit,
            child: const Text('保存'),
          ),
        ],
      );
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips({required this.failure, required this.onPlan});

  final ApiFailure? failure;
  final VoidCallback? onPlan;

  @override
  Widget build(BuildContext context) {
    final page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final failureText = failure?.message;
    final startPlanning = onPlan;
    return ListView(
      padding: EdgeInsets.all(page),
      children: <Widget>[
        const SizedBox(height: 40),
        const Icon(Icons.route_outlined, color: AppColors.celadon, size: 30),
        const SizedBox(height: 16),
        const Text(
          '还没有保存的行程',
          style: TextStyle(
            fontSize: AppTypography.sectionTitle,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          failureText ?? '生成一份旅行方案后，这里会显示今天的下一站和完整日程。',
          style: const TextStyle(
            fontSize: AppTypography.caption,
            color: AppColors.crackle,
            height: 1.6,
          ),
        ),
        if (startPlanning != null) ...<Widget>[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: startPlanning,
              child: const Text('去规划一份'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 图片与资料的出处，写成一段说明。
///
/// 景区照片要么是运营台上传的授权照片，要么是明确标注的占位示例图；
/// 这一段就是"这张图从哪来"的答案。配图本身有问题时（占位 / 缺图 /
/// 来源未登记）先给出状态说明，再列出已登记的出处 —— 让游客一眼看出
/// 眼前这张图还不是最终素材，而不是靠一行小字去猜。
String _imageCreditText(Destination destination) {
  final String notice = destination.imageNotice;
  final String credit = destination.imageCredit.trim();
  final String source = destination.sourceUrl.trim();
  return <String>[
    if (notice.isNotEmpty) notice,
    if (credit.isNotEmpty) '图片：$credit',
    if (source.isNotEmpty) '资料参考：$source',
  ].join('\n');
}

/// Attraction detail. The photograph is the one place imagery is allowed; the
/// facts below are set as label-value rows on the page rather than in cards.
class DestinationDetail extends ConsumerWidget {
  const DestinationDetail({super.key, required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final favorites =
        ref.watch(favoritesProvider).valueOrNull ?? const <FavoriteItem>[];
    final isFavorite = favorites.any((item) => item.poiId == destination.id);
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: AppColors.ink,
            foregroundColor: AppColors.onInk,
            actions: <Widget>[
              IconButton(
                onPressed: () => _toggleFavorite(context, ref),
                tooltip: isFavorite ? '取消收藏' : '收藏',
                icon: AppIcon(
                  AppIcons.favorite(selected: isFavorite),
                  size: 22,
                  color: isFavorite ? AppColors.amber : AppColors.onInk,
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 20,
                bottom: 14,
              ),
              title: Text(
                destination.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onInk,
                ),
              ),
              // Same plate as the discover grid: disk cached, themed
              // fallback, and the scrim keeps the title readable over any
              // photograph.
              background: PhotoPlate(
                url: destination.image,
                height: 260,
                fit: BoxFit.cover,
                scrim: true,
                semanticLabel: destination.name,
                fallbackLabel: destination.name,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 22, page, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate(<Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${destination.city} · ${destination.theme}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.crackle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: DataStatusBadge(
                        status: destination.dataStatus,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  destination.summary,
                  style: const TextStyle(
                    fontSize: AppTypography.lead,
                    height: 1.6,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 26),
                KeyValueRow(
                  label: '门票参考',
                  value: '¥${destination.ticket} 起',
                ),
                KeyValueRow(label: '建议游玩', value: destination.duration),
                KeyValueRow(label: '适合', value: destination.audience),
                const SizedBox(height: 30),
                const SectionRule(label: '为什么值得去'),
                const SizedBox(height: 12),
                const Text(
                  '这里既是河南文旅路线中的重要一站，也是适合慢下来阅读风物的地方。系统会结合你的时间、预算和天气，判断它是否适合放进当前行程。',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: AppColors.crackle,
                    height: 1.7,
                  ),
                ),
                const SizedBox(height: 26),
                const SectionRule(label: '出行提示'),
                const SizedBox(height: 12),
                _Note(text: destination.weatherTip),
                if (destination.showsImageSourceSection) ...<Widget>[
                  const SizedBox(height: 26),
                  const SectionRule(label: '图片来源'),
                  const SizedBox(height: 12),
                  _Note(text: _imageCreditText(destination)),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => JourneyScreen(
                          repository: ref.read(travelRepositoryProvider),
                        ),
                      ),
                    ),
                    child: const Text('以此景点开始规划'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Favourites live on the account, so this is also the point where an
  /// anonymous visitor is told why signing in matters.
  Future<void> _toggleFavorite(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    if (ref.read(sessionProvider).valueOrNull == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('收藏需要登录。请到「我的」登录后再试。')),
        );
      return;
    }
    try {
      await ref.read(favoritesProvider.notifier).toggle(
            poiId: destination.id,
            poiName: destination.name,
            city: destination.city,
            imageUrl: destination.image,
          );
      final isFavorite =
          ref.read(favoritesProvider.notifier).contains(destination.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(isFavorite ? '已加入收藏。' : '已取消收藏。')),
        );
    } on ApiFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.danger = false});

  final String text;
  final bool danger;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            danger ? Icons.error_outline : Icons.info_outline,
            size: 16,
            color: danger ? AppColors.kilnRed : AppColors.celadon,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: danger ? AppColors.riskText : AppColors.crackle,
                height: 1.6,
              ),
            ),
          ),
        ],
      );
}
