import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/models/trip_models.dart';
import 'package:yujian_travel/screens/messages_screen.dart';

import '../support/test_http.dart';

/// 本轮三个界面改动的回归：
/// 1. 行程页默认是"我的行程"首页，不是一进门就把最新那份行程摊开；
/// 2. 首页右上角的铃铛与头像都是真入口，未读红点跟着已读状态走；
/// 3. 足迹的三项统计只认服务端聚合出来的数字。
void main() {
  group('足迹口径', () {
    test('服务端返回的城市与里程被原样读入，不做估算', () {
      final TripFootprint footprint = TripFootprint.fromJson(<String, dynamic>{
        'cities': <Object>[
          <String, Object>{
            'name': '洛阳',
            'tripCount': 2,
            'firstVisitAt': '2026-09-01T10:00:00Z',
            'lastVisitAt': '2026-10-01T10:00:00Z',
          },
          <String, Object>{'name': '开封', 'tripCount': 1},
        ],
        'totalMeters': 51200,
        'totalDays': 5,
        'tripCount': 2,
      });

      expect(footprint.cities.map((CityVisit city) => city.name), <String>['洛阳', '开封']);
      expect(footprint.cities.first.tripCount, 2);
      expect(footprint.cities.last.lastVisitAt, isNull);
      expect(footprint.totalKm, closeTo(51.2, 0.001));
      expect(footprint.totalDays, 5);
      expect(footprint.isEmpty, isFalse);
    });

    test('一份行程都没有时是空足迹，不是一份零公里的假数据', () {
      const TripFootprint empty = TripFootprint.empty;

      expect(empty.isEmpty, isTrue);
      expect(empty.cities, isEmpty);
      expect(empty.totalMeters, 0);
      expect(empty.totalKm, 0);
    });
  });

  group('消息中心', () {
    test('未读数跟着已读状态走，重复标记同一条不会重复计数', () async {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(
            AppBootstrap(
              config: const AppConfig(
                apiBaseUrl: '',
                connectTimeout: Duration(seconds: 1),
                receiveTimeout: Duration(seconds: 1),
                sendTimeout: Duration(seconds: 1),
              ),
              sessionStore: SessionStore(storage: MemoryKeyValueStore()),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      final inbox = await container.read(noticeInboxProvider.future);
      expect(inbox.items, isNotEmpty);
      expect(container.read(unreadNoticeCountProvider), inbox.unread);

      final String first = inbox.items.first.id;
      container.read(readNoticesProvider.notifier)
        ..markRead(first)
        ..markRead(first);
      await container.read(noticeInboxProvider.future);
      expect(container.read(unreadNoticeCountProvider), inbox.items.length - 1);

      container.read(readNoticesProvider.notifier).markAll(
            inbox.items.map((notice) => notice.id),
          );
      await container.read(noticeInboxProvider.future);
      expect(container.read(unreadNoticeCountProvider), 0);
    });
  });

  group('行程页首页', () {
    testWidgets('默认停在"我的行程"，点新建才进规划表单', (WidgetTester tester) async {
      await _pumpApp(tester, const Size(390, 844));
      await _selectTab(tester, Icons.route_outlined);

      // '我的行程' 在"我的"页也有一条入口，所以这里只断言它确实出现了。
      expect(find.text('我的行程'), findsWidgets);
      expect(find.text('记录每一次出发与抵达'), findsOneWidget);
      expect(find.text('查看历史行程'), findsOneWidget);
      expect(
        find.text('生成专属行程'),
        findsNothing,
        reason: '行程页不该一进来就把规划表单摊开',
      );

      await tester.tap(find.text('新建一个行程').first);
      await tester.pumpAndSettle();

      expect(find.text('生成专属行程'), findsOneWidget);
      expect(find.text('规划行程'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('发现页顶栏', () {
    testWidgets('铃铛可点开消息中心，点开一条就变成已读', (WidgetTester tester) async {
      await _pumpApp(tester, const Size(390, 844));

      // 顶栏两个入口都要在：铃铛 + 圆形头像。
      expect(find.byKey(const Key('home-notice-bell')), findsOneWidget);
      expect(find.byKey(const Key('home-avatar')), findsOneWidget);

      final ProviderContainer container =
          tester.widget<UncontrolledProviderScope>(
        find.byType(UncontrolledProviderScope).first,
      ).container;
      final int unread = container.read(unreadNoticeCountProvider);
      expect(unread, greaterThan(0));

      await tester.tap(find.byKey(const Key('home-notice-bell')));
      await tester.pumpAndSettle();

      expect(find.text('消息通知'), findsWidgets);
      expect(find.text('未读'), findsWidgets);

      // 点开一条 = 已读，红点的数字要跟着掉一个。
      await tester.tap(find.text('行程页新增「你的足迹」'));
      await tester.pumpAndSettle();

      expect(container.read(unreadNoticeCountProvider), unread - 1);
      expect(find.text('已读'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点头像切到"我的"页', (WidgetTester tester) async {
      await _pumpApp(tester, const Size(390, 844));

      await tester.tap(find.byKey(const Key('home-avatar')));
      await tester.pumpAndSettle();

      expect(find.text('我的收藏'), findsOneWidget);
      expect(find.text('隐私与数据'), findsOneWidget);
      expect(find.text('关于豫见智旅'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(
          AppBootstrap(
            config: const AppConfig(
              apiBaseUrl: '',
              connectTimeout: Duration(seconds: 1),
              receiveTimeout: Duration(seconds: 1),
              sendTimeout: Duration(seconds: 1),
            ),
            sessionStore: SessionStore(storage: MemoryKeyValueStore()),
          ),
        ),
      ],
      child: const YujianApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _selectTab(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}
