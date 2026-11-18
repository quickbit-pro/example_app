import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'document_api.dart';

class OriginalReceiptButton extends StatelessWidget {
  const OriginalReceiptButton({required this.documentId, super.key});
  final String documentId;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      icon: const Icon(Icons.image_outlined),
      label: Text(context.tr('View original receipt')),
      onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _ReceiptPhoto(documentId: documentId)));
}

class _ReceiptPhoto extends ConsumerWidget {
  const _ReceiptPhoto({required this.documentId});
  final String documentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Dialog.fullscreen(
      child: Scaffold(
          appBar: AppBar(
              title: Text(context.tr('Original receipt')),
              leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context))),
          body: ref.watch(originalDocumentProvider(documentId)).when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                  child: TextButton(
                      onPressed: () =>
                          ref.invalidate(originalDocumentProvider(documentId)),
                      child: Text(context
                          .tr('Could not load the photo. Tap to retry.')))),
              data: (bytes) => Center(
                  child: InteractiveViewer(
                      minScale: .5,
                      maxScale: 5,
                      child: Image.memory(bytes, errorBuilder: (_, __, ___) => Text(context.tr('This document cannot be previewed as a photo.'))))))));
}
