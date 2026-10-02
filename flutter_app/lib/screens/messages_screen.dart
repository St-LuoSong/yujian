import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../app/session_providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/theme/app_typography.dart';
import '../core/widgets/press_scale.dart';
import '../core/widgets/surface_card.dart';
import '../core/widgets/tag_pill.dart';
import '../models/message_models.dart';

const List<NoticeMessage> _localNotices = <NoticeMessage>[
  NoticeMessage(
    id: 'release-v03',
    type: 'RELEASE',
    title: '行程页新增「你的足迹」',
    body: '足迹里的城市、里程与旅行天数都由已保存的行程聚合；里程只统计路线工具真的给过距离的路段。',
  ),
  NoticeMessage(
    id: 'data-sources',
    type: 'DATA',
    title: '天气、车次与路线从哪里来',
    body: '三条外部数据都在服务端统一调用，并在行程里标注实时、缓存还是演示数据。',
  ),
  NoticeMessage(
    id: 'privacy',
    type: 'PRIVACY',
    title: '我们不采集这些信息',
    body: '身份证号、银行卡号、支付信息与后台持续定位都不在采集范围内；定位只在主动打开附近景点时请求一次。',
  ),
  NoticeMessage(
    id: 'tripsync',
    type: 'TRIP_SYNC',
    title: '保存的行程跟着账号走',
    body: '登录后同一份行程可以在其它设备继续打开；分享出去的是只读链接，对方改不到原方案。',
  ),
];

/// Local read state used before the user signs in.
///
/// Once an account is available, the server is the source of truth and this
/// provider is not consulted.
final readNoticesProvider =
    NotifierProvider<ReadNotices, Set<String>>(ReadNotices.new);

class ReadNotices extends Notifier<Set<String>> {
  @override
  Set<String> build() => const <String>{};

  void markRead(String id) {
    if (state.contains(id)) return;
    state = <String>{...state, id};
  }

  void markAll(Iterable<String> ids) {
    state = <String>{...state, ...ids};
  }
}

final noticeInboxProvider =
    AsyncNotifierProvider<NoticeInboxController, NoticeInbox>(
  NoticeInboxController.new,
);

class NoticeInboxController extends AsyncNotifier<NoticeInbox> {
  bool _localMode = true;

  @override
  Future<NoticeInbox> build() async {
    final user = ref.watch(sessionProvider).valueOrNull;
    _localMode = user == null;
    if (_localMode) {
      return _localInbox(ref.watch(readNoticesProvider));
    }
    return ref.watch(accountRepositoryProvider).listMessages();
  }

  Future<void> markRead(String id) async {
    if (_localMode) {
      ref.read(readNoticesProvider.notifier).markRead(id);
      return;
    }
    await ref.read(accountRepositoryProvider).markMessageRead(id);
    ref.invalidateSelf();
    await future;
  }

  Future<void> markAll() async {
    if (_localMode) {
      ref.read(readNoticesProvider.notifier)
          .markAll(_localNotices.map((notice) => notice.id));
      return;
    }
    await ref.read(accountRepositoryProvider).markAllMessagesRead();
    ref.invalidateSelf();
    await future;
  }
}

NoticeInbox _localInbox(Set<String> read) {
  final items = _localNotices
      .map((notice) => NoticeMessage(
            id: notice.id,
            type: notice.type,
            title: notice.title,
            body: notice.body,
            read: read.contains(notice.id),
          ))
      .toList();
  return NoticeInbox(
    items: items,
    unread: items.where((item) => !item.read).length,
  );
}

/// Unread badge for the account page and the message entry.
final unreadNoticeCountProvider = Provider<int>(
  (ref) => ref.watch(noticeInboxProvider).valueOrNull?.unread ?? 0,
);

class MessagesScreen extends ConsumerWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    final AsyncValue<NoticeInbox> inbox = ref.watch(noticeInboxProvider);
    final bool signedIn = ref.watch(sessionProvider).valueOrNull != null;

    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        title: const Text('消息通知'),
        actions: <Widget>[
          if ((inbox.valueOrNull?.unread ?? 0) > 0)
            TextButton(
              onPressed: () => ref.read(noticeInboxProvider.notifier).markAll(),
              child: const Text('全部已读'),
            ),
        ],
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace _) => Center(
          child: Padding(
            padding: EdgeInsets.all(page),
            child: Text(
              error is ApiFailure ? error.message : '消息加载失败，请稍后重试。',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppTypography.caption,
                color: AppColors.riskText,
                height: 1.6,
              ),
            ),
          ),
        ),
        data: (NoticeInbox data) => ListView(
          padding: EdgeInsets.fromLTRB(page, 6, page, 32),
          children: <Widget>[
            _NoticeProvenance(signedIn: signedIn),
            const SizedBox(height: AppSpacing.section),
            for (final NoticeMessage notice in data.items) ...<Widget>[
              _NoticeTile(
                notice: notice,
                unread: !notice.read,
                onTap: () =>
                    ref.read(noticeInboxProvider.notifier).markRead(notice.id),
              ),
              const SizedBox(height: AppSpacing.content),
            ],
          ],
        ),
      ),
    );
  }
}

class _NoticeProvenance extends StatelessWidget {
  const _NoticeProvenance({required this.signedIn});

  final bool signedIn;

  @override
  Widget build(BuildContext context) => SurfaceCard(
        color: AppColors.surfaceTint,
        shadow: const <BoxShadow>[],
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Icon(Icons.campaign_outlined,
                size: 18, color: AppColors.celadonDeep),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                signedIn
                    ? '消息保存在账号下，已读状态会随账号同步；这不是实时推送，也不代表有人在后台持续跟踪。'
                    : '当前显示本机产品说明；登录后消息与已读状态会同步到账号。',
                style: const TextStyle(
                  fontSize: AppTypography.caption,
                  color: AppColors.inkSoft,
                  height: 1.6,
                ),
              ),
            ),
          ],
        ),
      );
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({
    required this.notice,
    required this.unread,
    required this.onTap,
  });

  final NoticeMessage notice;
  final bool unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
        child: SurfaceCard(
          border: unread ? AppColors.celadon : AppColors.hairline,
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: unread
                          ? AppColors.celadonDeep
                          : AppColors.surfaceSunken,
                      borderRadius:
                          BorderRadius.circular(AppSpacing.radiusSmall),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      _iconFor(notice.type),
                      size: 18,
                      color: unread ? AppColors.onInk : AppColors.crackle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      notice.title,
                      style: TextStyle(
                        fontSize: AppTypography.cardTitle,
                        fontWeight:
                            unread ? FontWeight.w700 : FontWeight.w600,
                        color: AppColors.ink,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (unread)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.kilnRed,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                notice.body,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  color: AppColors.inkSoft,
                  height: 1.65,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  TagPill(_tagFor(notice.type), dense: true),
                  const SizedBox(width: 8),
                  Text(
                    unread ? '未读' : '已读',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w700,
                      color: unread ? AppColors.kilnRed : AppColors.crackle,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  static IconData _iconFor(String type) => switch (type) {
        'RELEASE' => Icons.map_outlined,
        'DATA' => Icons.hub_outlined,
        'PRIVACY' => Icons.shield_outlined,
        'TRIP_SYNC' => Icons.route_outlined,
        _ => Icons.notifications_none,
      };

  static String _tagFor(String type) => switch (type) {
        'RELEASE' => '版本',
        'DATA' => '数据',
        'PRIVACY' => '安全',
        'TRIP_SYNC' => '行程',
        _ => '系统',
      };
}
