import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/app_config.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_failure.dart';
import '../../models/community_models.dart';

/// Public community feed plus the interactions that require a signed-in user.
class CommunityRepository {
  CommunityRepository({required ApiClient client, required AppConfig config})
      : _client = client,
        _config = config;

  final ApiClient _client;
  final AppConfig _config;

  /// 服务端存的是 `/media/...` 相对路径，这里补成这台设备能访问的绝对地址。
  ///
  /// 数据库里不能写某台设备的 IP：模拟器是 10.0.2.2、真机是局域网地址，
  /// 一旦写进去，别人的手机就打不开这些图。
  CommunityPost _resolve(CommunityPost post) => post.copyWith(
        imageUrls: post.imageUrls.map(_config.resolveMediaUrl).toList(),
        authorAvatarUrl: post.authorAvatarUrl == null
            ? null
            : _config.resolveMediaUrl(post.authorAvatarUrl!),
      );

  /// 头像和配图走同一条规则：库里存 `/media/...`，显示前补成这台设备能访问的地址。
  CommunityComment _resolveComment(CommunityComment comment) =>
      comment.authorAvatarUrl == null || comment.authorAvatarUrl!.isEmpty
          ? comment
          : comment.copyWith(
              authorAvatarUrl: _config.resolveMediaUrl(comment.authorAvatarUrl!),
            );

  /// 把绝对地址还原成入库用的相对路径；只对本站 `/media/` 图片生效。
  static String storageImageUrl(String raw) {
    final Uri? uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme && uri.path.startsWith('/media/')) {
      return uri.path;
    }
    return raw;
  }

  /// 给刚上传、还没入库的图片做本页预览。
  String mediaUrl(String raw) => _config.resolveMediaUrl(raw);

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
    return CommunityPage.fromJson(data).mapItems(_resolve);
  }

  Future<CommunityPost> fetchDetail(String id) async {
    final data = await _client.getJsonObject('/community/posts/$id');
    return _resolve(CommunityPost.fromJson(data));
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
    return _resolve(CommunityPost.fromJson(data));
  }

  Future<CommunityPost> updatePost({
    required String id,
    required String title,
    required String content,
    required String city,
    required String tags,
    required String visibility,
    String? tripPlanId,
    required List<String> imageUrls,
  }) async {
    final data = await _client.patchJsonObject(
      '/community/posts/$id',
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
    return _resolve(CommunityPost.fromJson(data));
  }

  Future<CommunityPage> fetchMine() async {
    final data = await _client.getJsonObject(
      '/community/posts/mine',
      query: <String, dynamic>{'page': 1, 'size': 50},
    );
    return CommunityPage.fromJson(data).mapItems(_resolve);
  }

  Future<void> deletePost(String id) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>('/community/posts/$id'),
    );
  }

  Future<CommunityPost> like(String id) async {
    final data = await _client.postJsonObject('/community/posts/$id/like');
    return _resolve(CommunityPost.fromJson(data));
  }

  Future<CommunityPost> unlike(String id) async {
    final data = await _client.deleteJsonObject('/community/posts/$id/like');
    return _resolve(CommunityPost.fromJson(data));
  }

  /// 收藏（书签）。与点赞是两个独立动作。
  Future<CommunityPost> favorite(String id) async {
    final data = await _client.postJsonObject('/community/posts/$id/favorite');
    return _resolve(CommunityPost.fromJson(data));
  }

  Future<CommunityPost> unfavorite(String id) async {
    final data = await _client.deleteJsonObject('/community/posts/$id/favorite');
    return _resolve(CommunityPost.fromJson(data));
  }

  /// 我收藏的旅记。
  Future<CommunityPage> fetchFavorites({int page = 1, int size = 20}) async {
    final data = await _client.getJsonObject(
      '/community/posts/favorites',
      query: <String, dynamic>{'page': page, 'size': size},
    );
    return CommunityPage.fromJson(data).mapItems(_resolve);
  }

  Future<void> report(String id, String reason) async {
    await _client.sendNoContent(
      () => _client.post<dynamic>(
        '/community/posts/$id/report',
        data: <String, Object?>{'reason': reason},
      ),
    );
  }

  // ------------------------------------------------------------------
  // 评论
  // ------------------------------------------------------------------

  Future<CommentPage> fetchComments(
    String postId, {
    int page = 1,
    int size = 20,
  }) async {
    final data = await _client.getJsonObject(
      '/community/posts/$postId/comments',
      query: <String, dynamic>{'page': page, 'size': size},
    );
    return CommentPage.fromJson(data).mapItems(_resolveComment);
  }

  Future<CommunityComment> addComment(
    String postId,
    String content, {
    String? parentId,
  }) async {
    final data = await _client.postJsonObject(
      '/community/posts/$postId/comments',
      body: <String, dynamic>{
        'content': content,
        'parentId': parentId,
      },
    );
    return _resolveComment(CommunityComment.fromJson(data));
  }

  /// 给评论点赞 / 取消。服务端返回的是那条评论的最新状态。
  ///
  /// 注意返回值的 `replies` 一定是空的：接口只回这一条评论，调用方应该只取
  /// `likeCount` 与 `likedByMe`，不要把整棵回复树用它替换掉。
  Future<CommunityComment> likeComment(String commentId) async {
    final data = await _client.postJsonObject('/community/comments/$commentId/like');
    return _resolveComment(CommunityComment.fromJson(data));
  }

  Future<CommunityComment> unlikeComment(String commentId) async {
    final data = await _client.deleteJsonObject('/community/comments/$commentId/like');
    return _resolveComment(CommunityComment.fromJson(data));
  }

  /// 「我的」页的互动数据。
  Future<CommunityStats> fetchMyStats() async {
    final data = await _client.getJsonObject('/community/stats/me');
    return CommunityStats.fromJson(data);
  }

  Future<void> deleteComment(String commentId) async {
    await _client.sendNoContent(
      () => _client.delete<dynamic>('/community/comments/$commentId'),
    );
  }

  Future<String> uploadImage(File file) async {
    try {
      final data = await _client
          .postMultipartJson(
            '/community/media/images',
            data: FormData.fromMap(<String, Object>{
              'file': await MultipartFile.fromFile(file.path),
            }),
          )
          // 单张图片必须有明确上限：网络半开时不能让发布页一直转圈。
          .timeout(const Duration(seconds: 45));
      return (data['relativeUrl'] ?? data['url'] ?? '').toString();
    } on TimeoutException {
      throw const ApiFailure(
        kind: ApiFailureKind.timeout,
        message: '图片上传超时，请检查网络后重试。',
      );
    }
  }
}
