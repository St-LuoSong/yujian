import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/screens/community_screen.dart';

import '../support/test_http.dart';

void main() {
  testWidgets('社区信息流显示旅记并进入详情', (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
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
    expect(find.text('河洛旅人'), findsOneWidget);

    await tester.tap(find.text('洛阳两日'));
    await tester.pumpAndSettle();

    expect(find.text('沿着伊河看石窟。'), findsWidgets);
    expect(find.text('旅记'), findsWidgets);
  });
}

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
