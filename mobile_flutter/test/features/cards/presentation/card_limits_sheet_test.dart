import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/cards/domain/card_limits.dart';
import 'package:mobile_flutter/features/cards/presentation/card_limits_sheet.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
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

const _info = CardLimitsInfo(
  currency: 'USD',
  canUpdate: true,
  capSource: 'card_type',
  daily: 250,
  monthly: 3000,
  capDaily: 500,
  capWeekly: 2000,
  capMonthly: 6000,
  tierName: 'Pro',
);

const _card = PaymentCard(
  id: 'card-1',
  label: 'EXAMPLE Card',
  last4: '4242',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 10000),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
  virtual: true,
);

void main() {
  testWidgets('limits sheet shows tier ceilings and flags values above them',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final theme = buildAppThemes(_branding).dark;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cardLimitsProvider('card-1').overrideWith((ref) async => _info),
        ],
        child: MaterialApp(
          theme: theme,
          darkTheme: theme,
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: CardLimitsSheet(card: _card)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Spending limits'), findsOneWidget);
    expect(find.textContaining('Pro tier caps each limit'), findsOneWidget);
    expect(find.text(r'Tier max $500'), findsOneWidget);
    expect(find.text(r'Tier max $2,000'), findsOneWidget);
    expect(find.text(r'Tier max $6,000'), findsOneWidget);
    expect(find.widgetWithText(TextField, '250'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));
    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    expect(sliders.map((slider) => slider.max), [500, 2000, 6000]);

    // The retained slider updates its amount field and stops at the tier cap.
    await tester.drag(find.byType(Slider).first, const Offset(500, 0));
    await tester.pump();
    expect(find.widgetWithText(TextField, '500'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider).first).value, 500);

    await tester.enterText(find.widgetWithText(TextField, '500'), '900');
    await tester.pump();
    expect(find.text(r'Above your tier ceiling of $500'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
