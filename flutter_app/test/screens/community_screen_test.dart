import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
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
    // 互动栏即便换行，真实数据与"待开放"标注都必须完整可见。
    expect(find.text('评论待开放'), findsOneWidget);
    expect(find.text('收藏待开放'), findsOneWidget);
    expect(find.textContaining('河洛旅人'), findsOneWidget);
  });

  testWidgets('社区信息流显示旅记并进入详情', (WidgetTester tester) async {
    final RecordingAdapter adapter = _feedAdapter();

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
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
    // 互动栏里点赞与浏览量是真实数据；评论和收藏如实标注待开放。
    expect(find.text('7'), findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(find.text('评论待开放'), findsOneWidget);
    expect(find.text('收藏待开放'), findsOneWidget);

    await tester.tap(find.text('洛阳两日'));
    await tester.pumpAndSettle();

    expect(find.text('沿着伊河看石窟。'), findsWidgets);
    expect(find.text('旅记'), findsWidgets);
  });
}

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

Map<String, Object> _postJson() => <String, Object>{
      'id': 'p1',
      'authorName': '河洛旅人',
      'authorAvatarKey': 'celadon',
      'title': '洛阳两日',
      'content': '沿着伊河看石窟。',
      'city': '洛阳',
      'tags': '历史文化,博物馆',
      'imageUrls': <String>[],
      'likeCount': 7,
      'viewCount': 30,
      'likedByMe': false,
      'status': 'APPROVED',
      'visibility': 'PUBLIC',
      'createdAt': '2026-10-02T10:00:00Z',
      'publishedAt': '2026-10-02T10:00:00Z',
    };
