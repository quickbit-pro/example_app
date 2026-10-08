import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/auth_token_provider.dart';
import '../../../core/documents/document_api.dart';
import '../data/transaction_documents_api.dart';
import '../data/invoice_picker.dart';
export '../data/invoice_picker.dart';
import '../export/save_transaction_pdf.dart';
import '../export/transaction_pdf_ready_dialog.dart';

final invoicePickerProvider = Provider((ref) => InvoicePicker());

/// Private attachments are scoped by the authenticated owner and provider transaction ID.
class TransactionInvoices extends ConsumerStatefulWidget {
  const TransactionInvoices({required this.transactionId, super.key});
  final String transactionId;
  @override
  ConsumerState<TransactionInvoices> createState() =>
      _TransactionInvoicesState();
}

class _TransactionInvoicesState extends ConsumerState<TransactionInvoices> {
  bool _busy = false;
  String? _message;
  String? _stage;
  InvoiceFile? _pendingFile;
  String? _uploadedId;
  bool _failed = false;
  bool _current(int generation, String transactionId) =>
      mounted &&
      widget.transactionId == transactionId &&
      ref.read(authSessionGenerationProvider) == generation;

  Future<void> _upload(bool camera, {bool retry = false}) async {
    if (_busy) return;
    final generation = ref.read(authSessionGenerationProvider);
    final transactionId = widget.transactionId;
    setState(() {
      _busy = true;
      _message = null;
      _failed = false;
      _stage = retry ? 'Saving invoice…' : 'Choose your invoice…';
    });
    try {
      final file = retry
          ? _pendingFile
          : await ref.read(invoicePickerProvider).pick(camera: camera);
      if (!mounted || !_current(generation, transactionId)) return;
      if (file == null) {
        setState(() => _message = 'No file selected.');
        return;
      }
      if (!retry) {
        _pendingFile = file;
        _uploadedId = null;
      }
      if (file.bytes.isEmpty || file.bytes.length > 10 * 1024 * 1024) {
        throw const FormatException('Choose an invoice up to 10 MB.');
      }
      setState(() => _stage = 'Uploading invoice…');
      final id = _uploadedId ??
          await ref
              .read(documentApiProvider)
              .upload(bytes: file.bytes, filename: file.filename);
      if (!mounted || !_current(generation, transactionId)) return;
      _uploadedId = id;
      setState(() => _stage = 'Attaching to transaction…');
      await ref.read(transactionDocumentsApiProvider).attach(transactionId, id);
      if (!mounted || !_current(generation, transactionId)) return;
      ref.invalidate(transactionDocumentsProvider(transactionId));
      setState(() {
        _message = 'Invoice saved.';
        _pendingFile = null;
        _uploadedId = null;
      });
    } catch (error) {
      if (_current(generation, transactionId)) {
        setState(() {
          _message = _error(error);
          _failed = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _stage = null;
        });
      }
    }
  }

  String _error(Object error) {
    if (error is FormatException) return error.message;
    if (error is DioException && error.response?.data is Map) {
      final data = error.response!.data as Map;
      final message = data['message'] ?? data['detail'] ?? data['title'];
      if (message is String && message.length < 400) return message;
    }
    return 'Could not save the invoice. Please try again.';
  }

  Future<void> _open(TransactionDocument document) async {
    if (_busy) return;
    if (!document.isPdf) {
      await showDialog<void>(
          context: context, builder: (_) => _InvoicePhoto(document: document));
      return;
    }
    final generation = ref.read(authSessionGenerationProvider);
    final transactionId = widget.transactionId;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final bytes =
          await ref.read(documentApiProvider).download(document.documentId);
      if (!mounted || !_current(generation, transactionId)) return;
      if (kIsWeb) {
        final delivery = prepareTransactionPdf(bytes, document.filename);
        try {
          await showDialog<void>(
              context: context,
              builder: (_) => TransactionPdfReadyDialog(document: delivery));
        } finally {
          delivery.dispose();
        }
      } else {
        await saveTransactionPdf(bytes, document.filename);
      }
    } catch (_) {
      if (_current(generation, transactionId)) {
        setState(
            () => _message = 'Could not open the invoice. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TransactionDocument document) async {
    if (_busy) return;
    final generation = ref.read(authSessionGenerationProvider);
    final transactionId = widget.transactionId;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await ref.read(transactionDocumentsApiProvider).remove(document.id);
      if (!mounted || !_current(generation, transactionId)) return;
      ref.invalidate(transactionDocumentsProvider(transactionId));
    } catch (_) {
      if (_current(generation, transactionId)) {
        setState(() =>
            _message = 'Could not remove the attachment. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transactionId.isEmpty) return const SizedBox.shrink();
    ref.listen(authSessionGenerationProvider, (_, __) {
      if (mounted) {
        setState(() {
          _message = null;
          _pendingFile = null;
          _uploadedId = null;
          _failed = false;
        });
      }
    });
    final documents =
        ref.watch(transactionDocumentsProvider(widget.transactionId));
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colors.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        LayoutBuilder(builder: (context, constraints) {
          final heading = Row(children: [
            Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.receipt_long_outlined,
                    color: colors.primary, size: 23)),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Invoices',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Keep receipts with this transaction',
                      style: TextStyle(
                          fontSize: 12, color: colors.onSurfaceVariant)),
                ])),
          ]);
          final actions = Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.icon(
                onPressed: _busy ? null : () => _upload(false),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Choose file')),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _upload(true),
                icon: const Icon(Icons.photo_camera_outlined, size: 18),
                label: const Text('Take photo')),
          ]);
          return constraints.maxWidth >= 620
              ? Row(children: [
                  Expanded(child: heading),
                  const SizedBox(width: 16),
                  actions
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 16), actions]);
        }),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.lock_outline_rounded,
              size: 13, color: colors.onSurfaceVariant),
          const SizedBox(width: 5),
          Expanded(
              child: Text('Private · Images or PDF · Up to 10 MB',
                  style:
                      TextStyle(fontSize: 12, color: colors.onSurfaceVariant)))
        ]),
        if (_busy || _message != null) ...[
          const SizedBox(height: 14),
          Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: (_failed ? colors.error : colors.primary)
                      .withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_pendingFile != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(_pendingFile!.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600))),
                    Row(children: [
                      Icon(
                          _busy
                              ? Icons.cloud_upload_outlined
                              : _failed
                                  ? Icons.error_outline
                                  : Icons.check_circle_outline,
                          size: 18,
                          color: _failed ? colors.error : colors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Semantics(
                              liveRegion: true,
                              child: Text(
                                  _busy
                                      ? (_stage ?? 'Please wait…')
                                      : _message!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: _failed
                                          ? colors.error
                                          : colors.onSurface)))),
                      if (_failed && _pendingFile != null && !_busy)
                        TextButton(
                            onPressed: () => _upload(false, retry: true),
                            child: const Text('Retry')),
                    ]),
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: LinearProgressIndicator(minHeight: 3)),
                  ])),
        ],
        documents.when(
          skipLoadingOnRefresh: false,
          loading: () => const Padding(
              padding: EdgeInsets.only(top: 16),
              child: LinearProgressIndicator(minHeight: 2)),
          error: (_, __) => TextButton(
              onPressed: () => ref.invalidate(
                  transactionDocumentsProvider(widget.transactionId)),
              child: const Text('Could not load invoices. Retry')),
          data: (rows) =>
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (rows.isEmpty && !_busy && !_failed)
              Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text('No invoices attached yet.',
                      style: TextStyle(
                          color: colors.onSurfaceVariant, fontSize: 13))),
            for (final document in rows)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Material(
                    color:
                        colors.surfaceContainerHighest.withValues(alpha: .45),
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 12, right: 4),
                      leading: Container(
                          width: 38,
                          height: 44,
                          decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(8)),
                          child: Icon(
                              document.isPdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.image_outlined,
                              color: colors.primary)),
                      title: Text(document.filename,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          '${(document.byteLength / 1024).ceil()} KB · ${document.isPdf && !kIsWeb ? 'Save PDF' : 'Open invoice'}',
                          style: const TextStyle(fontSize: 12)),
                      onTap: _busy ? null : () => _open(document),
                      trailing: IconButton(
                          tooltip: 'Remove attachment',
                          onPressed: _busy ? null : () => _remove(document),
                          icon: Icon(Icons.close,
                              color: colors.onSurfaceVariant, size: 18)),
                    ),
                  )),
          ]),
        ),
      ]),
    );
  }
}

class _InvoicePhoto extends ConsumerWidget {
  const _InvoicePhoto({required this.document});
  final TransactionDocument document;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Dialog.fullscreen(
          child: Scaffold(
        appBar: AppBar(
            title: Text(document.filename),
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context))),
        body: ref.watch(originalDocumentProvider(document.documentId)).when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () => ref.invalidate(
                          originalDocumentProvider(document.documentId)),
                      child: const Text('Could not load invoice. Retry'))),
              data: (bytes) => Center(
                  child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: Image.memory(bytes,
                          errorBuilder: (_, __, ___) => const Text(
                              'This image could not be displayed.')))),
            ),
      ));
}
