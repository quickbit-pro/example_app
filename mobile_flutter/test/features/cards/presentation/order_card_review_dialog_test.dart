import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/card_discount.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/cards/presentation/order_card_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/shared/widgets/neo_banking_components.dart';

import 'order_card_discount_test.dart' show tier;

class _Api extends MobileBankingApi {
  _Api() : super(Dio());

  @override
  Future<CardDiscount> validateCardDiscount(String code) async =>
      CardDiscount.fromJson(const {'isValid': false});
}

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'light',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: '',
  supportPhone: '',
  legalEntity: '',
);

/// Opens the order review at [size] and returns the review's scroll body.
Future<Finder> _openReview(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.binding.setSurfaceSize(null);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(const AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://localhost',
          branding: _branding)),
      mobileBankingApiProvider.overrideWithValue(_Api()),
      mobileTenantConfigProvider
          .overrideWith((_) async => MobileTenantConfig.fromJson(const {})),
      kycDetailedStatusProvider
          .overrideWith((_) async => KycDetailedStatus.fromJson(const {
                'interlace': {'approved': true, 'status': 'approved'},
              })),
      currentTierProvider.overrideWith((_) async => tier),
      tiersProvider.overrideWith((_) async => [tier]),
      cardTierProvider('1').overrideWith((_) async => tier),
      budgetsProvider.overrideWith((_) async => []),
    ],
    child: MaterialApp(
      theme: buildAppThemes(_branding).light,
      home: const OrderCardScreen(),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  final confirm = find.text('Confirm & order Virtual');
  await tester.ensureVisible(confirm);
  await tester.pump(const Duration(milliseconds: 500));
  await tester.tap(confirm);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  return find
      .descendant(
        of: find.byType(NeoFullScreenDialog),
        matching: find.byType(Scrollable),
      )
      .first;
}

/// [text] inside the review, not on the order screen behind it.
Finder _inReview(String text) => find.descendant(
    of: find.byType(NeoFullScreenDialog), matching: find.textContaining(text));

void main() {
  // A 13" laptop browser, a 15" one and a 1080p monitor.
  for (final size in const [
    Size(1440, 790),
    Size(1440, 900),
    Size(1920, 950)
  ]) {
    testWidgets(
        'every agreement is on screen without scrolling at '
        '${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      final body = await _openReview(tester, size);
      final visible = tester.getRect(body);

      for (final agreement in const [
        'I accept the E-Sign Agreement',
        'I accept the Privacy Policy and Terms of Service',
        'I certify the accuracy of my information',
        'card usage terms',
      ]) {
        final rect = tester.getRect(_inReview(agreement));
        expect(rect.bottom, lessThanOrEqualTo(visible.bottom),
            reason: agreement);
        expect(rect.top, greaterThanOrEqualTo(visible.top), reason: agreement);
      }
      // The agreements sit beside the card and its costs, not under them.
      expect(
        tester.getTopLeft(_inReview('Legal agreements')).dx,
        greaterThan(tester.getTopRight(_inReview('Costs')).dx),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a narrow window keeps the single column', (tester) async {
    final body = await _openReview(tester, const Size(760, 800));
    await tester.scrollUntilVisible(_inReview('Legal agreements'), 200,
        scrollable: body);

    // One column: the agreements follow the costs down the page.
    expect(
      tester.getTopLeft(_inReview('Legal agreements')).dy,
      greaterThan(tester.getBottomLeft(_inReview('Costs')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
