import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/config/app_config.dart';
import '../core/data_status.dart';
import '../core/icons/app_icons.dart';
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
import '../models/planner_preset.dart';
import '../models/travel_models.dart';
import 'additional_screens.dart';
import 'community_screen.dart';
import 'culture_screen.dart';
import 'messages_screen.dart';
import 'nearby_screen.dart';
import 'planner_screen.dart';
import 'popular_screen.dart';
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
  /// 当前 Tab 由 provider 持有：文化锦囊弹窗也要能把用户送回行程页。
  int get tab => ref.watch(homeTabProvider);
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
                onScene: _startPrompt,
                onScenePreset: _startScene,
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

  /// 主题路线卡只带一句话：写进备注，直接过去。
  void _startPrompt(String prompt) {
    promptInput.text = prompt;
    _handOff(prompt);
  }

  /// 场景标签除了那句话，还把能确定的字段一起带过去 ——
  /// 表单打开就是"填好了、能直接改"的状态，而不是还要从头填一遍。
  void _startScene(PlannerPreset preset) {
    promptInput.text = preset.prompt;
    ref.read(pendingPlannerPresetProvider.notifier).state = preset;
    _handOff(preset.prompt);
  }

  void _handOff(String prompt) {
    ref.read(pendingPromptProvider.notifier).state = prompt;
    ref.read(homeTabProvider.notifier).state = _journeyTab;
  }

  /// Switching back to 发现 restarts the feed from page 1.
  ///
  /// The reset happens on the way **in**, not on the way out: IndexedStack keeps
  /// every tab built, so bumping the key while the tab is hidden would fire a
  /// page-1 request nobody is looking at.
  void _selectTab(int value) {
    // 先读旧值再改 provider：epoch 的判定要用"切换前"停在哪个 Tab。
    final int previous = ref.read(homeTabProvider);
    ref.read(homeTabProvider.notifier).state = value;
    setState(() {
      if (value == _discoverTab && previous != _discoverTab) {
        _discoverEpoch++;
      }
      if (value == _journeyTab && previous != _journeyTab) {
        _journeyEpoch++;
      }
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
    required this.onScenePreset,
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

  /// 点场景标签时，连同预填条件一起交出去。
  final ValueChanged<PlannerPreset> onScenePreset;

  /// 点右上角头像时切到"我的"。
  final VoidCallback onOpenProfile;

  @override
  State<_Discover> createState() => _DiscoverState();
}

class _DiscoverState extends State<_Discover> {
  /// 首页四个场景。
  ///
  /// 每个场景带两样东西：一句完整的自然语言需求（让后端拿到真实意图），
  /// 以及一份能确定的字段（目的地、天数、兴趣、节奏）。只带句子的话，
  /// 用户点进来还得自己把表单填一遍，这个入口就只做了一半。
  static const List<({String asset, PlannerPreset preset})> _scenes =
      <({String asset, PlannerPreset preset})>[
    (
      asset: AppIcons.sceneWeekend,
      preset: PlannerPreset(
        label: '周末短途',
        prompt: '周末想从郑州出发找个不太累的地方，两天一夜，最好有山水和美食。',
        origin: '郑州',
        destination: '开封',
        days: 2,
        adults: 2,
        interests: <String>['历史人文', '地道美食'],
        pace: '轻松',
        transport: '高铁 + 打车',
      ),
    ),
    (
      asset: AppIcons.sceneAncient,
      preset: PlannerPreset(
        label: '古都寻迹',
        prompt: '两个人在郑州，想去洛阳看历史文化，两天，节奏适中。',
        origin: '郑州',
        destination: '洛阳',
        days: 2,
        adults: 2,
        interests: <String>['历史人文'],
        pace: '适中',
        transport: '高铁 + 打车',
      ),
    ),
    (
      asset: AppIcons.sceneNature,
      preset: PlannerPreset(
        label: '山水秘境',
        prompt: '从郑州去云台山，两天行程，喜欢自然风光，能接受爬山。',
        origin: '郑州',
        destination: '焦作',
        days: 2,
        adults: 2,
        interests: <String>['自然风光'],
        pace: '适中',
        transport: '混合出行',
      ),
    ),
    (
      asset: AppIcons.sceneFood,
      preset: PlannerPreset(
        label: '河南美食',
        prompt: '在开封玩一天，主要想吃当地特色小吃，顺便看看古都景点。',
        origin: '郑州',
        destination: '开封',
        days: 1,
        adults: 2,
        interests: <String>['地道美食'],
        pace: '轻松',
        transport: '高铁 + 打车',
      ),
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

  /// 首页聚合内容（横幅、主题路线、精选景点、文化预览）。
  ///
  /// 与景点信息流分开加载：信息流是分页的、会越来越长，而这一块是固定
  /// 几个板块。失败时保持为 null，页面退回内置素材，不阻塞下面的卡片。
  HomeResult? _home;

  @override
  void initState() {
    super.initState();
    _loadNextPage();
    _loadHome();
  }

  Future<void> _loadHome() async {
    final HomeResult result = await widget.repository.fetchHome();
    if (!mounted) return;
    setState(() => _home = result);
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

  /// 打开「景区推荐」：按游客收藏数排出来的榜单。
  ///
  /// 与首页那条"精选推荐"分开：那条是运营挑的，这条是游客自己攒的，
  /// 依据不同，能讲的话也不同。
  void _openPopular() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => PopularScreen(
          repository: widget.repository,
          onBrowseAll: _openAll,
        ),
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

  /// 打开「文化锦囊」。
  ///
  /// 不做"有没有内容"的前置探测：文章为空时列表页自己给出空态与重试，
  /// 但入口本身必须是真的能点 —— 空入口比空列表更让人失望。
  void _openCulture() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CultureScreen(repository: widget.repository),
      ),
    );
  }

  void _openCultureArticle(CultureArticleSummary article) {
    // 和文化锦囊列表里的点法保持一致：底部弹窗，而不是整页跳转。
    showCultureArticleSheet(
      context,
      repository: widget.repository,
      preview: article,
    );
  }

  /// 服务端还没给出主题路线时的兜底。
  ///
  /// 把内置的三条走廊改写成同一种结构，卡片只有一套渲染逻辑；否则首页要
  /// 为"服务端路线"和"内置走廊"各写一份 UI，两边迟早长歪。
  static final List<ThemeRoute> _fallbackRoutes = <ThemeRoute>[
    for (final TravelCorridor corridor in corridors)
      ThemeRoute(
        id: 'builtin-${corridor.title}',
        title: corridor.title,
        subtitle: corridor.subtitle,
        cities: corridor.title,
        duration: corridor.duration,
        budget: corridor.budget,
        coverUrl: corridor.image,
        highlights: corridor.tags,
        planningPrompt: '',
        imageCredit: '',
        sourceUrl: '',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final double viewport = MediaQuery.sizeOf(context).width;
    final double page = AppSpacing.pageFor(viewport);
    final HomeResult? home = _home;
    final List<ThemeRoute> routes =
        home == null || home.routes.isEmpty ? _fallbackRoutes : home.routes;
    final List<Destination> featured =
        home?.featured ?? const <Destination>[];
    final List<CultureArticleSummary> culture =
        home?.culture ?? const <CultureArticleSummary>[];

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
          // 首屏横幅通栏铺满，左右不留白、不切圆角：整页只有这一处是"整幅照片"，
          // 它才立得住。下面所有区块都退回到留白与网格里。
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _HeroBanner(
                page: page,
                controller: widget.controller,
                onPlan: widget.onPlan,
                headline: home?.headline ?? TravelRepository.defaultHeadline,
                subline: home?.subline ?? TravelRepository.defaultSubline,
                imageUrl: home?.visual['HOME_HERO'] ?? '',
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 20, page, 0),
            sliver: SliverToBoxAdapter(
              child: _QuickEntries(
                onNearby: _openNearby,
                onPopular: _openPopular,
                onPlan: widget.onPlan,
                onCulture: _openCulture,
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 22, page, 0),
            sliver: SliverToBoxAdapter(
              child:
                  _SceneChips(scenes: _scenes, onScene: widget.onScenePreset),
            ),
          ),
          // 精选路线：三条走廊，横向一整张一大张地滑。
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 26, page, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: '精选路线',
                subtitle: '首版把郑州—开封、郑州—洛阳、焦作—云台山做深，而不是铺满全省。',
                  imageAsset: AppIcons.route,
                trailing: _MoreEntry(onTap: _openAll),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 196,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: EdgeInsets.fromLTRB(page - 8, 14, page - 8, 0),
                itemCount: routes.length,
                separatorBuilder: (BuildContext context, int index) =>
                    const SizedBox(width: 12),
                itemBuilder: (BuildContext context, int index) => SizedBox(
                  width: viewport * 0.82,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _RouteCard(
                      route: routes[index],
                      onTap: () => widget.onScene(routes[index].prompt),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 精选推荐：运营挑出来的那 12 个，横滑一列小卡。
          if (featured.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(page, 26, page, 0),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: '精选推荐',
                  subtitle: '运营从内容库里挑出来的河南目的地，先看值不值得去。',
                  imageAsset: AppIcons.featured,
                  trailing: _MoreEntry(onTap: _openAll),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 232,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.fromLTRB(page, 14, page, 0),
                  itemCount: featured.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(width: 12),
                  itemBuilder: (BuildContext context, int index) =>
                      _FeaturedCard(destination: featured[index]),
                ),
              ),
            ),
          ],
          if (culture.isNotEmpty) ...<Widget>[
            SliverPadding(
              padding: EdgeInsets.fromLTRB(page, 26, page, 0),
              sliver: SliverToBoxAdapter(
                child: SectionHeader(
                  title: '文化锦囊',
                  subtitle: '出发前读两分钟，路上多懂一点中原。',
                  icon: Icons.menu_book_outlined,
                  trailing: _MoreEntry(onTap: _openCulture, label: '全部文章'),
                ),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(page, 14, page, 0),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 216,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    itemCount: culture.length,
                    separatorBuilder: (BuildContext context, int index) =>
                        const SizedBox(width: 12),
                    itemBuilder: (BuildContext context, int index) =>
                        _CulturePreviewCard(
                          article: culture[index],
                          onTap: () => _openCultureArticle(culture[index]),
                        ),
                  ),
                ),
              ),
            ),
          ],
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 28, page, 0),
            sliver: SliverToBoxAdapter(
              child: SectionHeader(
                title: '更多景点',
                subtitle: '每条都给出票价、建议时长和来源状态，先判断值不值得去。',
                imageAsset: AppIcons.more,
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
          // 目录部分换成"一行一个"的列表：推荐区是挑出来的，这里是把内容库
          // 摊开给人翻，两种读法用两种版式，页面才不像同一面卡片墙重复三遍。
          SliverPadding(
            padding: EdgeInsets.fromLTRB(page, 6, page, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext context, int index) => _AttractionRow(
                  destination: _items[index],
                  showDivider: index != _items.length - 1,
                ),
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
  const _MoreEntry({required this.onTap, this.label = '查看更多'});

  final VoidCallback onTap;

  /// 按钮文案。默认"查看更多"；文化锦囊那一条说"全部文章"更准确。
  final String label;

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                label,
                style: const TextStyle(fontSize: AppTypography.caption),
              ),
              const Icon(Icons.chevron_right, size: 16),
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
                padding: EdgeInsets.fromLTRB(page, 8, page, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => _AttractionRow(
                      destination: _items[index],
                      showDivider: index != _items.length - 1,
                    ),
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
    // 自定义头像是 /media/... 相对路径，显示前要补成这台设备能访问的地址。
    final AppConfig config = ref.watch(appConfigProvider);
    return Row(
      children: <Widget>[
        // 左上角用 APK 自己的图标，而不是一个写着"豫"的色块：
        // 用户刚在桌面上点过这个图标，进来还认得它。
        const AppIcon(AppIcons.logo, size: 36),
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
          avatarUrl: config.resolveMediaUrl(user?.avatarUrl ?? ''),
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

/// 首页右上角的圆形头像。
///
/// 三种来源按优先级取：上传的照片 → 预设图案 → 用户名首字。
/// 之前这一处只画首字，所以"换了头像但首页没变"，是同一个信息在两处各算了一遍。
class _HeaderAvatar extends StatelessWidget {
  const _HeaderAvatar({
    super.key,
    required this.user,
    required this.avatarUrl,
    required this.onTap,
  });

  final UserProfile? user;

  /// 已解析为绝对地址的自定义头像；为空表示没有上传过照片。
  final String avatarUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final UserProfile? account = user;
    final String initial = account == null || account.username.isEmpty
        ? ''
        : account.username.substring(0, 1);
    final bool signedIn = initial.isNotEmpty;
    final bool hasPhoto = signedIn && avatarUrl.isNotEmpty;
    final IconData? preset = _presetIcon(account?.avatarKey);
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
            clipBehavior: Clip.antiAlias,
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
            child: !signedIn
                ? const Icon(
                    Icons.person_outline,
                    size: 19,
                    color: AppColors.crackle,
                  )
                : hasPhoto
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        width: 38,
                        height: 38,
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 160),
                        // 图片挂了就回到预设或首字，不留一个碎图图标。
                        errorWidget: (_, __, ___) => _letterOrPreset(initial, preset),
                        placeholder: (_, __) => const SizedBox.shrink(),
                      )
                    : _letterOrPreset(initial, preset),
          ),
        ),
      ),
    );
  }

  Widget _letterOrPreset(String initial, IconData? preset) {
    if (preset != null) {
      return Icon(preset, size: 19, color: AppColors.onInk);
    }
    return Text(
      initial,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.onInk,
      ),
    );
  }

  static IconData? _presetIcon(String? key) => switch (key) {
        'celadon' => Icons.landscape_outlined,
        'kiln' => Icons.account_balance_outlined,
        'amber' => Icons.wb_sunny_outlined,
        'river' => Icons.water_outlined,
        'ink' => Icons.auto_awesome_outlined,
        _ => null,
      };
}

/// 首页横幅：一张山河图承担品牌展示，搜索框压在图上。
///
/// 与旧版 _HeroCard 的区别：不再是一块"照片 + 大表单"的卡片，而是把
/// "一句话规划"收成一个浮层输入框，让第一屏先讲河南、再谈功能。
/// 图片地址来自运营台的 HOME_HERO 槽；没配时退回内置的河南照片。
class _HeroBanner extends StatelessWidget {
  const _HeroBanner({
    required this.page,
    required this.controller,
    required this.onPlan,
    required this.headline,
    required this.subline,
    required this.imageUrl,
  });

  /// 页面左右留白。横幅自己通栏，但压在上面的文字仍与整页对齐。
  final double page;

  final TextEditingController controller;
  final VoidCallback onPlan;
  final String headline;
  final String subline;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final String hero =
        imageUrl.trim().isEmpty ? corridors.first.image : imageUrl.trim();
    return Stack(
      children: <Widget>[
        PhotoPlate(
          url: hero,
          height: 300,
          scrim: true,
          fallbackLabel: '河南',
          semanticLabel: '河南山河',
        ),
        Positioned(
          left: page,
          right: page,
          top: 26,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const TagPill('河南文旅', tone: TagTone.neutral, dense: true),
              const SizedBox(height: 12),
              Text(
                headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: Color(0xDDEEF3F0),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          left: page,
          right: page,
          bottom: 16,
          child: _PromptField(controller: controller, onPlan: onPlan),
        ),
      ],
    );
  }
}

/// 压在横幅上的自然语言输入框。
///
/// 输入本身还是走原来那条规划链路（onPlan → 行程页），这里只换皮：
/// 输入框有实体白底和阴影，保证压在照片上也读得清；右侧是一个圆形发送键，
/// 拇指能够到，也不必在窄屏上再挤一行按钮。
class _PromptField extends StatelessWidget {
  const _PromptField({required this.controller, required this.onPlan});

  final TextEditingController controller;
  final VoidCallback onPlan;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl + 2),
          boxShadow: AppColors.cardShadow,
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.auto_awesome_outlined,
              size: 18,
              color: AppColors.celadonDeep,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 2,
                textInputAction: TextInputAction.done,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  color: AppColors.ink,
                ),
                decoration: const InputDecoration(
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  hintText: '两人周末从郑州去洛阳，想看历史文化，不要太累',
                ),
                onSubmitted: (_) => onPlan(),
              ),
            ),
            const SizedBox(width: 8),
            PressScale(
              child: SizedBox(
                width: 44,
                height: 44,
                child: FilledButton(
                  onPressed: onPlan,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 44),
                    padding: EdgeInsets.zero,
                    shape: const CircleBorder(),
                    backgroundColor: AppColors.celadonDeep,
                  ),
                  child: const Icon(Icons.arrow_forward, size: 18),
                ),
              ),
            ),
          ],
        ),
      );
}

/// 首页四个快捷入口。
///
/// 四件事对应四个真实去处：附近景点 / 景点推荐 / 行程规划 / 文化锦囊。
/// 没有"建设中"，也没有点了不动的入口。
class _QuickEntries extends StatelessWidget {
  const _QuickEntries({
    required this.onNearby,
    required this.onPopular,
    required this.onPlan,
    required this.onCulture,
  });

  final VoidCallback onNearby;
  final VoidCallback onPopular;
  final VoidCallback onPlan;
  final VoidCallback onCulture;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: _QuickEntry(
              asset: AppIcons.nearby,
              label: '附近景点',
              semanticLabel: '附近景点',
              onTap: onNearby,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _QuickEntry(
              asset: AppIcons.discover,
              label: '景区推荐',
              semanticLabel: '景区推荐，按游客收藏排序',
              onTap: onPopular,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _QuickEntry(
              asset: AppIcons.planning,
              label: '行程规划',
              semanticLabel: '行程规划',
              onTap: onPlan,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _QuickEntry(
              asset: AppIcons.culture,
              label: '文化锦囊',
              semanticLabel: '文化锦囊',
              onTap: onCulture,
            ),
          ),
        ],
      );
}

/// 一个快捷入口：图标 + 一行字，没有卡片、没有描边、没有底色。
///
/// 之前给图标套了一个浅色圆角块，结果是"框大图标小"，四个入口像四张缩小
/// 的卡片。这里把装饰全部去掉，只留图标本身，并在点击时给一层很轻的水波，
/// 让"可以点"由反馈说明，而不是由边框说明。
class _QuickEntry extends StatelessWidget {
  const _QuickEntry({
    required this.asset,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final String asset;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semanticLabel,
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // 图标本身就是主体：不上色、不套容器。
                  // 尺寸按"这一格有多宽"来定 —— 四个并排正好占满一行，
                  // 所以手机上看到的是四张大图标，而不是大框套小图。
                  LayoutBuilder(
                    builder:
                        (BuildContext context, BoxConstraints constraints) {
                      final double size =
                          constraints.maxWidth.clamp(48.0, 80.0);
                      return AppIcon(asset, size: size);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 一组"从一个场景开始"的入口。
///
/// 之前用的是 Material 默认的 ActionChip：灰描边、小图标，四个挤在一行或者
/// 零散折成两行，看上去像系统组件而不是这个产品的一部分。现在每一格是两列
/// 网格里的一张白色小卡：图标落在浅青圆底里，按下去有水波和轻微缩放，
/// 一行两个、四个正好两行，拇指不用瞄准。
class _SceneChips extends StatelessWidget {
  const _SceneChips({required this.scenes, required this.onScene});

  final List<({String asset, PlannerPreset preset})> scenes;
  final ValueChanged<PlannerPreset> onScene;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '从一个场景开始',
            style: TextStyle(
              fontSize: AppTypography.secondary,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 10),
          // 四个场景排成一行：图标不带边框、不带底色，一行占的高度和一次
          // 呼吸差不多，把纵向空间留给下面的路线与景点。
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const double gap = 8;
              final double cell =
                  (constraints.maxWidth - gap * (scenes.length - 1)) /
                      scenes.length;
              return Row(
                children: <Widget>[
                  for (int index = 0; index < scenes.length; index++)
                    ...<Widget>[
                      if (index > 0) const SizedBox(width: gap),
                      SizedBox(
                        width: cell,
                        child: _SceneTile(
                          asset: scenes[index].asset,
                          label: scenes[index].preset.label,
                          onTap: () => onScene(scenes[index].preset),
                        ),
                      ),
                    ],
                ],
              );
            },
          ),
        ],
      );
}

/// 一个场景格子：图标 + 场景名。
///
/// 图标用的是团队自己画的那一套，所以这里不再给它套边框、圆底或卡片 ——
/// 直接显示图形本身，按下去有水波与轻微缩放就够了。
class _SceneTile extends StatelessWidget {
  const _SceneTile({
    required this.asset,
    required this.label,
    required this.onTap,
  });

  final String asset;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label，一键填好行程条件',
        child: PressScale(
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AppIcon(asset, size: 30),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// 精选路线卡：一条走廊的照片 + 标题 + 时长/预算/主题标签。
///
/// 数据结构改用服务端的 ThemeRoute，卡片本身不再关心路线来自网络还是内置，
/// 渲染只有这一处。
class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, required this.onTap});

  final ThemeRoute route;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              PhotoPlate(
                url: route.coverUrl,
                height: 168,
                scrim: true,
                fallbackLabel: route.title,
                semanticLabel: route.title,
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 14,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      route.title,
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
                      route.subtitle,
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
                        if (route.duration.isNotEmpty)
                          TagPill(route.duration, dense: true),
                        if (route.budget.isNotEmpty)
                          TagPill(route.budget,
                              tone: TagTone.sand, dense: true),
                        for (final String tag in route.highlights.take(2))
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

/// 精选推荐卡（横向滚动）。只有运营台标记 home_featured 的景点才会进来。
///
/// 只呈现有来源的事实：城市/主题、票价、建议时长。没有评分与点评数 ——
/// 内容库里没有这两个字段，编一个出来就是假数据。
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.destination});

  final Destination destination;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 168,
        child: PressScale(
          child: SurfaceCard(
            padding: const EdgeInsets.all(8),
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
                  height: 104,
                  radius: AppSpacing.radiusSmall,
                  fallbackLabel: destination.name,
                  semanticLabel: destination.name,
                ),
                const SizedBox(height: 8),
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
                const SizedBox(height: 2),
                Text(
                  destination.theme.isEmpty
                      ? destination.city
                      : '${destination.city} · ${destination.theme}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                  ),
                ),
                const Spacer(),
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        '¥${destination.ticket} 起',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amberInk,
                          fontFeatures: AppTypography.tabularFigures,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
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
              ],
            ),
          ),
        ),
      );
}

/// 首页文化锦囊预览卡。
class _CulturePreviewCard extends StatelessWidget {
  const _CulturePreviewCard({required this.article, required this.onTap});

  final CultureArticleSummary article;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 208,
        child: PressScale(
          child: SurfaceCard(
            padding: const EdgeInsets.all(8),
            onTap: onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                PhotoPlate(
                  url: article.coverUrl,
                  height: 84,
                  radius: AppSpacing.radiusSmall,
                  fallbackLabel: article.category,
                  semanticLabel: article.title,
                ),
                const SizedBox(height: 8),
                if (article.category.isNotEmpty)
                  TagPill(article.category, dense: true),
                const SizedBox(height: 6),
                Text(
                  article.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.secondary,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    article.summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 内容库目录里的一行：缩略图 + 名称、简介、票价与时长 + 来源状态。
///
/// 这里刻意不用上面那种大图卡片：推荐区是"替你挑出来的"，用图说话；
/// 目录是"把内容库摊开让你自己翻"，用行说话。三处内容用三种版式，
/// 页面才有节奏，也不会再像同一面卡片墙重复三遍。
class _AttractionRow extends StatelessWidget {
  const _AttractionRow({required this.destination, required this.showDivider});

  final Destination destination;

  /// 最后一行不画分隔线：列表末尾留一条悬空的线很显眼。
  final bool showDivider;

  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => DestinationDetail(destination: destination),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    PhotoPlate(
                      url: destination.image,
                      height: 84,
                      width: 84,
                      radius: AppSpacing.radiusSmall,
                      fallbackLabel: destination.name,
                      semanticLabel: destination.name,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
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
                          const SizedBox(height: 8),
                          Row(
                            children: <Widget>[
                              Text(
                                '¥${destination.ticket} 起',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: AppTypography.caption,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.amberInk,
                                  fontFeatures: AppTypography.tabularFigures,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Text(
                                  destination.duration,
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
                  ],
                ),
                if (showDivider) ...<Widget>[
                  const SizedBox(height: 12),
                  const Divider(
                    height: 1,
                    thickness: 0.6,
                    color: AppColors.hairline,
                  ),
                ],
              ],
            ),
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

