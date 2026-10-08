import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_lifecycle.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_member_status.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_level_lifecycle.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_member_status.dart';
import 'package:mobile_flutter/features/rewards/presentation/referral_explanation.dart';
import 'package:mobile_flutter/features/rewards/presentation/rewards_screen.dart';
import 'package:mobile_flutter/features/signup/presentation/referral_quote_terms.dart';
import 'package:mobile_flutter/features/signup/domain/referral_quote.dart';
import 'package:mobile_flutter/features/signup/presentation/referral_signup_outcome.dart';

Future<void> pump(WidgetTester tester, Widget child, {bool rtl = false}) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          home: Scaffold(
              body: MediaQuery(
                  data:
                      const MediaQueryData(textScaler: TextScaler.linear(2.5)),
                  child: Directionality(
                      textDirection:
                          rtl ? TextDirection.rtl : TextDirection.ltr,
                      child: SingleChildScrollView(child: child)))))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'phone forecast states assumptions and preserves accepted offers at large RTL text',
      (tester) async {
    await pump(
        tester,
        ReferralLevelLifecycleView(
            currency: 'USD',
            data: ReferralLevelLifecycle(
                programId: 'p',
                asOf: DateTime.utc(2026, 9, 15),
                currentLevel: const ReferralLevel(name: 'Elite'),
                forecast: ReferralLevelForecast(
                    effectiveAt: DateTime.utc(2026, 9, 20),
                    daysUntil: 5,
                    level: const ReferralLevel(
                        name: 'Starter',
                        topupCalculationType: 'PERCENT_OF_WL_FEE',
                        topupRate: 10)),
                existingOffersProtected: true,
                protectedRelationshipCount: 4,
                forecastAssumption: 'NO_FUTURE_ACTIVITY_OR_POLICY_CHANGES')),
        rtl: true);
    expect(
        find.text('Projection assumes no new activity or programme changes.'),
        findsOneWidget);
    expect(
        find.text(
            'Existing accepted offers stay unchanged. This level applies to new invitations.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unavailable lifecycle is not a zero or fabricated forecast',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          referralLevelLifecycleProvider.overrideWith((ref) async => null),
        ],
        child: const MaterialApp(
            home:
                Scaffold(body: ReferralLevelLifecycleCard(currency: 'USD')))));
    await tester.pumpAndSettle();
    expect(find.text('Level history and forecasts are unavailable.'),
        findsOneWidget);
    expect(find.byKey(const Key('referral_lifecycle_forecast')), findsNothing);
  });

  testWidgets(
      'pending signup and support reference do not claim a referral was accepted',
      (tester) async {
    await pump(
        tester,
        const ReferralSignupOutcomeView(
            outcome: ReferralSignupOutcome(ReferralSignupState.pending,
                correlationId: 'attempt-123')));
    expect(
        find.text(
            'Your account is created. Your referral is awaiting confirmation.'),
        findsOneWidget);
    expect(find.text('Your referral is confirmed.'), findsNothing);
    expect(find.text('attempt-123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted contractual terms retain their original language',
      (tester) async {
    await pump(
        tester,
        const ReferralAcceptedTermsCard(
            status: ReferralGeoStatus(
                attributed: true,
                status: 'PENDING',
                canPayout: false,
                acceptedTerms: 'Conditions originales acceptées',
                acceptedLocale: 'fr',
                acceptedVersion: 2)));
    expect(find.text('Referral payouts are not currently available.'),
        findsOneWidget);
    await tester.tap(find.text('Your accepted referral terms'));
    await tester.pumpAndSettle();
    expect(find.text('Conditions originales acceptées'), findsOneWidget);
    expect(find.text('Version 2 · language fr'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('durable incoming status is shown before the member can invite',
      (tester) async {
    const snapshot = RewardsSnapshot(
      config: MobileTenantConfig(
          companyName: 'Example',
          brandName: 'Example',
          referralsEnabled: true,
          referralRegistrationMode: 'code',
          vouchersEnabled: false,
          existingAccountClaimEnabled: false,
          boomFiExchangeEnabled: false,
          walletOutflowsEnabled: false,
          equalsMoneyEnabled: true),
      referralSummary: {'enabled': false},
    );
    await tester.pumpWidget(ProviderScope(overrides: [
      rewardsSnapshotProvider.overrideWith((ref) async => snapshot),
      referralAttributionOutcomeProvider.overrideWith((ref) async =>
          const ReferralSignupOutcome(ReferralSignupState.needsReview,
              correlationId: 'incoming-123')),
      referralGeoStatusProvider.overrideWith((ref) async => null),
    ], child: const MaterialApp(home: RewardsScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Your account is created. Your referral needs review.'),
        findsOneWidget);
    expect(find.text('incoming-123'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('financial receipt renders exact decimal strings',
      (tester) async {
    await pump(
        tester,
        ReferralRewardExplanationView(
            reward: ReferralReward.fromJson({
              'amount': '9',
              'currency': 'USD',
              'status': 'PAID',
              'balance': {
                'cashPaid': '123456789012.12345678',
                'offsetSettled': '0.00000001',
                'reservedCash': '1.23000000',
                'remainingPayable': '0.00000002',
                'legacyCashUnknown': false
              }
            }),
            usesVouchers: false));
    expect(find.text('123456789012.12345678 USD'), findsOneWidget);
    expect(find.text('0.00000001 USD'), findsOneWidget);
    expect(find.text('1.23000000 USD'), findsOneWidget);
    expect(find.text('0.00000002 USD'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'quoted boost caps and original Arabic terms remain readable in LTR UI',
      (tester) async {
    await pump(
        tester,
        ReferralQuoteTermsView(
            quote: ReferralQuote.fromJson({
          'quoteId': 'q',
          'registrationAttemptId': 'a',
          'termsVersion': 3,
          'termsText': 'شروط الإحالة الأصلية',
          'locale': 'ar',
          'termsHash': 't',
          'policyHash': 'p',
          'expiresAt': '2099-01-01T00:00:00Z',
          'eligibilityNotice': 'Original eligibility notice',
          'boosts': [
            {
              'name': 'September',
              'kind': 'MULTIPLIER',
              'multiplier': '2',
              'startsAt': '2026-09-15T00:00:00Z',
              'endsAt': '2026-09-16T00:00:00Z',
              'maximumIncrementalReward': '5.25',
              'currency': 'USD'
            }
          ],
        })));
    final terms = find.byKey(const Key('signup_referral_quoted_terms'));
    expect(Directionality.of(tester.element(terms)), TextDirection.rtl);
    expect(find.text('Original eligibility notice'), findsOneWidget);
    expect(find.textContaining('Maximum additional reward:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('accepted Arabic terms keep RTL in an English interface',
      (tester) async {
    await pump(
        tester,
        const ReferralAcceptedTermsCard(
            status: ReferralGeoStatus(
                attributed: true,
                status: 'ELIGIBLE',
                acceptedTerms: 'شروط الإحالة الأصلية',
                acceptedLocale: 'ar',
                acceptedVersion: 1)));
    await tester.tap(find.text('Your accepted referral terms'));
    await tester.pumpAndSettle();
    expect(
        Directionality.of(
            tester.element(find.byKey(const Key('referral_accepted_terms')))),
        TextDirection.rtl);
    expect(tester.takeException(), isNull);
  });
}
