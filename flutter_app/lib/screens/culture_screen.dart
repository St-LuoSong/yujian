import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../data/repositories/travel_repository.dart';
import '../models/travel_models.dart';
import 'additional_screens.dart';

/// 文化锦囊：运营台发布的河南历史、非遗、风物与实用提醒。
///
/// 版式按"翻杂志"的节奏来：顶部沉浸式渐变头图、吸顶的分类胶囊、下面双列
/// 瀑布流。点开一篇文章不跳页，而是从底部升起一张 85% 高的弹窗 —— 用户还能
/// 看见身后的瀑布流，浏览的心流不会被打断。
///
/// 所有内容（分类、封面、正文、来源授权）都来自运营台；阅读时长由服务端按
/// 正文字数算出来，客户端不编。
class CultureScreen extends StatefulWidget {
  const CultureScreen({super.key, required this.repository});

  final TravelRepository repository;

  @override
  State<CultureScreen> createState() => _CultureScreenState();
}

class _CultureScreenState extends State<CultureScreen> {
  final TextEditingController _search = TextEditingController();

  bool _loading = true;
  bool _searching = false;
  CultureResult? _result;
  String _category = '';
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final CultureResult result = await widget.repository.fetchCultureArticles();
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  /// 分类来自运营台实际配置的值，不在客户端写死一份"应该有哪些分类"。
  List<String> get _categories {
    final Set<String> seen = <String>{};
    for (final CultureArticleSummary item
        in _result?.items ?? const <CultureArticleSummary>[]) {
      if (item.category.isNotEmpty) {
        seen.add(item.category);
      }
    }
    return seen.toList();
  }

  List<CultureArticleSummary> get _visible {
    final String query = _query.trim().toLowerCase();
    return (_result?.items ?? const <CultureArticleSummary>[])
        .where((CultureArticleSummary item) =>
            _category.isEmpty || item.category == _category)
        .where((CultureArticleSummary item) =>
            query.isEmpty ||
            item.title.toLowerCase().contains(query) ||
            item.summary.toLowerCase().contains(query) ||
            item.category.toLowerCase().contains(query))
        .toList();
  }

  void _open(CultureArticleSummary item) {
    showCultureArticleSheet(
      context,
      repository: widget.repository,
      preview: item,
    );
  }

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double page = AppSpacing.pageFor(width);
    final List<CultureArticleSummary> items = _visible;

    return Scaffold(
      backgroundColor: AppColors.ground,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: _CultureHero(
                page: page,
                searching: _searching,
                controller: _search,
                onBack: () => Navigator.of(context).maybePop(),
                onToggleSearch: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) {
                    _search.clear();
                    _query = '';
                  }
                }),
                onQuery: (String value) => setState(() => _query = value),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PillTabsDelegate(
                height: 56,
                page: page,
                child: _PillTabs(
                  categories: _categories,
                  selected: _category,
                  onSelect: (String value) => setState(() => _category = value),
                ),
              ),
            ),
            if (_loading && items.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (items.isEmpty)
              SliverToBoxAdapter(
                child: _EmptyState(
                  message: _result?.failure == null
                      ? '这个分类下还没有内容，换个标签看看。'
                      : '暂时连不上服务器，请检查网络后重试。',
                  onRetry: _load,
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 4, page, 96),
                sliver: SliverToBoxAdapter(
                  // 切标签不是"啪"地换一批：200ms 淡入 + 轻微上移，
                  // 让人看得出内容换了，又不会等。
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (Widget child, Animation<double> value) {
                      final bool still =
                          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                      if (still) {
                        return child;
                      }
                      return FadeTransition(
                        opacity: value,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.02),
                            end: Offset.zero,
                          ).animate(value),
                          child: child,
                        ),
                      );
                    },
                    child: _Waterfall(
                      key: ValueKey<String>('$_category|$_query'),
                      items: items,
                      onTap: _open,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 沉浸式顶部：薄荷绿到淡蓝的柔和渐变 + 返回 / 标题 / 搜索 + 一句副标题。
class _CultureHero extends StatelessWidget {
  const _CultureHero({
    required this.page,
    required this.searching,
    required this.controller,
    required this.onBack,
    required this.onToggleSearch,
    required this.onQuery,
  });

  final double page;
  final bool searching;
  final TextEditingController controller;
  final VoidCallback onBack;
  final VoidCallback onToggleSearch;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[Color(0xFFDCF2E9), Color(0xFFDCEAF7)],
          ),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(4, 6, 4, 18),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                const AppBackButton(),
                const Expanded(
                  child: Text(
                    '文化锦囊',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: AppTypography.sectionTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onToggleSearch,
                  tooltip: searching ? '收起搜索' : '搜索文化内容',
                  icon: Icon(
                    searching ? Icons.close : Icons.search,
                    size: 21,
                    color: AppColors.inkSoft,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              '读懂中原，让旅行不止于打卡',
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.inkSoft,
              ),
            ),
            if (searching) ...<Widget>[
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: page),
                child: TextField(
                  controller: controller,
                  onChanged: onQuery,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜"龙门石窟""豫剧""胡辣汤"…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.86),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}

/// 吸顶的分类胶囊：滚上去之后变成一条带磨砂的浅色条。
class _PillTabsDelegate extends SliverPersistentHeaderDelegate {
  _PillTabsDelegate({
    required this.height,
    required this.page,
    required this.child,
  });

  final double height;
  final double page;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) =>
      ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: AppColors.ground.withValues(alpha: 0.82),
            padding: EdgeInsets.fromLTRB(page, 8, page, 8),
            child: child,
          ),
        ),
      );

  @override
  bool shouldRebuild(covariant _PillTabsDelegate oldDelegate) =>
      oldDelegate.child != child ||
      oldDelegate.height != height ||
      oldDelegate.page != page;
}

class _PillTabs extends StatelessWidget {
  const _PillTabs({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<String> categories;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          _Pill(
            label: '全部',
            active: selected.isEmpty,
            onTap: () => onSelect(''),
          ),
          for (final String category in categories) ...<Widget>[
            const SizedBox(width: 8),
            _Pill(
              label: category,
              active: selected == category,
              onTap: () => onSelect(category),
            ),
          ],
        ],
      );
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              color: active ? AppColors.celadonDeep : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              border: Border.all(
                color: active ? AppColors.celadonDeep : AppColors.hairline,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.caption,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppColors.onInk : AppColors.inkSoft,
              ),
            ),
          ),
        ),
      );
}

/// 双列瀑布流：按估算高度把卡片放进当前较短的那一列。
///
/// 图片高度由 id 的稳定散列决定 —— 运营台配的封面比例各不相同，客户端拿不到
/// 尺寸，与其等图片解码完再跳一次，不如先给每张卡一个稳定、错落的高度，
/// 图片按 cover 填进去。这样滑动时不会"跳来跳去"。
class _Waterfall extends StatelessWidget {
  const _Waterfall({super.key, required this.items, required this.onTap});

  final List<CultureArticleSummary> items;
  final ValueChanged<CultureArticleSummary> onTap;

  @override
  Widget build(BuildContext context) {
    final List<CultureArticleSummary> left = <CultureArticleSummary>[];
    final List<CultureArticleSummary> right = <CultureArticleSummary>[];
    double leftHeight = 0;
    double rightHeight = 0;
    for (final CultureArticleSummary item in items) {
      final double height = _estimatedHeight(item);
      if (leftHeight <= rightHeight) {
        left.add(item);
        leftHeight += height;
      } else {
        right.add(item);
        rightHeight += height;
      }
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: _column(left)),
        const SizedBox(width: 14),
        Expanded(child: _column(right)),
      ],
    );
  }

  Widget _column(List<CultureArticleSummary> column) => Column(
        children: <Widget>[
          for (final CultureArticleSummary item in column)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _CultureCard(
                item: item,
                coverHeight: _coverHeight(item),
                onTap: () => onTap(item),
              ),
            ),
        ],
      );
}

class _CultureCard extends StatelessWidget {
  const _CultureCard({
    required this.item,
    required this.coverHeight,
    required this.onTap,
  });

  final CultureArticleSummary item;
  final double coverHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ({Color ink, Color surface}) tone = _categoryTone(item.category);
    return PressScale(
      scale: 0.97,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard + 4),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppSpacing.radiusCard + 4),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: Color(0x0A000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppSpacing.radiusCard + 4),
                ),
                child: PhotoPlate(
                  url: item.coverUrl,
                  height: coverHeight,
                  fallbackLabel: item.category,
                  semanticLabel: item.title,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    if (item.category.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: tone.surface,
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusPill),
                        ),
                        child: Text(
                          '#${item.category}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: tone.ink,
                          ),
                        ),
                      ),
                    const SizedBox(height: 7),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.secondary,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.likeCount > 0
                          ? '阅读 ${item.readingMinutes} 分钟 · ♥ ${item.likeCount}'
                          : '阅读 ${item.readingMinutes} 分钟',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.crackle,
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

/// 分类色：低饱和，只落在标签文字和极浅的底色上。
/// 详情页那行元信息：作者 · 阅读 N 分钟 · ♥ N。没填的项就不显示，
/// 不用占位符假装有内容。
String _metaLine(CultureArticleSummary preview, CultureArticle? article) {
  final String author =
      (article?.author.isNotEmpty ?? false) ? article!.author : preview.author;
  final int likes =
      (article?.likeCount ?? 0) > 0 ? article!.likeCount : preview.likeCount;
  return <String>[
    if (author.isNotEmpty) author,
    '阅读 ${preview.readingMinutes} 分钟',
    if (likes > 0) '♥ $likes',
  ].join(' · ');
}

({Color ink, Color surface}) _categoryTone(String category) =>
    switch (category) {
      '历史遗迹' => (
          ink: const Color(0xFF8A5A22),
          surface: const Color(0xFFF6EEDF),
        ),
      '非遗体验' => (
          ink: const Color(0xFFA4525F),
          surface: const Color(0xFFF8E9EC),
        ),
      '地道风物' => (
          ink: const Color(0xFF3F7157),
          surface: const Color(0xFFE7F2EA),
        ),
      '避坑指南' => (
          ink: const Color(0xFF4A6478),
          surface: const Color(0xFFE9EFF4),
        ),
      _ => (
          ink: AppColors.celadonDeep,
          surface: AppColors.celadonPale,
        ),
    };

/// 稳定的散列：同一条内容每次进来高度一致，瀑布流不会自己重排。
int _stableHash(String value) {
  int hash = 7;
  for (final int unit in value.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  return hash;
}

double _coverHeight(CultureArticleSummary item) =>
    138 + (_stableHash(item.id) % 3) * 26;

double _estimatedHeight(CultureArticleSummary item) =>
    _coverHeight(item) + (item.title.length > 14 ? 96 : 78);

/// 打开文章弹窗。
///
/// 用底部弹窗而不是整页跳转：用户是从瀑布流里点进来的，关掉之后应该还停在
/// 刚才那一屏，而不是被丢回列表顶部。
Future<void> showCultureArticleSheet(
  BuildContext context, {
  required TravelRepository repository,
  required CultureArticleSummary preview,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (BuildContext sheetContext) => Consumer(
        builder: (BuildContext context, WidgetRef ref, Widget? child) =>
            FractionallySizedBox(
          heightFactor: ref.watch(cultureSheetExpandedProvider) ? 1 : 0.88,
          alignment: Alignment.bottomCenter,
          child: _CultureArticleSheet(
            repository: repository,
            preview: preview,
          ),
        ),
      ),
    );

/// 文章详情（弹窗内容）。先把列表里已有的字段显示出来，正文到了再补 ——
/// 点开不会先看到一屏空白。
class _CultureArticleSheet extends ConsumerStatefulWidget {
  const _CultureArticleSheet({required this.repository, required this.preview});

  final TravelRepository repository;
  final CultureArticleSummary preview;

  @override
  ConsumerState<_CultureArticleSheet> createState() =>
      _CultureArticleSheetState();
}

class _CultureArticleSheetState extends ConsumerState<_CultureArticleSheet> {
  bool _loading = true;
  CultureArticle? _article;

  /// 正文里提到的景点。只有景点名真的出现在文章里才算，不做"猜一个相关"。
  List<Destination> _related = const <Destination>[];

  @override
  void initState() {
    super.initState();
    // 每次打开都从 88% 开始：上一次展开过，不该影响这一次。
    ref.read(cultureSheetExpandedProvider.notifier).state = false;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final CultureArticleResult result =
        await widget.repository.fetchCultureArticle(widget.preview.id);
    final CatalogResult catalog = await widget.repository.fetchDestinations();
    if (!mounted) return;
    final CultureArticle? article = result.article;
    setState(() {
      _article = article;
      _related = article == null
          ? const <Destination>[]
          : _relatedPois(article, catalog.destinations);
      _loading = false;
    });
  }

  static List<Destination> _relatedPois(
    CultureArticle article,
    List<Destination> pool,
  ) {
    final String text =
        '${article.title}${article.summary}${article.content}';
    return pool
        .where((Destination poi) =>
            poi.name.length >= 2 && text.contains(poi.name))
        .take(3)
        .toList();
  }

  /// 用这篇文章做一次行程规划：把需求交给行程页，并切回主导航的行程 Tab。
  void _planFrom(String title, String summary) {
    final String prompt = summary.isEmpty
        ? '想围绕「$title」安排一次河南行程。'
        : '$summary（想围绕「$title」安排行程。）';
    ref.read(pendingPromptProvider.notifier).state = prompt;
    // 2 = 行程 Tab，HomeScreen 读的是同一个 provider。
    ref.read(homeTabProvider.notifier).state = 2;
    Navigator.of(context).pop();
    Navigator.of(context).popUntil((Route<dynamic> route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final CultureArticleSummary preview = widget.preview;
    final CultureArticle? article = _article;
    final String title = article?.title ?? preview.title;
    final String category = article?.category ?? preview.category;
    final String cover = article?.coverUrl ?? preview.coverUrl;
    final String credit = article?.imageCredit ?? preview.imageCredit;
    final String sourceUrl = article?.sourceUrl ?? preview.sourceUrl;
    final ({Color ink, Color surface}) tone = _categoryTone(category);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.ground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          // 抓手 + 关闭：告诉用户"往下拖就关掉"。
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.hairline,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => ref
                      .read(cultureSheetExpandedProvider.notifier)
                      .state = !ref.read(cultureSheetExpandedProvider),
                  tooltip: ref.watch(cultureSheetExpandedProvider)
                      ? '收起'
                      : '展开全屏',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    ref.watch(cultureSheetExpandedProvider)
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    size: 20,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(page, 4, page, 32),
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
                  child: PhotoPlate(
                    url: cover,
                    height: 210,
                    fallbackLabel: category,
                    semanticLabel: title,
                  ),
                ),
                const SizedBox(height: AppSpacing.content),
                if (category.isNotEmpty) ...<Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tone.surface,
                      borderRadius: BorderRadius.circular(
                        AppSpacing.radiusPill,
                      ),
                    ),
                    child: Text(
                      '#$category',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tone.ink,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _metaLine(preview, article),
                  style: const TextStyle(
                    fontSize: AppTypography.caption,
                    color: AppColors.crackle,
                  ),
                ),
                const SizedBox(height: AppSpacing.content),
                if (_loading && article == null)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (article == null)
                  _EmptyState(
                    message: '正文没读到，可能是网络断了。',
                    onRetry: _load,
                  )
                else
                  for (final String paragraph in _paragraphs(article.content))
                    Padding(
                      // 行高 1.8、段间距 16、不缩进：中文长文靠段距分节，
                      // 首行缩进在这里只会显得像 Word 文档。
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        paragraph,
                        style: const TextStyle(
                          fontSize: AppTypography.body,
                          color: AppColors.inkSoft,
                          height: 1.8,
                        ),
                      ),
                    ),
                if (credit.isNotEmpty || sourceUrl.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.content),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceTint,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    child: Text(
                      <String>[
                        if (credit.isNotEmpty) '图片：$credit',
                        if (sourceUrl.isNotEmpty) '来源：$sourceUrl',
                      ].join('\n'),
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.crackle,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
                if (_related.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpacing.section),
                  const Text(
                    '文中提到的景点',
                    style: TextStyle(
                      fontSize: AppTypography.secondary,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final Destination poi in _related)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: PressScale(
                        child: InkWell(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  DestinationDetail(destination: poi),
                            ),
                          ),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radiusSmall),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius:
                                  BorderRadius.circular(AppSpacing.radiusSmall),
                              border: Border.all(color: AppColors.hairline),
                            ),
                            child: Row(
                              children: <Widget>[
                                PhotoPlate(
                                  url: poi.image,
                                  height: 48,
                                  width: 48,
                                  radius: AppSpacing.radiusSmall,
                                  fallbackLabel: poi.name,
                                  semanticLabel: poi.name,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(
                                        poi.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppTypography.secondary,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '¥${poi.ticket} 起 · ${poi.duration}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: AppTypography.caption,
                                          color: AppColors.crackle,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                  color: AppColors.crackle,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: AppSpacing.section),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => _planFrom(
                      title,
                      article?.summary ?? preview.summary,
                    ),
                    icon: const Icon(
                      Icons.auto_awesome_motion_outlined,
                      size: 18,
                    ),
                    label: const Text('用这个主题做一份行程'),
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

/// 正文按空行切段。运营台写的时候用换行分段，客户端不替它猜小标题。
List<String> _paragraphs(String content) => content
    .split(RegExp(r'\n\s*\n|\r\n\s*\r\n'))
    .map((String part) => part.trim())
    .where((String part) => part.isNotEmpty)
    .toList();

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTypography.secondary,
                color: AppColors.crackle,
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      );
}
