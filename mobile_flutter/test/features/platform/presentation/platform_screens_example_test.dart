import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/presentation/banking_services_screen.dart';
import 'package:mobile_flutter/features/platform/presentation/tiers_screen.dart';
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

/// A white-label tenant: no `ExampleBrand` extension, so both screens must fall
/// through to their pre-Example trees.
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

final _starter = PlatformResource.fromJson(const {
  'TierId': 1,
  'name': 'Starter',
  'description': 'the plan every account starts on',
  'tierLevel': 1,
  'monthlyFee': '0',
  'currencyCode': 'EUR',
  'features': ['virtual card'],
  'limits': {'dailyLimit': '500'},
});

final _premium = PlatformResource.fromJson(const {
  'TierId': 7,
  'name': 'Premium',
  'description': 'higher limits and priority support',
  'tierLevel': 2,
  'monthlyFee': '9.99',
  'yearlyFee': '99.99',
  'currencyCode': 'EUR',
  'isPopular': true,
  'maxCards': 5,
  'features': ['priority support'],
  'benefits': [
    {'name': 'airport lounge'},
  ],
  'limits': {'dailyLimit': '2500', 'monthlyLimit': '10000'},
  'cardBenefits': [
    {
      'cardTypeName': 'Virtual Premium',
      'freeCardsIncluded': 2,
      'issueFee': '0',
      'currencyCode': 'EUR',
    },
  ],
});

/// `GET tiers/card-tier/7`: the cards the Premium plan carries.
final _premiumCards = PlatformResource.fromJson(const {
  'CardTypeTiers': [
    {
      'CardTypeId': 3,
      'TierId': 7,
      'FreeCardsIncluded': 1,
      'FreeCardsPeriod': 'lifetime',
      'MonthlySubscriptionFee': null,
      'MaxCards': 10,
      'IsActive': true,
      'CardType': {
        'Id': 3,
        'Name': 'Premium Virtual',
        'Description': 'Spend your crypto anywhere in the world.',
        'Features': ['Contactless Payment', 'GOOGLE_PAY'],
        'MonthlyFee': 0.1,
        'IssuanceFee': 0.1,
        'MonthlySubscriptionFee': 0.1,
        'ReplacementFee': 5,
        'CurrencyCode': 'USD',
        'IsEnabled': true,
        'IsVirtual': true,
      },
    },
    {
      'CardTypeId': 4,
      'IsActive': false,
      'CardType': {'Id': 4, 'Name': 'Retired Card', 'IsEnabled': true},
    },
  ],
});

final _balances = [
  PlatformResource.fromJson(const {
    'BalanceId': 'b-eur',
    'currency': 'EUR',
    'available': '1250.5',
    'provider': 'modulr',
  }),
  PlatformResource.fromJson(const {
    'BalanceId': 'b-usd',
    'currency': 'USD',
    'balance': 830.25,
    'provider': 'modulr',
  }),
];

List<Override> get _tierOverrides => [
      tiersProvider.overrideWith((ref) async => [_starter, _premium]),
      currentTierProvider.overrideWith((ref) async => _starter),
    ];

List<Override> get _balanceOverrides => [
      bankingBalancesProvider.overrideWith((ref) async => _balances),
    ];

Widget _host({
  required Widget child,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
  bool reducedMotion = false,
  bool sheenScope = false,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      // The brightness is chosen by picking the ThemeData, so the mode only
      // has to point at `theme`.
      themeMode: ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: sheenScope ? ExampleSheenScope(child: child) : child,
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

void main() {
  group('Example tiers', () {
    for (final width in const [375.0, 393.0, 834.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('reads as a plan ladder at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const TiersScreen(),
              width: width,
              brightness: brightness,
              overrides: _tierOverrides,
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);

          // Headline states the plan once.
          expect(find.text('CURRENT TIER'), findsOneWidget);
          expect(find.text('Active'), findsOneWidget);
          expect(
            find.text('Your plan is active. Compare it with the tiers below.'),
            findsOneWidget,
          );
          // Prose is left as prose, not title-cased into "Higher Limits And
          // Priority Support".
          expect(
            find.text('Higher limits and priority support'),
            findsOneWidget,
          );

          // The headline gives the monthly price, and the detail keeps both
          // published billing options available for comparison.
          expect(find.text('Free'), findsOneWidget);
          expect(
            find.descendant(
              of: find.byType(ExampleAmount),
              matching: find.textContaining('9.99'),
            ),
            findsOneWidget,
          );
          expect(find.text('per month'), findsNWidgets(2));
          expect(
            find.text('Price monthly 9.99 EUR · yearly 99.99 EUR'),
            findsOneWidget,
          );

          // Weight is spent once: one filled CTA, one recommendation pill,
          // and the plan you are on holds the slot without a button.
          expect(find.byType(ExampleGlassButton), findsOneWidget);
          expect(find.text('Choose this plan'), findsOneWidget);
          expect(find.text('Most popular'), findsOneWidget);
          expect(find.text('Current'), findsOneWidget);
          expect(find.text('You are on this plan'), findsOneWidget);

          // Numbers land in the spec table, inclusions in the list.
          expect(find.text('Monthly limit'), findsOneWidget);
          expect(find.text('10,000'), findsOneWidget);
          expect(find.text('Cards included'), findsOneWidget);
          expect(find.text('Priority Support'), findsOneWidget);
          expect(find.text('Airport Lounge'), findsOneWidget);
          // The label prefix is dropped next to the check mark.
          expect(find.text('Feature Priority Support'), findsNothing);
          // The shared line's U+2022 is normalised to the Latin-1 middle dot
          // every other Example screen separates facts with.
          expect(
            find.text(
                'Card Virtual Premium \u00B7 free cards 2 \u00B7 issue 0 EUR'),
            findsOneWidget,
          );
          expect(find.textContaining('\u2022'), findsNothing);
        });
      }
    }

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 375,
          brightness: Brightness.light,
          overrides: _tierOverrides,
          textScale: 1.3,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Choose this plan'), findsOneWidget);
      expect(find.text('You are on this plan'), findsOneWidget);
    });

    testWidgets('lands the actions on one baseline at desktop width',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 1440,
          brightness: Brightness.dark,
          overrides: _tierOverrides,
        ),
        width: 1440,
      );

      final cta = tester.getBottomLeft(find.byType(ExampleGlassButton));
      final held = tester.getBottomLeft(find.byKey(currentPlanSlotKey));
      // Two columns, equalised by the run's IntrinsicHeight: the panels are
      // side by side and their actions share a baseline.
      expect(cta.dx, greaterThan(held.dx));
      expect(cta.dy, closeTo(held.dy, 1));
    });

    testWidgets('stacks into one column on a phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 375,
          brightness: Brightness.dark,
          overrides: _tierOverrides,
        ),
        width: 375,
      );

      final cta = tester.getTopLeft(find.byType(ExampleGlassButton));
      final held = tester.getTopLeft(find.byKey(currentPlanSlotKey));
      expect(cta.dy, greaterThan(held.dy));
    });

    testWidgets('starts no ticker under reduced motion', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 393,
          brightness: Brightness.dark,
          overrides: _tierOverrides,
          reducedMotion: true,
          sheenScope: true,
        ),
        width: 393,
      );

      // pumpAndSettle above would have timed out on a looping sheen: reaching
      // here is the proof that the reduced-motion path paints the settled
      // state and schedules nothing.
      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsOneWidget);
      expect(find.text('Free'), findsOneWidget);
    });

    testWidgets('offers a way back when the service publishes no tiers',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 375,
          brightness: Brightness.light,
          overrides: [
            tiersProvider.overrideWith((ref) async => <PlatformResource>[]),
            currentTierProvider.overrideWith((ref) async => null),
          ],
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No plans to compare yet'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
      expect(find.text('No tier selected'), findsOneWidget);
      expect(find.byType(ExampleGlassButton), findsNothing);
    });

    testWidgets('says what a plan includes only when asked', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 393,
          brightness: Brightness.dark,
          overrides: [
            ..._tierOverrides,
            cardTierProvider('7').overrideWith((ref) async => _premiumCards),
          ],
        ),
        width: 393,
      );

      // Folded away on the ladder: one quiet control per plan.
      expect(find.text("What's included"), findsNWidgets(2));
      expect(find.text('Cards available with this plan'), findsNothing);

      await tester.ensureVisible(find.text("What's included").last);
      await tester.pumpAndSettle();
      await tester.tap(find.text("What's included").last);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Cards available with this plan'), findsOneWidget);
      expect(find.text('Priority Support'), findsWidgets);
      expect(find.text('Premium Virtual'), findsOneWidget);
      expect(find.text('Retired Card'), findsNothing);
      expect(find.text('Contactless Payment'), findsOneWidget);
      expect(find.text('Google Pay'), findsOneWidget);
      expect(find.text('1 in total (lifetime)'), findsOneWidget);
      expect(find.text('Maximum cards you can order'), findsOneWidget);
      // Issuance, card subscription and service fee; the plan sets no card
      // subscription of its own, which the provider's page calls free.
      expect(find.text('\$0.10'), findsNWidgets(3));
      expect(find.text('Plan card subscription / month'), findsOneWidget);
      expect(
        find.text('Account and card activation are subject to verification.'),
        findsOneWidget,
      );

      // The rarer charges stay folded until asked for.
      expect(find.text('Replacement fee'), findsNothing);
      await tester.ensureVisible(find.text('Additional fees'));
      await tester.tap(find.text('Additional fees'));
      await tester.pumpAndSettle();
      expect(find.text('Replacement fee'), findsOneWidget);
      expect(find.text('\$5.00'), findsOneWidget);

      // Reading is not choosing: the sheet offers the plan's action but
      // nothing was selected by opening it.
      expect(find.text('Choose this plan'), findsNWidgets(2));
      await tester.ensureVisible(find.text('Close'));
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Cards available with this plan'), findsNothing);
    });

    testWidgets('the plan you are on opens without a choose action',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 393,
          brightness: Brightness.light,
          overrides: [
            ..._tierOverrides,
            cardTierProvider('1').overrideWith(
                (ref) async => PlatformResource.fromJson(const {})),
          ],
        ),
        width: 393,
      );

      await tester.tap(find.text("What's included").first);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
          find.text('No cards are listed for this plan yet.'), findsOneWidget);
      // Only the ladder's own button remains; the sheet adds none.
      expect(find.text('Choose this plan'), findsOneWidget);
      expect(find.text('Current'), findsNWidgets(2));
    });

    testWidgets('a white-label tenant still gets the pre-Example screen',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const TiersScreen(),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _tierOverrides,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.text('Choose this plan'), findsNothing);
      expect(find.text('Select'), findsOneWidget);
      expect(
        find.text('Price monthly 9.99 EUR • yearly 99.99 EUR'),
        findsWidgets,
      );
    });
  });

  group('Example banking services', () {
    for (final width in const [375.0, 393.0, 834.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('sets the balances as money at $width in $brightness',
            (tester) async {
          await _pumpAt(
            tester,
            _host(
              child: const BankingServicesScreen(),
              width: width,
              brightness: brightness,
              overrides: _balanceOverrides,
            ),
            width: width,
          );

          expect(tester.takeException(), isNull);

          expect(find.text('Provider balances'), findsOneWidget);
          expect(find.text('Safeguarding statement'), findsOneWidget);
          expect(find.text('EUR'), findsOneWidget);
          expect(find.text('USD'), findsOneWidget);
          expect(find.textContaining('1,250.50'), findsOneWidget);
          expect(find.textContaining('830.25'), findsOneWidget);
          expect(find.text('Modulr'), findsNWidgets(2));

          // One decisive control, and it says what it will do.
          expect(find.byType(ExampleGlassButton), findsOneWidget);
          expect(find.text('Lock a EUR to USD rate'), findsOneWidget);
          expect(find.textContaining('€100.00'), findsOneWidget);
        });
      }
    }

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BankingServicesScreen(),
          width: 375,
          brightness: Brightness.light,
          overrides: _balanceOverrides,
          textScale: 1.3,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Lock a EUR to USD rate'), findsOneWidget);
    });

    testWidgets('keeps the amounts aligned in one column', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BankingServicesScreen(),
          width: 393,
          brightness: Brightness.dark,
          overrides: _balanceOverrides,
        ),
        width: 393,
      );

      final eur = tester.getTopRight(find.textContaining('1,250.50'));
      final usd = tester.getTopRight(find.textContaining('830.25'));
      expect(eur.dx, closeTo(usd.dx, 0.5));
    });

    testWidgets('offers a way back when no balance has landed', (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BankingServicesScreen(),
          width: 375,
          brightness: Brightness.light,
          overrides: [
            bankingBalancesProvider
                .overrideWith((ref) async => <PlatformResource>[]),
          ],
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('No balances to show yet'), findsOneWidget);
      expect(find.text('Check again'), findsOneWidget);
    });

    testWidgets('falls back to the shared list when nothing parses',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BankingServicesScreen(),
          width: 375,
          brightness: Brightness.dark,
          overrides: [
            bankingBalancesProvider.overrideWith(
              (ref) async => [
                PlatformResource.fromJson(const {
                  'BalanceId': 'b-x',
                  'title': 'Reserve',
                  'status': 'pending',
                }),
              ],
            ),
          ],
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Reserve'), findsOneWidget);
      expect(find.byType(ExampleAmount), findsNothing);
    });

    testWidgets('a white-label tenant still gets the pre-Example screen',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          child: const BankingServicesScreen(),
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _balanceOverrides,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.text('Create EUR to USD quote'), findsOneWidget);
      expect(find.text('Lock a EUR to USD rate'), findsNothing);
    });
  });
}
