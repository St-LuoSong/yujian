import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/core/widgets/route_gauge.dart';
import 'package:yujian_travel/models/travel_models.dart';
import 'package:yujian_travel/screens/journey/day_card.dart';

void main() {
  testWidgets('手机窄屏与大字体下长来源和状态标签不横向溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: DayCard(
              day: PlanDay(
                'DAY 01',
                '2026-10-04',
                <PlanStop>[
                  PlanStop(
                    '08:06',
                    '郑州东站乘高铁前往洛阳龙门站',
                    '交通',
                    '请以铁路官方渠道为准。',
                    237,
                    source: '12306 MCP（2026-10-04 官方车次、余票、票价）',
                    dataStatus: DataStatus.degraded,
                    duration: '约43分钟',
                    transport: '高铁',
                    risk: '演示数据风险：请以官方渠道为准。',
                  ),
                ],
              ),
              index: 0,
              city: '洛阳',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('今日行程的元信息在窄屏长来源下不横向溢出',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: RouteGauge(
                planStatus: DataStatus.degraded,
                stops: <PlanStop>[
                  PlanStop(
                    '08:06',
                    '郑州东站乘高铁前往洛阳龙门站',
                    '交通',
                    '请以铁路官方渠道为准。',
                    237,
                    source: '12306 MCP（2026-10-04 官方车次、余票、票价）',
                    dataStatus: DataStatus.degraded,
                    duration: '约43分钟',
                    transport: '高铁',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
