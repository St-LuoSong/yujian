import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/core/widgets/option_sheet.dart';
import 'package:yujian_travel/models/community_models.dart';
import 'package:yujian_travel/screens/community_publish_screen.dart';

import '../support/test_http.dart';

void main() {
  testWidgets('关联行程用主题化弹层选择，而不是 Material 下拉框',
      (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/trip-plans') {
        return jsonBody(<Object>[_tripJson()]);
      }
      return jsonBody(<Object>[]);
    });

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
        child: const MaterialApp(home: CommunityPublishScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // 收起态：没有任何 Material 下拉框，默认选中第一份行程。
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.text('洛阳两日游'), findsOneWidget);
    expect(find.textContaining('郑州—洛阳'), findsOneWidget);

    await tester.tap(find.text('洛阳两日游'));
    await tester.pumpAndSettle();

    // 展开态：同一套主题化选项，展开前后的值是同一个。
    expect(find.text('选择关联行程'), findsOneWidget);
    expect(find.byType(OptionTile), findsWidgets);
  });

  testWidgets('编辑模式带出原有内容并回到审核', (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/trip-plans') {
        return jsonBody(<Object>[_tripJson()]);
      }
      // 提交修改必须走 PATCH，而不是重新建一篇。
      expect(options.method, 'PATCH');
      expect(options.path, '/community/posts/p1');
      return jsonBody(<String, Object?>{
        'id': 'p1',
        'authorName': '河洛旅人',
        'title': '洛阳两日',
        'content': '沿着伊河看石窟。',
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
      });
    });

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
        child: MaterialApp(
          home: CommunityPublishScreen(editing: _editingPost()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('编辑旅记'), findsOneWidget);
    expect(find.text('洛阳两日'), findsOneWidget);
    expect(find.text('沿着伊河看石窟。'), findsOneWidget);

    // 表单比一屏长，提交按钮在懒加载列表的下方，先滚到它再点。
    await tester.scrollUntilVisible(
      find.text('提交审核'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('提交审核'));
    await tester.pumpAndSettle();

    // 提交后给出审核提示，并回到上一页。
    expect(find.text('修改已提交审核'), findsOneWidget);
  });
}

CommunityPost _editingPost() => const CommunityPost(
      id: 'p1',
      authorName: '河洛旅人',
      tripPlanId: 'plan-1',
      title: '洛阳两日',
      content: '沿着伊河看石窟。',
      city: '洛阳',
      tags: <String>['历史文化'],
      imageUrls: <String>[],
      likeCount: 0,
      viewCount: 0,
      likedByMe: false,
      status: 'APPROVED',
      visibility: 'PUBLIC',
    );

Map<String, Object> _tripJson() => <String, Object>{
      'id': 'plan-1',
      'title': '洛阳两日游',
      'summary': '沿着伊河读懂千年中原',
      'corridor': '郑州—洛阳',
      'intensity': '适中',
      'totalCost': 384,
      'perPersonCost': 192,
      'daysCount': 2,
      'dataStatus': '演示数据',
      'updatedAt': '2026-10-02T10:00:00Z',
    };
