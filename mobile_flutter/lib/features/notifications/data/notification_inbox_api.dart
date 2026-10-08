import 'package:dio/dio.dart';

import '../domain/app_notification.dart';

class NotificationInboxApi {
  const NotificationInboxApi(this._dio);

  final Dio _dio;

  Future<List<AppNotification>> list({bool unreadOnly = false}) async {
    final response = await _dio.get<dynamic>(
      '/api/v1/mobile/notifications',
      queryParameters: {'unreadOnly': unreadOnly, 'limit': 100},
    );
    final data = response.data;
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ))
        .map(AppNotification.fromJson)
        .toList();
  }

  Future<int> unreadCount() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/mobile/notifications/unread-count',
    );
    final value = response.data?['count'];
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  Future<void> setRead(String notificationId, {required bool read}) =>
      _dio.patch<void>(
        '/api/v1/mobile/notifications/${Uri.encodeComponent(notificationId)}',
        data: {'read': read},
      );

  Future<void> readAll() =>
      _dio.post<void>('/api/v1/mobile/notifications/read-all');
}
