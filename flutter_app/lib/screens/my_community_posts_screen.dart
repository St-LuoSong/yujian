import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../models/community_models.dart';
import '../data/repositories/community_repository.dart';
import 'community_publish_screen.dart';
import 'community_screen.dart';

class MyCommunityPostsScreen extends ConsumerStatefulWidget {
  const MyCommunityPostsScreen({super.key});

  @override
  ConsumerState<MyCommunityPostsScreen> createState() =>
      _MyCommunityPostsScreenState();
}

class _MyCommunityPostsScreenState
    extends ConsumerState<MyCommunityPostsScreen> {
  List<CommunityPost> _posts = <CommunityPost>[];
  bool _loading = true;
  String? _error;
  String _filter = 'ALL';

  CommunityRepository get _repository =>
      ref.read(communityRepositoryProvider);

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
      final CommunityPage page = await _repository.fetchMine();
      if (!mounted) return;
      setState(() {
        _posts = page.items;
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

  List<CommunityPost> get _visible => _filter == 'ALL'
      ? _posts
      : _posts.where((post) => post.status == _filter).toList();

  int _count(String status) => _posts.where((post) => post.status == status).length;

  Future<void> _openPublish() async {
    final bool? created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const CommunityPublishScreen()),
    );
    if (created == true && mounted) await _load();
  }

  /// 作者修改自己的旅记；提交后服务端会把它打回 PENDING 重新审核。
  Future<void> _edit(CommunityPost post) async {
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CommunityPublishScreen(editing: post),
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _delete(CommunityPost post) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除这篇旅记？'),
        content: const Text('删除后无法恢复，已通过的内容也会从公开旅记中移除。'),
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
    if (confirmed != true) return;
    try {
      await _repository.deletePost(post.id);
      if (!mounted) return;
      setState(() => _posts = _posts.where((item) => item.id != post.id).toList());
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
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        leading: const AppBackButton(),
        title: const Text('我的旅记'),
        actions: <Widget>[
          IconButton(
            onPressed: _openPublish,
            tooltip: '写旅记',
            icon: const Icon(Icons.edit_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(page, 10, page, 36),
          children: <Widget>[
            const Text(
              '每一次发布都会先进入审核，审核结果会在这里保留。',
              style: TextStyle(
                fontSize: AppTypography.lead,
                color: AppColors.inkSoft,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 16),
            _StatusFilters(
              selected: _filter,
              counts: <String, int>{
                'ALL': _posts.length,
                'PENDING': _count('PENDING'),
                'APPROVED': _count('APPROVED'),
                'REJECTED': _count('REJECTED'),
              },
              onSelected: (value) => setState(() => _filter = value),
            ),
            const SizedBox(height: 16),
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
            else if (_visible.isEmpty)
              _EmptyPosts(onCreate: _openPublish)
            else
              for (final CommunityPost post in _visible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _MyPostCard(
                    post: post,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CommunityDetailScreen(
                          initial: post,
                          ownerMode: true,
                        ),
                      ),
                    ),
                    onEdit: () => _edit(post),
                    onDelete: () => _delete(post),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _StatusFilters extends StatelessWidget {
  const _StatusFilters({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    const List<(String, String)> items = <(String, String)>[
      ('ALL', '全部'),
      ('PENDING', '审核中'),
      ('APPROVED', '已通过'),
      ('REJECTED', '已驳回'),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final (String key, String label) in items) ...<Widget>[
            ChoiceChip(
              label: Text('$label ${counts[key] ?? 0}'),
              selected: selected == key,
              onSelected: (_) => onSelected(key),
            ),
            const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

class _MyPostCard extends StatelessWidget {
  const _MyPostCard({
    required this.post,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final CommunityPost post;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final (String label, String tagClass) = switch (post.status) {
      'PENDING' => ('审核中', 'tag-warn'),
      'APPROVED' => ('已通过', 'tag-ok'),
      'REJECTED' => ('已驳回', 'tag-danger'),
      'TAKEN_DOWN' => ('已下架', 'tag-danger'),
      _ => (post.status, 'tag-muted'),
    };
    return PressScale(
      child: SurfaceCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            PhotoPlate(
              url: post.imageUrls.isEmpty ? '' : post.imageUrls.first,
              width: 78,
              height: 78,
              radius: AppSpacing.radiusSmall,
              fallbackLabel: post.city,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          post.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.cardTitle,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TagPill(label, dense: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    post.content,
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
                      TagPill(post.city, dense: true),
                      const SizedBox(width: 6),
                      Text(
                        post.visibility == 'PUBLIC' ? '公开' : '仅自己',
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.crackle,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.favorite,
                          size: 15, color: AppColors.kilnRed),
                      const SizedBox(width: 3),
                      Text(
                        '${post.likeCount}',
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          color: AppColors.crackle,
                        ),
                      ),
                    ],
                  ),
                  if (post.moderationNote != null && post.moderationNote!.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 7),
                    Text(
                      post.moderationNote!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.riskText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 4),
            // 编辑与删除竖着放，宽度只占一个图标的宽度，360dp 窄屏也不会挤掉标题。
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  onPressed: onEdit,
                  tooltip: '编辑旅记',
                  icon: const Icon(Icons.edit_outlined, size: 18),
                ),
                IconButton(
                  onPressed: onDelete,
                  tooltip: '删除旅记',
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Column(
          children: <Widget>[
            const Icon(Icons.auto_stories_outlined,
                size: 36, color: AppColors.celadonDeep),
            const SizedBox(height: 10),
            const Text(
              '还没有发布过旅记',
              style: TextStyle(
                fontSize: AppTypography.cardTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              '从一份已保存的行程开始，写下你的路线和感受。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.crackle,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.edit_outlined, size: 17),
              label: const Text('写第一篇旅记'),
            ),
          ],
        ),
      );
}
