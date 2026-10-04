import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/config/app_config.dart';
import '../core/icons/app_icons.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/app_back_button.dart';
import '../core/widgets/photo_plate.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../data/repositories/travel_repository.dart';
import '../models/account_models.dart';
import '../models/community_models.dart';
import '../models/travel_models.dart';
import '../models/trip_models.dart';
import 'account_screen.dart';
import 'account_security_screens.dart';
import 'additional_screens.dart';
import 'check_update_screen.dart';
import 'community_screen.dart';
import 'messages_screen.dart';
import 'my_community_posts_screen.dart';
import 'trip_screen.dart';

/// 退出登录：一次确认，然后清掉本地会话。
///
/// 抽成顶层函数是因为"我的"页和"设置 - 账号与安全"都要用它。
/// 两处各写一份确认弹层的代价是：总有一天两边的文案不一致。
Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text('退出登录？'),
      content: const Text('退出后不会删除你的行程与收藏，重新登录即可继续查看。'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) {
    return;
  }
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  await ref.read(sessionProvider.notifier).signOut();
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(content: Text('已退出登录。')));
}

/// Account tab.
///
/// 这一页只做两件事：告诉用户"我现在是谁"，以及把账号相关的入口收在一处。
/// 收藏、行程、消息这些内容各自有独立页面 —— 把列表直接摊在这一页上，
/// 账号页会长成第二个首页。
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final AsyncValue<UserProfile?> session = ref.watch(sessionProvider);
    final int unread = ref.watch(unreadNoticeCountProvider);

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          session.when(
            loading: () => const _ProfileHeroSkeleton(),
            error: (Object error, StackTrace _) => _ProfileErrorView(
              message: error is ApiFailure ? error.message : '账号状态读取失败，请稍后重试。',
              onRetry: () => ref.invalidate(sessionProvider),
            ),
            data: (UserProfile? user) => _ProfileHero(user: user),
          ),
          const SizedBox(height: AppSpacing.section),
          _ImpactCard(),
          const SizedBox(height: AppSpacing.section),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                _MenuRow(
                  iconAsset: AppIcons.favoriteOutline,
                  title: '我的收藏',
                  detail: '景区、旅记与行程',
                  onTap: () => _push(context, const FavoritesScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.route_outlined,
                  title: '我的行程',
                  detail: '查看、重命名或删除已保存的行程',
                  onTap: () => _push(context, const TripHomeScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.auto_stories_outlined,
                  title: '我的旅记',
                  detail: '查看审核中、已通过和已驳回的旅记',
                  onTap: () => _push(context, const MyCommunityPostsScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.notifications_none,
                  title: '消息通知',
                  detail: '产品与数据说明',
                  badge: unread,
                  onTap: () => _push(context, const MessagesScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.settings_outlined,
                  title: '设置',
                  detail: '账号与安全、个人信息、软件设置',
                  onTap: () => _push(context, const SettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.content),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                _MenuRow(
                  icon: Icons.shield_outlined,
                  title: '隐私与数据',
                  detail: '我们存什么、不存什么',
                  onTap: () => _push(context, const PrivacyScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.storage_outlined,
                  title: '第三方数据来源',
                  detail: '地图 / 天气 / 车次 / 模型',
                  onTap: () => _push(context, const DataSourcesScreen()),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.info_outline,
                  title: '关于豫见智旅',
                  trailingText: 'v0.3',
                  onTap: () => _push(context, const AboutScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开子页面，并挡住"同一层压两次"。
  ///
  /// 这一页的行是整块可点的：快速点两下会 push 两条一模一样的路由，
  /// 用户按一次返回还停在同一个页面，看起来就像返回按钮失灵、出不去了。
  /// 用当前路由做一次引用比较，栈顶确实换过了才允许再 push。
  static void _push(BuildContext context, Widget page) {
    if (identical(ModalRoute.of(context), _lastPushed)) {
      return;
    }
    final Route<void> route =
        MaterialPageRoute<void>(builder: (BuildContext context) => page);
    _lastPushed = route;
    Navigator.of(context).push(route);
  }

  /// 上一次由这一页 push 出去的路由，只用于挡住连点，不参与任何业务判断。
  static Route<dynamic>? _lastPushed;
}

/// 「我获得的互动」。
///
/// 四个数字都只统计**别人对我**的动作：自己给自己的旅记点赞、给自己的评论点赞
/// 都不计入。否则这块数据会退化成"我点过多少下"，而不是"我发的东西被看见了多少"。
class _ImpactCard extends ConsumerWidget {
  const _ImpactCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<CommunityStats?> stats = ref.watch(_communityStatsProvider);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radiusCard),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[AppColors.celadonDeep, AppColors.celadon],
        ),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33204F49),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.auto_awesome_outlined,
                size: 17,
                color: AppColors.onInkMuted,
              ),
              const SizedBox(width: 8),
              const Text(
                '我获得的互动',
                style: TextStyle(
                  fontSize: AppTypography.cardTitle,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onInk,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '别人对你旅记与评论的真实回应',
            style: TextStyle(
              fontSize: AppTypography.caption,
              color: AppColors.onInkMuted,
            ),
          ),
          const SizedBox(height: 16),
          stats.when(
            loading: () => const SizedBox(
              height: 52,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.onInk,
                  ),
                ),
              ),
            ),
            error: (Object error, StackTrace _) => Text(
              error is ApiFailure ? error.message : '互动数据读取失败。',
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.onInkMuted,
                height: 1.5,
              ),
            ),
            data: (CommunityStats? value) => value == null
                ? const Text(
                    '登录后查看你获得的点赞、收藏与评论。',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.onInkMuted,
                      height: 1.5,
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ImpactTile(label: '帖子获赞', value: value.postLikes),
                      _ImpactTile(label: '评论获赞', value: value.commentLikes),
                      _ImpactTile(label: '被收藏', value: value.favorites),
                      _ImpactTile(label: '我的评论', value: value.comments),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ImpactTile extends StatelessWidget {
  const _ImpactTile({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 数字先用 FittedBox 收窄：六位数在 1.3 倍字号下会比这一格还宽，
            // 与其让它溢出，不如让这一个数字自己缩小。
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                '$value',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onInk,
                  fontFeatures: AppTypography.tabularFigures,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.onInkMuted,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
}

/// 页面顶部的身份卡：圆形头像 + 用户名 + 邮箱 + 两枚状态徽标。
class _ProfileHero extends ConsumerWidget {
  const _ProfileHero({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final UserProfile? account = user;
    final bool signedIn = account != null;
    // 服务端存的是 /media/... 相对路径，显示前补成这台设备能访问的地址。
    final AppConfig config = ref.watch(appConfigProvider);
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
            children: <Widget>[
              _Avatar(
                initial: signedIn ? _initial(account.displayName) : '',
                signedIn: signedIn,
                avatarKey: account?.avatarKey,
                avatarUrl: config.resolveMediaUrl(account?.avatarUrl ?? ''),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      signedIn ? account.displayName : '还没有登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onInk,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      signedIn
                          ? '@${account.username} · ${account.email}'
                          : '登录后可保存、收藏并分享行程',
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
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              TagPill(
                signedIn ? '已登录' : '匿名体验中',
                tone: signedIn ? TagTone.settled : TagTone.neutral,
                dense: true,
              ),
              if (signedIn)
                TagPill(
                  account.emailVerified ? '邮箱已验证' : '未验证邮箱',
                  tone:
                      account.emailVerified ? TagTone.settled : TagTone.caution,
                  dense: true,
                ),
              if (signedIn && account.roles.isNotEmpty)
                TagPill(account.roles.join('、'),
                    tone: TagTone.sand, dense: true),
            ],
          ),
          if (!signedIn) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const AccountScreen()),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  foregroundColor: AppColors.celadonDeep,
                ),
                icon: const Icon(Icons.login, size: 16),
                label: const Text('登录 / 注册'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _initial(String name) =>
      name.isEmpty ? '游' : name.substring(0, 1);
}

/// 圆形头像。未登录时是空心人像，登录后是用户名首字。
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.initial,
    required this.signedIn,
    this.avatarKey,
    this.avatarUrl,
  });

  final String initial;
  final bool signedIn;
  final String? avatarKey;

  /// 已解析为绝对地址的自定义头像；为空表示用预设图案或用户名首字。
  final String? avatarUrl;

  /// 头像直径。整页只有这一个尺寸，写成常量比留一个参数更清楚。
  static const double size = 56;

  @override
  Widget build(BuildContext context) {
    final String url = avatarUrl?.trim() ?? '';
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // 双层描边而不是纯色块：深色卡面上，纯色圆和背景的边界太弱。
        color: signedIn ? AppColors.surfaceTint : Colors.white12,
        border: Border.all(color: const Color(0x66FFFFFF), width: 2),
      ),
      alignment: Alignment.center,
      child: !signedIn
          ? Icon(
              Icons.person_outline,
              size: size * 0.42,
              color: AppColors.onInkMuted,
            )
          : url.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  fadeInDuration: const Duration(milliseconds: 160),
                  // 图片挂了就回到首字/预设，不留一个碎图图标。
                  errorWidget: (_, __, ___) => _presetOrInitial(),
                  placeholder: (_, __) => const SizedBox.shrink(),
                )
              : _presetOrInitial(),
    );
  }

  Widget _presetOrInitial() {
    final IconData? icon = _avatarIcon(avatarKey);
    if (icon != null) {
      return Icon(icon, size: size * 0.42, color: _avatarIconColor(avatarKey));
    }
    return Text(
      initial,
      style: TextStyle(
        fontSize: size * 0.36,
        fontWeight: FontWeight.w700,
        color: AppColors.celadonDeep,
      ),
    );
  }

  static IconData? _avatarIcon(String? key) => switch (key) {
        'celadon' => Icons.landscape_outlined,
        'kiln' => Icons.account_balance_outlined,
        'amber' => Icons.wb_sunny_outlined,
        'river' => Icons.water_outlined,
        'ink' => Icons.auto_awesome_outlined,
        _ => null,
      };

  static Color _avatarIconColor(String? key) => switch (key) {
        'kiln' => AppColors.kilnRed,
        'amber' => AppColors.amber,
        _ => AppColors.celadonDeep,
      };
}

class _ProfileHeroSkeleton extends StatelessWidget {
  const _ProfileHeroSkeleton();

  @override
  Widget build(BuildContext context) => const SurfaceCard(
        color: AppColors.celadonDeep,
        child: SizedBox(
          height: 96,
          child: Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.onInk,
              ),
            ),
          ),
        ),
      );
}

class _ProfileErrorView extends StatelessWidget {
  const _ProfileErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline,
                    size: 16, color: AppColors.kilnRed),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.riskText,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      );
}

/// 分组里的一行入口。
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    this.icon,
    this.iconAsset,
    required this.title,
    required this.onTap,
    this.detail,
    this.trailingText,
    this.badge = 0,
    this.danger = false,
  });

  final IconData? icon;

  /// 素材图标（assets/icons/）。给了它就优先于 [icon]。
  final String? iconAsset;
  final String title;
  final String? detail;
  final String? trailingText;
  final int badge;
  final bool danger;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: <Widget>[
                if (iconAsset != null)
                  AppIcon(
                    iconAsset!,
                    size: 20,
                    color: danger ? AppColors.kilnRed : AppColors.celadon,
                  )
                else
                  Icon(
                    icon,
                    size: 19,
                    color: danger ? AppColors.kilnRed : AppColors.celadon,
                  ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w600,
                          color: danger ? AppColors.kilnRed : AppColors.ink,
                        ),
                      ),
                      if (detail != null) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          detail!,
                          style: const TextStyle(
                            fontSize: AppTypography.caption,
                            color: AppColors.crackle,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (badge > 0) ...<Widget>[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.kilnRed,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusPill),
                    ),
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (trailingText != null) ...<Widget>[
                  Text(
                    trailingText!,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                const Icon(Icons.chevron_right,
                    size: 18, color: AppColors.crackle),
              ],
            ),
          ),
        ),
      );
}

/// 收藏总站的三个板块。
///
/// 景区星标与旅记星标是两张真的收藏表，各自跟着账号走。行程**不是**"把
/// 自己创建的东西再收藏一次"：用户保存下来的行程本身就是他想留下的东西，
/// 再叠一层收藏只会让"取消收藏"和"删除行程"变成两件互相打架的事。所以
/// 第三块直接读已保存的行程列表。
enum _FavoritesTab {
  scenic('景区', Icons.landscape_outlined),
  post('旅记', Icons.article_outlined),
  trip('行程', Icons.route_outlined);

  const _FavoritesTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// 收藏里只存了 `poiId`，要打开景点详情就得把它还原成完整的 [Destination]。
///
/// 目录走的是仓库里那一份景点库（在线拉取 + 本地缓存 + 演示兜底），所以这里
/// 不会多出第二条内容来源；拉一次整页复用，下拉刷新时再显式作废。
final _scenicCatalogProvider = FutureProvider<List<Destination>>((ref) async {
  final CatalogResult catalog =
      await ref.watch(travelRepositoryProvider).fetchDestinations();
  return catalog.destinations;
});

/// 「我获得的互动」。
///
/// 未登录直接返回 null 而不是空统计：这两种状态在界面上要说不同的话
/// （"登录后查看" vs "还没有人互动"），用同一个 0 表示会把它们混成一件事。
final _communityStatsProvider = FutureProvider<CommunityStats?>((ref) async {
  if (ref.watch(sessionProvider).valueOrNull == null) {
    return null;
  }
  return ref.watch(communityRepositoryProvider).fetchMyStats();
});

/// 我的收藏。
///
/// v0.4 之前这一页只列景区收藏，而且每一行是静态文字 —— 点上去什么也不会
/// 发生，另外两类收藏根本没有入口。现在它是三个板块的收藏总站，每个最小
/// 单元都能点进对应的内容页。
class FavoritesScreen extends ConsumerStatefulWidget {
  const FavoritesScreen({super.key});

  @override
  ConsumerState<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends ConsumerState<FavoritesScreen> {
  _FavoritesTab _tab = _FavoritesTab.scenic;

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final bool signedIn = ref.watch(sessionProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        // 显式返回按钮：这一页在导航栈里恒有上一层，但把 leading 写死就不会
        // 因为栈形态变化而静默消失。
        leading: const AppBackButton(),
        title: const Text('我的收藏'),
      ),
      body: Column(
        children: <Widget>[
          _FavoritesTabBar(
            current: _tab,
            onChanged: (_FavoritesTab next) {
              if (next == _tab) {
                return;
              }
              setState(() => _tab = next);
            },
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (
                Widget child,
                Animation<double> animation,
              ) =>
                  FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.04, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey<_FavoritesTab>(_tab),
                child: signedIn
                    ? _buildSignedInTab(page)
                    : _FavoritesSignedOut(page: page),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedInTab(double page) {
    switch (_tab) {
      case _FavoritesTab.scenic:
        return _ScenicFavoritesTab(page: page);
      case _FavoritesTab.post:
        return CommunityFavoritesList(page: page, showIntro: false);
      case _FavoritesTab.trip:
        return _TripFavoritesTab(page: page);
    }
  }
}

/// 收藏总站的分段控件。
///
/// 不用 `SegmentedButton`：那个控件在 360dp 宽、1.3 倍字号下会把三个中文
/// 标签挤成省略号。这里是手写胶囊段，三段等宽，选中态是一层浮起的白底 ——
/// 切换时走颜色与阴影的过渡，不是硬跳。
class _FavoritesTabBar extends StatelessWidget {
  const _FavoritesTabBar({required this.current, required this.onChanged});

  final _FavoritesTab current;
  final ValueChanged<_FavoritesTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Padding(
      padding: EdgeInsets.fromLTRB(page, 6, page, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surfaceSunken,
          borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        ),
        child: Row(
          children: <Widget>[
            for (final _FavoritesTab tab in _FavoritesTab.values)
              Expanded(
                child: _FavoritesTabButton(
                  tab: tab,
                  selected: tab == current,
                  onTap: () => onChanged(tab),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FavoritesTabButton extends StatelessWidget {
  const _FavoritesTabButton({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _FavoritesTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color foreground =
        selected ? AppColors.celadonDeep : AppColors.crackle;
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              boxShadow: selected ? AppColors.chipShadow : const <BoxShadow>[],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(tab.icon, size: 15, color: foreground),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 景区收藏：一条一个景点，点进详情，点星标就地取消。
class _ScenicFavoritesTab extends ConsumerWidget {
  const _ScenicFavoritesTab({required this.page});

  final double page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<FavoriteItem>> favorites =
        ref.watch(favoritesProvider);
    // 目录可能还在路上，也可能这个景点已经从内容库下架 —— 两种情况下都
    // 先按收藏记录里存的字段把卡片画出来，点开时再决定能不能进详情。
    final List<Destination> catalog =
        ref.watch(_scenicCatalogProvider).valueOrNull ?? const <Destination>[];
    final Map<String, Destination> byId = <String, Destination>{
      for (final Destination destination in catalog)
        destination.id: destination,
    };

    return RefreshIndicator(
      onRefresh: () => _refresh(ref),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(page, 4, page, 36),
        children: <Widget>[
          const _FavoritesLead(
            text: '景点星标跟着账号走，换一台设备登录后仍然会回到这里。',
          ),
          const SizedBox(height: 14),
          favorites.when(
            loading: () => const _FavoritesLoading(),
            error: (Object error, StackTrace _) => _FavoritesNotice(
              icon: Icons.error_outline,
              tone: _FavoritesNoticeTone.risk,
              title: '收藏读取失败',
              text: error is ApiFailure ? error.message : '请稍后重试。',
              actionLabel: '重试',
              onAction: () => ref.invalidate(favoritesProvider),
            ),
            data: (List<FavoriteItem> items) => items.isEmpty
                ? const _FavoritesNotice(
                    icon: Icons.star_border,
                    title: '还没有收藏的景区',
                    text: '在景区详情页点星标，就能把它留在这里。',
                  )
                : Column(
                    children: <Widget>[
                      for (final FavoriteItem item in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _ScenicFavoriteCard(
                            item: item,
                            resolved: byId[item.poiId],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(_scenicCatalogProvider);
    ref.invalidate(favoritesProvider);
    try {
      await ref.read(favoritesProvider.future);
    } on Object {
      // 失败态由 provider 自己渲染；这里只负责让下拉动画收起。
    }
  }
}

class _ScenicFavoriteCard extends ConsumerWidget {
  const _ScenicFavoriteCard({required this.item, required this.resolved});

  final FavoriteItem item;

  /// 目录里对应的景点。目录还没到、或这个景点已下架时为 null。
  final Destination? resolved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? city = item.city;
    return PressScale(
      child: SurfaceCard(
        padding: const EdgeInsets.all(10),
        onTap: () => _open(context, ref),
        child: Row(
          children: <Widget>[
            PhotoPlate(
              url: resolved?.image ?? item.imageUrl ?? '',
              width: 74,
              height: 74,
              radius: AppSpacing.radiusControl,
              fallbackLabel: item.poiName,
              semanticLabel: item.poiName,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.poiName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.3,
                    ),
                  ),
                  if (city != null && city.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                      ),
                    ),
                  ],
                  const SizedBox(height: 7),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '查看景点详情',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w600,
                          color: AppColors.celadon,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 15,
                        color: AppColors.celadon,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _remove(context, ref),
              tooltip: '取消收藏',
              icon: const AppIcon(
                AppIcons.favoriteFilled,
                size: 20,
                color: AppColors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 打开景点详情。
  ///
  /// 目录已经到手上就直接进详情；还没到时先等目录 —— 等不到就如实说明
  /// "这个景点当前打不开"，而不是拿收藏记录里那点字段拼一个假详情页。
  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);

    Destination? destination = resolved;
    if (destination == null) {
      try {
        final List<Destination> catalog =
            await ref.read(_scenicCatalogProvider.future);
        destination = catalog.cast<Destination?>().firstWhere(
              (Destination? candidate) => candidate?.id == item.poiId,
              orElse: () => null,
            );
      } on ApiFailure catch (failure) {
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(failure.message)));
        return;
      }
    }

    final Destination? target = destination;
    if (target == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('这个景点当前未上架，详情暂时打不开。')),
        );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (BuildContext context) =>
            DestinationDetail(destination: target),
      ),
    );
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(favoritesProvider.notifier).toggle(
            poiId: item.poiId,
            poiName: item.poiName,
          );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已取消收藏。')));
    } on ApiFailure catch (failure) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

/// 行程：已保存的行程方案。
class _TripFavoritesTab extends ConsumerStatefulWidget {
  const _TripFavoritesTab({required this.page});

  final double page;

  @override
  ConsumerState<_TripFavoritesTab> createState() => _TripFavoritesTabState();
}

class _TripFavoritesTabState extends ConsumerState<_TripFavoritesTab> {
  late Future<TripListResult> _future;
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _future = ref.read(travelRepositoryProvider).fetchTripPlans();
  }

  Future<void> _reload() async {
    final Future<TripListResult> next =
        ref.read(travelRepositoryProvider).fetchTripPlans();
    setState(() => _future = next);
    await next;
  }

  /// 一次只开一份行程：连点两下不该 push 两条一模一样的路由。
  Future<void> _open(TripSummary summary) async {
    if (_openingId != null) {
      return;
    }
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final NavigatorState navigator = Navigator.of(context);
    setState(() => _openingId = summary.id);
    try {
      final PlanResult result =
          await ref.read(travelRepositoryProvider).fetchTripPlan(summary.id);
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<TripListResult>(
        future: _future,
        builder: (
          BuildContext context,
          AsyncSnapshot<TripListResult> snapshot,
        ) {
          final EdgeInsets padding =
              EdgeInsets.fromLTRB(widget.page, 4, widget.page, 36);
          if (snapshot.connectionState != ConnectionState.done) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              children: const <Widget>[_FavoritesLoading()],
            );
          }
          final TripListResult? data = snapshot.data;
          final List<TripSummary> items = data?.items ?? const <TripSummary>[];
          final ApiFailure? failure = data?.failure;
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: padding,
            children: <Widget>[
              const _FavoritesLead(
                text: '这里是你保存过的行程方案，点一条就能回到那份逐日安排。',
              ),
              const SizedBox(height: 14),
              if (failure != null) ...<Widget>[
                _FavoritesNotice(
                  icon: Icons.cloud_off_outlined,
                  tone: _FavoritesNoticeTone.caution,
                  title: '当前显示本地缓存',
                  text: failure.message,
                ),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty)
                const _FavoritesNotice(
                  icon: Icons.route_outlined,
                  title: '还没有保存的行程',
                  text: '在「规划」里生成一份方案并保存，它就会出现在这里。',
                )
              else
                for (final TripSummary summary in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TripFavoriteCard(
                      summary: summary,
                      opening: _openingId == summary.id,
                      onTap: () => _open(summary),
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _TripFavoriteCard extends StatelessWidget {
  const _TripFavoriteCard({
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
    final String updatedLabel =
        updated == null ? '' : ' · 更新于 ${_monthDay(updated.toLocal())}';
    return PressScale(
      child: SurfaceCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
        onTap: onTap,
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    summary.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      TagPill(summary.corridor, dense: true),
                      TagPill('${summary.daysCount} 天', dense: true),
                      TagPill(summary.intensity, dense: true),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '合计 ¥${summary.totalCost} · 人均 ¥${summary.perPersonCost}'
                    '$updatedLabel',
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
            const SizedBox(width: 6),
            if (opening)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.crackle,
              ),
          ],
        ),
      ),
    );
  }
}

/// 未登录：三类收藏都跟着账号走，所以这里只给一个入口，不摆三个空列表。
class _FavoritesSignedOut extends StatelessWidget {
  const _FavoritesSignedOut({required this.page});

  final double page;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(page, 4, page, 36),
        children: <Widget>[
          _FavoritesNotice(
            icon: Icons.lock_outline,
            title: '登录后查看收藏',
            text: '景区星标、旅记收藏和保存的行程都跟着账号走，登录后会一起回到这里。',
            actionLabel: '去登录',
            onAction: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext context) => const AccountScreen(),
              ),
            ),
          ),
        ],
      );
}

enum _FavoritesNoticeTone { neutral, caution, risk }

/// 收藏总站里的空态、错误态与缓存提示共用的一张卡。
class _FavoritesNotice extends StatelessWidget {
  const _FavoritesNotice({
    required this.icon,
    required this.title,
    required this.text,
    this.tone = _FavoritesNoticeTone.neutral,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String text;
  final _FavoritesNoticeTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final (Color surface, Color foreground, Color iconColor) = switch (tone) {
      _FavoritesNoticeTone.neutral => (
          AppColors.surfaceTint,
          AppColors.inkSoft,
          AppColors.celadonDeep,
        ),
      _FavoritesNoticeTone.caution => (
          AppColors.cautionSurface,
          AppColors.cautionText,
          AppColors.amber,
        ),
      _FavoritesNoticeTone.risk => (
          AppColors.riskSurface,
          AppColors.riskText,
          AppColors.kilnRed,
        ),
    };
    final String? label = actionLabel;
    return SurfaceCard(
      color: surface,
      shadow: const <BoxShadow>[],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      text,
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: foreground,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (label != null && onAction != null) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: onAction, child: Text(label)),
            ),
          ],
        ],
      ),
    );
  }
}

class _FavoritesLoading extends StatelessWidget {
  const _FavoritesLoading();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 34),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _FavoritesLead extends StatelessWidget {
  const _FavoritesLead({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: AppTypography.caption,
          color: AppColors.crackle,
          height: 1.6,
        ),
      );
}

/// 「12月31日」—— 只用于列表里的一句补充说明，不承担日历语义。
String _monthDay(DateTime value) => '${value.month}月${value.day}日';

/// 设置页：账号与安全、个人基本信息、软件设置。
///
/// 首版只把"现在的状态"如实列出来，不做假的开关 —— 一个点不动的开关比没有
/// 开关更让人困惑。还不能改的项直接写"规划中"。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final UserProfile? user = ref.watch(sessionProvider).valueOrNull;
    final AsyncValue<int> cacheSize = ref.watch(cacheSizeProvider);
    final bool signedIn = user != null;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          const _SectionLabel('账号与安全'),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              children: <Widget>[
                _SettingRow(
                  label: '登录状态',
                  value: signedIn ? '已登录' : '未登录（匿名体验中）',
                ),
                _SettingRow(label: '邮箱', value: signedIn ? user.email : '—'),
                _SettingRow(
                  label: '邮箱验证',
                  value: !signedIn
                      ? '—'
                      : user.emailVerified
                          ? '已验证'
                          : '未验证',
                ),
                _SettingRow(
                  label: '账号角色',
                  value: !signedIn || user.roles.isEmpty
                      ? '—'
                      : user.roles.join('、'),
                ),
                if (signedIn) ...<Widget>[
                  const Divider(height: 1),
                  _MenuRow(
                    icon: Icons.password_outlined,
                    title: '修改密码',
                    detail: '修改后所有设备需要重新登录',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const ChangePasswordScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _MenuRow(
                    icon: Icons.mark_email_read_outlined,
                    title: user.emailVerified ? '邮箱已验证' : '验证邮箱',
                    detail: user.emailVerified
                        ? user.email
                        : '验证 ${user.email}，用于账号安全',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const VerifyEmailScreen(),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  _MenuRow(
                    icon: Icons.devices_other_outlined,
                    title: '退出所有设备',
                    detail: '撤销所有刷新令牌，本机也会退出',
                    onTap: () => _logoutAll(context, ref),
                  ),
                  const Divider(height: 1),
                  _MenuRow(
                    icon: Icons.delete_forever_outlined,
                    title: '删除账号',
                    detail: '删除账号、行程、收藏与分享',
                    danger: true,
                    onTap: () => _deleteAccount(context, ref),
                  ),
                ],
              ],
            ),
          ),
          const _InfoNote(
            '邮箱验证码与密码找回走 SMTP，属于首版预留能力：未配置 SMTP 时验证码只写入服务端日志。',
          ),
          const SizedBox(height: AppSpacing.section),
          const _SectionLabel('个人基本信息'),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              children: <Widget>[
                _SettingRow(
                  label: '用户名',
                  value: signedIn ? user.username : '—',
                ),
                if (signedIn) ...<Widget>[
                  const Divider(height: 1),
                  _MenuRow(
                    icon: Icons.badge_outlined,
                    title: '昵称与头像',
                    detail: user.displayName,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EditProfileScreen(),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const _InfoNote(
            '头像可以用预设图案，也可以上传自己的照片；上传的照片会重新编码并去掉位置信息。',
          ),
          const SizedBox(height: AppSpacing.section),
          const _SectionLabel('软件设置'),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Column(
              children: <Widget>[
                const _SettingRow(label: '外观', value: '跟随系统（浅色）'),
                const _SettingRow(label: '字体大小', value: '跟随系统设置'),
                const _SettingRow(label: '动效', value: '尊重系统「减少动态效果」'),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.system_update_alt,
                  title: '检查更新',
                  detail: '向服务端查询是否有新版本',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const CheckUpdateScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.cached_outlined,
                  title: '清除离线缓存',
                  detail: cacheSize.when(
                    data: (bytes) =>
                        bytes <= 0 ? '当前没有缓存' : '当前占用 ${_formatBytes(bytes)}',
                    loading: () => '正在计算缓存…',
                    error: (_, __) => '缓存大小暂不可读',
                  ),
                  onTap: () => _clearCache(context, ref),
                ),
              ],
            ),
          ),
          const _InfoNote(
            '字体与动效都读系统设置，而不是在应用里另做一套开关：系统的无障碍设置是用户已经调好的那一个。',
          ),
          if (signedIn) ...<Widget>[
            const SizedBox(height: AppSpacing.section),
            Center(
              child: TextButton(
                onPressed: () => confirmSignOut(context, ref),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.kilnRed,
                  minimumSize: const Size(0, AppSpacing.minTouchTarget),
                ),
                child: const Text('退出登录'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _clearCache(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('清除离线缓存？'),
        content: const Text('只会删除本机的景点与最近行程缓存，不会删除服务端账号、行程或收藏。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localCacheProvider)?.clearAll();
    ref.invalidate(cacheSizeProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('离线缓存已清除。')));
  }

  Future<void> _logoutAll(BuildContext context, WidgetRef ref) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('退出所有设备？'),
        content: const Text('会撤销所有设备的刷新令牌，本机也会退出登录。当前短时访问令牌到期后需要重新登录。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出所有设备'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(sessionProvider.notifier).logoutAllDevices();
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('已退出所有设备。')));
    } on ApiFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final TextEditingController password = TextEditingController();
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除账号？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('账号、行程、收藏与分享会被永久删除，且无法恢复。请输入密码确认。'),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: '当前密码'),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.kilnRed),
            onPressed: () => Navigator.of(context).pop(password.text),
            child: const Text('永久删除'),
          ),
        ],
      ),
    );
    password.dispose();
    if (value == null || value.isEmpty) return;
    try {
      await ref.read(sessionProvider.notifier).deleteAccount(value);
      if (!context.mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('账号已删除。')));
    } on ApiFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 隐私与数据：把"存什么、不存什么、你能做什么"写成三条清单。
class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScaffold(
        title: '隐私与数据',
        intro: '这一页写的都是已经生效的做法，不是承诺清单。',
        blocks: const <_InfoBlock>[
          _InfoBlock(
            title: '我们保存的信息',
            lines: <String>[
              '账号：用户名、邮箱、口令的哈希值（不保存明文口令）。',
              '行程：出发地、目的地、天数、预算区间与生成的逐日安排。',
              '收藏与分享链接：只保存景区标识与分享所需的最小字段。',
              '匿名体验：一个设备指纹哈希与剩余体验次数，用于免登录试用。',
            ],
          ),
          _InfoBlock(
            title: '我们不采集的信息',
            lines: <String>[
              '身份证号、银行卡号与任何支付信息 —— 平台内不完成购票与支付。',
              '后台持续定位：只有你主动打开「附近景点」时才请求一次位置。',
              '与旅行无关的精确住址，以及无业务必要的设备信息。',
            ],
          ),
          _InfoBlock(
            title: '你的权利',
            lines: <String>[
              '删除行程：在「行程 - 历史行程」里删除，逐日安排一并删除。',
              '关闭分享：分享链接可以随时撤销，撤销后立即失效。',
              '删除账号：在设置中发起后，账号与行程一并删除，不做保留。',
              '查看来源：行程里每一条外部数据都标注了实时、缓存或演示。',
            ],
          ),
          _InfoBlock(
            title: '密钥与日志',
            lines: <String>[
              '地图、模型与 SMTP 的密钥只存在服务端环境变量，不进 APK。',
              '日志不记录口令、令牌与完整敏感请求体。',
            ],
          ),
        ],
      );
}

/// 第三方数据来源：谁提供什么、什么时候是演示数据。
class DataSourcesScreen extends StatelessWidget {
  const DataSourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScaffold(
        title: '第三方数据来源',
        intro: '外部数据一律由服务端调用，APK 不内置任何第三方密钥。',
        blocks: const <_InfoBlock>[
          _InfoBlock(
            title: '百度地图 Web 服务',
            lines: <String>[
              '用途：跨城与市内的路线、距离、耗时，以及景点的 POI 检索。',
              '可能拿到缓存结果（同一路线短时间内重复查询时），界面会标注。',
            ],
          ),
          _InfoBlock(
            title: 'Open-Meteo',
            lines: <String>[
              '用途：出行日期的温度、降水概率与风力，用于判断户外安排是否可行。',
              '预报有更新周期，展示时会带上取数时间。',
            ],
          ),
          _InfoBlock(
            title: '12306 适配层',
            lines: <String>[
              '用途：车次、余票、票价与经停信息，作为跨城交通方案的参考。',
              '平台不代购、不保存身份证号；购票请到官方渠道完成。',
            ],
          ),
          _InfoBlock(
            title: '大模型服务',
            lines: <String>[
              '用途：理解自然语言需求、编排外部工具、生成结构化行程。',
              '可切换 OpenAI / DeepSeek / Kimi / Qwen，也支持本地演示模式。',
              '模型只负责表达与编排；时间冲突、开放时间与预算校验由后端完成。',
            ],
          ),
          _InfoBlock(
            title: '图片与文案',
            lines: <String>[
              '景区图片由运营台在后台上传，并登记来源与版权。',
              '没有登记来源的图片会被标记出来，不会当成已授权素材。',
            ],
          ),
        ],
      );
}

/// 关于豫见智旅。
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) => _InfoScaffold(
        title: '关于豫见智旅',
        intro: '面向河南自由行游客的 AI 旅行规划与智慧出行平台。',
        blocks: const <_InfoBlock>[
          _InfoBlock(
            title: '版本',
            lines: <String>[
              'v0.3 · Android 首发（Flutter）',
              '服务端：Spring Boot + MySQL 8；管理台：Vue 3 + Vite',
            ],
          ),
          _InfoBlock(
            title: '这个版本重点做了什么',
            lines: <String>[
              '行程页变成"我的行程"首页：进行中的行程、历史行程与你去过的地方。',
              '足迹里的城市与里程来自真实落库的行程，不估算、不补默认值。',
              '外部数据全部标注实时 / 缓存 / 演示，行程能不能走通要给出依据。',
            ],
          ),
          _InfoBlock(
            title: '免责说明',
            lines: <String>[
              '开放时间、门票与车次为参考信息，出行前请以景区与 12306 官方为准。',
              '天气与路况会变化，行程里的时间安排不构成安全保证。',
            ],
          ),
          _InfoBlock(
            title: '开源依赖',
            lines: <String>[
              '只使用 MIT / BSD / Apache-2.0 许可的组件，清单见交付文档',
              'THIRD_PARTY_NOTICES.md。',
            ],
          ),
        ],
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.small),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: AppTypography.secondary,
            fontWeight: FontWeight.w700,
            color: AppColors.crackle,
            letterSpacing: AppTypography.labelTracking,
          ),
        ),
      );
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 92,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  color: AppColors.ink,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.crackle,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}

class _InfoNote extends StatelessWidget {
  const _InfoNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10, left: 2, right: 2),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            color: AppColors.crackle,
            height: 1.6,
          ),
        ),
      );
}

class _InfoScaffold extends StatelessWidget {
  const _InfoScaffold({
    required this.title,
    required this.blocks,
    this.intro,
  });

  final String title;
  final String? intro;
  final List<_InfoBlock> blocks;

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final String? lead = intro;
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 36),
        children: <Widget>[
          if (lead != null) ...<Widget>[
            Text(
              lead,
              style: const TextStyle(
                fontSize: AppTypography.lead,
                color: AppColors.inkSoft,
                height: 1.6,
              ),
            ),
            const SizedBox(height: AppSpacing.section),
          ],
          for (final _InfoBlock block in blocks) ...<Widget>[
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    block.title,
                    style: const TextStyle(
                      fontSize: AppTypography.cardTitle,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (final String line in block.lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Padding(
                            padding: EdgeInsets.only(top: 6, right: 8),
                            child: SizedBox(
                              width: 5,
                              height: 5,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.celadon,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              line,
                              style: const TextStyle(
                                fontSize: AppTypography.body,
                                color: AppColors.inkSoft,
                                height: 1.6,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.content),
          ],
        ],
      ),
    );
  }
}

class _InfoBlock {
  const _InfoBlock({required this.title, required this.lines});

  final String title;
  final List<String> lines;
}
