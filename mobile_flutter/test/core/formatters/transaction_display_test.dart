import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/formatters/transaction_display.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  test('humanizes provider transaction names and statuses', () {
    expect(transactionDisplayTitle('UK.OBIE.BalanceTransfer'), 'Bank transfer');
    expect(transactionDisplayStatus('closed'), 'Completed');
    expect(transactionDisplayStatus('in_progress'), 'Pending');
  });

  test('applies an outgoing direction to an unsigned amount', () {
    final transaction = LedgerTransaction.fromJson(const {
      'title': 'Payment',
      'amount': {'currency': 'GBP', 'amount': 12.5},
      'direction': 'DEBIT',
    });

    expect(transaction.amount.minorUnits, -1250);
  });

  test('keeps local card payment amount with USD settlement', () {
    final transaction = LedgerTransaction.fromJson(const {
      'id': 'card-payment-1',
      'merchantName': 'Coffee Shop',
      'type': 'card_payment',
      'status': 'closed',
      'currency': 'USD',
      'amount': '4.92',
      'transactionCurrency': 'EUR',
      'transactionAmount': '4.20',
    });

    expect(transaction.title, 'Coffee Shop');
    expect(transaction.displayType, 'Card Payment');
    // Card payments are money out even when the provider omits a direction.
    expect(transaction.displayAmount.formatted, '-€4.20');
    expect(transaction.secondarySettlementAmount?.formatted, '-\$4.92');
  });

  test('retains provider metadata for transaction details', () {
    final transaction = LedgerTransaction.fromJson(const {
      'id': 'equals-payment-1',
      'amount': {'currency': 'GBP', 'amount': 15},
      'metadata': {
        'provider': 'EqualsMoney',
        'budgetId': 'F58977',
        'schemeName': 'Faster Payments',
      },
    });

    expect(transaction.metadata['provider'], 'EqualsMoney');
    expect(transaction.metadata['budgetId'], 'F58977');
    expect(transaction.metadata['schemeName'], 'Faster Payments');
  });

  test('decodes string metadata returned by providers', () {
    final transaction = LedgerTransaction.fromJson(const {
      'id': 'equals-payment-2',
      'amount': {'currency': 'GBP', 'amount': 5},
      'metadata': '{"budgetId":"F123","paymentMethod":"FPS"}',
    });

    expect(transaction.metadata['budgetId'], 'F123');
    expect(transaction.metadata['paymentMethod'], 'FPS');
  });

  test('keeps top-level Mastercard enrichment visible in transaction details',
      () {
    final transaction = LedgerTransaction.fromJson(const {
      'id': 'card-payment-enriched',
      'amount': {'currency': 'USD', 'amount': 12},
      'merchantName': 'Example Shop',
      'merchantEnrichment': {
        'logoUrl': 'https://cdn.example.com/merchant.png',
        'categoryName': 'Retail',
      },
    });

    expect(
      transaction.merchantLogoUrl,
      'https://cdn.example.com/merchant.png',
    );
    expect(transaction.merchantCategory, 'Retail');
    expect(transaction.metadata['merchantEnrichment'], isA<Map>());
  });
}
