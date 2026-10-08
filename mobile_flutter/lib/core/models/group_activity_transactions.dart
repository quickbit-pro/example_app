import 'banking_models.dart';
import 'group_card_fees.dart';

/// A presentation group. Its amount comes from [primary], never from summing
/// ledger legs (which can describe the same money in different currencies).
class ActivityTransactionGroup {
  ActivityTransactionGroup(this.primary, List<LedgerTransaction> entries)
      : entries = List.unmodifiable(entries);

  final LedgerTransaction primary;
  final List<LedgerTransaction> entries;
}

String _key(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Joins explicit operation references after applying existing duplicate/fee
/// rules. Work on the already scoped/filtered rows so expansion cannot expose
/// another account's entries. Missing links remain separate; equal amounts or
/// nearby timestamps alone are not evidence of a shared operation. Legacy
/// provider shapes below require matching operation metadata as well.
List<ActivityTransactionGroup> groupActivityTransactions(
    List<LedgerTransaction> rows) {
  if (rows.isEmpty) return [];
  final fields = [
    for (final row in rows)
      {for (final field in row.metadata.entries) _key(field.key): field.value}
  ];
  String value(int i, String key) => fields[i][key]?.toString().trim() ?? '';
  String budget(int i) =>
      rows[i].budgetId.isNotEmpty ? rows[i].budgetId : value(i, 'budgetid');
  final parents = List.generate(rows.length, (i) => i);
  int root(int i) {
    while (parents[i] != i) {
      parents[i] = parents[parents[i]];
      i = parents[i];
    }
    return i;
  }

  void join(int a, int b) {
    parents[root(b)] = root(a);
  }

  final byId = <String, List<int>>{};
  final byObject = <LedgerTransaction, int>{};
  final byGroup = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    byObject[rows[i]] = i;
    if (rows[i].id.isNotEmpty) {
      byId.putIfAbsent(rows[i].id, () => []).add(i);
    }
    final group = value(i, 'transactiongroupid');
    if (group.isNotEmpty) join(byGroup.putIfAbsent(group, () => i), i);
  }
  for (var i = 0; i < rows.length; i++) {
    final parent = byId[value(i, 'parenttransactionid')];
    if (parent?.length == 1) join(parent!.single, i);
  }
  for (final group in ledgerDuplicateGroups(rows)) {
    for (final member in group.skip(1)) {
      join(byObject[group.first]!, byObject[member]!);
    }
  }

  final displayed = groupCardFees(rows);
  for (final row in displayed) {
    final parent = byId[row.id];
    if (parent?.length != 1) continue;
    for (final fee in row.cardFees) {
      final child = byId[fee.id];
      if (child?.length == 1) join(parent!.single, child!.single);
    }
  }

  // Interlace can surface the same card funding operation on both its card
  // and wallet feeds. Prefer an exact provider/client reference here;
  // never treat a reusable card/account id as a transaction reference.
  final funding = <String, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    final type = _key(rows[i].rawType);
    if (!const {'cardtopup', 'cardunload', 'walletcredit', 'walletdebit'}
        .contains(type)) {
      continue;
    }
    for (final field in ['externaltransactionid', 'clienttransactionid']) {
      final ref = value(i, field);
      if (ref.isNotEmpty) {
        funding.putIfAbsent('$field:$ref', () => []).add(i);
      }
    }
  }
  for (final matches in funding.values) {
    final cards = matches.where((i) =>
        const {'cardtopup', 'cardunload'}.contains(_key(rows[i].rawType)));
    final wallets = matches.where((i) =>
        const {'walletcredit', 'walletdebit'}.contains(_key(rows[i].rawType)));
    if (cards.length == 1 && wallets.length == 1) {
      final card = cards.single, wallet = wallets.single;
      if (rows[wallet].cardId.isEmpty ||
          rows[wallet].cardId == rows[card].cardId) {
        join(card, wallet);
      }
    }
  }

  // Older Interlace wallet events retain only provider type 3 (card
  // transfer-out). Historical paired bookings differ by one millisecond.
  // Require the specific event type, matching amount/currency/status and a
  // mutually unique pair within one second; ordinary wallet debits never join.
  bool near(int a, int b, Duration window) =>
      rows[a].hasBookedAt &&
      rows[b].hasBookedAt &&
      rows[a].bookedAt.difference(rows[b].bookedAt).abs() <= window;
  bool sameAmount(int a, int b) =>
      rows[a].amount.currency.toUpperCase() ==
          rows[b].amount.currency.toUpperCase() &&
      rows[a].amount.decimalAmount.abs() == rows[b].amount.decimalAmount.abs();
  bool sameScope(int a, int b) {
    for (final pair in [
      (rows[a].accountId, rows[b].accountId),
      (rows[a].cardId, rows[b].cardId),
      (rows[a].walletId, rows[b].walletId),
      (budget(a), budget(b)),
    ]) {
      if (pair.$1.isNotEmpty && pair.$2.isNotEmpty && pair.$1 != pair.$2) {
        return false;
      }
    }
    return true;
  }

  bool unlinked(int i) =>
      value(i, 'transactiongroupid').isEmpty &&
      value(i, 'parenttransactionid').isEmpty;
  void joinUnique(Map<int, Set<int>> candidates) {
    final reverse = <int, Set<int>>{};
    for (final entry in candidates.entries) {
      for (final candidate in entry.value) {
        reverse.putIfAbsent(candidate, () => {}).add(entry.key);
      }
    }
    for (final entry in candidates.entries) {
      if (entry.value.length == 1 && reverse[entry.value.single]!.length == 1) {
        join(entry.key, entry.value.single);
      }
    }
  }

  final unloads = <int, Set<int>>{};
  for (var i = 0; i < rows.length; i++) {
    if (_key(rows[i].rawType) != 'walletdebit' ||
        value(i, 'type') != '3' ||
        !unlinked(i)) {
      continue;
    }
    for (var j = 0; j < rows.length; j++) {
      if (_key(rows[j].rawType) == 'cardunload' &&
          value(j, 'type') == '3' &&
          unlinked(j) &&
          sameAmount(i, j) &&
          sameScope(i, j) &&
          _key(rows[i].status) == _key(rows[j].status) &&
          near(i, j, const Duration(seconds: 1))) {
        unloads.putIfAbsent(i, () => {}).add(j);
      }
    }
  }
  joinUnique(unloads);

  // Equals credits can omit the order id while the paired funding debit and
  // exchange record carry it. Require the same budget, sub-second debit/credit
  // booking, and the order's buy currency/amount. The FX summary itself may be
  // posted much later, so do not compare its timestamp to the credit.
  final buyLegs = <int, List<int>>{};
  for (var i = 0; i < rows.length; i++) {
    if (const {'fxtrade', 'exchange'}.contains(_key(rows[i].rawType)) &&
        value(i, 'tradeid').isNotEmpty) {
      buyLegs.putIfAbsent(root(i), () => []).add(i);
    }
  }
  final credits = <int, Set<int>>{};
  for (var i = 0; i < rows.length; i++) {
    if (_key(rows[i].rawType) != 'deposit' ||
        value(i, 'source') != 'exchange' ||
        _key(value(i, 'provider')) != 'equalsmoney' ||
        budget(i).isEmpty ||
        value(i, 'tradeid').isNotEmpty ||
        !cardFeeWasCharged(rows[i]) ||
        (value(i, 'transactiongroupid').isNotEmpty &&
            !value(i, 'transactiongroupid')
                .startsWith('equalsmoney:ledger:')) ||
        value(i, 'parenttransactionid').isNotEmpty) {
      continue;
    }
    for (var j = 0; j < rows.length; j++) {
      if (_key(rows[j].rawType) != 'withdrawal' ||
          value(j, 'source') != 'exchange' ||
          _key(value(j, 'provider')) != 'equalsmoney' ||
          budget(j) != budget(i) ||
          !sameScope(i, j) ||
          !cardFeeWasCharged(rows[j]) ||
          !near(i, j, const Duration(seconds: 1))) {
        continue;
      }
      final operation = root(j);
      if (operation == root(i)) continue;
      final hasBuyLeg = (buyLegs[operation] ?? []).any((k) => sameAmount(i, k));
      if (hasBuyLeg) credits.putIfAbsent(i, () => {}).add(operation);
    }
  }
  joinUnique(credits);

  // A legacy top-up fee lacks a parent reference, but the top-up reports the
  // exact charged fee. Keep the credited amount as the summary; subtracting
  // this fee again would understate what reached the card.
  final topupFees = <int, Set<int>>{};
  for (var i = 0; i < rows.length; i++) {
    if (_key(rows[i].rawType) != 'fees' ||
        _key(rows[i].title) != 'feescardtopupfee' ||
        !unlinked(i)) {
      continue;
    }
    for (var j = 0; j < rows.length; j++) {
      if (_key(rows[j].rawType) == 'cardtopup' &&
          unlinked(j) &&
          rows[j].amount.currency.toUpperCase() ==
              rows[i].amount.currency.toUpperCase() &&
          double.tryParse(value(j, 'fee')) ==
              rows[i].amount.decimalAmount.abs() &&
          rows[i].amount.decimalAmount != 0 &&
          sameScope(i, j) &&
          cardFeeWasCharged(rows[i]) &&
          cardFeeWasCharged(rows[j]) &&
          near(i, j, const Duration(seconds: 2))) {
        topupFees.putIfAbsent(i, () => {}).add(j);
      }
    }
  }
  joinUnique(topupFees);

  final members = <int, List<LedgerTransaction>>{};
  for (var i = 0; i < rows.length; i++) {
    members.putIfAbsent(root(i), () => []).add(rows[i]);
  }
  final summaries = <int, LedgerTransaction>{};
  for (final row in displayed) {
    final index = byId[row.id];
    final i = index?.length == 1 ? index!.single : byObject[row];
    if (i == null) continue;
    final group = root(i);
    final previous = summaries[group];
    if (previous == null || _rank(row) < _rank(previous)) {
      summaries[group] = row;
    }
  }
  return [
    for (final group in members.entries)
      ActivityTransactionGroup(
          summaries[group.key] ?? group.value.first, group.value),
  ];
}

int _rank(LedgerTransaction row) {
  final type = _key(row.rawType);
  final kind = switch (type) {
    'fxtrade' => 0,
    'cardtopup' || 'cardunload' => 1,
    'exchange' => 2,
    'walletcredit' || 'walletdebit' => 4,
    _ => isLedgerFee(row) ? 5 : 3,
  };
  return (row.isPrimary ? 0 : 10) + kind;
}

/// Keep existing fee/currency accounting while excluding a wallet view that
/// grouping has linked to a card funding operation. Without this, an unload
/// hidden under its card row would still appear as spending in the net flow.
/// A scoped wallet feed with no card counterpart retains its wallet movement.
List<LedgerTransaction> activityAccountingRows(List<LedgerTransaction> rows) {
  final walletViews = <String>{};
  for (final group in groupActivityTransactions(rows)) {
    if (!const {'cardtopup', 'cardunload'}
        .contains(_key(group.primary.rawType))) {
      continue;
    }
    for (final entry in group.entries) {
      if (entry.id.isNotEmpty &&
          const {'walletcredit', 'walletdebit'}.contains(_key(entry.rawType))) {
        walletViews.add(entry.id);
      }
    }
  }
  return groupCardFees(rows)
      .where((row) => !walletViews.contains(row.id))
      .toList();
}
