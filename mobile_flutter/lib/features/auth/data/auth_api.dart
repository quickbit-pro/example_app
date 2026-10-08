import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.refreshToken,
    required this.userName,
    required this.email,
  });

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final token = json['accessToken'] ?? json['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('Login response did not include a token');
    }
    final refreshToken = json['refreshToken'];

    return AuthSession(
      accessToken: token,
      refreshToken: refreshToken is String ? refreshToken : '',
      userName: _firstNonEmpty(json, const ['userName', 'name']) ?? '',
      email: _firstNonEmpty(json, const ['email']) ?? '',
    );
  }

  final String accessToken;
  final String refreshToken;
  final String userName;
  final String email;
}

class AccountClaimChallenge {
  const AccountClaimChallenge({
    required this.id,
    required this.expiresAt,
    required this.message,
  });

  factory AccountClaimChallenge.fromJson(Map<String, dynamic> json) {
    final id = json['challengeId']?.toString() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (id.isEmpty || expiresAt == null) {
      throw const FormatException('Verification response was incomplete');
    }
    return AccountClaimChallenge(
      id: id,
      expiresAt: expiresAt,
      message: json['message']?.toString() ??
          'If the account exists, a verification code has been sent.',
    );
  }

  final String id;
  final DateTime expiresAt;
  final String message;
}

class AccountLinkSession {
  const AccountLinkSession({
    required this.token,
    required this.challengeId,
    required this.status,
    required this.expiresAt,
  });

  factory AccountLinkSession.fromJson(
    Map<String, dynamic> json, {
    required String token,
  }) {
    final challengeId = json['challengeId']?.toString() ?? '';
    final status = json['status']?.toString().toUpperCase() ?? '';
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    if (challengeId.isEmpty || status.isEmpty || expiresAt == null) {
      throw const FormatException('Account transfer response was incomplete');
    }
    return AccountLinkSession(
      token: token,
      challengeId: challengeId,
      status: status,
      expiresAt: expiresAt,
    );
  }

  final String token;
  final String challengeId;
  final String status;
  final DateTime expiresAt;

  bool get isTerminal =>
      status == 'DENIED' || status == 'CONSUMED' || status == 'EXPIRED';

  AccountLinkSession copyWith({String? status, DateTime? expiresAt}) =>
      AccountLinkSession(
        token: token,
        challengeId: challengeId,
        status: status ?? this.status,
        expiresAt: expiresAt ?? this.expiresAt,
      );
}

String? _firstNonEmpty(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final text = json[key]?.toString().trim();
    if (text != null && text.isNotEmpty) {
      return text;
    }
  }

  return null;
}

class AuthApi {
  const AuthApi(this._dio);

  final Dio _dio;

  Future<AuthSession> login({
    required String email,
    required String password,
  }) async {
    final outcome = await signIn(email: email, password: password);
    final session = outcome.session;
    if (session == null) {
      throw StateError('This account requires a second factor to sign in.');
    }
    return session;
  }

  /// Password step of sign-in. Accounts with 2FA get a challenge instead of
  /// tokens; finish with [completeTwoFactor].
  Future<LoginOutcome> signIn({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/login',
      data: {
        'email': email,
        'password': password,
        'deviceName': currentDeviceLabel(),
      },
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Login response was empty');
    }
    if (data['requiresTwoFactor'] == true) {
      final challenge = data['challengeToken']?.toString() ?? '';
      if (challenge.isEmpty) {
        throw const FormatException('Login response was missing a challenge');
      }
      return LoginOutcome.challenge(challenge);
    }
    return LoginOutcome.signedIn(AuthSession.fromJson(data));
  }

  Future<AuthSession> completeTwoFactor({
    required String challengeToken,
    required String code,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/login/2fa',
      data: {'challengeToken': challengeToken, 'code': code.trim()},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Sign-in response was empty');
    }
    return AuthSession.fromJson(data);
  }

  Future<AccountSecurity> getSecurity() async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/v1/mobile/auth/security');
    return AccountSecurity.fromJson(response.data ?? const {});
  }

  Future<TwoFactorSetup> setupTwoFactor({required String password}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/2fa/setup',
      data: {'currentPassword': password},
    );
    final data = response.data ?? const {};
    return TwoFactorSetup(
      secret: data['secret']?.toString() ?? '',
      otpauthUri: data['otpauthUri']?.toString() ?? '',
    );
  }

  Future<List<String>> enableTwoFactor({required String code}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/2fa/enable',
      data: {'code': code.trim()},
    );
    final codes = response.data?['recoveryCodes'];
    return codes is List ? codes.map((code) => code.toString()).toList() : [];
  }

  Future<AccountSecurity> disableTwoFactor({required String code}) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/2fa/disable',
      data: {'code': code.trim()},
    );
    return AccountSecurity.fromJson(response.data ?? const {});
  }

  Future<AccountSecurity> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/password/change',
      data: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
    return AccountSecurity.fromJson(response.data ?? const {});
  }

  Future<AccountSecurity> setDuressPassword({
    required String currentPassword,
    required String duressPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/duress',
      data: {
        'currentPassword': currentPassword,
        'duressPassword': duressPassword,
      },
    );
    return AccountSecurity.fromJson(response.data ?? const {});
  }

  Future<AccountSecurity> removeDuressPassword({
    required String currentPassword,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/duress/remove',
      data: {'currentPassword': currentPassword},
    );
    return AccountSecurity.fromJson(response.data ?? const {});
  }

  Future<AuthSession> refresh({
    required String refreshToken,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/refresh',
      data: {'refreshToken': refreshToken},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    final data = response.data;
    if (data == null) {
      throw const FormatException('Refresh response was empty');
    }

    return AuthSession.fromJson(data);
  }

  /// Tells the API to revoke the current session. Best effort: the local
  /// tokens are cleared regardless of the outcome.
  Future<void> logout({String? refreshToken}) => _dio.post<void>(
        '/api/v1/mobile/auth/logout',
        data: {
          if (refreshToken != null && refreshToken.isNotEmpty)
            'refreshToken': refreshToken,
        },
        options: Options(extra: const {'skipAuthRefresh': true}),
      );

  /// Devices with a live session for this account.
  Future<List<AuthDeviceSession>> listSessions() async {
    final response = await _dio.get<dynamic>('/api/v1/mobile/auth/sessions');
    final data = response.data;
    final items = data is List
        ? data
        : data is Map && data['sessions'] is List
            ? data['sessions'] as List
            : const [];
    return [
      for (final item in items.whereType<Map>())
        AuthDeviceSession.fromJson(
          item.map((key, value) => MapEntry(key.toString(), value)),
        ),
    ];
  }

  Future<void> revokeSession(String sessionId) =>
      _dio.delete<void>('/api/v1/mobile/auth/sessions/$sessionId');

  Future<void> revokeOtherSessions() =>
      _dio.post<void>('/api/v1/mobile/auth/sessions/revoke-others');

  /// Requests a code without exposing account existence. Returns the resend
  /// cooldown; acceptance is not confirmation of inbox delivery.
  Future<int> requestPasswordReset(String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/password/forgot',
      data: {'email': email.trim()},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    return ((response.data?['retryAfterSeconds'] as num?)?.toInt() ?? 60).clamp(
      0,
      3600,
    );
  }

  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/password/reset',
      data: {
        'email': email.trim(),
        'code': code.trim(),
        'newPassword': newPassword,
      },
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
  }

  /// Re-sends the registration confirmation code. Always 202 server-side.
  Future<void> resendEmailVerification(String email) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/email/resend',
      data: {'email': email.trim()},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
  }

  Future<void> verifyEmail(
      {required String email, required String code}) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/email/verify',
      data: {'email': email.trim(), 'code': code.trim()},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
  }

  Future<AccountClaimChallenge> requestAccountClaim(String email) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/account-claim/challenges',
      data: {'email': email.trim()},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    return AccountClaimChallenge.fromJson(response.data ?? const {});
  }

  Future<void> completeAccountClaim({
    required String email,
    required String challengeId,
    required String code,
    required String password,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/account-claim/complete',
      data: {
        'email': email.trim(),
        'challengeId': challengeId,
        'code': code.trim(),
        'password': password,
      },
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
  }

  Future<AccountLinkSession> scanAccountLink({
    required String qrPayload,
    required String deviceName,
  }) async {
    final uri = Uri.tryParse(qrPayload.trim());
    final token = uri?.queryParameters['token']?.trim();
    if (uri == null ||
        uri.scheme.toLowerCase() != 'hoppa' ||
        uri.host.toLowerCase() != 'account-transfer' ||
        token == null ||
        token.length < 32) {
      throw const FormatException(
          'This is not a valid account-transfer QR code');
    }

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/account-link/scan',
      data: {'qrPayload': qrPayload.trim(), 'deviceName': deviceName},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    return AccountLinkSession.fromJson(
      response.data ?? const {},
      token: token,
    );
  }

  Future<AccountLinkSession> getAccountLinkStatus(
      AccountLinkSession session) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/account-link/status',
      data: {'token': session.token},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
    return AccountLinkSession.fromJson(
      response.data ?? const {},
      token: session.token,
    );
  }

  Future<void> completeAccountLink({
    required String token,
    required String password,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/auth/account-link/complete',
      data: {'token': token, 'password': password},
      options: Options(extra: const {'skipAuthRefresh': true}),
    );
  }
}

/// Short label the API stores with the session so the customer recognises the
/// device in Settings; browsers get a more specific name from the user agent.
String currentDeviceLabel() {
  if (kIsWeb) return 'Web browser';
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => 'iPhone',
    TargetPlatform.android => 'Android phone',
    TargetPlatform.macOS => 'Mac',
    TargetPlatform.windows => 'Windows PC',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.fuchsia => 'Device',
  };
}

class AuthDeviceSession {
  const AuthDeviceSession({
    required this.id,
    required this.deviceName,
    required this.isCurrent,
    this.ipAddress,
    this.createdAt,
    this.lastUsedAt,
    this.expiresAt,
  });

  factory AuthDeviceSession.fromJson(Map<String, dynamic> json) {
    DateTime? date(Object? value) =>
        value == null ? null : DateTime.tryParse(value.toString())?.toLocal();
    return AuthDeviceSession(
      id: (json['id'] ?? json['Id'] ?? '').toString(),
      deviceName: (json['deviceName'] ?? json['DeviceName'] ?? 'Unknown device')
          .toString(),
      isCurrent: json['isCurrent'] == true || json['IsCurrent'] == true,
      ipAddress: (json['ipAddress'] ?? json['IpAddress'])?.toString(),
      createdAt: date(json['createdAt'] ?? json['CreatedAt']),
      lastUsedAt: date(json['lastUsedAt'] ?? json['LastUsedAt']),
      expiresAt: date(json['expiresAt'] ?? json['ExpiresAt']),
    );
  }

  final String id;
  final String deviceName;
  final bool isCurrent;
  final String? ipAddress;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? expiresAt;
}

/// Result of the password step: either tokens, or a 2FA challenge to finish.
class LoginOutcome {
  const LoginOutcome._({this.session, this.challengeToken});

  const LoginOutcome.signedIn(AuthSession session) : this._(session: session);

  const LoginOutcome.challenge(String token) : this._(challengeToken: token);

  final AuthSession? session;
  final String? challengeToken;

  bool get requiresTwoFactor => challengeToken != null;
}

class AccountSecurity {
  const AccountSecurity({
    required this.twoFactorEnabled,
    required this.recoveryCodesRemaining,
    required this.duressPasswordSet,
    this.passwordChangedAt,
  });

  factory AccountSecurity.fromJson(Map<String, dynamic> json) =>
      AccountSecurity(
        twoFactorEnabled: json['twoFactorEnabled'] == true,
        recoveryCodesRemaining:
            (json['recoveryCodesRemaining'] as num?)?.toInt() ?? 0,
        duressPasswordSet: json['duressPasswordSet'] == true,
        passwordChangedAt: json['passwordChangedAt'] == null
            ? null
            : DateTime.tryParse(json['passwordChangedAt'].toString()),
      );

  final bool twoFactorEnabled;
  final int recoveryCodesRemaining;
  final bool duressPasswordSet;
  final DateTime? passwordChangedAt;
}

class TwoFactorSetup {
  const TwoFactorSetup({required this.secret, required this.otpauthUri});

  final String secret;
  final String otpauthUri;
}
