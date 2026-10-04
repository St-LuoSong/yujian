import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/models/community_models.dart';
import 'package:yujian_travel/screens/community_screen.dart';

import '../support/test_http.dart';

void main() {
  testWidgets('社区卡片在 360dp 与 1.3 倍字体下不溢出', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _bootstrap(),
          apiClientProvider.overrideWithValue(ApiClient(dioWith(_feedAdapter()))),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: const Scaffold(body: CommunityScreen()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 互动栏即便换行，四个真实计数都必须完整可见。
    expect(find.text('3'), findsOneWidget);
    // 收藏已经实现：显示真实计数，靠 tooltip 标注语义。
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.textContaining('河洛旅人'), findsOneWidget);
  });

  testWidgets('社区信息流显示旅记并进入详情', (WidgetTester tester) async {
    final RecordingAdapter adapter = _feedAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _bootstrap(),
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
        ],
        child: const MaterialApp(home: CommunityScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('洛阳两日'), findsOneWidget);
    // 作者信息栏在最上方：用户名与发布时间在同一行。
    expect(find.textContaining('河洛旅人'), findsOneWidget);
    expect(find.textContaining('·'), findsWidgets);
    // 互动栏里四个计数都是真实数据。
    expect(find.text('7'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);

    await tester.tap(find.text('洛阳两日'));
    await tester.pumpAndSettle();

    expect(find.text('沿着伊河看石窟。'), findsWidgets);
    expect(find.text('旅记'), findsWidgets);
  });

  testWidgets('详情页多图走宫格，互动栏在窄屏与大字体下不溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/community/posts/p1') {
        return jsonBody(_postJson(images: 6));
      }
      return jsonBody(<String, Object>{});
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _bootstrap(),
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
        ],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
            child: CommunityDetailScreen(
              initial: CommunityPost(
                id: 'p1',
                authorName: '河洛旅人',
                title: '洛阳两日',
                content: '沿着伊河看石窟。',
                city: '洛阳',
                tags: const <String>['历史文化', '博物馆'],
                imageUrls: List<String>.generate(6, (int i) => ''),
                likeCount: 7,
                viewCount: 30,
                likedByMe: false,
                status: 'APPROVED',
                visibility: 'PUBLIC',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 详情页的评论数来自评论区自己那一次请求：这条假适配器没有给评论，
    // 所以它必须是 0，而不是拿卡片上那份快照充数。
    expect(find.text('7'), findsOneWidget);
    expect(find.byTooltip('收藏'), findsOneWidget);
    expect(find.text('评论 0'), findsOneWidget);
    expect(find.text('还没有评论。说点什么，让后来的人少走一点弯路。'), findsOneWidget);
  });

  testWidgets('旅记详情展示真实评论，未登录只能读不能写', (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/community/posts/p1') {
        return jsonBody(_postJson());
      }
      if (options.path == '/community/posts/p1/comments') {
        return jsonBody(<String, Object>{
          'items': <Object>[
            <String, Object>{
              'id': 'c1',
              'postId': 'p1',
              'authorName': '少林客',
              'authorAvatarKey': 'ink',
              'content': '早上去龙门人少很多。',
              'mine': false,
              'createdAt': '2026-10-03T02:00:00Z',
            },
          ],
          'page': 1,
          'size': 20,
          'total': 1,
          'hasMore': false,
        });
      }
      return jsonBody(<String, Object>{});
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          _bootstrap(),
          apiClientProvider.overrideWithValue(ApiClient(dioWith(adapter))),
        ],
        child: MaterialApp(
          home: CommunityDetailScreen(
            initial: CommunityPost(
              id: 'p1',
              authorName: '河洛旅人',
              title: '洛阳两日',
              content: '沿着伊河看石窟。',
              city: '洛阳',
              tags: const <String>['历史文化'],
              imageUrls: const <String>[],
              likeCount: 7,
              viewCount: 30,
              likedByMe: false,
              status: 'APPROVED',
              visibility: 'PUBLIC',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 计数与列表都来自评论接口，而不是卡片上那份快照。
    expect(find.text('评论 1'), findsOneWidget);
    expect(find.text('少林客'), findsOneWidget);
    expect(find.text('早上去龙门人少很多。'), findsOneWidget);
    // 未登录时给的是入口，不是一个点了没反应的输入框。
    expect(find.text('登录后可以发表评论。'), findsOneWidget);
    expect(find.text('去登录'), findsOneWidget);
  });
}

/// 社区仓库现在同时依赖接口客户端与运行时配置，测试里把这两样都换成假的。
/// 会话状态也走这条链路，所以提前把平台启动对象喂进来。
Override _bootstrap() => appBootstrapProvider.overrideWithValue(
      AppBootstrap(
        config: testConfig,
        sessionStore: SessionStore(storage: MemoryKeyValueStore()),
      ),
    );

RecordingAdapter _feedAdapter() => RecordingAdapter((options, _) async {
      if (options.path == '/community/posts') {
        return jsonBody(<String, Object>{
          'items': <Object>[_postJson()],
          'page': 1,
          'size': 8,
          'total': 1,
          'hasMore': false,
        });
      }
      if (options.path == '/community/posts/p1') {
        return jsonBody(_postJson());
      }
      return jsonBody(<String, Object>{});
    });

Map<String, Object> _postJson({int images = 0}) => <String, Object>{
      'id': 'p1',
      'authorName': '河洛旅人',
      'authorAvatarKey': 'celadon',
      'title': '洛阳两日',
      'content': '沿着伊河看石窟。',
      'city': '洛阳',
      'tags': '历史文化,博物馆',
      'imageUrls': List<String>.generate(images, (int i) => ''),
      'likeCount': 7,
      'favoriteCount': 2,
      'commentCount': 3,
      'viewCount': 30,
      'likedByMe': false,
      'status': 'APPROVED',
      'visibility': 'PUBLIC',
      'createdAt': '2026-10-02T10:00:00Z',
      'publishedAt': '2026-10-02T10:00:00Z',
    };
