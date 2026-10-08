class BoomFiExchangeOverview {
  const BoomFiExchangeOverview({
    required this.accountId,
    required this.accountName,
    required this.accountEnabled,
    required this.accountState,
    required this.balances,
    required this.settlementAccounts,
    required this.subAccounts,
    required this.fiatFundingCurrencies,
  });

  factory BoomFiExchangeOverview.fromJson(Map<String, dynamic> json) {
    final account = _map(_value(json, 'account', 'Account'));
    final balanceEnvelope = _map(_value(json, 'balances', 'Balances'));
    return BoomFiExchangeOverview(
      accountId: _integer(_value(account, 'id', 'Id')),
      accountName: _text(_value(account, 'name', 'Name')),
      accountEnabled: _boolean(_value(account, 'enabled', 'Enabled')),
      accountState: _text(_value(account, 'state', 'State')),
      balances: _list(_value(balanceEnvelope, 'balances', 'Balances'))
          .map((item) => BoomFiExchangeBalance.fromJson(_map(item)))
          .where((item) => item.currency.isNotEmpty)
          .toList(),
      settlementAccounts:
          _list(_value(json, 'settlement_accounts', 'SettlementAccounts'))
              .map(_map)
              .toList(),
      subAccounts: _list(_value(account, 'sub_accounts', 'SubAccounts'))
          .map(_map)
          .toList(),
      fiatFundingCurrencies: _list(
              _value(json, 'fiat_funding_currencies', 'FiatFundingCurrencies'))
          .map((item) => item.toString().trim().toUpperCase())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }

  final int accountId;
  final String accountName;
  final bool accountEnabled;
  final String accountState;
  final List<BoomFiExchangeBalance> balances;
  final List<Map<String, dynamic>> settlementAccounts;
  final List<Map<String, dynamic>> subAccounts;
  final List<String> fiatFundingCurrencies;

  bool get hasProviderData =>
      accountId > 0 ||
      balances.isNotEmpty ||
      settlementAccounts.isNotEmpty ||
      subAccounts.isNotEmpty;

  bool get isReady =>
      hasProviderData &&
      (accountEnabled ||
          const {'ready', 'active', 'enabled'}
              .contains(accountState.trim().toLowerCase()) ||
          balances.isNotEmpty);
}

class BoomFiExchangeBalance {
  const BoomFiExchangeBalance({
    required this.accountId,
    required this.currency,
    required this.amount,
    required this.pendingAmount,
    required this.chainId,
    required this.chainName,
    required this.tokenAddress,
  });

  factory BoomFiExchangeBalance.fromJson(Map<String, dynamic> json) {
    final chain = _map(_value(json, 'chain', 'Chain'));
    return BoomFiExchangeBalance(
      accountId: _integer(_value(json, 'account_id', 'AccountId')),
      currency: _text(_value(json, 'currency', 'Currency')).toUpperCase(),
      amount: _decimal(_value(json, 'amount', 'Amount')),
      pendingAmount: _decimal(_value(json, 'pending_amount', 'PendingAmount')),
      chainId: _integer(_value(chain, 'id', 'Id')),
      chainName: _text(_value(chain, 'name', 'Name')),
      tokenAddress: _text(_value(json, 'token_address', 'TokenAddress')),
    );
  }

  final int accountId;
  final String currency;
  final double amount;
  final double pendingAmount;
  final int chainId;
  final String chainName;
  final String tokenAddress;

  bool get isCrypto => chainId != 0;
  String get key => '$accountId:$currency:$chainId';
}

class BoomFiTransfer {
  const BoomFiTransfer({
    required this.id,
    required this.status,
    required this.direction,
    required this.cryptoCurrency,
    required this.cryptoAmount,
    required this.fiatCurrency,
    required this.quoteDecisionStatus,
    required this.completionMessage,
  });

  factory BoomFiTransfer.fromJson(Map<String, dynamic> json) => BoomFiTransfer(
        id: _integer(_value(json, 'id', 'Id')),
        status: _text(_value(json, 'status', 'Status')),
        direction:
            _text(_value(json, 'transferDirection', 'TransferDirection')),
        cryptoCurrency: _text(_value(json, 'cryptoCurrency', 'CryptoCurrency')),
        cryptoAmount: _text(_value(json, 'cryptoAmount', 'CryptoAmount')),
        fiatCurrency: _text(_value(json, 'fiatCurrency', 'FiatCurrency')),
        quoteDecisionStatus:
            _text(_value(json, 'quoteDecisionStatus', 'QuoteDecisionStatus')),
        completionMessage:
            _text(_value(json, 'completionMessage', 'CompletionMessage')),
      );

  final int id;
  final String status;
  final String direction;
  final String cryptoCurrency;
  final String cryptoAmount;
  final String fiatCurrency;
  final String quoteDecisionStatus;
  final String completionMessage;

  bool get needsQuoteDecision => status == 'awaiting_quote_approval';
  bool get needsFundsDecision => status == 'awaiting_funds_decision';
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<Object?> _list(Object? value) => value is List ? value : const [];

Object? _value(Map<String, dynamic> json, String first, String second) =>
    json[first] ?? json[second];

String _text(Object? value) => value?.toString().trim() ?? '';

int _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value)) ?? 0;

double _decimal(Object? value) =>
    value is num ? value.toDouble() : double.tryParse(_text(value)) ?? 0;

bool _boolean(Object? value) =>
    value == true || _text(value).toLowerCase() == 'true';
