import '../../../core/models/banking_models.dart';

enum TransactionAssetFilter { all, fiat, crypto }

extension TransactionAssetFilterDisplay on TransactionAssetFilter {
  String get label => switch (this) {
        TransactionAssetFilter.all => 'All',
        TransactionAssetFilter.fiat => 'Fiat',
        TransactionAssetFilter.crypto => 'Crypto',
      };

  /// Asset filtering follows the currency of the amount visible on the row.
  /// A USD leg of a crypto conversion is fiat, even though its operation type
  /// is crypto; no source currency or converted amount is inferred.
  bool matches(LedgerTransaction transaction) {
    final currency = transaction.displayAmount.currency.trim().toUpperCase();
    return switch (this) {
      TransactionAssetFilter.all => true,
      TransactionAssetFilter.fiat => Money.isFiatCurrency(currency),
      TransactionAssetFilter.crypto => _assetCode.hasMatch(currency) &&
          !_nonCurrencyValues.contains(currency) &&
          !Money.isFiatCurrency(currency),
    };
  }
}

enum TransactionActivityType {
  card,
  account,
  crypto,
  transfer,
  topUp,
  payment,
  fee
}

extension TransactionActivityTypeDisplay on TransactionActivityType {
  String get label => switch (this) {
        TransactionActivityType.card => 'Card',
        TransactionActivityType.account => 'Account',
        TransactionActivityType.crypto => 'Crypto',
        TransactionActivityType.transfer => 'Transfer',
        TransactionActivityType.topUp => 'Top up',
        TransactionActivityType.payment => 'Payment',
        TransactionActivityType.fee => 'Fee',
      };

  bool matches(LedgerTransaction transaction) => switch (this) {
        TransactionActivityType.card => _isCard(transaction),
        // Account scope includes fiat and crypto wallet movements. Currency
        // denomination is selected independently by TransactionAssetFilter.
        TransactionActivityType.account => !_isCard(transaction),
        TransactionActivityType.crypto => _isCrypto(transaction),
        TransactionActivityType.transfer =>
          transaction.type == TransactionType.transfer,
        TransactionActivityType.topUp =>
          transaction.type == TransactionType.topUp,
        TransactionActivityType.payment =>
          transaction.type == TransactionType.payment,
        TransactionActivityType.fee => transaction.type == TransactionType.fee,
      };
}

bool _isCard(LedgerTransaction transaction) {
  if (transaction.cardId.trim().isNotEmpty) return true;
  final type = _normalizedKey(transaction.rawType);
  if (type.startsWith('card')) return true;
  // The legacy parser defaults unknown types to card. Provider bank credit,
  // debit and wallet movements must not inherit that fallback classification.
  if (const {'credit', 'debit', 'walletcredit', 'walletdebit', 'boxes'}
      .contains(type)) {
    return false;
  }
  return transaction.type == TransactionType.card && !_isCrypto(transaction);
}

bool _isCrypto(LedgerTransaction transaction) {
  // The provider emits crypto_deposit, crypto_withdrawal, crypto_exchange,
  // crypto_to_quantum and quantum_to_crypto_exchange. A generic exchange can
  // be fiat; its currencies, rather than its name, establish crypto activity.
  return _normalizedKey(transaction.rawType).contains('crypto') ||
      transactionCryptoAssets(transaction).isNotEmpty;
}

/// Actual asset currencies supplied on the ledger row or its structured
/// metadata. Descriptions, merchant names and amounts are never inferred.
Set<String> transactionCryptoAssets(LedgerTransaction transaction) {
  final assets = <String>{};

  void add(Object? value) {
    if (value is! String) return;
    final currency = value.trim().toUpperCase();
    if (!_assetCode.hasMatch(currency) ||
        _nonCurrencyValues.contains(currency) ||
        Money.isFiatCurrency(currency)) {
      return;
    }
    assets.add(currency);
  }

  void collect(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        if (_currencyKeys.contains(_normalizedKey(entry.key.toString()))) {
          add(entry.value);
        }
        collect(entry.value);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        collect(item);
      }
    }
  }

  add(transaction.amount.currency);
  add(transaction.transactionAmount?.currency);
  collect(transaction.metadata);
  return assets;
}

String _normalizedKey(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

final _assetCode = RegExp(r'^[A-Z][A-Z0-9]{1,14}$');
const _nonCurrencyValues = {'UNKNOWN', 'NULL', 'NONE', 'UNDEFINED'};
const _currencyKeys = {
  'currency',
  'currencycode',
  'sourcecurrency',
  'targetcurrency',
  'destinationcurrency',
  'fromcurrency',
  'tocurrency',
  'basecurrency',
  'quotecurrency',
  'settlementcurrency',
  'transactioncurrency',
  'originalcurrency',
  'localcurrency',
  'cryptocurrency',
  'cryptocurrencycode',
  'tokensymbol',
  'assetcode',
  'assetsymbol',
};
