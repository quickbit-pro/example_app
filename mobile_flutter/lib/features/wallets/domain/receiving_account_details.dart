import '../../../core/models/platform_models.dart';

/// Receiving details supplied by the banking API, with explicit account links.
class ReceivingAccountDetails {
  ReceivingAccountDetails({
    required this.accountNumber,
    required this.swift,
    required this.bankName,
    required this.holder,
    Iterable<String> scopeIds = const [],
    Iterable<String> currencies = const [],
  })  : scopeIds = Set.unmodifiable(scopeIds),
        currencies = Set.unmodifiable(
            currencies.map((value) => value.trim().toUpperCase())),
        _budgetIds = const {},
        _bindings = List.unmodifiable([
          _ReceivingBinding(scopeIds, const [], currencies),
        ]),
        _identifiers = Set.unmodifiable({_identifier(accountNumber)});

  ReceivingAccountDetails._({
    required this.accountNumber,
    required this.swift,
    required this.bankName,
    required this.holder,
    required Iterable<String> scopeIds,
    required Iterable<String> budgetIds,
    required Iterable<String> identifiers,
    required Iterable<String> currencies,
    Iterable<_ReceivingBinding>? bindings,
  })  : scopeIds = Set.unmodifiable(scopeIds),
        currencies = Set.unmodifiable(currencies),
        _budgetIds = Set.unmodifiable(budgetIds),
        _bindings = List.unmodifiable(bindings ??
            [
              _ReceivingBinding(scopeIds, budgetIds, currencies),
            ]),
        _identifiers = Set.unmodifiable(identifiers);

  final String accountNumber;
  final String swift;
  final String bankName;
  final String holder;
  final Set<String> scopeIds;
  final Set<String> currencies;
  final Set<String> _budgetIds;
  final Set<String> _identifiers;
  final List<_ReceivingBinding> _bindings;

  bool get isIban => _isIban(_identifier(accountNumber));

  String get maskedIdentifier {
    final number = _identifier(accountNumber);
    if (number.isEmpty) return '';
    final suffix =
        number.length <= 4 ? number : number.substring(number.length - 4);
    return '${isIban ? number.substring(0, 2) : ''}***$suffix';
  }

  String get copyAll => [
        'Fiat account details',
        '${isIban ? 'IBAN' : 'Account number'}: $accountNumber',
        if (swift.isNotEmpty) 'SWIFT/BIC: $swift',
        if (holder.isNotEmpty) 'Account holder: $holder',
        if (bankName.isNotEmpty) 'Bank: $bankName',
      ].join('\n');

  String get qrPayload => copyAll;
}

/// Preserves routing details across currency/payment-method duplicate rows.
List<ReceivingAccountDetails> receivingAccountsFromResources(
  List<PlatformResource> resources,
) =>
    _mergeAccounts(
        resources.expand((resource) => _accountsIn(resource.metadata)));

List<ReceivingAccountDetails> _mergeAccounts(
  Iterable<ReceivingAccountDetails> details,
) {
  final accounts = <ReceivingAccountDetails>[];
  for (final account in details) {
    final matches = <int>[
      for (var index = 0; index < accounts.length; index++)
        if (_identifier(accounts[index].accountNumber) ==
                _identifier(account.accountNumber) &&
            _compatibleBank(accounts[index], account) &&
            _compatibleLocalScope(accounts[index], account))
          index,
    ];
    if (matches.length == 1) {
      final index = matches.single;
      accounts[index] = _mergeDetails(accounts[index], account);
    } else {
      // A local number is not globally unique across banks. Incomplete routing
      // details also cannot choose between multiple conflicting bank records.
      accounts.add(account);
    }
  }
  return List.unmodifiable(accounts);
}

bool _compatibleLocalScope(
    ReceivingAccountDetails first, ReceivingAccountDetails second) {
  if (first.isIban && second.isIban) return true;
  final firstIds =
      (first._budgetIds.isEmpty ? first.scopeIds : first._budgetIds)
          .map(_scopeKey)
          .toSet();
  final secondIds =
      (second._budgetIds.isEmpty ? second.scopeIds : second._budgetIds)
          .map(_scopeKey)
          .toSet();
  return firstIds.length == secondIds.length &&
      firstIds.every(secondIds.contains);
}

bool _compatibleBank(
    ReceivingAccountDetails first, ReceivingAccountDetails second) {
  final firstSwift = _identifier(first.swift);
  final secondSwift = _identifier(second.swift);
  if (firstSwift.isNotEmpty && secondSwift.isNotEmpty) {
    return firstSwift == secondSwift;
  }
  final firstBank = first.bankName.trim().toLowerCase();
  final secondBank = second.bankName.trim().toLowerCase();
  return firstBank.isEmpty || secondBank.isEmpty || firstBank == secondBank;
}

ReceivingAccountDetails _mergeDetails(
  ReceivingAccountDetails primary,
  ReceivingAccountDetails secondary,
) =>
    ReceivingAccountDetails._(
      accountNumber: primary.accountNumber,
      swift: primary.swift.isEmpty ? secondary.swift : primary.swift,
      bankName:
          primary.bankName.isEmpty ? secondary.bankName : primary.bankName,
      holder: primary.holder.isEmpty ? secondary.holder : primary.holder,
      scopeIds: {...primary.scopeIds, ...secondary.scopeIds},
      budgetIds: {...primary._budgetIds, ...secondary._budgetIds},
      identifiers: {...primary._identifiers, ...secondary._identifiers},
      currencies: {...primary.currencies, ...secondary.currencies},
      bindings: [...primary._bindings, ...secondary._bindings],
    );

class _ReceivingBinding {
  _ReceivingBinding(
    Iterable<String> scopeIds,
    Iterable<String> budgetIds,
    Iterable<String> currencies,
  )   : scopeIds = Set.unmodifiable(scopeIds.map(_scopeKey)),
        budgetIds = Set.unmodifiable(budgetIds.map(_scopeKey)),
        currencies = Set.unmodifiable(
            currencies.map((value) => value.trim().toUpperCase()));

  final Set<String> scopeIds;
  final Set<String> budgetIds;
  final Set<String> currencies;
}

/// Returns only an unambiguous identity or explicit scope match.
///
/// User ID, currency, display name, list position, and a sole returned account
/// do not establish that a receiving account belongs to the selected budget.
ReceivingAccountDetails? receivingAccountForBudget(
  PlatformResource budget,
  List<ReceivingAccountDetails> accounts, {
  String? currency,
}) {
  final scopeIds = _scopeIds(budget.metadata);
  final budgetIds = _budgetIds(budget.metadata);
  // A budget's structured ID is reliable; PlatformResource.id can instead be
  // synthesized from a title or currency by PlatformResource.fromJson.
  final explicitId = _text(budget.metadata, const ['id']);
  if (explicitId != null) {
    scopeIds.add(explicitId);
    budgetIds.add(explicitId);
  }
  final embeddedDetails = _accountsIn(
    budget.metadata,
    inheritedScopes: scopeIds,
    inheritedBudgets: budgetIds,
  ).toList();
  final selectedCurrency = currency?.trim().toUpperCase();
  bool acceptsCurrency(ReceivingAccountDetails account) =>
      selectedCurrency == null ||
      selectedCurrency.isEmpty ||
      account.currencies.isEmpty ||
      account.currencies.contains(selectedCurrency);
  bool sameIdentity(
          ReceivingAccountDetails first, ReceivingAccountDetails second) =>
      first._identifiers.any(second._identifiers.contains) &&
      _compatibleBank(first, second) &&
      ((first.isIban &&
              second.isIban &&
              first.accountNumber == second.accountNumber) ||
          (first.swift.isNotEmpty &&
              second.swift.isNotEmpty &&
              _identifier(first.swift) == _identifier(second.swift)) ||
          (first.bankName.isNotEmpty &&
              second.bankName.isNotEmpty &&
              first.bankName.trim().toLowerCase() ==
                  second.bankName.trim().toLowerCase()) ||
          first._budgetIds.any(second._budgetIds.contains));
  final enrichedDetails = embeddedDetails.map((embedded) {
    final matches =
        accounts.where((account) => sameIdentity(embedded, account)).toList();
    return matches.length == 1
        ? _mergeDetails(embedded, matches.single)
        : embedded;
  });
  final authoritative =
      _mergeAccounts(enrichedDetails).where(acceptsCurrency).toList();
  if (authoritative.isNotEmpty) {
    return authoritative.length == 1 ? authoritative.single : null;
  }
  final candidates = _mergeAccounts([
    ...accounts.where((account) =>
        !embeddedDetails.any((embedded) => sameIdentity(embedded, account))),
  ]).where(acceptsCurrency).toList();
  final normalizedBudgets = budgetIds.map(_scopeKey).toSet();
  // Equals budget accountId names its shared owner, not that specific budget.
  final normalizedScopes =
      (budgetIds.isEmpty ? scopeIds : budgetIds).map(_scopeKey).toSet();
  final matches = candidates
      .where((account) => account._bindings.any((binding) {
            if (selectedCurrency != null &&
                selectedCurrency.isNotEmpty &&
                binding.currencies.isNotEmpty &&
                !binding.currencies.contains(selectedCurrency)) {
              return false;
            }
            if (binding.budgetIds.isNotEmpty &&
                !binding.budgetIds.any(normalizedBudgets.contains)) {
              return false;
            }
            return binding.scopeIds.any(normalizedScopes.contains);
          }))
      .toList();
  if (matches.length == 1) return matches.single;
  // Equals can return the shared IBAN under EUR only, even when this same
  // account holds RON as well. Prefer exact currency routing above; fall back
  // only to one proven account identity for a supported account currency.
  final supported = _accountCurrencies(budget.metadata);
  if (matches.isEmpty &&
      selectedCurrency != null &&
      supported.length > 1 &&
      supported.contains(selectedCurrency)) {
    final shared = receivingAccountForBudget(budget, accounts);
    if (shared?.isIban == true) return shared;
  }
  return null;
}

Set<String> _accountCurrencies(Map<String, dynamic> metadata) {
  final result = <String>{};
  for (final key in const [
    'supportedCurrencies',
    'currencies',
    'balances',
    'currencyBalances'
  ]) {
    final values = _value(metadata, key);
    if (values is! List) continue;
    for (final value in values) {
      final entry = _map(value);
      final code = entry == null
          ? (value is String ? value : null)
          : _text(entry, const ['currency', 'currencyCode', 'code']);
      if (code != null && code.trim().isNotEmpty) {
        result.add(code.trim().toUpperCase());
      }
    }
  }
  for (final key in const ['data', 'result', 'account']) {
    final nested = _map(_value(metadata, key));
    if (nested != null) result.addAll(_accountCurrencies(nested));
  }
  return result;
}

Iterable<ReceivingAccountDetails> _accountsIn(
  Map<String, dynamic> metadata, {
  Set<String> inheritedScopes = const {},
  Set<String> inheritedBudgets = const {},
  String inheritedHolder = '',
  String inheritedBankName = '',
  Set<String> inheritedCurrencies = const {},
}) sync* {
  final scopes = {...inheritedScopes, ..._scopeIds(metadata)};
  final budgets = {...inheritedBudgets, ..._budgetIds(metadata)};
  final holder = _text(metadata, const [
        'userName',
        'accountHolderName',
        'accountHolder',
        'holderName',
        'payeeName',
      ]) ??
      inheritedHolder;
  final bankName = _text(metadata, const ['bankName']) ?? inheritedBankName;
  final currency = _text(metadata, const ['currency', 'currencyCode']);
  final currencies =
      currency == null ? inheritedCurrencies : {currency.toUpperCase()};
  final routing = _routingValues(metadata);
  final iban = routing['iban'] ?? _text(metadata, const ['iban']);
  final number =
      iban ?? _text(metadata, const ['accountNumber', 'accountIdentifier']);
  if (number != null && number.trim().isNotEmpty) {
    final accountNumber = _identifier(number);
    yield ReceivingAccountDetails._(
      accountNumber: accountNumber,
      swift: routing['swift_code'] ??
          routing['swift'] ??
          routing['bic'] ??
          _text(metadata, const ['swift', 'swiftCode', 'bic']) ??
          _swiftBankIdentifier(metadata),
      bankName: bankName,
      holder: holder,
      scopeIds: scopes,
      budgetIds: budgets,
      currencies: currencies,
      identifiers: {
        accountNumber,
        if (_text(metadata, const ['accountNumber'])
            case final String localNumber)
          _identifier(localNumber),
      },
    );
  }

  // These are observed banking-info envelopes and linked-bank collections.
  for (final key in const ['data', 'result', 'account', 'linkedBankAccounts']) {
    final value = _value(metadata, key);
    final children = value is List ? value : [value];
    for (final child in children) {
      final childMap = _map(child);
      if (childMap == null) continue;
      yield* _accountsIn(
        childMap,
        inheritedScopes: scopes,
        inheritedBudgets: budgets,
        inheritedHolder: holder,
        inheritedBankName: bankName,
        inheritedCurrencies: currencies,
      );
    }
  }

  final settlement = _map(_value(metadata, 'settlementDetails'));
  final currencyDetails =
      settlement == null ? null : _value(settlement, 'currencyDetails');
  if (currencyDetails is List) {
    for (final entry in currencyDetails) {
      final details = _map(entry);
      if (details == null) continue;
      final settlementCurrency = _text(details, const ['currencyCode']);
      final local = _map(_value(details, 'local'));
      final international = _map(_value(details, 'international'));
      final localNumber = local == null
          ? null
          : _text(local, const ['iban', 'accountNumber', 'accountIdentifier']);
      final internationalNumber = international == null
          ? null
          : _text(international,
              const ['iban', 'accountNumber', 'accountIdentifier']);
      // Prefer the IBAN supplied for this currency. Picking GBP's domestic
      // number first also creates false ambiguity when other currency rows
      // describe this same account using its international IBAN.
      final bank = localNumber != null && _isIban(_identifier(localNumber))
          ? local
          : internationalNumber != null &&
                  _isIban(_identifier(internationalNumber))
              ? international
              : localNumber != null
                  ? local
                  : international;
      if (bank == null) continue;
      yield* _accountsIn(
        bank,
        inheritedScopes: scopes,
        inheritedBudgets: budgets,
        inheritedHolder: holder,
        inheritedBankName: bankName,
        inheritedCurrencies: settlementCurrency == null
            ? currencies
            : {settlementCurrency.toUpperCase()},
      );
    }
  }
}

String _swiftBankIdentifier(Map<String, dynamic> metadata) {
  final bankIdentifier =
      _text(metadata, const ['bankIdentifier'])?.toUpperCase();
  return bankIdentifier != null &&
          RegExp(r'^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$')
              .hasMatch(bankIdentifier)
      ? bankIdentifier
      : '';
}

Set<String> _scopeIds(Map<String, dynamic> metadata) {
  final scopes = <String>{};
  for (final key in const [
    'budgetId',
    'accountId',
    'parentAccountId',
    'walletId'
  ]) {
    final value = _text(metadata, [key]);
    if (value != null) scopes.add(value);
  }
  for (final key in const ['budget', 'account', 'wallet']) {
    final nested = _map(_value(metadata, key));
    if (nested == null) continue;
    final id = _text(nested, const ['id']);
    if (id != null) scopes.add(id);
    scopes.addAll(_scopeIds(nested));
  }
  for (final key in const ['data', 'result']) {
    final nested = _map(_value(metadata, key));
    if (nested != null) scopes.addAll(_scopeIds(nested));
  }
  return scopes;
}

Set<String> _budgetIds(Map<String, dynamic> metadata) {
  final ids = <String>{};
  final id = _text(metadata, const ['budgetId']);
  if (id != null) ids.add(id);
  final nestedBudget = _map(_value(metadata, 'budget'));
  if (nestedBudget != null) {
    final nestedId = _text(nestedBudget, const ['id', 'budgetId']);
    if (nestedId != null) ids.add(nestedId);
  }
  for (final key in const ['data', 'result', 'account']) {
    final nested = _map(_value(metadata, key));
    if (nested != null) ids.addAll(_budgetIds(nested));
  }
  return ids;
}

Map<String, String> _routingValues(Map<String, dynamic> metadata) {
  final codes = _value(metadata, 'routingCodes');
  if (codes is! List) return const {};
  final values = <String, String>{};
  for (final code in codes) {
    final map = _map(code);
    if (map == null) continue;
    final type = _text(map, const ['routingCodeType', 'type']);
    final value = _text(map, const ['routingCodeValue', 'value']);
    if (type == null || value == null) continue;
    values.putIfAbsent(type.toLowerCase().replaceAll('-', '_'), () => value);
  }
  return values;
}

String _identifier(String value) =>
    value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
String _scopeKey(String value) => value.trim().toLowerCase();
bool _isIban(String value) =>
    RegExp(r'^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$').hasMatch(value);

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
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

Map<String, dynamic>? _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : null;
