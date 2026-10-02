import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/core/widgets/data_status_legend.dart';

/// The legend is the only place that states how a plan was sourced, so it has to
/// survive the three acceptance widths and a 1.3x system font without
/// overflowing: a clipped provenance line is worse than no line at all.
void main() {
  const Map<String, Size> acceptanceWidths = <String, Size>{
    '360x800 compact baseline': Size(360, 800),
    '390x844 design reference': Size(390, 844),
    '412x915 wide check': Size(412, 915),
  };

  for (final MapEntry<String, Size> entry in acceptanceWidths.entries) {
    testWidgets('legend fits at ${entry.key}', (WidgetTester tester) async {
      await _pump(tester, entry.value);

      expect(tester.takeException(), isNull);
      expect(find.text('数据来源共 5 项'), findsOneWidget);
      // 实时 / 演示 / 降级各 1 项，系统资料 2 项。
      expect(find.text('1'), findsNWidgets(3));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('legend fits at ${entry.key} with 1.3x system text',
        (WidgetTester tester) async {
      await _pump(tester, entry.value, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.text('数据来源共 5 项'), findsOneWidget);
    });
  }

  testWidgets('an empty legend renders nothing instead of a orphan caption',
      (WidgetTester tester) async {
    await _pump(tester, const Size(390, 844), counts: const <DataStatus, int>{});

    expect(tester.takeException(), isNull);
    expect(find.textContaining('数据来源'), findsNothing);
  });
}

const Map<DataStatus, int> _mixed = <DataStatus, int>{
  DataStatus.realtime: 1,
  DataStatus.system: 2,
  DataStatus.mock: 1,
  DataStatus.degraded: 1,
};

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  double textScale = 1,
  Map<DataStatus, int> counts = _mixed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: DataStatusLegend(counts: counts, total: 5),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

