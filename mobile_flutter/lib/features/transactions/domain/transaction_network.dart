import '../../../core/models/banking_models.dart';
import 'transaction_activity_type.dart';

/// A receipt's network comes from provider fields, never its title or currency.
/// In particular, EUR does not establish SEPA and USDC does not establish a
/// blockchain: both can travel over more than one payment network.
String? transactionNetworkLabel(LedgerTransaction transaction) {
  final explicit = _networkIn(transaction.metadata);
  if (explicit != null) return explicit;

  final type = _key(transaction.rawType);
  if (transaction.cardId.trim().isNotEmpty ||
      type.startsWith('card') ||
      const {'purchase', 'authorization', 'refund', 'chargeback'}
          .contains(type)) {
    return 'Card network';
  }
  if (TransactionActivityType.crypto.matches(transaction)) return null;
  if (type.contains('exchange') ||
      type.contains('conversion') ||
      type.contains('swap') ||
      type.contains('internal')) {
    return null;
  }
  if (const {
        'credit',
        'debit',
        'budgetcredit',
        'budgetdebit',
        'deposit',
        'withdrawal',
        'payout',
      }.contains(type) ||
      type.startsWith('bank') ||
      type.startsWith('transfer') ||
      type.startsWith('sepa') ||
      type.startsWith('swift')) {
    return 'Bank transfer';
  }
  return null;
}

String? _networkIn(Map<Object?, Object?> metadata) {
  final fields = {
    for (final entry in metadata.entries) _key('${entry.key}'): entry.value,
  };
  for (final key in const [
    'paymentrail',
    'rail',
    'paymentnetwork',
    'network',
    'networkname',
    'chain',
    'chainname',
    'blockchain',
    'blockchainnetwork',
    'cardnetwork',
    'schemename',
  ]) {
    final value = fields[key];
    final text =
        value is Map ? _text(value['name'] ?? value['Name']) : _text(value);
    if (text != null) return _bankRail(text) ?? text;
  }
  // Payment methods can also be operations such as "exchange". Only known
  // rail values belong in the Network row.
  final method = _text(fields['paymentmethod']);
  final rail = method == null ? null : _bankRail(method);
  if (rail != null) return rail;

  // Do not search recipient rosters or fee breakdowns: their network fields
  // do not necessarily describe the transaction's payment network.
  for (final key in const [
    'payment',
    'paymentdetails',
    'transfer',
    'transferdetails',
    'transaction',
    'transactiondetails',
    'crypto',
    'card',
    'carddetails',
  ]) {
    final value = fields[key];
    if (value is Map) {
      final network = _networkIn(value);
      if (network != null) return network;
    }
  }
  return null;
}

String? _text(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  final text = value.trim();
  if (const {'unknown', 'null', 'none', 'undefined'}.contains(_key(text))) {
    return null;
  }
  return text;
}

String? _bankRail(String value) => switch (_key(value)) {
      'sepa' || 'sct' || 'sepacredittransfer' => 'SEPA',
      'sepainstant' ||
      'sctinst' ||
      'sepainstantcredittransfer' =>
        'SEPA Instant',
      'swift' => 'SWIFT',
      'ach' => 'ACH',
      'bacs' => 'BACS',
      'chaps' => 'CHAPS',
      'fps' || 'fasterpayments' => 'Faster Payments',
      'wire' || 'wiretransfer' => 'Wire transfer',
      'banktransfer' => 'Bank transfer',
      _ => null,
    };

String _key(String value) =>
    value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
