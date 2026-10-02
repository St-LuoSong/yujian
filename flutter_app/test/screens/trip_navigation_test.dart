import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/core/widgets/app_back_button.dart';

import '../support/test_http.dart';

/// 行程导航的回归用例。
///
/// 起因是用户实测报的一个"卡死"：从「我的」进「我的行程」，再点开一份行程之后，
/// 返回按钮和底部导航都不见了，人被困在行程详情里。
///
/// 这里锁住三件事：
/// 1. 行程相关页面用的是**显式**返回按钮（AppBackButton），不再依赖 AppBar 的自动
///    leading —— 后者只在"这条路由下面还有活动路由"时才出现，属于静默失效；
/// 2. 三条入口（我的 → 我的行程、行程 → 查看历史行程、行程 → 最近一次行程卡片）
///    一路退回之后，主导航（底部导航栏）一定还在；
/// 3. 连点两下入口只压一层历史页，按一次返回直接回到行程首页。
void main() {
  testWidgets('我的 → 我的行程 → 打开行程：每层都能退回，底部导航最后还在',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    await _selectTab(tester, Icons.person_outline);
    expect(find.text('我的行程'), findsOneWidget);

    await tester.tap(find.text('我的行程'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget);
    expect(find.text('全部行程'), findsOneWidget);

    // 历史页里最近一份会出现两次：顶部「下一站」卡片与列表行。取列表行。
    await tester.tap(find.text(_planTitle).last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget);
    expect(find.text('龙门石窟'), findsWidgets);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget,
        reason: '退回历史页后仍然要有返回按钮');

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: '退回主导航后底部导航栏必须还在');
    expect(find.text('我的收藏'), findsOneWidget);
  });

  testWidgets('行程 → 查看历史行程 → 打开行程：一路退回仍是行程首页',
      (WidgetTester tester) async {
    await _pumpApp(tester);

    await _selectTab(tester, Icons.route_outlined);
    // 行程首页里它出现两次：动作卡标题 + 足迹空状态里的按钮。
    expect(find.text('新建一个行程'), findsWidgets);

    await tester.tap(find.text('查看历史行程'));
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget);

    await tester.tap(find.text(_planTitle).last);
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('新建一个行程'), findsWidgets);
  });

  testWidgets('行程首页的「最近一次行程」卡片也能打开并退回',
      (WidgetTester tester) async {
    await _pumpApp(tester);
    await _selectTab(tester, Icons.route_outlined);

    await tester.tap(find.text(_planTitle).first);
    await tester.pumpAndSettle();
    expect(find.byType(AppBackButton), findsOneWidget);
    expect(find.text('龙门石窟'), findsWidgets);

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget,
        reason: '从最近一次行程退回后底部导航必须还在');
    expect(find.text('查看历史行程'), findsOneWidget);
  });

  testWidgets('连点两下「查看历史行程」不会压入两层历史页',
      (WidgetTester tester) async {
    await _pumpApp(tester);
    await _selectTab(tester, Icons.route_outlined);

    final Finder entry = find.text('查看历史行程');
    await tester.tap(entry);
    await tester.pump(const Duration(milliseconds: 30));
    await tester.tap(entry, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('全部行程'), findsOneWidget);

    // 只按一次返回就应该回到行程首页；如果压了两层，这里会停在另一个历史页。
    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(find.text('新建一个行程'), findsWidgets,
        reason: '一次返回应当直接回到行程首页');
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}

const String _planTitle = '洛阳历史文化两日游';

Future<void> _pumpApp(WidgetTester tester) async {
  final RecordingAdapter adapter = RecordingAdapter((options, _) async {
    switch (options.path) {
      case '/pois':
        return jsonBody(<Object>[]);
      case '/trip-plans':
        return jsonBody(<Object>[_summaryJson()]);
      case '/trip-plans/plan-1/today':
        return jsonBody(<String, Object>{
          'tripId': 'plan-1',
          'date': '今日',
          'nextStop': '龙门石窟',
          'arrival': '09:00',
          'weather': '晴 18—26℃',
          'status': '演示数据',
          'remainingItems': <Object>[],
        });
      case '/trip-plans/plan-1':
        return jsonBody(_planJson());
      case '/trip-plans/footprint':
        return jsonBody(<String, Object>{
          'cities': <Object>[],
          'totalMeters': 0,
          'totalDays': 0,
          'tripCount': 0,
        });
      default:
        return jsonBody(<String, Object>{});
    }
  });

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(
          AppBootstrap(
            config: const AppConfig(
              apiBaseUrl: testBaseUrl,
              connectTimeout: Duration(seconds: 1),
              receiveTimeout: Duration(seconds: 1),
              sendTimeout: Duration(seconds: 1),
            ),
            sessionStore: SessionStore(storage: MemoryKeyValueStore()),
          ),
        ),
        apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
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

Map<String, Object> _summaryJson() => <String, Object>{
      'id': 'plan-1',
      'title': _planTitle,
      'summary': '沿着伊河读懂千年中原',
      'corridor': '郑州—洛阳',
      'intensity': '适中',
      'totalCost': 384,
      'perPersonCost': 192,
      'daysCount': 2,
      'dataStatus': '演示数据',
      'updatedAt': '2026-10-01T10:00:00Z',
    };

Map<String, Object> _planJson() => <String, Object>{
      'id': 'plan-1',
      'title': _planTitle,
      'corridor': '郑州—洛阳',
      'intensity': '适中',
      'totalCost': 384,
      'perPersonCost': 192,
      'dataStatus': '演示数据',
      'warnings': <String>['门票信息请以官方渠道为准。'],
      'days': <Object>[
        <String, Object>{
          'label': 'DAY 01',
          'date': '古都一日',
          'items': <Object>[
            <String, Object>{
              'type': '景点',
              'title': '龙门石窟',
              'time': '09:00',
              'duration': '约3小时',
              'transport': '公共交通',
              'description': '洛阳站 → 景区约20分钟',
              'cost': 90,
              'source': '系统景点库',
              'dataStatus': '演示数据',
              'risk': '建议提前预约',
            },
          ],
        },
      ],
    };
