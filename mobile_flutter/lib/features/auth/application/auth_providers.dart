import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/auth_token_provider.dart';
import '../../../core/api/dio_provider.dart';
import '../data/auth_api.dart';
import '../data/biometric_authenticator.dart';
import '../data/session_credential_storage.dart';
export '../data/session_credential_storage.dart' show sessionStorageProvider;
import '../../notifications/notifications.dart';
import 'biometric_providers.dart';

/// Devices signed in to this account; refreshed after every revocation.
final authSessionsProvider =
    FutureProvider.autoDispose<List<AuthDeviceSession>>((ref) {
  return ref.watch(authApiProvider).listSessions();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return AuthApi(ref.watch(dioProvider));
});

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthState {
  const AuthState({
    this.session,
    this.pendingTwoFactorChallenge,
    this.biometricLocked = false,
  });

  final AuthSession? session;

  /// A saved session exists but the device biometric must be confirmed
  /// before it is used (PWA launch with biometrics enabled).
  final bool biometricLocked;

  /// Set after a correct password on a 2FA account; the UI must collect a
  /// code and call [AuthController.completeTwoFactor].
  final String? pendingTwoFactorChallenge;

  bool get isAuthenticated => session != null;
  bool get requiresTwoFactor => pendingTwoFactorChallenge != null;
}

/// Account security summary (2FA, duress password, password age).
final accountSecurityProvider =
    FutureProvider.autoDispose<AccountSecurity>((ref) {
  return ref.watch(authApiProvider).getSecurity();
});

/// Thrown when biometric unlock is requested but unavailable / refused. The
/// UI maps these to actionable copy.
class BiometricLoginException implements Exception {
  const BiometricLoginException(this.kind, [this.message]);

  final BiometricLoginFailure kind;
  final String? message;

  @override
  String toString() => message ?? kind.name;
}

enum BiometricLoginFailure {
  notEnrolled,
  noStoredCredentials,
  cancelled,
  lockedOut,
  timedOut,
  failed,
}

class AuthController extends AsyncNotifier<AuthState> {
  bool _disposed = false;
  bool _loggingOut = false;
  @override
  Future<AuthState> build() async {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      _biometricAttempt?.cancel();
    });
    ref.listen<String?>(authTokenProvider, (previous, next) {
      if (previous != null &&
          next == null &&
          state.valueOrNull != null &&
          !_loggingOut) {
        ref.read(refreshTokenProvider.notifier).state = null;
        state = const AsyncData(AuthState());
        ref.read(sessionStorageProvider).clear();
        return;
      }
      // Token refreshes happen inside the HTTP layer; keep the stored
      // session in step so the next restart uses the newest pair.
      if (next != null && next.isNotEmpty) _persistCurrentSession();
    });
    ref.listen<String?>(refreshTokenProvider, (previous, next) {
      if (next != null && next.isNotEmpty) _persistCurrentSession();
    });

    final stored = await ref.read(sessionStorageProvider).read();
    // On the web the saved session stays sealed until the passkey prompt
    // succeeds; the unlock then rotates the token pair before entering.
    if (kIsWeb && await _biometricLockRequired()) {
      _lockedSession = stored;
      return const AuthState(biometricLocked: true);
    }
    if (stored == null) return const AuthState();
    ref.read(authTokenProvider.notifier).state = stored.accessToken;
    ref.read(refreshTokenProvider.notifier).state = stored.refreshToken;
    _advanceSessionGeneration();
    return AuthState(
      session: AuthSession(
        accessToken: stored.accessToken,
        refreshToken: stored.refreshToken,
        userName: stored.userName,
        email: stored.email,
      ),
    );
  }

  /// Session held back at launch until biometrics confirm the customer.
  StoredSession? _lockedSession;

  Future<bool> _biometricLockRequired() async {
    try {
      final storage = ref.read(biometricStorageProvider);
      return await storage.isEnabled() && await storage.hasStoredToken();
    } catch (_) {
      return false;
    }
  }

  bool _persistenceScheduled = false;
  Future<void> _persistence = Future.value();

  void _persistCurrentSession() {
    if (_persistenceScheduled) return;
    _persistenceScheduled = true;
    // Access and refresh tokens are updated together in one synchronous turn.
    // Persist the completed pair, never the intermediate combination.
    scheduleMicrotask(() {
      _persistenceScheduled = false;
      _persistence =
          _persistence.then((_) => _saveCurrentSession()).catchError((_) {});
    });
  }

  Future<void> _saveCurrentSession() async {
    if (_disposed) return;
    final session = state.valueOrNull?.session;
    final token = ref.read(authTokenProvider);
    if (session == null || token == null || token.isEmpty) return;
    final refreshToken = ref.read(refreshTokenProvider) ?? '';
    final generation = ref.read(authSessionGenerationProvider);
    await ref.read(sessionStorageProvider).save(
          StoredSession(
            accessToken: token,
            refreshToken: refreshToken,
            email: session.email,
            userName: session.userName,
          ),
        );
    // Refresh tokens are single use: keep the biometric copy current so the
    // next launch unlock does not present a revoked token.
    if (_disposed) return;
    final biometricStorage = ref.read(biometricStorageProvider);
    await biometricStorage.isEnabled().then((enabled) async {
      if (!enabled ||
          refreshToken.isEmpty ||
          _disposed ||
          ref.read(authSessionGenerationProvider) != generation ||
          ref.read(authTokenProvider) != token) {
        return;
      }
      await biometricStorage.save(
        token: token,
        refreshToken: refreshToken,
        email: session.email,
        userName: session.userName,
      );
    }).catchError((_) {});
  }

  /// Standard email/password login. Behavior preserved for callers.
  ///
  /// When [persistForBiometric] is `true` and the login succeeds, the access
  /// token is also written to the platform keystore so a subsequent
  /// [loginWithBiometrics] call can rehydrate the session without the
  /// password.
  Future<void> login({
    required String email,
    required String password,
    bool persistForBiometric = false,
  }) async {
    cancelBiometricLogin();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final outcome = await ref.read(authApiProvider).signIn(
            email: email,
            password: password,
          );
      if (outcome.requiresTwoFactor) {
        _pendingEmail = email;
        _pendingPersistForBiometric = persistForBiometric;
        return AuthState(pendingTwoFactorChallenge: outcome.challengeToken);
      }
      final session = outcome.session!;
      return _finishLogin(
        session,
        email: email,
        persistForBiometric: persistForBiometric,
      );
    });
  }

  String _pendingEmail = '';
  bool _pendingPersistForBiometric = false;

  /// Second sign-in step for 2FA accounts.
  Future<void> completeTwoFactor(String code) async {
    final challenge = state.valueOrNull?.pendingTwoFactorChallenge;
    if (challenge == null) return;
    final email = _pendingEmail;
    final persist = _pendingPersistForBiometric;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      try {
        final session = await ref.read(authApiProvider).completeTwoFactor(
              challengeToken: challenge,
              code: code,
            );
        // Awaited so a failure while finishing the login lands in the catch
        // below and keeps the challenge, instead of escaping the try.
        return await _finishLogin(
          session,
          email: email,
          persistForBiometric: persist,
        );
      } catch (_) {
        // Keep the challenge so the customer can retry the code.
        state = AsyncData(AuthState(pendingTwoFactorChallenge: challenge));
        rethrow;
      }
    });
  }

  void cancelTwoFactor() {
    _pendingEmail = '';
    state = const AsyncData(AuthState());
  }

  Future<AuthState> _finishLogin(
    AuthSession session, {
    required String email,
    required bool persistForBiometric,
  }) async {
    {
      _lockedSession = null;
      ref.read(authTokenProvider.notifier).state = session.accessToken;
      ref.read(refreshTokenProvider.notifier).state = session.refreshToken;
      _advanceSessionGeneration();
      await ref.read(sessionStorageProvider).save(
            StoredSession(
              accessToken: session.accessToken,
              refreshToken: session.refreshToken,
              email: session.email.isEmpty ? email : session.email,
              userName: session.userName,
            ),
          );

      final biometricStorage = ref.read(biometricStorageProvider);
      final enrolled =
          await biometricStorage.isEnabled().catchError((_) => false);
      final savedEmail = enrolled ? await biometricStorage.readEmail() : null;
      final loginEmail = session.email.isEmpty ? email : session.email;
      if (persistForBiometric ||
          (enrolled && savedEmail?.toLowerCase() == loginEmail.toLowerCase())) {
        await biometricStorage.save(
          token: session.accessToken,
          refreshToken: session.refreshToken,
          email: session.email.isEmpty ? email : session.email,
          userName: session.userName,
        );
        ref.invalidate(biometricEnrollmentProvider);
      } else if (enrolled) {
        // Never leave another user's biometric tokens attached to this login.
        await biometricStorage.disable();
        ref.invalidate(biometricEnrollmentProvider);
      }

      return AuthState(session: session);
    }
  }

  /// Prompts the OS biometric sheet, then hydrates the session from the
  /// securely-stored token. Does not call the password endpoint.
  Future<void>? _biometricLogin;
  _BiometricLoginAttempt? _biometricAttempt;

  Future<void> loginWithBiometrics({required String reason}) {
    if (_biometricLogin != null) return _biometricLogin!;
    final attempt = _BiometricLoginAttempt();
    _biometricAttempt = attempt;
    return _biometricLogin =
        _performBiometricLogin(attempt, reason: reason).whenComplete(() {
      if (identical(_biometricAttempt, attempt)) {
        _biometricAttempt = null;
        _biometricLogin = null;
      }
    });
  }

  /// Password sign-in must remain reachable even if the device prompt hangs.
  void cancelBiometricLogin() {
    final attempt = _biometricAttempt;
    if (attempt == null) return;
    attempt.cancel();
    _biometricAttempt = null;
    _biometricLogin = null;
    unawaited(ref.read(biometricAuthenticatorProvider).cancel());
    state = const AsyncData(AuthState());
  }

  Future<void> _performBiometricLogin(_BiometricLoginAttempt attempt,
      {required String reason}) async {
    state = const AsyncLoading();
    final outcome = await AsyncValue.guard(
        () => _restoreBiometricSession(attempt, reason: reason).timeout(
              const Duration(seconds: 45),
              onTimeout: () {
                attempt.cancel();
                if (!_disposed && identical(_biometricAttempt, attempt)) {
                  unawaited(ref.read(biometricAuthenticatorProvider).cancel());
                }
                throw const BiometricLoginException(
                  BiometricLoginFailure.timedOut,
                  'Unlock timed out. Sign in with your password.',
                );
              },
            ));
    // A cancelled prompt/refresh may finish after a new password login.
    if (!_disposed && identical(_biometricAttempt, attempt)) state = outcome;
  }

  Future<AuthState> _restoreBiometricSession(_BiometricLoginAttempt attempt,
      {required String reason}) async {
    final storage = ref.read(biometricStorageProvider);
    if (!await attempt.wait(storage.isEnabled()) ||
        !await attempt.wait(storage.hasStoredToken())) {
      throw const BiometricLoginException(
        BiometricLoginFailure.noStoredCredentials,
        'Biometric sign-in is not set up on this device.',
      );
    }

    final auth = ref.read(biometricAuthenticatorProvider);
    final capability = await attempt.wait(auth.capability());
    if (!capability.available) {
      throw const BiometricLoginException(
        BiometricLoginFailure.notEnrolled,
        'No biometrics are enrolled on this device.',
      );
    }

    final result = await attempt.wait(auth.authenticate(reason: reason));
    switch (result) {
      case BiometricAuthResult.success:
        break;
      case BiometricAuthResult.cancelled:
        throw const BiometricLoginException(BiometricLoginFailure.cancelled);
      case BiometricAuthResult.lockedOut:
        throw const BiometricLoginException(
          BiometricLoginFailure.lockedOut,
          'Too many failed attempts. Try again later or use your password.',
        );
      case BiometricAuthResult.failed:
        throw const BiometricLoginException(
          BiometricLoginFailure.failed,
          'Biometric verification failed.',
        );
    }

    // Prefer the pair from the sealed launch session: it is the newest
    // after in-app refreshes rotated the biometric copy.
    final locked = _lockedSession;
    final storedToken =
        locked?.accessToken ?? await attempt.wait(storage.readToken());
    final storedRefresh = locked?.refreshToken.isNotEmpty == true
        ? locked!.refreshToken
        : await attempt.wait(storage.readRefreshToken()) ?? '';
    final storedEmail = locked?.email.isNotEmpty == true
        ? locked!.email
        : await attempt.wait(storage.readEmail()) ?? '';
    final storedName = locked?.userName.isNotEmpty == true
        ? locked!.userName
        : await attempt.wait(storage.readUserName()) ?? '';
    if (storedToken == null || storedToken.isEmpty) {
      throw const BiometricLoginException(
        BiometricLoginFailure.noStoredCredentials,
      );
    }

    // Reopening immediately can reuse an unexpired access token after the
    // biometric check. Rotate expired tokens before loading protected data.
    var token = storedToken;
    var refreshToken = storedRefresh;
    var email = storedEmail;
    var userName = storedName;
    if (refreshToken.isNotEmpty && !_accessTokenStillValid(token)) {
      try {
        final fresh = await attempt.wait(
            ref.read(authApiProvider).refresh(refreshToken: refreshToken));
        token = fresh.accessToken;
        refreshToken = fresh.refreshToken;
        if (fresh.email.isNotEmpty) email = fresh.email;
        if (fresh.userName.isNotEmpty) userName = fresh.userName;
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        if (status == 401 || status == 403) {
          await _clearExpiredBiometricSession(attempt);
          throw const BiometricLoginException(
            BiometricLoginFailure.noStoredCredentials,
            'Your saved sign-in has expired. Sign in with your password and turn biometrics on again.',
          );
        }
        rethrow;
      }
    }

    await attempt.wait(ref.read(sessionStorageProvider).save(
          StoredSession(
            accessToken: token,
            refreshToken: refreshToken,
            email: email,
            userName: userName,
          ),
        ));
    await attempt.wait(storage.save(
      token: token,
      refreshToken: refreshToken,
      email: email,
      userName: userName,
    ));
    _lockedSession = null;
    ref.read(authTokenProvider.notifier).state = token;
    ref.read(refreshTokenProvider.notifier).state = refreshToken;
    _advanceSessionGeneration();

    return AuthState(
      session: AuthSession(
        accessToken: token,
        refreshToken: refreshToken,
        userName: userName,
        email: email,
      ),
    );
  }

  Future<void> _clearExpiredBiometricSession(
      _BiometricLoginAttempt attempt) async {
    _lockedSession = null;
    ref.read(authTokenProvider.notifier).state = null;
    ref.read(refreshTokenProvider.notifier).state = null;
    _advanceSessionGeneration();
    await attempt.wait(ref.read(sessionStorageProvider).clear());
    await attempt.wait(ref.read(biometricStorageProvider).disable());
    ref.invalidate(biometricEnrollmentProvider);
  }

  /// Convenience: enable biometric login using the current live session
  /// token (called from the profile/settings toggle).
  Future<void> enableBiometricForCurrentSession({String? email}) async {
    final session = state.valueOrNull?.session;
    final token = ref.read(authTokenProvider);
    if (session == null && (token == null || token.isEmpty)) {
      return;
    }
    await ref.read(biometricStorageProvider).save(
          token: token ?? session!.accessToken,
          refreshToken:
              ref.read(refreshTokenProvider) ?? session?.refreshToken ?? '',
          email: session?.email ?? (email ?? ''),
          userName: session?.userName ?? '',
        );
    ref.invalidate(biometricEnrollmentProvider);
  }

  Future<void> disableBiometric() async {
    ref.read(biometricAuthenticatorProvider).forget();
    await ref.read(biometricStorageProvider).disable();
    ref.invalidate(biometricEnrollmentProvider);
  }

  Future<void> logout({bool clearBiometric = false}) async {
    cancelBiometricLogin();
    _lockedSession = null;
    _loggingOut = true;
    // Keep sign-in blocked until local credential cleanup completes. The token
    // listener must not publish a logged-out state halfway through cleanup.
    state = const AsyncLoading();
    try {
      await ref
          .read(pushNotificationServiceProvider)
          .deactivate()
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      // Logging out must not be blocked by a slow notification unregister call.
    }
    if (ref.read(authTokenProvider) != null) {
      try {
        await ref
            .read(authApiProvider)
            .logout(refreshToken: ref.read(refreshTokenProvider))
            .timeout(const Duration(seconds: 3));
      } catch (_) {
        // Server-side revocation is best effort; local sign-out always wins.
      }
    }
    ref.read(authTokenProvider.notifier).state = null;
    ref.read(refreshTokenProvider.notifier).state = null;
    _advanceSessionGeneration();
    try {
      // Drain session persistence so an older token save cannot re-enable
      // biometric enrollment after this device has been reset.
      await _persistence;
      await ref.read(sessionStorageProvider).clear();
      if (clearBiometric) await disableBiometric();
    } finally {
      _loggingOut = false;
      state = const AsyncData(AuthState());
    }
  }

  void _advanceSessionGeneration() {
    final notifier = ref.read(authSessionGenerationProvider.notifier);
    notifier.state = notifier.state + 1;
  }
}

/// Completes pending waits on cancellation and blocks their late side effects.
class _BiometricLoginAttempt {
  final _cancelled = Completer<void>();

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  Future<T> wait<T>(Future<T> operation) async {
    final result = await Future.any<T>([
      operation,
      _cancelled.future.then<T>((_) =>
          throw const BiometricLoginException(BiometricLoginFailure.cancelled)),
    ]);
    if (_cancelled.isCompleted) {
      throw const BiometricLoginException(BiometricLoginFailure.cancelled);
    }
    return result;
  }
}

// This only decides whether a refresh is needed. The server still validates
// the token on every protected request; decoding does not authenticate it.
bool _accessTokenStillValid(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    final claims =
        jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
            as Map<String, dynamic>;
    final expires = claims['exp'];
    return expires is num &&
        expires * 1000 >
            DateTime.now()
                .add(const Duration(seconds: 30))
                .millisecondsSinceEpoch;
  } catch (_) {
    return false;
  }
}
