/// A message shown in the in-app notification center.
class NoticeMessage {
  const NoticeMessage({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.read = false,
    this.createdAt,
  });

  factory NoticeMessage.fromJson(Map<String, dynamic> json) => NoticeMessage(
        id: json['id']?.toString() ?? '',
        type: json['type']?.toString() ?? 'SYSTEM',
        title: json['title']?.toString() ?? '',
        body: json['body']?.toString() ?? '',
        read: json['read'] == true,
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      );

  final String id;
  final String type;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
}

class NoticeInbox {
  const NoticeInbox({required this.items, required this.unread});

  factory NoticeInbox.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((item) => NoticeMessage.fromJson(item.cast<String, dynamic>()))
            .toList()
        : <NoticeMessage>[];
    return NoticeInbox(
      items: items,
      unread: _integer(json['unread']),
    );
  }

  final List<NoticeMessage> items;
  final int unread;
}

int _integer(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
