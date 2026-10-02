import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
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
  const _CommunityHeader({required this.total, required this.onCreate});

  final int total;
  final VoidCallback onCreate;

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
  const _CommunityCard({required this.post, required this.onTap});

  final CommunityPost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  PhotoPlate(
                    url: post.imageUrls.isEmpty ? '' : post.imageUrls.first,
                    height: 188,
                    scrim: true,
                    fallbackLabel: post.city,
                    semanticLabel: post.title,
                  ),
                  Positioned(
                    left: 14,
                    top: 14,
                    child: TagPill(
                      post.city,
                      tone: TagTone.neutral,
                      dense: true,
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const SizedBox(height: 7),
                    Text(
                      post.content,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        color: AppColors.inkSoft,
                        height: 1.55,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        _MiniAvatar(
                          name: post.authorName,
                          avatarKey: post.authorAvatarKey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            post.authorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: AppTypography.caption,
                              color: AppColors.crackle,
                            ),
                          ),
                        ),
                        const Icon(Icons.star, size: 16, color: AppColors.amber),
                        const SizedBox(width: 3),
                        Text(
                          '${post.likeCount}',
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                            fontFeatures: AppTypography.tabularFigures,
                          ),
                        ),
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
  bool _reportBusy = false;

  CommunityRepository get _repository => ref.read(communityRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _post = widget.initial;
    _refresh();
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
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          _PostGallery(post: _post),
          const SizedBox(height: AppSpacing.content),
          Text(
            _post.title,
            style: const TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              height: 1.28,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              _MiniAvatar(
                name: _post.authorName,
                avatarKey: _post.authorAvatarKey,
                size: 38,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _post.authorName,
                      style: const TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shareDate == null ? '刚刚分享' : _formatDate(shareDate),
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                      ),
                    ),
                  ],
                ),
              ),
              TagPill(_post.city, dense: true),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _post.content,
            style: const TextStyle(
              fontSize: AppTypography.body,
              color: AppColors.inkSoft,
              height: 1.8,
            ),
          ),
          if (_post.tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _post.tags.map((tag) => TagPill(tag, dense: true)).toList(),
            ),
          ],
          const SizedBox(height: 22),
          if (widget.ownerMode)
            _OwnerStatusCard(post: _post)
          else
            SurfaceCard(
              color: AppColors.surfaceTint,
              shadow: const <BoxShadow>[],
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _likeBusy ? null : _toggleLike,
                      icon: Icon(
                        _post.likedByMe ? Icons.star : Icons.star_border,
                        color: _post.likedByMe ? AppColors.amber : null,
                      ),
                      label: Text(_post.likedByMe ? '已收藏这份旅记' : '收藏这份旅记'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: _reportBusy ? null : _report,
                    child: const Text('举报'),
                  ),
                ],
              ),
            ),
        ],
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
      final CommunityPost updated =
          _post.likedByMe ? await _repository.unlike(_post.id) : await _repository.like(_post.id);
      if (!mounted) return;
      setState(() {
        _post = updated;
        _likeBusy = false;
      });
      _message(updated.likedByMe ? '已收藏这份旅记。' : '已取消收藏。');
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _likeBusy = false);
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
              leading: Icon(Icons.flag_outlined),
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
    final String note = post.moderationNote == null || post.moderationNote!.isEmpty
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

class _PostGallery extends StatelessWidget {
  const _PostGallery({required this.post});

  final CommunityPost post;

  @override
  Widget build(BuildContext context) {
    if (post.imageUrls.isEmpty) {
      return PhotoPlate(
        url: '',
        height: 220,
        fallbackLabel: post.city,
        semanticLabel: post.title,
      );
    }
    if (post.imageUrls.length == 1) {
      return PhotoPlate(
        url: post.imageUrls.first,
        height: 260,
        fallbackLabel: post.city,
        semanticLabel: post.title,
      );
    }
    return SizedBox(
      height: 260,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.93),
        itemCount: post.imageUrls.length,
        itemBuilder: (BuildContext context, int index) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: PhotoPlate(
            url: post.imageUrls[index],
            height: 260,
            fallbackLabel: post.city,
            semanticLabel: '${post.title} 图片 ${index + 1}',
          ),
        ),
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  const _MiniAvatar({
    required this.name,
    this.avatarKey,
    this.size = 30,
  });

  final String name;
  final String? avatarKey;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.celadonPale,
          border: Border.all(color: AppColors.surface, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Icon(
          _icon(avatarKey),
          size: size * 0.52,
          color: AppColors.celadonDeep,
        ),
      );

  IconData _icon(String? key) => switch (key) {
        'kiln' => Icons.account_balance_outlined,
        'amber' => Icons.wb_sunny_outlined,
        'river' => Icons.water_outlined,
        'ink' => Icons.auto_awesome_outlined,
        _ => Icons.landscape_outlined,
      };
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
            Icon(Icons.auto_stories_outlined, size: 34, color: AppColors.celadonDeep),
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

String _formatDate(DateTime date) {
  final DateTime local = date.toLocal();
  return '${local.year}.${local.month.toString().padLeft(2, '0')}.${local.day.toString().padLeft(2, '0')}';
}
