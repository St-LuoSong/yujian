import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/models/map_models.dart';

/// 服务端 `MapModels.RouteMap` 的解析契约。
///
/// 地图有两条必须同时成立的路径：正常返回时把底图、编号点和折线取出来；
/// 服务端明确降级时安静地变成文字路线。两者都不能在解析层抛异常，否则
/// 一次外部服务抖动就会把整个行程页带崩。
void main() {
  group('RouteMapSnapshot.fromJson', () {
    test('maps a routed day with markers, polyline and provenance', () {
      final snapshot = RouteMapSnapshot.fromJson(<String, dynamic>{
        'tripId': 'trip-1',
        'dayIndex': 2,
        'dayLabel': '第 2 天',
        'dayDate': '2026-10-03',
        'viewport': <String, dynamic>{
          'centerLng': 112.4543,
          'centerLat': 34.6197,
          'zoom': 13,
          'width': 1024,
          'height': 768,
          'fitted': true,
        },
        'imageUrl': '/api/map/image?center=112.4543,34.6197&zoom=13&ticket=abc',
        'imageLifetimeSeconds': 1800,
        'markers': <Object?>[
          <String, dynamic>{
            'index': 1,
            'title': '龙门石窟',
            'itemType': 'attraction',
            'time': '09:00',
            'lng': 112.4691,
            'lat': 34.5554,
            'x': 610.5,
            'y': 402.25,
            'inside': true,
            'coordinateSource': '景点库',
            'confidence': 100,
          },
          <String, dynamic>{
            'index': 2,
            'title': '洛阳博物馆',
            'itemType': 'attraction',
            'time': '14:30',
            'lng': 112.4342,
            'lat': 34.6358,
            'x': 480.0,
            'y': 180.75,
            'inside': false,
            'coordinateSource': '百度地图',
            'confidence': 25,
          },
        ],
        'polyline': <Object?>[
          <Object?>[610.5, 402.25],
          <Object?>[480.0, 180.75],
        ],
        'unplaced': <Object?>[
          <String, dynamic>{
            'title': '郑州出发前往洛阳',
            'reason': '移动类安排不参与打点',
          },
        ],
        'attribution': <Object?>['百度地图', '豫见智旅行程校验'],
        'dataStatus': '缓存数据',
        'source': '百度地图',
        'fallback': false,
        'queriedAt': '2026-10-01T12:00:00Z',
        'expiresAt': '2026-10-01T12:30:00Z',
      });

      expect(snapshot.tripId, 'trip-1');
      expect(snapshot.dayIndex, 2);
      expect(snapshot.dayLabel, '第 2 天');
      expect(snapshot.hasImage, isTrue);
      expect(snapshot.fallback, isFalse);
      expect(snapshot.status, DataStatus.cached);
      expect(snapshot.viewport?.zoom, 13);
      expect(snapshot.viewport?.fitted, isTrue);
      expect(snapshot.markers.length, 2);
      expect(snapshot.markers.first.title, '龙门石窟');
      expect(snapshot.markers.first.coordinateSource, '景点库');
      expect(snapshot.markers.first.confidence, 100);
      expect(snapshot.markers.last.inside, isFalse);
      expect(snapshot.polyline, <Offset>[const Offset(610.5, 402.25), const Offset(480, 180.75)]);
      expect(snapshot.unplaced.single.title, '郑州出发前往洛阳');
      expect(snapshot.attribution, contains('百度地图'));
      expect(snapshot.queriedAt, isNotNull);
    });

    test('a degraded snapshot turns into a textual route instead of throwing', () {
      final snapshot = RouteMapSnapshot.fromJson(<String, dynamic>{
        'tripId': 'trip-2',
        'dataStatus': '演示数据（降级）',
        'fallback': true,
        'message': '地图服务暂时不可用。',
      });

      expect(snapshot.hasImage, isFalse);
      expect(snapshot.viewport, isNull);
      expect(snapshot.fallback, isTrue);
      expect(snapshot.status, DataStatus.degraded);
      expect(snapshot.message, '地图服务暂时不可用。');
      expect(snapshot.markers, isEmpty);
      expect(snapshot.polyline, isEmpty);
      expect(snapshot.source, '百度地图');
    });

    test('malformed points and unknown statuses degrade per entry, not globally', () {
      final snapshot = RouteMapSnapshot.fromJson(<String, dynamic>{
        'viewport': <String, dynamic>{'centerLng': 113.6, 'centerLat': 34.7},
        'imageUrl': '/api/map/image?ticket=abc',
        'markers': <Object?>['not-a-marker', <String, dynamic>{'title': '开封府'}],
        'polyline': <Object?>[
          <Object?>[1.0],
          <Object?>[2.0, 3.0],
          'garbage',
        ],
        'dataStatus': '天知道',
      });

      expect(snapshot.markers.length, 1);
      expect(snapshot.markers.single.title, '开封府');
      expect(snapshot.markers.single.coordinateSource, '百度地图');
      expect(snapshot.polyline, <Offset>[const Offset(2, 3)]);
      expect(snapshot.viewport?.zoom, 12);
      expect(snapshot.viewport?.fitted, isFalse);
      expect(snapshot.status, DataStatus.unknown);
      expect(snapshot.imageLifetimeSeconds, 0);
      expect(snapshot.queriedAt, isNull);
    });
  });
}
