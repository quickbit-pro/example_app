// Sign-up with a campaign link that no longer attributes (contract
// 2026-09-15): the `?ref=` code is prefilled as before; when check-referral
// answers CAMPAIGN_LINK_INACTIVE the screen says so, clears and unlocks the
// field, and the sign-up carries on as a normal one.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';

class _FakeApi extends MobilePlatformApi {
  _FakeApi(this.answers) : super(Dio());

  final Map<String, ReferralWelcome?> answers;
  final checked = <String>[];

  @override
  Future<ReferralWelcome?> checkReferralCode(String referralCode) async {
    checked.add(referralCode.trim());
    return answers[referralCode.trim()];
  }
}

Future<void> _pump(WidgetTester tester, _FakeApi api,
    {bool required = false}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobilePlatformApiProvider.overrideWithValue(api),
        mobileTenantConfigProvider.overrideWith(
          (ref) async => MobileTenantConfig(
            companyName: 'Example',
            brandName: 'Example',
            referralsEnabled: true,
            referralRegistrationMode: required ? 'required' : 'optional',
            vouchersEnabled: false,
            existingAccountClaimEnabled: false,
            boomFiExchangeEnabled: false,
            walletOutflowsEnabled: false,
            equalsMoneyEnabled: true,
          ),
        ),
      ],
      child: const MaterialApp(
        home: SignupScreen(
          initialReferralCode: 'AUTUMN26',
          referralSource: 'LINK',
          // The referral field lives on the security step; open there so
          // the test can type into it.
          initialStep: 2,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The check runs once typing (or the prefill) has paused.
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
}

EditableText _field(WidgetTester tester) => tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('signup_referral_code'), skipOffstage: false),
        matching: find.byType(EditableText, skipOffstage: false),
      ),
    );

void main() {
  testWidgets('an inactive campaign link is announced and the sign-up goes on',
      (tester) async {
    final api = _FakeApi({'AUTUMN26': const ReferralWelcome.inactiveCampaignLink()});
    await _pump(tester, api);
    expect(api.checked, ['AUTUMN26']);
    expect(find.byKey(const Key('signup_referral_link_inactive'), skipOffstage: false),
        findsOneWidget);
    expect(find.text('This invitation link is no longer active', skipOffstage: false),
        findsOneWidget);
    expect(
        find.text('You can still sign up without a code, or enter another one.',
            skipOffstage: false),
        findsOneWidget);
    final field = _field(tester);
    expect(field.controller.text, isEmpty, reason: 'the dead code is dropped');
    expect(field.readOnly, isFalse, reason: 'the customer may enter another');
    expect(find.text('Applied from your invitation link.', skipOffstage: false),
        findsNothing);

    // Typing another code clears the note and checks the new one.
    await tester.enterText(
        find.byKey(const Key('signup_referral_code'), skipOffstage: false), 'FRIEND1');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    expect(api.checked, ['AUTUMN26', 'FRIEND1']);
    expect(_field(tester).controller.text, 'FRIEND1');
    expect(find.byKey(const Key('signup_referral_link_inactive'), skipOffstage: false),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a live link keeps the prefilled, locked code', (tester) async {
    final api = _FakeApi({
      'AUTUMN26': const ReferralWelcome(inviterDisplayName: 'Maja', welcomeAmount: 3),
    });
    await _pump(tester, api);
    expect(find.byKey(const Key('signup_referral_link_inactive'), skipOffstage: false),
        findsNothing);
    final field = _field(tester);
    expect(field.controller.text, 'AUTUMN26');
    expect(field.readOnly, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('when a code is required the note asks for another one',
      (tester) async {
    final api = _FakeApi({'AUTUMN26': const ReferralWelcome.inactiveCampaignLink()});
    await _pump(tester, api, required: true);
    expect(find.text('Enter another referral code to continue.', skipOffstage: false),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
