import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../core/cache/display_snapshot.dart';
import '../domain/assistant_conversation.dart';
import '../domain/assistant_departure.dart';
import 'assistant_api.dart';

final assistantHistoryOwnerProvider = Provider<String?>(
  (ref) => ref.watch(displayCacheOwnerProvider),
  dependencies: [displayCacheOwnerProvider],
);

final assistantHistoryStorageProvider = Provider<AssistantHistoryStorage>(
  (ref) => AssistantHistoryStorage(),
);

/// Bounded account-scoped device history using the app's platform store.
/// Native secure storage and browser storage have different protections; this
/// is not server history or end-to-end encryption. Sign-out hides memory/UI;
/// this account's history can return after sign-in until it expires or is cleared.
class AssistantHistoryStorage {
  AssistantHistoryStorage({
    FlutterSecureStorage? storage,
    DateTime Function()? now,
  })  : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _now = now ?? DateTime.now;

  static const maxConversations = 20;
  static const maxTurns = 20;
  static const maxAge = Duration(days: 7);
  static const maxEncodedBytes = 512 * 1024;
  static const _keyPrefix = 'assistant.conversations.v1.';
  final FlutterSecureStorage _storage;
  final DateTime Function() _now;
  Future<void> _pending = Future.value();

  static bool _validOwner(String owner) =>
      RegExp(r'^[a-f0-9]{64}$').hasMatch(owner);
  static bool _validId(String id) =>
      RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(id);

  Future<T> _ordered<T>(Future<T> Function() action, T fallback) {
    final result =
        _pending.then((_) => action()).catchError((Object _) => fallback);
    _pending = result.then<void>((_) {});
    return result;
  }

  Future<List<SavedAssistantConversation>> load(String owner) =>
      _ordered(() async {
        if (!_validOwner(owner)) return <SavedAssistantConversation>[];
        final entries = _bounded(await _read(owner));
        // Reading also removes expired/corrupt entries instead of leaving them
        // indefinitely on a device that continues using this account.
        try {
          await _write(owner, entries);
        } catch (_) {
          // A failed cleanup must not hide an otherwise readable history.
        }
        return List<SavedAssistantConversation>.unmodifiable(entries);
      }, const <SavedAssistantConversation>[]);

  Future<bool> save(
    String owner,
    SavedAssistantConversation conversation, {
    required bool Function() isCurrent,
  }) {
    // Freeze and validate before queueing, so caller mutations cannot change a
    // queued save. A trailing pending/failed user turn is intentionally dropped.
    final snapshot = _normalize(conversation);
    return _ordered(() async {
      if (!_validOwner(owner) || snapshot == null || !isCurrent()) return false;
      final entries = await _read(owner);
      if (!isCurrent()) return false;
      entries.removeWhere((entry) => entry.id == snapshot.id);
      entries.add(snapshot);
      final bounded = _bounded(entries);
      await _write(owner, bounded);
      return bounded.any((entry) => entry.id == snapshot.id);
    }, false);
  }

  Future<bool> delete(
    String owner,
    String id, {
    required bool Function() isCurrent,
  }) =>
      _ordered(() async {
        if (!_validOwner(owner) || !_validId(id) || !isCurrent()) return false;
        final entries = await _read(owner);
        if (!isCurrent()) return false;
        entries.removeWhere((entry) => entry.id == id);
        await _write(owner, _bounded(entries));
        return true;
      }, false);

  Future<bool> clear(String owner, {required bool Function() isCurrent}) =>
      _ordered(() async {
        if (!_validOwner(owner) || !isCurrent()) return false;
        await _storage.delete(key: '$_keyPrefix$owner');
        return true;
      }, false);

  Future<List<SavedAssistantConversation>> _read(String owner) async {
    final raw = await _storage.read(key: '$_keyPrefix$owner');
    if (raw == null || utf8.encode(raw).length > maxEncodedBytes) return [];
    try {
      final bucket = jsonDecode(raw);
      if (bucket is! Map ||
          bucket['version'] != 1 ||
          bucket['owner'] != owner) {
        return [];
      }
      final items = bucket['conversations'];
      if (items is! List || items.length > maxConversations) return [];
      final result = <SavedAssistantConversation>[];
      for (final item in items) {
        try {
          if (item is! Map) continue;
          final turns = item['turns'];
          if (turns is! List || turns.length > maxTurns) continue;
          final savedTurns = <SavedAssistantTurn>[];
          for (final turn in turns) {
            if (turn is! Map) throw const FormatException();
            savedTurns.add(SavedAssistantTurn(
              role: turn['role'] as String,
              text: turn['text'] as String,
              reply: turn['reply'] == null
                  ? null
                  : AssistantReply.fromJson(
                      Map<String, dynamic>.from(turn['reply'] as Map)),
            ));
          }
          final departureJson = item['departure'];
          AssistantDeparture? departure;
          if (departureJson is Map) {
            departure = AssistantDeparture(
              city: departureJson['city'] as String,
              countryCode: departureJson['countryCode'] as String?,
              airportCode: departureJson['airportCode'] as String?,
            );
          }
          final parsed = _normalize(SavedAssistantConversation(
            id: item['id'] as String,
            title: item['title'] as String,
            updatedAt: DateTime.parse(item['updatedAt'] as String),
            turns: savedTurns,
            departure: departure,
          ));
          if (parsed != null) result.add(parsed);
        } catch (_) {
          // A corrupt conversation must not hide other valid saved chats.
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }

  SavedAssistantConversation? _normalize(SavedAssistantConversation entry) {
    if (!_validId(entry.id)) return null;
    final turns = <SavedAssistantTurn>[];
    for (var index = 0; index + 1 < entry.turns.length; index += 2) {
      final question = entry.turns[index];
      final answer = entry.turns[index + 1];
      final reply = answer.reply;
      if (question.role != 'user' ||
          question.reply != null ||
          answer.role != 'assistant' ||
          reply == null ||
          question.text.trim().isEmpty ||
          question.text.length > 1500 ||
          reply.reply.trim().isEmpty ||
          reply.reply.length > 12000 ||
          answer.text != reply.reply) {
        // Refuse incomplete/misaligned pairs rather than associate the wrong
        // answer with a question or accidentally persist a rejected draft.
        continue;
      }
      final safeReply = AssistantReply.fromJson(_replyJson(reply));
      turns.add(SavedAssistantTurn(role: 'user', text: question.text));
      turns.add(SavedAssistantTurn(
          role: 'assistant', text: safeReply.reply, reply: safeReply));
    }
    if (turns.isEmpty) return null;
    final departure = entry.departure;
    final validDeparture = departure != null &&
        isValidAssistantDepartureCity(departure.city) &&
        (departure.countryCode == null ||
            RegExp(r'^[A-Z]{2}$').hasMatch(departure.countryCode!)) &&
        (departure.airportCode == null ||
            RegExp(r'^[A-Z]{3}$').hasMatch(departure.airportCode!));
    return SavedAssistantConversation(
      id: entry.id,
      title: assistantConversationTitle(
          entry.title.isEmpty ? turns.first.text : entry.title),
      updatedAt: entry.updatedAt.toUtc(),
      turns: turns
          .skip(turns.length > maxTurns ? turns.length - maxTurns : 0)
          .toList(),
      departure: validDeparture ? departure : null,
    );
  }

  List<SavedAssistantConversation> _bounded(
      List<SavedAssistantConversation> entries) {
    final now = _now().toUtc();
    final byId = <String, SavedAssistantConversation>{};
    for (final entry in entries) {
      final age = now.difference(entry.updatedAt);
      if (age.isNegative || age >= maxAge) continue;
      final previous = byId[entry.id];
      if (previous == null || entry.updatedAt.isAfter(previous.updatedAt)) {
        byId[entry.id] = entry;
      }
    }
    final sorted = byId.values.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(maxConversations).toList();
  }

  Future<void> _write(
      String owner, List<SavedAssistantConversation> entries) async {
    var encoded = _encode(owner, entries);
    while (
        utf8.encode(encoded).length > maxEncodedBytes && entries.isNotEmpty) {
      if (entries.length > 1 || entries.single.turns.length <= 2) {
        entries.removeLast();
      } else {
        // Keep the newest successful pairs even if one large conversation
        // exceeds the device storage budget by itself.
        final entry = entries.single;
        entries[0] = SavedAssistantConversation(
          id: entry.id,
          title: entry.title,
          updatedAt: entry.updatedAt,
          turns: entry.turns.skip(2).toList(),
          departure: entry.departure,
        );
      }
      encoded = _encode(owner, entries);
    }
    if (entries.isEmpty) {
      await _storage.delete(key: '$_keyPrefix$owner');
    } else {
      await _storage.write(key: '$_keyPrefix$owner', value: encoded);
    }
  }

  String _encode(String owner, List<SavedAssistantConversation> entries) =>
      jsonEncode({
        'version': 1,
        'owner': owner,
        'conversations': [
          for (final entry in entries)
            {
              'id': entry.id,
              'title': entry.title,
              'updatedAt': entry.updatedAt.toIso8601String(),
              if (entry.departure != null)
                'departure': entry.departure!.toJson(),
              'turns': [
                for (final turn in entry.turns)
                  {
                    'role': turn.role,
                    'text': turn.text,
                    if (turn.reply != null) 'reply': _replyJson(turn.reply!),
                  }
              ],
            }
        ],
      });

  Map<String, dynamic> _replyJson(AssistantReply reply) => {
        'reply': reply.reply,
        if (reply.answer != null) 'answer': reply.answer!.toJson(),
        if (reply.verification != null) 'verification': reply.verification,
        'actions': [
          for (final action in reply.actions.take(5))
            {
              'label': truncateAssistantText(action.label, 160),
              'url': action.url.length > 4096 ? '' : action.url,
              'kind': action.kind,
            }
        ],
        'sources': [
          for (final source in reply.sources.take(5))
            {
              'title': truncateAssistantText(source.title, 240),
              'url': source.url.length > 4096 ? '' : source.url,
            }
        ],
        'webSearchUsed': reply.webSearchUsed,
        'refused': reply.refused,
        'usage': {
          'enabled': reply.usage.enabled,
          'dailyLimit': reply.usage.dailyLimit,
          'used': reply.usage.used,
          'remaining': reply.usage.remaining,
          'resetsAt': reply.usage.resetsAt.toIso8601String(),
          'maxMessageCharacters': reply.usage.maxMessageCharacters,
        },
      };
}
