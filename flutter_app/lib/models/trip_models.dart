import '../core/data_status.dart';
import 'travel_models.dart';

/// Row shown on the "我的行程" list.
///
/// Mirrors `TripPlanModels.Summary`.
class TripSummary {
  const TripSummary({
    required this.id,
    required this.title,
    required this.summary,
    required this.corridor,
    required this.intensity,
    required this.totalCost,
    required this.perPersonCost,
    required this.daysCount,
    required this.status,
    this.updatedAt,
  });

  factory TripSummary.fromJson(Map<String, dynamic> json) => TripSummary(
        id: _text(json['id']),
        title: _textOr(json['title'], '河南旅行方案'),
        summary: _text(json['summary']),
        corridor: _textOr(json['corridor'], '河南'),
        intensity: _textOr(json['intensity'], '适中'),
        totalCost: _integer(json['totalCost']),
        perPersonCost: _integer(json['perPersonCost']),
        daysCount: _integer(json['daysCount']),
        status: DataStatus.fromServer(json['dataStatus']),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      );

  /// Builds a summary from a cached full plan when the list endpoint is not
  /// reachable, so an offline user still sees the most recent trip.
  factory TripSummary.fromPlan(TravelPlan plan, {required DataStatus status}) =>
      TripSummary(
        id: plan.id ?? '',
        title: plan.title,
        summary: plan.statusDetail ?? '',
        corridor: plan.corridor,
        intensity: plan.intensity,
        totalCost: plan.totalCost,
        perPersonCost: plan.perPerson,
        daysCount: plan.days.length,
        status: status,
      );

  final String id, title, summary, corridor, intensity;
  final int totalCost, perPersonCost, daysCount;
  final DataStatus status;
  final DateTime? updatedAt;
}

/// "你的足迹"统计。
///
/// Mirrors `TripPlanModels.Footprint`. 每个数字都来自服务端对落库行程的聚合：
/// 里程只累计行程项里真的带了距离的那些，所以界面上必须写"已记录里程"。
class TripFootprint {
  const TripFootprint({
    required this.cities,
    required this.totalMeters,
    required this.totalDays,
    required this.tripCount,
  });

  factory TripFootprint.fromJson(Map<String, dynamic> json) => TripFootprint(
        cities: _mapList(json['cities']).map(CityVisit.fromJson).toList(),
        totalMeters: _integer(json['totalMeters']),
        totalDays: _integer(json['totalDays']),
        tripCount: _integer(json['tripCount']),
      );

  /// 离线或未登录时用的空足迹。数字类的东西宁可空着，也不给一份编出来的统计。
  static const TripFootprint empty = TripFootprint(
    cities: <CityVisit>[],
    totalMeters: 0,
    totalDays: 0,
    tripCount: 0,
  );

  /// 去过的城市，最近到访的排在最前。
  final List<CityVisit> cities;

  /// 已记录里程（米）。路线工具没给距离的行程项不计入。
  final int totalMeters;

  final int totalDays;
  final int tripCount;

  bool get isEmpty => tripCount == 0;

  /// 公里数，保留一位小数交给界面格式化。
  double get totalKm => totalMeters / 1000;
}

/// 足迹里的一个到访城市。
class CityVisit {
  const CityVisit({
    required this.name,
    required this.tripCount,
    this.firstVisitAt,
    this.lastVisitAt,
  });

  factory CityVisit.fromJson(Map<String, dynamic> json) => CityVisit(
        name: _text(json['name']),
        tripCount: _integer(json['tripCount']),
        firstVisitAt:
            DateTime.tryParse(json['firstVisitAt']?.toString() ?? ''),
        lastVisitAt: DateTime.tryParse(json['lastVisitAt']?.toString() ?? ''),
      );

  final String name;
  final int tripCount;
  final DateTime? firstVisitAt;
  final DateTime? lastVisitAt;
}

/// Result of a local adjustment request.
///
/// Mirrors `TripPlanModels.AdjustmentResult` on the server: the new plan, a
/// human readable list of what changed, and the version counter used for undo.
class AdjustmentResult {
  const AdjustmentResult({
    required this.plan,
    required this.changes,
    required this.version,
  });

  factory AdjustmentResult.fromJson(Map<String, dynamic> json) =>
      AdjustmentResult(
        plan: TravelPlan.fromJson(_map(json['plan'])),
        changes: _textList(json['changes']),
        version: _integer(json['version']),
      );

  final TravelPlan plan;

  /// What the adjustment engine actually changed, for the "改了什么" panel.
  final List<String> changes;

  final int version;
}

/// One external tool call recorded for a plan.
///
/// Mirrors `TripPlanModels.ToolTrace`.
class ToolTrace {
  const ToolTrace({
    required this.toolName,
    required this.source,
    required this.dataStatus,
    required this.success,
    this.outputSummary,
    this.errorCode,
    this.durationMs,
  });

  factory ToolTrace.fromJson(Map<String, dynamic> json) => ToolTrace(
        toolName: _text(json['toolName']),
        source: _text(json['source']),
        dataStatus: DataStatus.fromServer(json['dataStatus']),
        success: json['success'] == true,
        outputSummary: json['outputSummary']?.toString(),
        errorCode: json['errorCode']?.toString(),
        durationMs: json['durationMs'] is num
            ? (json['durationMs'] as num).toInt()
            : int.tryParse(json['durationMs']?.toString() ?? ''),
      );

  final String toolName;
  final String source;
  final DataStatus dataStatus;
  final bool success;
  final String? outputSummary;
  final String? errorCode;
  final int? durationMs;
}

/// Why a plan looks the way it does: which engine produced it, which prompt
/// version was used and which tools answered.
///
/// Mirrors `TripPlanModels.TraceResponse`.
class TraceInfo {
  const TraceInfo({
    required this.engine,
    required this.promptVersion,
    required this.dataStatus,
    required this.toolMockCount,
    required this.warnings,
    required this.invocations,
  });

  factory TraceInfo.fromJson(Map<String, dynamic> json) => TraceInfo(
        engine: _text(json['engine']),
        promptVersion: _text(json['promptVersion']),
        dataStatus: DataStatus.fromServer(json['dataStatus']),
        toolMockCount: _integer(json['toolMockCount']),
        warnings: _textList(json['warnings']),
        invocations:
            _mapList(json['toolInvocations']).map(ToolTrace.fromJson).toList(),
      );

  final String engine;
  final String promptVersion;
  final DataStatus dataStatus;

  /// How many of the recorded tool calls were served by the mock adapter.
  final int toolMockCount;

  final List<String> warnings;
  final List<ToolTrace> invocations;

  /// True when every recorded call came from the mock adapter, which means the
  /// plan must never be presented as live data.
  bool get isFullyMock =>
      invocations.isNotEmpty && toolMockCount >= invocations.length;

  /// Provenance mix of every recorded call, ordered from the most verified to
  /// the least. The order is fixed rather than sorted by count so the readout
  /// keeps a stable shape when a plan is regenerated or adjusted. Statuses with
  /// no calls are left out instead of being reported as zero.
  Map<DataStatus, int> get statusCounts {
    const List<DataStatus> ordered = <DataStatus>[
      DataStatus.realtime,
      DataStatus.cached,
      DataStatus.system,
      DataStatus.aiGenerated,
      DataStatus.mock,
      DataStatus.degraded,
      DataStatus.expired,
      DataStatus.unavailable,
    ];
    final Map<DataStatus, int> counts = <DataStatus, int>{};
    for (final DataStatus status in ordered) {
      final int count =
          invocations.where((ToolTrace trace) => trace.dataStatus == status).length;
      if (count > 0) {
        counts[status] = count;
      }
    }
    return counts;
  }
}

/// Read model for the "today" view.
///
/// Mirrors `TripPlanModels.TodayResponse`.
class TodayInfo {
  const TodayInfo({
    required this.tripId,
    required this.date,
    required this.nextStop,
    required this.arrival,
    required this.weather,
    required this.status,
    required this.remaining,
  });

  factory TodayInfo.fromJson(Map<String, dynamic> json) => TodayInfo(
        tripId: _text(json['tripId']),
        date: _textOr(json['date'], '今日'),
        nextStop: _textOr(json['nextStop'], '暂无安排'),
        arrival: _textOr(json['arrival'], '待定'),
        weather: _textOr(json['weather'], '天气数据暂不可用'),
        status: DataStatus.fromServer(json['status']),
        remaining:
            _mapList(json['remainingItems']).map(PlanStop.fromJson).toList(),
      );

  /// Mirrors the server's `today()` derivation for the offline case: the first
  /// day counts as today and no stop is treated as already visited.
  factory TodayInfo.fromPlan(TravelPlan plan, {required DataStatus status}) {
    final stopList =
        plan.days.isEmpty ? const <PlanStop>[] : plan.days.first.stops;
    return TodayInfo(
      tripId: plan.id ?? '',
      date: '今日',
      nextStop: stopList.isEmpty ? '暂无安排' : stopList.first.title,
      arrival: stopList.isEmpty ? '待定' : stopList.first.time,
      weather: '天气数据暂不可用',
      status: status,
      remaining: stopList,
    );
  }

  final String tripId, date, nextStop, arrival, weather;
  final DataStatus status;
  final List<PlanStop> remaining;
}

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((item) => item.cast<String, dynamic>())
      .toList();
}

String _text(Object? value) => value?.toString() ?? '';

String _textOr(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

List<String> _textList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList();
}

int _integer(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
