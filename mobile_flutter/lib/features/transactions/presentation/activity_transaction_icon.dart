import 'package:flutter/material.dart';

import '../../../core/models/banking_models.dart';
import '../domain/transaction_activity_type.dart';

/// Operation glyph for Activity when the API does not supply a merchant logo.
/// Provider types and the displayed amount determine the icon; merchant names
/// and descriptions cannot turn an ordinary payment into an exchange or fee.
IconData activityTransactionIcon(LedgerTransaction transaction) {
  final type = transaction.displayType
      .replaceAll(RegExp(r'[^a-zA-Z0-9]'), '')
      .toLowerCase();

  // Fees and exchanges keep their identity regardless of which direction a
  // provider leg moves. displayType also decodes numeric card operation types.
  if (transaction.type == TransactionType.fee || type.contains('fee')) {
    return Icons.receipt_long_outlined;
  }
  if (type.contains('exchange') ||
      type.contains('conversion') ||
      type.contains('convert') ||
      type.contains('swap') ||
      const {'cryptotoquantum', 'cryptotoquantumtransfer'}.contains(type)) {
    return Icons.currency_exchange_rounded;
  }

  final amount = transaction.displayAmount;
  if (amount.isPositive) return Icons.arrow_downward_rounded;
  if (amount.isNegative) {
    if (transaction.type == TransactionType.card &&
        TransactionActivityType.card.matches(transaction) &&
        !type.contains('withdraw') &&
        !type.contains('topup') &&
        !type.contains('unload') &&
        !type.startsWith('atm')) {
      return Icons.shopping_basket_outlined;
    }
    return Icons.arrow_upward_rounded;
  }

  // A zero amount has no incoming/outgoing direction.
  return TransactionActivityType.card.matches(transaction)
      ? Icons.credit_card_rounded
      : Icons.swap_vert_rounded;
}
