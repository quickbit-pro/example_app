import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/kyc/data/kyc_api.dart';

void main() {
  _hostedUrlTests();
  group('SumsubToken', () {
    test('parses token field from backend response', () {
      final token = SumsubToken.fromJson({
        'token': 'sdk-token',
        'expiresAt': '2026-05-01T12:00:00Z',
      });

      expect(token.token, 'sdk-token');
      expect(token.expiresAt, '2026-05-01T12:00:00Z');
    });

    test('parses accessToken fallback from backend response', () {
      final token = SumsubToken.fromJson({'accessToken': 'sdk-token'});

      expect(token.token, 'sdk-token');
    });

    test('rejects empty token response', () {
      expect(
        () => SumsubToken.fromJson({}),
        throwsA(isA<FormatException>()),
      );
    });
  });

  test('KYC payload required by backend can be supplied by caller', () {
    const applicantProfile = {
      'Occupation': 'Software engineer',
      'AnnualSalary': '50001-75000',
      'AccountPurpose': 'Everyday banking',
      'ExpectedMonthlyVolume': '1001-5000',
      'DocumentIssueDate': '2026-01-01',
    };

    expect(applicantProfile.values.every((value) => value.isNotEmpty), isTrue);
  });

  test('OccupationCode parses Hoppa occupation fields only', () {
    final occupation = OccupationCode.fromJson({
      'Value': '2613',
      'Title': 'Software developers',
      'MajorGroup': 'Professionals',
    });

    expect(occupation.value, '2613');
    expect(occupation.title, 'Software developers');
    expect(occupation.majorGroup, 'Professionals');
  });

  test('KycApi parses nested occupation code wrappers', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StaticAdapter(
        200,
        {
          'data': {
            'occupationCodes': [
              {'Code': '2613', 'Title': 'Software developers'},
            ],
          },
        },
      );

    final occupations = await KycApi(dio).getOccupationCodes();

    expect(occupations.single.value, '2613');
    expect(occupations.single.title, 'Software developers');
  });

  test('KycApi returns fallback occupation codes for missing options',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _StaticAdapter(404, {'message': 'Not found'});

    final occupations = await KycApi(dio).getOccupationCodes();

    expect(occupations, fallbackOccupationCodes);
  });
}

class _StaticAdapter implements HttpClientAdapter {
  _StaticAdapter(this.statusCode, this.payload);

  final int statusCode;
  final Object payload;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(payload),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void _hostedUrlTests() {
  group('hostedKycUrlFromJson', () {
    test('finds the link under any common key, including nested data', () {
      expect(
        hostedKycUrlFromJson({'kycUrl': 'https://in.sumsub.com/websdk/p/abc'}),
        Uri.parse('https://in.sumsub.com/websdk/p/abc'),
      );
      expect(
        hostedKycUrlFromJson({
          'data': {'permalink': 'https://in.sumsub.com/websdk/p/xyz'},
        }),
        Uri.parse('https://in.sumsub.com/websdk/p/xyz'),
      );
      expect(hostedKycUrlFromJson('https://example.com/kyc'), isNotNull);
    });

    test('reads the Hoppa kyc-url response, which uses accessToken', () {
      expect(
        hostedKycUrlFromJson({
          'success': true,
          'accessToken': 'https://in.sumsub.com/websdk/p/sbx_z7mltqXHp46SsWAJ',
          'applicantId': '6a98535e51f5239176e4cca9',
          'status': 'initiated',
        }),
        Uri.parse('https://in.sumsub.com/websdk/p/sbx_z7mltqXHp46SsWAJ'),
      );
      expect(
        () => hostedKycUrlFromJson({
          'success': false,
          'errorMessage': 'Applicant already verified',
        }),
        throwsA(isA<StateError>()),
      );
    });

    test('ignores responses without a usable link', () {
      expect(hostedKycUrlFromJson({'token': '_act-sbx-123'}), isNull);
      expect(hostedKycUrlFromJson({'url': 'not a url'}), isNull);
      expect(hostedKycUrlFromJson(null), isNull);
    });
  });
}
