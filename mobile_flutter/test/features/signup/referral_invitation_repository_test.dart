import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/signup/data/referral_invitation_repository.dart';
import 'package:mobile_flutter/features/signup/domain/referral_invitation.dart';

void main() {
  test('preview sends the exact opaque token and parses the response',
      () async {
    const token = 'opaque.+/_-token==';
    late RequestOptions request;
    final dio = Dio()
      ..httpClientAdapter = _Adapter((options) async {
        request = options;
        return _jsonResponse(200, {
          'email': 'invitee@example.com',
          'referralCode': 'ABC1234',
          'inviterDisplayName': 'John',
          'expiresAt': '2026-09-04T12:00:00Z',
        });
      });

    final preview = await DioReferralInvitationRepository(dio).preview(token);

    expect(request.path, '/api/v2/referral-invitations/preview');
    expect(request.queryParameters['token'], token);
    expect(request.extra['sensitiveRequest'], isTrue);
    expect(preview.email, 'invitee@example.com');
    expect(preview.referralCode, 'ABC1234');
    expect(preview.inviterDisplayName, 'John');
  });

  test('preview carries the welcome and terms version when served', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async => _jsonResponse(200, {
            'email': 'invitee@example.com',
            'referralCode': 'ABC1234',
            'inviterDisplayName': 'John',
            'expiresAt': '2026-09-04T12:00:00Z',
            'welcomeAmount': '3',
            'welcomeCurrency': 'USD',
            'termsVersion': 2,
          }));

    final preview = await DioReferralInvitationRepository(dio).preview('t');

    expect(preview.welcomeAmount, 3);
    expect(preview.welcomeCurrency, 'USD');
    expect(preview.hasWelcome, isTrue);
    expect(preview.termsVersion, 2);
  });

  test('preview tolerates a backend without the welcome fields', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((_) async => _jsonResponse(200, {
            'email': 'invitee@example.com',
            'referralCode': 'ABC1234',
            'inviterDisplayName': 'John',
            'expiresAt': '2026-09-04T12:00:00Z',
          }));

    final preview = await DioReferralInvitationRepository(dio).preview('t');

    expect(preview.welcomeAmount, 0);
    expect(preview.hasWelcome, isFalse);
    expect(preview.termsVersion, isNull);
  });

  test('invalid, expired, and consumed responses are classified safely',
      () async {
    Future<ReferralInvitationFailure> failureFor(
      int status,
      Map<String, dynamic> payload,
    ) async {
      final dio = Dio()
        ..httpClientAdapter = _Adapter(
          (_) async => _jsonResponse(status, payload),
        );
      try {
        await DioReferralInvitationRepository(dio).preview('secret-token');
        fail('Expected preview to fail');
      } on ReferralInvitationFailure catch (error) {
        return error;
      }
    }

    expect(
      (await failureFor(404, {'code': 'INVALID'})).type,
      ReferralInvitationFailureType.invalid,
    );
    expect(
      (await failureFor(410, {'code': 'EXPIRED'})).type,
      ReferralInvitationFailureType.expired,
    );
    final consumed = await failureFor(400, {'code': 'ALREADY_USED'});
    expect(consumed.type, ReferralInvitationFailureType.expired);
    expect(consumed.toString(), isNot(contains('secret-token')));
  });

  test('transport failures are classified as network errors', () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter(
        (options) => throw DioException.connectionError(
          requestOptions: options,
          reason: 'offline',
        ),
      );

    expect(
      () => DioReferralInvitationRepository(dio).preview('secret-token'),
      throwsA(
        isA<ReferralInvitationFailure>().having(
          (failure) => failure.type,
          'type',
          ReferralInvitationFailureType.network,
        ),
      ),
    );
  });
}

class _Adapter implements HttpClientAdapter {
  _Adapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonResponse(int status, Map<String, dynamic> payload) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
