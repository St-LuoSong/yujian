import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/config/app_config.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../models/account_models.dart';
import 'account_screen.dart';
import 'account_security_screens.dart';
import 'additional_screens.dart';
import 'messages_screen.dart';
import 'my_community_posts_screen.dart';
import 'server_endpoint_screen.dart';

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
          SurfaceCard(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                _MenuRow(
                  icon: Icons.star_border,
                  title: '我的收藏',
                  detail: '想去的景区',
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

/// 页面顶部的身份卡：圆形头像 + 用户名 + 邮箱 + 两枚状态徽标。
class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final UserProfile? account = user;
    final bool signedIn = account != null;
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
                  tone: account.emailVerified ? TagTone.settled : TagTone.caution,
                  dense: true,
                ),
              if (signedIn && account.roles.isNotEmpty)
                TagPill(account.roles.join('、'), tone: TagTone.sand, dense: true),
            ],
          ),
          if (!signedIn) ...<Widget>[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
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
  });

  final String initial;
  final bool signedIn;
  final String? avatarKey;

  /// 头像直径。整页只有这一个尺寸，写成常量比留一个参数更清楚。
  static const double size = 56;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // 双层描边而不是纯色块：深色卡面上，纯色圆和背景的边界太弱。
          color: signedIn ? AppColors.surfaceTint : Colors.white12,
          border: Border.all(color: const Color(0x66FFFFFF), width: 2),
        ),
        alignment: Alignment.center,
        child: signedIn
            ? _avatarIcon(avatarKey) != null
                ? Icon(
                    _avatarIcon(avatarKey),
                    size: size * 0.42,
                    color: _avatarIconColor(avatarKey),
                  )
                : Text(
                    initial,
                    style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.w700,
                      color: AppColors.celadonDeep,
                    ),
                  )
            : Icon(
                Icons.person_outline,
                size: size * 0.42,
                color: AppColors.onInkMuted,
              ),
      );

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
    required this.icon,
    required this.title,
    required this.onTap,
    this.detail,
    this.trailingText,
    this.badge = 0,
    this.danger = false,
  });

  final IconData icon;
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
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

/// 我的收藏：独立成页，不再挤在"我的"页上。
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final AsyncValue<List<FavoriteItem>> favorites =
        ref.watch(favoritesProvider);
    final bool signedIn = ref.watch(sessionProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(title: const Text('我的收藏')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(page, 8, page, 32),
        children: <Widget>[
          if (!signedIn) ...<Widget>[
            const _InfoNote('收藏是跟着账号走的：登录后收藏的景区会在换设备时同步回来。'),
            const SizedBox(height: AppSpacing.content),
          ],
          SurfaceCard(
            child: favorites.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace _) => Text(
                error is ApiFailure ? error.message : '收藏读取失败，请稍后重试。',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.riskText,
                  height: 1.6,
                ),
              ),
              data: (List<FavoriteItem> items) => items.isEmpty
                  ? const Text(
                      '还没有收藏的景点。在景区详情页点「收藏」即可加入。',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        color: AppColors.crackle,
                        height: 1.6,
                      ),
                    )
                  : Column(
                      children: <Widget>[
                        for (int index = 0; index < items.length; index++)
                          ...<Widget>[
                            if (index > 0) const Divider(height: 1),
                            _FavoriteRow(item: items[index]),
                          ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteRow extends ConsumerWidget {
  const _FavoriteRow({required this.item});

  final FavoriteItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? city = item.city;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: <Widget>[
          const Icon(Icons.star, size: 18, color: AppColors.amber),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.poiName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.body,
                    color: AppColors.ink,
                  ),
                ),
                if (city != null && city.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 3),
                  Text(
                    city,
                    style: const TextStyle(
                      fontSize: AppTypography.caption,
                      color: AppColors.crackle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: () => ref.read(favoritesProvider.notifier).toggle(
                  poiId: item.poiId,
                  poiName: item.poiName,
                ),
            tooltip: '取消收藏',
            icon: const Icon(Icons.close, size: 16),
          ),
        ],
      ),
    );
  }
}



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
    final AppConfig config = ref.watch(appConfigProvider);
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
          const _InfoNote('头像使用预设图案，不上传照片；这样不会把个人照片放到公开图片地址。'),
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
                  icon: Icons.dns_outlined,
                  title: '服务器地址',
                  detail: config.lockedByBuild
                      ? '当前安装包已固定'
                      : (config.apiBaseUrl.isEmpty ? '未配置' : config.apiBaseUrl),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const ServerEndpointScreen(),
                    ),
                  ),
                ),
                const Divider(height: 1),
                _MenuRow(
                  icon: Icons.cached_outlined,
                  title: '清除离线缓存',
                  detail: cacheSize.when(
                    data: (bytes) => bytes <= 0
                        ? '当前没有缓存'
                        : '当前占用 ${_formatBytes(bytes)}',
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
