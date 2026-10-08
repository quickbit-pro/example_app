import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import '../../../core/l10n/app_localizations.dart';
import 'transaction_pdf_renderer.dart' deferred as renderer;

import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';

typedef TransactionIdentityResolver = String? Function(
  LedgerTransaction transaction,
);

/// An immutable, user-visible snapshot. The caller supplies precisely the
/// filtered rows currently displayed; exporting never fetches a different feed.
class TransactionPdfSnapshot {
  TransactionPdfSnapshot({
    required Iterable<LedgerTransaction> transactions,
    Iterable<String> filters = const [],
    TransactionIdentityResolver? identityFor,
    DateTime? generatedAt,
    this.receipt = false,
    this.appName = 'Example',
    this.design = const AppDesign(),
    this.localizations = const AppLocalizations(Locale('en'), {}),
  })  : generatedAt = generatedAt ?? DateTime.now(),
        filters = List.unmodifiable(
            filters.where((label) => label.trim().isNotEmpty)),
        rows = List.unmodifiable(transactions.map(
          (transaction) => TransactionPdfRow.fromTransaction(
            transaction,
            identity: identityFor?.call(transaction),
            localizations: localizations,
          ),
        )) {
    if (receipt && rows.length != 1) {
      throw ArgumentError('A receipt must contain exactly one transaction.');
    }
  }

  final List<TransactionPdfRow> rows;
  final List<String> filters;
  final DateTime generatedAt;
  final bool receipt;
  final String appName;
  final AppDesign design;
  final AppLocalizations localizations;
  String tr(String key, [Map<String, Object?> values = const {}]) =>
      localizations.translate(key, values);
  bool get rtl => localizations.locale.languageCode == 'ar';

  String get title =>
      tr(receipt ? 'Transaction receipt' : 'Transaction activity');

  String get fileName {
    final stamp =
        generatedAt.toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '');
    final safeReference = receipt
        ? rows.single.reference.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '')
        : '';
    final reference = receipt
        ? '-${safeReference.substring(0, safeReference.length.clamp(0, 36))}'
        : '';
    final brand = appName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final prefix = brand.isEmpty ? 'app' : brand;
    return '$prefix-${receipt ? 'receipt' : 'activity'}$reference-$stamp.pdf';
  }
}

class TransactionPdfRow {
  const TransactionPdfRow({
    required this.reference,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.status,
    required this.booked,
    required this.amount,
    this.identity,
    this.settlementAmount,
  });

  factory TransactionPdfRow.fromTransaction(
    LedgerTransaction transaction, {
    String? identity,
    AppLocalizations localizations = const AppLocalizations(Locale('en'), {}),
  }) {
    final settlement = transaction.secondarySettlementAmount;
    return TransactionPdfRow(
      reference: transaction.id,
      title: transaction.title,
      subtitle: transaction.subtitle == transaction.status
          ? ''
          : transaction.subtitle,
      type: localizations.translate(transaction.displayType),
      status: transaction.status.trim().isEmpty
          ? localizations.translate('Not provided')
          : localizations.translate(_statusKey(transaction.status)),
      booked: transaction.hasBookedAt
          ? transactionPdfDateLabel(transaction.bookedAt)
          : localizations.translate('Date unavailable'),
      amount: transactionPdfAmountLabel(transaction.displayAmount),
      settlementAmount:
          settlement == null ? null : transactionPdfAmountLabel(settlement),
      identity: identity?.trim().isEmpty == true ? null : identity,
    );
  }

  final String reference;
  final String title;
  final String subtitle;
  final String type;
  final String status;
  final String booked;
  final String amount;
  final String? settlementAmount;
  final String? identity;
}

String transactionPdfAmountLabel(Money amount) {
  final formatted = amount.formatted;
  final currency = amount.currency.trim().toUpperCase();
  final sign = !Money.maskAmounts && amount.isPositive ? '+' : '';
  return '$sign$formatted${formatted.endsWith(currency) || currency.isEmpty ? '' : ' $currency'}';
}

/// Includes the offset in force on the transaction date, including DST.
String transactionPdfDateLabel(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  final offset = local.timeZoneOffset;
  final offsetMinutes = offset.inMinutes.abs();
  final zone = 'UTC${offset.isNegative ? '-' : '+'}'
      '${two(offsetMinutes ~/ 60)}:${two(offsetMinutes % 60)}';
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}:${two(local.second)} $zone';
}

/// Load the PDF engine only when an export is requested. The lightweight
/// snapshot stays available while the user browses accounts and activity.
Future<Uint8List> buildTransactionPdf(
  TransactionPdfSnapshot snapshot, {
  AssetBundle? assetBundle,
}) async {
  await renderer.loadLibrary();
  return renderer.buildTransactionPdf(snapshot, assetBundle: assetBundle);
}

String _statusKey(String value) {
  if (value.isEmpty) return value;
  const known = {
    'completed',
    'pending',
    'failed',
    'cancelled',
    'processing',
    'rejected',
    'approved',
    'settled'
  };
  return known.contains(value.toLowerCase())
      ? '${value[0].toUpperCase()}${value.substring(1).toLowerCase()}'
      : value;
}
