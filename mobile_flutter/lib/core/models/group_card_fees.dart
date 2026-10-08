import 'banking_models.dart';

String _key(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
Map<String, dynamic> _fields(LedgerTransaction row) =>
    {for (final e in row.metadata.entries) _key(e.key): e.value};
String _value(Map<String, dynamic> fields, String key) =>
    fields[key]?.toString().trim() ?? '';

final _digits = RegExp(r'^\d+$');
final _feeSuffix = RegExp(r'-Fee$', caseSensitive: false);
final _clientFeeSuffix =
    RegExp(r'_Fee_(Consumption|Declination)$', caseSensitive: false);
final _feeRequest =
    RegExp(r'request\s+([A-Za-z0-9-]+)\s*$', caseSensitive: false);
final _feeTitlePrefix = RegExp(r'^\s*fees?\s*:\s*', caseSensitive: false);

bool isLinkedCardFee(LedgerTransaction row) {
  final type = _key(row.rawType);
  final client = _value(_fields(row), 'clienttransactionid').toLowerCase();
  return const {
        'cardpaymentfee',
        'carddeclinefee',
        'consumptionfee',
        'declinationfee',
        '9',
        '10'
      }.contains(type) ||
      client.endsWith('_fee_consumption') ||
      client.endsWith('_fee_declination');
}

bool _isDeclineFee(LedgerTransaction row) =>
    _key(row.rawType).contains('declin') ||
    _value(_fields(row), 'clienttransactionid')
        .toLowerCase()
        .endsWith('_fee_declination') ||
    row.rawType == '10' ||
    _value(_fields(row), 'type') == '10';

/// A fee the provider books as its own ledger row: a card fee, or an account
/// fee such as the Equals service fee on an order or an incoming credit.
bool isLedgerFee(LedgerTransaction row) =>
    isLinkedCardFee(row) ||
    row.type == TransactionType.fee ||
    _key(row.rawType) == 'fee' ||
    _key(row.rawType) == 'fees';

bool cardFeeWasCharged(LedgerTransaction row) => const {
      'success',
      'completed',
      'settled',
      'closed',
      'booked'
    }.contains(_key(row.status));

String cardFeeLabel(LedgerTransaction row) {
  if (isLinkedCardFee(row)) {
    return _isDeclineFee(row) ? 'Decline fee' : 'Consumption fee';
  }
  // "Fee: Service fee" → "Service fee"; a bare "fee" → "Fee".
  final title = row.title.replaceFirst(_feeTitlePrefix, '').trim();
  if (title.isEmpty || _key(title) == 'fee' || _key(title) == 'fees') {
    return 'Fee';
  }
  return '${title[0].toUpperCase()}${title.substring(1)}';
}

/// What the fee actually cost. Hoppa books a decline fee with `amount: 0` and
/// the charge in `feeAmount`; every other fee carries it in `amount`.
Money feeChargedAmount(LedgerTransaction fee) {
  if (fee.amount.decimalAmount != 0) return fee.amount;
  final fields = _fields(fee);
  final raw = double.tryParse(_value(fields, 'feeamount'));
  if (raw == null || !raw.isFinite || raw <= 0) return fee.amount;
  final currency = _value(fields, 'feecurrency').toUpperCase();
  return Money(
    currency: currency.isEmpty ? fee.amount.currency : currency,
    minorUnits: -(raw * 100).round(),
    decimalAmount: -raw,
  );
}

bool _isEqualsRow(Map<String, dynamic> fields) =>
    _value(fields, 'transactiongroupid').startsWith('equalsmoney:') ||
    _key(_value(fields, 'provider')) == 'equalsmoney' ||
    const {'orders', 'exchange', 'externalcredit'}
        .contains(_key(_value(fields, 'source')));

/// The provider ledger entries this row is a view of. Equals surfaces one box
/// transaction as a ledger leg (`externalTransactionId` = box id, or a
/// `equalsmoney:ledger:<box>` group) *and* as an order or fee record carrying
/// `boxTransactionId`; both name the same movement.
Set<String> _boxIds(Map<String, dynamic> fields) {
  final ids = <String>{};
  final box = _value(fields, 'boxtransactionid');
  if (box.isNotEmpty) ids.add(box);
  if (_isEqualsRow(fields)) {
    final external = _value(fields, 'externaltransactionid');
    if (_digits.hasMatch(external)) ids.add(external);
    final group = _value(fields, 'transactiongroupid');
    final ledger = RegExp(r'^equalsmoney:ledger:(\d+)$').firstMatch(group);
    if (ledger != null) ids.add(ledger.group(1)!);
  }
  return ids;
}

/// The Equals order this row belongs to — a fee order keeps its `-Fee`
/// suffix here, so the caller can tell the fee from the order it charges.
String _orderRef(Map<String, dynamic> fields) {
  final trade = _value(fields, 'tradeid');
  if (trade.isNotEmpty) return trade;
  final group = RegExp(r'^equalsmoney:order:(.+)$')
      .firstMatch(_value(fields, 'transactiongroupid'));
  if (group != null) return group.group(1)!.trim();
  final order = _value(fields, 'orderid');
  // Numeric order ids are Equals' internal keys, not the order reference.
  if (order.isNotEmpty && !_digits.hasMatch(order)) return order;
  return '';
}

class _Entry {
  _Entry(this.index, this.row)
      : fields = _fields(row),
        members = [index];
  final int index;
  final LedgerTransaction row;
  final Map<String, dynamic> fields;

  /// Indices of the raw rows folded into this one.
  final List<int> members;
}

/// Which view of one movement survives when several are folded together: the
/// row that says the most. An FX trade names both legs; a fee record names
/// the fee; a bare ledger leg ("Budget debit: orders") names neither.
int _rank(LedgerTransaction row) {
  final type = _key(row.rawType);
  if (type == 'fxtrade') return 0;
  if (type == 'fee') return 1;
  // The payment is the movement; Hoppa's "fees" record of the same amount
  // is the request it settled, and would read as a fee on top of it.
  if (type == 'internalpayment') return 2;
  if (type == 'fees') return 3;
  if (type == 'exchange') return 4;
  return 5;
}

/// Collapses rows that are the same provider movement seen twice: rows that
/// share a box transaction id, primary Equals rows on the same order, and a
/// Hoppa "fees: Direct payment for request N" beside the internal payment
/// with client id N for the same amount.
///
/// Match explicit provider references only. The order and the fee record
/// carry the ids; merchant, amount and date are never used to fold rows.
List<LedgerTransaction> dedupeLedgerDuplicates(List<LedgerTransaction> rows) =>
    [for (final entry in _fold(rows)) entry.row];

/// Original records behind each folded movement, with the display row first.
/// Activity uses these to keep duplicate provider views available on expansion.
List<List<LedgerTransaction>> ledgerDuplicateGroups(
        List<LedgerTransaction> rows) =>
    [
      for (final entry in _fold(rows))
        [for (final index in entry.members) rows[index]],
    ];

List<_Entry> _fold(List<LedgerTransaction> rows) {
  final entries = [for (var i = 0; i < rows.length; i++) _Entry(i, rows[i])];
  final parent = List<int>.generate(rows.length, (i) => i);
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  void union(int a, int b) {
    final ra = find(a), rb = find(b);
    if (ra != rb) parent[rb] = ra;
  }

  final byKey = <String, int>{};
  void link(String key, int i) {
    final first = byKey.putIfAbsent(key, () => i);
    if (first != i) union(first, i);
  }

  final requests = <String, int>{};
  for (final entry in entries) {
    final row = entry.row;
    for (final box in _boxIds(entry.fields)) {
      link('box:$box', entry.index);
    }
    final order = _orderRef(entry.fields);
    if (order.isNotEmpty &&
        row.isPrimary &&
        !isLedgerFee(row) &&
        !_feeSuffix.hasMatch(order)) {
      link('order:$order', entry.index);
    }
    if (_key(row.rawType) == 'internalpayment') {
      final client = _value(entry.fields, 'clienttransactionid');
      if (client.isNotEmpty) requests.putIfAbsent(client, () => entry.index);
    }
  }
  for (final entry in entries) {
    final row = entry.row;
    if (_key(row.rawType) != 'fees') continue;
    final request = _feeRequest.firstMatch(row.title)?.group(1);
    final payment = request == null ? null : requests[request];
    if (payment == null) continue;
    final other = rows[payment].amount;
    if (other.currency.toUpperCase() == row.amount.currency.toUpperCase() &&
        other.decimalAmount == row.amount.decimalAmount) {
      union(payment, entry.index);
    }
  }

  final groups = <int, List<_Entry>>{};
  for (final entry in entries) {
    groups.putIfAbsent(find(entry.index), () => []).add(entry);
  }
  final kept = <_Entry>[];
  for (final group in groups.values) {
    var best = group.first;
    for (final entry in group.skip(1)) {
      if (_rank(entry.row) < _rank(best.row)) best = entry;
    }
    // The survivor answers for every reference its duplicates carried, so a
    // fee that names the hidden leg still finds the row that stayed.
    for (final entry in group) {
      if (identical(entry, best)) continue;
      best.members.add(entry.index);
      for (final field in entry.fields.entries) {
        best.fields.putIfAbsent(field.key, () => field.value);
      }
      best.fields.putIfAbsent('__boxids', () => <String>{});
      (best.fields['__boxids'] as Set<String>).addAll(_boxIds(entry.fields));
    }
    kept.add(best);
  }
  kept.sort((a, b) => a.index.compareTo(b.index));
  return kept;
}

Set<String> _allBoxIds(_Entry entry) => {
      ..._boxIds(entry.fields),
      ...?(entry.fields['__boxids'] as Set<String>?),
    };

/// A card fee the provider did not link by reference is matched to the one
/// card payment on the same card booked within this window of it. Hoppa's
/// older decline fees (June 2026 and before) carry a `relatedCardTransactionId`
/// that names nothing in the feed and a client id without the fee suffix, so
/// without this they sit as orphan "$0.00" rows beside the decline they
/// belong to. The window is tight enough that two attempts seconds apart
/// still resolve by nearest booking time, and a tie stays standalone.
const _cardFeeWindow = Duration(seconds: 15);

/// Hoppa books these to the second, so two attempts one second apart are
/// still told apart; only an equal distance is a tie.
const _cardFeeTieBreak = Duration(milliseconds: 500);

/// Presentation grouping only. Keep the original feed for balances/exports.
///
/// First folds duplicate views of one movement ([dedupeLedgerDuplicates]),
/// then attaches each fee to the row it charges — a card fee to its purchase
/// by provider or client reference, an Equals `<order>-Fee` to its order or to
/// the credit it names — and hides the fee row. Unmatched and ambiguous fees
/// remain standalone.
List<LedgerTransaction> groupCardFees(List<LedgerTransaction> rows) {
  final entries = _fold(rows);
  final ids = <String, Set<int>>{};
  final clients = <String, Set<int>>{};
  final orders = <String, Set<int>>{};
  final boxes = <String, Set<int>>{};
  void add(Map<String, Set<int>> index, String key, int i) {
    if (key.isNotEmpty) index.putIfAbsent(key, () => {}).add(i);
  }

  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final row = entry.row;
    if (isLedgerFee(row)) continue;
    final fields = entry.fields;
    if (row.type == TransactionType.card &&
        !const {'7', '8', '15', '16'}.contains(row.rawType)) {
      for (final id in [
        row.id,
        _value(fields, 'externaltransactionid'),
        _value(fields, 'cardtransactionid')
      ]) {
        add(ids, id, i);
      }
    }
    add(clients, _value(fields, 'clienttransactionid'), i);
    final order = _orderRef(fields);
    if (!_feeSuffix.hasMatch(order)) add(orders, order, i);
    for (final box in _allBoxIds(entry)) {
      add(boxes, box, i);
    }
  }

  final attached = <int, List<LedgerTransaction>>{};
  final hidden = <int>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    final fee = entry.row;
    if (!isLedgerFee(fee)) continue;
    final fields = entry.fields;
    final candidates = <int>{};
    final card = isLinkedCardFee(fee);
    if (card) {
      for (final id in [
        _value(fields, 'relatedcardtransactionid'),
        _value(fields, 'sourcetransactionid'),
        _value(fields, 'sourcelocaltransactionid')
      ]) {
        candidates.addAll(ids[id] ?? {});
      }
      final client = _value(fields, 'clienttransactionid');
      final parentClient = client.replaceFirst(_clientFeeSuffix, '');
      if (parentClient != client) {
        candidates.addAll(clients[parentClient] ?? {});
      }
    } else {
      final order = _orderRef(fields);
      if (_feeSuffix.hasMatch(order)) {
        candidates.addAll(orders[order.replaceFirst(_feeSuffix, '')] ?? {});
      }
      candidates.addAll(boxes[_value(fields, 'relatedcreditid')] ?? {});
    }
    candidates.removeWhere((j) =>
        fee.cardId.isNotEmpty &&
        entries[j].row.cardId.isNotEmpty &&
        fee.cardId != entries[j].row.cardId);
    if (card && candidates.isEmpty) {
      final nearest = _nearestCardPayment(entries, i);
      if (nearest != null) candidates.add(nearest);
    }
    // An order's funding leg shares its reference but is not the order; the
    // fee belongs on the primary row the ledger shows.
    if (candidates.length > 1) {
      final primary = candidates.where((j) => entries[j].row.isPrimary);
      if (primary.length == 1) candidates.retainWhere(primary.contains);
    }
    if (candidates.length != 1) continue;
    attached.putIfAbsent(candidates.single, () => []).add(fee);
    hidden.add(i);
  }
  return [
    for (var i = 0; i < entries.length; i++)
      if (!hidden.contains(i))
        attached.containsKey(i)
            ? entries[i].row.withCardFees(attached[i]!)
            : entries[i].row
  ];
}

int? _nearestCardPayment(List<_Entry> entries, int feeIndex) {
  final fee = entries[feeIndex].row;
  if (!fee.hasBookedAt || fee.cardId.isEmpty) return null;
  final decline = _isDeclineFee(fee);
  int? best;
  Duration? bestGap;
  Duration? runnerUp;
  for (var j = 0; j < entries.length; j++) {
    final row = entries[j].row;
    if (j == feeIndex ||
        row.type != TransactionType.card ||
        isLedgerFee(row) ||
        !row.hasBookedAt ||
        row.cardId != fee.cardId ||
        const {'7', '8', '15', '16'}.contains(row.rawType)) {
      continue;
    }
    if (decline && !_hasFailed(row)) continue;
    final gap = (fee.bookedAt.difference(row.bookedAt)).abs();
    if (gap > _cardFeeWindow) continue;
    if (bestGap == null || gap < bestGap) {
      runnerUp = bestGap;
      bestGap = gap;
      best = j;
    } else if (runnerUp == null || gap < runnerUp) {
      runnerUp = gap;
    }
  }
  if (best == null) return null;
  if (runnerUp != null && runnerUp - bestGap! < _cardFeeTieBreak) return null;
  return best;
}

bool _hasFailed(LedgerTransaction row) => const {
      'failed',
      'fail',
      'declined',
      'rejected',
      'cancelled',
      'canceled',
    }.contains(_key(row.status));

Money cardListAmount(LedgerTransaction row) {
  final charged = row.cardFees.where(cardFeeWasCharged).toList();
  if (charged.isEmpty ||
      charged.any((f) =>
          feeChargedAmount(f).currency.toUpperCase() !=
          row.amount.currency.toUpperCase())) {
    return row.displayAmount;
  }
  final total = (_hasFailed(row) ? 0.0 : row.amount.decimalAmount) +
      charged.fold<double>(
          0, (sum, fee) => sum + feeChargedAmount(fee).decimalAmount);
  return Money(
      currency: row.amount.currency,
      minorUnits: (total * 100).round(),
      decimalAmount: total);
}

String? cardFeeCaption(LedgerTransaction row) {
  if (row.cardFees.isEmpty) return null;
  return row.cardFees.map((fee) {
    final amount = feeChargedAmount(fee);
    return '${cardFeeLabel(fee)} ${amount.currency} ${amount.decimalAmount.abs().toStringAsFixed(2)}'
        '${cardFeeWasCharged(fee) ? '' : ' · ${fee.status}'}';
  }).join(' · ');
}
