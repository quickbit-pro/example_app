import '../../../core/models/banking_models.dart';

bool transactionMatchesScope(
  LedgerTransaction transaction,
  Iterable<String> scopeIds,
) {
  final normalizedScope =
      scopeIds.map(_normalize).where((value) => value.isNotEmpty).toSet();
  if (normalizedScope.isEmpty) return false;

  final transactionIds = <String>{
    _normalize(transaction.accountId),
    _normalize(transaction.walletId),
    _normalize(transaction.budgetId),
  }..remove('');
  _collectScopeIds(transaction.metadata, transactionIds);

  return transactionIds.any(normalizedScope.contains);
}

const _scopeKeys = {
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

void _collectScopeIds(Object? value, Set<String> result) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key
          .toString()
          .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
          .toLowerCase();
      if (_scopeKeys.contains(key)) {
        final id = _normalize(entry.value?.toString() ?? '');
        if (id.isNotEmpty) result.add(id);
      }
      _collectScopeIds(entry.value, result);
    }
  } else if (value is Iterable) {
    for (final item in value) {
      _collectScopeIds(item, result);
    }
  }
}

String _normalize(String value) => value.trim().toLowerCase();
