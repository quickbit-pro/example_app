import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/diagnostics/app_build_info.dart';
import 'package:mobile_flutter/core/web/update_available_banner.dart';
import 'package:mobile_flutter/core/widgets/app_version_header.dart';

void main() {
  for (final width in [320.0, 900.0, 1470.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('update and version both visible at $width scale $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var reloads = 0;
        await tester.pumpWidget(ProviderScope(
            overrides: [
              appBuildInfoProvider.overrideWith((ref) async =>
                  const AppBuildInfo(
                      version: '0.1.7',
                      buildNumber: '11',
                      revision: 'abcdef0')),
              clientEnvironmentProvider.overrideWithValue('Chrome'),
            ],
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(textScaler: TextScaler.linear(scale)),
                      child: AppUpdateFrame(
                          readyOverride: true,
                          onReload: () => reloads++,
                          child: child!),
                    ),
                home: Scaffold(
                    appBar: AppBar(title: const Text('Home')),
                    body: const Text('Content')))));
        await tester.pumpAndSettle();
        final update = find.widgetWithText(TextButton, 'Update now');
        final badge = find.byKey(AppVersionFrame.headerKey);
        expect(update, findsOneWidget);
        expect(badge, findsOneWidget);
        expect(tester.getRect(update).overlaps(tester.getRect(badge)), isFalse);
        expect(tester.getRect(update).bottom,
            lessThanOrEqualTo(tester.getRect(badge).top));
        await tester.tap(update);
        expect(reloads, 1);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('dismiss-app-update')));
        await tester.pumpAndSettle();
        expect(find.text('Update now'), findsNothing);
        expect(badge, findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
