import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import 'transaction_pdf_delivery.dart';

/// Keep the prepared file available when a PWA cannot download, or the user
/// cancels sharing. Each action gets its own gesture after PDF generation.
class TransactionPdfReadyDialog extends StatefulWidget {
  const TransactionPdfReadyDialog({required this.document, super.key});

  final TransactionPdfDelivery document;

  @override
  State<TransactionPdfReadyDialog> createState() =>
      _TransactionPdfReadyDialogState();
}

class _TransactionPdfReadyDialogState extends State<TransactionPdfReadyDialog> {
  bool _sharing = false;
  String? _message;

  void _open() {
    try {
      final opened = widget.document.open();
      setState(() => _message = opened
          ? 'Use the PDF viewer’s menu to print.'
          : 'The PDF window was blocked. Try Download PDF or Share PDF.');
    } catch (_) {
      setState(() => _message = 'Could not open the PDF. Try another action.');
    }
  }

  void _download() {
    try {
      widget.document.download();
      setState(() => _message =
          'Check your browser downloads. You can also open the PDF.');
    } catch (_) {
      setState(
          () => _message = 'Could not download the PDF. Try another action.');
    }
  }

  Future<void> _share() async {
    setState(() => _sharing = true);
    try {
      final shared = await widget.document.share();
      if (mounted) {
        setState(
            () => _message = shared ? 'PDF shared.' : 'Sharing cancelled.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message =
            'Could not share the PDF. Try Open PDF or Download PDF.');
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('PDF ready')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr(
                  'Open the PDF to print from its viewer. On your phone, you can also share it with a PDF app or save it to files.')),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, children: [
                FilledButton.icon(
                  onPressed: _sharing ? null : _open,
                  icon: const Icon(Icons.open_in_new),
                  label: Text(context.tr('Open PDF')),
                ),
                OutlinedButton.icon(
                  onPressed: _sharing ? null : _download,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(context.tr('Download PDF')),
                ),
                if (widget.document.canShare)
                  OutlinedButton.icon(
                    onPressed: _sharing ? null : _share,
                    icon: const Icon(Icons.share_outlined),
                    label: Text(_sharing
                        ? context.tr('Sharing…')
                        : context.tr('Share PDF')),
                  ),
              ]),
              if (_message != null) ...[
                const SizedBox(height: 16),
                Semantics(liveRegion: true, child: Text(_message!)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _sharing ? null : () => Navigator.of(context).pop(),
            child: Text(context.tr('Done')),
          ),
        ],
      );
}
