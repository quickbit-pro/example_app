import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:html/parser.dart' as html;
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';

class EqualsDocument {
  const EqualsDocument(
      {required this.url, required this.type, required this.bytes});
  final String url;
  final String type;
  final Uint8List bytes;
}

final equalsDocumentProvider = FutureProvider.autoDispose
    .family<EqualsDocument, String>((ref, kind) async {
  final response = await ref.watch(dioProvider).get<Map<String, dynamic>>(
      '/api/v1/mobile/agreements/equals/documents/$kind');
  final json = response.data!;
  return EqualsDocument(
      url: json['sourceUrl'] as String,
      type: json['contentType'] as String,
      bytes: base64Decode(json['content'] as String));
});

/// Render document content, not the website's navigation, trackers or scripts.
/// Keep all legal text, headings, lists, tables and links in the document body.
String equalsDocumentHtml(Uint8List bytes) {
  final parsed = html.parse(utf8.decode(bytes));
  final body = parsed.querySelector('main') ??
      parsed.querySelector('article') ??
      parsed.body;
  if (body == null || body.querySelector('iframe, object, embed') != null) {
    throw const FormatException(
        'Document requires unsupported embedded content.');
  }
  for (final element in body.querySelectorAll(
      'script, style, noscript, nav, header, footer, form, button')) {
    element.remove();
  }
  for (final element in body.querySelectorAll('*')) {
    // Website CSS can hide text or collapse sections; display all content.
    element.attributes.removeWhere((name, _) =>
        !const ['href', 'colspan', 'rowspan', 'alt'].contains(name));
  }
  if (body.text.trim().length < 100) {
    throw const FormatException('Document is empty.');
  }
  return body.innerHtml;
}

Future<bool> showEqualsDocumentDialog(
  BuildContext context, {
  required String kind,
  required String title,
  required String url,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => EqualsDocumentDialog(kind: kind, title: title, url: url),
    ) ??
    false;

class EqualsDocumentDialog extends ConsumerStatefulWidget {
  const EqualsDocumentDialog(
      {super.key, required this.kind, required this.title, required this.url});
  final String kind;
  final String title;
  final String url;

  @override
  ConsumerState<EqualsDocumentDialog> createState() =>
      _EqualsDocumentDialogState();
}

class _EqualsDocumentDialogState extends ConsumerState<EqualsDocumentDialog> {
  final _scroll = ScrollController();
  final _pdf = PdfViewerController();
  bool _reachedBottom = false;
  bool _pdfReady = false;
  bool _pdfFailed = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_checkHtml);
    _pdf.addListener(_checkPdf);
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pdf.removeListener(_checkPdf);
    super.dispose();
  }

  void _markBottom() {
    if (mounted && !_reachedBottom) setState(() => _reachedBottom = true);
  }

  void _checkHtml() {
    if (_scroll.hasClients &&
        _scroll.position.hasContentDimensions &&
        _scroll.position.extentAfter <= 1) {
      _markBottom();
    }
  }

  void _checkPdf() {
    if (_pdfReady &&
        !_pdfFailed &&
        _pdf.isReady &&
        _pdf.visibleRect.bottom >= _pdf.layout.pageLayouts.last.bottom - 1) {
      _markBottom();
    }
  }

  void _retry() {
    setState(() {
      _reachedBottom = false;
      _pdfReady = false;
      _pdfFailed = false;
    });
    ref.invalidate(equalsDocumentProvider(widget.kind));
  }

  Widget _error() => Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(context.tr(
              'The document could not be loaded. Please try again or contact support.')),
          TextButton(onPressed: _retry, child: Text(context.tr('Try again'))),
        ]),
      ));

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(equalsDocumentProvider(widget.kind));
    var valid = false;
    final content = document.when(
      skipLoadingOnRefresh: false,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _error(),
      data: (data) {
        if (data.url != widget.url || data.bytes.isEmpty) return _error();
        if (data.type == 'application/pdf') {
          valid = !_pdfFailed;
          return PdfViewer.data(data.bytes,
              sourceName: data.url,
              controller: _pdf,
              params: PdfViewerParams(
                scrollByMouseWheel: 1.0,
                viewerOverlayBuilder: (context, size, handleLinkTap) => [
                  PdfViewerScrollThumb(
                    key: const Key('equals-document-pdf-scrollbar'),
                    controller: _pdf,
                    orientation: ScrollbarOrientation.right,
                    thumbSize: const Size(32, 48),
                    margin: 4,
                    thumbBuilder: (context, size, pageNumber, controller) =>
                        MouseRegion(
                      cursor: SystemMouseCursors.grab,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: Theme.of(context).colorScheme.onPrimary),
                        ),
                        child: Icon(Icons.drag_handle,
                            color: Theme.of(context).colorScheme.onPrimary,
                            size: 22),
                      ),
                    ),
                  ),
                ],
                onViewerReady: (_, __) {
                  _pdfReady = true;
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) => _checkPdf());
                },
                onDocumentLoadFinished: (_, succeeded) {
                  if (!succeeded) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() {
                          _pdfFailed = true;
                          _reachedBottom = false;
                        });
                      }
                    });
                  }
                },
                errorBannerBuilder: (_, __, ___, ____) => _error(),
              ));
        }
        if (data.type != 'text/html') return _error();
        String markup;
        try {
          markup = equalsDocumentHtml(data.bytes);
        } catch (_) {
          return _error();
        }
        valid = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _checkHtml();
        });
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: SingleChildScrollView(
            key: const Key('equals-document-scroll'),
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            child: HtmlWidget(
              markup,
              baseUrl: Uri.parse(data.url),
              buildAsync: false,
              renderMode: RenderMode.column,
              onTapUrl: (url) async {
                final uri = Uri.tryParse(url);
                if (uri == null ||
                    !const ['https', 'mailto'].contains(uri.scheme)) {
                  return false;
                }
                try {
                  return await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                } catch (_) {
                  return false;
                }
              },
            ),
          ),
        );
      },
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800, maxHeight: 850),
          child: SizedBox(
            width: double.infinity,
            height: MediaQuery.sizeOf(context).height * .88,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
                      child: Row(children: [
                        Expanded(
                            child: Text(context.tr(widget.title),
                                style: Theme.of(context).textTheme.titleLarge)),
                        IconButton(
                            tooltip: context.tr('Close'),
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close)),
                      ])),
                  Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      child: Text(context.tr(
                          'Scroll to the bottom to confirm you have reviewed this document.'))),
                  const Divider(height: 1),
                  Expanded(child: content),
                  const Divider(height: 1),
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton(
                        key: const Key('equals-document-confirm'),
                        onPressed:
                            valid && !document.isLoading && _reachedBottom
                                ? () => Navigator.pop(context, true)
                                : null,
                        child:
                            Text(context.tr('I have reviewed this document')),
                      )),
                ]),
          )),
    );
  }
}
