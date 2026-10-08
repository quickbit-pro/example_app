import 'banking_models.dart';

/// Hoppa may return both a card fee and its database ledger counterpart as
/// primary rows. Collapse only an unambiguous, successful debit pair sharing
/// the provider ID, currency and exact parsed amount. Never match by title/date.
List<LedgerTransaction> deduplicateCardFees(List<LedgerTransaction> rows) {
  final cards = <String, List<int>>{};
  final fees = <String, List<int>>{};
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  for (var i = 0; i < rows.length; i++) {
    final row = rows[i];
    if (!row.amount.isNegative ||
        !const {'success', 'completed', 'settled'}
            .contains(normalize(row.status))) {
      continue;
    }
    final fields = {
      for (final e in row.metadata.entries) normalize(e.key): e.value,
    };
    final externalId = fields['externaltransactionid']?.toString().trim() ?? '';
    if (externalId.isEmpty) continue;
    final type = normalize(row.rawType);
    final source = normalize(fields['source']?.toString() ?? '');
    final isCard =
        type == 'cardfee' && source == 'cardfee' && row.cardId.isNotEmpty;
    final isFee = type == 'fees' && source == 'database' && row.cardId.isEmpty;
    if (!isCard && !isFee) continue;
    final key =
        '$externalId|${row.amount.currency.toUpperCase()}|${row.amount.decimalAmount}';
    (isCard ? cards : fees).putIfAbsent(key, () => []).add(i);
  }
  final omit = <int>{};
  for (final entry in cards.entries) {
    final matching = fees[entry.key];
    if (entry.value.length == 1 && matching?.length == 1) {
      omit.add(matching!.single);
    }
  }
  return [
    for (var i = 0; i < rows.length; i++)
      if (!omit.contains(i)) rows[i]
  ];
}
