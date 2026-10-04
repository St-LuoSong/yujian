import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/app/session_providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/models/account_models.dart';
import 'package:yujian_travel/screens/additional_screens.dart';
import 'package:yujian_travel/screens/profile_screens.dart';

import '../support/test_http.dart';

/// 收藏总站的回归点只有一个：**每一条都能点进去**。
///
/// 改造之前的收藏页是一列静态文字，点上去什么也不会发生 —— 用户报的就是这个。
/// 所以这里断言的是"点了之后真的到了景点详情"，而不是"渲染出了哪些文字"：
/// 文字断言在静态列表上也全都能过，等于没测。
void main() {
  testWidgets('景区收藏点一条就进景点详情', (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/favorites') {
        return jsonBody(<Object>[
          <String, Object>{
            'id': 'f1',
            'poiId': 'longmen',
            'poiName': '龙门石窟',
            'city': '洛阳',
          },
        ]);
      }
      if (options.path == '/pois') {
        return jsonBody(<Object>[_destinationJson()]);
      }
      throw StateError('unexpected request ${options.path}');
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(
            AppBootstrap(
              config: testConfig,
              sessionStore: SessionStore(storage: MemoryKeyValueStore()),
            ),
          ),
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
          // 收藏是跟着账号走的，所以总站只对已登录用户展出内容。
          sessionProvider.overrideWith(_SignedInSession.new),
        ],
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 名称会出现两次：卡片标题一次，图片占位图的说明文字一次。
    expect(find.text('龙门石窟'), findsWidgets);
    expect(find.text('查看景点详情'), findsOneWidget);

    await tester.tap(find.text('查看景点详情'));
    await tester.pumpAndSettle();

    expect(find.byType(DestinationDetail), findsOneWidget);
    expect(find.text('门票参考'), findsOneWidget);
  });

  testWidgets('未登录时三个板块都只给一个登录入口', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appBootstrapProvider.overrideWithValue(
            AppBootstrap(
              config: testConfig,
              sessionStore: SessionStore(storage: MemoryKeyValueStore()),
            ),
          ),
          apiClientProvider.overrideWithValue(
            ApiClient(
              dioWith(
                RecordingAdapter(
                  (_, __) async => throw StateError('未登录不该发请求'),
                ),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: FavoritesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('登录后查看收藏'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);

    await tester.tap(find.text('行程'));
    await tester.pumpAndSettle();

    // 换板块不改变结论：还是同一个入口，而不是三个空列表。
    expect(find.text('登录后查看收藏'), findsOneWidget);
  });
}

class _SignedInSession extends SessionController {
  @override
  Future<UserProfile?> build() async => const UserProfile(
        id: 'u1',
        username: 'traveler',
        email: 'traveler@example.com',
        emailVerified: false,
        roles: <String>['USER'],
      );
}

/// 只给详情页需要的最小字段；imageUrl 留空，测试里不去碰网络图片。
Map<String, Object?> _destinationJson() => <String, Object?>{
      'id': 'longmen',
      'name': '龙门石窟',
      'city': '洛阳',
      'category': '历史文化',
      'imageUrl': '',
      'description': '伊河两岸的千年石刻。',
      'ticketFrom': 90,
      'duration': '3 小时',
      'suitability': '历史文化爱好者',
      'weatherTip': '夏季注意防晒。',
      'dataStatus': 'SYSTEM',
    };
