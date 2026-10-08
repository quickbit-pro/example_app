import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import 'save_transaction_pdf.dart';
import 'transaction_pdf.dart';
import 'transaction_pdf_ready_dialog.dart';

/// A download action for the exact visible ledger or one loaded receipt.
/// Passing null while loading/error prevents exporting a stale or partial feed.
class TransactionPdfExportButton extends ConsumerStatefulWidget {
  const TransactionPdfExportButton({
    required this.transactions,
    this.filters = const [],
    this.identityFor,
    this.receipt = false,
    this.appName,
    this.label,
    super.key,
  });

  final List<LedgerTransaction>? transactions;
  final List<String> filters;
  final TransactionIdentityResolver? identityFor;
  final bool receipt;
  final String? appName;
  final String? label;

  @override
  ConsumerState<TransactionPdfExportButton> createState() =>
      _TransactionPdfExportButtonState();
}

class _TransactionPdfExportButtonState
    extends ConsumerState<TransactionPdfExportButton> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final transactions = widget.transactions;
    final enabled = !_busy &&
        transactions != null &&
        transactions.isNotEmpty &&
        (!widget.receipt || transactions.length == 1);
    final tooltip = _busy
        ? context.tr('Preparing PDF')
        : widget.receipt
            ? context.tr('Export receipt as PDF')
            : context.tr('Export transactions as PDF');
    final icon = _busy
        ? const SizedBox.square(
            dimension: 20, child: AppProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.print_outlined);
    if (widget.label != null) {
      return Tooltip(
        message: tooltip,
        child: TextButton.icon(
          onPressed: enabled ? _export : null,
          icon: icon,
          label: Text(_busy ? context.tr('Preparing…') : widget.label!),
          style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
      );
    }
    return IconButton(
      style: MediaQuery.disableAnimationsOf(context)
          ? const ButtonStyle(animationDuration: Duration.zero)
          : null,
      tooltip: tooltip,
      onPressed: enabled ? _export : null,
      icon: icon,
    );
  }

  Future<void> _export() async {
    final transactions = widget.transactions;
    if (_busy || transactions == null || transactions.isEmpty) return;
    setState(() => _busy = true);
    try {
      // Resolve labels, amounts and identities synchronously before any await so
      // refresh/filter changes cannot alter the document the user requested.
      final snapshot = TransactionPdfSnapshot(
        transactions: transactions,
        filters: widget.filters,
        identityFor: widget.identityFor,
        receipt: widget.receipt,
        appName: widget.appName ??
            (AppDesignTheme.nameOf(context).isEmpty
                ? ref.read(appConfigProvider).branding.appName
                : AppDesignTheme.nameOf(context)),
        design: context.brandDesign,
        localizations: AppLocalizations.of(context),
      );
      final bytes = await buildTransactionPdf(snapshot);
      if (!mounted) return;
      if (kIsWeb) {
        final document = prepareTransactionPdf(bytes, snapshot.fileName);
        try {
          await showDialog<void>(
            context: context,
            builder: (_) => TransactionPdfReadyDialog(document: document),
          );
        } finally {
          document.dispose();
        }
        return;
      }
      final saved = await saveTransactionPdf(bytes, snapshot.fileName);
      if (saved && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('PDF saved.')),
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Could not export PDF. Please try again.')),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
