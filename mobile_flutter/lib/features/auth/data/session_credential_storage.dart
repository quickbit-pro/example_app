import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final sessionStorageProvider = Provider<SessionCredentialStorage>((ref) {
  return SessionCredentialStorage();
});

/// Keeps the signed-in session (access + refresh token) in the platform
/// keystore so the app survives a restart or a browser refresh without asking
/// for the password again. Cleared on sign-out.
class SessionCredentialStorage {
  SessionCredentialStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  final FlutterSecureStorage _storage;
  Future<void> _writes = Future.value();

  Future<void> _writeInOrder(Future<void> Function() write) {
    final next = _writes.catchError((_) {}).then((_) => write());
    _writes = next;
    return next;
  }

  static const _tokenKey = 'auth.session.token';
  static const _sessionKey = 'auth.session.v2';
  static const _refreshTokenKey = 'auth.session.refreshToken';
  static const _emailKey = 'auth.session.email';
  static const _userNameKey = 'auth.session.userName';

  Future<StoredSession?> read() async {
    await _writes.catchError((_) {});
    try {
      final encoded = await _storage.read(key: _sessionKey);
      if (encoded != null) {
        final data = jsonDecode(encoded) as Map<String, dynamic>;
        return StoredSession(
          accessToken: data['accessToken'] as String,
          refreshToken: data['refreshToken'] as String,
          email: data['email'] as String,
          userName: data['userName'] as String,
        );
      }
      final token = await _storage.read(key: _tokenKey);
      if (token == null || token.isEmpty) return null;
      return StoredSession(
        accessToken: token,
        refreshToken: await _storage.read(key: _refreshTokenKey) ?? '',
        email: await _storage.read(key: _emailKey) ?? '',
        userName: await _storage.read(key: _userNameKey) ?? '',
      );
    } catch (_) {
      // A missing keystore (tests, unsupported browsers) only means no
      // restored session.
      return null;
    }
  }

  Future<void> save(StoredSession session) =>
      _writeInOrder(() => _save(session));

  Future<void> _save(StoredSession session) async {
    try {
      // One encrypted record prevents app closure between separate writes
      // from leaving a new access token paired with an old refresh token.
      await _storage.write(
          key: _sessionKey,
          value: jsonEncode({
            'accessToken': session.accessToken,
            'refreshToken': session.refreshToken,
            'email': session.email,
            'userName': session.userName,
          }));
    } catch (_) {
      // Persistence is best effort; the live session keeps working.
    }
  }

  Future<void> clear() => _writeInOrder(_clear);

  Future<void> _clear() async {
    try {
      await _storage.delete(key: _sessionKey);
      await _storage.delete(key: _tokenKey);
      await _storage.delete(key: _refreshTokenKey);
      await _storage.delete(key: _emailKey);
      await _storage.delete(key: _userNameKey);
    } catch (_) {
      // Nothing to clear.
    }
  }
}

class StoredSession {
  const StoredSession({
    required this.accessToken,
    required this.refreshToken,
    required this.email,
    required this.userName,
  });

  final String accessToken;
  final String refreshToken;
  final String email;
  final String userName;
}
