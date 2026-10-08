import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/shared.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';

void main() {
  testWidgets('enabled fiat currencies have flags including HUF and RON',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Row(children: [
      ExampleCurrencyAvatar(code: 'HUF'),
      ExampleCurrencyAvatar(code: 'RON'),
      ExampleCurrencyAvatar(code: 'CNY'),
      ExampleCurrencyAvatar(code: 'PLN'),
    ])));
    for (final flag in ['🇭🇺', '🇷🇴', '🇨🇳', '🇵🇱']) {
      expect(find.text(flag), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses official stablecoin artwork', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            CurrencyLogo(symbol: 'USDC'),
            CurrencyLogo(symbol: 'USDT'),
          ],
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    expect(
      (images[0].image as AssetImage).assetName,
      'assets/crypto/usdc.png',
    );
    expect(
      (images[1].image as AssetImage).assetName,
      'assets/crypto/usdt.png',
    );
  });

  testWidgets('keeps a readable fallback for other currencies', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CurrencyLogo(symbol: 'EUR')),
    );

    expect(find.text('E'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });
}
