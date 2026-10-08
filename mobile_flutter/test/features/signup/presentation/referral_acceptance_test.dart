// The referred user's side of the programme at signup.
//
// A code requests attribution at account creation without a separate checkbox.
// Quote loading stays in the background and cannot block the security step.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/application/referral_invitation_providers.dart';
import 'package:mobile_flutter/features/signup/data/referral_invitation_repository.dart';
import 'package:mobile_flutter/features/signup/domain/referral_invitation.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/features/signup/domain/referral_quote.dart';

const _config = MobileTenantConfig(
  companyName: 'Hoppa',
  brandName: 'Hoppa',
  referralsEnabled: true,
  referralRegistrationMode: 'optional',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
);

/// Serves the referral check from memory; the network is never touched.
class _FakeApi extends MobilePlatformApi {
  _FakeApi({this.welcome, this.quoteUnavailable = false}) : super(Dio());

  final bool quoteUnavailable;

  final ReferralWelcome? welcome;
  final checked = <String>[];

  @override
  Future<ReferralQuote> getReferralQuote(
      {required String registrationAttemptId,
      required String referralCode,
      required String source,
      String? invitationToken,
      required String locale}) async {
    if (quoteUnavailable) throw const FormatException('Quote unavailable');
    return ReferralQuote(
        quoteId: 'q',
        registrationAttemptId: registrationAttemptId,
        termsVersion: 2,
        termsText: 'Original referral terms',
        termsHash: 'terms',
        policyHash: 'policy',
        expiresAt: DateTime.utc(2099));
  }

  @override
  Future<ReferralWelcome?> checkReferralCode(String referralCode) async {
    checked.add(referralCode);
    return welcome;
  }
}

class _FakeRepository implements ReferralInvitationRepository {
  _FakeRepository(this.result);

  final ReferralInvitationPreview result;

  @override
  Future<ReferralInvitationPreview> preview(String token) async => result;
}

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  String? initialReferralCode,
  String? invitationToken,
  ReferralInvitationPreview? invitation,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobilePlatformApiProvider.overrideWithValue(api),
        mobileTenantConfigProvider.overrideWith((ref) async => _config),
        if (invitation != null)
          referralInvitationRepositoryProvider
              .overrideWithValue(_FakeRepository(invitation)),
      ],
      child: MaterialApp(
        home: SignupScreen(
          initialReferralCode: initialReferralCode,
          invitationToken: invitationToken,
          referralSource: initialReferralCode == null ? 'MANUAL_CODE' : 'LINK',
          initialStep: 2,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The referral check waits for typing to pause; let that pause elapse.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

void _expectCodeOnly() {
  expect(find.byKey(const Key('signup_referral_accept'), skipOffstage: false),
      findsNothing);
  expect(
      find.byKey(const Key('signup_referral_needs_review'),
          skipOffstage: false),
      findsNothing);
  expect(
      find.byKey(const Key('signup_referral_quoted_terms'),
          skipOffstage: false),
      findsNothing);
  expect(
      find.text('Original referral terms', skipOffstage: false), findsNothing);
}

void main() {
  for (final unavailable in [false, true]) {
    testWidgets(
        'link code has no referral acceptance, quote unavailable=$unavailable',
        (tester) async {
      final api = _FakeApi(quoteUnavailable: unavailable);
      await _pump(tester, api: api, initialReferralCode: 'ABC1234');
      expect(api.checked, ['ABC1234']);
      _expectCodeOnly();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'ValidExample1234');
      await tester.tap(find.text('Continue').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.widget<Stepper>(find.byType(Stepper)).currentStep, 3);
    });
  }

  testWidgets('no code, no acceptance asked', (tester) async {
    final api = _FakeApi();
    await _pump(tester, api: api);
    _expectCodeOnly();
    expect(api.checked, isEmpty);
  });

  testWidgets('a typed code is checked without adding referral conditions',
      (tester) async {
    final api =
        _FakeApi(welcome: const ReferralWelcome(inviterDisplayName: 'Ana'));
    await _pump(tester, api: api);
    final field = find.descendant(
      of: find.byKey(const Key('signup_referral_code'), skipOffstage: false),
      matching: find.byType(EditableText, skipOffstage: false),
    );
    await tester.enterText(field, 'FRIEND1');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(api.checked, ['FRIEND1']);
    _expectCodeOnly();
    await tester.enterText(field, '');
    await tester.pumpAndSettle();
    _expectCodeOnly();
  });

  testWidgets('email invitation retains its code without another checkbox',
      (tester) async {
    final api = _FakeApi();
    await _pump(tester,
        api: api,
        invitationToken: 'opaque-token',
        invitation: ReferralInvitationPreview(
          email: 'invitee@example.com',
          referralCode: 'ABC1234',
          inviterDisplayName: 'John',
          expiresAt: DateTime.utc(2099),
        ));
    expect(api.checked, isEmpty);
    _expectCodeOnly();
  });

  test('registration carries the acceptance and the terms version', () async {
    late Map<String, dynamic> payload;
    final dio = Dio()
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        expect(options.path, '/api/v1/mobile/auth/signup');
        payload = jsonDecode(body) as Map<String, dynamic>;
        return ResponseBody.fromString(
          jsonEncode({'message': 'Account created'}),
          201,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    await MobilePlatformApi(dio).signUp(
      email: 'friend@example.test',
      password: 'StrongPassword1',
      firstName: 'Friend',
      lastName: 'Example',
      accountType: 'personal',
      referralCode: 'ABC1234',
      referralSource: 'LINK',
      referralAccepted: true,
      referralTermsVersion: 2,
    );
    expect(payload['referralAccepted'], isTrue);
    expect(payload['referralTermsVersion'], 2);

    await MobilePlatformApi(dio).signUp(
      email: 'friend@example.test',
      password: 'StrongPassword1',
      firstName: 'Friend',
      lastName: 'Example',
      accountType: 'personal',
    );
    expect(payload.containsKey('referralAccepted'), isFalse);
    expect(payload.containsKey('referralTermsVersion'), isFalse);
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options, String body) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body =
        requestStream == null ? '' : await utf8.decodeStream(requestStream);
    return _handler(options, body);
  }
}
