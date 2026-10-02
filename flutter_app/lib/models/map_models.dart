import 'dart:ui' show Offset;

import '../core/data_status.dart';

/// 行程地图的一次快照。
///
/// 服务端已经算好每个站点的像素坐标，客户端只负责画：这样投影公式只有一份实现
/// （Java 侧，可单元测试），APK 也不需要理解百度坐标系。
///
/// 对应后端 `MapModels.RouteMap`。
class RouteMapSnapshot {
  const RouteMapSnapshot({
    required this.tripId,
    required this.dayIndex,
    required this.dayLabel,
    required this.dayDate,
    required this.viewport,
    required this.imageUrl,
    required this.imageLifetimeSeconds,
    required this.markers,
    required this.polyline,
    required this.unplaced,
    required this.attribution,
    required this.status,
    required this.source,
    required this.fallback,
    this.queriedAt,
    this.expiresAt,
    this.message,
  });

  factory RouteMapSnapshot.fromJson(Map<String, dynamic> json) {
    final viewport = json['viewport'];
    return RouteMapSnapshot(
      tripId: _text(json['tripId']),
      dayIndex: _integer(json['dayIndex'], 1),
      dayLabel: _textOr(json['dayLabel'], ''),
      dayDate: _textOr(json['dayDate'], ''),
      viewport: viewport is Map
          ? RouteMapViewport.fromJson(viewport.cast<String, dynamic>())
          : null,
      imageUrl: _text(json['imageUrl']),
      imageLifetimeSeconds: _integer(json['imageLifetimeSeconds'], 0),
      markers: _list(json['markers']).map(RouteMapMarker.fromJson).toList(),
      polyline: _rawList(json['polyline'])
          .whereType<List<Object?>>()
          .where((List<Object?> entry) => entry.length >= 2)
          .map((List<Object?> entry) => Offset(
                _number(entry[0]),
                _number(entry[1]),
              ))
          .toList(),
      unplaced: _list(json['unplaced']).map(RouteMapUnplaced.fromJson).toList(),
      attribution: _strings(json['attribution']),
      status: DataStatus.fromServer(json['dataStatus']),
      source: _textOr(json['source'], '百度地图'),
      fallback: json['fallback'] == true,
      queriedAt: _time(json['queriedAt']),
      expiresAt: _time(json['expiresAt']),
      message: json['message']?.toString(),
    );
  }

  final String tripId;
  final int dayIndex;
  final String dayLabel;
  final String dayDate;
  final RouteMapViewport? viewport;

  /// 已经解析成这台设备可以访问的绝对地址；为空表示没有底图。
  final String imageUrl;
  final int imageLifetimeSeconds;
  final List<RouteMapMarker> markers;

  /// 按行程顺序连起来的折线，坐标与 [markers] 同一套像素体系。
  final List<Offset> polyline;
  final List<RouteMapUnplaced> unplaced;
  final List<String> attribution;
  final DataStatus status;
  final String source;

  /// true 表示服务端明确降级（没有 AK、取图失败、没有可信坐标），
  /// 界面必须换成文字路线，而不是留一块空白。
  final bool fallback;
  final String? message;
  final DateTime? queriedAt;
  final DateTime? expiresAt;

  bool get hasImage => imageUrl.isNotEmpty && viewport != null;
}

class RouteMapViewport {
  const RouteMapViewport({
    required this.centerLng,
    required this.centerLat,
    required this.zoom,
    required this.width,
    required this.height,
    required this.fitted,
  });

  factory RouteMapViewport.fromJson(Map<String, dynamic> json) => RouteMapViewport(
        centerLng: _number(json['centerLng']),
        centerLat: _number(json['centerLat']),
        zoom: _integer(json['zoom'], 12),
        width: _integer(json['width'], 1024),
        height: _integer(json['height'], 768),
        fitted: json['fitted'] == true,
      );

  final double centerLng;
  final double centerLat;
  final int zoom;
  final int width;
  final int height;

  /// true 表示这是服务端自动框选的全览视图，界面可以显示"回到全览"。
  final bool fitted;
}

class RouteMapMarker {
  const RouteMapMarker({
    required this.index,
    required this.title,
    required this.itemType,
    required this.time,
    required this.lng,
    required this.lat,
    required this.x,
    required this.y,
    required this.inside,
    required this.coordinateSource,
    required this.confidence,
  });

  factory RouteMapMarker.fromJson(Map<String, dynamic> json) => RouteMapMarker(
        index: _integer(json['index'], 0),
        title: _text(json['title']),
        itemType: _textOr(json['itemType'], ''),
        time: _textOr(json['time'], ''),
        lng: _number(json['lng']),
        lat: _number(json['lat']),
        x: _number(json['x']),
        y: _number(json['y']),
        inside: json['inside'] == true,
        coordinateSource: _textOr(json['coordinateSource'], '百度地图'),
        confidence: _integer(json['confidence'], 0),
      );

  final int index;
  final String title;
  final String itemType;
  final String time;
  final double lng;
  final double lat;
  final double x;
  final double y;

  /// 是否落在当前窗口内。用户在拖动或放大之后，部分点会跑到画面外。
  final bool inside;
  final String coordinateSource;
  final int confidence;
}

/// 没能可信定位的安排，连同原因一起展示，而不是悄悄丢掉。
class RouteMapUnplaced {
  const RouteMapUnplaced({required this.title, required this.reason});

  factory RouteMapUnplaced.fromJson(Map<String, dynamic> json) => RouteMapUnplaced(
        title: _text(json['title']),
        reason: _textOr(json['reason'], '未定位'),
      );

  final String title;
  final String reason;
}

/// 原样保留的列表，用于形状不固定的字段（例如折线是 [[x, y], ...]）。
List<Object?> _rawList(Object? value) => value is List ? value : const <Object?>[];

List<Map<String, dynamic>> _list(Object? value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value
      .whereType<Map>()
      .map((entry) => entry.cast<String, dynamic>())
      .toList();
}

List<String> _strings(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((entry) => entry.toString()).toList();
}

String _text(Object? value) => value?.toString() ?? '';

String _textOr(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

double _number(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

int _integer(Object? value, int fallback) {
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

DateTime? _time(Object? value) {
  final text = value?.toString() ?? '';
  return text.isEmpty ? null : DateTime.tryParse(text);
}
