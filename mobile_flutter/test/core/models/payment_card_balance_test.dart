import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  test('detail zero survives artwork and metadata fallback from a stale list',
      () {
    final detail = PaymentCard.fromJson({
      'id': 'card',
      'balance': {'available': '0.00', 'currency': 'USD'},
    });
    final listed = PaymentCard.fromJson({
      'id': 'card',
      'label': 'My card',
      'balance': 167.98,
    });
    final merged = detail.withFallback(listed);
    expect(merged.balance.minorUnits, 0);
    expect(merged.hasReportedBalance, isTrue);
    expect(merged.label, 'My card');
  });

  test('missing detail balance remains distinguishable from a reported zero',
      () {
    final detail = PaymentCard.fromJson({'id': 'card'});
    final listed = PaymentCard.fromJson({'id': 'card', 'balance': 167.98});
    expect(detail.hasReportedBalance, isFalse);
    final merged = detail.withFallback(listed);
    expect(merged.balance.minorUnits, 16798);
    expect(merged.hasReportedBalance, isFalse);
  });

  for (final available in [0, 72.35]) {
    test('available card balance wins over ledger and total: $available', () {
      final card = PaymentCard.fromJson({
        'id': 1,
        'currency': 'USD',
        'balance': 100,
        'totalBalance': 120,
        'availableBalance': available,
      });
      expect(card.balance.minorUnits, (available * 100).round());
    });
  }
  test('Pascal case Hoppa availability is used', () {
    final card = PaymentCard.fromJson({
      'Data': {
        'Id': 1,
        'Currency': 'EUR',
        'Balance': 100,
        'AvailableBalance': '42.17',
      }
    });
    expect(card.balance.minorUnits, 4217);
    expect(card.balance.currency, 'EUR');
  });
  test('nested available balance wins over nested ledger amount', () {
    final card = PaymentCard.fromJson({
      'balance': {
        'currency': 'EUR',
        'amount': 100,
        'availableBalance': 70,
      }
    });
    expect(card.balance.minorUnits, 7000);
    expect(card.balance.currency, 'EUR');
  });
  test('legacy card response with only balance remains supported', () {
    final card = PaymentCard.fromJson({
      'balance': {
        'currency': 'USD',
        'minorUnits': 1500,
      }
    });
    expect(card.balance.minorUnits, 1500);
  });
}
