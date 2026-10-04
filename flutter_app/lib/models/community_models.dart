class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.authorName,
    required this.title,
    required this.content,
    required this.city,
    required this.tags,
    required this.imageUrls,
    required this.likeCount,
    required this.viewCount,
    required this.likedByMe,
    required this.status,
    required this.visibility,
    this.favoriteCount = 0,
    this.commentCount = 0,
    this.favoritedByMe = false,
    this.authorAvatarKey,
    this.authorAvatarUrl,
    this.tripPlanId,
    this.createdAt,
    this.publishedAt,
    this.moderationNote,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: _text(json['id']),
        authorName: _text(json['authorName']),
        authorAvatarKey: json['authorAvatarKey']?.toString(),
        authorAvatarUrl: json['authorAvatarUrl']?.toString(),
        tripPlanId: json['tripPlanId']?.toString(),
        title: _text(json['title']),
        content: _text(json['content']),
        city: _text(json['city']),
        tags: _tags(json['tags']),
        imageUrls: _textList(json['imageUrls']),
        likeCount: _integer(json['likeCount']),
        favoriteCount: _integer(json['favoriteCount']),
        commentCount: _integer(json['commentCount']),
        viewCount: _integer(json['viewCount']),
        likedByMe: json['likedByMe'] == true,
        favoritedByMe: json['favoritedByMe'] == true,
        status: _text(json['status']),
        visibility: _text(json['visibility']),
        createdAt: _date(json['createdAt']),
        publishedAt: _date(json['publishedAt']),
        moderationNote: json['moderationNote']?.toString(),
      );

  final String id;
  final String authorName;
  final String? authorAvatarKey;

  /// 作者自定义头像的相对路径；为空时回落到 [authorAvatarKey] 的预设图案。
  final String? authorAvatarUrl;
  final String? tripPlanId;
  final String title;
  final String content;
  final String city;
  final List<String> tags;
  final List<String> imageUrls;
  final int likeCount;
  final int favoriteCount;
  final int commentCount;
  final int viewCount;
  final bool likedByMe;
  final bool favoritedByMe;
  final String status;
  final String visibility;
  final DateTime? createdAt;
  final DateTime? publishedAt;
  final String? moderationNote;

  bool get isPublic => visibility == 'PUBLIC';

  /// 只用于把图片地址换成这台设备能访问的绝对地址，或更新点赞状态。
  CommunityPost copyWith({
    List<String>? imageUrls,
    int? likeCount,
    bool? likedByMe,
    int? favoriteCount,
    int? commentCount,
    bool? favoritedByMe,
    String? authorAvatarUrl,
  }) =>
      CommunityPost(
        id: id,
        authorName: authorName,
        authorAvatarKey: authorAvatarKey,
        authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
        tripPlanId: tripPlanId,
        title: title,
        content: content,
        city: city,
        tags: tags,
        imageUrls: imageUrls ?? this.imageUrls,
        likeCount: likeCount ?? this.likeCount,
        favoriteCount: favoriteCount ?? this.favoriteCount,
        commentCount: commentCount ?? this.commentCount,
        viewCount: viewCount,
        likedByMe: likedByMe ?? this.likedByMe,
        favoritedByMe: favoritedByMe ?? this.favoritedByMe,
        status: status,
        visibility: visibility,
        createdAt: createdAt,
        publishedAt: publishedAt,
        moderationNote: moderationNote,
      );
}

class CommunityPage {
  const CommunityPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
    required this.hasMore,
  });

  factory CommunityPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    return CommunityPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) => CommunityPost.fromJson(item.cast<String, dynamic>()))
              .toList()
          : const <CommunityPost>[],
      page: _integer(json['page']),
      size: _integer(json['size']),
      total: _integer(json['total']),
      hasMore: json['hasMore'] == true,
    );
  }

  final List<CommunityPost> items;
  final int page;
  final int size;
  final int total;
  final bool hasMore;

  CommunityPage mapItems(CommunityPost Function(CommunityPost) transform) =>
      CommunityPage(
        items: items.map(transform).toList(),
        page: page,
        size: size,
        total: total,
        hasMore: hasMore,
      );
}

String _text(Object? value) => value?.toString() ?? '';

String? _textOrNull(Object? value) {
  final String text = value?.toString() ?? '';
  return text.isEmpty ? null : text;
}

/// 一条旅记评论。Mirrors `CommunityModels.CommentView`.
///
/// [mine] 由服务端判定，客户端不拿用户名去比对：用户名可能被改过，而且"这条
/// 能不能删"本来就不该由客户端自己算。
class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.authorName,
    required this.content,
    required this.mine,
    this.parentId,
    this.authorAvatarKey,
    this.authorAvatarUrl,
    this.likeCount = 0,
    this.likedByMe = false,
    this.status = 'ACTIVE',
    this.createdAt,
    this.replies = const <CommunityComment>[],
  });

  factory CommunityComment.fromJson(Map<String, dynamic> json) => CommunityComment(
        id: _text(json['id']),
        postId: _text(json['postId']),
        parentId: _textOrNull(json['parentId']),
        authorName: _text(json['authorName']),
        authorAvatarKey: json['authorAvatarKey']?.toString(),
        authorAvatarUrl: json['authorAvatarUrl']?.toString(),
        content: _text(json['content']),
        mine: json['mine'] == true,
        likeCount: _integer(json['likeCount']),
        likedByMe: json['likedByMe'] == true,
        status: _textOrNull(json['status']) ?? 'ACTIVE',
        createdAt: _date(json['createdAt']),
        replies: _commentList(json['replies']),
      );

  final String id, postId, authorName, content;

  /// 为空表示顶层评论；非空表示它挂在某条顶层评论下（服务端只做两层）。
  final String? parentId;
  final String? authorAvatarKey;
  final String? authorAvatarUrl;
  final bool mine;
  final int likeCount;
  final bool likedByMe;
  final String status;
  final DateTime? createdAt;

  /// 只有顶层评论会带内容；回复自身的这一项恒为空。
  final List<CommunityComment> replies;

  bool get isReply => parentId != null && parentId!.isNotEmpty;

  CommunityComment copyWith({
    String? authorAvatarUrl,
    int? likeCount,
    bool? likedByMe,
    List<CommunityComment>? replies,
  }) =>
      CommunityComment(
        id: id,
        postId: postId,
        parentId: parentId,
        authorName: authorName,
        authorAvatarKey: authorAvatarKey,
        authorAvatarUrl: authorAvatarUrl ?? this.authorAvatarUrl,
        content: content,
        mine: mine,
        likeCount: likeCount ?? this.likeCount,
        likedByMe: likedByMe ?? this.likedByMe,
        status: status,
        createdAt: createdAt,
        replies: replies ?? this.replies,
      );
}

/// 「我的」页的互动数据。每一项都只统计"别人对我"的动作。
class CommunityStats {
  const CommunityStats({
    required this.postLikes,
    required this.commentLikes,
    required this.favorites,
    required this.comments,
  });

  factory CommunityStats.fromJson(Map<String, dynamic> json) => CommunityStats(
        postLikes: _integer(json['postLikes']),
        commentLikes: _integer(json['commentLikes']),
        favorites: _integer(json['favorites']),
        comments: _integer(json['comments']),
      );

  final int postLikes;
  final int commentLikes;
  final int favorites;
  final int comments;

  int get totalLikes => postLikes + commentLikes;
}

List<CommunityComment> _commentList(Object? value) {
  if (value is! List) return const <CommunityComment>[];
  return value
      .whereType<Map>()
      .map((item) => CommunityComment.fromJson(item.cast<String, dynamic>()))
      .toList();
}

class CommentPage {
  const CommentPage({
    required this.items,
    required this.page,
    required this.size,
    required this.total,
    required this.hasMore,
  });

  factory CommentPage.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['items'];
    return CommentPage(
      items: raw is List
          ? raw
              .whereType<Map>()
              .map((item) =>
                  CommunityComment.fromJson(item.cast<String, dynamic>()))
              .toList()
          : const <CommunityComment>[],
      page: _integer(json['page']),
      size: _integer(json['size']),
      total: _integer(json['total']),
      hasMore: json['hasMore'] == true,
    );
  }

  final List<CommunityComment> items;
  final int page;
  final int size;
  final int total;
  final bool hasMore;

  CommentPage mapItems(CommunityComment Function(CommunityComment) transform) =>
      CommentPage(
        // 递归而不是只映射顶层：回复里的头像地址同样要按当前主机补全，
        // 漏掉一层就会出现"主评论头像正常、回复头像碎图"。
        items: items.map((item) => _mapCommentTree(item, transform)).toList(),
        page: page,
        size: size,
        total: total,
        hasMore: hasMore,
      );
}

CommunityComment _mapCommentTree(
  CommunityComment comment,
  CommunityComment Function(CommunityComment) transform,
) =>
    transform(comment.copyWith(
      replies: comment.replies.map(transform).toList(),
    ));

int _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _date(Object? value) => DateTime.tryParse(value?.toString() ?? '');

List<String> _textList(Object? value) {
  if (value is! List) return const <String>[];
  return value.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
}

List<String> _tags(Object? value) {
  if (value is List) return _textList(value);
  final raw = value?.toString() ?? '';
  return raw
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}
