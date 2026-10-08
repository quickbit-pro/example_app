import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/formatters/transaction_display.dart';
import '../../banking/application/banking_providers.dart' as banking;
import '../../platform/application/platform_providers.dart';
import '../../rewards/domain/rewards_models.dart';
import '../../wallets/domain/exchange_models.dart';
import '../../wallets/domain/receiving_account_details.dart';
import '../domain/dashboard_models.dart';
import '../domain/market_rates.dart';

final refreshHoppaDashboardProvider = Provider<Future<void> Function()>((ref) {
  Future<void>? inFlight;
  Future<void> refresh() async {
    // Invalidate the source snapshots as well as the composed Home snapshot.
    // Otherwise a fresh total can be paired with yesterday's transactions.
    ref.invalidate(cardDetailProvider);
    ref.invalidate(banking.cardsProvider);
    ref.invalidate(banking.dashboardProvider);
    ref.invalidate(banking.accountsProvider);
    ref.invalidate(banking.transactionsProvider);
    ref.invalidate(banking.activityTransactionsProvider);
    ref.invalidate(banking.activityAccountTransactionsProvider);
    ref.invalidate(banking.activityCardTransactionsProvider);
    ref.invalidate(banking.accountTransactionsProvider);
    ref.invalidate(budgetsProvider);
    ref.invalidate(mobileTenantConfigProvider);
    ref.invalidate(equalsBankingInfoProvider);
    ref.invalidate(exchangeOverviewProvider);
    ref.invalidate(userAssetsProvider);
    ref.invalidate(userWalletsProvider);
    ref.invalidate(portfolioEstimateProvider);
    ref.invalidate(kycDetailedStatusProvider);
    ref.invalidate(marketRatesProvider);
    ref.invalidate(hoppaDashboardProvider);
    await ref.read(hoppaDashboardProvider.future);
  }

  return () => inFlight ??= (() {
        // Entry/resume can coincide with the first fetch. Share that request
        // instead of invalidating it and paying for the same API calls twice.
        final current = ref.read(hoppaDashboardProvider);
        if (current.isLoading) {
          return ref.read(hoppaDashboardProvider.future).then<void>((_) {});
        }
        return refresh();
      })()
          .whenComplete(() => inFlight = null);
});

final hoppaDashboardProvider =
    FutureProvider<HoppaDashboardSnapshot>((ref) async {
  // Riverpod creates a provider the first time it is watched, so awaiting one
  // source before watching the next loads Home one round trip at a time.
  // Watch every source that does not depend on another response up front;
  // the awaits below then only wait for requests that are already in flight.
  final bankingFuture = ref.watch(banking.dashboardProvider.future);
  final detailedAccountsFuture = _bankingAccountsOrNullWhenUnavailable(
      ref.watch(banking.accountsProvider.future));
  final tenantConfigFuture = _tenantConfigWhenUnavailable(
    ref.watch(mobileTenantConfigProvider.future),
  );
  // budgetsProvider answers with an empty list itself when Equals Money is
  // disabled for the tenant, so it can start before the config arrives.
  final budgetsFuture = _emptyPlatformResourcesWhenUnavailable(
    ref.watch(budgetsProvider.future),
  );
  final portfolioFuture = _portfolioEstimateWhenUnavailable(
    ref.watch(portfolioEstimateProvider.future),
  );

  final bankingSnapshot = await bankingFuture;
  final isBusinessAccount = bankingSnapshot.profile.isBusinessAccount;
  final listedCards =
      isBusinessAccount ? const <PaymentCard>[] : bankingSnapshot.cards;
  // Everything that depends on the profile starts here, together: the
  // per-card details plus the personal-account wallet and exchange sources.
  // List responses can retain yesterday's balance after the detail endpoint
  // has refreshed it. Share the Cards screen's source and its invalidations.
  final currentCardsFuture = Future.wait([
    for (final card in listedCards)
      card.status == CardStatus.cancelled
          ? Future<PaymentCard?>.value(card)
          : card.id.trim().isEmpty
              ? Future<PaymentCard?>.value(null)
              : _currentCardWhenUnavailable(
                  ref.watch(cardDetailProvider(card.id).future), card.id),
  ]);
  final assetsFuture = isBusinessAccount
      ? Future.value(const <PlatformResource>[])
      : _emptyPlatformResourcesWhenUnavailable(
          ref.watch(userAssetsProvider.future),
        );
  final walletsFuture = isBusinessAccount
      ? Future.value(const <PlatformResource>[])
      : _emptyPlatformResourcesWhenUnavailable(
          ref.watch(userWalletsProvider.future),
        );
  final tenantConfig = await tenantConfigFuture;
  final fiatEnabled = tenantConfig?.equalsMoneyEnabled ?? true;
  final exchangeFuture =
      !isBusinessAccount && tenantConfig?.boomFiExchangeEnabled == true
          ? _exchangeOverviewWhenUnavailable(
              ref.watch(exchangeOverviewProvider.future),
            )
          : Future<BoomFiExchangeOverview?>.value(null);
  final equalsBudgets =
      fiatEnabled ? await budgetsFuture : const <PlatformResource>[];
  final equalsBankingInfoFuture = equalsBudgets.isEmpty
      ? Future.value(const <PlatformResource>[])
      : _emptyPlatformResourcesWhenUnavailable(
          ref.watch(equalsBankingInfoProvider.future),
        );

  final currentCards = await currentCardsFuture;
  final detailedAccounts =
      await detailedAccountsFuture ?? bankingSnapshot.accounts;
  final assets = await assetsFuture;
  final wallets = await walletsFuture;
  final equalsBankingInfo = await equalsBankingInfoFuture;
  final hoppaPortfolioEstimate = await portfolioFuture;
  final marketRates = hoppaPortfolioEstimate == null
      ? await _marketRatesWhenUnavailable(
          ref.watch(marketRatesProvider.future),
        )
      : null;
  final exchange = await exchangeFuture;
  final allBalanceAccounts = _balanceAccountsFromSources(
    bankingAccounts: detailedAccounts,
    primary: assets,
    fallback: wallets,
    equalsBudgets: equalsBudgets,
    equalsBankingInfo: equalsBankingInfo,
    exchange: exchange,
  );
  final balanceAccounts = isBusinessAccount
      ? allBalanceAccounts
          .where((account) => account.provider == 'EqualsMoney')
          .toList()
      : fiatEnabled
          ? allBalanceAccounts
          : allBalanceAccounts
              .where((account) => account.provider != 'EqualsMoney')
              .toList();
  final accountReady =
      bankingSnapshot.profile.isKycReady || bankingSnapshot.canUseBanking;

  return HoppaDashboardSnapshot(
    customerName: bankingSnapshot.profile.name,
    accountId: bankingSnapshot.profile.id,
    accounts: balanceAccounts,
    // Only the assets the crypto card can hold (USD, USDC, USDT); this keeps
    // Home in step with the Crypto tab instead of listing every provider
    // wallet the API returns.
    holdings: [
      ...assets,
      ...wallets,
    ]
        .where(_isVisibleInterlaceWalletResource)
        .expand(_cryptoHoldingsFromResource)
        .whereType<HoppaCryptoHolding>()
        .toList(),
    activities:
        // The same rows Activity draws: duplicate provider views folded and
        // each fee on the row it charges.
        groupCardFees(bankingSnapshot.transactions)
            .map(_activityFromTransaction)
            .toList(),
    cards: [
      for (var i = 0; i < listedCards.length; i++)
        currentCards[i] ?? listedCards[i],
    ],
    cardBalancesAvailable: currentCards.every((card) => card != null),
    onboardingProgress: _onboardingProgress(
      bankingSnapshot.onboarding,
      accountReady: accountReady,
    ),
    marketSentiment: '',
    requiresKyc: !bankingSnapshot.profile.isKycReady,
    accountReady: accountReady,
    fiatEnabled: fiatEnabled,
    exchangeEnabled: isBusinessAccount
        ? accountReady
        : tenantConfig?.boomFiExchangeEnabled ?? false,
    outflowsEnabled: isBusinessAccount
        ? accountReady
        : tenantConfig?.walletOutflowsEnabled ?? false,
    referralsEnabled: tenantConfig?.referralsEnabled ?? false,
    vouchersEnabled: tenantConfig?.vouchersEnabled ?? false,
    isBusinessAccount: isBusinessAccount,
    portfolioEstimate: hoppaPortfolioEstimate ??
        _portfolioEstimateFromRates(balanceAccounts, marketRates),
  );
});

Future<PaymentCard?> _currentCardWhenUnavailable(
  Future<PaymentCard> request,
  String cardId,
) async {
  try {
    final card = await request;
    return card.id == cardId && card.hasReportedBalance ? card : null;
  } on DioException {
    // Keep card navigation available, but do not total stale list balances.
    return null;
  }
}

Future<MarketRateTable?> _marketRatesWhenUnavailable(
  Future<MarketRateTable> request,
) async {
  try {
    return await request;
  } on DioException {
    return null;
  }
}

Future<PortfolioEstimate?> _portfolioEstimateWhenUnavailable(
  Future<PortfolioEstimate> request,
) async {
  try {
    return await request;
  } on DioException {
    return null;
  }
}

PortfolioEstimate? _portfolioEstimateFromRates(
  List<HoppaFiatAccount> accounts,
  MarketRateTable? rateTable,
) {
  if (rateTable == null || rateTable.rates.isEmpty) return null;

  var total = 0.0;
  var valuedBalances = 0;
  final missing = <String>{};
  for (final account in accounts) {
    final currency = account.currency.trim().toUpperCase();
    final value = rateTable.value(currency, account.balance);
    if (value == null) {
      if (account.balance.abs() >= 0.00000001) missing.add(currency);
      continue;
    }
    total += value;
    valuedBalances++;
  }

  if (valuedBalances == 0) return null;
  return PortfolioEstimate(
    baseCurrency: rateTable.baseCurrency,
    total: total,
    valuedAt: rateTable.refreshedAt,
    isPartial: rateTable.isPartial || missing.isNotEmpty,
    isStale: rateTable.isStale,
    missingCurrencies: missing.toList()..sort(),
  );
}

Future<MobileTenantConfig?> _tenantConfigWhenUnavailable(
  Future<MobileTenantConfig> request,
) async {
  try {
    return await request;
  } on DioException {
    return null;
  }
}

Future<List<PlatformResource>> _emptyPlatformResourcesWhenUnavailable(
  Future<List<PlatformResource>> request,
) async {
  try {
    return await request;
  } on DioException {
    // Assets and wallets enrich the dashboard, but they are not required to
    // render it. A provider outage or timeout must not blank the whole Home
    // screen when profile, accounts, cards, and activity are still healthy.
    return const [];
  }
}

Future<List<AccountBalance>?> _bankingAccountsOrNullWhenUnavailable(
  Future<List<AccountBalance>> request,
) async {
  try {
    return await request;
  } on DioException {
    // The composed dashboard snapshot carries the same accounts list.
    return null;
  }
}

Future<BoomFiExchangeOverview?> _exchangeOverviewWhenUnavailable(
  Future<BoomFiExchangeOverview> request,
) async {
  try {
    return await request;
  } on DioException {
    return null;
  }
}

List<HoppaFiatAccount> _balanceAccountsFromResources(
  List<PlatformResource> resources, {
  String fallbackProvider = 'BoomFi',
  bool dedupeBalanceIds = true,
  bool interlaceWalletsOnly = false,
}) {
  final seenBalanceIds = <String>{};
  final totals = <String, _ProviderBalance>{};

  for (final resource in resources) {
    if (interlaceWalletsOnly && !_isVisibleInterlaceWalletResource(resource)) {
      continue;
    }
    for (final entry in _balanceEntriesFromResource(resource)) {
      if (dedupeBalanceIds &&
          entry.id.isNotEmpty &&
          !seenBalanceIds.add(entry.id)) {
        continue;
      }
      final provider = _providerName(resource, fallbackProvider);
      final key = '$provider:${entry.currency}';
      totals.update(
        key,
        (value) => value.copyWith(amount: value.amount + entry.amount),
        ifAbsent: () => _ProviderBalance(
          currency: entry.currency,
          provider: provider,
          amount: entry.amount,
        ),
      );
    }
  }

  return totals.entries
      .where((entry) => entry.value.currency.trim().isNotEmpty)
      .map(
        (entry) => HoppaFiatAccount(
          id: entry.key,
          name: '${entry.value.currency} balance',
          currency: entry.value.currency,
          balance: entry.value.amount,
          available: entry.value.amount,
          iban: '',
          tint: _assetColor(entry.value.currency),
          provider: entry.value.provider,
        ),
      )
      .toList()
    ..sort((left, right) {
      final provider = left.provider.compareTo(right.provider);
      return provider == 0 ? left.currency.compareTo(right.currency) : provider;
    });
}

List<HoppaFiatAccount> _balanceAccountsFromSources({
  required List<AccountBalance> bankingAccounts,
  required List<PlatformResource> primary,
  required List<PlatformResource> fallback,
  required List<PlatformResource> equalsBudgets,
  required List<PlatformResource> equalsBankingInfo,
  BoomFiExchangeOverview? exchange,
}) {
  final result = <HoppaFiatAccount>[];
  final indexes = <String, int>{};

  void add(HoppaFiatAccount account) {
    final key = '${account.provider}:${account.currency}'.toLowerCase();
    final existingIndex = indexes[key];
    if (existingIndex == null) {
      indexes[key] = result.length;
      result.add(account);
      return;
    }
    // Sources are added in priority order. A reported zero is a balance,
    // not missing data: lower-priority wallet/account snapshots can still
    // contain funds already consumed by a card top-up.
  }

  for (final account in _balanceAccountsFromResources(
    primary,
    fallbackProvider: 'Interlace',
    interlaceWalletsOnly: true,
  )) {
    add(account);
  }
  for (final account in _balanceAccountsFromResources(
    fallback,
    fallbackProvider: 'Interlace',
    interlaceWalletsOnly: true,
  )) {
    add(account);
  }
  for (final account in _balanceAccountsFromResources(
    equalsBudgets,
    fallbackProvider: 'EqualsMoney',
    dedupeBalanceIds: false,
  )) {
    add(account);
  }
  if (exchange != null) {
    for (final balance in exchange.balances) {
      add(
        HoppaFiatAccount(
          id: 'boomfi:${balance.key}',
          name: exchange.accountName.isEmpty
              ? 'Exchange balance'
              : exchange.accountName,
          currency: balance.currency,
          balance: balance.amount,
          available: balance.amount,
          iban: '',
          tint: _assetColor(balance.currency),
          provider: 'BoomFi',
        ),
      );
    }
  }

  // Generic banking accounts are a fallback. Provider-specific endpoints
  // above distinguish Quantum wallets from per-card balances and aggregate
  // Equals budgets correctly.
  for (final account in bankingAccounts) {
    final provider =
        _normalizedProvider(account.provider, fallback: 'Interlace');
    final balances = account.currencyBalances.isNotEmpty
        ? account.currencyBalances
        : _accountMoneyValues(account);
    for (final balance in balances) {
      add(
        HoppaFiatAccount(
          id: '${account.id}:${balance.currency}',
          name: account.name,
          currency: balance.currency.toUpperCase(),
          balance: balance.minorUnits / 100,
          available: balance.minorUnits / 100,
          iban: account.iban,
          tint: _assetColor(balance.currency),
          provider: provider,
          isPrimary: result.isEmpty,
        ),
      );
    }
  }

  final receivingAccounts = receivingAccountsFromResources(equalsBankingInfo);
  return result.map((account) {
    if (account.provider != 'EqualsMoney') return account;
    final matchingBudgets = <String, PlatformResource>{};
    var hasUnidentifiedBudget = false;
    for (final budget in equalsBudgets) {
      if (_providerName(budget, 'EqualsMoney') != 'EqualsMoney') continue;
      if (!_balanceEntriesFromResource(budget)
          .any((entry) => entry.currency == account.currency)) {
        continue;
      }
      // PlatformResource.id can be synthesized from a title or currency.
      // Account navigation requires an identifier present in the API payload.
      final budgetTitle = (_textValue(budget.metadata, const [
                'displayName',
                'DisplayName',
                'name',
                'Name',
                'title',
                'Title',
              ]) ??
              budget.title)
          .trim()
          .toLowerCase();
      final budgetId = (_textValue(budget.metadata, const [
                'budgetId',
                'BudgetId',
                'id',
                'Id',
              ]) ??
              // On named budgets accountId identifies their shared owner.
              // Only the primary account can use that ID as its own scope.
              (budgetTitle == 'account balance'
                  ? _textValue(
                      budget.metadata, const ['accountId', 'AccountId'])
                  : null) ??
              '')
          .trim();
      if (budgetId.isEmpty) {
        hasUnidentifiedBudget = true;
      } else {
        matchingBudgets[budgetId] = budget;
      }
    }
    final budget = !hasUnidentifiedBudget && matchingBudgets.length == 1
        ? matchingBudgets.values.single
        : null;
    final receiving = budget == null
        ? null
        : receivingAccountForBudget(
            budget,
            receivingAccounts,
            currency: account.currency,
          );
    return HoppaFiatAccount(
      id: account.id,
      name: account.name,
      currency: account.currency,
      balance: account.balance,
      available: account.available,
      // A provider/currency total can span multiple accounts. Its identity
      // must remain unset unless the actual source budget is unique.
      iban: receiving?.isIban == true ? receiving!.accountNumber : '',
      accountNumber: receiving?.accountNumber ?? '',
      tint: account.tint,
      provider: account.provider,
      isPrimary: account.isPrimary,
      budgetId: budget == null ? '' : matchingBudgets.keys.single,
    );
  }).toList();
}

bool _isVisibleInterlaceWalletResource(PlatformResource resource) {
  final currency = _assetCode(resource)?.toUpperCase();
  if (!const {'USD', 'USDC', 'USDT'}.contains(currency)) return false;
  if (currency != 'USD') return true;

  final balanceType = _textValue(resource.metadata, const [
    'balanceType',
    'BalanceType',
  ])?.toLowerCase().replaceAll(' ', '');
  return balanceType == null || balanceType == 'quantumaccount';
}

List<Money> _accountMoneyValues(AccountBalance account) {
  final values = <String, Money>{};
  for (final money in [account.available, account.balance]) {
    final currency = money.currency.trim().toUpperCase();
    final existing = values[currency];
    if (existing == null ||
        (existing.minorUnits == 0 && money.minorUnits != 0)) {
      values[currency] = money;
    }
  }
  return values.values.toList();
}

String _providerName(PlatformResource resource, String fallback) {
  final value = _textValue(resource.metadata, const [
    'provider',
    'Provider',
    'providerName',
    'ProviderName',
    'bankProvider',
    'BankProvider',
  ]);
  return _normalizedProvider(value, fallback: fallback);
}

String _normalizedProvider(String? value, {required String fallback}) {
  final normalized = value?.trim().toLowerCase() ?? '';
  if (normalized.contains('equals')) return 'EqualsMoney';
  if (normalized.contains('interlace')) return 'Interlace';
  if (normalized.contains('boom')) return 'BoomFi';
  return value?.trim().isNotEmpty == true ? value!.trim() : fallback;
}

class _ProviderBalance {
  const _ProviderBalance({
    required this.currency,
    required this.provider,
    required this.amount,
  });

  final String currency;
  final String provider;
  final double amount;

  _ProviderBalance copyWith({double? amount}) => _ProviderBalance(
        currency: currency,
        provider: provider,
        amount: amount ?? this.amount,
      );
}

List<_BalanceEntry> _balanceEntriesFromResource(PlatformResource resource) {
  final balances =
      _listValue(resource.metadata, const ['balances', 'Balances']);
  if (balances != null && balances.isNotEmpty) {
    return balances
        .whereType<Map>()
        .map((balance) {
          final normalized =
              balance.map((key, value) => MapEntry(key.toString(), value));
          final currency = _textValue(normalized, const [
            'currency',
            'Currency',
            'currencyCode',
            'CurrencyCode',
            'asset',
            'Asset',
          ]);
          if (currency == null) {
            return null;
          }

          return _BalanceEntry(
            id: '${_resourceBalanceId(resource)}:${currency.toUpperCase()}',
            currency: currency.toUpperCase(),
            amount: _balanceAmount(normalized),
          );
        })
        .whereType<_BalanceEntry>()
        .toList();
  }

  final currency = _assetCode(resource);
  if (currency == null) {
    return const [];
  }

  return [
    _BalanceEntry(
      id: _resourceBalanceId(resource),
      currency: currency.toUpperCase(),
      amount: _balanceAmount(resource.metadata),
    ),
  ];
}

double _balanceAmount(Map<String, dynamic> json) {
  return _doubleValue(json, const [
        'availableBalance',
        'AvailableBalance',
        'available',
        'Available',
        'balance',
        'Balance',
        'amount',
        'Amount',
      ]) ??
      0;
}

String _resourceBalanceId(PlatformResource resource) {
  final value = _textValue(resource.metadata, const [
        'balanceId',
        'BalanceId',
        'walletId',
        'WalletId',
        'id',
        'Id',
      ]) ??
      resource.id;
  return value.trim();
}

class _BalanceEntry {
  const _BalanceEntry({
    required this.id,
    required this.currency,
    required this.amount,
  });

  final String id;
  final String currency;
  final double amount;
}

HoppaCryptoHolding? _cryptoHoldingFromResource(PlatformResource resource) {
  final symbol = _assetCode(resource);
  if (symbol == null) {
    return null;
  }

  final fiatValue = _doubleValue(resource.metadata, const [
    'fiatValue',
    'FiatValue',
    'value',
    'Value',
    'eurValue',
    'EurValue',
    'marketValue',
    'MarketValue',
  ]);
  final changePercent = _doubleValue(resource.metadata, const [
    'changePercent',
    'ChangePercent',
    'priceChangePercent',
    'PriceChangePercent',
    'percentChange24h',
    'PercentChange24h',
    'change24h',
    'Change24h',
  ]);

  return HoppaCryptoHolding(
    symbol: symbol,
    name: _textValue(resource.metadata, const [
          'name',
          'Name',
          'displayName',
          'DisplayName',
          'assetName',
          'AssetName',
          'currencyName',
          'CurrencyName',
        ]) ??
        resource.title,
    amount: _doubleValue(resource.metadata, const [
          'amount',
          'Amount',
          'balance',
          'Balance',
          'available',
          'Available',
          'availableBalance',
          'AvailableBalance',
          'quantity',
          'Quantity',
        ]) ??
        0,
    fiatValue: fiatValue ?? 0,
    price: _doubleValue(resource.metadata, const [
          'price',
          'Price',
          'marketPrice',
          'MarketPrice',
          'currentPrice',
          'CurrentPrice',
        ]) ??
        0,
    changePercent: changePercent ?? 0,
    tint: _assetColor(symbol),
    hasFiatValue: fiatValue != null,
    hasChangePercent: changePercent != null,
  );
}

List<HoppaCryptoHolding> _cryptoHoldingsFromResource(
  PlatformResource resource,
) {
  final balances =
      _listValue(resource.metadata, const ['balances', 'Balances']);
  if (balances == null || balances.isEmpty) {
    final holding = _cryptoHoldingFromResource(resource);
    return holding == null ? const [] : [holding];
  }

  return balances
      .whereType<Map>()
      .map((balance) =>
          balance.map((key, value) => MapEntry(key.toString(), value)))
      .map(_cryptoHoldingFromBalance)
      .whereType<HoppaCryptoHolding>()
      .toList();
}

HoppaCryptoHolding? _cryptoHoldingFromBalance(Map<String, dynamic> balance) {
  final rawSymbol = _textValue(balance, const [
    'currency',
    'Currency',
    'currencyCode',
    'CurrencyCode',
    'asset',
    'Asset',
    'tokenSymbol',
    'TokenSymbol',
  ]);
  if (rawSymbol == null) {
    return null;
  }

  final symbol = rawSymbol.toUpperCase();
  return HoppaCryptoHolding(
    symbol: symbol,
    name: symbol,
    amount: _doubleValue(balance, const [
          'available',
          'Available',
          'balance',
          'Balance',
          'amount',
          'Amount',
        ]) ??
        0,
    fiatValue: 0,
    price: 0,
    changePercent: 0,
    tint: _assetColor(symbol),
    hasFiatValue: false,
    hasChangePercent: false,
  );
}

HoppaActivity _activityFromTransaction(LedgerTransaction transaction) {
  final displayAmount = cardListAmount(transaction);
  final secondaryAmount = transaction.secondarySettlementAmount;
  return HoppaActivity(
    id: transaction.id,
    title: transactionDisplayTitle(transaction.title),
    subtitle: transaction.displayType,
    amount: displayAmount.minorUnits / 100,
    currency: displayAmount.currency,
    kind: switch (transaction.type) {
      TransactionType.card => HoppaActivityKind.card,
      TransactionType.transfer => HoppaActivityKind.transfer,
      TransactionType.topUp => HoppaActivityKind.deposit,
      TransactionType.payment => HoppaActivityKind.account,
      TransactionType.fee => HoppaActivityKind.account,
    },
    timeLabel: transaction.hasBookedAt
        ? _timeLabel(transaction.bookedAt)
        : 'Date unavailable',
    statusLabel: transactionDisplayStatus(
      transaction.status.isEmpty ? transaction.subtitle : transaction.status,
    ),
    secondaryAmount:
        secondaryAmount == null ? null : secondaryAmount.minorUnits / 100,
    secondaryCurrency: secondaryAmount?.currency ?? '',
    merchantLogoUrl: transaction.merchantLogoUrl,
    bookedAt: transaction.hasBookedAt ? transaction.bookedAt : null,
    transaction: transaction,
  );
}

double _onboardingProgress(
  List<OnboardingTask> tasks, {
  required bool accountReady,
}) {
  if (accountReady) {
    return 1;
  }
  if (tasks.isEmpty) {
    return 0;
  }

  return tasks.where((task) => task.isComplete).length / tasks.length;
}

String _timeLabel(DateTime bookedAt) =>
    DateFormat('d MMM yyyy · HH:mm').format(bookedAt.toLocal());

String? _assetCode(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'asset',
    'Asset',
    'assetCode',
    'AssetCode',
    'currencyCode',
    'CurrencyCode',
    'token',
    'Token',
    'tokenSymbol',
    'TokenSymbol',
    'symbol',
    'Symbol',
    'currency',
    'Currency',
  ]);
}

List<Object?>? _listValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value;
    }
  }

  return null;
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return null;
}

double? _doubleValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _doubleFromAny(json[key]);
    if (value != null) {
      return value;
    }
  }

  return null;
}

double? _doubleFromAny(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }
  if (value is Map<String, dynamic>) {
    final minorUnits = value['minorUnits'] ?? value['MinorUnits'];
    if (minorUnits != null) {
      final parsed = _doubleFromAny(minorUnits);
      return parsed == null ? null : parsed / 100;
    }

    return _doubleValue(value, const ['amount', 'Amount', 'value', 'Value']);
  }

  return null;
}

Color _assetColor(String symbol) {
  final colors = [
    Colors.blue,
    Colors.teal,
    Colors.indigo,
    Colors.green,
    Colors.deepOrange,
    Colors.purple,
  ];
  return colors[symbol.hashCode.abs() % colors.length];
}
