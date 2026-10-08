import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../wallets/domain/receiving_account_details.dart';
import 'transaction_scope.dart';

/// Resolves the ledger's real account/card reference against API resources.
/// A shared currency, merchant name, or last four digits never identify a row.
String? transactionIdentityLabel(
  LedgerTransaction transaction, {
  Iterable<PaymentCard> cards = const [],
  Iterable<AccountBalance> accounts = const [],
  Iterable<PlatformResource> budgets = const [],
  Iterable<PlatformResource> bankingInfo = const [],
  String cardId = '',
}) {
  final resolvedCardId = cardId.trim().isNotEmpty ? cardId : transaction.cardId;
  if (resolvedCardId.trim().isNotEmpty) {
    final cardLabel = transactionCardIdentityLabel(resolvedCardId, cards);
    if (cardLabel != null) return cardLabel;
  }
  final rawType = transaction.rawType.trim().toLowerCase();
  final cardContext = resolvedCardId.trim().isNotEmpty ||
      rawType.startsWith('card_') ||
      (rawType.isEmpty && transaction.type == TransactionType.card);
  final cardNumber = cardContext
      ? _uniqueMetadataValue(
          transaction.metadata,
          _cardNumberKeys,
          excludedContainers: _counterpartyContainers,
        )
      : null;
  final maskedCard = maskTransactionCardNumber(cardNumber ?? '');
  if (maskedCard != null) return 'Card $maskedCard';

  final matchingBudgets = _matchingBudgets(transaction, budgets);
  if (matchingBudgets.length == 1) {
    final receiving = receivingAccountForBudget(
      matchingBudgets.single,
      receivingAccountsFromResources(bankingInfo.toList()),
      // Currency only disambiguates receiving details after an exact budget
      // match. It never chooses which account owns the transaction.
      currency: transaction.displayAmount.currency,
    );
    if (receiving != null && receiving.maskedIdentifier.isNotEmpty) {
      return 'Account ${receiving.maskedIdentifier}';
    }
  }

  final budgetIds = _transactionBudgetIds(transaction);
  final directIds = budgetIds.isNotEmpty
      ? budgetIds
      : [transaction.accountId, transaction.walletId]
          .map(_normalizeId)
          .where((id) => id.isNotEmpty)
          .toSet();
  final directMatches = accounts
      .where((account) => directIds.contains(_normalizeId(account.id)))
      .toList();
  final matches = directMatches.isNotEmpty
      ? directMatches
      : budgetIds.isNotEmpty
          ? const <AccountBalance>[]
          : accounts
              .where((account) =>
                  transactionMatchesScope(transaction, [account.id]))
              .toList();
  final matchingIds =
      matches.map((account) => _normalizeId(account.id)).toSet();
  if (matchingIds.length == 1) {
    final account = matches.first;
    final identifier = maskTransactionAccountIdentifier(account.iban) ??
        maskTransactionAccountIdentifier(account.accountNumber);
    if (identifier != null) return 'Account $identifier';
  }

  // These keys explicitly describe the ledger/source account. Generic IBAN,
  // beneficiary and destination fields may belong to somebody else.
  final sourceIdentifier =
      _uniqueMetadataValue(transaction.metadata, _sourceAccountNumberKeys);
  final maskedAccount =
      maskTransactionAccountIdentifier(sourceIdentifier ?? '');
  return maskedAccount == null ? null : 'Account $maskedAccount';
}

String? transactionCardIdentityLabel(
    String cardId, Iterable<PaymentCard> cards) {
  final id = _normalizeId(cardId);
  if (id.isEmpty) return null;
  for (final card in cards) {
    if (_normalizeId(card.id) != id) continue;
    final number = maskTransactionCardNumber(card.last4);
    return number == null ? null : 'Card $number';
  }
  return null;
}

/// Whether an account roster can resolve this transaction; avoids unrelated
/// API requests for transactions without any account identity.
bool transactionHasAccountReference(LedgerTransaction transaction) =>
    [transaction.accountId, transaction.walletId, transaction.budgetId]
        .any((id) => id.trim().isNotEmpty) ||
    _metadataValues(transaction.metadata, _accountReferenceKeys).isNotEmpty;

bool transactionHasMatchingBudget(
  LedgerTransaction transaction,
  Iterable<PlatformResource> budgets,
) =>
    _matchingBudgets(transaction, budgets).length == 1;

bool transactionHasBudgetReference(LedgerTransaction transaction) =>
    _transactionBudgetIds(transaction).isNotEmpty;

List<PlatformResource> _matchingBudgets(
  LedgerTransaction transaction,
  Iterable<PlatformResource> budgets,
) {
  final explicitBudgetIds = _transactionBudgetIds(transaction);
  final matches = <String, PlatformResource>{};
  for (final budget in budgets) {
    // PlatformResource.id can be synthesized from a currency or title. Only
    // identity fields on the real budget response establish a relationship.
    final id = _budgetResourceId(budget);
    if (id == null) continue;
    final matchesIdentity = explicitBudgetIds.isNotEmpty
        ? explicitBudgetIds.contains(id)
        : transactionMatchesScope(transaction, [id]);
    if (matchesIdentity) matches[id] = budget;
  }
  return matches.values.toList();
}

Set<String> _transactionBudgetIds(LedgerTransaction transaction) => {
      if (transaction.budgetId.trim().isNotEmpty)
        _normalizeId(transaction.budgetId),
      ..._metadataValues(transaction.metadata, _budgetReferenceKeys)
          .map(_normalizeId),
    };

String? _budgetResourceId(PlatformResource budget) {
  for (final key in const ['budgetid', 'id']) {
    for (final entry in budget.metadata.entries) {
      if (_normalizeKey(entry.key) != key) continue;
      final value = entry.value;
      if (value is! String && value is! num) continue;
      final id = _normalizeId(value.toString());
      if (id.isNotEmpty) return id;
    }
  }
  return null;
}

String? maskTransactionCardNumber(String value) {
  final compact = value.replaceAll(RegExp(r'[\s-]'), '');
  final tail = RegExp(r'(\d{4})$').firstMatch(compact)?.group(1);
  return tail == null ? null : '•••• $tail';
}

String? maskTransactionAccountIdentifier(String value) {
  final compact = value.trim().replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (compact.isEmpty ||
      const {'UNKNOWN', 'NULL', 'NONE', 'UNAVAILABLE'}.contains(compact)) {
    return null;
  }
  final tail = RegExp(r'([A-Z0-9]{4})$').firstMatch(compact)?.group(1);
  if (tail == null) return null;
  final country = RegExp(r'^[A-Z]{2}(?:\d{2}|[•*…])').hasMatch(compact)
      ? compact.substring(0, 2)
      : '';
  return '$country***$tail';
}

/// Masks structured identity metadata in receipts as well as the dedicated
/// account/card fact. Unknown identity values are omitted, not fabricated.
String? transactionMetadataDisplayValue(String key, Object value) {
  final normalized = _normalizeKey(key);
  final display = value.toString().trim();
  if (display.isEmpty) return null;
  if (_cardNumberKeys.contains(normalized) ||
      normalized == 'pan' ||
      normalized == 'maskedpan') {
    return maskTransactionCardNumber(display);
  }
  if (normalized.contains('iban') ||
      normalized.endsWith('accountnumber') ||
      normalized.endsWith('accountidentifier')) {
    return maskTransactionAccountIdentifier(display);
  }
  return display;
}

const _cardNumberKeys = {
  'cardlast4',
  'cardlastfour',
  'cardnumberlastfour',
  'cardnumberlast4',
  'maskedcardnumber',
  'cardnumber',
};

const _counterpartyContainers = {
  'recipient',
  'recipients',
  'beneficiary',
  'beneficiaries',
  'counterparty',
  'counterparties',
  'destination',
  'destinationcard',
  'payee',
  'payees',
};

const _sourceAccountNumberKeys = {
  'accountiban',
  'sourceiban',
  'sourceaccountiban',
  'fromiban',
  'fromaccountiban',
  'sourceaccountnumber',
  'fromaccountnumber',
};

const _accountReferenceKeys = {
  'accountid',
  'budgetid',
  'walletid',
  'sourceaccountid',
  'sourcebudgetid',
  'sourcewalletid',
  'destinationaccountid',
  'destinationbudgetid',
  'destinationwalletid',
  'fromaccountid',
  'frombudgetid',
  'toaccountid',
  'tobudgetid',
};

const _budgetReferenceKeys = {
  'budgetid',
  'sourcebudgetid',
  'destinationbudgetid',
  'frombudgetid',
  'tobudgetid',
};

String? _uniqueMetadataValue(
  Object? metadata,
  Set<String> keys, {
  Set<String> excludedContainers = const {},
}) {
  final values =
      _metadataValues(metadata, keys, excludedContainers: excludedContainers);
  return values.length == 1 ? values.single : null;
}

Set<String> _metadataValues(
  Object? metadata,
  Set<String> keys, {
  Set<String> excludedContainers = const {},
}) {
  final values = <String>{};
  void visit(Object? value) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = _normalizeKey(entry.key.toString());
        if (excludedContainers.contains(key)) continue;
        final nested = entry.value;
        if (keys.contains(key) &&
            nested != null &&
            nested is! Map &&
            nested is! Iterable) {
          final text = nested.toString().trim();
          if (text.isNotEmpty) values.add(text);
        }
        visit(nested);
      }
    } else if (value is Iterable) {
      for (final item in value) {
        visit(item);
      }
    }
  }

  visit(metadata);
  return values;
}

String _normalizeKey(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();

String _normalizeId(String value) => value.trim().toLowerCase();
