import 'package:flutter/material.dart';

import '../core/data_status.dart';
import '../core/icons/app_icons.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/data_status_badge.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../data/repositories/travel_repository.dart';
import '../models/travel_models.dart';
import 'additional_screens.dart';

/// 景区推荐：按游客收藏数排出来的榜单。
///
/// 为什么值得单独一页，而不是把首页再铺一遍：首页那条"精选推荐"是运营挑的，
/// 这里这条是游客自己攒的 —— 两件事的**依据**不同，讲给用户听的话也不同。
/// 收藏还很少的时候服务端会用系统推荐补位，所以这里不会是一张空榜。
///
/// 首版只读：不做"我最想去"的投票，也不做刷榜控制。
class PopularScreen extends StatefulWidget {
  const PopularScreen({
    super.key,
    required this.repository,
    this.onBrowseAll,
    this.limit = 10,
  });

  final TravelRepository repository;

  /// 去看完整目录。为空时页脚不出现这个入口 —— 空按钮比没有按钮更糟。
  final VoidCallback? onBrowseAll;

  final int limit;

  @override
  State<PopularScreen> createState() => _PopularScreenState();
}

class _PopularScreenState extends State<PopularScreen> {
  bool _loading = true;
  CatalogResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final CatalogResult result =
        await widget.repository.fetchPopularDestinations(limit: widget.limit);
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  void _open(Destination destination) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DestinationDetail(destination: destination),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final List<Destination> items =
        _result?.destinations ?? const <Destination>[];
    final ApiFailure? failure = _result?.failure;
    final DataStatus status = _result?.status ?? DataStatus.mock;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        backgroundColor: AppColors.ground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: const AppBackButton(),
        title: const Text(
          '景区推荐',
          style: TextStyle(
            fontSize: AppTypography.sectionTitle,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(page, 4, page, 40),
          children: <Widget>[
            const Text(
              '按游客收藏数排序，收藏还不多时用系统推荐补位。',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                color: AppColors.crackle,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.content),
            if (_loading && items.isEmpty)
              const _PopularLoading()
            else if (items.isEmpty)
              _PopularEmpty(failure: failure, onRetry: _load)
            else ...<Widget>[
              DataStatusBadge(status: status, updatedAt: _result?.updatedAt),
              const SizedBox(height: AppSpacing.content),
              if (failure != null) ...<Widget>[
                // 退回本机目录时不再是"收藏榜"：那一份是本机演示内容，
                // 按内容库顺序排的。不把顺序冒充成收藏数，是这个项目里
                // 和"不把演示数据说成实时"同一条规矩。
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.riskSurface,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSmall),
                  ),
                  child: Text(
                    '暂时读不到服务端的收藏数据，下面是本机演示目录，'
                    '按内容库顺序排列。原因：${failure.message}',
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.inkSoft,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.content),
              ],
              _RankTable(items: items, onTap: _open),
              if (widget.onBrowseAll != null) ...<Widget>[
                const SizedBox(height: AppSpacing.section),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: widget.onBrowseAll,
                    child: const Text('查看全部景点'),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.content),
              const Text(
                '收藏数来自本平台的游客收藏记录，不代表景区官方热度。',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 榜单正文：一张表，不是一叠卡片。
///
/// 名次本来就是有先后的一串，所以用编号是信息、不是装饰；行与行之间只留一条
/// 发丝线，读起来像榜，也顺手把"这是列表"和首页那面图墙区分开。
class _RankTable extends StatelessWidget {
  const _RankTable({required this.items, required this.onTap});

  final List<Destination> items;
  final ValueChanged<Destination> onTap;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: <Widget>[
            for (int index = 0; index < items.length; index++)
              _RankRow(
                rank: index + 1,
                destination: items[index],
                onTap: () => onTap(items[index]),
                showDivider: index != items.length - 1,
              ),
          ],
        ),
      );
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.destination,
    required this.onTap,
    required this.showDivider,
  });

  final int rank;
  final Destination destination;
  final VoidCallback onTap;
  final bool showDivider;

  /// 前三名用窑变朱，其余用雾灰：名次本身有强弱，颜色只是把它说清楚。
  Color get _rankColor => rank <= 3 ? AppColors.kilnRed : AppColors.crackle;

  @override
  Widget build(BuildContext context) {
    final String meta = destination.theme.isEmpty
        ? destination.city
        : '${destination.city} · ${destination.theme}';
    return PressScale(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 30,
                    child: Text(
                      rank.toString().padLeft(2, '0'),
                      style: TextStyle(
                        fontSize: AppTypography.secondary,
                        fontWeight: FontWeight.w700,
                        color: _rankColor,
                        fontFeatures: AppTypography.tabularFigures,
                      ),
                    ),
                  ),
                  PhotoPlate(
                    url: destination.image,
                    height: 56,
                    width: 56,
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
                        const SizedBox(height: 3),
                        Text(
                          meta,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                          ),
                        ),
                        const SizedBox(height: 5),
                        _FavoriteCount(count: destination.favoriteCount),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Text(
                        '¥${destination.ticket} 起',
                        style: const TextStyle(
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w700,
                          color: AppColors.amberInk,
                          fontFeatures: AppTypography.tabularFigures,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        destination.duration,
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
              if (showDivider) ...<Widget>[
                const SizedBox(height: 10),
                const Divider(height: 1, thickness: 0.6, color: AppColors.hairline),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 一行收藏数。0 次就说"暂无收藏"，不画一颗空星冒充有人收藏过。
class _FavoriteCount extends StatelessWidget {
  const _FavoriteCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Text(
        '暂无收藏',
        style: TextStyle(
          fontSize: AppTypography.caption,
          color: AppColors.crackle,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const AppIcon(AppIcons.favoriteFilled, size: 13),
        const SizedBox(width: 4),
        Text(
          '$count 人收藏',
          style: const TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: FontWeight.w600,
            color: AppColors.amberInk,
            fontFeatures: AppTypography.tabularFigures,
          ),
        ),
      ],
    );
  }
}

class _PopularLoading extends StatelessWidget {
  const _PopularLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.section),
        child: Column(
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.2),
            ),
            SizedBox(height: AppSpacing.content),
            Text(
              '正在读取收藏榜…',
              style: TextStyle(
                fontSize: AppTypography.secondary,
                color: AppColors.crackle,
              ),
            ),
          ],
        ),
      );
}

class _PopularEmpty extends StatelessWidget {
  const _PopularEmpty({required this.failure, required this.onRetry});

  final ApiFailure? failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        border: AppColors.celadonPale,
        shadow: const <BoxShadow>[],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '这次没读到榜单',
              style: TextStyle(
                fontSize: AppTypography.cardTitle,
                fontWeight: FontWeight.w700,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              failure?.message ?? '网络或服务端暂时不可用。',
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.inkSoft,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.content),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      );
}
