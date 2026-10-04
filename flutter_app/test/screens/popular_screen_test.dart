import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/data/repositories/travel_repository.dart';
import 'package:yujian_travel/screens/popular_screen.dart';

import '../support/test_http.dart';

/// 「景区推荐」= 收藏榜。
///
/// 这一页存在的理由是"依据不同"：首页那条精选推荐是运营挑的，这条是游客自己
/// 攒的。所以测试只盯两件事 —— 榜单确实按收藏数显示，以及收藏为 0 时不许
/// 拿一颗空星冒充有人收藏过。
void main() {
  test('收藏榜走 /pois/popular，并把 favoriteCount 解析进模型', () async {
    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/pois/popular');
      expect(options.queryParameters['limit'], 10);
      return jsonBody(<Object>[
        _ranked('longmen', '龙门石窟', 7),
        _ranked('shaolin', '嵩山少林', 0),
      ]);
    });

    final CatalogResult result =
        await _repository(adapter).fetchPopularDestinations();

    expect(result.status, DataStatus.system);
    expect(result.destinations.first.name, '龙门石窟');
    expect(result.destinations.first.favoriteCount, 7);
    expect(result.destinations.last.favoriteCount, 0);
  });

  testWidgets('收藏榜按名次列出景点，0 收藏如实写"暂无收藏"',
      (WidgetTester tester) async {
    final RecordingAdapter adapter = RecordingAdapter(
      (options, _) async => jsonBody(<Object>[
        _ranked('longmen', '龙门石窟', 7),
        _ranked('shaolin', '嵩山少林', 0),
      ]),
    );
    bool browsed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: PopularScreen(
          repository: _repository(adapter),
          onBrowseAll: () => browsed = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    // 景点名会出现两次：一次是行标题，一次是缺图时的占位说明。
    expect(find.text('龙门石窟'), findsWidgets);
    expect(find.text('7 人收藏'), findsOneWidget);
    expect(find.text('暂无收藏'), findsOneWidget);

    await tester.tap(find.text('查看全部景点'));
    await tester.pumpAndSettle();
    expect(browsed, isTrue);
  });
}

TravelRepository _repository(RecordingAdapter adapter) => TravelRepository(
      client: ApiClient(dioWith(adapter)),
      config: testConfig,
    );

Map<String, Object> _ranked(String id, String name, int favoriteCount) =>
    <String, Object>{
      'poi': <String, Object>{
        'id': id,
        'name': name,
        'city': '洛阳',
        'category': '人文古迹',
        'imageUrl': '',
        'description': '一句话介绍。',
        'ticketFrom': 90,
        'duration': '3-4小时',
        'dataStatus': '系统资料',
        'imageStatus': 'REGISTERED',
      },
      'favoriteCount': favoriteCount,
    };
