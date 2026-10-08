import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/cards/presentation/widgets/neo_bank_card.dart';

void main() {
  testWidgets('shows the Hoppa card network on the card face', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: NeoBankCard(
                label: 'Card',
                last4: '3191',
                network: 'mastercard',
                virtual: true,
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('MASTERCARD'), findsOneWidget);
  });
}
