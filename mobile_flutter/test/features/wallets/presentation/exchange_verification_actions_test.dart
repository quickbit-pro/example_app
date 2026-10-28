import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_actions.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_panel.dart';

class TierApi extends MobilePlatformApi {
  TierApi(this.tier) : super(Dio());
  String tier;
  String status = 'approved';
  int starts = 0;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() async => {
        'eligible': true,
        'tier': tier,
        'status': status,
        'hasProviderAccount': false,
      };
  @override
  Future<Map<String, dynamic>> startExchangeVerification(String value) async {
    starts++;
    tier = value;
    status = 'pending';
    return {'tier': value, 'status': status};
  }
}

void main() {
  for (final width in [320.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('verification buttons stay separated at $width / $scale',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(24),
              child: ExchangeVerificationActions(
                showChooseLimits: true,
                showActivate: true,
                chooseLabel: 'Change limits',
                onChooseLimits: () {},
                onActivate: () {},
              ),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final primary = tester.getRect(find.byType(FilledButton));
        final secondary = tester.getRect(find.byType(OutlinedButton));
        expect(primary.overlaps(secondary), isFalse);
        expect(secondary.left - primary.right >= 12 ||
            secondary.top - primary.bottom >= 12, isTrue);
      });
    }
  }

  for (final source in ['sdd', 'cdd']) {
    testWidgets('changing $source starts selected tier and clears old activation',
        (tester) async {
      final api = TierApi(source);
      await tester.pumpWidget(ProviderScope(
        overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(child: ExchangeVerificationPanel()))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Activate Exchange'), findsOneWidget);
      await tester.tap(find.text('Change limits'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(source == 'sdd' ? 'Higher limits' : 'Basic'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(api.starts, 0);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(api.starts, 1);
      expect(api.tier, source == 'sdd' ? 'cdd' : 'sdd');
      expect(find.text('Activate Exchange'), findsNothing);
      expect(find.text('Your verification is under review.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
