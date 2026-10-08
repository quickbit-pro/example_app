import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/formatters/amount_input.dart';

void main() {
  test('Max truncates instead of rounding up', () {
    expect(maxAmountInput(32.0395, decimals: 2), '32.03');
    expect(maxAmountInput(4.9749999, decimals: 2), '4.97');
    expect(maxAmountInput(4.999, decimals: 2), '4.99');
    expect(maxAmountInput(1.10, decimals: 2), '1.1');
    expect(maxAmountInput(0, decimals: 2), '0');
  });

  test('decimals follow the currency', () {
    expect(amountDecimalsFor('USD'), 2);
    expect(amountDecimalsFor('usdc'), 2);
  });
}
