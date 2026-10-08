import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/onboarding/presentation/account_setup_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/flavors.dart';

const _branding = AppBranding(
  appName: 'Example',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.test',
  supportPhone: '',
  legalEntity: 'Example',
);

final _lite = PlatformResource.fromJson(const {
  'Id': 1,
  'Name': 'Lite',
  'AccountType': 'personal',
  'MonthlyFee': 9.99,
  'TierLevel': 1,
  'IncludesEqualsIban': true,
});

class _Api extends MobilePlatformApi {
  _Api() : super(Dio());

  final selected = <int>[];

  @override
  Future<ActionResult> selectTier(
      {required int tierId, String? tierCycle}) async {
    selected.add(tierId);
    return const ActionResult(message: 'Tier changed');
  }

  @override
  Future<PlatformResource> getCurrentTier() async =>
      PlatformResource.fromJson(const {});
}

Future<_Api> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = _Api();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://127.0.0.1:1',
        branding: _branding,
      )),
      mobilePlatformApiProvider.overrideWithValue(api),
      dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
            profile: UserProfile.fromJson(const {
              'id': 'customer-1',
              'accountType': 'personal',
              'kycStatus': 'verified',
            }),
            accounts: const [],
            cards: const [],
            transactions: const [],
            onboarding: const [],
          )),
      currentTierProvider.overrideWith((ref) async => null),
      tiersProvider.overrideWith((ref) async => [_lite]),
      cardTierProvider('1')
          .overrideWith((ref) async => PlatformResource.fromJson(const {})),
    ],
    child: MaterialApp(
      theme: buildAppThemes(_branding).dark,
      home: const MediaQuery(
        data: MediaQueryData(size: Size(430, 1000), disableAnimations: true),
        child: AccountSetupScreen(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('reading what a tier includes never picks it', (tester) async {
    final api = await _pump(tester);

    await tester.ensureVisible(find.text("What's included"));
    await tester.tap(find.text("What's included"));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Account with IBAN included'), findsOneWidget);
    expect(find.text('Cards available with this plan'), findsOneWidget);
    expect(api.selected, isEmpty);

    // The sheet's own action is the explicit choice.
    await tester.ensureVisible(find.text('Choose this plan'));
    await tester.tap(find.text('Choose this plan'));
    await tester.pumpAndSettle();

    expect(api.selected, [1]);
    expect(find.text('Cards available with this plan'), findsNothing);
  });

  testWidgets('the tier row and its details are separate controls',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    // Each is its own node with its own tap, not folded into the station.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Select Lite')),
      matchesSemantics(
        label: 'Select Lite',
        isButton: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.bySemanticsLabel('What the Lite plan includes')),
      isSemantics(isButton: true, hasTapAction: true),
    );
    handle.dispose();
  });
}
