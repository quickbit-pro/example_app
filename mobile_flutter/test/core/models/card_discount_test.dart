import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/card_discount.dart';

void main() {
  test('percentage discounts affect each matching fee', () {
    final discount = CardDiscount.fromJson({
      'isValid': true,
      'buyDiscountPercent': 25,
      'monthlyDiscountPercent': 50,
      'yearlyDiscountPercent': 100
    });
    expect(discount.price(20, 'buy'), 15);
    expect(discount.price(8, 'monthly'), 4);
    expect(discount.price(60, 'yearly'), 0);
    expect(discount.description('buy'), '25% off');
  });
  test('fixed prices replace fees, including zero; null preserves base price',
      () {
    final discount = CardDiscount.fromJson({
      'isValid': true,
      'discountType': 'fixed',
      'buyDiscountFixed': '3',
      'monthlyDiscountFixed': 0,
      'yearlyDiscountFixed': null
    });
    expect(discount.price(20, 'buy'), 3);
    expect(discount.price(8, 'monthly'), 0);
    expect(discount.price(60, 'yearly'), 60);
    expect(discount.description('monthly'), 'Fixed price');
    expect(discount.description('yearly'), isNull);
  });
  test('invalid codes never alter a fee', () {
    final discount =
        CardDiscount.fromJson({'isValid': false, 'buyDiscountPercent': 100});
    expect(discount.price(20, 'buy'), 20);
    expect(discount.description('buy'), isNull);
  });
}
