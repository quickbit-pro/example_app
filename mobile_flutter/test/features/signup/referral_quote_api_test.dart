import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/signup/data/referral_device_token.dart';
import 'package:mobile_flutter/features/signup/data/visitor_id_store.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Map<String, dynamic> Function(RequestOptions) respond;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(respond(options)), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
  @override
  void close({bool force = false}) {}
}

void main() {
  test('quote carries locale and source and cannot belong to another attempt',
      () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        expect(request.path, '/api/v1/mobile/auth/referral-quote');
        expect(request.data['locale'], 'fr');
        expect(request.data['source'], 'EMAIL_INVITATION');
        expect(request.data['invitationToken'], 'email-token');
        return {
          'quoteId': 'q',
          'registrationAttemptId': 'wrong-attempt',
          'termsVersion': 2,
          'termsText': 'Conditions',
          'termsHash': 't',
          'policyHash': 'p',
          'expiresAt': '2099-01-01T00:00:00Z'
        };
      });
    await expectLater(
        MobilePlatformApi(dio).getReferralQuote(
            registrationAttemptId: 'right-attempt',
            referralCode: 'ABC',
            source: 'EMAIL_INVITATION',
            invitationToken: 'email-token',
            locale: 'fr'),
        throwsFormatException);
  });
  test(
      'signup transmits immutable consent evidence and device signal separately',
      () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        expect(request.data['registrationAttemptId'], 'attempt');
        expect(request.data['referralQuoteId'], 'quote');
        expect(request.data['referralTermsHash'], 'terms-hash');
        expect(request.data['referralPolicyHash'], 'policy-hash');
        expect(request.data['referralAccepted'], true);
        expect(request.data['installationToken'], 'device');
        expect(request.data.containsKey('ipAddress'), false);
        return {
          'message': 'Account created',
          'referralAttributionStatus': 'PENDING'
        };
      });
    final result = await MobilePlatformApi(dio).signUp(
        email: 'a@example.com',
        password: 'password',
        firstName: 'A',
        lastName: 'B',
        accountType: 'personal',
        referralCode: 'ABC',
        registrationAttemptId: 'attempt',
        referralQuoteId: 'quote',
        referralTermsHash: 'terms-hash',
        referralPolicyHash: 'policy-hash',
        referralAccepted: true,
        installationToken: 'device');
    expect(result.metadata['referralAttributionStatus'], 'PENDING');
  });
  test('review-only signup explicitly declines unavailable offer consent',
      () async {
    final dio = Dio()
      ..httpClientAdapter = _Adapter((request) {
        expect(request.data['referralNeedsReview'], true);
        expect(request.data['referralAccepted'], false);
        expect(request.data.containsKey('referralQuoteId'), false);
        return {
          'message': 'Account created',
          'referralAttributionStatus': 'NEEDS_REVIEW'
        };
      });
    await MobilePlatformApi(dio).signUp(
        email: 'a@example.com',
        password: 'password',
        firstName: 'A',
        lastName: 'B',
        accountType: 'personal',
        referralCode: 'ABC',
        registrationAttemptId: 'attempt',
        referralNeedsReview: true,
        referralAccepted: false);
  });
  test('risk installation token is stable and separate from click analytics',
      () async {
    SharedPreferences.setMockInitialValues(
        {VisitorIdStore.preferenceKey: '234c9850-d023-46e1-bb76-427af3bed456'});
    const store = ReferralDeviceTokenStore();
    final token = await store.getOrCreate();
    expect(VisitorIdStore.isVisitorId(token!), true);
    expect(token, isNot('234c9850-d023-46e1-bb76-427af3bed456'));
    expect(await store.getOrCreate(), token);
  });
}
