import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/app.dart';
import 'package:yujian_travel/app/bootstrap.dart';
import 'package:yujian_travel/app/providers.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/storage/session_store.dart';
import 'package:yujian_travel/core/widgets/app_back_button.dart';

import '../support/test_http.dart';

/// Layout regression guard for the three acceptance widths in
/// `docs/MOBILE_LAYOUT_SPEC.md`.
///
/// The bootstrap is overridden with an empty endpoint, so every read takes the
/// bundled demo branch: no network, no platform plugins, deterministic frames.
/// An overflowing RenderFlex is reported as a test exception, which is exactly
/// the failure this suite is meant to catch before it reaches a device.
///
/// The navigation is 发现 / 行程 / 我的. 规划 and 行程 were merged, so the journey
/// flow is: open the tab, fill nothing, generate, then open the evidence card.
void main() {
  const Map<String, Size> acceptanceWidths = <String, Size>{
    '360x800 compact baseline': Size(360, 800),
    '390x844 design reference': Size(390, 844),
    '412x915 wide check': Size(412, 915),
  };

  for (final MapEntry<String, Size> entry in acceptanceWidths.entries) {
    testWidgets('discover page has no overflow at ${entry.key}',
        (WidgetTester tester) async {
      await _pumpApp(tester, entry.value);
      expect(tester.takeException(), isNull);
      expect(find.text('豫见智旅'), findsOneWidget);
      expect(find.text('河南，让旅行更简单'), findsOneWidget);

      // Scroll the whole page so every sliver is laid out at least once.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'discover scrolled');
    });

    testWidgets('journey page has no overflow at ${entry.key}',
        (WidgetTester tester) async {
      await _pumpApp(tester, entry.value);

      await _selectTab(tester, Icons.route_outlined);
      // 行程页现在的默认状态是"我的行程"首页，它自己也要撑得住这三种宽度。
      expect(tester.takeException(), isNull, reason: 'journey hub overflowed');

      await tester.tap(find.text('新建一个行程').first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'journey form overflowed');

      await tester.ensureVisible(find.text('生成专属行程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成专属行程'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'journey result overflowed');

      // The result sits below the collapsed condition card; walk it so the day
      // cards, the budget card and the evidence card all get measured.
      await tester.drag(find.byType(ListView).first, const Offset(0, -2400));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'journey result scrolled');

      await tester.ensureVisible(find.text('方案依据'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('方案依据'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'evidence card overflowed');
    });

    testWidgets('profile and account pages have no overflow at ${entry.key}',
        (WidgetTester tester) async {
      await _pumpApp(tester, entry.value);

      await _selectTab(tester, Icons.person_outline);
      expect(tester.takeException(), isNull, reason: 'profile overflowed');

      await tester.tap(find.text('登录 / 注册'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'account page overflowed');

      // The register branch adds two fields inside an animated container.
      await tester.tap(find.text('注册'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'register mode overflowed');

      await tester.drag(find.byType(ListView).first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'account scrolled');
    });

    testWidgets('saved trip page has no overflow at ${entry.key}',
        (WidgetTester tester) async {
      await _pumpApp(tester, entry.value);

      await _selectTab(tester, Icons.route_outlined);
      expect(tester.takeException(), isNull, reason: 'journey hub overflowed');

      // 首页 → 历史行程（离线时是空状态页）这条路径也要撑住。
      await tester.tap(find.text('查看历史行程'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'trip history overflowed');
      // 行程页用的是产品自己的返回按钮（AppBackButton，tooltip 是「返回」），
      // 不是 Material 默认的 BackButton，所以 tester.pageBack() 找不到它。
      await tester.tap(find.byType(AppBackButton));
      await tester.pumpAndSettle();

      // 再从首页进表单生成一份，用表单顶部的入口回到同一页。
      await tester.tap(find.text('新建一个行程').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('生成专属行程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('生成专属行程'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'journey result overflowed');

      await tester.tap(find.byIcon(Icons.bookmarks_outlined).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'trip history overflowed');
    });
  }
}

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appBootstrapProvider.overrideWithValue(_offlineBootstrap()),
      ],
      child: const YujianApp(),
    ),
  );
  await tester.pumpAndSettle();
}

/// A bootstrap whose endpoint is intentionally empty, matching a release build
/// that was produced without `--dart-define=API_BASE_URL`.
AppBootstrap _offlineBootstrap() => AppBootstrap(
      config: const AppConfig(
        apiBaseUrl: '',
        connectTimeout: Duration(seconds: 1),
        receiveTimeout: Duration(seconds: 1),
        sendTimeout: Duration(seconds: 1),
      ),
      // The in-memory store keeps the suite off the platform keystore, which has
      // no implementation under `flutter test`.
      sessionStore: SessionStore(storage: MemoryKeyValueStore()),
    );

Future<void> _selectTab(WidgetTester tester, IconData icon) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.byIcon(icon),
    ),
  );
  await tester.pumpAndSettle();
}
