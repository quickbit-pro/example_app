import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../flavors.dart';
import '../../features/auth/application/biometric_providers.dart';
import '../../features/auth/data/session_credential_storage.dart';
import 'auth_token_provider.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  return AppConfig.fromEnvironment();
});

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  // Rebuild the HTTP/data provider graph at explicit session boundaries. We
  // deliberately do not watch the access token itself because token refresh
  // occurs inside this provider's interceptor.
  final generation = ref.watch(authSessionGenerationProvider);
  var active = true;
  ref.onDispose(() => active = false);
  Future<_RefreshedSession?>? refreshInFlight;

  final dio = Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = ref.read(authTokenProvider);
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final request = error.requestOptions;
        final sensitiveRequest = request.extra['sensitiveRequest'] == true;
        final status = error.response?.statusCode;
        if (!active || ref.read(authSessionGenerationProvider) != generation) {
          handler.next(error);
          return;
        }
        // A suspended PWA or a radio handover may fail its first read. Retry
        // once after a short delay; never replay payments, uploads or refresh
        // token rotation, and never retry across a logout/new login boundary.
        if (_canRetryRead(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (active &&
              ref.read(authSessionGenerationProvider) == generation &&
              request.cancelToken?.isCancelled != true) {
            request.extra['transientReadRetried'] = true;
            try {
              handler.resolve(await dio.fetch<Object?>(request));
            } on DioException catch (retryError) {
              handler.next(retryError);
            }
            return;
          }
          handler.next(error);
          return;
        }
        if (status == 401 && request.extra['skipAuthRefresh'] != true) {
          final currentToken = ref.read(authTokenProvider);
          _RefreshedSession? refreshed;
          try {
            // A late 401 can belong to a token already replaced by another
            // request. Retry it with the current token without rotating again.
            if (currentToken != null &&
                request.headers['Authorization'] != 'Bearer $currentToken') {
              refreshed = _RefreshedSession(currentToken);
            } else {
              refreshed = await (refreshInFlight ??= _refreshAccessToken(
                ref,
                config,
                isCurrent: () =>
                    active &&
                    ref.read(authSessionGenerationProvider) == generation,
              ).whenComplete(() => refreshInFlight = null));
            }
          } on DioException catch (refreshError) {
            // Offline/timeouts/server outages do not revoke a saved session.
            handler.next(refreshError);
            return;
          }
          if (!active ||
              ref.read(authSessionGenerationProvider) != generation) {
            handler.next(error);
            return;
          }
          if (refreshed != null) {
            request
              ..headers['Authorization'] = 'Bearer ${refreshed.accessToken}'
              ..extra['skipAuthRefresh'] = true;

            try {
              // Sending consumes FormData and its files. Recreate their streams
              // for the authorized retry, including late 401 responses.
              final data = request.data;
              if (data is FormData) {
                request.data = data.clone();
              }
              handler.resolve(await dio.fetch<Object?>(request));
              return;
            } on DioException catch (retryError) {
              error = retryError;
            }
          }
        }

        // A rejected protected request means the in-memory session is no
        // longer usable. Clearing both tokens also updates AuthController,
        // which lets GoRouter return the user to sign-in instead of leaving a
        // desktop shell around a permanent 401 error card.
        if (error.response?.statusCode == 401) {
          ref.read(authTokenProvider.notifier).state = null;
          ref.read(refreshTokenProvider.notifier).state = null;
        }

        final loggedStatus = error.response?.statusCode;
        final statusText = loggedStatus == null ? '' : ' HTTP $loggedStatus.';
        final detail = sensitiveRequest
            ? ''
            : _responseErrorText(error.response?.data) ?? error.message ?? '';
        final loggedTarget = sensitiveRequest ? request.path : request.uri;
        final loggedDetail = sensitiveRequest
            ? ' Sensitive request details omitted.'
            : ' ${error.response?.data ?? detail}';
        debugPrint(
          '${request.method} $loggedTarget failed$statusText$loggedDetail',
        );

        handler.next(
          DioException(
            requestOptions: request,
            response: error.response,
            type: error.type,
            error: error.error,
            stackTrace: error.stackTrace,
            message: sensitiveRequest
                ? '${request.method} ${request.path} failed.$statusText'
                : '${request.method} ${request.uri} failed.$statusText $detail',
          ),
        );
      },
    ),
  );

  return dio;
});

bool _canRetryRead(DioException error) {
  final request = error.requestOptions;
  if (request.method != 'GET' ||
      request.data != null ||
      request.extra['transientReadRetried'] == true ||
      request.cancelToken?.isCancelled == true) {
    return false;
  }
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.receiveTimeout ||
      const {502, 503, 504}.contains(error.response?.statusCode);
}

Future<_RefreshedSession?> _refreshAccessToken(Ref ref, AppConfig config,
    {required bool Function() isCurrent}) async {
  final refreshToken = ref.read(refreshTokenProvider);
  if (refreshToken == null || refreshToken.isEmpty) {
    return null;
  }

  try {
    final refreshDio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );
    final response = await refreshDio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    final data = response.data;
    final accessToken = data?['accessToken'];
    final nextRefreshToken = data?['refreshToken'];
    if (accessToken is! String || accessToken.isEmpty) {
      return null;
    }

    if (!isCurrent()) return null;
    if (nextRefreshToken is String && nextRefreshToken.isNotEmpty) {
      final storage = ref.read(sessionStorageProvider);
      final saved = await storage.read();
      if (!isCurrent()) return null;
      if (saved != null) {
        // Complete the durable token rotation before retrying API requests.
        // An immediate PWA close must not restore the consumed refresh token.
        await storage.save(StoredSession(
          accessToken: accessToken,
          refreshToken: nextRefreshToken,
          email: saved.email,
          userName: saved.userName,
        ));
      }
      if (!isCurrent()) return null;
    }
    ref.read(authTokenProvider.notifier).state = accessToken;
    if (nextRefreshToken is String && nextRefreshToken.isNotEmpty) {
      ref.read(refreshTokenProvider.notifier).state = nextRefreshToken;
      // Keep the biometric copy current so a later fingerprint sign-in
      // exchanges a token that is still valid.
      await _syncBiometricTokens(ref, accessToken, nextRefreshToken,
          isCurrent: isCurrent);
    }

    return _RefreshedSession(accessToken);
  } on DioException catch (error) {
    if (!isCurrent()) return null;
    if (error.response?.statusCode != 401 &&
        error.response?.statusCode != 403) {
      rethrow;
    }
    ref.read(authTokenProvider.notifier).state = null;
    ref.read(refreshTokenProvider.notifier).state = null;
    return null;
  } on FormatException {
    if (!isCurrent()) return null;
    ref.read(authTokenProvider.notifier).state = null;
    ref.read(refreshTokenProvider.notifier).state = null;
    return null;
  }
}

class _RefreshedSession {
  const _RefreshedSession(this.accessToken);

  final String accessToken;
}

String? _responseErrorText(Object? data) {
  if (data == null) {
    return null;
  }

  if (data is Map) {
    for (final key in const [
      'detail',
      'Detail',
      'message',
      'Message',
      'title',
      'Title',
      'error',
      'Error',
    ]) {
      final value = data[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) {
        return text;
      }
    }

    final errors = data['errors'] ?? data['Errors'];
    if (errors is Map && errors.isNotEmpty) {
      final first = errors.values.first;
      if (first is Iterable && first.isNotEmpty) {
        return first.first?.toString();
      }
      return first?.toString();
    }
  }

  return data.toString();
}

Future<void> _syncBiometricTokens(
  Ref ref,
  String accessToken,
  String refreshToken, {
  required bool Function() isCurrent,
}) async {
  try {
    final storage = ref.read(biometricStorageProvider);
    if (!await storage.isEnabled()) return;
    final email = await storage.readEmail() ?? '';
    final userName = await storage.readUserName() ?? '';
    if (!isCurrent() || ref.read(authTokenProvider) != accessToken) return;
    await storage.save(
      token: accessToken,
      refreshToken: refreshToken,
      email: email,
      userName: userName,
    );
  } catch (_) {
    // Never let bookkeeping break the request that triggered the refresh.
  }
}
