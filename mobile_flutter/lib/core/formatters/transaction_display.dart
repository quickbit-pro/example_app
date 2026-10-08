String transactionDisplayTitle(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return 'Transaction';
  final normalized = raw.toLowerCase();

  if (normalized.contains('uk.obie.balancetransfer')) {
    return 'Bank transfer';
  }
  if (normalized.contains('interlace withdrawal') &&
      normalized.contains('equals money')) {
    return 'Transfer to fiat account';
  }
  if (normalized.contains('wallet debit')) return 'Wallet debit';
  if (normalized.contains('wallet credit')) return 'Wallet credit';
  if (normalized.startsWith('crypto deposit')) return 'Crypto deposit';
  if (normalized.startsWith('exchange ')) return 'Crypto exchange';
  if (normalized.contains('card top-up') ||
      normalized.contains('card top up')) {
    return 'Card top-up';
  }

  final spaced = raw
      .replaceAll(RegExp(r'[._-]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) return 'Transaction';
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String transactionDisplayStatus(String value) {
  final normalized = value.toLowerCase().replaceAll('_', ' ').trim();
  return switch (normalized) {
    'complete' || 'completed' || 'closed' || 'settled' => 'Completed',
    'pending' || 'processing' || 'in progress' => 'Pending',
    'failed' || 'fail' || 'declined' || 'rejected' => 'Failed',
    'cancelled' || 'canceled' => 'Cancelled',
    '' => 'Processing',
    _ => '${normalized[0].toUpperCase()}${normalized.substring(1)}',
  };
}
