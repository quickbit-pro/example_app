class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventType,
    required this.title,
    required this.body,
    required this.route,
    required this.createdAt,
    required this.readAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] ?? '').toString(),
        eventType: (json['eventType'] ?? '').toString(),
        title: (json['title'] ?? 'Notification').toString(),
        body: (json['body'] ?? '').toString(),
        route: (json['route'] ?? '/home').toString(),
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        readAt: DateTime.tryParse(json['readAt']?.toString() ?? ''),
      );

  final String id;
  final String eventType;
  final String title;
  final String body;
  final String route;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
}
