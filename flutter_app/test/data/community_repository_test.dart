import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
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
    final repository = CommunityRepository(client: ApiClient(dioWith(adapter)));

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
    final repository = CommunityRepository(client: ApiClient(dioWith(adapter)));

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
    final repository = CommunityRepository(client: ApiClient(dioWith(adapter)));

    await repository.report('p1', '不实信息');

    expect(adapter.requests, hasLength(1));
  });
}

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
