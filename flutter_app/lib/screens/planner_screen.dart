import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/formatters/chinese_date.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/city_picker_sheet.dart';
import '../core/widgets/date_picker_sheet.dart';
import '../core/widgets/form_controls.dart';
import '../core/widgets/measure_value.dart';
import '../core/widgets/option_sheet.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/route_selector.dart';
import '../core/widgets/section_header.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../data/repositories/travel_repository.dart';
import '../models/travel_models.dart';
import '../models/trip_models.dart';
import 'additional_screens.dart';
import 'journey/trip_result_view.dart';
import 'trip_screen.dart';

/// 出发日期在请求体里的唯一写法：yyyy-MM-dd。
///
/// 服务端按这个字段查天气与车次、给每一天打日期，所以格式化只能有一份实现，
/// 页头展示与请求体必须给出同一个字符串。
String _formatDate(DateTime date) {
  final String month = date.month.toString().padLeft(2, '0');
  final String day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

/// The journey page: everything from "here is what I want" to "here is the
/// plan, day by day".
///
/// 规划 and 行程 used to be two tabs that rendered the same object at different
/// moments. They are now one page: the condition card collapses into a summary
/// once a plan exists, and the plan is laid out underneath it.
class JourneyScreen extends ConsumerStatefulWidget {
  const JourneyScreen({super.key, required this.repository});

  final TravelRepository repository;

  @override
  ConsumerState<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends ConsumerState<JourneyScreen> {
  /// 行程天数的范围。服务端 `PlanDates.resolveDays` 的上限也是 7，
  /// 两边必须是同一个数：界面放开到 10、后端悄悄截成 7，
  /// 用户看到的就是「我填了 10 天，方案只给 7 天」。
  static const int _minDays = 1;
  static const int _maxDays = 7;

  final TextEditingController _budget = TextEditingController(text: '3000');
  final TextEditingController _note = TextEditingController();

  /// 天数的输入框与它自己的焦点。天数真正的值仍然是 `_days`，
  /// 输入框只是它的一个显示，失焦时会被重新对齐（见 [_syncDaysField]）。
  final TextEditingController _daysField = TextEditingController(text: '2');
  final FocusNode _daysFocus = FocusNode();

  /// Names of the steps the backend planning pipeline performs, in order. Shown
  /// while a request is in flight so the wait has a shape. It is labelled as the
  /// pipeline order, not as live tool output.
  static const List<String> _pipeline = <String>[
    '理解旅行偏好',
    '查询景点与开放时间',
    '计算交通路线',
    '获取天气与出行可行性',
    '估算预算与行程强度',
    '校验时间冲突与风险',
  ];

  PlanResult? _result;
  bool _loading = false;

  /// "我的行程"弹层已经开着的时候，不再压第二层。
  /// 快速连点两下会 push 两条一样的路由，按一次返回还停在同一页。
  bool _historyOpen = false;
  bool _conditionsOpen = true;

  /// 行程页现在是两态：默认是"我的行程"首页，点"新建一个行程"才进入规划表单。
  ///
  /// 以前这一页一进来就 `_restoreLatest()`，把最新那份行程直接摊开，
  /// 于是"行程"tab 看起来永远只有一份行程，历史与足迹都没有位置。
  bool _plannerOpen = false;
  int _step = 0;
  Timer? _ticker;
  Map<String, String> _images = const <String, String>{};

  String _origin = '郑州';
  String _destination = '洛阳';
  DateTime _startDate = DateTime.now().add(const Duration(days: 1));
  int _days = 2;
  int _adults = 2;
  int _children = 0;
  String _pace = '适中';
  String _transport = '高铁 + 打车';
  final Set<String> _interests = <String>{'历史人文'};

  /// 用户自己加的兴趣与节奏。基础选项是常量，自定义的值只能活在状态里，
  /// 所以它们放在这一层而不是胶囊组件内部——卡片折叠再展开时不该丢。
  final List<String> _customInterests = <String>[];
  final List<String> _customPaces = <String>[];

  /// 最近选过的城市，城市选择器拿它做「最近使用」。
  final List<String> _recentCities = <String>[];

  static const List<String> _interestOptions = <String>[
    '历史人文',
    '自然风光',
    '地道美食',
    '深度研学',
    '亲子出行',
  ];
  static const List<String> _paces = <String>['轻松', '适中', '紧凑'];

  /// 交通方式与那句解释。选项本身说不清代价（「自驾」意味着停车和油费），
  /// 解释是做决定用的，不是装饰。
  static const Map<String, String> _transportDetails = <String, String>{
    '高铁 + 打车': '城际坐高铁，市内以打车为主',
    '公共交通': '地铁与公交优先，成本最低',
    '自驾': '全程自驾，适合山水类目的地',
    '混合出行': '高铁进城，市内地铁加打车',
  };

  @override
  void initState() {
    super.initState();
    _daysFocus.addListener(_onDaysFocusChanged);
    // 从首页带着一句话过来时直接进表单：用户已经表达过意图，再让他点一次
    // "新建一个行程"是多余的一步。其余情况都停在"我的行程"首页。
    final String? pending = ref.read(pendingPromptProvider);
    _plannerOpen = pending != null && pending.isNotEmpty;
    if (_plannerOpen) {
      _note.text = pending!;
      unawaited(_loadCatalog());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _budget.dispose();
    _note.dispose();
    _daysField.dispose();
    _daysFocus.dispose();
    super.dispose();
  }

  /// 天数输入框拿到焦点时全选，用户直接敲数字就能替换；
  /// 失焦时把文字拉回真实值，避免出现「框里写着 9、实际按 2 天生成」。
  void _onDaysFocusChanged() {
    if (_daysFocus.hasFocus) {
      _daysField.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _daysField.text.length,
      );
      return;
    }
    _syncDaysField();
  }

  void _syncDaysField() {
    final String text = '$_days';
    if (_daysField.text != text) {
      _daysField.text = text;
    }
  }

  /// 天数的唯一写入口。夹到合法区间，并让输入框跟上。
  void _setDays(int value) {
    final int clamped = value < _minDays
        ? _minDays
        : value > _maxDays
            ? _maxDays
            : value;
    setState(() => _days = clamped);
    if (_daysField.text != '$clamped') {
      _daysField.text = '$clamped';
      _daysField.selection = TextSelection.collapsed(
        offset: _daysField.text.length,
      );
    }
  }

  /// 键盘输入。超范围立刻夹回并把框里的字改掉，让用户当场看到上限，
  /// 而不是等到生成完才发现天数和填的不一样。
  void _onDaysTyped(String raw) {
    final int? parsed = int.tryParse(raw.trim());
    if (parsed == null) {
      return;
    }
    if (parsed < _minDays) {
      _setDays(_minDays);
      return;
    }
    if (parsed > _maxDays) {
      _setDays(_maxDays);
      return;
    }
    setState(() => _days = parsed);
  }

  /// 交换出发地与目的地。交换按钮的动画由 RouteSelector 负责，这里只改值。
  void _swapRoute() {
    setState(() {
      final String previous = _origin;
      _origin = _destination;
      _destination = previous;
    });
  }

  /// 打开城市选择弹层。出发地和目的地共用同一个弹层，只有标题不同。
  Future<void> _pickCity({required bool isOrigin}) async {
    final String? picked = await showCityPickerSheet(
      context,
      title: isOrigin ? '选择出发地' : '选择目的地',
      selected: isOrigin ? _origin : _destination,
      recent: _recentCities,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      // 选成和另一边同一个城市时，与其留下一份「从郑州到郑州」的方案，
      // 不如把两边对调 —— 用户的意图几乎总是「我想反着走」。
      if (isOrigin) {
        if (picked == _destination) {
          _destination = _origin;
        }
        _origin = picked;
      } else {
        if (picked == _origin) {
          _origin = _destination;
        }
        _destination = picked;
      }
      // 最近使用最多留 6 个，新的排前面。
      _recentCities
        ..remove(picked)
        ..insert(0, picked);
      if (_recentCities.length > 6) {
        _recentCities.removeRange(6, _recentCities.length);
      }
    });
  }

  Future<void> _pickTransport() async {
    final String? picked = await showOptionSheet(
      context,
      title: '交通方式',
      subtitle: '这一项决定方案里城际与市内的衔接方式，生成后仍可修改。',
      options: _transportDetails.keys.toList(),
      selected: _transport,
      details: _transportDetails,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() => _transport = picked);
  }

  void _addCustomInterest(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return;
    }
    setState(() {
      // 和基础选项重名时不再新加一个胶囊，直接选中已有的那个。
      if (!_interestOptions.contains(value) &&
          !_customInterests.contains(value)) {
        _customInterests.add(value);
      }
      _interests.add(value);
    });
  }

  void _addCustomPace(String raw) {
    final String value = raw.trim();
    if (value.isEmpty) {
      return;
    }
    setState(() {
      if (!_paces.contains(value) && !_customPaces.contains(value)) {
        _customPaces.add(value);
      }
      _pace = value;
    });
  }

  /// Joins the content library so each day card can show the photograph of the
  /// attraction it names. A miss simply leaves the card text only.
  Future<void> _loadCatalog() async {
    try {
      final CatalogResult catalog = await widget.repository.fetchDestinations();
      if (!mounted) {
        return;
      }
      setState(() {
        _images = <String, String>{
          for (final Destination destination in catalog.destinations)
            if (destination.image.isNotEmpty) destination.name: destination.image,
        };
      });
    } on ApiFailure {
      // The catalog is decoration here; the journey still works without it.
    }
  }

  /// 从"我的行程"首页进入规划表单。
  ///
  /// 顺带消费一次首页带过来的那句话：消费掉之后，用户从表单返回首页再进来，
  /// 看到的就是干净的空表单，而不是上一句话还留在备注里。
  void _openPlanner() {
    final String? pending = ref.read(pendingPromptProvider);
    setState(() {
      _plannerOpen = true;
      _conditionsOpen = true;
      if (pending != null && pending.isNotEmpty) {
        _note.text = pending;
      }
    });
    if (pending != null && pending.isNotEmpty) {
      ref.read(pendingPromptProvider.notifier).state = null;
    }
    unawaited(_loadCatalog());
  }

  /// 回到"我的行程"首页。已经生成的方案不会被丢掉：它已经存到服务端，
  /// 首页的"最近一次行程"与历史行程都能再打开。
  void _closePlanner() {
    FocusScope.of(context).unfocus();
    setState(() => _plannerOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    // A sentence typed on the discover page lands here as the free text note,
    // so that entrance is a real hand off rather than a second input.
    ref.listen<String?>(pendingPromptProvider, (String? previous, String? next) {
      if (next == null || next.isEmpty) {
        return;
      }
      _note.text = next;
      ref.read(pendingPromptProvider.notifier).state = null;
      unawaited(_loadCatalog());
      setState(() {
        _plannerOpen = true;
        _conditionsOpen = true;
        // 新的需求 = 重新开始：上一份结果留在历史行程里，不再占着这张表单。
        _result = null;
      });
    });

    if (!_plannerOpen) {
      return _JourneyHub(repository: widget.repository, onCreate: _openPlanner);
    }
    return _buildPlanner(context);
  }

  Widget _buildPlanner(BuildContext context) {
    final double viewport = MediaQuery.sizeOf(context).width;
    final double page = AppSpacing.pageFor(viewport);

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        title: const Text('规划行程'),
        leading: IconButton(
          onPressed: _closePlanner,
          tooltip: '返回我的行程',
          icon: const Icon(Icons.arrow_back, size: 20),
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _openHistory,
            tooltip: '我的行程',
            icon: const Icon(Icons.bookmarks_outlined, size: 20),
          ),
        ],
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(page, 4, page, 40),
        children: <Widget>[
          if (_result == null) ...<Widget>[
            const _JourneyIntro(),
            const SizedBox(height: AppSpacing.section),
          ],
          _ConditionCard(
            open: _conditionsOpen,
            hasPlan: _result != null,
            onToggle: () => setState(() => _conditionsOpen = !_conditionsOpen),
            origin: _origin,
            destination: _destination,
            onSwap: _swapRoute,
            onPickOrigin: () => _pickCity(isOrigin: true),
            onPickDestination: () => _pickCity(isOrigin: false),
            startDate: _startDate,
            onStartDate: _pickDate,
            days: _days,
            daysController: _daysField,
            daysFocus: _daysFocus,
            minDays: _minDays,
            maxDays: _maxDays,
            onDays: _setDays,
            onDaysTyped: _onDaysTyped,
            adults: _adults,
            children: _children,
            onAdults: (int value) => setState(() => _adults = value),
            onChildren: (int value) => setState(() => _children = value),
            pace: _pace,
            paces: <String>[..._paces, ..._customPaces],
            onPace: (String value) => setState(() => _pace = value),
            transport: _transport,
            onPickTransport: _pickTransport,
            interests: _interests,
            interestOptions: <String>[..._interestOptions, ..._customInterests],
            onInterest: (String value) => setState(() {
              if (!_interests.remove(value)) {
                _interests.add(value);
              }
            }),
            onAddInterest: _addCustomInterest,
            onAddPace: _addCustomPace,
            budget: _budget,
            note: _note,
            loading: _loading,
            onGenerate: _generate,
          ),
          if (_loading) ...<Widget>[
            const SizedBox(height: AppSpacing.section),
            _PlanningProgress(step: _step, steps: _pipeline),
          ],
          if (_result != null) ...<Widget>[
            const SizedBox(height: AppSpacing.section),
            if (_result!.isFallback) ...<Widget>[
              _FallbackNotice(failure: _result!.failure!),
              const SizedBox(height: AppSpacing.content),
            ],
            TripResultView(
              plan: _result!.plan,
              budgetPerPerson: _parsedBudget,
              startDate: _startDate,
              images: _images,
              onPlanChanged: (TravelPlan next) => setState(
                () => _result =
                    PlanResult(plan: next, failure: _result!.failure),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int? get _parsedBudget {
    final int? value = int.tryParse(_budget.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  /// 出行日期用产品自己的中文日历弹层。
  ///
  /// 之前这里调的是 Material 的 `showDatePicker`，实机弹出来的是
  /// 「Sat, Oct 3 / October 2026 / CANCEL / OK」——项目没有本地化包，
  /// 组件只剩英文一种写法。换成 `showChineseDateSheet` 之后整块弹层都是中文，
  /// 顺带多了「今天 / 明天 / 后天 / 下周六」四个快捷入口。
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showChineseDateSheet(
      context,
      initialDate: _startDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _startDate = picked);
    }
  }

  /// Composes the sentence the planner receives. The structured fields are
  /// spelled out so the extraction step has something concrete to work with
  /// even when the free text is vague.
  String _composePrompt() {
    final StringBuffer buffer = StringBuffer()
      ..write('从$_origin出发前往$_destination，')
      ..write('$_days 天行程，')
      ..write('同行${_adults + _children}人')
      ..write(_children > 0 ? '（含$_children 名儿童）' : '')
      ..write('，');
    final int? budget = _parsedBudget;
    if (budget != null) {
      buffer.write('预算每人 $budget 元，');
    }
    if (_interests.isNotEmpty) {
      buffer.write('兴趣偏好：${_interests.join('、')}，');
    }
    buffer
      ..write('节奏$_pace，')
      ..write('交通方式$_transport。');
    final String note = _note.text.trim();
    if (note.isNotEmpty) {
      buffer.write(note);
    }
    return buffer.toString();
  }

  Future<void> _generate() async {
    if (_adults + _children <= 0) {
      _notify('同行人数至少 1 人。');
      return;
    }
    setState(() {
      _loading = true;
      _step = 0;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 900), (Timer timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _step = (_step + 1).clamp(0, _pipeline.length - 1));
    });

    try {
      final PlanResult created = await widget.repository.createPlan(
        prompt: _composePrompt(),
        // 出发日期必须随请求上去：服务端用它查天气与车次、并给每一天打上日期。
        // 少了这一行，用户选的那天就只在客户端显示，方案里会出现另一个日期。
        startDate: _formatDate(_startDate),
        origin: _origin,
        destination: _destination,
        people: _adults + _children,
        days: _days,
        budgetPerPerson: _parsedBudget,
        interests: _interests.join('、'),
        pace: _pace,
        transport: _transport,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _result = created;
        _loading = false;
        _conditionsOpen = false;
      });
      FocusScope.of(context).unfocus();
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      _notify(failure.message);
    } finally {
      _ticker?.cancel();
    }
  }

  Future<void> _openHistory() async {
    if (_historyOpen) {
      return;
    }
    _historyOpen = true;
    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (BuildContext context) =>
              TripHomeScreen(onPlan: () => Navigator.of(context).pop()),
        ),
      );
    } finally {
      _historyOpen = false;
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _JourneyIntro extends StatelessWidget {
  const _JourneyIntro();

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '把条件交给它，\n拿到一份走得通的行程。',
            style: TextStyle(
              fontSize: AppTypography.pageTitle,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              height: AppTypography.headingHeight,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '先填出行条件，生成后会给出逐日安排、预算拆解和四项风险核对。首次体验无需登录。',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
              height: 1.6,
            ),
          ),
        ],
      );
}

/// A failure that reached the user as a fallback still has to be named, so the
/// plan below is never mistaken for a live server response.
class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.failure});

  final ApiFailure failure;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.cautionSurface,
        shadow: const <BoxShadow>[],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.cloud_off_outlined,
              size: 16,
              color: AppColors.cautionText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '当前展示的是降级结果：${failure.message}',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.cautionText,
                  height: 1.55,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PlanningProgress extends StatelessWidget {
  const _PlanningProgress({required this.step, required this.steps});

  final int step;
  final List<String> steps;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SectionHeader(
              title: '正在生成行程',
              subtitle: '按后端规划管线的顺序展示，完成后可在「方案依据」查看真实调用记录。',
              icon: Icons.auto_awesome_motion_outlined,
            ),
            const SizedBox(height: 14),
            const LinearProgressIndicator(minHeight: 4),
            const SizedBox(height: 14),
            for (int i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: i < step
                          ? const Icon(
                              Icons.check_circle,
                              size: 16,
                              color: AppColors.settled,
                            )
                          : i == step
                              ? const CircularProgressIndicator(strokeWidth: 2)
                              : const Icon(
                                  Icons.circle_outlined,
                                  size: 14,
                                  color: AppColors.celadonPale,
                                ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        steps[i],
                        style: TextStyle(
                          fontSize: AppTypography.secondary,
                          fontWeight:
                              i == step ? FontWeight.w700 : FontWeight.w500,
                          color: i == step ? AppColors.ink : AppColors.crackle,
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

/// The condition form. Collapses to a one line summary once a plan exists, so
/// the result is not pushed a whole screen down.
///
/// 版式取舍：
/// * 出发地 / 目的地是这一屏的主控件，用 [RouteSelector] 独占一行，中间可交换；
/// * 出行日期与行程天数是第二重要，并排一行；
/// * 同行人数压成一行两个计数，不再各占一整行；
/// * 兴趣、体力在末尾各带一个自定义入口，输入行独立成行，不与胶囊抢位置。
///
/// 选择类控件全部自己实现（[SelectChip] / [PickerField]），
/// 不用 Material 的 Chip 与 DropdownButtonFormField：这两个组件在 M3 下
/// 选中态的底色和文字色由组件自己推断，主题里只改一半就会出现深底深字，
/// 展开态则会弹出一块没有任何样式的矩形列表。
class _ConditionCard extends StatelessWidget {
  const _ConditionCard({
    required this.open,
    required this.hasPlan,
    required this.onToggle,
    required this.origin,
    required this.destination,
    required this.onSwap,
    required this.onPickOrigin,
    required this.onPickDestination,
    required this.startDate,
    required this.onStartDate,
    required this.days,
    required this.daysController,
    required this.daysFocus,
    required this.minDays,
    required this.maxDays,
    required this.onDays,
    required this.onDaysTyped,
    required this.adults,
    required this.children,
    required this.onAdults,
    required this.onChildren,
    required this.pace,
    required this.paces,
    required this.onPace,
    required this.transport,
    required this.onPickTransport,
    required this.interests,
    required this.interestOptions,
    required this.onInterest,
    required this.onAddInterest,
    required this.onAddPace,
    required this.budget,
    required this.note,
    required this.loading,
    required this.onGenerate,
  });

  final bool open;
  final bool hasPlan;
  final VoidCallback onToggle;

  final String origin;
  final String destination;
  final VoidCallback onSwap;
  final VoidCallback onPickOrigin;
  final VoidCallback onPickDestination;

  final DateTime startDate;
  final VoidCallback onStartDate;

  final int days;
  final TextEditingController daysController;
  final FocusNode daysFocus;
  final int minDays;
  final int maxDays;
  final ValueChanged<int> onDays;
  final ValueChanged<String> onDaysTyped;

  final int adults;
  final int children;
  final ValueChanged<int> onAdults;
  final ValueChanged<int> onChildren;

  final String pace;
  final List<String> paces;
  final ValueChanged<String> onPace;

  final String transport;
  final VoidCallback onPickTransport;

  final Set<String> interests;
  final List<String> interestOptions;
  final ValueChanged<String> onInterest;
  final ValueChanged<String> onAddInterest;
  final ValueChanged<String> onAddPace;

  final TextEditingController budget;
  final TextEditingController note;
  final bool loading;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    if (!open && hasPlan) {
      return SurfaceCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        onTap: onToggle,
        child: Row(
          children: <Widget>[
            const Icon(Icons.tune, size: 18, color: AppColors.celadonDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    '出行条件',
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$origin → $destination · '
                    '${formatChineseDateCompact(startDate)} · '
                    '$days 天 · ${adults + children} 人',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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
            const Text(
              '修改',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                fontWeight: FontWeight.w700,
                color: AppColors.celadonDeep,
              ),
            ),
            const Icon(Icons.expand_more, size: 18, color: AppColors.celadonDeep),
          ],
        ),
      );
    }

    final String? relative = relativeDayLabel(startDate);
    return SurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            onTap: hasPlan ? onToggle : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
                AppSpacing.cardPadding,
                AppSpacing.content,
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.tune, size: 18, color: AppColors.celadonDeep),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '出行条件',
                      style: TextStyle(
                        fontSize: AppTypography.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  if (hasPlan)
                    const Icon(
                      Icons.expand_less,
                      size: 20,
                      color: AppColors.crackle,
                    ),
                ],
              ),
            ),
          ),
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
                RouteSelector(
                  origin: origin,
                  destination: destination,
                  onSwap: onSwap,
                  onPickOrigin: onPickOrigin,
                  onPickDestination: onPickDestination,
                  enabled: !loading,
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          FieldLabel(
                            relative == null ? '出行日期' : '出行日期 · $relative',
                          ),
                          PickerField(
                            key: const Key('planner-date-field'),
                            value: formatChineseDateCompact(startDate),
                            enabled: !loading,
                            onTap: onStartDate,
                            semanticLabel:
                                '出行日期，当前 ${formatChineseDate(startDate)}，点开选择',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const FieldLabel('行程天数'),
                          _DayInput(
                            key: const Key('planner-days-stepper'),
                            controller: daysController,
                            focusNode: daysFocus,
                            days: days,
                            min: minDays,
                            max: maxDays,
                            enabled: !loading,
                            onStep: onDays,
                            onTyped: onDaysTyped,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                const FieldLabel('同行人数'),
                _TravelersRow(
                  adults: adults,
                  children: children,
                  enabled: !loading,
                  onAdults: onAdults,
                  onChildren: onChildren,
                ),
                const SizedBox(height: 18),
                const FieldLabel('总预算（元 / 人）'),
                TextField(
                  controller: budget,
                  enabled: !loading,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(hintText: '例如 3000'),
                ),
                const SizedBox(height: 18),
                _ChipGroup(
                  label: '兴趣偏好',
                  options: interestOptions,
                  enabled: !loading,
                  showCheck: true,
                  isSelected: (String option) => interests.contains(option),
                  onToggle: onInterest,
                  customHint: '输入自定义兴趣，例如：摄影',
                  onAdd: onAddInterest,
                ),
                const SizedBox(height: 18),
                _ChipGroup(
                  label: '体力偏好',
                  options: paces,
                  enabled: !loading,
                  isSelected: (String option) => pace == option,
                  onToggle: onPace,
                  customHint: '输入自定义节奏，例如：每天只安排半天',
                  onAdd: onAddPace,
                ),
                const SizedBox(height: 18),
                const FieldLabel('交通方式'),
                PickerField(
                  key: const Key('planner-transport-field'),
                  value: transport,
                  icon: Icons.commute_outlined,
                  enabled: !loading,
                  onTap: onPickTransport,
                  semanticLabel: '交通方式，当前 $transport，点开更换',
                ),
                const SizedBox(height: 18),
                const FieldLabel('补充要求（可选）'),
                TextField(
                  controller: note,
                  enabled: !loading,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '例如：想避开人流高峰、希望安排一晚夜游、老人不要爬太多台阶…',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: loading ? null : onGenerate,
                    icon: loading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.onInk,
                            ),
                          )
                        : const Icon(Icons.route_outlined, size: 18),
                    label: Text(
                      loading
                          ? '正在生成…'
                          : (hasPlan ? '重新生成行程' : '生成专属行程'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '系统会核对开放时间、路线耗时、天气与预算，再给出可执行方案。生成失败时会说明原因，不会把降级数据说成实时数据。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 行程天数的输入控件。
///
/// 换掉了原来的 Slider：一，可拖的范围只有 1—3 天，拇指停在中点时说不清
/// 到底选了几；二，需求要的是自己输入。现在是「− 数字 天 +」——
/// 数字可以直接点开键盘改（拿到焦点时全选，敲一下就能替换），
/// 两侧的加减留给单手操作。
class _DayInput extends StatelessWidget {
  const _DayInput({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.days,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onStep,
    required this.onTyped,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int days;
  final int min;
  final int max;
  final bool enabled;

  /// 传入调整之后的绝对值，不是增量。
  final ValueChanged<int> onStep;

  final ValueChanged<String> onTyped;

  @override
  Widget build(BuildContext context) => Container(
        height: AppSpacing.buttonHeight,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
          border: Border.all(color: AppColors.hairline),
        ),
        child: Row(
          children: <Widget>[
            _StepButton(
              icon: Icons.remove,
              label: '减少一天',
              enabled: enabled && days > min,
              onTap: () => onStep(days - 1),
            ),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 24,
                    child: TextField(
                      key: const Key('planner-days-input'),
                      controller: controller,
                      focusNode: focusNode,
                      enabled: enabled,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      // 位数跟着上限走，写死 1 会在范围调整后变成隐藏的坑。
                      maxLength: max >= 10 ? 2 : 1,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: onTyped,
                      decoration: const InputDecoration(
                        isDense: true,
                        filled: false,
                        counterText: '',
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                      ),
                      style: const TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    '天',
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      color: AppColors.crackle,
                    ),
                  ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.add,
              label: '增加一天',
              enabled: enabled && days < max,
              onTap: () => onStep(days + 1),
            ),
          ],
        ),
      );
}

/// 同行人数：一行两个计数。
///
/// 之前成人、儿童各占一整行灰条，把「日期 / 天数 / 人数」这三组信息
/// 拉成了一长条。现在压成一行两块，中间一道细分隔线，仍然是一眼能读完的一组。
class _TravelersRow extends StatelessWidget {
  const _TravelersRow({
    required this.adults,
    required this.children,
    required this.enabled,
    required this.onAdults,
    required this.onChildren,
  });

  final int adults;
  final int children;
  final bool enabled;
  final ValueChanged<int> onAdults;
  final ValueChanged<int> onChildren;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.ground,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: <Widget>[
              Expanded(
                child: _Counter(
                  label: '成人',
                  value: adults,
                  min: 1,
                  max: 12,
                  enabled: enabled,
                  onChanged: onAdults,
                ),
              ),
              const VerticalDivider(
                width: 10,
                thickness: 1,
                color: AppColors.hairline,
              ),
              Expanded(
                child: _Counter(
                  label: '儿童',
                  value: children,
                  min: 0,
                  max: 8,
                  enabled: enabled,
                  onChanged: onChildren,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 一个紧凑的计数块：标签 + − 数值 +。
///
/// 值本身也是可读的文本而不是只靠两个按钮，读屏和截图都能直接看出人数。
class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: AppTypography.secondary,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.remove,
            label: '减少$label',
            enabled: enabled && value > min,
            onTap: () => onChanged(value - 1),
          ),
          SizedBox(
            width: 24,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTypography.cardTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
                fontFeatures: AppTypography.tabularFigures,
                height: AppTypography.tightHeight,
              ),
            ),
          ),
          _StepButton(
            icon: Icons.add,
            label: '增加$label',
            enabled: enabled && value < max,
            onTap: () => onChanged(value + 1),
          ),
        ],
      );
}

/// 加 / 减。
///
/// 视觉直径 32，比 IconButton 默认的 48 小：把人数压进一行必须让出一部分
/// 触点面积，两个按钮整体仍然在一个 40 高的控件里，单手点得到。
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Material(
          color: enabled ? AppColors.surface : Colors.transparent,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled ? onTap : null,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Icon(
                icon,
                size: 16,
                color: enabled
                    ? AppColors.celadonDeep
                    : AppColors.crackle.withValues(alpha: 0.35),
              ),
            ),
          ),
        ),
      );
}

/// 一组可选胶囊，末尾带一个「自定义」入口。
///
/// 自定义输入行独立成一行，**不塞进 Wrap 里**：塞进去的话，
/// 一个很长的自定义值会把最后一行胶囊挤得重新折行，输入框自己也会随字数变形。
/// 独立成行之后，无论加多少字、加多少个自定义值，胶囊区都只是多折一行。
class _ChipGroup extends StatefulWidget {
  const _ChipGroup({
    required this.label,
    required this.options,
    required this.isSelected,
    required this.onToggle,
    required this.customHint,
    required this.onAdd,
    this.showCheck = false,
    this.enabled = true,
  });

  final String label;
  final List<String> options;
  final bool Function(String) isSelected;
  final ValueChanged<String> onToggle;

  /// 自定义输入框的提示语，写清楚这里能填什么。
  final String customHint;

  final ValueChanged<String> onAdd;
  final bool showCheck;
  final bool enabled;

  @override
  State<_ChipGroup> createState() => _ChipGroupState();
}

class _ChipGroupState extends State<_ChipGroup> {
  final TextEditingController _custom = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _toggleEditor() => setState(() {
        _editing = !_editing;
        if (!_editing) {
          _custom.clear();
        }
      });

  void _submit() {
    final String value = _custom.text.trim();
    if (value.isEmpty) {
      return;
    }
    widget.onAdd(value);
    setState(() {
      _custom.clear();
      _editing = false;
    });
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          FieldLabel(widget.label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String option in widget.options)
                SelectChip(
                  label: option,
                  selected: widget.isSelected(option),
                  showCheck: widget.showCheck,
                  enabled: widget.enabled,
                  onTap: () => widget.onToggle(option),
                ),
              SelectChip(
                label: _editing ? '取消自定义' : '自定义',
                icon: _editing ? Icons.close : Icons.add,
                selected: _editing,
                enabled: widget.enabled,
                onTap: _toggleEditor,
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topLeft,
            child: _editing
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _editor(),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      );

  Widget _editor() => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: TextField(
              key: ValueKey<String>('custom-input-${widget.label}'),
              controller: _custom,
              autofocus: true,
              enabled: widget.enabled,
              textInputAction: TextInputAction.done,
              maxLength: 10,
              onSubmitted: (String _) => _submit(),
              decoration: InputDecoration(
                hintText: widget.customHint,
                isDense: true,
                counterText: '',
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: widget.enabled ? _submit : null, child: const Text('添加')),
        ],
      );
}


/// "行程"tab 的首页。
///
/// 用户给的版式很明确：标题 + 最近一份行程 + 两个入口 + 你的足迹。
/// 这一页的第一职责是回答"我要去哪"，而不是立刻摊开一份行程，
/// 所以数据只在用户点下去之后才取。
class _JourneyHub extends StatefulWidget {
  const _JourneyHub({required this.repository, required this.onCreate});

  final TravelRepository repository;

  /// 进入规划表单。
  final VoidCallback onCreate;

  @override
  State<_JourneyHub> createState() => _JourneyHubState();
}

class _JourneyHubState extends State<_JourneyHub> {
  late Future<_HubData> _future;
  String? _openingId;

  /// 历史页弹层已经开着的时候，不再压第二层（理由同 _PlannerScreenState）。
  bool _historyOpen = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_HubData> _load() async {
    final TripListResult trips = await widget.repository.fetchTripPlans();
    final FootprintResult footprint = await widget.repository.fetchFootprint();
    return _HubData(trips: trips, footprint: footprint);
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _open(TripSummary summary) async {
    if (_openingId != null) {
      return;
    }
    // 先取到两个 State 再 await：await 之后再用 context 是不安全的。
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _openingId = summary.id);
    try {
      final PlanResult result =
          await widget.repository.fetchTripPlan(summary.id);
      if (!mounted) {
        return;
      }
      setState(() => _openingId = null);
      await navigator.push(
        MaterialPageRoute<void>(builder: (_) => TripScreen(plan: result.plan)),
      );
    } on ApiFailure catch (failure) {
      if (!mounted) {
        return;
      }
      setState(() => _openingId = null);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _openHistory() async {
    if (_historyOpen) {
      return;
    }
    _historyOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const TripHomeScreen()),
      );
    } finally {
      _historyOpen = false;
    }
    // 历史页里可能删了或改了名字，回来重新取一次，不在本地假装同步。
    if (mounted) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(page, 16, page, 36),
        children: <Widget>[
          _HubHeader(onRefresh: _reload),
          const SizedBox(height: 18),
          FutureBuilder<_HubData>(
            future: _future,
            builder: (BuildContext context, AsyncSnapshot<_HubData> snapshot) {
              final _HubData? data = snapshot.data;
              final bool loading =
                  snapshot.connectionState != ConnectionState.done;
              final List<TripSummary> items = data?.trips.items ?? const <TripSummary>[];
              final TripSummary? latest = items.isEmpty ? null : items.first;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (latest != null) ...<Widget>[
                    _RecentTripCard(
                      summary: latest,
                      opening: _openingId == latest.id,
                      onTap: () => _open(latest),
                    ),
                    const SizedBox(height: AppSpacing.content),
                  ] else if (loading) ...<Widget>[
                    const _HubLoadingCard(),
                    const SizedBox(height: AppSpacing.content),
                  ],
                  _HubActionCard(
                    primary: true,
                    icon: Icons.add,
                    title: '新建一个行程',
                    subtitle: '创建旅行计划',
                    onTap: widget.onCreate,
                  ),
                  const SizedBox(height: AppSpacing.content),
                  _HubActionCard(
                    primary: false,
                    icon: Icons.history,
                    title: '查看历史行程',
                    subtitle: '回顾走过的路',
                    onTap: _openHistory,
                  ),
                  const SizedBox(height: AppSpacing.section),
                  const _FootprintRule(),
                  const SizedBox(height: AppSpacing.content),
                  _FootprintCard(
                    result: data?.footprint,
                    loading: loading,
                    onCreate: widget.onCreate,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _HubData {
  const _HubData({required this.trips, required this.footprint});

  final TripListResult trips;
  final FootprintResult footprint;
}

class _HubHeader extends StatelessWidget {
  const _HubHeader({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '我的行程',
                  style: TextStyle(
                    fontSize: AppTypography.pageTitle,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: AppTypography.headingHeight,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '记录每一次出发与抵达',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            tooltip: '刷新',
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      );
}

/// 最近一份行程。用品牌色的渐变卡把它和下面两个入口区分开：它是"继续"，不是"开始"。
class _RecentTripCard extends StatelessWidget {
  const _RecentTripCard({
    required this.summary,
    required this.opening,
    required this.onTap,
  });

  final TripSummary summary;
  final bool opening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final DateTime? updated = summary.updatedAt;
    return PressScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppColors.celadonDeep, AppColors.celadon],
          ),
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x33204F49),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: opening ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: Colors.white24,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.work_outline,
                          size: 16,
                          color: AppColors.onInk,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          '最近一次行程',
                          style: TextStyle(
                            fontSize: AppTypography.caption,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onInkMuted,
                            letterSpacing: AppTypography.labelTracking,
                          ),
                        ),
                      ),
                      if (opening)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.onInk,
                          ),
                        )
                      else
                        const Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: AppColors.onInkMuted,
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    summary.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onInk,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      _OnDarkPill(summary.corridor.isEmpty ? '河南' : summary.corridor),
                      _OnDarkPill('${summary.daysCount} 天'),
                      _OnDarkPill('人均 ${_money(summary.perPersonCost)}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '最后更新 ${_shortDate(updated)}',
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.onInkMuted,
                          ),
                        ),
                      ),
                      const Text(
                        '继续查看',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onInk,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 深色卡面上的小胶囊。
class _OnDarkPill extends StatelessWidget {
  const _OnDarkPill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: FontWeight.w600,
            color: AppColors.onInk,
          ),
        ),
      );
}

/// 首页上的两个大入口。主入口用品牌实色，次入口用白卡 + 描边。
class _HubActionCard extends StatelessWidget {
  const _HubActionCard({
    required this.primary,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool primary;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          color: primary ? AppColors.celadonDeep : AppColors.surface,
          border: primary ? null : AppColors.hairline,
          shadow: primary
              ? const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x2A1C4B46),
                    blurRadius: 16,
                    offset: Offset(0, 6),
                  ),
                ]
              : AppColors.cardShadow,
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          child: Row(
            children: <Widget>[
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: primary ? Colors.white24 : AppColors.surfaceTint,
                  borderRadius: BorderRadius.circular(13),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 21,
                  color: primary ? AppColors.onInk : AppColors.celadonDeep,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: primary ? AppColors.onInk : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: primary
                            ? AppColors.onInkMuted
                            : AppColors.crackle,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 20,
                color: primary ? AppColors.onInkMuted : AppColors.crackle,
              ),
            ],
          ),
        ),
      );
}

/// ─── 你的足迹 ─── 这一条分隔线。
class _FootprintRule extends StatelessWidget {
  const _FootprintRule();

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          const Text(
            '你的足迹',
            style: TextStyle(
              fontSize: AppTypography.secondary,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
              letterSpacing: AppTypography.labelTracking,
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(child: Divider(height: 1)),
          const SizedBox(width: 10),
          Text(
            '已保存行程聚合',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          ),
        ],
      );
}


/// 数据还没回来时的占位卡。
///
/// 高度固定，和真正的内容卡接近 —— 加载完成时页面不会跳一下。
class _HubLoadingCard extends StatelessWidget {
  const _HubLoadingCard();

  @override
  Widget build(BuildContext context) => const SurfaceCard(
        child: SizedBox(
          height: 76,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
}

/// 你的足迹：示意图 + 三个数字 + 城市清单。
///
/// 数字全部来自服务端对落库行程的聚合。**不做任何估算**：一份行程都没存过
/// 就是空状态，而不是先画一张地图再补默认值。
class _FootprintCard extends StatelessWidget {
  const _FootprintCard({
    required this.result,
    required this.loading,
    required this.onCreate,
  });

  final FootprintResult? result;
  final bool loading;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final TripFootprint data = result?.footprint ?? TripFootprint.empty;
    if (data.isEmpty) {
      final bool unavailable = result?.failure != null;
      return SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.explore_outlined,
                    size: 18, color: AppColors.celadon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    loading
                        ? '正在统计你去过的地方…'
                        : unavailable
                            ? '暂时拿不到足迹数据'
                            : '还没有留下足迹',
                    style: const TextStyle(
                      fontSize: AppTypography.body,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              unavailable
                  ? '足迹由服务端按已保存的行程统计。现在读不到，就先不显示任何数字。'
                  : '生成并保存第一份行程之后，这里会点亮你去过的城市，并累计已记录里程与旅行天数。',
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('新建一个行程'),
            ),
          ],
        ),
      );
    }

    final List<CityVisit> cities = data.cities;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HenanFootprintMap(cities: cities),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: MeasureValue(
                  value: '${cities.length}',
                  unit: '个',
                  label: '去过的城市',
                ),
              ),
              Expanded(
                child: MeasureValue(
                  value: _areaKm(data.totalKm),
                  unit: 'km',
                  label: '已记录里程',
                ),
              ),
              Expanded(
                child: MeasureValue(
                  value: '${data.totalDays}',
                  unit: '天',
                  label: '旅行天数',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final CityVisit city in cities)
                TagPill(
                  city.tripCount > 1
                      ? '${city.name} · ${city.tripCount} 次'
                      : city.name,
                  tone: TagTone.sand,
                  dense: true,
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '示意地图，非精确 GIS 底图；里程只累计路线工具返回过距离的路段，'
            '其余路段不计入，所以这里是「已记录里程」而不是总里程。',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

/// 河南足迹示意图。
///
/// 底图是 `assets/images/henan_map.jpg`：河南省轮廓和 18 个地市名都是素材自带的，
/// 所以这里**不画轮廓、不画网格、也不写地名**，只在"去过的城市"名上方点一个记号 ——
/// 底图和字是死的，状态才是活的。
///
/// 坐标是照着这张底图手工标定的**相对坐标**（左上为原点），不是投影出来的真实
/// 经纬度；换底图就要重新标定一次。界面下方因此明确写着"示意地图"。
/// 不引入地图 SDK 是刻意的：这一页离线也要能画出来。
const String _kHenanMapAsset = 'assets/images/henan_map.jpg';

/// 底图的像素比例（450 × 452）。外框跟着它走，底图既不会被裁掉也不会留白边。
const double _kHenanMapAspect = 450 / 452;

class _HenanFootprintMap extends StatefulWidget {
  const _HenanFootprintMap({required this.cities});

  final List<CityVisit> cities;

  @override
  State<_HenanFootprintMap> createState() => _HenanFootprintMapState();
}

class _HenanFootprintMapState extends State<_HenanFootprintMap>
    with SingleTickerProviderStateMixin {
  /// 一次性点亮动画。**不做循环**：首页上的地图每次呼吸一下，
  /// 在移动端只会让人以为它在加载。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Set<String> lit = <String>{
      for (final CityVisit city in widget.cities) city.name,
    };
    return Semantics(
      label: '河南足迹示意图，已点亮 ${lit.length} 个城市',
      child: AspectRatio(
        aspectRatio: _kHenanMapAspect,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 外框比例 = 底图比例，所以 fill 不会把河南拉变形。
              // 素材缺失时给一块同色底，而不是让卡片塌成一个红叉。
              Image.asset(
                _kHenanMapAsset,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
                excludeFromSemantics: true,
                errorBuilder: (BuildContext context, Object error,
                        StackTrace? stackTrace) =>
                    const ColoredBox(color: AppColors.surfaceTint),
              ),
              AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? child) => CustomPaint(
                  painter: _HenanFootprintPainter(
                    lit: lit,
                    progress: Curves.easeOutCubic.transform(_controller.value),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 在底图上点亮去过的城市。
///
/// 只画记号，不画文字：地名在底图里已经有了，再画一遍就是重影。
class _HenanFootprintPainter extends CustomPainter {
  _HenanFootprintPainter({required this.lit, required this.progress});

  final Set<String> lit;
  final double progress;

  /// 18 个地市名在这张底图上的相对位置（名字的中心，左上为原点）。
  static const Map<String, Offset> _labels = <String, Offset>{
    '安阳': Offset(0.622, 0.135),
    '濮阳': Offset(0.740, 0.150),
    '鹤壁': Offset(0.576, 0.212),
    '新乡': Offset(0.562, 0.287),
    '焦作': Offset(0.442, 0.298),
    '济源': Offset(0.352, 0.294),
    '三门峡': Offset(0.172, 0.406),
    '洛阳': Offset(0.344, 0.410),
    '郑州': Offset(0.484, 0.410),
    '开封': Offset(0.640, 0.375),
    '商丘': Offset(0.796, 0.437),
    '许昌': Offset(0.516, 0.500),
    '平顶山': Offset(0.386, 0.552),
    '漯河': Offset(0.544, 0.556),
    '周口': Offset(0.724, 0.558),
    '驻马店': Offset(0.582, 0.671),
    '南阳': Offset(0.360, 0.729),
    '信阳': Offset(0.592, 0.885),
  };

  /// 记号相对地市名的竖直偏移。负值 = 画在名字**上方**，不盖住字。
  static const double _dotLift = -0.028;

  @override
  void paint(Canvas canvas, Size size) {
    // 记号大小跟着卡片最短边缩放，平板上不会缩成一粒沙。
    final double unit = size.shortestSide;
    _labels.forEach((String name, Offset label) {
      if (!lit.contains(name)) {
        return;
      }
      final Offset center = Offset(
        label.dx * size.width,
        (label.dy + _dotLift) * size.height,
      );
      // 三层：金色光晕 → 白圈（把点从蓝色底图里托起来）→ 朱砂点。
      canvas.drawCircle(
        center,
        unit * 0.045 * progress,
        Paint()..color = AppColors.amber.withValues(alpha: 0.24 * progress),
      );
      canvas.drawCircle(
        center,
        unit * 0.020 * progress,
        Paint()..color = Colors.white.withValues(alpha: 0.95 * progress),
      );
      canvas.drawCircle(
        center,
        unit * 0.012,
        Paint()..color = AppColors.kilnRed,
      );
    });
  }

  @override
  bool shouldRepaint(_HenanFootprintPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.lit.length != lit.length ||
      !oldDelegate.lit.containsAll(lit);
}

/// 金额：三位一分组，符号跟着正负号走。
String _money(int value) {
  final String digits = value.abs().toString();
  final StringBuffer buffer = StringBuffer();
  for (int index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[index]);
  }
  return (value < 0 ? '-¥' : '¥') + buffer.toString();
}

/// 相对日期。一周以内说"几天前"，更早给月日。
String _shortDate(DateTime? time) {
  if (time == null) {
    return '时间未知';
  }
  final DateTime local = time.toLocal();
  final DateTime now = DateTime.now();
  final int days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(local.year, local.month, local.day))
      .inDays;
  if (days <= 0) {
    return '今天';
  }
  if (days == 1) {
    return '昨天';
  }
  if (days < 7) {
    return '$days 天前';
  }
  return '${local.month}月${local.day}日';
}

/// 公里数：超过 100 就不显示小数了，小数字对旅行者没有意义。
String _areaKm(double km) =>
    km >= 100 ? km.toStringAsFixed(0) : km.toStringAsFixed(1);
