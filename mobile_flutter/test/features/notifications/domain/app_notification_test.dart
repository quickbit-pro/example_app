import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/notifications/domain/app_notification.dart';

void main() {
  test('parses unread and read inbox notifications', () {
    final unread = AppNotification.fromJson({
      'id': 'notification-1',
      'eventType': 'card.transaction',
      'title': 'Card payment',
      'body': 'Payment completed',
      'route': '/transactions/42',
      'createdAt': '2026-09-01T08:00:00Z',
      'readAt': null,
    });
    final read = AppNotification.fromJson({
      'id': 'notification-2',
      'createdAt': '2026-09-01T08:00:00Z',
      'readAt': '2026-09-01T08:05:00Z',
    });

    expect(unread.isRead, isFalse);
    expect(unread.route, '/transactions/42');
    expect(read.isRead, isTrue);
  });
}
