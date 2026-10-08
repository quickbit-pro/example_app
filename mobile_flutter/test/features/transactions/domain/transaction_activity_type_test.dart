import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/domain/transaction_activity_type.dart';

LedgerTransaction _transaction(Map<String, dynamic> values) =>
    LedgerTransaction.fromJson({
      'id': 'transaction-1',
      'amount': '12.50',
      'currency': 'USD',
      'type': 'transfer_in',
      ...values,
    });

void main() {
  test('asset filter separates displayed fiat and crypto within conversions',
      () {
    final usd = _transaction({
      'type': 'quantum_to_crypto_exchange',
      'currency': 'USD',
      'metadata': {'targetCurrency': 'USDC'},
    });
    final usdt = _transaction({
      'type': 'crypto_to_quantum_transfer',
      'currency': 'USDT',
      'metadata': {'destinationCurrency': 'USD'},
    });

    expect(TransactionActivityType.crypto.matches(usd), isTrue);
    expect(TransactionAssetFilter.fiat.matches(usd), isTrue);
    expect(TransactionAssetFilter.crypto.matches(usd), isFalse);
    expect(TransactionAssetFilter.crypto.matches(usdt), isTrue);
    expect(TransactionAssetFilter.fiat.matches(usdt), isFalse);
    expect(TransactionAssetFilter.all.matches(usd), isTrue);
    expect(TransactionAssetFilter.all.matches(usdt), isTrue);
  });

  test(
      'asset filter follows original displayed amount over settlement currency',
      () {
    final nativeCrypto = _transaction({
      'currency': 'USD',
      'transactionCurrency': 'BTC',
      'transactionAmount': '0.00000001',
    });
    final nativeFiat = _transaction({
      'currency': 'USDC',
      'transactionCurrency': 'NGN',
      'transactionAmount': '1000.00',
    });

    expect(TransactionAssetFilter.crypto.matches(nativeCrypto), isTrue);
    expect(TransactionAssetFilter.fiat.matches(nativeCrypto), isFalse);
    expect(TransactionAssetFilter.fiat.matches(nativeFiat), isTrue);
    expect(TransactionAssetFilter.crypto.matches(nativeFiat), isFalse);
  });

  test('asset filters do not infer a currency from merchant or operation text',
      () {
    final fiat = _transaction({
      'currency': 'JPY',
      'title': 'Crypto BTC exchange',
      'metadata': {'sourceCurrency': 'USDT'},
    });
    final unknown = _transaction({'currency': 'unknown'});

    expect(TransactionAssetFilter.fiat.matches(fiat), isTrue);
    expect(TransactionAssetFilter.crypto.matches(fiat), isFalse);
    expect(TransactionAssetFilter.all.matches(unknown), isTrue);
    expect(TransactionAssetFilter.fiat.matches(unknown), isFalse);
    expect(TransactionAssetFilter.crypto.matches(unknown), isFalse);
  });

  test('all crypto types remain identifiable even when settling in USD', () {
    for (final type in [
      'crypto_deposit',
      'crypto_withdrawal',
      'crypto_exchange',
      'crypto_to_quantum',
      'quantum_to_crypto_exchange',
    ]) {
      final transaction = _transaction({'type': type});
      expect(TransactionActivityType.crypto.matches(transaction), isTrue);
      expect(TransactionActivityType.account.matches(transaction), isTrue);
      expect(transactionCryptoAssets(transaction), isEmpty);
    }
  });

  test('asset selectors use native and structured exchange currencies', () {
    final transaction = _transaction({
      'type': 'exchange',
      'transactionCurrency': 'ETH',
      'transactionAmount': '0.001',
      'metadata': {
        'source_currency': ' usdc ',
        'targetCurrency': 'USD',
        'exchange': {'TokenSymbol': 'BTC'},
        'legs': [
          {'cryptoCurrencyCode': 'USDT'},
          {'destinationCurrency': 'EUR'},
        ],
      },
    });

    expect(
        transactionCryptoAssets(transaction), {'ETH', 'USDC', 'BTC', 'USDT'});
    expect(TransactionActivityType.crypto.matches(transaction), isTrue);
  });

  test(
      'merchant words and remarks cannot classify a fiat card payment as crypto',
      () {
    final transaction = _transaction({
      'type': 'card_payment',
      'title': 'Ethereum museum',
      'merchantName': 'Crypto coffee BTC',
      'metadata': {
        'description': 'Bought USDC book',
        'merchant': {'name': 'Bitcoin store'},
        'sourceCurrency': 'unknown',
      },
    });

    expect(TransactionActivityType.card.matches(transaction), isTrue);
    expect(TransactionActivityType.crypto.matches(transaction), isFalse);
    expect(transactionCryptoAssets(transaction), isEmpty);
  });

  test('fiat exchanges and fiat accounts remain separate from crypto', () {
    for (final currency in ['EUR', 'JPY', 'MXN', 'INR', 'NGN']) {
      final transaction = _transaction({
        'type': 'exchange',
        'currency': currency,
        'metadata': {'sourceCurrency': currency, 'targetCurrency': 'USD'},
      });

      expect(TransactionActivityType.account.matches(transaction), isTrue);
      expect(TransactionActivityType.transfer.matches(transaction), isTrue);
      expect(TransactionActivityType.crypto.matches(transaction), isFalse);
      expect(transactionCryptoAssets(transaction), isEmpty);
    }
  });

  test('bank and wallet credits do not inherit the legacy card fallback', () {
    for (final type in ['credit', 'debit', 'wallet_credit', 'wallet_debit']) {
      final transaction = _transaction({'type': type});

      expect(TransactionActivityType.card.matches(transaction), isFalse);
      expect(TransactionActivityType.account.matches(transaction), isTrue);
    }
  });

  test('native crypto never falls through to the legacy card default', () {
    final transaction = _transaction({'type': '', 'currency': 'BTC'});

    expect(TransactionActivityType.crypto.matches(transaction), isTrue);
    expect(TransactionActivityType.card.matches(transaction), isFalse);
    expect(TransactionActivityType.account.matches(transaction), isTrue);
  });

  test('account type combines independently with fiat and crypto denominations',
      () {
    final fiat = _transaction({'currency': 'EUR', 'accountId': 'account-1'});
    final crypto = _transaction({
      'type': 'crypto_withdrawal',
      'currency': 'USDT',
      'walletId': 'wallet-1',
    });
    final card = _transaction({
      'type': 'card_payment',
      'currency': 'USD',
      'cardId': 17,
    });

    expect(TransactionActivityType.account.matches(fiat), isTrue);
    expect(TransactionAssetFilter.fiat.matches(fiat), isTrue);
    expect(TransactionActivityType.account.matches(crypto), isTrue);
    expect(TransactionAssetFilter.crypto.matches(crypto), isTrue);
    expect(TransactionActivityType.account.matches(card), isFalse);
    expect(TransactionActivityType.card.matches(card), isTrue);
  });

  test('card fees and top-ups belong to the card source as well as their type',
      () {
    final fee = _transaction({'type': 'card_fee', 'cardId': 17});
    final topUp = _transaction({'type': 'card_topup'});

    expect(TransactionActivityType.card.matches(fee), isTrue);
    expect(TransactionActivityType.fee.matches(fee), isTrue);
    expect(TransactionActivityType.account.matches(fee), isFalse);
    expect(TransactionActivityType.card.matches(topUp), isTrue);
    expect(TransactionActivityType.topUp.matches(topUp), isTrue);
  });

  test('generic row with an actual card ID stays in its card source', () {
    final transaction = _transaction({'type': 'fees', 'cardId': 23});

    expect(TransactionActivityType.card.matches(transaction), isTrue);
    expect(TransactionActivityType.account.matches(transaction), isFalse);
  });

  test('crypto direction remains supplied by the signed ledger amount', () {
    final incoming =
        _transaction({'type': 'crypto_deposit', 'currency': 'USDC'});
    final outgoing = _transaction({
      'type': 'crypto_withdrawal',
      'currency': 'BTC',
      'amount': '0.00000001',
    });

    expect(TransactionActivityType.crypto.matches(incoming), isTrue);
    expect(incoming.amount.isPositive, isTrue);
    expect(TransactionActivityType.crypto.matches(outgoing), isTrue);
    expect(outgoing.amount.isNegative, isTrue);
    expect(outgoing.amount.decimalAmount, -0.00000001);
  });
}
