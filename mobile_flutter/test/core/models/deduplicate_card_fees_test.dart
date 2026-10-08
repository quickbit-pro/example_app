import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/deduplicate_card_fees.dart';

LedgerTransaction fee(bool card, [Map<String, Object?> changes = const {}]) =>
    LedgerTransaction.fromJson({
      'id': card ? 'card-record' : 'database-record',
      'type': card ? 'card_fee' : 'fees',
      'source': card ? 'card_fee' : 'database',
      'cardId': card ? 569 : null,
      'amount': card ? 2 : -2,
      'currency': 'USD',
      'status': card ? 'success' : 'completed',
      'isPrimary': true,
      'externalTransactionId': 'same-provider-charge',
      ...changes,
    });

void main() {
  test('keeps card-linked charge once in either response order', () {
    for (final rows in [
      [fee(true), fee(false)],
      [fee(false), fee(true)]
    ]) {
      final result = deduplicateCardFees(rows);
      expect(result.map((r) => r.id), ['card-record']);
      expect(result.single.cardId, '569');
      expect(result.single.amount.decimalAmount, -2);
    }
  });
  test('does not hide distinct fees, mismatches, or uncertain records', () {
    for (final changes in <Map<String, Object?>>[
      {'externalTransactionId': 'another-charge'},
      {'externalTransactionId': null},
      {'currency': 'EUR'},
      {'amount': -3},
      {'status': 'pending'},
      {'status': 'failed'},
      {'source': 'another-provider'},
      {'type': 'refund'},
      {'cardId': 570},
    ]) {
      expect(
          deduplicateCardFees([fee(true), fee(false, changes)]), hasLength(2));
    }
    expect(deduplicateCardFees([fee(false)]), hasLength(1));
    expect(
        deduplicateCardFees([fee(true), fee(true), fee(false)]), hasLength(3));
    expect(
        deduplicateCardFees([fee(true), fee(false), fee(false)]), hasLength(3));
  });
}
