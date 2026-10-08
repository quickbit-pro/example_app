import 'package:mobile_flutter/features/peer/presentation/peer_composer.dart';
import 'package:mobile_flutter/features/peer/application/peer_providers.dart';
import 'package:mobile_flutter/brands/example/example.dart';
// The nested navigator must keep the persistent rail accessible, while a
// root modal must hide and block that same navigation until it closes.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';

const _branding = AppBranding(
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

const _dashboard = DashboardSnapshot(
  profile: UserProfile(
    id: 'u1',
    name: 'Ali Deveci',
    email: 'ali@example.test',
    accountType: 'personal',
    kycStatus: 'approved',
    businessStatus: 'not_started',
    onboardingStatus: 'complete',
  ),
  accounts: [],
  cards: [],
  transactions: [],
  onboarding: [],
);

Widget _app(String location, {required bool equalsMoney}) {
  final themes = buildAppThemes(_branding);
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) => BankingShell(child: child),
        routes: [
          for (final path in ['/home', '/money', '/wallets/assets', '/cards'])
            GoRoute(
              path: path,
              builder: (context, state) => Column(children: [
                Text(path),
                ElevatedButton(
                    onPressed: () => showPeerComposerSheet(context,
                        mode: PeerComposerMode.request),
                    child: const Text('Open audit modal'))
              ]),
            ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      peerContactsProvider.overrideWith((ref) async => []),
      appConfigProvider.overrideWithValue(const AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'https://example.invalid',
        branding: _branding,
      )),
      mobileTenantConfigProvider
          .overrideWith((ref) async => MobileTenantConfig.fromJson({
                'features': {'equalsMoneyEnabled': equalsMoney}
              })),
      dashboardProvider.overrideWith((ref) async => _dashboard),
    ],
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('en'),
      supportedLocales: appLanguages.map((l) => l.locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('root modal blocks shell navigation and keeps the current route',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app('/home', equalsMoney: true));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final modalSemantics = tester.ensureSemantics();
    final navPosition = tester.getCenter(find.text('Cards').last);
    await tester.tap(find.text('Open audit modal'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.byType(PeerComposer), findsOneWidget);
    final modalTree = tester
        .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!
        .toStringDeep();
    expect(modalTree.contains('Cards'), isFalse);
    await tester.tapAt(navPosition);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(find.text('/home'), findsOneWidget);
    expect(find.text('/cards'), findsNothing);
    modalSemantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('segmented tabs each expose one named semantic control',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExampleSegmentedControl<int>(segments: const [
      (value: 0, label: 'Overview'),
      (value: 1, label: 'Friends')
    ], selected: 0, onChanged: (_) {}))));
    final tree = tester
        .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!
        .toStringDeep();
    expect(RegExp('label: "Friends"').allMatches(tree).length, 1);
    expect(RegExp('label: "Overview"').allMatches(tree).length, 1);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('nested routes preserve desktop rail in the semantics tree',
      (tester) async {
    tester.view.physicalSize = const Size(918, 736);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(_app('/cards', equalsMoney: true));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final tree = tester
        .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode!
        .toStringDeep();
    expect(tree.contains('Accounts'), isTrue);
    expect(tree.contains('Cards'), isTrue);
    expect(tree.contains('/cards'), isTrue);
    expect(find.byTooltip('Accounts'), findsOneWidget);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
