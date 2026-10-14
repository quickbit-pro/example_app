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
    this.deposits = const [],
    this.payments = const [],
    this.restrictedTradingCurrencies = const [],
  });

  factory BoomFiExchangeOverview.fromJson(Map<String, dynamic> json) {
    final account = _map(_value(json, 'account', 'Account'));
    final balanceEnvelope = _map(_value(json, 'balances', 'Balances'));
    return BoomFiExchangeOverview(
      restrictedTradingCurrencies: _list(_value(json, 'restricted_trading_currencies', 'RestrictedTradingCurrencies') ?? json['restrictedTradingCurrencies']).map((v) => v.toString().trim().toUpperCase()).toList(),
      payments: _list(_value(json, 'payments', 'Payments')).map((item) => BoomFiDeposit.fromJson(_map(item))).toList(),
      deposits: _list(_value(json, 'deposits', 'Deposits'))
          .map((item) => BoomFiDeposit.fromJson(_map(item)))
          .toList(),
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

  final List<String> restrictedTradingCurrencies;
  bool canTrade(String currency) => !restrictedTradingCurrencies.contains(currency.trim().toUpperCase());

  final List<BoomFiDeposit> deposits, payments;
  final int accountId;
  final String accountName;
  final bool accountEnabled;
  final String accountState;
  final List<BoomFiExchangeBalance> balances;
  final List<Map<String, dynamic>> settlementAccounts;
  final List<Map<String, dynamic>> subAccounts;
  final List<String> fiatFundingCurrencies;

  /// The network rows are routes into the same currency balance. Never sum
  /// those repeated amounts. Keep the original rows for account/route selection.
  List<BoomFiExchangeBalance> get displayBalances {
    final currencies = <String, BoomFiExchangeBalance>{};
    for (final balance in balances) {
      final currency = balance.currency.trim().toUpperCase();
      if (currency.isEmpty) continue;
      final current = currencies[currency];
      // Account discovery can add empty route placeholders after provider rows.
      if (current == null || (current.amount == 0 && balance.amount > 0)) {
        currencies[currency] = balance;
      }
    }
    return currencies.values.toList(growable: false);
  }

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
    this.details = const {},
  });

  factory BoomFiTransfer.fromJson(Map<String, dynamic> json) => BoomFiTransfer(
        details: Map<String, dynamic>.unmodifiable(json),
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
  final Map<String, dynamic> details;
  String detail(String key) =>
      (details[key] ?? details['${key[0].toUpperCase()}${key.substring(1)}'])
          ?.toString() ??
      '';
  bool get canKeepFunds =>
      needsFundsDecision && direction == 'interlace_to_equals';
  bool get isTerminal => const {
        'completed',
        'direct_exchange_completed',
        'returned',
        'cancelled',
        'canceled',
        'failed',
        'funds_held'
      }.contains(status);

  bool get isBankExchange => direction == 'exchange_to_bank';
  bool get deliversToCard => direction == 'exchange_to_crypto' && detail('destinationCryptoAddress').isNotEmpty;
  bool get conversionSettled => detail('fiatSettledAt').isNotEmpty ||
      const {'completed', 'settled', 'success', 'succeeded'}.contains(detail('boomFiSettlementStatus').toLowerCase());
  bool get awaitingSettlementDetails => isBankExchange && conversionSettled &&
      status == 'exchange_submitted' && detail('toAmount').isEmpty;
  bool get showInProgress {
    if (const {'completed', 'direct_exchange_completed', 'settled', 'returned',
      'cancelled', 'canceled', 'funds_held', 'exchange_quoted', 'direct_exchange_quoted'}.contains(status)) { return false; }
    // A quote that failed before acceptance never moved money. Retain failures
    // after submission/settlement so held funds remain visible.
    if (isBankExchange && status == 'exchange_failed' &&
        detail('boomFiOrderId').isEmpty && !conversionSettled) { return false; }
    return true;
  }
  String get flowLabel => switch (direction) {
    'exchange_to_bank' => '$cryptoCurrency → $fiatCurrency → Bank account',
    'exchange_to_crypto' => '$cryptoCurrency → $fiatCurrency · ${deliversToCard ? 'Crypto card account' : 'Exchange balance'}',
    'equals_to_interlace' => 'Fiat account → Crypto card',
    'interlace_to_equals' => 'Crypto card → Fiat account',
    _ => 'Exchange transfer',
  };
  List<String> get progressLabels => switch (direction) {
    'exchange_to_bank' => ['Exchange\nbalance', 'Convert to\n$fiatCurrency', 'Withdraw to\nbank'],
    'exchange_to_crypto' => ['Exchange\nbalance', 'Convert to\n$fiatCurrency', deliversToCard ? 'Crypto card\naccount' : 'Exchange\nbalance'],
    'equals_to_interlace' => ['Fiat\naccount', 'Received by\nExchange', 'Converting', 'Crypto\ncard'],
    _ => ['Crypto\ncard', 'Received by\nExchange', 'Converting', 'Fiat\naccount'],
  };
  int get progressStage {
    if (const {'completed','direct_exchange_completed','settled'}.contains(status)) return progressLabels.length;
    if (isBankExchange) {
      if (conversionSettled || const {'withdrawal_ready','withdrawal_submitting','payout_submitted'}.contains(status)) return 2;
      return const {'exchange_accepting','exchange_submitted'}.contains(status) ? 1 : 0;
    }
    if (direction == 'exchange_to_crypto') {
      if (status.startsWith('payout') || conversionSettled) return 2;
      return status == 'direct_exchange_submitted' ? 1 : 0;
    }
    if (status.contains('payout') || status.contains('credit') || status.contains('loading')) return 3;
    if (status.contains('convert') || status.contains('quote') || status == 'submitted') return 2;
    return 1;
  }
  String? get progressStatusLabel {
    if (awaitingSettlementDetails) return 'Awaiting provider details';
    if (!isBankExchange) return null;
    return switch (status) {
      'exchange_quoted' => 'Awaiting confirmation',
      'exchange_preparing' || 'exchange_accepting' => 'Confirming exchange',
      'exchange_submitted' => conversionSettled ? 'Withdrawal pending' : 'Converting',
      'withdrawal_ready' => 'Withdrawal queued',
      'withdrawal_submitting' => 'Confirming withdrawal',
      'payout_submitted' => 'Bank withdrawal processing',
      'exchange_failed' => 'Exchange not completed',
      'completed' => 'Completed',
      _ => null,
    };
  }

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

class BoomFiDeposit {
  const BoomFiDeposit(
      {required this.id,
      required this.paymentId,
      required this.amount,
      required this.currency,
      required this.chainId,
      required this.status,
      required this.providerStatus,
      required this.transactionHash,
      this.createdAt,
      this.updatedAt,
      this.actionUrl,
      this.settlementTransactionHash = '',
      this.paymentMethod = 'Deposit'});
  factory BoomFiDeposit.fromJson(Map<String, dynamic> json) {
    Object? value(String key) =>
        json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
    return BoomFiDeposit(
        id: _integer(value('id')),
        paymentId: _text(value('paymentId')),
        amount: _text(value('amount')),
        currency: _text(value('currency')),
        chainId: _integer(value('chainId')),
        status: _text(value('status')),
        providerStatus: _text(value('providerStatus')),
        paymentMethod: _text(value('paymentMethod')).isEmpty ? 'Deposit' : _text(value('paymentMethod')),
        transactionHash: _text(value('transactionHash')),
        settlementTransactionHash: _text(value('settlementTransactionHash')),
        createdAt: DateTime.tryParse(_text(value('createdAt'))),
        updatedAt: DateTime.tryParse(_text(value('updatedAt'))),
        actionUrl: _text(value('actionUrl')));
  }
  final int id, chainId;
  final String paymentId,
      amount,
      currency,
      status,
      providerStatus,
      transactionHash;
  final DateTime? createdAt, updatedAt;
  final String? actionUrl;
  final String settlementTransactionHash, paymentMethod;
  bool get isDeposit => paymentMethod == 'Deposit';
  bool get requiresAction => status == 'requires_action';
  String get statusLabel => switch (status) {
        'requires_action' => 'Verification required',
        'completed' => 'Completed',
        'failed' => 'Failed',
        'cancelled' => 'Cancelled',
        _ => 'Processing',
      };
  String? get verificationUrl {
    if (!requiresAction) return null;
    final uri = Uri.tryParse(actionUrl ?? '');
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        (uri.hasPort && uri.port != 443) ||
        !const {'www.zbx.com', 'zbx.com'}.contains(uri.host.toLowerCase())) {
      return null;
    }
    return uri.toString();
  }
}
