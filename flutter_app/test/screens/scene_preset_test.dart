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

/// 首页"从一个场景开始"是一个**功能**，不是四个装饰标签。
///
/// 点"山水秘境"之后：目的地要从默认的洛阳变成焦作，并且表单上方说清楚
/// "这些条件是按哪个场景填的" —— 否则用户看到字段被改了，只会以为自己点错。
void main() {
  testWidgets('点场景标签会把目的地等条件填进表单，并说明来源',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final RecordingAdapter adapter = RecordingAdapter((options, _) async {
      if (options.path == '/home') {
        return jsonBody(<String, Object>{});
      }
      if (options.path == '/pois/page') {
        return jsonBody(<String, Object>{
          'items': <Object>[],
          'page': 1,
          'size': 6,
          'total': 0,
          'hasMore': false,
        });
      }
      return jsonBody(<Object>[]);
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

    final Finder scene = find.text('山水秘境');
    await tester.ensureVisible(scene);
    await tester.pumpAndSettle();
    await tester.tap(scene);
    await tester.pumpAndSettle();

    expect(
      find.text('已按「山水秘境」填好条件，可以直接生成，也可以改。'),
      findsOneWidget,
    );
    // 目的地被场景改成了焦作（表单默认是洛阳）。
    expect(find.text('焦作'), findsWidgets);
    // 兴趣按场景换成自然风光。
    expect(find.text('自然风光'), findsWidgets);
  });
}
