import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

void main() {
  test(
      'booking timestamp provenance distinguishes missing and malformed API dates',
      () {
    for (final value in [null, '', 'not-a-date']) {
      final transaction = LedgerTransaction.fromJson({
        'id': 'undated',
        'type': 'transfer',
        'bookedAt': value,
      });
      expect(transaction.hasBookedAt, isFalse);
    }
    final transaction = LedgerTransaction.fromJson({
      'id': 'dated',
      'type': 'transfer',
      'metadata': {'bookedAt': '2026-09-06T11:25:00Z'},
    });
    expect(transaction.hasBookedAt, isTrue);
    expect(transaction.bookedAt.toUtc(), DateTime.utc(2026, 9, 6, 11, 25));
  });

  LedgerTransaction parse(String type, [num amount = 12.5]) =>
      LedgerTransaction.fromJson({
        'id': 't-$type',
        'type': type,
        'amount': amount,
        'currency': 'USD',
        'status': 'completed',
        'description': 'Test',
        'createdAt': '2026-09-04T08:00:00Z',
      });

  test('transfers to the master account are outflows', () {
    expect(parse('transfer_to_master').amount.minorUnits, -1250);
    expect(parse('user_to_master_transfer').amount.minorUnits, -1250);
    expect(parse('p2p_send').amount.minorUnits, -1250);
  });

  test('transfers from the master account stay inflows', () {
    expect(parse('transfer_from_master').amount.minorUnits, 1250);
    expect(parse('master_to_user_transfer').amount.minorUnits, 1250);
  });

  test('fees are outflows and zero stays zero', () {
    expect(parse('card_fee').amount.minorUnits, -1250);
    expect(parse('card_fee', 0).amount.minorUnits, 0);
  });

  test('crypto withdrawal keeps native fractions and debit direction', () {
    final transaction = LedgerTransaction.fromJson({
      'id': 'crypto-out',
      'type': 'crypto_withdrawal',
      'amount': '0.00000001',
      'currency': 'BTC',
    });

    expect(transaction.amount.minorUnits, 0);
    expect(transaction.amount.decimalAmount, -0.00000001);
    expect(transaction.amount.isNegative, isTrue);
    expect(transaction.amount.isPositive, isFalse);
    expect(transaction.amount.formatted, '-0.00000001 BTC');
  });

  test('crypto deposit retains six decimals without assuming a USD value', () {
    final transaction = LedgerTransaction.fromJson({
      'id': 'crypto-in',
      'type': 'crypto_deposit',
      'amount': '0.000123',
      'currency': 'USDC',
    });

    expect(transaction.amount.currency, 'USDC');
    expect(transaction.amount.decimalAmount, 0.000123);
    expect(transaction.amount.isPositive, isTrue);
    expect(transaction.amount.formatted, '0.000123 USDC');
  });

  test('explicit credit prevents withdrawal name from flipping the amount', () {
    final transaction = LedgerTransaction.fromJson({
      'type': 'crypto_withdrawal',
      'direction': 'credit',
      'amount': '0.000123',
      'currency': 'ETH',
    });

    expect(transaction.amount.decimalAmount, 0.000123);
  });

  test('already signed crypto and its original amount stay negative', () {
    final transaction = LedgerTransaction.fromJson({
      'type': 'crypto_withdrawal',
      'amount': '-0.000123',
      'currency': 'ETH',
      'transactionAmount': '0.00012',
      'transactionCurrency': 'ETH',
    });

    expect(transaction.amount.decimalAmount, -0.000123);
    expect(transaction.displayAmount.decimalAmount, -0.00012);
    expect(transaction.secondarySettlementAmount?.decimalAmount, -0.000123);
  });

  test('provider minor units and existing Money constructors remain cents', () {
    const existing = Money(currency: 'USD', minorUnits: -1250);
    final parsed = LedgerTransaction.fromJson({
      'type': 'crypto_deposit',
      'amount': {'currency': 'USDC', 'minorUnits': 123},
    });

    expect(existing.decimalAmount, -12.5);
    expect(existing.negated.decimalAmount, 12.5);
    expect(parsed.amount.decimalAmount, 1.23);
  });

  test('USD spent buying crypto is an outflow with its actual amount', () {
    final transaction = LedgerTransaction.fromJson({
      'type': 'quantum_to_crypto_exchange',
      'amount': '998.50',
      'currency': 'USD',
      'metadata': {
        'targetCurrency': 'USDC',
        'cryptoAmountReceived': '997.25',
      },
    });

    expect(transaction.amount.decimalAmount, -998.50);
    expect(transaction.amount.currency, 'USD');
    expect(transaction.metadata['cryptoAmountReceived'], '997.25');
  });

  test('explicit credit direction wins over USD-to-crypto operation name', () {
    final transaction = LedgerTransaction.fromJson({
      'type': 'quantum_to_crypto_exchange',
      'amount': '998.50',
      'currency': 'USD',
      'metadata': {'creditDebitIndicator': 'credit'},
    });

    expect(transaction.amount.decimalAmount, 998.50);
  });

  test('generic crypto exchange sign needs a known USD funding operation', () {
    final plain = LedgerTransaction.fromJson({
      'type': 'crypto_exchange',
      'amount': '550.00',
      'currency': 'USD',
    });
    final funding = LedgerTransaction.fromJson({
      'type': 'crypto_exchange',
      'amount': '550.00',
      'currency': 'USD',
      'metadata': {'operation': 'quantum_to_crypto_exchange'},
    });
    final received = LedgerTransaction.fromJson({
      'type': 'quantum_to_crypto_exchange',
      'amount': '549.125',
      'currency': 'USDC',
    });

    expect(plain.amount.decimalAmount, 550.00);
    expect(funding.amount.decimalAmount, -550.00);
    expect(received.amount.decimalAmount, 549.125);
  });

  test('primary-operation flags survive parsing with a true legacy default',
      () {
    expect(parse('crypto_withdrawal').isPrimary, isTrue);
    expect(LedgerTransaction.fromJson({'isPrimary': false}).isPrimary, isFalse);
    expect(LedgerTransaction.fromJson({'IsPrimary': false}).isPrimary, isFalse);
    expect(LedgerTransaction.fromJson({'isPrimary': true}).isPrimary, isTrue);
  });

  test('card identity preserves actual API ids and ignores display hints', () {
    expect(LedgerTransaction.fromJson({'cardId': 17}).cardId, '17');
    expect(LedgerTransaction.fromJson({'CardId': ' 23 '}).cardId, '23');
    expect(
      LedgerTransaction.fromJson({
        'cardId': 17,
        'metadata': {'cardId': 99},
      }).cardId,
      '17',
    );
    expect(
      LedgerTransaction.fromJson({
        'metadata': '{"card_id":42}',
      }).cardId,
      '42',
    );
    expect(
      LedgerTransaction.fromJson({
        'title': 'Card 8763',
        'last4': '8763',
        'metadata': {'externalCardId': 'provider-only-id'},
      }).cardId,
      isEmpty,
    );
  });

  test('fiat lookup includes the banking provider currency registry', () {
    expect(Money.isFiatCurrency(' usd '), isTrue);
    expect(Money.isFiatCurrency('JPY'), isTrue);
    expect(Money.isFiatCurrency('NGN'), isTrue);
    expect(Money.isFiatCurrency('USDC'), isFalse);
    expect(Money.isFiatCurrency('BTC'), isFalse);
    expect(Money.isFiatCurrency(''), isFalse);
  });

  test('provider type names map to filterable kinds', () {
    expect(parse('card_payment').type, TransactionType.card);
    expect(parse('card_payment_reversal').type, TransactionType.card);
    expect(parse('refund').type, TransactionType.card);
    expect(parse('cashback').type, TransactionType.card);
    expect(parse('card_withdrawal').type, TransactionType.card);
    expect(parse('card_unload').type, TransactionType.transfer);
    expect(parse('transfer_in').type, TransactionType.transfer);
    expect(parse('card_topup_fee').type, TransactionType.fee);
    expect(parse('card_loading').type, TransactionType.topUp);
    expect(parse('deposit').type, TransactionType.topUp);
    expect(parse('transfer_to_master').type, TransactionType.transfer);
    expect(parse('p2p_send').type, TransactionType.transfer);
    expect(parse('crypto_withdrawal').type, TransactionType.transfer);
    expect(parse('card_fee').type, TransactionType.fee);
    expect(parse('fees').type, TransactionType.fee);
    expect(parse('card_topup').type, TransactionType.topUp);
    expect(parse('card_load').type, TransactionType.topUp);
    expect(parse('payment').type, TransactionType.payment);
    expect(parse('card_purchase').type, TransactionType.card);
    expect(parse('').type, TransactionType.card);
  });
}
