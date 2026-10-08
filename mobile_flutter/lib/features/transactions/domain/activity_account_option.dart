import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../wallets/domain/receiving_account_details.dart';
import 'transaction_identity.dart';
import 'transaction_scope.dart';

/// A display selection backed by an account or budget returned by the API.
/// [key] is a UI key, never an ID to send to an account transaction endpoint.
class ActivityAccountOption {
  ActivityAccountOption({
    required this.key,
    required this.label,
    required Iterable<String> scopeIds,
    this.currency = '',
    this.maskedIdentifier = '',
  }) : scopeIds = Set.unmodifiable(scopeIds);

  final String key;
  final String label;
  final Set<String> scopeIds;
  final String currency;
  final String maskedIdentifier;

  bool matches(LedgerTransaction transaction) =>
      transactionMatchesScope(transaction, scopeIds) &&
      (currency.isEmpty ||
          transaction.displayAmount.currency.trim().toUpperCase() == currency);
}

/// Account choices come from rosters, including accounts with no history or
/// zero balances. Currency can narrow an exact account; it never identifies one.
List<ActivityAccountOption> buildActivityAccountOptions({
  Iterable<AccountBalance> accounts = const [],
  Iterable<PlatformResource> budgets = const [],
  Iterable<PlatformResource> bankingInfo = const [],
}) {
  final sources = <String, _AccountSource>{};
  final receiving = receivingAccountsFromResources(bankingInfo.toList());

  // The budget endpoint is the authoritative roster of allocated currencies.
  // Supported currencies on a unified account are capabilities, not accounts.
  for (final budget in budgets) {
    final id = _text(budget.metadata, ['budgetId', 'id']);
    if (id == null) continue;
    final source = sources.putIfAbsent('budget:${id.toLowerCase()}',
        () => _AccountSource(id, 'budget', budget.title, 'Equals Money'));
    source.currencies.addAll(_budgetCurrencies(budget.metadata));
    source.budgets.add(budget);
  }

  for (final account in accounts) {
    final explicitBudget = account.budgetId.trim();
    final isBudget = explicitBudget.isNotEmpty ||
        account.accountType.trim().toUpperCase() == 'BUDGET';
    final id = explicitBudget.isNotEmpty ? explicitBudget : account.id.trim();
    if (id.isEmpty) continue;
    final kind = isBudget ? 'budget' : 'account';
    final source = sources.putIfAbsent('$kind:${id.toLowerCase()}',
        () => _AccountSource(id, kind, account.name, account.provider));
    if (_genericName(source.name) && !_genericName(account.name)) {
      source.name = account.name;
    }
    if (source.provider.isEmpty) source.provider = account.provider;
    source.accounts.add(account);
    final knownCurrencies = <String>{
      ...account.currencyBalances.map((value) => value.currency),
      ...account.linkedBankAccounts.map((value) => value.currency),
    }.map(_currency).where((value) => value.isNotEmpty).toSet();
    if (knownCurrencies.isEmpty && account.hasBalanceCurrency) {
      final balanceCurrency = _currency(account.balance.currency);
      if (balanceCurrency.isNotEmpty) knownCurrencies.add(balanceCurrency);
    }
    // Budget balances are filtered to allocated currencies by the budget API;
    // the aggregate banking balance API can also return inactive currencies.
    if (source.budgets.isEmpty || source.currencies.isEmpty) {
      source.currencies.addAll(knownCurrencies);
    }
  }

  final choices = <ActivityAccountOption>[];
  final choiceSources = <String, _AccountSource>{};
  for (final source in sources.values) {
    final currencies = source.currencies.toList()..sort();
    for (final currency in currencies.isEmpty ? [''] : currencies) {
      final identifiers = <String>{
        for (final budget in source.budgets)
          if (receivingAccountForBudget(budget, receiving, currency: currency)
              case final ReceivingAccountDetails details)
            details.maskedIdentifier,
        for (final account in source.accounts)
          ..._accountIdentifiers(account, currency),
      }..remove('');
      final identifier = identifiers.length == 1 ? identifiers.single : '';
      final key = '${source.kind}:${source.id.toLowerCase()}:$currency';
      choices.add(ActivityAccountOption(
        key: key,
        label: _label(source.name, currency, identifier),
        scopeIds: [source.id],
        currency: currency,
        maskedIdentifier: identifier,
      ));
      choiceSources[key] = source;
    }
  }

  // Two real accounts can share a currency and a name. Keep both and expose
  // an explicitly labelled API reference if bank identifiers are unavailable.
  final labelCounts = <String, int>{};
  for (final choice in choices) {
    labelCounts.update(choice.label, (count) => count + 1, ifAbsent: () => 1);
  }
  final result = choices.map((choice) {
    if (labelCounts[choice.label] == 1) return choice;
    final source = choiceSources[choice.key]!;
    var suffixLength = 8;
    while (suffixLength < source.id.length &&
        choices.any((other) {
          if (other.key == choice.key || other.label != choice.label) {
            return false;
          }
          final otherId = choiceSources[other.key]!.id.toLowerCase();
          return otherId.endsWith(source.id
              .substring(source.id.length - suffixLength)
              .toLowerCase());
        })) {
      suffixLength++;
    }
    final reference = source.id.length <= suffixLength
        ? source.id
        : '…${source.id.substring(source.id.length - suffixLength)}';
    return ActivityAccountOption(
      key: choice.key,
      label: [
        choice.label,
        if (source.provider.isNotEmpty) _providerLabel(source.provider),
        'Ref $reference',
      ].join(' · '),
      scopeIds: choice.scopeIds,
      currency: choice.currency,
      maskedIdentifier: choice.maskedIdentifier,
    );
  }).toList()
    ..sort((left, right) => left.label.compareTo(right.label));
  return List.unmodifiable(result);
}

String _label(String name, String currency, String identifier) {
  final cleanedName = name
      .trim()
      .replaceAll(RegExp(r'\bMain\b', caseSensitive: false), '')
      .trim();
  final displayName = _genericName(cleanedName)
      ? (currency.isEmpty ? 'Account' : '$currency account')
      : cleanedName;
  return [
    displayName,
    if (currency.isNotEmpty &&
        displayName.toUpperCase() != currency &&
        displayName != '$currency account')
      currency,
    if (identifier.isNotEmpty) identifier,
  ].join(' · ');
}

class _AccountSource {
  _AccountSource(this.id, this.kind, this.name, this.provider);
  final String id;
  final String kind;
  String name;
  String provider;
  final Set<String> currencies = {};
  final List<AccountBalance> accounts = [];
  final List<PlatformResource> budgets = [];
}

Iterable<String> _accountIdentifiers(AccountBalance account, String currency) {
  if (account.linkedBankAccounts.isNotEmpty) {
    return account.linkedBankAccounts
        .where((bank) => _currency(bank.currency) == currency)
        .map((bank) =>
            maskTransactionAccountIdentifier(bank.iban) ??
            maskTransactionAccountIdentifier(bank.accountNumber))
        .whereType<String>();
  }
  final identifier = maskTransactionAccountIdentifier(account.iban) ??
      maskTransactionAccountIdentifier(account.accountNumber);
  return identifier == null ? const [] : [identifier];
}

bool _genericName(String name) => const {
      '',
      'main',
      'account',
      'account balance',
      'budget',
      'bank account'
    }.contains(name.trim().toLowerCase());

String _providerLabel(String provider) => switch (provider.toLowerCase()) {
      '2' || 'equalsmoney' => 'Equals Money',
      '1' || 'interlace' => 'Interlace',
      '3' || 'unifiedswitch' => 'UnifiedSwitch',
      _ => provider,
    };

Set<String> _budgetCurrencies(Map<String, dynamic> metadata) {
  final currencies = <String>{};
  void add(Object? value) {
    if (value is String && _currency(value).isNotEmpty) {
      currencies.add(_currency(value));
    }
  }

  add(_text(metadata, ['currency', 'currencyCode']));
  for (final key in ['currencies']) {
    final values = _value(metadata, key);
    if (values is Iterable) {
      for (final value in values) {
        if (value is Map) {
          add(_text(_map(value), ['currency', 'currencyCode']));
        } else {
          add(value);
        }
      }
    }
  }
  if (currencies.isNotEmpty) return currencies;
  for (final key in [
    'balances',
    'currencyBalances',
    'supportedCurrencyBalances',
    'availableBalances',
    'linkedBankAccounts'
  ]) {
    final values = _value(metadata, key);
    if (values is Iterable) {
      for (final value in values.whereType<Map>()) {
        add(_text(_map(value), ['currency', 'currencyCode']));
      }
    }
  }
  final settlement = _value(metadata, 'settlementDetails');
  if (settlement is Map) {
    final values = _value(_map(settlement), 'currencyDetails');
    if (values is Iterable) {
      for (final value in values.whereType<Map>()) {
        add(_text(_map(value), ['currency', 'currencyCode']));
      }
    }
  }
  return currencies;
}

String _currency(String value) {
  final normalized = value.trim().toUpperCase();
  return RegExp(r'^[A-Z][A-Z0-9]{1,14}$').hasMatch(normalized) &&
          !const {'UNKNOWN', 'NULL', 'NONE', 'UNAVAILABLE'}.contains(normalized)
      ? normalized
      : '';
}

Object? _value(Map<String, dynamic> metadata, String key) {
  for (final entry in metadata.entries) {
    if (entry.key.toLowerCase() == key.toLowerCase()) return entry.value;
  }
  return null;
}

String? _text(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = _value(metadata, key);
    if (value is! String && value is! num) continue;
    if (value.toString().trim().isNotEmpty) return value.toString().trim();
  }
  return null;
}

Map<String, dynamic> _map(Map value) =>
    value.map((key, value) => MapEntry(key.toString(), value));
