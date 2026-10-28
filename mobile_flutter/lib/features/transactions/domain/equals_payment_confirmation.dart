import '../../../core/models/banking_models.dart';

bool canDownloadEqualsPaymentConfirmation(LedgerTransaction transaction) {
  final fields = {
    for (final entry in transaction.metadata.entries)
      entry.key.toLowerCase(): entry.value,
  };
  if (fields['provider']?.toString().toLowerCase() != 'equalsmoney' ||
      !_positiveInteger(transaction.id)) {
    return false;
  }
  final type = transaction.rawType.toLowerCase();
  final originalType = (fields['originaltype'] ?? fields['original_type'] ?? '')
      .toString()
      .toLowerCase();
  const types = {'payment', 'payout'};
  return (types.contains(type) || types.contains(originalType)) &&
      [
        fields['paymentid'],
        fields['payment_id'],
        fields['externaltransactionid']
      ].any(_positiveInteger);
}

bool _positiveInteger(Object? value) => value is num
    ? value.isFinite && value >= 1 && value == value.truncateToDouble()
    : value is String && RegExp(r'^[1-9][0-9]*$').hasMatch(value.trim());
