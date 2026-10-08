// One primary material per app.
//
// Eight screens were Example-themed in earlier waves but kept running their
// decisive action through a Material `FilledButton`, so the app answered "what
// do I press" with two different objects depending on which page you were on.
// This suite pins the five conversions that closed that, and — just as
// important — pins that every one of them is invisible to a white-label
// tenant, whose tree must keep the exact `FilledButton` it renders today.
//
// Each case runs at 375 (the phone floor) and 1440 (the desktop shell) in both
// Twilight and Pearl daylight, because a glass button resolves a completely
// different material per brightness and a regression in one theme is easy to
// miss from the other.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/presentation/accounts_screen.dart';
import 'package:mobile_flutter/features/business/application/business_providers.dart';
import 'package:mobile_flutter/features/business/presentation/business_screen.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/presentation/onboarding_banking_screen.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/rewards_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _exampleBranding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

/// A white-label tenant: no `ExampleBrand` extension on the theme, so every
/// converted CTA must fall through to the pre-Example `FilledButton`.
const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

const _widths = [375.0, 1440.0];

// -- fixtures ---------------------------------------------------------------

const _tenantConfig = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'code',
  vouchersEnabled: false,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);

const _referralSnapshot = RewardsSnapshot(
  config: _tenantConfig,
  referralSummary: {
    'referralCode': 'EXAMPLE-7788',
    'referralPath': 'https://example.test/r/EXAMPLE-7788',
    'currentLevel': {'name': 'Level 2'},
    'progress': {'currentValue': 3, 'nextThreshold': 10},
    'referrals': {'Invited': 6, 'Successful': 2, 'InProgress': 4},
    'commissions': {'Available': '42.50', 'Currency': 'EUR'},
  },
);

/// A provider action that is blocking the customer: the required-action card
/// renders this as the whole body on Accounts and on Money.
const _blockingKyc = KycDetailedStatus(
  hoppaStatus: 'approved',
  bankStatus: 'action_required',
  cardIssuerStatus: 'pending',
  nextAction: 'equals_money_action',
  equalsMoneyRequiredAction: 'liveness_check',
  equalsMoneyActionUrl: 'https://provider.test/liveness',
);

/// Nothing outstanding, so Accounts shows its ledger (and the sandbox panel).
const _clearKyc = KycDetailedStatus(
  hoppaStatus: 'approved',
  bankStatus: 'approved',
  cardIssuerStatus: 'approved',
  nextAction: '',
  equalsMoneyAccountId: 'em-1',
  equalsMoneyApproved: true,
);

/// A realistic multi-currency Equals account. Its dropdown label — the name
/// plus its supported currencies — is long enough that the sandbox panel's
/// account field overflowed by 120 px at 375 before `isExpanded` bounded it,
/// so this fixture is also the 375-width regression guard.
const _equalsAccount = AccountBalance(
  id: 'acc-1',
  name: 'Main account',
  iban: 'GB29NWBK60161331926819',
  balance: Money(currency: 'GBP', minorUnits: 125000),
  available: Money(currency: 'GBP', minorUnits: 125000),
  provider: 'equalsmoney',
  supportedCurrencies: ['GBP', 'EUR'],
);

/// The same account with a label short enough to fit an unbounded dropdown.
///
/// The white-label case has to use it: that tenant's dropdown is deliberately
/// left exactly as it renders today, `isExpanded` and all, so it still
/// overflows on the long label. That overflow predates this change and is
/// reported as a follow-up rather than fixed here, because fixing it would
/// move a non-Example tenant's pixels.
const _shortLabelAccount = AccountBalance(
  id: 'acc-1',
  name: 'Main',
  iban: 'GB29NWBK60161331926819',
  balance: Money(currency: 'GBP', minorUnits: 125000),
  available: Money(currency: 'GBP', minorUnits: 125000),
  provider: 'equalsmoney',
  supportedCurrencies: ['GBP'],
);

// -- harness ----------------------------------------------------------------

Widget _host({
  required Widget child,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
  bool reducedMotion = false,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      // Brightness is chosen by picking the ThemeData, so the mode only has to
      // point at `theme`.
      themeMode: ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child,
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget app, {
  required double width,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

/// Every glass CTA on screen clears the 44 pt target floor from the laws, in
/// both themes and at both widths.
void _expectTargetsClear(WidgetTester tester) {
  for (final element in find.byType(ExampleGlassButton).evaluate()) {
    final size = tester.getSize(find.byWidget(element.widget));
    expect(
      size.height,
      greaterThanOrEqualTo(ExampleGlassButton.minTouchTarget),
      reason: 'a glass CTA fell under the 44 pt target floor',
    );
  }
}

// -- provider sets ----------------------------------------------------------

List<Override> _rewardsOverrides() => [
      rewardsSnapshotProvider.overrideWith((ref) async => _referralSnapshot),
    ];

List<Override> _accountsOverrides({bool shortLabel = false}) => [
      kycDetailedStatusProvider.overrideWith((ref) async => _clearKyc),
      accountsProvider.overrideWith(
        (ref) async => [shortLabel ? _shortLabelAccount : _equalsAccount],
      ),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => const []),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenantConfig),
    ];

/// The money surface reaches its payees tab only through a full dashboard, so
/// the graph has to be complete: a profile that is bank-onboarded, an account
/// so `canUseBanking` is true, and an empty payee book so the tab opens on its
/// "Add payee" state rather than on the confirm form.
List<Override> _moneyOverrides() => [
      kycDetailedStatusProvider.overrideWith((ref) async => _clearKyc),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenantConfig),
      budgetsProvider.overrideWith((ref) async => const []),
      equalsBankingInfoProvider.overrideWith((ref) async => const []),
      accountsProvider.overrideWith((ref) async => [_equalsAccount]),
      payeesProvider.overrideWith((ref) async => const <Payee>[]),
      dashboardProvider.overrideWith(
        (ref) async => const DashboardSnapshot(
          profile: UserProfile(
            id: 'u-1',
            name: 'Test Customer',
            email: 'test@example.test',
            accountType: 'personal',
            kycStatus: 'approved',
            businessStatus: 'not_started',
            onboardingStatus: 'approved',
          ),
          accounts: [_equalsAccount],
          cards: [],
          transactions: [],
          onboarding: [],
        ),
      ),
    ];

List<Override> _businessOverrides({required bool submitted}) => [
      businessOnboardingStatusProvider.overrideWith(
        (ref) async => <String, dynamic>{
          'status': submitted ? 'in_review' : 'not_started',
          'requiredAction': 'identity_verification',
          'actionUrl': 'https://provider.test/secure-check',
        },
      ),
      businessOnboardingOptionsProvider.overrideWith(
        (ref) async => BusinessOnboardingOptions.fromJson(
          const <String, dynamic>{},
        ),
      ),
    ];

void main() {
  // -------------------------------------------------------------------------
  // Rewards — the offer card's "Share", with "Copy link" and "Invite by
  // email" as its paired second choices.
  // -------------------------------------------------------------------------
  group('Rewards invite CTA', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('is the house glass at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const RewardsScreen(),
              width: width,
              brightness: brightness,
              overrides: _rewardsOverrides(),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          // One Share control on the page — the desktop workspace also
          // names a Share *tab*, which is a nav item, not a glass button.
          final share = find.widgetWithText(ExampleGlassButton, 'Share',
              skipOffstage: false);
          expect(share, findsOneWidget);

          final glass = tester.widget<ExampleGlassButton>(share);
          expect(glass.tone, ExampleGlassButtonTone.primary);
          // A panel is a painted surface: `surface` is the ground that cannot
          // dissolve, and it is what keeps this button opaque over the frosted
          // panel it sits on.
          expect(glass.ground, ExampleGlassGround.surface);
          // The screen's single sweep belongs to the tier hairline.
          expect(glass.sheen, isFalse);
          // The paired second choice is the same material, one tone down:
          // the email invitation under Share on the phone's offer card, Copy
          // link beside Share in the desktop link row.
          final paired = tester.widget<ExampleGlassButton>(
            find.widgetWithText(
              ExampleGlassButton,
              width < ExampleBreakpoints.desktop ? 'Invite by email' : 'Copy link',
              skipOffstage: false,
            ),
          );
          expect(paired.tone, ExampleGlassButtonTone.neutral);
          expect(paired.sheen, isFalse);
          // The Material slab is gone from the Example referral panel.
          expect(
            find.widgetWithText(FilledButton, 'Invite by email',
                skipOffstage: false),
            findsNothing,
          );
          _expectTargetsClear(tester);
        });
      }
    }

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const RewardsScreen(),
          width: 375,
          brightness: Brightness.light,
          overrides: _rewardsOverrides(),
          textScale: 1.3,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Invite by email'), findsOneWidget);
      _expectTargetsClear(tester);
    });

    testWidgets('reaches its final state instantly under reduced motion',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const RewardsScreen(),
          width: 375,
          brightness: Brightness.dark,
          overrides: _rewardsOverrides(),
          reducedMotion: true,
        ),
        width: 375,
      );

      // pumpAndSettle would hide a loop; a single frame is the real proof that
      // nothing is still animating.
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Invite by email'), findsOneWidget);
    });

    testWidgets('a white-label tenant keeps its FilledButton', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const RewardsScreen(),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _rewardsOverrides(),
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.text('Email invite'), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // The provider's required-action card. Defined in onboarding_banking, but
  // rendered as the whole body by Accounts and by Money — which is why the
  // conversion had to be gated rather than assumed onboarding-only.
  // -------------------------------------------------------------------------
  group('EqualsMoney required-action CTA', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('is the house glass at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const Scaffold(
                body: EqualsMoneyRequiredActionCard(status: _blockingKyc),
              ),
              width: width,
              brightness: brightness,
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final glass = tester.widget<ExampleGlassButton>(
            find.byType(ExampleGlassButton),
          );
          expect(glass.label, 'Continue liveness check');
          expect(glass.tone, ExampleGlassButtonTone.primary);
          expect(glass.ground, ExampleGlassGround.surface);
          expect(find.byType(FilledButton), findsNothing);
          _expectTargetsClear(tester);
        });
      }
    }

    testWidgets('a white-label tenant keeps its FilledButton', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const Scaffold(
            body: EqualsMoneyRequiredActionCard(status: _blockingKyc),
          ),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Continue liveness check'),
        findsOneWidget,
      );
    });

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const Scaffold(
            body: EqualsMoneyRequiredActionCard(status: _blockingKyc),
          ),
          width: 375,
          brightness: Brightness.light,
          textScale: 1.3,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      _expectTargetsClear(tester);
    });
  });

  // -------------------------------------------------------------------------
  // Accounts — the sandbox fund-test panel. Deliberately `neutral`: the
  // ledger has no decisive action, and a staging-only control must never be
  // the loudest object on a banking screen.
  // -------------------------------------------------------------------------
  group('Accounts sandbox funding CTA', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('is quiet house glass at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const Scaffold(body: AccountsContent()),
              width: width,
              brightness: brightness,
              overrides: _accountsOverrides(),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final glass = tester.widget<ExampleGlassButton>(
            find.widgetWithText(ExampleGlassButton, 'Fund test balance'),
          );
          expect(glass.tone, ExampleGlassButtonTone.neutral);
          expect(glass.ground, ExampleGlassGround.surface);
          expect(glass.expand, isFalse);
          expect(glass.sheen, isFalse);
          expect(
            find.widgetWithText(FilledButton, 'Fund test balance'),
            findsNothing,
          );
          _expectTargetsClear(tester);
        });
      }
    }

    testWidgets('a white-label tenant keeps its FilledButton', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const Scaffold(body: AccountsContent()),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _accountsOverrides(shortLabel: true),
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Fund test balance'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Business — the provider escalation inside the KYB status panel. Its tone
  // is the judgement: quiet while the pinned bar owns Submit, primary once the
  // bar is gone and it is the only action left.
  // -------------------------------------------------------------------------
  group('Business secure-check CTA', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('defers to the submit bar at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const BusinessScreen(),
              width: width,
              brightness: brightness,
              overrides: _businessOverrides(submitted: false),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final glass = tester.widget<ExampleGlassButton>(
            find.widgetWithText(ExampleGlassButton, 'Continue secure check'),
          );
          expect(glass.tone, ExampleGlassButtonTone.neutral);
          expect(glass.ground, ExampleGlassGround.surface);
          // The bar's own primary is still the screen's one loud object.
          expect(
            find.widgetWithText(ExampleGlassButton, 'Continue'),
            findsOneWidget,
          );
          expect(
            find.widgetWithText(FilledButton, 'Continue secure check'),
            findsNothing,
          );
          _expectTargetsClear(tester);
        });

        testWidgets('takes the primary once submitted at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const BusinessScreen(),
              width: width,
              brightness: brightness,
              overrides: _businessOverrides(submitted: true),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final glass = tester.widget<ExampleGlassButton>(
            find.widgetWithText(ExampleGlassButton, 'Continue secure check'),
          );
          expect(glass.tone, ExampleGlassButtonTone.primary);
          // Submitted removes the CTA bar, so this is the screen's only glass.
          expect(find.byType(ExampleGlassButton), findsOneWidget);
          _expectTargetsClear(tester);
        });
      }
    }

    testWidgets('a white-label tenant keeps its FilledButton', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BusinessScreen(),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _businessOverrides(submitted: true),
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Continue secure check'),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Money — the payees tab's "Add payee". The tab's commit further down was
  // already glass, so this one Material slab made a single tab answer "what do
  // I press" with two materials. The two never co-render.
  // -------------------------------------------------------------------------
  group('Money add-payee CTA', () {
    for (final width in _widths) {
      for (final brightness in Brightness.values) {
        testWidgets('is the house glass at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const MoneyScreen(initialTab: MoneyTab.payees),
              width: width,
              brightness: brightness,
              overrides: _moneyOverrides(),
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);
          final glass = tester.widget<ExampleGlassButton>(
            find.widgetWithText(ExampleGlassButton, 'Add payee'),
          );
          expect(glass.tone, ExampleGlassButtonTone.primary);
          expect(glass.ground, ExampleGlassGround.surface);
          expect(
            find.widgetWithText(FilledButton, 'Add payee'),
            findsNothing,
          );
          // Scan QR stays the quieter control beside it: one emphasis, not two.
          expect(
            find.widgetWithText(OutlinedButton, 'Scan QR'),
            findsOneWidget,
          );
          _expectTargetsClear(tester);
        });
      }
    }

    testWidgets('a white-label tenant keeps its FilledButton', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const MoneyScreen(initialTab: MoneyTab.payees),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _moneyOverrides(),
        ),
        width: 375,
      );

      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Add payee'),
        findsOneWidget,
      );
      // The legacy money header (`_EqualsMoneyHeader`, money_screen.dart:903)
      // overflows its own Row by 27 px at 375. It predates this change, it is
      // in the non-Example branch, and moving it would move a tenant's pixels —
      // so it is reported as a follow-up and drained here rather than
      // asserted away. The Example cases above still assert a clean frame.
      final legacy = tester.takeException();
      expect(legacy, isA<FlutterError>());
      expect('$legacy', contains('overflowed'));
    });
  });
}
