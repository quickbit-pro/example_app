// The desktop rail marks the open section by route, not by label.
//
// A customer running the app in German opened Accounts and saw no rail item
// lit: the shell had been picking the Accounts entry by comparing its
// translated label with the English word, so "Konten" never matched.
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
              builder: (context, state) => Center(child: Text(path)),
            ),
        ],
      ),
    ],
  );
  return ProviderScope(
    overrides: [
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
      locale: const Locale('de'),
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

bool _railSelected(WidgetTester tester, String label) {
  final semantics = tester.widget<Semantics>(find.descendant(
    of: find.byTooltip(label),
    matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == label),
  ));
  return semantics.properties.selected ?? false;
}

void main() {
  for (final (location, equalsMoney) in const [
    ('/money', true),
    ('/wallets/assets', false),
  ]) {
    testWidgets('the German rail marks Konten as open at $location',
        (tester) async {
      tester.view.physicalSize = const Size(1024, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      // The German copy is an asset, and asset loads do not complete under
      // the test clock: warm the delegate and let the app's own load finish.
      await tester
          .runAsync(() => AppLocalizations.delegate.load(const Locale('de')));
      await tester.pumpWidget(_app(location, equalsMoney: equalsMoney));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      // The rail keeps a sheen alive, so advance a fixed amount instead of
      // waiting for a tree that never settles.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
      expect(find.text(location), findsOneWidget);
      expect(find.byTooltip('Konten'), findsOneWidget,
          reason: 'The rail is in German.');
      expect(_railSelected(tester, 'Konten'), isTrue);
      expect(_railSelected(tester, 'Startseite'), isFalse);
      expect(_railSelected(tester, 'Karten'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
