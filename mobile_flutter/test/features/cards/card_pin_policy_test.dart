import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/cards/domain/card_pin_policy.dart';

void main() {
  test('accepts unpredictable six-digit PINs', () {
    for (final pin in ['482915', '907341', '112358', '135790', '112233']) {
      expect(cardPinProblem(pin), isNull, reason: pin);
    }
  });

  test('rejects anything but six digits', () {
    for (final pin in ['', '1234', '12345', '1234567', '12a456']) {
      expect(cardPinProblem(pin), 'Exactly 6 digits', reason: pin);
    }
  });

  test('rejects a single repeated digit', () {
    for (final pin in ['000000', '111111', '999999']) {
      expect(cardPinMeetsPolicy(pin), isFalse, reason: pin);
      expect(cardPinProblem(pin), contains('repeated digit'));
    }
  });

  test('rejects consecutive runs including wrap-around', () {
    for (final pin in [
      '123456',
      '654321',
      '456789',
      '890123',
      '210987',
      '098765'
    ]) {
      expect(cardPinMeetsPolicy(pin), isFalse, reason: pin);
      expect(cardPinProblem(pin), contains('run of digits'));
    }
  });

  test('rejects repeating patterns', () {
    for (final pin in ['121212', '123123', '909090', '258258']) {
      expect(cardPinMeetsPolicy(pin), isFalse, reason: pin);
      expect(cardPinProblem(pin), contains('repeating pattern'));
    }
  });
}
