import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/group_card_fees.dart';

LedgerTransaction purchase(
        {String id = 'purchase',
        String card = '17',
        String client = 'client-1',
        String status = 'closed'}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'cardId': card,
      'type': 'card_payment',
      'status': status,
      'amount': 13.42,
      'currency': 'USD',
      'externalTransactionId': 'provider-$id',
      'transactionAmount': 10.50,
      'transactionCurrency': 'EUR',
      'metadata': {'clientTransactionId': client, 'fee': .32},
    });
LedgerTransaction fee(
        {String id = 'fee',
        String card = '17',
        String client = 'client-1_Fee_Consumption',
        String? related,
        String status = 'closed',
        String currency = 'USD'}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'cardId': card,
      'type': 'card_payment_fee',
      'status': status,
      'amount': .5,
      'currency': currency,
      if (related != null) 'relatedCardTransactionId': related,
      'metadata': {'clientTransactionId': client, 'fee': .5},
    });

void main() {
  test('numeric card consumption and fee types retain debit direction', () {
    final parent = LedgerTransaction.fromJson({
      'id': 'numeric',
      'type': 1,
      'amount': 10,
      'currency': 'USD',
      'status': 'closed'
    });
    final charge = LedgerTransaction.fromJson({
      'id': 'numeric-fee',
      'type': 9,
      'amount': .5,
      'currency': 'USD',
      'status': 'closed',
      'relatedCardTransactionId': 'numeric'
    });
    final grouped = groupCardFees([parent, charge]);
    expect(grouped, hasLength(1));
    expect(cardListAmount(grouped.single).decimalAmount, -10.5);
  });

  test(
      'production client suffix joins different provider IDs without double charging metadata fees',
      () {
    final rows = [fee(related: 'different-provider-id'), purchase()];
    final grouped = groupCardFees(rows);
    expect(grouped, hasLength(1));
    expect(grouped.single.id, 'purchase');
    expect(grouped.single.cardFees, hasLength(1));
    expect(
        cardListAmount(grouped.single).decimalAmount, closeTo(-13.92, .000001));
    expect(cardListAmount(grouped.single).currency, 'USD');
    expect(grouped.single.transactionAmount!.currency, 'EUR');
    expect(rows, hasLength(2));
    expect(rows.last.cardFees, isEmpty);
    expect(rows.last.amount.decimalAmount, -13.42);
    expect(groupCardFees(grouped).single.cardFees, hasLength(1));
  });
  test('exact related ID joins decline fee with failed purchase', () {
    final grouped = groupCardFees([
      purchase(status: 'declined'),
      fee(client: '', related: 'provider-purchase')
    ]);
    expect(grouped, hasLength(1));
    expect(cardListAmount(grouped.single).decimalAmount, -.5);
  });
  test('failed fee is shown but not included in total charged', () {
    final grouped = groupCardFees([purchase(), fee(status: 'failed')]);
    expect(grouped.single.cardFees, hasLength(1));
    expect(cardFeeWasCharged(grouped.single.cardFees.single), isFalse);
    expect(cardFeeCaption(grouped.single), contains('failed'));
    expect(cardListAmount(grouped.single).decimalAmount, -10.5);
  });
  test(
      'no merchant/date guessing; missing parent, mismatched card, ambiguous and conflicting links stay visible',
      () {
    expect(groupCardFees([fee(client: 'unrelated'), purchase()]), hasLength(2));
    expect(groupCardFees([fee(card: 'other'), purchase()]), hasLength(2));
    expect(groupCardFees([fee(), purchase(), purchase(id: 'second')]),
        hasLength(3));
    expect(
        groupCardFees([
          fee(related: 'provider-second'),
          purchase(),
          purchase(id: 'second', client: 'client-2')
        ]),
        hasLength(3));
    expect(groupCardFees([fee()]), hasLength(1));
  });
  group('Hoppa production shapes', () {
    LedgerTransaction declined(
            {required String id,
            required String client,
            required String at,
            String card = '541'}) =>
        LedgerTransaction.fromJson({
          'id': id,
          'externalTransactionId': 'ext-$id',
          'type': 'card_payment',
          'description': 'Type1: MESARIJA SELAK',
          'amount': 66.87,
          'currency': 'USD',
          'status': 'fail',
          'transactionDate': at,
          'cardId': card,
          'feeAmount': 1.51,
          'metadata': {
            'clientTransactionId': client,
            'type': 1,
            'cardTransactionId': 'ext-$id'
          },
        });

    test('two declined attempts each keep their own two fees', () {
      final rows = [
        LedgerTransaction.fromJson({
          'id': '76750',
          'type': 'card_decline_fee',
          'description': 'Card decline fee for transaction',
          'amount': -0.5,
          'currency': 'USD',
          'status': 'completed',
          'transactionDate': '2026-09-01T09:44:46',
          'cardId': '541',
          'relatedCardTransactionId': 'ext-76748',
          'feeAmount': 0.5,
        }),
        LedgerTransaction.fromJson({
          'id': '76749',
          'type': 'card_payment_fee',
          'amount': 0.5,
          'currency': 'USD',
          'status': 'closed',
          'transactionDate': '2026-09-01T09:44:43',
          'cardId': '541',
          'relatedCardTransactionId': 'unknown-1',
          'metadata': {
            'clientTransactionId': '2094723116296110081_Fee_Consumption'
          },
        }),
        declined(
            id: '76748',
            client: '2094723116296110081',
            at: '2026-09-01T09:44:43'),
        LedgerTransaction.fromJson({
          'id': '76742',
          'type': 'card_decline_fee',
          'description': 'Card decline fee for transaction',
          'amount': -0.5,
          'currency': 'USD',
          'status': 'completed',
          'transactionDate': '2026-09-01T09:44:29',
          'cardId': '541',
          'relatedCardTransactionId': 'ext-76741',
          'feeAmount': 0.5,
        }),
        LedgerTransaction.fromJson({
          'id': '76743',
          'type': 'card_payment_fee',
          'amount': 0.5,
          'currency': 'USD',
          'status': 'closed',
          'transactionDate': '2026-09-01T09:44:27',
          'cardId': '541',
          'relatedCardTransactionId': 'unknown-2',
          'metadata': {
            'clientTransactionId': '2094723045705687041_Fee_Consumption'
          },
        }),
        declined(
            id: '76741',
            client: '2094723045705687041',
            at: '2026-09-01T09:44:26'),
      ];
      final grouped = groupCardFees(rows);
      expect(grouped.map((r) => r.id), ['76748', '76741']);
      for (final row in grouped) {
        expect(row.cardFees, hasLength(2));
        expect(cardListAmount(row).decimalAmount, closeTo(-1, .000001));
        expect(cardFeeCaption(row),
            'Decline fee USD 0.50 · Consumption fee USD 0.50');
      }
    });

    test(
        'an unlinked zero-amount decline fee joins the nearest declined '
        'purchase on its card and reports the fee it carried', () {
      LedgerTransaction declineFee(String id, String at, String related) =>
          LedgerTransaction.fromJson({
            'id': id,
            'externalTransactionId': 'ext-$id',
            'relatedCardTransactionId': related,
            'type': 'card_payment_fee',
            'description': 'Type10: ',
            'amount': 0,
            'currency': 'USD',
            'status': 'closed',
            'transactionDate': at,
            'cardId': '396',
            'feeAmount': 0.5,
            'metadata': {
              'clientTransactionId': 'd2edd680-$id',
              'type': 10,
              'cardTransactionId': 'ext-$id'
            },
          });
      final rows = [
        declineFee('53421', '2026-06-24T17:09:03.9', '633ac32d'),
        declined(
            id: '53420',
            client: '73a6dc78',
            at: '2026-06-24T17:09:03.5',
            card: '396'),
        declineFee('53419', '2026-06-24T17:09:01.9', 'f233981d'),
        declined(
            id: '53418',
            client: 'bd01f292',
            at: '2026-06-24T17:09:00.9',
            card: '396'),
      ];
      final grouped = groupCardFees(rows);
      expect(grouped.map((r) => r.id), ['53420', '53418']);
      for (final row in grouped) {
        expect(row.cardFees, hasLength(1));
        expect(feeChargedAmount(row.cardFees.single).decimalAmount, -.5);
        expect(cardFeeCaption(row), 'Decline fee USD 0.50');
        expect(cardListAmount(row).decimalAmount, closeTo(-.5, .000001));
      }
    });

    test('the time fallback never crosses cards or ties', () {
      final fee = LedgerTransaction.fromJson({
        'id': 'f',
        'type': 'card_payment_fee',
        'amount': 0,
        'currency': 'USD',
        'status': 'closed',
        'transactionDate': '2026-06-24T17:09:02',
        'cardId': '396',
        'feeAmount': 0.5,
        'metadata': {'type': 10},
      });
      // Other card.
      expect(
          groupCardFees([
            fee,
            declined(
                id: 'a', client: 'a', at: '2026-06-24T17:09:02', card: '397')
          ]),
          hasLength(2));
      // Two attempts equally near.
      expect(
          groupCardFees([
            fee,
            declined(
                id: 'a', client: 'a', at: '2026-06-24T17:09:01', card: '396'),
            declined(
                id: 'b', client: 'b', at: '2026-06-24T17:09:03', card: '396'),
          ]),
          hasLength(3));
      // Too far away.
      expect(
          groupCardFees([
            fee,
            declined(
                id: 'a', client: 'a', at: '2026-06-24T17:08:00', card: '396')
          ]),
          hasLength(2));
    });

    test('a fee paid for an internal payment request is the same movement', () {
      final rows = [
        LedgerTransaction.fromJson({
          'id': '6747',
          'type': 'internal_payment',
          'description': 'internal_payment: Payment internal payment',
          'amount': -7.85,
          'currency': 'USD',
          'status': 'completed',
          'transactionDate': '2025-09-05T13:32:49',
          'metadata': {'clientTransactionId': '35'},
        }),
        LedgerTransaction.fromJson({
          'id': '6746',
          'type': 'fees',
          'description': 'fees: Direct payment for request 35',
          'amount': -7.85,
          'currency': 'USD',
          'status': 'completed',
          'transactionDate': '2025-09-05T13:32:49',
          'metadata': {'clientTransactionId': '6746'},
        }),
      ];
      final grouped = groupCardFees(rows);
      expect(grouped.map((r) => r.id), ['6747']);
      expect(grouped.single.cardFees, isEmpty);
      expect(cardListAmount(grouped.single).decimalAmount, -7.85);
    });
  });

  group('Equals production shapes', () {
    test('a service fee surfaced twice charges the credit it names once', () {
      final rows = [
        LedgerTransaction.fromJson({
          'id': '79711',
          'externalTransactionId': '8977968',
          'transactionGroupId': 'equalsmoney:order:E22369QSSHM8-Fee',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'fees',
          'description': 'fee',
          'amount': 0.03,
          'currency': 'EUR',
          'status': 'completed',
          'transactionDate': '2026-09-09T15:02:07',
          'tradeId': 'E22369QSSHM8-Fee',
          'metadata': {'orderId': '8731793', 'boxTransactionId': '145817850'},
        }),
        LedgerTransaction.fromJson({
          'id': '79710',
          'externalTransactionId': 'E22369QSSHM8-Fee',
          'isPrimary': true,
          'type': 'fee',
          'description': 'Fee: Service fee',
          'amount': 0.03,
          'currency': 'EUR',
          'status': 'completed',
          'transactionDate': '2026-09-09T15:02:05',
          'tradeId': 'E22369QSSHM8-Fee',
          'metadata': {
            'orderId': 'E22369QSSHM8-Fee',
            'source': 'orders',
            'provider': 'equalsmoney',
            'relatedCreditId': 145817847,
            'boxTransactionId': 145817850,
            'feeDebited': true
          },
        }),
        LedgerTransaction.fromJson({
          'id': '79701',
          'externalTransactionId': '145817847',
          'transactionGroupId': 'equalsmoney:activity-group:448a5eb9',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'deposit',
          'description': 'UK.OBIE.SEPACreditTransfer',
          'amount': 20,
          'currency': 'EUR',
          'status': 'completed',
          'transactionDate': '2026-09-09T15:02:00',
          'metadata': {
            'source': 'external_credit',
            'boxTransactionId': '145817847'
          },
        }),
      ];
      final grouped = groupCardFees(rows);
      expect(grouped.map((r) => r.id), ['79701']);
      final deposit = grouped.single;
      expect(deposit.cardFees, hasLength(1));
      expect(deposit.cardFees.single.id, '79710');
      expect(cardFeeLabel(deposit.cardFees.single), 'Service fee');
      expect(cardFeeCaption(deposit), 'Service fee EUR 0.03');
      expect(cardListAmount(deposit).decimalAmount, closeTo(19.97, .000001));
      // Duplicate views fold before any fee is attached.
      expect(dedupeLedgerDuplicates(rows).map((r) => r.id), ['79710', '79701']);
    });

    test('an FX trade is one row carrying its fee; its legs fold into it', () {
      final rows = [
        LedgerTransaction.fromJson({
          'id': '80005',
          'externalTransactionId': 'EOP354YEVZD1',
          'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'fx_trade',
          'description': 'FX Trade: 15 EUR → 12.72 GBP',
          'amount': 12.72,
          'currency': 'GBP',
          'status': 'completed',
          'transactionDate': '2026-09-10T07:22:41',
          'tradeId': 'EOP354YEVZD1',
          'metadata': {'orderId': 'EOP354YEVZD1'},
        }),
        LedgerTransaction.fromJson({
          'id': '80007',
          'externalTransactionId': '145910597',
          'transactionGroupId': 'equalsmoney:ledger:145910597',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'deposit',
          'description': 'Budget credit from Igor Lavrih',
          'amount': 12.72,
          'currency': 'GBP',
          'status': 'completed',
          'transactionDate': '2026-09-10T07:22:39',
          'metadata': {'source': 'exchange', 'boxTransactionId': 145910597},
        }),
        LedgerTransaction.fromJson({
          'id': '80006',
          'externalTransactionId': '145910596',
          'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1',
          'relationType': 'funding_debit',
          'isPrimary': false,
          'type': 'withdrawal',
          'description': 'Budget debit: exchange',
          'amount': 15,
          'currency': 'EUR',
          'status': 'completed',
          'transactionDate': '2026-09-10T07:22:39',
          'tradeId': 'EOP354YEVZD1',
          'metadata': {
            'orderId': 'EOP354YEVZD1',
            'source': 'exchange',
            'boxTransactionId': 145910596
          },
        }),
        LedgerTransaction.fromJson({
          'id': '80008',
          'externalTransactionId': '8982500',
          'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'exchange',
          'description': 'exchange',
          'amount': 12.72,
          'currency': 'GBP',
          'status': 'completed',
          'transactionDate': '2026-09-10T07:22:37',
          'tradeId': 'EOP354YEVZD1',
          'metadata': {'orderId': '8736845', 'boxTransactionId': '145910597'},
        }),
        LedgerTransaction.fromJson({
          'id': '80009',
          'externalTransactionId': '8982501',
          'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1-Fee',
          'relationType': 'primary',
          'isPrimary': true,
          'type': 'fees',
          'description': 'fee',
          'amount': 0.01,
          'currency': 'EUR',
          'status': 'completed',
          'transactionDate': '2026-09-10T07:22:36',
          'tradeId': 'EOP354YEVZD1-Fee',
          'metadata': {'orderId': '8736846', 'boxTransactionId': '145910599'},
        }),
      ];
      final grouped = groupCardFees(rows);
      expect(grouped.map((r) => r.id), ['80005', '80006']);
      final trade = grouped.first;
      expect(trade.cardFees.map((f) => f.id), ['80009']);
      expect(cardFeeCaption(trade), 'Fee EUR 0.01');
      // A fee in another currency is shown, never added to the trade.
      expect(cardListAmount(trade).decimalAmount, 12.72);
      expect(cardListAmount(trade).currency, 'GBP');
    });
  });

  test('different currency fee is never added to purchase currency', () {
    final grouped = groupCardFees([purchase(), fee(currency: 'GBP')]);
    expect(grouped.single.cardFees, hasLength(1));
    expect(cardListAmount(grouped.single).currency, 'EUR');
    expect(cardListAmount(grouped.single).decimalAmount, -10.5);
  });
}
