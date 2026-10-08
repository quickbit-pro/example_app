import 'package:dio/dio.dart';

class SumsubToken {
  const SumsubToken({required this.token, this.expiresAt});

  factory SumsubToken.fromJson(Map<String, dynamic> json) {
    final token = json['token'] ??
        json['Token'] ??
        json['accessToken'] ??
        json['AccessToken'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('KYC token response did not include a token');
    }

    return SumsubToken(
      token: token,
      expiresAt: (json['expiresAt'] ?? json['ExpiresAt']) as String?,
    );
  }

  final String token;
  final String? expiresAt;
}

class OccupationCode {
  const OccupationCode({
    required this.value,
    required this.title,
    this.majorGroup,
    this.minorGroup,
  });

  factory OccupationCode.fromJson(Map<String, dynamic> json) {
    final value =
        (json['value'] ?? json['Value'] ?? json['code'] ?? json['Code'])
                ?.toString() ??
            '';
    final title = (json['title'] ??
                json['Title'] ??
                json['name'] ??
                json['Name'] ??
                json['label'] ??
                json['Label'])
            ?.toString() ??
        value;

    return OccupationCode(
      value: value,
      title: title,
      majorGroup: (json['majorGroup'] ?? json['MajorGroup'])?.toString(),
      minorGroup: (json['minorGroup'] ?? json['MinorGroup'])?.toString(),
    );
  }

  final String value;
  final String title;
  final String? majorGroup;
  final String? minorGroup;
}

class KycApi {
  const KycApi(this._dio);

  final Dio _dio;

  Future<Uri> resumeVerification() async {
    final response = await _dio.post<dynamic>('/api/v1/mobile/kyc/resume');
    final uri = hostedKycUrlFromJson(response.data);
    if (uri == null || uri.scheme != 'https') {
      throw const FormatException(
          'A secure verification link was not returned.');
    }
    return uri;
  }

  Future<SumsubToken> createSumsubToken({
    required Map<String, Object?> applicantProfile,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/kyc/sumsub-token',
      data: applicantProfile,
    );

    final data = response.data;
    if (data == null) {
      throw const FormatException('KYC token response was empty');
    }

    return SumsubToken.fromJson(data);
  }

  /// Hosted Sumsub verification page issued by Hoppa
  /// (`/users/{id}/sumsub/kyc-url`). Returns null when the provider does not
  /// offer one, so callers can fall back to the embedded SDK.
  Future<Uri?> createHostedKycUrl({
    required Map<String, Object?> applicantProfile,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/v1/mobile/kyc/hosted-url',
      data: applicantProfile,
    );
    return hostedKycUrlFromJson(response.data);
  }

  Future<void> startOnboarding() async {
    await _dio.post<Map<String, dynamic>>(
      '/api/v1/mobile/onboarding/start',
      data: const {
        'customerType': 'individual',
        'productCode': 'neobanking',
      },
    );
  }

  Future<void> markKycSubmitted() async {
    await _dio.patch<Map<String, dynamic>>(
      '/api/v1/mobile/onboarding/steps',
      data: const {
        'step': 'kyc_submitted',
        'status': 'submitted',
        'notes': 'SumSub verification session was closed by the user.',
      },
    );
  }

  Future<List<OccupationCode>> getOccupationCodes() async {
    late final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        '/api/v1/mobile/kyc/occupation-codes',
      );
    } on DioException catch (error) {
      if (!_canUseFallbackOccupationCodes(error)) {
        rethrow;
      }

      return fallbackOccupationCodes;
    }

    final payload = response.data;
    final list = _extractOccupationList(payload);

    final occupations = list
        .map((item) {
          if (item is Map<String, dynamic>) {
            return OccupationCode.fromJson(item);
          }
          if (item is Map) {
            return OccupationCode.fromJson(
              item.map((key, value) => MapEntry(key.toString(), value)),
            );
          }
          if (item is String && item.trim().isNotEmpty) {
            return OccupationCode(value: item.trim(), title: item.trim());
          }

          return const OccupationCode(value: '', title: '');
        })
        .where((occupation) => occupation.value.isNotEmpty)
        .toList(growable: false);

    return occupations.isEmpty ? fallbackOccupationCodes : occupations;
  }
}

List<dynamic> _extractOccupationList(dynamic payload) {
  if (payload is List) {
    return payload;
  }

  if (payload is Map) {
    final normalized =
        payload.map((key, value) => MapEntry(key.toString(), value));
    for (final key in const [
      'occupationCodes',
      'OccupationCodes',
      'occupations',
      'Occupations',
      'codes',
      'Codes',
      'items',
      'Items',
      'list',
      'List',
      'data',
      'Data',
    ]) {
      final value = normalized[key];
      if (value is List) {
        return value;
      }
      if (value is Map) {
        final nested = _extractOccupationList(value);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }

    if (_looksLikeCodeTitleMap(normalized)) {
      return normalized.entries
          .map((entry) => {
                'value': entry.key,
                'title': entry.value?.toString() ?? entry.key,
              })
          .toList();
    }
  }

  return const [];
}

bool _looksLikeCodeTitleMap(Map<String, dynamic> payload) {
  if (payload.isEmpty) {
    return false;
  }

  const wrapperKeys = {
    'data',
    'Data',
    'items',
    'Items',
    'list',
    'List',
    'occupationCodes',
    'OccupationCodes',
    'occupations',
    'Occupations',
    'codes',
    'Codes',
  };
  if (payload.keys.any(wrapperKeys.contains)) {
    return false;
  }

  return payload.values.every((value) => value is String || value is num);
}

bool _canUseFallbackOccupationCodes(DioException error) {
  final status = error.response?.statusCode;
  return status == 400 || status == 404 || status == 409;
}

const fallbackOccupationCodes = [
  OccupationCode(value: '2611', title: 'Software and applications developers'),
  OccupationCode(value: '2411', title: 'Accountants'),
  OccupationCode(value: '2421', title: 'Management and organisation analysts'),
  OccupationCode(
      value: '2431', title: 'Advertising and marketing professionals'),
  OccupationCode(value: '3312', title: 'Credit and loans officers'),
  OccupationCode(value: '4110', title: 'General office clerks'),
  OccupationCode(value: '5223', title: 'Shop sales assistants'),
  OccupationCode(value: '5322', title: 'Home-based personal care workers'),
  OccupationCode(value: '7115', title: 'Carpenters and joiners'),
  OccupationCode(value: '9999', title: 'Other occupation'),
];

const _hostedUrlKeys = {
  // Hoppa's /users/{id}/sumsub/kyc-url returns the Sumsub link in
  // `accessToken` (https://in.sumsub.com/websdk/p/...).
  'accesstoken',
  'token',
  'url',
  'kycurl',
  'link',
  'permalink',
  'websdklink',
  'verificationurl',
  'hostedurl',
  'redirecturl',
  'sdklink',
};

/// Finds the verification link in a provider response regardless of the
/// key it was returned under (also looks inside nested `data`/`result`).
Uri? hostedKycUrlFromJson(Object? json) {
  if (json is String) {
    final uri = Uri.tryParse(json.trim());
    return uri != null && uri.hasScheme && uri.host.isNotEmpty ? uri : null;
  }
  if (json is! Map) return null;
  if (json['success'] == false) {
    final reason = (json['errorMessage'] ?? json['message'] ?? '').toString();
    throw StateError(
      reason.trim().isEmpty
          ? 'The verification link could not be created. Try again shortly.'
          : reason,
    );
  }
  for (final entry in json.entries) {
    final key = entry.key.toString().toLowerCase();
    if (_hostedUrlKeys.contains(key)) {
      final found = hostedKycUrlFromJson(entry.value);
      if (found != null) return found;
    }
  }
  for (final key in const ['data', 'Data', 'result', 'Result', 'payload']) {
    final nested = json[key];
    if (nested is Map || nested is String) {
      final found = hostedKycUrlFromJson(nested);
      if (found != null) return found;
    }
  }
  return null;
}
