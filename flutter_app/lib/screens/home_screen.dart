import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/data_status.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/data_status_badge.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/section_header.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../data/mock_catalog.dart';
import '../data/repositories/travel_repository.dart';
import '../models/account_models.dart';
import '../models/travel_models.dart';
import 'additional_screens.dart';
import 'community_screen.dart';
import 'messages_screen.dart';
import 'nearby_screen.dart';
import 'planner_screen.dart';
import 'profile_screens.dart';

/// App shell.
///
/// Four destinations: 发现 / 旅记 / 行程 / 我的.
/// 规划仍然和行程共用一个 tab，避免底部导航被拆得过碎。
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  static const int _discoverTab = 0;
  static const int _communityTab = 1;
  static const int _journeyTab = 2;
  static const int _profileTab = 3;

  static const List<NavigationDestination> _destinations =
      <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.explore_outlined),
      selectedIcon: Icon(Icons.explore),
      label: '发现',
    ),
    NavigationDestination(
      icon: Icon(Icons.auto_stories_outlined),
      selectedIcon: Icon(Icons.auto_stories),
      label: '旅记',
    ),
    NavigationDestination(
      icon: Icon(Icons.route_outlined),
      selectedIcon: Icon(Icons.route),
      label: '行程',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  /// 每次回到"发现"页就换一个 key，让首页信息流回到初始态。
  ///
  /// 用 key 而不是手动清空：Key 一变，旧 State 连同已经加载的那几页数据和
  /// 列表滚动位置一起被丢掉，不会留下"清了一半"的中间态。
  int _discoverEpoch = 0;

  /// 每次重新进入"行程"页也换一个 key，让行程页回到"我的行程"首页。
  ///
  /// 这一条是用户直接提的：以前只要生成过一次方案，之后每次切到"行程"都直接
  /// 摊开最新那份行程，行程页看起来就不像"我的行程列表"。换 key 之后，
  /// 切回来看到的是首页；从首页点"继续查看"才是那份行程。
  int _journeyEpoch = 0;

  final TextEditingController promptInput = TextEditingController();
  int tab = _discoverTab;
  late final TravelRepository repository;

  @override
  void initState() {
    super.initState();
    repository = ref.read(travelRepositoryProvider);
  }

  @override
  void dispose() {
    promptInput.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.ground,
        body: SafeArea(
          child: IndexedStack(
            index: tab,
            children: <Widget>[
              _Discover(
                key: ValueKey<int>(_discoverEpoch),
                loadPage: _loadDiscoverPage,
                repository: repository,
                controller: promptInput,
                onPlan: _startPlanning,
                onScene: _startScene,
                onOpenProfile: () => _selectTab(_profileTab),
              ),
              CommunityScreen(active: tab == _communityTab),
              JourneyScreen(
                key: ValueKey<int>(_journeyEpoch),
                repository: repository,
              ),
              const ProfileScreen(),
            ],
          ),
        ),
        bottomNavigationBar: DecoratedBox(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: AppColors.hairline, width: 1),
            ),
          ),
          child: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: _selectTab,
            destinations: _destinations,
          ),
        ),
      );

  /// Hands the typed sentence to the journey page, so the discover field is a
  /// real entrance rather than a second, disconnected input.
  void _startPlanning() {
    _handOff(promptInput.text.trim());
  }

  /// A scene chip already carries a full sentence, so it goes straight through.
  void _startScene(String prompt) {
    promptInput.text = prompt;
    _handOff(prompt);
  }

  void _handOff(String prompt) {
    ref.read(pendingPromptProvider.notifier).state = prompt;
    setState(() => tab = _journeyTab);
  }

  /// Switching back to 发现 restarts the feed from page 1.
  ///
  /// The reset happens on the way **in**, not on the way out: IndexedStack keeps
  /// every tab built, so bumping the key while the tab is hidden would fire a
  /// page-1 request nobody is looking at.
  void _selectTab(int value) {
    setState(() {
      if (value == _discoverTab && tab != _discoverTab) {
        _discoverEpoch++;
      }
      if (value == _journeyTab && tab != _journeyTab) {
        _journeyEpoch++;
      }
      tab = value;
    });
  }

  Future<DestinationPageResult> _loadDiscoverPage(int page, int size) =>
      repository.fetchDestinationPage(page: page, size: size);
}

/// 首页发现流。
///
/// 这里是 StatefulWidget 而不是 StatelessWidget：卡片是一条**分页信息流**，
/// 每滑到底部就再取一页。父层每次切回"发现"会换一个 key，于是这里重新从
/// 第一页开始 —— 用户看到的就是一个干净的初始态，而不是越滚越长的旧列表。
class _Discover extends StatefulWidget {
  const _Discover({
    super.key,
    required this.loadPage,
    required this.repository,
    required this.controller,
    required this.onPlan,
    required this.onScene,
    required this.onOpenProfile,
  });

  /// 取第 page 页、每页 size 条。走网络还是走缓存由仓库层决定，
  /// 页面不需要知道这里有没有网。
  final Future<DestinationPageResult> Function(int page, int size) loadPage;

  /// 「附近的景点」要自己发一次请求（坐标是它当场拿到的，不是首页这份分页），
  /// 所以它需要仓库本体，而不只是 loadPage 这个回调。
  final TravelRepository repository;

  final TextEditingController controller;
  final VoidCallback onPlan;
  final ValueChanged<String> onScene;

  /// 点右上角头像时切到"我的"。
  final VoidCallback onOpenProfile;

  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  /// One tap scenes. Each is a full sentence so the extraction step has real
  /// content, and so the traveller sees what a good input looks like.
  static const List<({String label, IconData icon, String prompt})> _scenes =
      <({String label, IconData icon, String prompt})>[
    (
      label: '周末短途',
      icon: Icons.weekend_outlined,
      prompt: '周末想从郑州出发找个不太累的地方，两天一夜，最好有山水和美食。',
    ),
    (
      label: '古都寻迹',
      icon: Icons.account_balance_outlined,
      prompt: '两个人在郑州，想去洛阳看历史文化，两天，节奏适中。',
    ),
    (
      label: '山水秘境',
      icon: Icons.landscape_outlined,
      prompt: '从郑州去云台山，两天行程，喜欢自然风光，能接受爬山。',
    ),
    (
      label: '河南美食',
      icon: Icons.ramen_dining_outlined,
      prompt: '在开封玩一天，主要想吃当地特色小吃，顺便看看古都景点。',
    ),
  ];

  /// 距离底部还有这么多像素时就去取下一页。
  ///
  /// 不等到 extentAfter 归零：那时手指已经贴在屏幕底部，再等一次往返很显眼。
  static const double _prefetchExtent = 480;

  final List<Destination> _items = <Destination>[];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;
  DataStatus? _status;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) {
      return;
    }
    setState(() => _loading = true);
    final DestinationPageResult result = await widget.loadPage(
      _page + 1,
      TravelRepository.destinationPageSize,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _page = result.page;
      _hasMore = result.hasMore;
      _status = result.status;
      _updatedAt = result.updatedAt;
      _failed = result.failure != null;
      // 手指每抖一下都会再触发一次预取。按 id 去重，卡片才不会凭空多一份。
      final Set<String> known =
          _items.map((Destination item) => item.id).toSet();
      _items.addAll(
        result.destinations.where((Destination item) => known.add(item.id)),
      );
    });
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _failed = false;
      _status = null;
      _updatedAt = null;
    });
    await _loadNextPage();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _prefetchExtent) {
      _loadNextPage();
    }
    return false;
  }

  void _openAll() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => _AllAttractionsScreen(loadPage: widget.loadPage),
      ),
    );
  }

  /// 打开「附近的景点」。
  ///
  /// 这里**不预先检查定位权限**：检查会带来一次多余的平台往返，而且真正的
  /// 授权时机应该是用户按下按钮之后、而不是页面替他把路堵上之前。
  /// 权限、系统开关、取坐标失败三种情况都由那一页自己兜住。
  void _openNearby() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => NearbyScreen(repository: widget.repository),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double viewport = MediaQuery.sizeOf(context).width;
    final double page = AppSpacing.pageFor(viewport);

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 12, page, 0),
            sliver: SliverToBoxAdapter(
              child: _BrandBar(onOpenProfile: widget.onOpenProfile),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 16, page, 0),
            sliver: SliverToBoxAdapter(
              child: _HeroCard(
                controller: widget.controller,
                onPlan: widget.onPlan,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 20, page, 0),
            sliver: SliverToBoxAdapter(
              child: _SceneChips(scenes: _scenes, onScene: widget.onScene),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 16, page, 0),
            sliver: SliverToBoxAdapter(
              child: _NearbyEntry(onTap: _openNearby),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 28, page, 0),
            sliver: const SliverToBoxAdapter(
              child: SectionHeader(
                title: '三条示范走廊',
                subtitle: '首版把郑州—开封、郑州—洛阳、焦作—云台山做深，而不是铺满全省。',
                icon: Icons.alt_route,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 14, page, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => Padding(
                  padding: EdgeInsets.only(
                    bottom: index == corridors.length - 1 ? 0 : 12,
                  ),
                  child: _CorridorCard(
                    corridor: corridors[index],
                    onTap: () => widget.onScene(
                      '想把${corridors[index].title}这条线走一遍，'
                      '${corridors[index].duration}，预算${corridors[index].budget}，'
                      '帮我安排行程。',
                    ),
                  ),
                ),
                childCount: corridors.length,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 28, page, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: '此刻去看看',
                subtitle: '每张卡片都给出票价、建议时长和适合人群，先判断值不值得去。',
                icon: Icons.photo_library_outlined,
                trailing: _MoreEntry(onTap: _openAll),
              ),
            ),
          ),
          if (_status != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(page, 12, page, 0),
              sliver: SliverToBoxAdapter(
                child: _CatalogProvenance(
                  status: _status!,
                  updatedAt: _updatedAt,
                  hasFailure: _failed,
                  onReload: _reload,
                ),
              ),
            ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 14, page, 0),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                mainAxisExtent: 252,
              ),
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) =>
                    _AttractionCard(destination: _items[index]),
                childCount: _items.length,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 14, page, 0),
            sliver: SliverToBoxAdapter(
              child: _FeedFooter(
                loading: _loading,
                hasMore: _hasMore,
                loaded: _items.length,
                onLoadMore: _loadNextPage,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 26, page, 32),
            sliver: const SliverToBoxAdapter(child: _DecisionStrip()),
          ),
        ],
      ),
    );
  }
}

/// 章节标题右侧的"查看更多"。
///
/// 首页只铺一屏卡片，想挨个看的人需要一个明确的去处，而不是在首页一路滑到底
/// —— 那正是这次要改掉的问题。
class _MoreEntry extends StatelessWidget {
  const _MoreEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            foregroundColor: AppColors.celadonDeep,
            backgroundColor: AppColors.surfaceTint,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('查看更多', style: TextStyle(fontSize: AppTypography.caption)),
              Icon(Icons.chevron_right, size: 16),
            ],
          ),
        ),
      );
}

/// 信息流底部的状态条。
///
/// 三种情况都要有明确说法：正在取下一页 / 还能继续看 / 已经到底。
/// 不放一个永远转动的圈 —— 那会让人以为页面一直在加载。
class _FeedFooter extends StatelessWidget {
  const _FeedFooter({
    required this.loading,
    required this.hasMore,
    required this.loaded,
    required this.onLoadMore,
  });

  final bool loading;
  final bool hasMore;
  final int loaded;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 10),
          Text(
            '正在加载更多景点…',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.crackle,
            ),
          ),
        ],
      );
    }
    if (!hasMore) {
      return Text(
        loaded == 0 ? '内容库暂时没有上架的景点。' : '已经到底了 · 共 $loaded 个景点',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: AppTypography.caption,
          color: AppColors.crackle,
        ),
      );
    }
    return Center(
      child: TextButton(
        onPressed: onLoadMore,
        child: const Text('加载更多'),
      ),
    );
  }
}

/// "查看更多"的去处。
///
/// 每页取 12 条，并且有自己独立的加载进度 —— 首页那份列表加载到哪儿，与这里
/// 无关。翻到底同样自动续取。
class _AllAttractionsScreen extends StatefulWidget {
  const _AllAttractionsScreen({required this.loadPage});

  final Future<DestinationPageResult> Function(int page, int size) loadPage;

  @override
  State<_AllAttractionsScreen> createState() => _AllAttractionsScreenState();
}

class _AllAttractionsScreenState extends State<_AllAttractionsScreen> {
  static const int _pageSize = 12;
  static const double _prefetchExtent = 600;

  final List<Destination> _items = <Destination>[];
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _failed = false;
  DataStatus? _status;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) {
      return;
    }
    setState(() => _loading = true);
    final DestinationPageResult result =
        await widget.loadPage(_page + 1, _pageSize);
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = false;
      _page = result.page;
      _hasMore = result.hasMore;
      _status = result.status;
      _updatedAt = result.updatedAt;
      _failed = result.failure != null;
      if (result.total > 0 && result.status == DataStatus.system) {
        _total = result.total;
      }
      final Set<String> known =
          _items.map((Destination item) => item.id).toSet();
      _items.addAll(
        result.destinations.where((Destination item) => known.add(item.id)),
      );
    });
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _total = 0;
      _hasMore = true;
      _failed = false;
      _status = null;
      _updatedAt = null;
    });
    await _loadNextPage();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _prefetchExtent) {
      _loadNextPage();
    }
    return false;
  }

  /// 只有总数确实来自服务端时才敢说"共 N 个"；离线降级时那个数字只是本地
  /// 切片的长度，说出来就是在编。
  String get _summary => _total > 0
      ? '内容库共 $_total 个景点，已经看了 ${_items.length} 个。'
      : '已经看了 ${_items.length} 个景点。';

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: AppColors.ground,
        foregroundColor: AppColors.ink,
        elevation: 0,
        title: const Text('河南景点'),
      ),
      body: SafeArea(
        top: false,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 2, page, 0),
                sliver: SliverToBoxAdapter(
                  // 上下排而不是左右排：_CatalogProvenance 内部用了 Flexible，
                  // 塞进 Row 的固定宽度位置会拿到无界约束，直接布局报错。
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        _summary,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.crackle,
                        ),
                      ),
                      if (_status != null) ...<Widget>[
                        const SizedBox(height: 6),
                        _CatalogProvenance(
                          status: _status!,
                          updatedAt: _updatedAt,
                          hasFailure: _failed,
                          onReload: _reload,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 14, page, 0),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    mainAxisExtent: 252,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) =>
                        _AttractionCard(destination: _items[index]),
                    childCount: _items.length,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 14, page, 28),
                sliver: SliverToBoxAdapter(
                  child: _FeedFooter(
                    loading: _loading,
                    hasMore: _hasMore,
                    loaded: _items.length,
                    onLoadMore: _loadNextPage,
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

/// Brand lockup plus the two utility entries.
///
/// 右上角这两件东西以前是"摆设"：铃铛是 `onPressed: null`（点不动，也没有红点），
/// 头像根本不存在。现在两个都是真的入口 —— 铃铛进消息中心并显示未读红点，
/// 头像进"我的"，已登录时显示用户名首字。
class _BrandBar extends ConsumerWidget {
  const _BrandBar({required this.onOpenProfile});

  final VoidCallback onOpenProfile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile? user = ref.watch(sessionProvider).valueOrNull;
    final int unread = ref.watch(unreadNoticeCountProvider);
    return Row(
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.celadonDeep,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: const Text(
            '豫',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.onInk,
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '豫见智旅',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                  letterSpacing: AppTypography.wordmarkTracking,
                ),
              ),
              SizedBox(height: 1),
              Text(
                '河南自由行的 AI 行程助手',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                ),
              ),
            ],
          ),
        ),
        _NoticeBell(
          key: const Key('home-notice-bell'),
          unread: unread,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MessagesScreen()),
          ),
        ),
        const SizedBox(width: 6),
        _HeaderAvatar(
          key: const Key('home-avatar'),
          user: user,
          onTap: onOpenProfile,
        ),
      ],
    );
  }
}

/// 首页右上角的铃铛：可点，且未读时带一个红点。
///
/// 红点只是"有未读"的补充提示，读屏与色觉障碍用户靠的是 tooltip 里的
/// 「消息通知，N 条未读」，不会因为看不见红点就漏掉这件事。
class _NoticeBell extends StatelessWidget {
  const _NoticeBell({
    super.key,
    required this.unread,
    required this.onTap,
  });

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: unread > 0 ? '消息通知，$unread 条未读' : '消息通知',
        child: InkResponse(
          onTap: onTap,
          radius: 22,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                const Icon(Icons.notifications_none,
                    size: 21, color: AppColors.ink),
                if (unread > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 15),
                      decoration: BoxDecoration(
                        color: AppColors.kilnRed,
                        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
                        border: Border.all(color: AppColors.ground, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          fontSize: 9,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: AppTypography.tabularFigures,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
}

/// 首页右上角的圆形头像。未登录是空心人像，登录后是用户名首字。
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    super.key,
    required this.user,
    required this.onTap,
  });

  final UserProfile? user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UserProfile? account = user;
    final String initial = account == null || account.username.isEmpty
        ? ''
        : account.username.substring(0, 1);
    final bool signedIn = initial.isNotEmpty;
    return Semantics(
      button: true,
      label: signedIn ? '我的，已登录 $initial' : '我的，尚未登录',
      child: PressScale(
        child: GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: signedIn ? AppColors.celadonDeep : AppColors.surface,
              border: Border.all(
                color: signedIn ? AppColors.celadonPale : AppColors.hairline,
                width: 1.5,
              ),
              boxShadow: AppColors.chipShadow,
            ),
            alignment: Alignment.center,
            child: signedIn
                ? Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onInk,
                    ),
                  )
                : const Icon(
                    Icons.person_outline,
                    size: 19,
                    color: AppColors.crackle,
                  ),
          ),
        ),
      ),
    );
  }
}

/// The first screen: one photograph, one sentence, one action.
class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.controller, required this.onPlan});

  final TextEditingController controller;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                PhotoPlate(
                  url: corridors.first.image,
                  height: 208,
                  scrim: true,
                  semanticLabel: '河南龙门石窟',
                ),
                const Positioned(
                  left: 18,
                  right: 18,
                  bottom: 18,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TagPill(
                        '河南 · 中原文化',
                        tone: TagTone.neutral,
                        dense: true,
                      ),
                      SizedBox(height: 10),
                      Text(
                        '一句话，规划你的河南之旅',
                        style: TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '从第一站到最后一程，把中原风物安排得刚刚好。',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          color: Color(0xDDEEF3F0),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  TextField(
                    controller: controller,
                    maxLines: 2,
                    minLines: 2,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '例如：两个人周末从郑州去洛阳，想看历史文化，不要太累',
                    ),
                    onSubmitted: (_) => onPlan(),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: onPlan,
                      icon: const Icon(Icons.auto_awesome_motion_outlined,
                          size: 18),
                      label: const Text('开始规划'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _SceneChips extends StatelessWidget {
  const _SceneChips({required this.scenes, required this.onScene});

  final List<({String label, IconData icon, String prompt})> scenes;
  final ValueChanged<String> onScene;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '或者，从一个场景开始',
            style: TextStyle(
              fontSize: AppTypography.secondary,
              fontWeight: FontWeight.w700,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final ({String label, IconData icon, String prompt}) scene
                  in scenes)
                PressScale(
                  child: ActionChip(
                    avatar: Icon(
                      scene.icon,
                      size: 16,
                      color: AppColors.celadonDeep,
                    ),
                    label: Text(scene.label),
                    onPressed: () => onScene(scene.prompt),
                  ),
                ),
            ],
          ),
        ],
      );
}

class _CorridorCard extends StatelessWidget {
  const _CorridorCard({required this.corridor, required this.onTap});

  final TravelCorridor corridor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              PhotoPlate(
                url: corridor.image,
                height: 168,
                scrim: true,
                fallbackLabel: corridor.title,
                semanticLabel: corridor.title,
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      corridor.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.sectionTitle,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      corridor.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: Color(0xDDEEF3F0),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        TagPill(corridor.duration, dense: true),
                        TagPill(corridor.budget, tone: TagTone.sand, dense: true),
                        for (final String tag in corridor.tags.take(2))
                          TagPill(tag, dense: true),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// Attraction card: photograph, name, one line of context, then the three facts
/// that decide whether it fits the trip.
class _AttractionCard extends StatelessWidget {
  const _AttractionCard({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          padding: const EdgeInsets.all(10),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DestinationDetail(destination: destination),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PhotoPlate(
                url: destination.image,
                height: 108,
                radius: AppSpacing.radiusSmall,
                fallbackLabel: destination.name,
                semanticLabel: destination.name,
              ),
              const SizedBox(height: 10),
              Text(
                destination.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                destination.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Expanded(
                    flex: 3,
                    child: Text(
                      '¥${destination.ticket} 起',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w700,
                        color: AppColors.amber,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      destination.duration,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: <Widget>[
                  TagPill(destination.city, dense: true),
                  const SizedBox(width: 6),
                  Flexible(
                    child: DataStatusBadge(
                      status: destination.dataStatus,
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// Where the attraction list came from, with a way out when it did not come
/// from the server.
class _CatalogProvenance extends StatelessWidget {
  const _CatalogProvenance({
    required this.status,
    required this.updatedAt,
    required this.hasFailure,
    required this.onReload,
  });

  final DataStatus status;
  final DateTime? updatedAt;
  final bool hasFailure;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Flexible(
            child: DataStatusBadge(
              status: status,
              updatedAt: updatedAt,
              dense: true,
            ),
          ),
          if (hasFailure) ...<Widget>[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onReload,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text('重新加载'),
            ),
          ],
        ],
      );
}

class _DecisionStrip extends StatelessWidget {
  const _DecisionStrip();

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(
              Icons.thermostat_outlined,
              color: AppColors.celadonDeep,
              size: 20,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '行前先看天气与开放时间',
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '方案里的天气、路线与车次会标注真实来源；取不到实时数据时会明确写成演示或降级数据，出行前请在官方渠道核验。',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.inkSoft,
                      height: 1.55,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

/// 发现页上的「在我附近」入口。
///
/// 不做成一个只有图标的按钮：它要把三件事一次说清 ——
/// 能得到什么（按距离排的附近景点）、代价是什么（一次定位授权）、
/// 以及不授权会怎样（退回按城市浏览）。
/// 最后一句尤其重要：把代价先说清楚，比事后弹一个"请开启权限"体面得多。
class _NearbyEntry extends StatelessWidget {
  const _NearbyEntry({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        onTap: onTap,
        color: AppColors.surfaceTint,
        border: AppColors.celadonPale,
        shadow: const <BoxShadow>[],
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.celadonPale,
                borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
              ),
              child: const Icon(
                Icons.near_me_outlined,
                size: 22,
                color: AppColors.celadonDeep,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '在我附近',
                    style: TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    '按直线距离看三公里内的河南景点。需要一次定位授权；不授权也能按城市浏览。',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      height: AppTypography.lineHeight,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward,
              size: 16,
              color: AppColors.celadonDeep,
            ),
          ],
        ),
      );
}
