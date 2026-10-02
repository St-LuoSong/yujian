import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/data/repositories/travel_repository.dart';

import '../support/test_http.dart';

/// 附近景点这一路的仓库行为。
///
/// 两个重点：
/// 1. 坐标与半径要真的发到 `/pois/nearby` 上；
/// 2. 这条链路**不降级** —— 拿不到就报错，不能用缓存或演示数据假装"附近"。
void main() {
  TravelRepository repositoryWith(RecordingAdapter adapter) => TravelRepository(
        client: ApiClient(dioWith(adapter)),
        config: testConfig,
      );

  group('fetchNearby', () {
    test('把服务端的 items 解成景点与直线距离', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{
              'poi': <String, dynamic>{
                'id': 'poi-1',
                'name': '二七纪念塔',
                'city': '郑州',
                'category': '地标',
                'imageUrl': '',
                'description': '郑州的城市原点。',
                'ticketFrom': 0,
                'duration': '1小时',
                'dataStatus': '系统资料',
              },
              'distanceMeters': 420,
            },
          ],
          'radiusMeters': 3000,
          'coordinateSystem': '入参 WGS-84，服务端换算到 BD-09 后比较',
          'skippedWithoutCoordinate': 3,
          'dataStatus': '系统资料',
        }),
      );

      final result = await repositoryWith(adapter)
          .fetchNearby(lng: 113.6254, lat: 34.7466);

      expect(result.failure, isNull);
      expect(result.items, hasLength(1));
      expect(result.items.single.destination.name, '二七纪念塔');
      expect(result.items.single.distanceMeters, 420);
      expect(result.radiusMeters, 3000);
      expect(result.skippedWithoutCoordinate, 3);
    });

    test('坐标、半径与条数都发给了 /pois/nearby', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(<String, dynamic>{
          'items': <dynamic>[],
          'radiusMeters': 5000,
          'skippedWithoutCoordinate': 0,
        }),
      );

      await repositoryWith(adapter).fetchNearby(
        lng: 113.6254,
        lat: 34.7466,
        radius: 5000,
        limit: 5,
      );

      final request = adapter.requests.single;
      expect(request.path, '/pois/nearby');
      expect(request.queryParameters['lng'], 113.6254);
      expect(request.queryParameters['lat'], 34.7466);
      expect(request.queryParameters['radius'], 5000);
      expect(request.queryParameters['limit'], 5);
    });

    test('服务端出错时如实报错，不拿缓存或演示数据顶上', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(
          <String, dynamic>{
            'code': 'SERVICE_UNAVAILABLE',
            'message': '外部数据源不可用',
          },
          status: 503,
        ),
      );

      final result = await repositoryWith(adapter)
          .fetchNearby(lng: 113.6254, lat: 34.7466);

      expect(result.failure, isNotNull);
      expect(result.items, isEmpty);
    });

    test('单条记录结构不对时只丢掉那一条，其余照常返回', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(<String, dynamic>{
          'items': <dynamic>[
            <String, dynamic>{'distanceMeters': 100},
            <String, dynamic>{
              'poi': <String, dynamic>{'id': 'poi-2', 'name': '龙门石窟', 'city': '洛阳'},
              'distanceMeters': 900,
            },
          ],
          'radiusMeters': 3000,
          'skippedWithoutCoordinate': 0,
        }),
      );

      final result = await repositoryWith(adapter)
          .fetchNearby(lng: 112.45, lat: 34.62);

      expect(result.failure, isNull);
      expect(result.items, hasLength(1));
      expect(result.items.single.destination.name, '龙门石窟');
    });
  });

  group('fetchDestinations(city:)', () {
    test('城市作为查询参数发给 /pois', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(<dynamic>[]),
      );

      final result =
          await repositoryWith(adapter).fetchDestinations(city: '洛阳');

      expect(adapter.requests.single.path, '/pois');
      expect(adapter.requests.single.queryParameters['city'], '洛阳');
      // 某个城市没有收录景点是一个合法答案，不该被当成"读空了"而降级。
      expect(result.failure, isNull);
      expect(result.destinations, isEmpty);
    });

    test('空字符串按"没有指定城市"处理，不带参数', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(<dynamic>[
          <String, dynamic>{
            'id': 'poi-1',
            'name': '龙门石窟',
            'city': '洛阳',
            'category': '石窟',
            'imageUrl': '',
            'description': '世界文化遗产。',
            'ticketFrom': 90,
            'duration': '3小时',
            'dataStatus': '系统资料',
          },
        ]),
      );

      await repositoryWith(adapter).fetchDestinations(city: '   ');

      expect(
        adapter.requests.single.queryParameters.containsKey('city'),
        isFalse,
      );
    });

    test('拿不到网络时，按城市过滤本机内容也能成立', () async {
      final adapter = RecordingAdapter(
        (options, body) async => jsonBody(
          <String, dynamic>{'code': 'SERVICE_UNAVAILABLE', 'message': '不可用'},
          status: 503,
        ),
      );
      final repository = repositoryWith(adapter);

      final all = await repository.fetchDestinations();
      expect(all.destinations, isNotEmpty, reason: '本机演示目录不该是空的');

      final city = all.destinations.first.city;
      final filtered = await repository.fetchDestinations(city: city);

      expect(filtered.destinations, isNotEmpty);
      expect(
        filtered.destinations.every((item) => item.city.contains(city)),
        isTrue,
      );
      expect(
        filtered.destinations.length <= all.destinations.length,
        isTrue,
      );
      // 降级就是降级：这条路径必须把 failure 带出来，界面才能如实标注来源。
      expect(filtered.failure, isNotNull);
    });
  });
}
