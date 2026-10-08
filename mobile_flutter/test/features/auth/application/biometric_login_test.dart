import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/auth/data/biometric_credential_storage.dart';
import 'package:mobile_flutter/features/auth/data/session_credential_storage.dart';
import 'package:mobile_flutter/features/notifications/notifications.dart';

class _Biometrics extends BiometricAuthenticator {
  int prompts = 0;
  int cancellations = 0;
  @override
  Future<void> cancel() async {
    cancellations++;
  }

  Completer<BiometricAuthResult> result = Completer();
  @override
  Future<BiometricCapability> capability() async => const BiometricCapability(
      available: true, types: [], reason: BiometricUnavailableReason.none);
  @override
  Future<BiometricAuthResult> authenticate({required String reason}) {
    prompts++;
    return result.future;
  }
}

class _Credentials extends BiometricCredentialStorage {
  bool enabled = true;
  Completer<void>? disableGate;
  final disableStarted = Completer<void>();
  String token = 'old';
  String refresh = 'refresh';
  @override
  Future<bool> isEnabled() async => enabled;
  @override
  Future<bool> hasStoredToken() async => token.isNotEmpty;
  @override
  Future<String?> readToken() async => token;
  @override
  Future<String?> readRefreshToken() async => refresh;
  @override
  Future<String?> readEmail() async => 'test@example.test';
  @override
  Future<String?> readUserName() async => 'Tester';
  @override
  Future<void> disable() async {
    if (!disableStarted.isCompleted) disableStarted.complete();
    if (disableGate != null) await disableGate!.future;
    enabled = false;
    token = refresh = '';
  }

  @override
  Future<void> save(
      {required String token,
      String refreshToken = '',
      required String email,
      String userName = ''}) async {
    enabled = true;
    this.token = token;
    refresh = refreshToken;
  }
}

class _SessionStore extends SessionCredentialStorage {
  StoredSession? saved;
  int clears = 0;
  @override
  Future<void> clear() async {
    clears++;
    saved = null;
  }

  @override
  Future<StoredSession?> read() async => null;
  @override
  Future<void> save(StoredSession session) async {
    saved = session;
  }
}

class _Api extends AuthApi {
  _Api() : super(Dio());
  @override
  Future<void> logout({String? refreshToken}) async {}
  int refreshes = 0;
  DioException? refreshError;
  Completer<AuthSession>? refreshResult;
  @override
  Future<LoginOutcome> signIn(
          {required String email, required String password}) async =>
      const LoginOutcome.signedIn(AuthSession(
          accessToken: 'password-access',
          refreshToken: 'password-refresh',
          email: 'test@example.test',
          userName: 'Tester'));
  @override
  Future<AuthSession> refresh({required String refreshToken}) async {
    refreshes++;
    if (refreshError != null) throw refreshError!;
    if (refreshResult != null) return refreshResult!.future;
    return const AuthSession(
        accessToken: 'fresh',
        refreshToken: 'rotated',
        email: 'test@example.test',
        userName: 'Tester');
  }
}

void main() {
  test('device reset finishes cleanup before password login and stays disabled',
      () async {
    final credentials = _Credentials()..disableGate = Completer<void>();
    final biometrics = _Biometrics();
    final session = _SessionStore();
    final container = ProviderContainer(overrides: [
      biometricAuthenticatorProvider.overrideWithValue(biometrics),
      biometricStorageProvider.overrideWithValue(credentials),
      sessionStorageProvider.overrideWithValue(session),
      authApiProvider.overrideWithValue(_Api()),
      pushNotificationServiceProvider
          .overrideWithValue(PushNotificationService(Dio())),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final controller = container.read(authControllerProvider.notifier);
    await controller.login(
        email: 'test@example.test', password: 'test-password');
    expect((await container.read(biometricEnrollmentProvider.future)).canUnlock,
        isTrue);
    final reset = controller.logout(clearBiometric: true);
    await credentials.disableStarted.future;
    expect(container.read(authControllerProvider).isLoading, isTrue);
    expect(container.read(authTokenProvider), isNull);
    credentials.disableGate!.complete();
    await reset;
    expect(container.read(authControllerProvider).requireValue.isAuthenticated,
        isFalse);
    expect(session.saved, isNull);
    expect((await container.read(biometricEnrollmentProvider.future)).canUnlock,
        isFalse);
    expect(biometrics.prompts, 0);
    await controller.login(
        email: 'test@example.test', password: 'test-password');
    expect(container.read(authControllerProvider).requireValue.isAuthenticated,
        isTrue);
    expect(credentials.enabled, isFalse);
    expect(credentials.token, isEmpty);
    await controller.enableBiometricForCurrentSession();
    expect((await container.read(biometricEnrollmentProvider.future)).canUnlock,
        isTrue);
    expect(credentials.token, 'password-access');
  });

  for (final stage in ['prompt', 'refresh', 'rejected refresh']) {
    test('password login wins over a cancelled biometric $stage', () async {
      final biometrics = _Biometrics();
      final credentials = _Credentials();
      final session = _SessionStore();
      final api = _Api()..refreshResult = Completer<AuthSession>();
      final container = ProviderContainer(overrides: [
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        biometricStorageProvider.overrideWithValue(credentials),
        sessionStorageProvider.overrideWithValue(session),
        authApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      final unlock = controller.loginWithBiometrics(reason: 'Unlock');
      if (stage != 'prompt') {
        biometrics.result.complete(BiometricAuthResult.success);
      }
      await Future<void>.delayed(Duration.zero);
      expect(container.read(authControllerProvider).isLoading, isTrue);
      expect(stage == 'prompt' ? biometrics.prompts : api.refreshes, 1);
      controller.cancelBiometricLogin();
      expect(container.read(authControllerProvider).isLoading, isFalse);
      expect(biometrics.cancellations, 1);
      await unlock;
      await controller.login(
          email: 'test@example.test', password: 'test-password');
      if (stage == 'prompt') {
        biometrics.result.complete(BiometricAuthResult.success);
      } else if (stage == 'rejected refresh') {
        final request = RequestOptions(path: '/auth/refresh');
        api.refreshResult!.completeError(DioException(
            requestOptions: request,
            response: Response(requestOptions: request, statusCode: 401)));
      } else {
        api.refreshResult!.complete(const AuthSession(
            accessToken: 'late-access',
            refreshToken: 'late-refresh',
            email: 'test@example.test',
            userName: 'Tester'));
      }
      await Future<void>.delayed(Duration.zero);
      expect(
          container
              .read(authControllerProvider)
              .requireValue
              .session!
              .accessToken,
          'password-access');
      expect(container.read(authTokenProvider), 'password-access');
      expect(container.read(refreshTokenProvider), 'password-refresh');
      expect(session.saved!.accessToken, 'password-access');
      expect(credentials.token, 'password-access');
      expect(credentials.enabled, isTrue);
      expect(session.clears, 0);
      if (stage == 'prompt') expect(api.refreshes, 0);
    });
  }

  testWidgets('stalled unlock times out and ignores late biometric success',
      (tester) async {
    final biometrics = _Biometrics();
    final api = _Api();
    final container = ProviderContainer(overrides: [
      biometricAuthenticatorProvider.overrideWithValue(biometrics),
      biometricStorageProvider.overrideWithValue(_Credentials()),
      sessionStorageProvider.overrideWithValue(_SessionStore()),
      authApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final unlock = container
        .read(authControllerProvider.notifier)
        .loginWithBiometrics(reason: 'Unlock');
    await tester.pump();
    expect(biometrics.prompts, 1);
    await tester.pump(const Duration(seconds: 45));
    await unlock;
    expect(container.read(authControllerProvider).isLoading, isFalse);
    expect(
        container.read(authControllerProvider).error,
        isA<BiometricLoginException>()
            .having((e) => e.kind, 'failure', BiometricLoginFailure.timedOut));
    expect(biometrics.cancellations, 1);
    biometrics.result.complete(BiometricAuthResult.success);
    await tester.pump();
    expect(container.read(authTokenProvider), isNull);
    expect(api.refreshes, 0);
  });

  for (final status in [401, 403, 503, null]) {
    test('biometric refresh status $status clears only expired credentials',
        () async {
      final biometrics = _Biometrics();
      final credentials = _Credentials();
      final session = _SessionStore()
        ..saved = const StoredSession(
            accessToken: 'old',
            refreshToken: 'refresh',
            email: 'test@example.test',
            userName: 'Tester');
      final request = RequestOptions(path: '/auth/refresh');
      final api = _Api()
        ..refreshError = DioException(
          requestOptions: request,
          type: status == null
              ? DioExceptionType.connectionError
              : DioExceptionType.badResponse,
          response: status == null
              ? null
              : Response(requestOptions: request, statusCode: status),
        );
      final container = ProviderContainer(overrides: [
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        biometricStorageProvider.overrideWithValue(credentials),
        sessionStorageProvider.overrideWithValue(session),
        authApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final unlock = container
          .read(authControllerProvider.notifier)
          .loginWithBiometrics(reason: 'Unlock');
      biometrics.result.complete(BiometricAuthResult.success);
      await unlock;
      final expired = status == 401 || status == 403;
      expect(container.read(authControllerProvider).hasError, isTrue);
      expect(container.read(authTokenProvider), isNull);
      expect(container.read(refreshTokenProvider), isNull);
      expect(credentials.enabled, !expired);
      expect(session.clears, expired ? 1 : 0);
      expect(session.saved == null, expired);
      expect(
          (await container.read(biometricEnrollmentProvider.future)).canUnlock,
          !expired);
      if (expired) {
        expect(
            container.read(authControllerProvider).error,
            isA<BiometricLoginException>().having((e) => e.kind, 'failure',
                BiometricLoginFailure.noStoredCredentials));
      }
    });
  }

  test('password fallback updates previously enabled biometric credentials',
      () async {
    final credentials = _Credentials();
    final container = ProviderContainer(overrides: [
      biometricStorageProvider.overrideWithValue(credentials),
      sessionStorageProvider.overrideWithValue(_SessionStore()),
      authApiProvider.overrideWithValue(_Api()),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container
        .read(authControllerProvider.notifier)
        .login(email: 'test@example.test', password: 'test-password');
    expect(container.read(authControllerProvider).requireValue.isAuthenticated,
        isTrue);
    expect(credentials.token, 'password-access');
    expect(credentials.refresh, 'password-refresh');
  });

  test('immediate reopen unlocks a valid session without rotating again',
      () async {
    final biometrics = _Biometrics();
    final credentials = _Credentials();
    final claims = base64Url.encode(utf8.encode(jsonEncode({
      'exp':
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000
    })));
    credentials.token = 'header.$claims.signature';
    final api = _Api();
    final container = ProviderContainer(overrides: [
      biometricAuthenticatorProvider.overrideWithValue(biometrics),
      biometricStorageProvider.overrideWithValue(credentials),
      sessionStorageProvider.overrideWithValue(_SessionStore()),
      authApiProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final unlock = container
        .read(authControllerProvider.notifier)
        .loginWithBiometrics(reason: 'Unlock');
    biometrics.result.complete(BiometricAuthResult.success);
    await unlock;
    expect(api.refreshes, 0);
    expect(biometrics.prompts, 1);
    expect(container.read(authControllerProvider).requireValue.isAuthenticated,
        isTrue);
  });
  for (final cancelFirst in [false, true]) {
    test(
        'biometric login needs no password and coalesces taps, retry=$cancelFirst',
        () async {
      final biometrics = _Biometrics();
      final credentials = _Credentials();
      final session = _SessionStore();
      final api = _Api();
      final container = ProviderContainer(overrides: [
        biometricAuthenticatorProvider.overrideWithValue(biometrics),
        biometricStorageProvider.overrideWithValue(credentials),
        sessionStorageProvider.overrideWithValue(session),
        authApiProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final controller = container.read(authControllerProvider.notifier);
      if (cancelFirst) {
        final cancelled = controller.loginWithBiometrics(reason: 'Sign in');
        biometrics.result.complete(BiometricAuthResult.cancelled);
        await cancelled;
        expect(container.read(authControllerProvider).hasError, isTrue);
        biometrics.result = Completer();
      }
      final first = controller.loginWithBiometrics(reason: 'Sign in');
      final duplicate = controller.loginWithBiometrics(reason: 'Sign in');
      expect(identical(first, duplicate), isTrue);
      biometrics.result.complete(BiometricAuthResult.success);
      await Future.wait([first, duplicate]);
      expect(api.refreshes, 1);
      expect(biometrics.prompts, cancelFirst ? 2 : 1);
      expect(
          container.read(authControllerProvider).requireValue.isAuthenticated,
          isTrue);
      expect(credentials.refresh, 'rotated');
      expect(session.saved?.refreshToken, 'rotated');
    });
  }
}
