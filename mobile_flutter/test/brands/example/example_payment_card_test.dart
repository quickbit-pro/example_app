import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  const card = PaymentCard(
    id: 'card-1',
    label: 'Quantum Black',
    last4: '4242',
    network: 'Visa',
    currency: 'USD',
    status: CardStatus.active,
    balance: Money(currency: 'USD', minorUnits: 1200),
    spendThisMonth: Money(currency: 'USD', minorUnits: 300),
    limit: Money(currency: 'USD', minorUnits: 50000),
    virtual: true,
    cardImageUrl: 'https://cdn.example.com/card.png',
    cardThumbnailUrl: 'https://cdn.example.com/card-thumb.png',
    cardImageAlt: 'Quantum Black card',
  );

  testWidgets('uses the issued card artwork on the full card face',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ExamplePaymentCard(card: card),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, card.cardImageUrl);
    expect(image.semanticLabel, card.cardImageAlt);
  });

  testWidgets('uses the app thumbnail for compact card previews',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 66,
            child: ExamplePaymentCard(
              card: card,
              compact: true,
              height: 42,
            ),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as NetworkImage).url, card.cardThumbnailUrl);
  });

  testWidgets('keeps the painted EXAMPLE fallback without app artwork',
      (tester) async {
    const fallbackCard = PaymentCard(
      id: 'card-2',
      label: 'Card',
      last4: '3191',
      network: 'Mastercard',
      currency: 'USD',
      status: CardStatus.active,
      balance: Money(currency: 'USD', minorUnits: 0),
      spendThisMonth: Money(currency: 'USD', minorUnits: 0),
      limit: Money(currency: 'USD', minorUnits: 0),
      virtual: false,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: ExamplePaymentCard(card: fallbackCard),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byType(ExampleWordmark), findsOneWidget);
  });
}
