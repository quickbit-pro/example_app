import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/cache/display_snapshot_codecs.dart';

void main() {
  test(
      'card details retain the issued code across API parsing and cached display',
      () {
    for (final key in ['discountCode', 'DiscountCode', 'discount_code']) {
      final card = PaymentCard.fromJson({'id': 1, key: 'SAVE25'});
      expect(card.discountCode, 'SAVE25');
      expect(decodePaymentCard(encodePaymentCard(card)).discountCode, 'SAVE25');
    }
  });
  test('old cached cards and undiscounted cards have no applied code', () {
    final card = PaymentCard.fromJson({'id': 1});
    expect(card.discountCode, isEmpty);
    final cached = encodePaymentCard(card)..remove('discountCode');
    expect(decodePaymentCard(cached).discountCode, isEmpty);
  });
}
