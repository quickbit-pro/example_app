import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  tearDown(() => Money.maskAmounts = false);

  test('crypto trims trailing zeros with a minimum of two decimal places', () {
    for (final currency in ['USDC', 'USDT', 'BTC', 'ETH']) {
      for (final (amount, number) in <(double, String)>[
        (0, '0.00'),
        (1, '1.00'),
        (-1, '-1.00'),
        (1.2, '1.20'),
        (1.23, '1.23'),
        (1.234500, '1.2345'),
        (0.000001, '0.000001'),
        (-0.000001, '-0.000001'),
        (12345.67, '12,345.67'),
      ]) {
        expect(Money.formatAmount(currency, amount), '$number $currency');
      }
    }
  });

  test('formatting preserves meaningful native crypto precision and value', () {
    for (final (currency, amount, expected) in [
      ('USDC', -1.234567, '-1.234567 USDC'),
      ('USDT', 0.000001, '0.000001 USDT'),
      ('BTC', 0.00000001, '0.00000001 BTC'),
      ('ETH', 1.23456789, '1.23456789 ETH'),
    ]) {
      final money = Money.fromJson(
        {'currency': currency, 'amount': amount},
        preservePrecision: true,
      );
      expect(money.formatted, expected);
      expect(money.decimalAmount, amount);
    }
  });

  test('fiat retains fixed cents and privacy still hides crypto amounts', () {
    expect(Money.formatAmount('EUR', 1), '€1.00');
    expect(Money.formatAmount('USD', 1.2), '\$1.20');
    expect(Money.formatAmount('RON', 1234.5), '1,234.50 RON');
    Money.maskAmounts = true;
    expect(Money.formatAmount('USDC', -1.2345), '••••');
  });
}
