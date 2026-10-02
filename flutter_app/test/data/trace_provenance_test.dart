import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/models/trip_models.dart';

/// The "依据" tab is the only place where the app states how a plan was
/// sourced, so the counting logic is pinned down here: a degraded tool must
/// never be counted as live, and the readout order must not depend on the order
/// in which the tools happened to answer.
void main() {
  test('a degraded tool status is simulated, not live', () {
    expect(DataStatus.fromServer('演示数据（降级）'), DataStatus.degraded);
    expect(DataStatus.fromServer('演示数据（降级）').isSimulated, isTrue);
    expect(DataStatus.fromServer('实时数据'), DataStatus.realtime);
    expect(DataStatus.fromServer('缓存数据'), DataStatus.cached);
    expect(DataStatus.fromServer('系统资料'), DataStatus.system);
    expect(DataStatus.fromServer('系统资料').isSimulated, isFalse);
  });

  test('the provenance readout groups calls in a fixed order', () {
    final info = _trace(<DataStatus>[
      DataStatus.degraded,
      DataStatus.system,
      DataStatus.realtime,
      DataStatus.system,
    ]);

    expect(
      info.statusCounts.keys.toList(),
      <DataStatus>[DataStatus.realtime, DataStatus.system, DataStatus.degraded],
    );
    expect(info.statusCounts.values.toList(), <int>[1, 2, 1]);
    expect(info.isFullyMock, isFalse);
  });

  test('an all-mock plan reports itself as fully mock', () {
    final info = _trace(<DataStatus>[DataStatus.mock, DataStatus.mock]);

    expect(info.isFullyMock, isTrue);
    expect(info.statusCounts, <DataStatus, int>{DataStatus.mock: 2});
  });

  test('a plan without recorded calls has an empty readout', () {
    expect(_trace(<DataStatus>[]).statusCounts, isEmpty);
  });
}

TraceInfo _trace(List<DataStatus> statuses) => TraceInfo(
      engine: 'mock-trip-factory',
      promptVersion: 'v1.0.0-tool-orchestration',
      dataStatus: DataStatus.mock,
      toolMockCount:
          statuses.where((DataStatus status) => status.isSimulated).length,
      warnings: const <String>[],
      invocations: <ToolTrace>[
        for (int index = 0; index < statuses.length; index++)
          ToolTrace(
            toolName: 'tool-$index',
            source: '测试来源',
            dataStatus: statuses[index],
            success: statuses[index] != DataStatus.degraded,
          ),
      ],
    );

