import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/data_status.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/core/network/api_failure.dart';
import 'package:yujian_travel/data/repositories/travel_repository.dart';
import 'package:yujian_travel/models/travel_models.dart';

import '../support/test_http.dart';

/// Verifies the parts of the repository contract that are easy to get subtly
/// wrong: what is sent on the wire, how a failure is surfaced, and when the
/// bundled demo data is allowed to answer instead of the server.
void main() {
  test('adjust posts the instruction and maps the adjustment result', () async {
    final adapter = RecordingAdapter((options, body) async {
      expect(options.method, 'POST');
      expect(options.path, '/trip-plans/plan-1/adjust');
      expect(jsonDecode(body!), <String, Object>{'instruction': '第二天轻松一点'});
      return jsonBody(<String, Object>{
        'plan': _planJson(id: 'plan-1', intensity: '轻松'),
        'changes': <String>['移除“返程”以降低当日行程强度'],
        'version': 2,
      });
    });

    final result = await _repository(adapter).adjustTripPlan(
      planId: 'plan-1',
      instruction: '第二天轻松一点',
    );

    expect(result.version, 2);
    expect(result.changes, <String>['移除“返程”以降低当日行程强度']);
    expect(result.plan.id, 'plan-1');
    expect(result.plan.intensity, '轻松');
    expect(result.plan.isPersisted, isTrue);
    // The backend truncates 385/2 to 192; the client must not recompute 193.
    expect(result.plan.perPerson, 192);
  });

  test('undo posts to the undo endpoint without a body', () async {
    final adapter = RecordingAdapter((options, body) async {
      expect(options.method, 'POST');
      expect(options.path, '/trip-plans/plan-1/undo');
      return jsonBody(_planJson(id: 'plan-1'));
    });

    final restored = await _repository(adapter).undoTripPlan('plan-1');

    expect(restored.id, 'plan-1');
    expect(restored.title, '洛阳历史文化两日游');
  });

  test('trace maps engine, prompt version and tool provenance', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/trip-plans/plan-1/trace');
      return jsonBody(<String, Object>{
        'engine': 'mock-trip-factory',
        'promptVersion': 'v1.0.0-tool-orchestration',
        'dataStatus': '演示数据',
        'toolMockCount': 2,
        'warnings': <String>['门票信息请以官方渠道为准。'],
        'toolInvocations': <Object>[
          <String, Object>{
            'toolName': 'getWeather',
            'source': '天气 Mock',
            'dataStatus': '演示数据',
            'success': true,
            'durationMs': 3,
          },
          <String, Object>{
            'toolName': 'searchTrain',
            'source': '12306 适配层 Mock',
            'dataStatus': '演示数据',
            'success': false,
            'errorCode': 'TOOL_FAILED',
          },
        ],
      });
    });

    final trace = await _repository(adapter).fetchTrace('plan-1');

    expect(trace.engine, 'mock-trip-factory');
    expect(trace.promptVersion, 'v1.0.0-tool-orchestration');
    expect(trace.invocations, hasLength(2));
    expect(trace.invocations.first.dataStatus, DataStatus.mock);
    expect(trace.invocations.last.success, isFalse);
    expect(trace.invocations.last.errorCode, 'TOOL_FAILED');
    expect(trace.isFullyMock, isTrue);
  });

  test('a trial limit reaches the caller instead of degrading to demo data',
      () async {
    final adapter = RecordingAdapter((_, __) async => ResponseBody.fromString(
          jsonEncode(<String, Object>{
            'code': 'TRIAL_LIMIT_REACHED',
            'message': '当前体验额度已用完，登录后可继续保存和管理行程',
          }),
          429,
          headers: jsonHeaders,
        ));

    expect(
      () => _repository(adapter).createPlan(prompt: '两个人去洛阳'),
      throwsA(isA<ApiFailure>()
          .having((failure) => failure.isTrialLimit, 'isTrialLimit', isTrue)
          .having(
              (failure) => failure.kind, 'kind', ApiFailureKind.rateLimited)),
    );
  });

  test('an unreachable server degrades to bundled demo data and says so',
      () async {
    final adapter = RecordingAdapter((options, __) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    });

    final result = await _repository(adapter).createPlan(prompt: '两个人去洛阳');

    expect(result.isFallback, isTrue);
    expect(result.plan.status, DataStatus.mock);
    expect(result.plan.isPersisted, isFalse);
    expect(result.plan.statusDetail, isNotNull);
    expect(result.failure?.kind, ApiFailureKind.network);
  });

  test('the trip list maps the summaries the server returns', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.method, 'GET');
      expect(options.path, '/trip-plans');
      return jsonBody(<Object>[
        <String, Object>{
          'id': 'plan-1',
          'title': '洛阳历史文化两日游',
          'summary': '沿着伊河读懂千年中原',
          'corridor': '郑州—洛阳',
          'intensity': '适中',
          'totalCost': 385,
          'perPersonCost': 192,
          'daysCount': 2,
          'dataStatus': '演示数据',
          'updatedAt': '2026-10-01T10:00:00Z',
        },
      ]);
    });

    final list = await _repository(adapter).fetchTripPlans();

    expect(list.items, hasLength(1));
    expect(list.items.first.id, 'plan-1');
    expect(list.items.first.perPersonCost, 192);
    expect(list.items.first.daysCount, 2);
    expect(list.items.first.updatedAt, isNotNull);
    expect(list.status, DataStatus.system);
  });

  test('today maps the next stop and the remaining items', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/trip-plans/plan-1/today');
      return jsonBody(<String, Object>{
        'tripId': 'plan-1',
        'date': '今日',
        'nextStop': '龙门石窟',
        'arrival': '09:00',
        'weather': '晴 18—26℃',
        'status': '演示数据',
        'remainingItems': <Object>[
          <String, Object>{
            'type': '景点',
            'title': '龙门石窟',
            'time': '09:00',
            'cost': 90,
            'source': '系统景点库',
            'dataStatus': '演示数据',
          },
        ],
      });
    });

    final today = await _repository(adapter).fetchToday('plan-1');

    expect(today.tripId, 'plan-1');
    expect(today.nextStop, '龙门石窟');
    expect(today.arrival, '09:00');
    expect(today.weather, '晴 18—26℃');
    expect(today.remaining, hasLength(1));
    expect(today.remaining.first.title, '龙门石窟');
    expect(today.status, DataStatus.mock);
  });

  test('an empty trip list stays empty instead of inventing a trip', () async {
    final adapter = RecordingAdapter((_, __) async => jsonBody(<Object>[]));

    final list = await _repository(adapter).fetchTripPlans();

    expect(list.isEmpty, isTrue);
    expect(list.items, isEmpty);
    expect(list.status, DataStatus.system);
  });

  test('creating a share link sends the visibility settings', () async {
    final adapter = RecordingAdapter((options, body) async {
      expect(options.method, 'POST');
      expect(options.path, '/trip-plans/plan-1/share');
      expect(
        jsonDecode(body!),
        <String, Object>{'hideBudget': true, 'expireDays': 7},
      );
      return jsonBody(<String, Object>{
        'id': 'share-1',
        'token': 'tok-1',
        'url': 'https://example.test/share/tok-1',
        'expiresAt': '2026-10-08T10:00:00Z',
        'hideBudget': true,
      });
    });

    final link = await _repository(adapter).createShareLink(planId: 'plan-1');

    expect(link.id, 'share-1');
    expect(link.token, 'tok-1');
    expect(link.url, 'https://example.test/share/tok-1');
    expect(link.hideBudget, isTrue);
    expect(link.expiresAt, isNotNull);
  });

  test('attraction payload carries the image credit the operator recorded',
      () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/pois');
      return jsonBody(<Object>[
        <String, Object>{
          'id': 'longmen',
          'name': '龙门石窟',
          'city': '洛阳',
          'category': '人文古迹',
          'imageUrl': 'https://cdn.example.test/longmen.jpg',
          'description': '一壁看尽千年风物，石刻造像沿伊河两岸铺展。',
          'ticketFrom': 90,
          'duration': '3—4小时',
          'suitability': '历史文化爱好者',
          'weatherTip': '雨天仍可游览，建议穿舒适防滑鞋。',
          'dataStatus': '系统资料',
          'imageCredit': '豫见智旅运营台 · 已授权实景图',
          'sourceUrl': 'https://www.lmsk.gov.cn/',
          'imageStatus': 'REGISTERED',
        },
      ]);
    });

    final result = await _repository(adapter).fetchDestinations();
    final Destination poi = result.destinations.single;

    // 图片来源要一路传到详情页：后台登记了出处，客户端就不能说不出来。
    expect(poi.imageCredit, '豫见智旅运营台 · 已授权实景图');
    expect(poi.sourceUrl, 'https://www.lmsk.gov.cn/');
    // 已登记授权的实景图不该在页面上贴任何"配图有问题"的标签。
    expect(poi.imageStatus, Destination.statusRegistered);
    expect(poi.imageNotice, isEmpty);
  });

  test('a placeholder photo tells the traveller it is not a real Henan photo',
      () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/pois');
      return jsonBody(<Object>[
        <String, Object>{
          'id': 'longmen',
          'name': '龙门石窟',
          'city': '洛阳',
          'category': '人文古迹',
          'imageUrl': 'https://images.unsplash.com/photo-1548013146?w=1200',
          'description': '一壁看尽千年风物。',
          'ticketFrom': 90,
          'duration': '3—4小时',
          'dataStatus': '演示数据',
          'imageCredit': '占位示例图（Unsplash）',
          'imageStatus': 'PLACEHOLDER',
        },
      ]);
    });

    final result = await _repository(adapter).fetchDestinations();
    final Destination poi = result.destinations.single;

    expect(poi.imageStatus, Destination.statusPlaceholder);
    // 状态判断来自服务端；客户端只负责把话说清楚，不自己编结论。
    expect(poi.imageNotice, contains('非河南实景'));
    expect(poi.showsImageSourceSection, isTrue);
  });

  test('the discover feed asks for one page at a time and maps hasMore',
      () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.method, 'GET');
      expect(options.path, '/pois/page');
      expect(options.queryParameters, <String, Object>{'page': 2, 'size': 6});
      return jsonBody(<String, Object>{
        'items': <Object>[
          <String, Object>{
            'id': 'longmen',
            'name': '龙门石窟',
            'city': '洛阳',
            'category': '人文古迹',
            'imageUrl': 'https://cdn.example.test/longmen.jpg',
            'description': '一壁看尽千年风物。',
            'ticketFrom': 90,
            'duration': '3—4小时',
            'dataStatus': '系统资料',
            'imageStatus': 'REGISTERED',
          },
        ],
        'page': 2,
        'size': 6,
        'total': 9,
        'hasMore': true,
      });
    });

    final result = await _repository(adapter).fetchDestinationPage(page: 2);

    expect(result.page, 2);
    expect(result.total, 9);
    // hasMore 由服务端给，客户端不去拿 page × size 和 total 自己推 ——
    // 这个测试就是钉住这一点。
    expect(result.hasMore, isTrue);
    expect(result.status, DataStatus.system);
    expect(result.destinations.single.name, '龙门石窟');
  });

  test('offline, the feed still pages through the bundled catalogue',
      () async {
    final adapter = RecordingAdapter((options, __) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'no route to host',
      );
    });
    final repository = _repository(adapter);

    final page1 = await repository.fetchDestinationPage(page: 1, size: 2);
    final page2 = await repository.fetchDestinationPage(page: 2, size: 2);

    // 断网时不能说"实时"，但也不能给一个空白页：降级到本地演示内容并如实标注。
    expect(page1.status, DataStatus.mock);
    expect(page1.destinations, hasLength(2));
    expect(page1.hasMore, isTrue);
    expect(page2.destinations, hasLength(2));
    expect(page2.hasMore, isFalse);
  });

  test('renaming a plan patches the trimmed title and nothing else', () async {
    final adapter = RecordingAdapter((options, body) async {
      expect(options.method, 'PATCH');
      expect(options.path, '/trip-plans/plan-1');
      expect(jsonDecode(body!), <String, Object>{'title': '洛阳慢游'});
      return jsonBody(_planJson(id: 'plan-1'));
    });

    await _repository(adapter).renameTripPlan(
      planId: 'plan-1',
      title: '  洛阳慢游  ',
    );

    expect(adapter.requests, hasLength(1));
  });

  test('a blank rename never reaches the server', () async {
    final adapter = RecordingAdapter((_, __) async {
      throw StateError('空标题不应该发请求');
    });

    expect(
      () => _repository(adapter).renameTripPlan(planId: 'plan-1', title: '   '),
      throwsA(
        isA<ApiFailure>()
            .having((ApiFailure f) => f.kind, 'kind', ApiFailureKind.validation)
            .having((ApiFailure f) => f.message, 'message', '行程名称不能为空。'),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('deleting a plan targets the plan id and accepts 204', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.method, 'DELETE');
      expect(options.path, '/trip-plans/plan-1');
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });

    await _repository(adapter).deleteTripPlan('plan-1');

    expect(adapter.requests, hasLength(1));
  });

  test('revoking a share link targets the share id', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.method, 'DELETE');
      expect(options.path, '/trip-shares/share-1');
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });

    await _repository(adapter).revokeShareLink('share-1');

    expect(adapter.requests, hasLength(1));
  });
}

const Map<String, List<String>> jsonHeaders = <String, List<String>>{
  Headers.contentTypeHeader: <String>[Headers.jsonContentType],
};

TravelRepository _repository(HttpClientAdapter adapter) => TravelRepository(
      client: ApiClient(dioWith(adapter)),
      config: testConfig,
    );

Map<String, Object> _planJson({required String id, String intensity = '适中'}) =>
    <String, Object>{
      'id': id,
      'title': '洛阳历史文化两日游',
      'corridor': '郑州—洛阳',
      'intensity': intensity,
      'totalCost': 385,
      'perPersonCost': 192,
      'dataStatus': '演示数据',
      'warnings': <String>['门票信息请以官方渠道为准。'],
      'days': <Object>[
        <String, Object>{
          'label': 'DAY 01',
          'date': '古都与石窟',
          'items': <Object>[
            <String, Object>{
              'type': '景点',
              'title': '龙门石窟',
              'time': '09:00',
              'duration': '约3小时',
              'transport': '公共交通',
              'description': '高铁站 → 景区约45分钟',
              'cost': 90,
              'source': '系统景点库',
              'dataStatus': '演示数据',
              'risk': '建议提前预约',
            },
          ],
        },
      ],
    };

ResponseBody jsonBody(Object value) => ResponseBody.fromString(
      jsonEncode(value),
      200,
      headers: jsonHeaders,
    );
