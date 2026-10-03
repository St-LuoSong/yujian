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
    this.authorAvatarKey,
    this.tripPlanId,
    this.createdAt,
    this.publishedAt,
    this.moderationNote,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> json) => CommunityPost(
        id: _text(json['id']),
        authorName: _text(json['authorName']),
        authorAvatarKey: json['authorAvatarKey']?.toString(),
        tripPlanId: json['tripPlanId']?.toString(),
        title: _text(json['title']),
        content: _text(json['content']),
        city: _text(json['city']),
        tags: _tags(json['tags']),
        imageUrls: _textList(json['imageUrls']),
        likeCount: _integer(json['likeCount']),
        viewCount: _integer(json['viewCount']),
        likedByMe: json['likedByMe'] == true,
        status: _text(json['status']),
        visibility: _text(json['visibility']),
        createdAt: _date(json['createdAt']),
        publishedAt: _date(json['publishedAt']),
        moderationNote: json['moderationNote']?.toString(),
      );

  final String id;
  final String authorName;
  final String? authorAvatarKey;
  final String? tripPlanId;
  final String title;
  final String content;
  final String city;
  final List<String> tags;
  final List<String> imageUrls;
  final int likeCount;
  final int viewCount;
  final bool likedByMe;
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
  }) =>
      CommunityPost(
        id: id,
        authorName: authorName,
        authorAvatarKey: authorAvatarKey,
        tripPlanId: tripPlanId,
        title: title,
        content: content,
        city: city,
        tags: tags,
        imageUrls: imageUrls ?? this.imageUrls,
        likeCount: likeCount ?? this.likeCount,
        viewCount: viewCount,
        likedByMe: likedByMe ?? this.likedByMe,
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
