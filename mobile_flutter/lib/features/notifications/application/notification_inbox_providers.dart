import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../data/notification_inbox_api.dart';
import '../domain/app_notification.dart';

final notificationInboxApiProvider = Provider<NotificationInboxApi>((ref) {
  return NotificationInboxApi(ref.watch(dioProvider));
});

final notificationInboxProvider = FutureProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationInboxApiProvider).list();
});

final unreadNotificationCountProvider = FutureProvider<int>((ref) {
  return ref.watch(notificationInboxApiProvider).unreadCount();
});

final notificationInboxActionProvider =
    AsyncNotifierProvider<NotificationInboxAction, void>(
  NotificationInboxAction.new,
);

class NotificationInboxAction extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> setRead(String id, {required bool read}) => _run(
        () => ref.read(notificationInboxApiProvider).setRead(id, read: read),
      );

  Future<void> readAll() =>
      _run(() => ref.read(notificationInboxApiProvider).readAll());

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    ref
      ..invalidate(notificationInboxProvider)
      ..invalidate(unreadNotificationCountProvider);
  }
}
