import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/shell/banking_shell.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/diagnostics/app_build_info.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/core/widgets/app_version_header.dart';
import 'package:mobile_flutter/customer_preview/preview_fixtures.dart';
import 'package:mobile_flutter/features/dashboard/data/service_onboarding_provider.dart';
import 'package:mobile_flutter/features/dashboard/domain/service_onboarding.dart';
import 'package:mobile_flutter/features/dashboard/presentation/example_dashboard.dart';
import 'package:mobile_flutter/flavors.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Geist')
          ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final width in [390.0, 900.0, 1200.0, 1470.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
          'Home status buttons clear actions and version at $width ${brightness.name}',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const branding = AppBranding(
            appName: 'Example',
            brandId: 'example',
            primarySeedHex: '621A96',
            accentSeedHex: 'C6F24E',
            loginBackgroundHex: '',
            themeMode: 'system',
            fontFamily: 'Geist',
            logoAsset: '',
            radiusScale: '1',
            supportEmail: '',
            supportPhone: '',
            legalEntity: '',
            design: AppDesign({
              'layout': 'example',
              'motion': {'enabled': false}
            }));
        final statuses = remainingServiceOnboarding(
            bankingEnabled: true,
            exchangeEnabled: true,
            preferences: {
              'enabled': true,
              'cryptoCard': true,
              'banking': true,
              'exchange': true
            },
            progress: {
              'interlace': 'approved',
              'equalsMoney': 'action_required',
              'boomFi': 'not_started'
            });
        final router = GoRouter(initialLocation: '/home', routes: [
          ShellRoute(
              builder: (_, __, child) => BankingShell(child: child),
              routes: [
                GoRoute(
                    path: '/home',
                    builder: (_, __) => ExampleDashboard(
                        snapshot: previewHome,
                        unreadNotifications: 2,
                        onRefresh: () async {},
                        animateChart: false))
              ]),
        ]);
        addTearDown(router.dispose);
        final themes = buildAppThemes(branding);
        await tester.pumpWidget(ProviderScope(
            overrides: [
              ...customerPreviewOverrides(branding),
              homeServiceOnboardingProvider
                  .overrideWith((ref) async => statuses),
              appBuildInfoProvider.overrideWith((ref) async =>
                  const AppBuildInfo(
                      version: '0.1.7',
                      buildNumber: '11',
                      revision: 'abc1234')),
              clientEnvironmentProvider.overrideWithValue('Chrome'),
            ],
            child: MaterialApp.router(
                theme: themes.light,
                darkTheme: themes.dark,
                themeMode: brightness == Brightness.light
                    ? ThemeMode.light
                    : ThemeMode.dark,
                debugShowCheckedModeBanner: false,
                routerConfig: router,
                builder: (context, child) => RepaintBoundary(
                    key: const ValueKey('onboarding-preview'),
                    child: AppVersionFrame(child: child!)))));
        await tester.pumpAndSettle();
        final version = tester.getRect(find.byKey(AppVersionFrame.headerKey));
        for (final service in OnboardingService.values) {
          final button = find.byKey(ValueKey('onboarding-${service.name}'));
          expect(button, findsOneWidget);
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.overlaps(version), isFalse);
          final send = find.text('Send money');
          if (send.evaluate().isNotEmpty) {
            expect(rect.overlaps(tester.getRect(send)), isFalse);
          }
        }
        expect(tester.takeException(), isNull);
        const capture = String.fromEnvironment('ONBOARDING_PREVIEW_PATH');
        if (capture.isNotEmpty &&
            width == 1470 &&
            brightness == Brightness.light) {
          final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('onboarding-preview')));
          await tester.runAsync(() async {
            final image = await (boundary.debugLayer! as OffsetLayer)
                .toImage(Rect.fromLTWH(0, 0, width, 90), pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(capture).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
