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
}
