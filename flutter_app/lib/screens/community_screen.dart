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
import '../core/widgets/meta_flow.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../core/widgets/user_avatar.dart';
import '../data/repositories/community_repository.dart';
import '../models/community_models.dart';
import 'account_screen.dart';
import 'community_publish_screen.dart';

/// Community feed. Public browsing does not require an account; like/report do.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key, this.active = true});

  /// The shell keeps tabs alive. Loading only after the tab is first opened
  /// avoids a background request while the user is still on 发现/行程/我的.
  final bool active;

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> {
  static const int _pageSize = 8;
  static const double _prefetchExtent = 520;
  static const List<String> _cities = <String>['全部', '郑州', '洛阳', '开封', '焦作'];
  static const List<String> _tags = <String>['全部', '历史文化', '山水', '美食', '博物馆'];

  final List<CommunityPost> _items = <CommunityPost>[];
  String _city = '全部';
  String _tag = '全部';
  int _page = 0;
  int _total = 0;
  bool _hasMore = true;
  bool _loading = false;
  bool _started = false;
  String? _failure;

  CommunityRepository get _repository => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _startIfNeeded();
  }

  @override
  void didUpdateWidget(covariant CommunityScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _startIfNeeded();
  }

  void _startIfNeeded() {
    if (_started || !widget.active) return;
    _started = true;
    _loadNextPage();
  }

  Future<void> _loadNextPage() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _failure = null;
    });
    try {
      final CommunityPage result = await _repository.fetchFeed(
        city: _city == '全部' ? null : _city,
        tag: _tag == '全部' ? null : _tag,
        page: _page + 1,
        size: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _page = result.page;
        _total = result.total;
        _hasMore = result.hasMore;
        final Set<String> known = _items.map((item) => item.id).toSet();
        _items.addAll(result.items.where((item) => known.add(item.id)));
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = failure.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failure = '旅记加载失败，请稍后重试。';
      });
    }
  }

  Future<void> _reload() async {
    setState(() {
      _items.clear();
      _page = 0;
      _total = 0;
      _hasMore = true;
      _failure = null;
    });
    await _loadNextPage();
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _prefetchExtent) {
      _loadNextPage();
    }
    return false;
  }

  void _selectCity(String city) {
    if (_city == city) return;
    setState(() => _city = city);
    _reload();
  }

  void _selectTag(String tag) {
    if (_tag == tag) return;
    setState(() => _tag = tag);
    _reload();
  }

  void _openPost(CommunityPost post) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CommunityDetailScreen(initial: post),
      ),
    );
  }

  /// 我收藏的旅记：未登录先登录，登录后直接进列表。
  Future<void> _openFavorites() async {
    if (ref.read(sessionProvider).valueOrNull == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
      );
      if (!mounted || ref.read(sessionProvider).valueOrNull == null) return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const MyCommunityFavoritesScreen(),
      ),
    );
  }

  Future<void> _openPublish() async {
    if (ref.read(sessionProvider).valueOrNull == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
      );
      if (!mounted || ref.read(sessionProvider).valueOrNull == null) return;
    }
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const CommunityPublishScreen(),
      ),
    );
    if (created == true && mounted) {
      await _reload();
    }
  }

  /// 点赞是真实操作：未登录先登录，失败如实提示，成功后只替换这一条。
  Future<void> _toggleLike(CommunityPost post) async {
    if (ref.read(sessionProvider).valueOrNull == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
      );
      if (!mounted || ref.read(sessionProvider).valueOrNull == null) return;
    }
    try {
      final CommunityPost updated = post.likedByMe
          ? await _repository.unlike(post.id)
          : await _repository.like(post.id);
      if (!mounted) return;
      setState(() {
        final int index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) {
          _items[index] = updated;
        }
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// 列表里的收藏与点赞一样是真实动作，成功后只替换这一条。
  Future<void> _toggleFavorite(CommunityPost post) async {
    if (ref.read(sessionProvider).valueOrNull == null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
      );
      if (!mounted || ref.read(sessionProvider).valueOrNull == null) return;
    }
    try {
      final CommunityPost updated = post.favoritedByMe
          ? await _repository.unfavorite(post.id)
          : await _repository.favorite(post.id);
      if (!mounted) return;
      setState(() {
        final int index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) {
          _items[index] = updated;
        }
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Material(
      color: Colors.transparent,
      child: RefreshIndicator(
        onRefresh: _reload,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: <Widget>[
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 20, page, 0),
                sliver: SliverToBoxAdapter(
                  child: _CommunityHeader(
                    total: _total,
                    onCreate: _openPublish,
                    onOpenFavorites: _openFavorites,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 18, page, 0),
                sliver: SliverToBoxAdapter(
                  child: _FilterStrip(
                    label: '城市',
                    values: _cities,
                    selected: _city,
                    onSelected: _selectCity,
                  ),
                ),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 8, page, 0),
                sliver: SliverToBoxAdapter(
                  child: _FilterStrip(
                    label: '主题',
                    values: _tags,
                    selected: _tag,
                    onSelected: _selectTag,
                  ),
                ),
              ),
              if (_failure != null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(page, 18, page, 0),
                  sliver: SliverToBoxAdapter(
                    child: _CommunityError(
                      message: _failure!,
                      onRetry: _reload,
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 18, page, 0),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) => Padding(
                      padding: EdgeInsets.only(
                        bottom: index == _items.length - 1 ? 0 : 14,
                      ),
                      child: _CommunityCard(
                        post: _items[index],
                        onTap: () => _openPost(_items[index]),
                        onToggleLike: () => _toggleLike(_items[index]),
                        onToggleFavorite: () => _toggleFavorite(_items[index]),
                      ),
                    ),
                    childCount: _items.length,
                  ),
                ),
              ),
              if (!_loading && _items.isEmpty && _failure == null)
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(page, 28, page, 0),
                  sliver: const SliverToBoxAdapter(
                    child: _CommunityEmpty(),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(page, 18, page, 36),
                sliver: SliverToBoxAdapter(
                  child: _CommunityFooter(
                    loading: _loading,
                    hasMore: _hasMore,
                    loaded: _items.length,
                    onMore: _loadNextPage,
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

class _CommunityHeader extends StatelessWidget {
  const _CommunityHeader({
    required this.total,
    required this.onCreate,
    required this.onOpenFavorites,
  });

  final int total;
  final VoidCallback onCreate;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Expanded(
                child: Text(
                  '旅记',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    height: 1.1,
                  ),
                ),
              ),
              IconButton(
                onPressed: onOpenFavorites,
                tooltip: '我收藏的旅记',
                icon: const AppIcon(
                  AppIcons.favoriteOutline,
                  size: 21,
                  color: AppColors.celadonDeep,
                ),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('写旅记'),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '把走过的河南，留给下一位旅人。',
            style: TextStyle(
              fontSize: AppTypography.lead,
              color: AppColors.inkSoft,
              height: 1.55,
            ),
          ),
          if (total > 0) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              '公开旅记 $total 篇 · 只展示已通过审核的内容',
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
              ),
            ),
          ],
        ],
      );
}

class _FilterStrip extends StatelessWidget {
  const _FilterStrip({
    required this.label,
    required this.values,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final List<String> values;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          SizedBox(
            width: 38,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final String value in values) ...<Widget>[
                    ChoiceChip(
                      label: Text(value),
                      selected: selected == value,
                      onSelected: (_) => onSelected(value),
                    ),
                    const SizedBox(width: 7),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
}

class _CommunityCard extends StatelessWidget {
  const _CommunityCard({
    required this.post,
    required this.onTap,
    required this.onToggleLike,
    required this.onToggleFavorite,
  });

  final CommunityPost post;
  final VoidCallback onTap;
  final VoidCallback onToggleLike;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final DateTime? shareDate = post.publishedAt ?? post.createdAt;
    final String authorLine = shareDate == null
        ? post.authorName
        : '${post.authorName} · ${formatChineseTimestamp(shareDate)}';
    final bool liked = post.likedByMe;
    return PressScale(
      child: SurfaceCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 作者信息栏：谁、什么时候写的，必须出现在封面之前。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: <Widget>[
                  UserAvatar(
                    name: post.authorName,
                    imageUrl: post.authorAvatarUrl,
                    avatarKey: post.authorAvatarKey,
                    size: 34,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      authorLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TagPill(post.city, dense: true),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            // 左图右文：封面与标题在同一视觉行里，读者一眼就能对上。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      PhotoPlate(
                        url: post.imageUrls.isEmpty ? '' : post.imageUrls.first,
                        width: 112,
                        height: 112,
                        radius: AppSpacing.radiusControl,
                        fallbackLabel: post.city,
                        semanticLabel: post.title,
                      ),
                      if (post.imageUrls.length > 1)
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: _PhotoCount(count: post.imageUrls.length),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          post.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.sectionTitle,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          post.content,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.inkSoft,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.hairline),
            // 互动栏：点赞、浏览量、收藏都是真的；评论还没做，如实标注。
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 9, 14, 9),
              child: Wrap(
                spacing: 16,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  _MetricItem(
                    icon: AppIcon(
                      AppIcons.like(selected: liked),
                      size: 17,
                      color: liked ? AppColors.kilnRed : AppColors.crackle,
                    ),
                    label: '${post.likeCount}',
                    tone: liked ? AppColors.kilnRed : AppColors.crackle,
                    tooltip: liked ? '取消点赞' : '点赞',
                    onTap: onToggleLike,
                  ),
                  _MetricItem(
                    icon: const Icon(
                      Icons.visibility_outlined,
                      size: 17,
                      color: AppColors.crackle,
                    ),
                    label: '${post.viewCount}',
                    tone: AppColors.crackle,
                    tooltip: '浏览 ${post.viewCount} 次',
                  ),
                  _MetricItem(
                    icon: const AppIcon(
                      AppIcons.comment,
                      size: 17,
                      color: AppColors.crackle,
                    ),
                    label: '${post.commentCount}',
                    tone: AppColors.crackle,
                    tooltip: '${post.commentCount} 条评论，点开旅记查看',
                  ),
                  _MetricItem(
                    icon: AppIcon(
                      AppIcons.favorite(selected: post.favoritedByMe),
                      size: 17,
                      color: post.favoritedByMe
                          ? AppColors.amber
                          : AppColors.crackle,
                    ),
                    label: '${post.favoriteCount}',
                    tone: post.favoritedByMe
                        ? AppColors.amber
                        : AppColors.crackle,
                    tooltip: post.favoritedByMe ? '取消收藏' : '收藏',
                    onTap: onToggleFavorite,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 多图角标：只说明"里面还有几张"，不占用标题区。
class _PhotoCount extends StatelessWidget {
  const _PhotoCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xB316211F),
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.photo_library_outlined,
                size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              '$count 图',
              style: const TextStyle(
                fontSize: 11,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      );
}

/// 互动栏里的一项。有 [onTap] 才是可点操作，否则只是如实展示的状态。
class _MetricItem extends StatelessWidget {
  const _MetricItem({
    required this.icon,
    required this.label,
    required this.tone,
    this.tooltip,
    this.onTap,
  });

  /// 已上色的图标（素材图标或 Material 图标），由调用方决定形状与颜色。
  final Widget icon;
  final String label;
  final Color tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Widget content = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        icon,
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.caption,
            color: tone,
            fontWeight: onTap == null ? FontWeight.w400 : FontWeight.w600,
            fontFeatures: AppTypography.tabularFigures,
          ),
        ),
      ],
    );
    final Widget withTooltip =
        tooltip == null ? content : Tooltip(message: tooltip!, child: content);
    if (onTap == null) {
      return withTooltip;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: withTooltip,
      ),
    );
  }
}

class CommunityDetailScreen extends ConsumerStatefulWidget {
  const CommunityDetailScreen({
    super.key,
    required this.initial,
    this.ownerMode = false,
  });

  final CommunityPost initial;
  final bool ownerMode;

  @override
  ConsumerState<CommunityDetailScreen> createState() =>
      _CommunityDetailScreenState();
}

class _CommunityDetailScreenState extends ConsumerState<CommunityDetailScreen> {
  late CommunityPost _post;
  bool _loading = false;
  bool _likeBusy = false;
  bool _favoriteBusy = false;
  bool _reportBusy = false;

  final TextEditingController _commentInput = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  List<CommunityComment> _comments = <CommunityComment>[];
  int _commentTotal = 0;
  bool _commentsLoading = true;
  bool _commentBusy = false;
  String? _commentsError;

  /// 正在回复的那条评论；为空表示输入框写的是顶层评论。
  CommunityComment? _replyTarget;

  /// 被手动展开的顶层评论 id（回复超过三条时默认收起）。
  final Set<String> _expandedThreads = <String>{};

  CommunityRepository get _repository => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _commentTotal = _post.commentCount;
    _refresh();
    _loadComments();
  }

  @override
  void dispose() {
    _commentInput.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    try {
      final CommunityPost fresh = await _repository.fetchDetail(_post.id);
      if (!mounted) return;
      setState(() {
        _post = fresh;
        _loading = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final DateTime? shareDate = _post.publishedAt ?? _post.createdAt;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('旅记'),
        actions: <Widget>[
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 6, page, 36),
        children: <Widget>[
          _PostAuthorBar(post: _post, shareDate: shareDate),
          const SizedBox(height: 16),
          Text(
            _post.title,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _post.content,
            style: const TextStyle(
              fontSize: AppTypography.body,
              color: AppColors.inkSoft,
              height: 1.8,
            ),
          ),
          if (_post.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            MetaFlow(
              spacing: 8,
              runSpacing: 8,
              children: _post.tags
                  .map((String tag) => TagPill(tag, dense: true))
                  .toList(),
            ),
          ],
          if (_post.imageUrls.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            _PostImageGrid(
              urls: _post.imageUrls,
              fallbackLabel: _post.city,
              title: _post.title,
              onOpen: _openImage,
            ),
          ],
          const SizedBox(height: 22),
          if (widget.ownerMode) ...<Widget>[
            _OwnerStatusCard(post: _post),
            const SizedBox(height: 12),
            _OwnerStatsRow(post: _post),
          ] else ...<Widget>[
            _DetailActionBar(
              post: _post,
              // 评论数以评论区那一份为准：它是唯一会在本页内变化的来源，
              // 用列表刷新时带回来的 total，而不是进页面那一刻的快照。
              commentCount: _commentTotal,
              likeBusy: _likeBusy,
              favoriteBusy: _favoriteBusy,
              onLike: _toggleLike,
              onFavorite: _toggleFavorite,
            ),
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: _reportBusy ? null : _report,
                icon: const AppIcon(
                  AppIcons.report,
                  size: 17,
                  color: AppColors.crackle,
                ),
                label: const Text('举报这篇旅记'),
              ),
            ),
          ],
          const SizedBox(height: 22),
          _CommentSection(
            total: _commentTotal,
            items: _comments,
            loading: _commentsLoading,
            error: _commentsError,
            signedIn: ref.watch(sessionProvider).valueOrNull != null,
            busy: _commentBusy,
            controller: _commentInput,
            focusNode: _commentFocus,
            onSubmit: _submitComment,
            onDelete: _deleteComment,
            onToggleLike: _toggleCommentLike,
            onReply: _startReply,
            onCancelReply: _cancelReply,
            onExpand: _toggleThread,
            replyTarget: _replyTarget,
            expandedThreads: _expandedThreads,
            onRetry: _loadComments,
            onSignIn: _openSignIn,
          ),
        ],
      ),
    );
  }

  void _openImage(int index) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: const Color(0xCC000000),
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 170),
        pageBuilder: (BuildContext context, _, __) => _ImageViewerScreen(
          urls: _post.imageUrls,
          initialIndex: index,
          title: _post.title,
          fallbackLabel: _post.city,
        ),
        transitionsBuilder:
            (BuildContext _, Animation<double> animation, __, Widget child) =>
                FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  Future<bool> _requireLogin() async {
    if (ref.read(sessionProvider).valueOrNull != null) return true;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
    );
    return ref.read(sessionProvider).valueOrNull != null;
  }

  Future<void> _toggleLike() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    setState(() => _likeBusy = true);
    try {
      final CommunityPost updated = _post.likedByMe
          ? await _repository.unlike(_post.id)
          : await _repository.like(_post.id);
      if (!mounted) return;
      setState(() {
        _post = updated;
        _likeBusy = false;
      });
      _message(updated.likedByMe ? '已点赞。' : '已取消点赞。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _likeBusy = false);
      _message(failure.message);
    }
  }

  /// 收藏（书签）与点赞是两个独立动作，各自维护自己的状态与计数。
  Future<void> _toggleFavorite() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    setState(() => _favoriteBusy = true);
    try {
      final CommunityPost updated = _post.favoritedByMe
          ? await _repository.unfavorite(_post.id)
          : await _repository.favorite(_post.id);
      if (!mounted) return;
      setState(() {
        _post = updated;
        _favoriteBusy = false;
      });
      _message(updated.favoritedByMe ? '已收藏。' : '已取消收藏。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _favoriteBusy = false);
      _message(failure.message);
    }
  }

  Future<void> _report() async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    final String? reason = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const ListTile(
              leading: AppIcon(
                AppIcons.report,
                size: 22,
                color: AppColors.inkSoft,
              ),
              title: Text('举报这份旅记'),
              subtitle: Text('选择原因后由管理员审核，举报人不会在公开页面显示。'),
            ),
            for (final String value in <String>['垃圾广告', '不实信息', '侵权或隐私', '其他'])
              ListTile(
                title: Text(value),
                onTap: () => Navigator.of(context).pop(value),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    setState(() => _reportBusy = true);
    try {
      await _repository.report(_post.id, reason);
      if (!mounted) return;
      setState(() => _reportBusy = false);
      _message('举报已提交，管理员会尽快处理。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _reportBusy = false);
      _message(failure.message);
    }
  }

  // ------------------------------------------------------------------
  // 评论
  // ------------------------------------------------------------------

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    try {
      final CommentPage page = await _repository.fetchComments(_post.id);
      if (!mounted) return;
      setState(() {
        _comments = page.items;
        _commentTotal = page.total;
        _commentsLoading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = failure.message;
      });
    }
  }

  Future<void> _submitComment() async {
    final String text = _commentInput.text.trim();
    if (text.isEmpty || _commentBusy) return;
    if (!await _requireLogin()) return;
    if (!mounted) return;
    final CommunityComment? target = _replyTarget;
    setState(() => _commentBusy = true);
    try {
      final CommunityComment created = await _repository.addComment(
        _post.id,
        text,
        // 回复"某条回复"时把顶层评论的 id 送上去：服务端也会做同样的收敛，
        // 这里先送对，拿回来的 parentId 才和界面上的位置一致。
        parentId: target == null
            ? null
            : (target.isReply ? target.parentId : target.id),
      );
      if (!mounted) return;
      setState(() {
        if (created.parentId == null) {
          // 顶层评论排在最前面，与服务端"按时间倒序"的口径保持一致。
          _comments = <CommunityComment>[created, ..._comments];
        } else {
          // 回复追加在它所属顶层评论的末尾，与服务端的正序一致。
          _comments = _comments
              .map((CommunityComment root) => root.id == created.parentId
                  ? root.copyWith(
                      replies: <CommunityComment>[...root.replies, created])
                  : root)
              .toList();
          _expandedThreads.add(created.parentId!);
        }
        _commentTotal += 1;
        _commentBusy = false;
        _commentsError = null;
        _replyTarget = null;
      });
      _commentInput.clear();
      FocusScope.of(context).unfocus();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _commentBusy = false);
      _message(failure.message);
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    final int removed = comment.isReply ? 1 : 1 + comment.replies.length;
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这条评论？'),
        content: Text(comment.isReply
            ? '删除后无法恢复。'
            : '删除后无法恢复；这条评论下的回复会一起删除。'),
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
    if (confirmed != true || !mounted) return;
    try {
      await _repository.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        // 删顶层评论时它的回复会被服务端一起删掉，计数也要一起扣。
        _comments = _comments
            .where((CommunityComment root) => root.id != comment.id)
            .map((CommunityComment root) => root.copyWith(
                  replies: root.replies
                      .where((CommunityComment reply) => reply.id != comment.id)
                      .toList(),
                ))
            .toList();
        _commentTotal = (_commentTotal - removed).clamp(0, 1 << 31);
        _expandedThreads.remove(comment.id);
      });
      _message('评论已删除。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _message(failure.message);
    }
  }

  Future<void> _openSignIn() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
    );
  }

  Future<void> _toggleCommentLike(CommunityComment comment) async {
    if (!await _requireLogin()) return;
    if (!mounted) return;
    try {
      final CommunityComment updated = comment.likedByMe
          ? await _repository.unlikeComment(comment.id)
          : await _repository.likeComment(comment.id);
      if (!mounted) return;
      setState(() => _comments = _withCommentLike(_comments, updated));
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _message(failure.message);
    }
  }

  /// 把点赞结果写回树里。
  ///
  /// 接口只回那一条评论，所以这里只替换计数与状态，不动它下面的回复 ——
  /// 用返回值整棵替换会把回复列表清空。
  List<CommunityComment> _withCommentLike(
    List<CommunityComment> roots,
    CommunityComment updated,
  ) =>
      roots.map((CommunityComment root) {
        if (root.id == updated.id) {
          return root.copyWith(
            likeCount: updated.likeCount,
            likedByMe: updated.likedByMe,
          );
        }
        return root.copyWith(
          replies: root.replies
              .map((CommunityComment reply) => reply.id == updated.id
                  ? reply.copyWith(
                      likeCount: updated.likeCount,
                      likedByMe: updated.likedByMe,
                    )
                  : reply)
              .toList(),
        );
      }).toList();

  void _startReply(CommunityComment comment) {
    setState(() => _replyTarget = comment);
    _commentFocus.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyTarget = null);
  }

  void _toggleThread(String rootId) {
    setState(() {
      if (!_expandedThreads.remove(rootId)) {
        _expandedThreads.add(rootId);
      }
    });
  }

  void _message(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }
}

class _OwnerStatusCard extends StatelessWidget {
  const _OwnerStatusCard({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    final String title = switch (post.status) {
      'PENDING' => '审核中',
      'APPROVED' => '已通过',
      'REJECTED' => '已驳回',
      'TAKEN_DOWN' => '已下架',
      _ => post.status,
    };
    final String note =
        post.moderationNote == null || post.moderationNote!.isEmpty
            ? '暂无审核说明。'
            : post.moderationNote!;
    return SurfaceCard(
      color: post.status == 'REJECTED' || post.status == 'TAKEN_DOWN'
          ? AppColors.riskSurface
          : AppColors.surfaceTint,
      shadow: const <BoxShadow>[],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '审核状态：$title',
            style: const TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            note,
            style: const TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.inkSoft,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 详情页顶部的作者信息栏：谁写的、什么时候、在哪座城。
class _PostAuthorBar extends StatelessWidget {
  const _PostAuthorBar({required this.post, required this.shareDate});

  final CommunityPost post;
  final DateTime? shareDate;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          UserAvatar(
            name: post.authorName,
            imageUrl: post.authorAvatarUrl,
            avatarKey: post.authorAvatarKey,
            size: 42,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  post.authorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  shareDate == null
                      ? '刚刚分享'
                      : formatChineseTimestamp(shareDate!),
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
          const SizedBox(width: 8),
          TagPill(post.city, dense: true),
        ],
      );
}

/// 朋友圈式图片宫格：1 张大图，2/4 张两列，其余三列。
///
/// 之前用的是横向 PageView，读者只能一张张划，看不到"这篇旅记一共几张"。
/// 宫格把内容一次交代清楚，也和社区卡片上的「N 图」角标对得上。
class _PostImageGrid extends StatelessWidget {
  const _PostImageGrid({
    required this.urls,
    required this.fallbackLabel,
    required this.title,
    required this.onOpen,
  });

  final List<String> urls;
  final String fallbackLabel;
  final String title;
  final ValueChanged<int> onOpen;

  static const double _gap = 6;

  /// 单格边长上限。一屏最多 3 格，且不会被平板的宽度拉大。
  static const double _maxTile = 96;

  /// 4 张用 2×2 更平衡；其余一律 3 列，保证"最多 3 格一行"。
  int get _columns => urls.length == 4 ? 2 : 3;

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return PressScale(
        child: GestureDetector(
          onTap: () => onOpen(0),
          child: PhotoPlate(
            url: urls.first,
            height: 232,
            radius: AppSpacing.radiusCard,
            fallbackLabel: fallbackLabel,
            semanticLabel: title,
          ),
        ),
      );
    }
    final int columns = _columns;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tile =
            (constraints.maxWidth - _gap * (columns - 1)) / columns;
        final double side = tile > _maxTile ? _maxTile : tile;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: <Widget>[
            for (int index = 0; index < urls.length; index++)
              PressScale(
                child: GestureDetector(
                  onTap: () => onOpen(index),
                  child: PhotoPlate(
                    url: urls[index],
                    width: side,
                    height: side,
                    radius: AppSpacing.radiusSmall,
                    fallbackLabel: fallbackLabel,
                    semanticLabel: '$title 图片 ${index + 1}',
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// 详情页互动栏。
///
/// 点赞是真实动作；收藏与评论还没有后端能力，因此如实标注「待开放」，
/// 既不放假数字，也不做成点不动的假按钮。
class _DetailActionBar extends StatelessWidget {
  const _DetailActionBar({
    required this.post,
    required this.commentCount,
    required this.likeBusy,
    required this.favoriteBusy,
    required this.onLike,
    required this.onFavorite,
  });

  final CommunityPost post;
  final int commentCount;
  final bool likeBusy;
  final bool favoriteBusy;
  final VoidCallback onLike;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) {
    final bool liked = post.likedByMe;
    final Color likeTone = liked ? AppColors.kilnRed : AppColors.inkSoft;
    return SurfaceCard(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _DetailAction(
              icon: AppIcon(
                AppIcons.like(selected: liked),
                size: 17,
                color: likeTone,
              ),
              label: '${post.likeCount}',
              tone: likeTone,
              tooltip: liked ? '取消点赞' : '点赞',
              onTap: likeBusy ? null : onLike,
            ),
          ),
          const _ActionDivider(),
          Expanded(
            child: _DetailAction(
              icon: AppIcon(
                AppIcons.favorite(selected: post.favoritedByMe),
                size: 17,
                color: post.favoritedByMe ? AppColors.amber : AppColors.inkSoft,
              ),
              label: '${post.favoriteCount}',
              tone: post.favoritedByMe ? AppColors.amber : AppColors.inkSoft,
              tooltip: post.favoritedByMe ? '取消收藏' : '收藏',
              onTap: favoriteBusy ? null : onFavorite,
            ),
          ),
          const _ActionDivider(),
          Expanded(
            child: _DetailAction(
              icon: const AppIcon(
                AppIcons.comment,
                size: 17,
                color: AppColors.inkSoft,
              ),
              label: '$commentCount',
              tone: AppColors.inkSoft,
              tooltip: '$commentCount 条评论',
              // 评论区就在下面一点，这里只报数，不再做第二个入口 ——
              // 一个点下去只是"滚到下面"的按钮，不如直接让下面那块自己说话。
              onTap: null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 评论区。
///
/// 发表框放在列表上方而不是页面底部：详情页是长内容，跟着键盘飘的底部输入框
/// 要额外处理内边距、遮挡与滚动三种情况；放在"读完正文就会看到"的位置，
/// 既少一层状态，也不会被键盘挡住。
class _CommentSection extends StatelessWidget {
  const _CommentSection({
    required this.total,
    required this.items,
    required this.loading,
    required this.error,
    required this.signedIn,
    required this.busy,
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
    required this.onDelete,
    required this.onToggleLike,
    required this.onReply,
    required this.onCancelReply,
    required this.onExpand,
    required this.replyTarget,
    required this.expandedThreads,
    required this.onRetry,
    required this.onSignIn,
  });

  final int total;
  final List<CommunityComment> items;
  final bool loading;
  final String? error;
  final bool signedIn;
  final bool busy;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSubmit;
  final ValueChanged<CommunityComment> onDelete;
  final ValueChanged<CommunityComment> onToggleLike;
  final ValueChanged<CommunityComment> onReply;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onExpand;

  /// 正在回复的那条评论；为空表示这条输入是顶层评论。
  final CommunityComment? replyTarget;

  /// 已经手动展开的顶层评论 id。
  final Set<String> expandedThreads;
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const AppIcon(AppIcons.comment, size: 18, color: AppColors.ink),
              const SizedBox(width: 8),
              Text(
                '评论 $total',
                style: const TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (signedIn)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (replyTarget != null) ...<Widget>[
                  _ReplyBanner(
                    target: replyTarget!,
                    onCancel: onCancelReply,
                  ),
                  const SizedBox(height: 8),
                ],
                _CommentComposer(
                  controller: controller,
                  focusNode: focusNode,
                  busy: busy,
                  onSubmit: onSubmit,
                  hintText: replyTarget == null ? '写下你的旅行建议…' : '回复这条评论…',
                ),
              ],
            )
          else
            SurfaceCard(
              color: AppColors.surfaceTint,
              shadow: const <BoxShadow>[],
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.lock_outline,
                    size: 18,
                    color: AppColors.celadonDeep,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '登录后可以发表评论。',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.inkSoft,
                        height: 1.5,
                      ),
                    ),
                  ),
                  TextButton(onPressed: onSignIn, child: const Text('去登录')),
                ],
              ),
            ),
          const SizedBox(height: 14),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (error != null)
            SurfaceCard(
              color: AppColors.riskSurface,
              shadow: const <BoxShadow>[],
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.error_outline,
                    size: 18,
                    color: AppColors.kilnRed,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(error!)),
                  TextButton(onPressed: onRetry, child: const Text('重试')),
                ],
              ),
            )
          else if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text(
                '还没有评论。说点什么，让后来的人少走一点弯路。',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.6,
                ),
              ),
            )
          else
            for (final CommunityComment comment in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CommentTile(
                  comment: comment,
                  signedIn: signedIn,
                  expanded: expandedThreads.contains(comment.id),
                  onToggleLike: onToggleLike,
                  onReply: onReply,
                  onDelete: onDelete,
                  onExpand: () => onExpand(comment.id),
                ),
              ),
        ],
      );
}

/// 发表框：一段可换行的输入 + 右侧发布。
class _CommentComposer extends StatelessWidget {
  const _CommentComposer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.onSubmit,
    required this.hintText,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final VoidCallback onSubmit;
  final String hintText;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: hintText,
                  counterText: '',
                  border: InputBorder.none,
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 40),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: Text(busy ? '发送中' : '发布'),
            ),
          ],
        ),
      );
}

/// 一条顶层评论：作者行 + 正文 + 操作条 + 折叠的回复列表。
class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.signedIn,
    required this.expanded,
    required this.onToggleLike,
    required this.onReply,
    required this.onDelete,
    required this.onExpand,
  });

  /// 折叠态先露几条回复。超过这个数量就收起来，避免一条热评把整页占满。
  static const int collapsedReplies = 3;

  final CommunityComment comment;
  final bool signedIn;
  final bool expanded;
  final ValueChanged<CommunityComment> onToggleLike;
  final ValueChanged<CommunityComment> onReply;
  final ValueChanged<CommunityComment> onDelete;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final List<CommunityComment> replies = comment.replies;
    final bool overflowing = replies.length > collapsedReplies;
    final List<CommunityComment> visible = expanded || !overflowing
        ? replies
        : replies.take(collapsedReplies).toList();
    final int hidden = replies.length - collapsedReplies;

    return SurfaceCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _CommentRow(
            comment: comment,
            signedIn: signedIn,
            onToggleLike: () => onToggleLike(comment),
            onReply: () => onReply(comment),
            onDelete: () => onDelete(comment),
          ),
          if (replies.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            // 回复整体缩进 + 左侧一条竖线：一眼能看出它们属于上面这条评论，
            // 而不是另起一条并列的评论。
            Container(
              margin: const EdgeInsets.only(left: 40),
              padding: const EdgeInsets.only(left: 12),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: AppColors.celadonPale, width: 2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final CommunityComment reply in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CommentRow(
                        comment: reply,
                        signedIn: signedIn,
                        dense: true,
                        onToggleLike: () => onToggleLike(reply),
                        onReply: () => onReply(reply),
                        onDelete: () => onDelete(reply),
                      ),
                    ),
                  if (overflowing)
                    _ReplyToggle(
                      expanded: expanded,
                      hidden: hidden,
                      onTap: onExpand,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 评论正文块。顶层评论与回复共用，只有尺寸和缩进不同。
class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.comment,
    required this.signedIn,
    required this.onToggleLike,
    required this.onReply,
    required this.onDelete,
    this.dense = false,
  });

  final CommunityComment comment;
  final bool signedIn;
  final VoidCallback onToggleLike;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final bool dense;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          UserAvatar(
            name: comment.authorName,
            imageUrl: comment.authorAvatarUrl,
            avatarKey: comment.authorAvatarKey,
            size: dense ? 26 : 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // 两侧都用 Flexible：昵称和"2025年12月31日 20:15"这种长时间戳
                // 加起来可能超过一行，让它们各自收敛比事后调字号可靠。
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        comment.authorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        formatChineseTimestamp(comment.createdAt),
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
                const SizedBox(height: 6),
                Text(
                  comment.content,
                  style: const TextStyle(
                    fontSize: AppTypography.body,
                    color: AppColors.ink,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 2),
                _CommentActions(
                  comment: comment,
                  onToggleLike: onToggleLike,
                  onReply: onReply,
                  onDelete: onDelete,
                ),
              ],
            ),
          ),
        ],
      );
}

/// 评论下面那排小动作：点赞 / 回复 / 删除自己的。
class _CommentActions extends StatelessWidget {
  const _CommentActions({
    required this.comment,
    required this.onToggleLike,
    required this.onReply,
    required this.onDelete,
  });

  final CommunityComment comment;
  final VoidCallback onToggleLike;
  final VoidCallback onReply;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final bool liked = comment.likedByMe;
    return Wrap(
      spacing: 14,
      runSpacing: 2,
      children: <Widget>[
        _CommentAction(
          icon: AppIcon(
            AppIcons.like(selected: liked),
            size: 15,
            color: liked ? AppColors.kilnRed : AppColors.crackle,
          ),
          label: comment.likeCount == 0 ? '赞' : '${comment.likeCount}',
          tone: liked ? AppColors.kilnRed : AppColors.crackle,
          tooltip: liked ? '取消点赞' : '点赞',
          onTap: onToggleLike,
        ),
        _CommentAction(
          icon: const AppIcon(
            AppIcons.comment,
            size: 15,
            color: AppColors.crackle,
          ),
          label: '回复',
          tone: AppColors.crackle,
          tooltip: '回复这条评论',
          onTap: onReply,
        ),
        if (comment.mine)
          _CommentAction(
            icon: const Icon(
              Icons.delete_outline,
              size: 15,
              color: AppColors.crackle,
            ),
            label: '删除',
            tone: AppColors.crackle,
            tooltip: '删除这条评论',
            onTap: onDelete,
          ),
      ],
    );
  }
}

class _CommentAction extends StatelessWidget {
  const _CommentAction({
    required this.icon,
    required this.label,
    required this.tone,
    required this.tooltip,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final Color tone;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                icon,
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w600,
                    color: tone,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

/// 回复折叠开关。超过三条回复时默认收起，点一下展开。
class _ReplyToggle extends StatelessWidget {
  const _ReplyToggle({
    required this.expanded,
    required this.hidden,
    required this.onTap,
  });

  final bool expanded;
  final int hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.celadonDeep,
              ),
              const SizedBox(width: 2),
              Text(
                expanded ? '收起回复' : '展开另外 $hidden 条回复',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w600,
                  color: AppColors.celadonDeep,
                ),
              ),
            ],
          ),
        ),
      );
}

/// 正在回复谁的提示带。
///
/// 做成一条能随时取消的横条，而不是把状态藏进输入框的 placeholder：
/// 用户需要一眼看清"这条发出去会挂到哪条评论下面"。
class _ReplyBanner extends StatelessWidget {
  const _ReplyBanner({required this.target, required this.onCancel});

  final CommunityComment target;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
        decoration: BoxDecoration(
          color: AppColors.surfaceTint,
          borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
        ),
        child: Row(
          children: <Widget>[
            const AppIcon(
              AppIcons.comment,
              size: 14,
              color: AppColors.celadonDeep,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '正在回复 ${target.authorName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
            InkResponse(
              onTap: onCancel,
              radius: 16,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, size: 15, color: AppColors.crackle),
              ),
            ),
          ],
        ),
      );
}

/// 作者看自己的旅记时给出只读数据，避免作者点到自己的点赞/举报。
class _OwnerStatsRow extends StatelessWidget {
  const _OwnerStatsRow({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _DetailAction(
                icon: AppIcon(
                  AppIcons.like(selected: true),
                  size: 17,
                  color: AppColors.kilnRed,
                ),
                label: '${post.likeCount} 获赞',
                tone: AppColors.kilnRed,
              ),
            ),
            const _ActionDivider(),
            Expanded(
              child: _DetailAction(
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 17,
                  color: AppColors.celadonDeep,
                ),
                label: '${post.viewCount} 浏览',
                tone: AppColors.celadonDeep,
              ),
            ),
          ],
        ),
      );
}

class _DetailAction extends StatelessWidget {
  const _DetailAction({
    required this.icon,
    required this.label,
    required this.tone,
    this.tooltip,
    this.onTap,
  });

  final Widget icon;
  final String label;
  final Color tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 单行「图标 + 文本」：比原来「图标 / 数字 / 文案」三行矮了一半，
    // 也让三个动作在同一基线上对齐。
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          icon,
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.caption,
                fontWeight: FontWeight.w600,
                color: tone,
                fontFeatures: AppTypography.tabularFigures,
              ),
            ),
          ),
        ],
      ),
    );
    final Widget withTooltip =
        tooltip == null ? content : Tooltip(message: tooltip!, child: content);
    if (onTap == null) {
      return withTooltip;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusControl),
      child: withTooltip,
    );
  }
}

class _ActionDivider extends StatelessWidget {
  const _ActionDivider();

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 34, color: AppColors.hairline);
}

/// 全屏看图：左右滑动切换、双指缩放。
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({
    required this.urls,
    required this.initialIndex,
    required this.title,
    required this.fallbackLabel,
  });

  final List<String> urls;
  final int initialIndex;
  final String title;
  final String fallbackLabel;

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    final NavigatorState navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final double boxWidth = screen.width - 32;
    final double boxHeight = screen.height * 0.62;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            // 图片之外的整片区域：点一下退出预览。
            // 放在最底层，图片本身用一层 GestureDetector 吃掉点击，
            // 只有真正点在"空白"上才会关闭。
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: const SizedBox.expand(),
              ),
            ),
            PageView.builder(
              controller: _controller,
              itemCount: widget.urls.length,
              onPageChanged: (int index) => setState(() => _index = index),
              itemBuilder: (BuildContext context, int index) => Center(
                child: GestureDetector(
                  onTap: () {},
                  child: SizedBox(
                    width: boxWidth,
                    height: boxHeight,
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: PhotoPlate(
                        url: widget.urls[index],
                        width: boxWidth,
                        height: boxHeight,
                        fit: BoxFit.contain,
                        fallbackLabel: widget.fallbackLabel,
                        semanticLabel: '${widget.title} 图片 ${index + 1}',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Row(
                children: <Widget>[
                  const AppBackButton(dark: true),
                  Expanded(
                    child: Text(
                      '${_index + 1} / ${widget.urls.length}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _close,
                    tooltip: '关闭预览',
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommunityError extends StatelessWidget {
  const _CommunityError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.riskSurface,
        shadow: const <BoxShadow>[],
        child: Row(
          children: <Widget>[
            const Icon(Icons.error_outline, color: AppColors.kilnRed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.riskText,
                  height: 1.5,
                ),
              ),
            ),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      );
}

class _CommunityEmpty extends StatelessWidget {
  const _CommunityEmpty();

  @override
  Widget build(BuildContext context) => const SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: <BoxShadow>[],
        child: Column(
          children: <Widget>[
            Icon(Icons.auto_stories_outlined,
                size: 34, color: AppColors.celadonDeep),
            SizedBox(height: 10),
            Text(
              '还没有公开旅记',
              style: TextStyle(
                fontSize: AppTypography.cardTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            SizedBox(height: 5),
            Text(
              '下一阶段会开放从行程发布旅记的入口。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
              ),
            ),
          ],
        ),
      );
}

class _CommunityFooter extends StatelessWidget {
  const _CommunityFooter({
    required this.loading,
    required this.hasMore,
    required this.loaded,
    required this.onMore,
  });

  final bool loading;
  final bool hasMore;
  final int loaded;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (!hasMore) {
      return Text(
        loaded == 0 ? '' : '已显示全部 $loaded 篇旅记',
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: AppTypography.caption,
          color: AppColors.crackle,
        ),
      );
    }
    return Center(
      child: TextButton(onPressed: onMore, child: const Text('继续看旅记')),
    );
  }
}

/// 我收藏的旅记（书签）。
///
/// 收藏跟着账号走；作者删除或下架后，服务端不再返回这篇，
/// 它也会自动从这个列表消失。
/// 我收藏的旅记列表（不含 Scaffold）。
///
/// 「我的」→「我的收藏 → 帖子」与社区页右上角入口共用这一份实现，
/// 免得两个入口各写一套加载与取消收藏逻辑。
class CommunityFavoritesList extends ConsumerStatefulWidget {
  const CommunityFavoritesList({
    super.key,
    required this.page,
    this.showIntro = true,
  });

  final double page;

  /// 独立页面显示一段说明；嵌进收藏总站时不必重复同一句话。
  final bool showIntro;

  @override
  ConsumerState<CommunityFavoritesList> createState() =>
      _CommunityFavoritesListState();
}

class _CommunityFavoritesListState
    extends ConsumerState<CommunityFavoritesList> {
  List<CommunityPost> _items = <CommunityPost>[];
  bool _loading = true;
  String? _error;

  CommunityRepository get _repository => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final CommunityPage page = await _repository.fetchFavorites();
      if (!mounted) return;
      setState(() {
        _items = page.items;
        _loading = false;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleLike(CommunityPost post) async {
    try {
      final CommunityPost updated = post.likedByMe
          ? await _repository.unlike(post.id)
          : await _repository.like(post.id);
      if (!mounted) return;
      setState(() {
        final int index = _items.indexWhere((item) => item.id == updated.id);
        if (index >= 0) _items[index] = updated;
      });
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _notify(failure.message);
    }
  }

  /// 在这个列表里取消收藏会直接把卡片移走，不需要再刷新一次。
  Future<void> _toggleFavorite(CommunityPost post) async {
    try {
      final CommunityPost updated = await _repository.unfavorite(post.id);
      if (!mounted) return;
      setState(() =>
          _items = _items.where((item) => item.id != updated.id).toList());
      _notify('已取消收藏。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      _notify(failure.message);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(widget.page, 6, widget.page, 36),
          children: <Widget>[
            if (widget.showIntro) ...<Widget>[
              const Text(
                '收藏只保存在你的账号里；作者删除或下架后，这篇会自动从这里消失。',
                style: TextStyle(
                  fontSize: AppTypography.lead,
                  color: AppColors.inkSoft,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(28),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              SurfaceCard(
                color: AppColors.riskSurface,
                shadow: const <BoxShadow>[],
                child: Row(
                  children: <Widget>[
                    const Icon(Icons.error_outline, color: AppColors.kilnRed),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_error!)),
                    TextButton(onPressed: _load, child: const Text('重试')),
                  ],
                ),
              )
            else if (_items.isEmpty)
              const SurfaceCard(
                color: AppColors.surfaceTint,
                shadow: <BoxShadow>[],
                child: Column(
                  children: <Widget>[
                    AppIcon(
                      AppIcons.favoriteOutline,
                      size: 34,
                      color: AppColors.celadonDeep,
                    ),
                    SizedBox(height: 10),
                    Text(
                      '还没有收藏的旅记',
                      style: TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '在旅记详情里点星标，就能把它留在这里。',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final CommunityPost post in _items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _CommunityCard(
                    post: post,
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CommunityDetailScreen(initial: post),
                        ),
                      );
                      if (mounted) await _load();
                    },
                    onToggleLike: () => _toggleLike(post),
                    onToggleFavorite: () => _toggleFavorite(post),
                  ),
                ),
          ],
        ),
      );
}

/// 独立的「我收藏的旅记」页面（社区页右上角入口）。
class MyCommunityFavoritesScreen extends StatelessWidget {
  const MyCommunityFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.ground,
        appBar: AppBar(
          leading: const AppBackButton(),
          title: const Text('我收藏的旅记'),
        ),
        body: CommunityFavoritesList(
          page: AppSpacing.pageFor(MediaQuery.sizeOf(context).width),
        ),
      );
}
