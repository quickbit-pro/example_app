import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/auth_token_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../data/equals_payment_confirmation_api.dart';
import '../domain/equals_payment_confirmation.dart';
import '../export/save_transaction_pdf.dart';
import '../export/transaction_pdf_ready_dialog.dart';

class EqualsPaymentConfirmationButton extends ConsumerStatefulWidget {
  const EqualsPaymentConfirmationButton({required this.transaction, super.key});
  final LedgerTransaction transaction;
  @override
  ConsumerState<EqualsPaymentConfirmationButton> createState() =>
      _ConfirmationState();
}

class _ConfirmationState
    extends ConsumerState<EqualsPaymentConfirmationButton> {
  bool _busy = false;
  String? _error;
  CancelToken? _cancel;
  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _download() async {
    if (_busy) return;
    final id = widget.transaction.id;
    final generation = ref.read(authSessionGenerationProvider);
    bool current() =>
        mounted &&
        widget.transaction.id == id &&
        ref.read(authSessionGenerationProvider) == generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    final cancel = CancelToken();
    _cancel = cancel;
    try {
      final bytes = await ref
          .read(equalsPaymentConfirmationApiProvider)
          .download(id, cancelToken: cancel);
      if (!mounted || !current()) return;
      final filename = 'equals-payment-confirmation-$id.pdf';
      if (kIsWeb) {
        final document = prepareTransactionPdf(bytes, filename);
        try {
          await showDialog<void>(
              context: context,
              builder: (_) => TransactionPdfReadyDialog(document: document));
        } finally {
          document.dispose();
        }
      } else {
        final saved = await saveTransactionPdf(bytes, filename);
        if (saved && mounted && current()) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(context.tr('PDF saved.'))));
        }
      }
    } catch (error) {
      if (current() &&
          !(error is DioException && CancelToken.isCancel(error))) {
        final unavailable = error is DioException &&
            const {400, 404}.contains(error.response?.statusCode);
        setState(() => _error = unavailable
            ? 'Payment confirmation is not available for this transaction yet.'
            : 'Could not download the payment confirmation. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!canDownloadEqualsPaymentConfirmation(widget.transaction)) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      OutlinedButton.icon(
        onPressed: _busy ? null : _download,
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
        icon: _busy
            ? const SizedBox.square(
                dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_outlined),
        label: Text(
            context.tr(_busy ? 'Preparing PDF' : 'Payment confirmation PDF'),
            textAlign: TextAlign.center),
      ),
      if (_error != null)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
                liveRegion: true,
                child: Text(context.tr(_error!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error)))),
    ]);
  }
}
