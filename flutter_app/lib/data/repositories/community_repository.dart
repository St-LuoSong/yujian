import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/network/api_client.dart';
import '../../models/community_models.dart';

/// Public community feed plus the interactions that require a signed-in user.
class CommunityRepository {
  CommunityRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  Future<CommunityPage> fetchFeed({
    String? city,
    String? tag,
    int page = 1,
    int size = 10,
  }) async {
    final data = await _client.getJsonObject(
      '/community/posts',
      query: <String, dynamic>{
        if (city != null && city.isNotEmpty) 'city': city,
        if (tag != null && tag.isNotEmpty) 'tag': tag,
        'page': page,
        'size': size,
      },
    );
    return CommunityPage.fromJson(data);
  }

  Future<CommunityPost> fetchDetail(String id) async {
    final data = await _client.getJsonObject('/community/posts/$id');
    return CommunityPost.fromJson(data);
  }

  Future<CommunityPost> createPost({
    required String title,
    required String content,
    required String city,
    required String tags,
    required String visibility,
    String? tripPlanId,
    required List<String> imageUrls,
  }) async {
    final data = await _client.postJsonObject(
      '/community/posts',
      body: <String, Object?>{
        'title': title,
        'content': content,
        'city': city,
        'tags': tags,
        'visibility': visibility,
        'tripPlanId': tripPlanId,
        'imageUrls': imageUrls,
      },
    );
    return CommunityPost.fromJson(data);
  }

  Future<CommunityPost> like(String id) async {
    final data = await _client.postJsonObject('/community/posts/$id/like');
    return CommunityPost.fromJson(data);
  }

  Future<CommunityPost> unlike(String id) async {
    final data = await _client.deleteJsonObject('/community/posts/$id/like');
    return CommunityPost.fromJson(data);
  }

  Future<void> report(String id, String reason) async {
    await _client.sendNoContent(
      () => _client.post<dynamic>(
        '/community/posts/$id/report',
        data: <String, Object?>{'reason': reason},
      ),
    );
  }

  Future<String> uploadImage(File file) async {
    final data = await _client.postMultipartJson(
      '/community/media/images',
      data: FormData.fromMap(<String, Object>{
        'file': await MultipartFile.fromFile(file.path),
      }),
    );
    return (data['relativeUrl'] ?? data['url'] ?? '').toString();
  }
}
