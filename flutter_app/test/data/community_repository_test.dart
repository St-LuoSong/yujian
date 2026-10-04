import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yujian_travel/core/config/app_config.dart';
import 'package:yujian_travel/core/network/api_client.dart';
import 'package:yujian_travel/data/repositories/community_repository.dart';
import 'package:yujian_travel/models/community_models.dart';

import '../support/test_http.dart';

void main() {
  test('feed sends filters and parses posts', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/community/posts');
      expect(options.queryParameters['city'], '洛阳');
      expect(options.queryParameters['tag'], '历史文化');
      expect(options.queryParameters['page'], 1);
      return jsonBody(<String, Object>{
        'items': <Object>[_postJson()],
        'page': 1,
        'size': 10,
        'total': 1,
        'hasMore': false,
      });
    });
    final repository = _repository(adapter);

    final CommunityPage page = await repository.fetchFeed(
      city: '洛阳',
      tag: '历史文化',
    );

    expect(page.items, hasLength(1));
    expect(page.items.single.title, '洛阳两日');
    expect(page.items.single.tags, <String>['历史文化', '博物馆']);
  });

  test('like and unlike use the post interaction endpoints', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/community/posts/p1/like');
      if (options.method == 'POST') {
        return jsonBody(<String, Object>{..._postJson(), 'likedByMe': true, 'likeCount': 8});
      }
      expect(options.method, 'DELETE');
      return jsonBody(<String, Object>{..._postJson(), 'likedByMe': false, 'likeCount': 7});
    });
    final repository = _repository(adapter);

    final CommunityPost liked = await repository.like('p1');
    final CommunityPost unliked = await repository.unlike('p1');

    expect(liked.likedByMe, isTrue);
    expect(liked.likeCount, 8);
    expect(unliked.likedByMe, isFalse);
    expect(unliked.likeCount, 7);
  });

  test('report posts the selected reason and accepts no content', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/community/posts/p1/report');
      expect(options.data, <String, Object?>{'reason': '不实信息'});
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });
    final repository = _repository(adapter);

    await repository.report('p1', '不实信息');

    expect(adapter.requests, hasLength(1));
  });

  test('my posts and deletion use the owner endpoints', () async {
    final adapter = RecordingAdapter((options, _) async {
      if (options.method == 'GET') {
        expect(options.path, '/community/posts/mine');
        expect(options.queryParameters['size'], 50);
        return jsonBody(<String, Object>{
          'items': <Object>[
            <String, Object>{..._postJson(), 'status': 'PENDING'},
          ],
          'page': 1,
          'size': 50,
          'total': 1,
          'hasMore': false,
        });
      }
      expect(options.method, 'DELETE');
      expect(options.path, '/community/posts/p1');
      return ResponseBody.fromString('', 204, headers: jsonHeaders);
    });
    final repository = _repository(adapter);

    final CommunityPage mine = await repository.fetchMine();
    await repository.deletePost('p1');

    expect(mine.items.single.status, 'PENDING');
    expect(adapter.requests, hasLength(2));
  });

  test('相对图片路径会被补成这台设备能访问的绝对地址', () async {
    final adapter = RecordingAdapter((options, _) async {
      return jsonBody(<String, Object>{
        'items': <Object>[
          <String, Object>{
            ..._postJson(),
            'imageUrls': <String>['/media/luoyang.jpg'],
          },
        ],
        'page': 1,
        'size': 10,
        'total': 1,
        'hasMore': false,
      });
    });

    final CommunityPage page = await _repository(adapter).fetchFeed();
    final String resolved = page.items.single.imageUrls.single;

    // 相对路径 /media/... 必须变成绝对地址，否则卡片只会显示占位图。
    expect(resolved, startsWith('https://'));
    expect(resolved, endsWith('/media/luoyang.jpg'));
    // 入库时要还原成相对路径，不能把本机地址写进数据库。
    expect(CommunityRepository.storageImageUrl(resolved), '/media/luoyang.jpg');
    expect(
      CommunityRepository.storageImageUrl('https://cdn.example.test/a.jpg'),
      'https://cdn.example.test/a.jpg',
    );
  });

  test('作者修改旅记走 PATCH 并回到待审核', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.method, 'PATCH');
      expect(options.path, '/community/posts/p1');
      expect(options.data, <String, Object?>{
        'title': '洛阳两日（改）',
        'content': '改过的正文。',
        'city': '洛阳',
        'tags': '历史文化',
        'visibility': 'PUBLIC',
        'tripPlanId': 'plan-1',
        'imageUrls': <String>['/media/a.jpg'],
      });
      return jsonBody(<String, Object?>{
        ..._postJson(),
        'title': '洛阳两日（改）',
        'status': 'PENDING',
        'publishedAt': null,
      });
    });

    final CommunityPost updated = await _repository(adapter).updatePost(
      id: 'p1',
      title: '洛阳两日（改）',
      content: '改过的正文。',
      city: '洛阳',
      tags: '历史文化',
      visibility: 'PUBLIC',
      tripPlanId: 'plan-1',
      imageUrls: <String>['/media/a.jpg'],
    );

    expect(updated.status, 'PENDING');
  });

  test('收藏与取消收藏走独立的 favorite 端点，并读取真实计数', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/community/posts/p1/favorite');
      if (options.method == 'POST') {
        return jsonBody(<String, Object>{
          ..._postJson(),
          'favoritedByMe': true,
          'favoriteCount': 1,
        });
      }
      return jsonBody(<String, Object>{
        ..._postJson(),
        'favoritedByMe': false,
        'favoriteCount': 0,
      });
    });
    final repository = _repository(adapter);

    final CommunityPost saved = await repository.favorite('p1');
    expect(saved.favoritedByMe, isTrue);
    expect(saved.favoriteCount, 1);

    final CommunityPost removed = await repository.unfavorite('p1');
    expect(removed.favoritedByMe, isFalse);
    expect(removed.favoriteCount, 0);
  });

  test('我收藏的旅记走 /community/posts/favorites', () async {
    final adapter = RecordingAdapter((options, _) async {
      expect(options.path, '/community/posts/favorites');
      expect(options.queryParameters['page'], 1);
      return jsonBody(<String, Object>{
        'items': <Object>[_postJson()],
        'page': 1,
        'size': 20,
        'total': 1,
        'hasMore': false,
      });
    });

    final CommunityPage page = await _repository(adapter).fetchFavorites();

    expect(page.items, hasLength(1));
  });
}

CommunityRepository _repository(RecordingAdapter adapter) =>
    CommunityRepository(
      client: ApiClient(dioWith(adapter)),
      config: const AppConfig(
        apiBaseUrl: testBaseUrl,
        connectTimeout: Duration(seconds: 1),
        receiveTimeout: Duration(seconds: 1),
        sendTimeout: Duration(seconds: 1),
      ),
    );

Map<String, Object> _postJson() => <String, Object>{
      'id': 'p1',
      'authorName': '河洛旅人',
      'authorAvatarKey': 'celadon',
      'title': '洛阳两日',
      'content': '沿着伊河看石窟。',
      'city': '洛阳',
      'tags': '历史文化,博物馆',
      'imageUrls': <String>[],
      'likeCount': 7,
      'viewCount': 30,
      'likedByMe': false,
      'status': 'APPROVED',
      'visibility': 'PUBLIC',
      'createdAt': '2026-10-02T10:00:00Z',
      'publishedAt': '2026-10-02T10:00:00Z',
    };
