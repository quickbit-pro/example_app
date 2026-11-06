import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/service_onboarding.dart';

/// Display preferences only. The server remains authoritative for onboarding.
/// The namespace is a hash of API, installation and signed-in user identity.
class OnboardingNoticeStore {
  OnboardingNoticeStore(this.preferences, this.owner) {
    if (owner == null) {
      return;
    }
    try {
      final decoded = jsonDecode(preferences.getString(key) ?? '{}');
      if (decoded is Map) {
        for (final service in OnboardingService.values) {
          final value = decoded[service.name];
          if (value is Map) {
            records[service.name] = Map<String, dynamic>.from(value);
          }
        }
      }
    } catch (_) {
      // A missing or unreadable display preference must not hide a reminder.
    }
  }

  static const completeWindow = Duration(hours: 24);
  final SharedPreferences preferences;
  final String? owner;
  String get key => 'onboarding.notices.v1.$owner';
  final Map<String, Map<String, dynamic>> records = {};
  Future<void> _pending = Future.value();

  Future<T> _ordered<T>(Future<T> Function() action) {
    final result = _pending.then((_) => action());
    _pending = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _save() async {
    if (owner == null) {
      return;
    }
    try {
      await preferences.setString(key, jsonEncode(records));
    } catch (_) {
      // Keep the in-memory acknowledgement if device persistence is unavailable.
    }
  }

  Future<List<ServiceOnboardingItem>> visible(
          List<ServiceOnboardingItem> items, DateTime now) =>
      _ordered(() async {
        final before = jsonEncode(records);
        final result = <ServiceOnboardingItem>[];
        for (final item in items) {
          final record = records.putIfAbsent(item.kind.name, () => {});
          if (item.stage == OnboardingStage.unavailable) {
            // An outage must not resurrect an acknowledged/expired Complete.
            final completedAt =
                DateTime.tryParse(record['completedAt']?.toString() ?? '');
            final previouslyHidden =
                record['state'] == OnboardingStage.complete.name &&
                    (record['acknowledged'] == true ||
                        (completedAt != null &&
                            now.difference(completedAt) >= completeWindow));
            if (!previouslyHidden) result.add(item);
            continue;
          }
          if (item.stage != OnboardingStage.complete) {
            record.remove('completedAt');
            record.remove('acknowledged');
            if (record['state'] != item.stage.name) {
              record['attentionAt'] = now.toUtc().toIso8601String();
            }
            record['state'] = item.stage.name;
            result.add(item);
            continue;
          }
          if (record['state'] != OnboardingStage.complete.name ||
              record['completedAt'] == null) {
            var completedAt = item.completedAt?.toUtc();
            final attention =
                DateTime.tryParse(record['attentionAt']?.toString() ?? '');
            if (completedAt == null ||
                completedAt.isAfter(now) ||
                (attention != null && completedAt.isBefore(attention))) {
              completedAt = now;
            }
            record['completedAt'] = completedAt.toUtc().toIso8601String();
            record['acknowledged'] = false;
          }
          record['state'] = OnboardingStage.complete.name;
          final completedAt =
              DateTime.tryParse(record['completedAt'].toString()) ?? now;
          if (record['acknowledged'] != true &&
              now.difference(completedAt) < completeWindow) {
            result.add(item);
          }
        }
        if (before != jsonEncode(records)) await _save();
        return result;
      });

  Future<void> acknowledge(OnboardingService service) => _ordered(() async {
        final record = records[service.name];
        if (record?['state'] != OnboardingStage.complete.name) {
          return;
        }
        record!['acknowledged'] = true;
        await _save();
      });
}
