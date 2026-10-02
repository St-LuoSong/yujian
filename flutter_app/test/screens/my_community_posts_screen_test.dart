import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/screens/my_community_posts_screen.dart';

import '../support/test_http.dart';

void main() {
  testWidgets('我的旅记显示审核状态并进入作者详情', (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/community/posts/mine') {
        return jsonBody(<String, Object>{
          'items': <Object>[_postJson()],
          'page': 1,
          'size': 50,
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
        child: const MaterialApp(home: MyCommunityPostsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('审核中'), findsWidgets);
    expect(find.text('待审旅记'), findsOneWidget);

    await tester.tap(find.text('待审旅记'));
    await tester.pumpAndSettle();

    expect(find.text('审核状态：审核中'), findsOneWidget);
    expect(find.text('举报'), findsNothing);
  });
}

Map<String, Object?> _postJson() => <String, Object?>{
      'id': 'p1',
      'authorName': '河洛旅人',
      'authorAvatarKey': 'celadon',
      'title': '待审旅记',
      'content': '等待管理员审核。',
      'city': '洛阳',
      'tags': '历史文化',
      'imageUrls': <String>[],
      'likeCount': 0,
      'viewCount': 0,
      'likedByMe': false,
      'status': 'PENDING',
      'visibility': 'PUBLIC',
      'createdAt': '2026-10-02T10:00:00Z',
      'publishedAt': null,
      'moderationNote': null,
    };
