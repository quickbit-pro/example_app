import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the auth tokens (and the email used for the password login) in
/// the platform keystore so we can rehydrate the session after a successful
/// biometric prompt without re-hitting the password endpoint.
///
/// Storage backends:
///   • iOS — Keychain, `first_unlock_this_device`, never synced to iCloud.
///   • Android — EncryptedSharedPreferences (AES-256 GCM, master key in the
///     Android Keystore).
///
/// We never store the password. On logout or when the user disables
/// biometrics we wipe the entire entry.
class BiometricCredentialStorage {
  BiometricCredentialStorage([FlutterSecureStorage? storage])
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

  static const _tokenKey = 'auth.biometric.token';
  static const _refreshTokenKey = 'auth.biometric.refreshToken';
  static const _emailKey = 'auth.biometric.email';
  static const _userNameKey = 'auth.biometric.userName';
  static const _enabledKey = 'auth.biometric.enabled';

  Future<bool> isEnabled() async {
    await _writes.catchError((_) {});
    final value = await _storage.read(key: _enabledKey);
    return value == 'true';
  }

  Future<bool> hasStoredToken() async {
    await _writes.catchError((_) {});
    final token = await _storage.read(key: _tokenKey);
    return token != null && token.isNotEmpty;
  }

  Future<String?> readToken() async {
    await _writes.catchError((_) {});
    return _storage.read(key: _tokenKey);
  }

  Future<String?> readRefreshToken() async {
    await _writes.catchError((_) {});
    return _storage.read(key: _refreshTokenKey);
  }

  Future<String?> readEmail() async {
    await _writes.catchError((_) {});
    return _storage.read(key: _emailKey);
  }

  Future<String?> readUserName() async {
    await _writes.catchError((_) {});
    return _storage.read(key: _userNameKey);
  }

  Future<void> save({
    required String token,
    String refreshToken = '',
    required String email,
    String userName = '',
  }) =>
      _writeInOrder(() => _save(
          token: token,
          refreshToken: refreshToken,
          email: email,
          userName: userName));

  Future<void> _save({
    required String token,
    String refreshToken = '',
    required String email,
    String userName = '',
  }) async {
    await _storage.write(key: _tokenKey, value: token);
    if (refreshToken.isEmpty) {
      await _storage.delete(key: _refreshTokenKey);
    } else {
      await _storage.write(key: _refreshTokenKey, value: refreshToken);
    }
    await _storage.write(key: _emailKey, value: email);
    await _storage.write(key: _userNameKey, value: userName);
    await _storage.write(key: _enabledKey, value: 'true');
  }

  Future<void> disable() => _writeInOrder(_disable);

  Future<void> _disable() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userNameKey);
    await _storage.write(key: _enabledKey, value: 'false');
  }

  Future<void> clear() => _writeInOrder(_clear);

  Future<void> _clear() async {
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: _emailKey);
    await _storage.delete(key: _userNameKey);
    await _storage.delete(key: _enabledKey);
  }
}
