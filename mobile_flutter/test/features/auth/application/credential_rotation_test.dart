import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/auth/data/biometric_credential_storage.dart';
import 'package:mobile_flutter/features/auth/data/session_credential_storage.dart';

class _SlowStorage extends FlutterSecureStorage {
  final data = <String, String>{};
  final firstWrite = Completer<void>();
  int writes = 0;
  @override
  Future<void> write(
      {required String key,
      required String? value,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    if (writes++ == 0) await firstWrite.future;
    if (value != null) data[key] = value;
  }

  @override
  Future<String?> read(
          {required String key,
          IOSOptions? iOptions,
          AndroidOptions? aOptions,
          LinuxOptions? lOptions,
          WebOptions? webOptions,
          MacOsOptions? mOptions,
          WindowsOptions? wOptions}) async =>
      data[key];
  @override
  Future<void> delete(
      {required String key,
      IOSOptions? iOptions,
      AndroidOptions? aOptions,
      LinuxOptions? lOptions,
      WebOptions? webOptions,
      MacOsOptions? mOptions,
      WindowsOptions? wOptions}) async {
    data.remove(key);
  }
}

void main() {
  test('session is one encrypted write and survives a fresh storage instance',
      () async {
    final disk = _SlowStorage()..firstWrite.complete();
    final session = SessionCredentialStorage(disk);
    await session.save(const StoredSession(
        accessToken: 'access',
        refreshToken: 'refresh',
        email: 'test@example.test',
        userName: 'Tester'));
    expect(disk.writes, 1);
    final restored = await SessionCredentialStorage(disk).read();
    expect(restored?.accessToken, 'access');
    expect(restored?.refreshToken, 'refresh');
  });
  test('existing installed apps can still read their legacy saved session',
      () async {
    final disk = _SlowStorage()
      ..data.addAll({
        'auth.session.token': 'legacy',
        'auth.session.refreshToken': 'legacy-refresh'
      });
    final restored = await SessionCredentialStorage(disk).read();
    expect(restored?.accessToken, 'legacy');
    expect(restored?.refreshToken, 'legacy-refresh');
  });
  test('slow earlier biometric save cannot overwrite a rotated token pair',
      () async {
    final disk = _SlowStorage();
    final storage = BiometricCredentialStorage(disk);
    final first = storage.save(
        token: 'old', refreshToken: 'old-refresh', email: 'test@example.test');
    final second = storage.save(
        token: 'new', refreshToken: 'new-refresh', email: 'test@example.test');
    disk.firstWrite.complete();
    await Future.wait([first, second]);
    expect(await storage.readToken(), 'new');
    expect(await storage.readRefreshToken(), 'new-refresh');
  });
  test('logout clears a session even when a save is still pending', () async {
    final disk = _SlowStorage();
    final storage = SessionCredentialStorage(disk);
    final save = storage.save(const StoredSession(
        accessToken: 'old',
        refreshToken: 'old-refresh',
        email: 'test@example.test',
        userName: 'Tester'));
    final clear = storage.clear();
    disk.firstWrite.complete();
    await Future.wait([save, clear]);
    expect(await storage.read(), isNull);
    expect(disk.data, isEmpty);
  });
}
