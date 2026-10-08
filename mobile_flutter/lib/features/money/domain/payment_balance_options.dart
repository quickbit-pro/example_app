import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';

List<AccountBalance> paymentAccountsWithBudgets(
  Iterable<AccountBalance> accounts,
  Iterable<PlatformResource> budgets,
) {
  final merged = <String, AccountBalance>{};

  void add(AccountBalance account) {
    final key = account.id.trim().isEmpty
        ? account.name.trim().toLowerCase()
        : account.id.trim();
    final existing = merged[key];
    if (existing == null ||
        fundedBalances(account).fold<int>(
              0,
              (total, balance) => total + balance.minorUnits,
            ) >
            fundedBalances(existing).fold<int>(
              0,
              (total, balance) => total + balance.minorUnits,
            )) {
      merged[key] = account;
    }
  }

  for (final budget in budgets) {
    final json = <String, dynamic>{...budget.metadata};
    json.putIfAbsent('id', () => budget.id);
    json.putIfAbsent('name', () => budget.title);
    add(AccountBalance.fromJson(json));
  }
  for (final account in accounts) {
    add(account);
  }

  return merged.values.toList();
}

List<Money> fundedBalances(AccountBalance account) {
  final balances = <String, Money>{};
  final candidates = <Money>[
    ...account.currencyBalances,
    account.available,
    account.balance,
  ];

  for (final balance in candidates) {
    final currency = balance.currency.trim().toUpperCase();
    if (currency.isEmpty || balance.minorUnits <= 0) continue;
    balances.putIfAbsent(
      currency,
      () => Money(currency: currency, minorUnits: balance.minorUnits),
    );
  }

  final result = balances.values.toList()
    ..sort((left, right) => left.currency.compareTo(right.currency));
  return result;
}

bool hasFundedBalance(AccountBalance account) =>
    fundedBalances(account).isNotEmpty;

List<String> fundedCurrencyOptions(
  AccountBalance account, {
  String? preferredCurrency,
}) {
  final options =
      fundedBalances(account).map((balance) => balance.currency).toList();
  final preferred = preferredCurrency?.trim().toUpperCase();
  if (preferred != null && options.remove(preferred)) {
    options.insert(0, preferred);
  }
  return options;
}

String paymentAccountOptionLabel(AccountBalance account) {
  return account.name.trim().isEmpty ? 'Account' : account.name.trim();
}
