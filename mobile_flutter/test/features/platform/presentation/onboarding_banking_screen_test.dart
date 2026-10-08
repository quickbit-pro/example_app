import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/presentation/onboarding_banking_screen.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

class _Api extends MobilePlatformApi {
  _Api(this.approved) : super(Dio());
  bool approved;
  bool fail = false;
  int statusReads = 0;
  @override
  Future<KycDetailedStatus> getDetailedKycStatus() async {
    statusReads++;
    if (fail) throw Exception('offline');
    return KycDetailedStatus.fromJson({'HoppaCardKycApproved': approved});
  }

  /// What `tiers/current` answers: a chosen tier unless a test clears it.
  Map<String, dynamic> currentTier = const {'TierId': 3, 'SelectedTierId': 3};
  bool tierLookupFails = false;
  @override
  Future<PlatformResource> getCurrentTier() async {
    if (tierLookupFails) throw Exception('offline');
    return PlatformResource.fromJson(currentTier);
  }
}

class _Picker extends FilePicker {
  bool readBytes = false;
  FilePickerResult? result;
  @override
  Future<FilePickerResult?> pickFiles(
      {String? dialogTitle,
      String? initialDirectory,
      FileType type = FileType.any,
      List<String>? allowedExtensions,
      Function(FilePickerStatus)? onFileLoading,
      bool allowCompression = true,
      int compressionQuality = 30,
      bool allowMultiple = false,
      bool withData = false,
      bool withReadStream = false,
      bool lockParentWindow = false,
      bool readSequential = false}) async {
    readBytes = withData;
    return result;
  }
}

Future<void> _pumpScreen(WidgetTester tester, _Api api,
    {bool example = true, bool business = false}) async {
  final router = GoRouter(initialLocation: '/onboarding/banking', routes: [
    GoRoute(
        path: '/onboarding/banking',
        builder: (_, __) => const OnboardingBankingScreen()),
    GoRoute(
        path: '/kyc',
        builder: (_, __) => const Scaffold(body: Text('Identity screen'))),
    GoRoute(
        path: '/business',
        builder: (_, __) => const Scaffold(body: Text('Business screen'))),
    GoRoute(
        path: '/tiers',
        builder: (_, __) => const Scaffold(body: Text('Tiers screen'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
      overrides: [
        mobilePlatformApiProvider.overrideWithValue(api),
        mobileTenantConfigProvider
            .overrideWith((ref) async => MobileTenantConfig.fromJson({})),
        dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
              profile: UserProfile.fromJson(
                  {'accountType': business ? 'business' : 'personal'}),
              accounts: const [],
              cards: const [],
              transactions: const [],
              onboarding: const [],
            )),
        providersProvider.overrideWith((ref) async => []),
        budgetsProvider.overrideWith((ref) async => []),
      ],
      child: MaterialApp.router(
          routerConfig: router,
          theme: ThemeData(extensions: [
            if (example) const ExampleBrand(),
            const AppDesignTheme(
                design: AppDesign({
                  'motion': {'enabled': false}
                }),
                appName: 'Hoppa'),
          ]))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('desktop install panel and empty card use configured app name',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const branding = AppBranding(
        appName: 'Acme Pay',
        primarySeedHex: '7044FF',
        accentSeedHex: 'CCFF00',
        loginBackgroundHex: '',
        themeMode: 'light',
        fontFamily: '',
        logoAsset: '',
        radiusScale: '1',
        supportEmail: '',
        supportPhone: '',
        legalEntity: '',
        design: AppDesign({
          'layout': 'example',
          'motion': {'enabled': false}
        }));
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
          path: '/home',
          builder: (_, __) =>
              const BankingShell(child: Scaffold(body: Text('Home body')))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(const AppConfig(
              flavor: AppFlavor.dev,
              apiBaseUrl: 'https://example.test',
              branding: branding)),
          mobileTenantConfigProvider
              .overrideWith((ref) async => MobileTenantConfig.fromJson({})),
          dashboardProvider.overrideWith((ref) async => DashboardSnapshot(
                profile: UserProfile.fromJson({}),
                accounts: const [],
                cards: const [],
                transactions: const [],
                onboarding: const [],
              )),
        ],
        child: MaterialApp.router(
            routerConfig: router, theme: buildAppThemes(branding).light)));
    await tester.pumpAndSettle();
    expect(find.text('Install Acme Pay'), findsOneWidget);
    expect(
        find.text('Order your Acme Pay card to see it here.'), findsOneWidget);
    expect(find.textContaining('Example'), findsNothing);
    await tester.ensureVisible(find.text('Install app'));
    await tester.tap(find.text('Install app'));
    await tester.pump();
    expect(
        find.textContaining('to add Acme Pay to this device.'), findsOneWidget);
  }, skip: !kIsWeb);

  for (final example in [true, false]) {
    testWidgets('unverified users go to identity, layout=$example',
        (tester) async {
      await _pumpScreen(tester, _Api(false), example: example);
      expect(find.text('Start EqualsMoney'), findsNothing);
      await tester.tap(find.text('Continue identity verification'));
      await tester.pumpAndSettle();
      expect(find.text('Identity screen'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  testWidgets('stale approval is rechecked before showing the form',
      (tester) async {
    final api = _Api(true);
    await _pumpScreen(tester, api);
    api.approved = false;
    await tester.tap(find.text('Start EqualsMoney'));
    await tester.pumpAndSettle();
    expect(api.statusReads, greaterThan(1));
    expect(find.text('Identity screen'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });
  testWidgets('status failure does not open banking form', (tester) async {
    final api = _Api(true);
    await _pumpScreen(tester, api);
    api.fail = true;
    await tester.tap(find.text('Start EqualsMoney'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Unable to verify identity status. Please try again.'),
        findsOneWidget);
  });
  for (final example in [true, false]) {
    testWidgets(
        'opening an account without a tier leads to the tiers first, '
        'example=$example', (tester) async {
      final api = _Api(true)..currentTier = const {};
      await _pumpScreen(tester, api, example: example);
      await tester.tap(find.text('Start EqualsMoney').last);
      await tester.pumpAndSettle();

      // The notice, not the application form the provider would refuse.
      expect(find.text('Choose a tier first'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);

      await tester.tap(find.text('Choose a tier'));
      await tester.pumpAndSettle();
      expect(find.text('Tiers screen'), findsOneWidget);
    });
  }
  testWidgets('the notice can be dismissed without leaving', (tester) async {
    final api = _Api(true)..currentTier = const {};
    await _pumpScreen(tester, api);
    await tester.tap(find.text('Start EqualsMoney'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a tier first'), findsNothing);
    expect(find.text('Start EqualsMoney'), findsOneWidget);
  });
  testWidgets('an unknown tier does not block the application form',
      (tester) async {
    final api = _Api(true)..tierLookupFails = true;
    await _pumpScreen(tester, api);
    await tester.tap(find.text('Start EqualsMoney'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a tier first'), findsNothing);
    expect(find.text('Main purposes'), findsWidgets);
  });
  testWidgets('business onboarding keeps the business route', (tester) async {
    await _pumpScreen(tester, _Api(false), business: true);
    await tester.tap(find.text('Start business onboarding'));
    await tester.pumpAndSettle();
    expect(find.text('Business screen'), findsOneWidget);
  });
  for (final extension in ['pdf', 'jpg']) {
    testWidgets('pathless $extension selection clears required warning',
        (tester) async {
      final picker = _Picker()
        ..result = FilePickerResult([
          PlatformFile(
            name: 'address.$extension',
            size: 3,
            bytes: Uint8List.fromList([65, 66, 67]),
          )
        ]);
      FilePicker.platform = picker;
      await _pumpScreen(tester, _Api(true));
      await tester.tap(find.text('Start EqualsMoney'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Choose'));
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(picker.readBytes, isTrue);
      expect(find.text('address.$extension'), findsOneWidget);
      expect(find.text('Proof of address is required.'), findsNothing);
      // Cancelling another selection retains the selected document.
      picker.result = null;
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      expect(find.text('address.$extension'), findsOneWidget);
    });
  }
}
