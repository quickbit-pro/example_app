import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/cards/domain/card_transaction_activity.dart';

void main() {
  test('uses the original purchase currency and keeps USD settlement below it',
      () {
    final activity = CardTransactionActivity.fromResource(
      PlatformResource.fromJson({
        'id': 'transaction-1',
        'currency': 'USD',
        'amount': '4.92',
        'transactionCurrency': 'EUR',
        'transactionAmount': '4.20',
        'type': 'card_payment',
        'status': 'closed',
        'merchantName': 'Coffee Shop',
        'merchantCity': 'Eindhoven',
        'merchantCountry': 'NL',
      }),
    );

    expect(activity.title, 'Coffee Shop');
    expect(activity.subtitle, 'Card Payment • Eindhoven, NL');
    expect(activity.displayAmount.formatted, '€4.20');
    expect(activity.secondarySettlementAmount?.formatted, '\$4.92');
    expect(activity.status, 'Closed');
  });

  test('uses the response currency instead of the Money EUR fallback', () {
    final activity = CardTransactionActivity.fromResource(
      PlatformResource.fromJson({
        'id': 'transaction-2',
        'currency': 'USD',
        'amount': 4.92,
        'type': 'card_payment',
        'status': 'closed',
      }),
    );

    expect(activity.displayAmount.formatted, '\$4.92');
    expect(activity.secondarySettlementAmount, isNull);
    expect(activity.title, 'Card Payment');
  });

  test('reads transaction values from nested metadata', () {
    final activity = CardTransactionActivity.fromResource(
      PlatformResource.fromJson({
        'id': 'transaction-3',
        'currency': 'USD',
        'amount': '10',
        'type': 'card_payment',
        'metadata': {
          'transactionCurrency': 'GBP',
          'transactionAmount': '7.50',
          'merchantName': 'Local Merchant',
        },
      }),
    );

    expect(activity.displayAmount.formatted, '£7.50');
    expect(activity.secondarySettlementAmount?.formatted, '\$10.00');
    expect(activity.title, 'Local Merchant');
  });

  test('accepts optional Hoppa Mastercard enrichment fields', () {
    final activity = CardTransactionActivity.fromResource(
      PlatformResource.fromJson({
        'id': 'transaction-4',
        'currency': 'USD',
        'amount': '9.99',
        'type': 'card_payment',
        'merchantName': 'Spotify',
        'merchantEnrichment': {
          'logoUrl': 'https://cdn.example.com/spotify.png',
          'categoryName': 'Digital subscriptions',
        },
      }),
    );

    expect(
      activity.merchantLogoUrl,
      'https://cdn.example.com/spotify.png',
    );
    expect(activity.merchantCategory, 'Digital subscriptions');
  });
}
