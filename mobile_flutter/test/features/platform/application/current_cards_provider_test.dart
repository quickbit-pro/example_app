import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';

PaymentCard card(double balance) => PaymentCard.fromJson({
      'id': '560',
      'last4': '6724',
      'status': 'active',
      'currency': 'USD',
      'availableBalance': balance,
    });

void main() {
  test('overview uses current detail balance, including an explicit zero',
      () async {
    var available = 37.69;
    final container = ProviderContainer(overrides: [
      cardsProvider.overrideWith((ref) async => [card(144.27)]),
      cardDetailProvider('560').overrideWith((ref) async => card(available)),
    ]);
    addTearDown(container.dispose);
    expect(
        (await container.read(currentCardsProvider.future))
            .single
            .balance
            .minorUnits,
        3769);
    available = 0;
    container.invalidate(cardDetailProvider('560'));
    expect(
        (await container.read(currentCardsProvider.future))
            .single
            .balance
            .minorUnits,
        0);
  });

  test('a detail failure cannot display the stale list balance as current',
      () async {
    final container = ProviderContainer(overrides: [
      cardsProvider.overrideWith((ref) async => [card(144.27)]),
      cardDetailProvider('560')
          .overrideWith((ref) async => throw StateError('offline')),
    ]);
    addTearDown(container.dispose);
    await expectLater(
        container.read(currentCardsProvider.future), throwsStateError);
  });
}
