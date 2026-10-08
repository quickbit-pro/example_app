import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../api/auth_token_provider.dart';
import '../api/dio_provider.dart';

/// Display-only cache identity. Tokens still require server validation; these
/// claims only prevent one customer/installation from seeing another's cache.
String? displayCacheOwner(String? token, String apiBaseUrl) {
  try {
    if (token == null) return null;
    final claims = jsonDecode(utf8.decode(
        base64Url.decode(base64Url.normalize(token.split('.')[1])))) as Map;
    final user = claims['local_user_id'] ?? claims['sub'];
    if (user == null || user.toString().isEmpty) return null;
    return sha256
        .convert(utf8.encode(jsonEncode([
          apiBaseUrl,
          claims['iss'],
          claims['company_installation_id'],
          user,
        ])))
        .toString();
  } catch (_) {
    return null;
  }
}

final displayCacheOwnerProvider = Provider<String?>((ref) {
  final baseUrl = ref.watch(appConfigProvider).apiBaseUrl;
  // Session generation advances after credentials are installed. Watching the
  // token directly would briefly pair a new owner with the old API graph.
  ref.watch(authSessionGenerationProvider);
  return displayCacheOwner(ref.read(authTokenProvider), baseUrl);
}, dependencies: [appConfigProvider, authSessionGenerationProvider]);

final displaySnapshotStorageProvider = Provider<DisplaySnapshotStorage>((ref) {
  final storage = DisplaySnapshotStorage();
  ref.listen(authTokenProvider, (previous, next) {
    if (previous != null && next == null) unawaited(storage.clear());
  });
  return storage;
}, dependencies: [authTokenProvider]);

/// One bounded, versioned bucket in the existing platform secure store. Writes
/// and logout cleanup are ordered so an older write cannot resurrect the cache.
class DisplaySnapshotStorage {
  DisplaySnapshotStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  static const key = 'display.snapshots.v1';
  static const maxAge = Duration(hours: 24);
  final FlutterSecureStorage _storage;
  Future<void> _pending = Future.value();

  Future<T?> _ordered<T>(Future<T?> Function() action) {
    final result =
        _pending.then((_) => action()).catchError((Object _) => null);
    _pending = result.then<void>((_) {});
    return result;
  }

  Future<Map<String, dynamic>> _readBucket(String owner) async {
    final raw = await _storage.read(key: key);
    if (raw == null) return {};
    final bucket = jsonDecode(raw) as Map<String, dynamic>;
    return bucket['owner'] == owner
        ? Map<String, dynamic>.from(bucket['entries'] as Map)
        : {};
  }

  Future<Map<String, dynamic>?> read(String owner, String name) =>
      _ordered(() async {
        final entry = (await _readBucket(owner))[name];
        if (entry is! Map) return null;
        final savedAt = DateTime.parse(entry['savedAt'] as String);
        final age = DateTime.now().difference(savedAt);
        if (age.isNegative || age > maxAge) return null;
        return Map<String, dynamic>.from(entry);
      });

  Future<void> write(String owner, String name, Map<String, dynamic> entry,
      {required bool Function() isCurrent}) async {
    await _ordered<void>(() async {
      if (!isCurrent()) return;
      Map<String, dynamic> entries;
      try {
        entries = await _readBucket(owner);
      } catch (_) {
        entries = {};
      }
      if (!isCurrent()) return;
      entries.remove(name);
      entries[name] = entry;
      while (entries.length > 12) {
        entries.remove(entries.keys.first);
      }
      var encoded = jsonEncode({'owner': owner, 'entries': entries});
      while (encoded.length > 2000000 && entries.length > 1) {
        entries.remove(entries.keys.first);
        encoded = jsonEncode({'owner': owner, 'entries': entries});
      }
      if (encoded.length <= 2000000) {
        await _storage.write(key: key, value: encoded);
      }
    });
  }

  Future<void> clear() async {
    await _ordered<void>(() => _storage.delete(key: key));
  }
}

class DisplaySnapshot<T> {
  const DisplaySnapshot({
    required this.value,
    this.isSaved = false,
    this.isRefreshing = false,
    this.savedAt,
    this.refreshError,
  });

  final AsyncValue<T> value;
  final bool isSaved;
  final bool isRefreshing;
  final DateTime? savedAt;
  final Object? refreshError;
}

/// Network providers remain authoritative for actions, receipts and exports.
/// This adapter races disk hydration against the live source for rendering.
class DisplaySnapshotController<T> extends StateNotifier<DisplaySnapshot<T>> {
  DisplaySnapshotController({
    required this.storage,
    required this.owner,
    required this.name,
    required this.encode,
    required this.decode,
  }) : super(DisplaySnapshot<T>(value: AsyncLoading<T>())) {
    unawaited(_hydrate());
  }

  final DisplaySnapshotStorage storage;
  final String? owner;
  final String name;
  final Map<String, dynamic> Function(T) encode;
  final T Function(Map<String, dynamic>) decode;
  T? _last;
  DateTime? _savedAt;
  bool _receivedFresh = false;
  bool _active = true;
  AsyncValue<T> _source = AsyncLoading<T>();

  Future<void> _hydrate() async {
    if (owner == null) return;
    try {
      final entry = await storage.read(owner!, name);
      if (!mounted || !_active || _receivedFresh || entry == null) return;
      _last = decode(Map<String, dynamic>.from(entry['data'] as Map));
      _savedAt = DateTime.parse(entry['savedAt'] as String);
      _publish();
    } catch (_) {
      // Missing, expired, corrupt or inaccessible storage is a cache miss.
    }
  }

  void endSession() {
    _active = false;
    _last = null;
    state = DisplaySnapshot<T>(value: AsyncLoading<T>());
  }

  void update(AsyncValue<T> next) {
    if (!_active) return;
    _source = next;
    // Riverpod may carry another session's previous value while dependencies
    // reload. Accept only a completed success from the current source.
    if (!next.isLoading && !next.hasError && next.hasValue) {
      _receivedFresh = true;
      _last = next.requireValue;
      _savedAt = DateTime.now();
      if (owner != null) unawaited(_save(_last as T, _savedAt!));
    }
    _publish();
  }

  Future<void> _save(T value, DateTime savedAt) async {
    try {
      await storage.write(
          owner!,
          name,
          {
            'savedAt': savedAt.toIso8601String(),
            'data': encode(value),
          },
          isCurrent: () => mounted && _active);
    } catch (_) {
      // Caching must never prevent a successful response from rendering.
    }
  }

  void _publish() {
    final saved = _last != null && (_source.isLoading || _source.hasError);
    state = DisplaySnapshot(
      value: _last != null
          ? AsyncData(_last as T)
          : _source.isLoading
              ? AsyncLoading<T>()
              : _source.hasError
                  ? AsyncError<T>(_source.error!, _source.stackTrace!)
                  : _source,
      isSaved: saved,
      isRefreshing: _source.isLoading,
      savedAt: _savedAt,
      refreshError: _source.error,
    );
  }
}

DisplaySnapshotController<T> watchDisplaySnapshot<T>(
  Ref ref, {
  required ProviderListenable<AsyncValue<T>> source,
  required String name,
  required Map<String, dynamic> Function(T) encode,
  required T Function(Map<String, dynamic>) decode,
}) {
  ref.watch(authSessionGenerationProvider);
  final controller = DisplaySnapshotController<T>(
    storage: ref.watch(displaySnapshotStorageProvider),
    owner: ref.watch(displayCacheOwnerProvider),
    name: name,
    encode: encode,
    decode: decode,
  );
  ref.listen(authTokenProvider, (previous, next) {
    if (previous != null && next == null) controller.endSession();
  });
  var initializing = true;
  ref.listen(source, (_, next) {
    if (initializing) {
      controller.update(next);
    } else {
      // Dependencies can reload during Riverpod's widget-build flush. Publish
      // afterward, so a watched notifier is not mutated during that build.
      scheduleMicrotask(() {
        if (controller.mounted) controller.update(next);
      });
    }
  }, fireImmediately: true);
  initializing = false;
  return controller;
}
