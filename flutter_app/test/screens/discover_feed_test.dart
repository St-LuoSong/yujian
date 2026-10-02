import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/data/repositories/travel_repository.dart';

import '../support/test_http.dart';

/// 首页"此刻去看看"的行为。
///
/// 这条信息流要同时满足两件看起来相反的事：
///   - 内容库越来越大，首页不能一次把整份目录铺出来；
///   - 用户往下滑的时候又不能卡住，得自己续。
/// 外加一条产品决定：**切回发现页要回到初始态**，而不是接着上次往下滚。
///
/// 注意：行程页在 IndexedStack 里一起被建起来，它也会走 /pois 取一份完整目录
/// （城市下拉用）。所以断言一律只看 /pois/page 这一路，别把别处的请求算进来。
void main() {
  testWidgets('发现页一次只取 6 张卡片，滑到底才续下一页',
      (WidgetTester tester) async {
    final adapter = _feedAdapter();

    await _pump(tester, adapter);

    // 初始只取第一页，而且只取一次 —— 首页不再一次性拉整份目录。
    expect(_feedRequests(adapter, 'page'), <Object?>[1]);
    expect(_feedRequests(adapter, 'size'), <Object?>[6]);

    await _scrollToBottom(tester);
    expect(_feedRequests(adapter, 'page'), <Object?>[1, 2]);

    // 第二页就是最后一页，再滑也不该有新请求。
    await _scrollToBottom(tester);
    expect(_feedRequests(adapter, 'page'), <Object?>[1, 2]);
    expect(find.text('已经到底了 · 共 12 个景点'), findsOneWidget);
  });

  testWidgets('切回发现页时，信息流回到初始态', (WidgetTester tester) async {
    final adapter = _feedAdapter();

    await _pump(tester, adapter);
    await _scrollToBottom(tester);
    expect(_feedRequests(adapter, 'page'), <Object?>[1, 2]);

    await _selectTab(tester, Icons.route_outlined);
    await _selectTab(tester, Icons.explore_outlined);

    // 重新从第一页开始，而不是接着上次的第 3 页。
    expect(_feedRequests(adapter, 'page'), <Object?>[1, 2, 1]);
  });

  testWidgets('查看更多打开完整列表，并且用自己的一套分页',
      (WidgetTester tester) async {
    final adapter = _feedAdapter();

    await _pump(tester, adapter);
    await _scrollTo(tester, find.text('查看更多'));
    await tester.tap(find.text('查看更多'));
    await tester.pumpAndSettle();

    expect(find.text('河南景点'), findsOneWidget);

    // 首页 6 条一页，完整列表 12 条一页，并且自己从第一页开始 ——
    // 首页那份列表加载到哪儿，与它无关。
    final RequestOptions last = adapter.requests.lastWhere(
      (RequestOptions options) => options.path == '/pois/page',
    );
    expect(last.queryParameters['size'], 12);
    expect(last.queryParameters['page'], 1);
  });
}

RecordingAdapter _feedAdapter() => RecordingAdapter((options, _) async {
      if (options.path == '/pois') {
        // 行程页自己取的那一份完整目录，与首页分页无关。
        return jsonBody(<Object>[]);
      }
      expect(options.path, '/pois/page');
      return jsonBody(_page(int.parse('${options.queryParameters['page']}')));
    });

Future<void> _pump(WidgetTester tester, RecordingAdapter adapter) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(
          AppBootstrap(
            config: testConfig,
            sessionStore: SessionStore(storage: MemoryKeyValueStore()),
          ),
        ),
        travelRepositoryProvider.overrideWithValue(
          TravelRepository(
            client: ApiClient(dioWith(adapter)),
            config: testConfig,
          ),
        ),
      ],
      child: const YujianApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// 只看首页/完整列表这一路分页请求的参数。
List<Object?> _feedRequests(RecordingAdapter adapter, String key) => adapter
    .requests
    .where((RequestOptions options) => options.path == '/pois/page')
    .map((RequestOptions options) => options.queryParameters[key])
    .toList();

/// 一页 6 个，第二页之后就没有了 —— 正好够验证"续取"与"到底"两种状态。
Map<String, Object> _page(int page) => <String, Object>{
      'items': List<Object>.generate(6, (int index) {
        final int number = (page - 1) * 6 + index + 1;
        return <String, Object>{
          'id': 'poi-$number',
          'name': '景点 $number',
          'city': '洛阳',
          'category': '人文古迹',
          'imageUrl': '',
          'description': '第 $number 个景点的一句话介绍。',
          'ticketFrom': 60,
          'duration': '2小时',
          'dataStatus': '系统资料',
          'imageStatus': 'REGISTERED',
        };
      }),
      'page': page,
      'size': 6,
      'total': 12,
      'hasMore': page < 2,
    };

Future<void> _scrollToBottom(WidgetTester tester) async {
  for (int i = 0; i < 4; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
  }
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  for (int i = 0; i < 10 && target.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();
  }
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
