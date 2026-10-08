import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'transaction_pdf_delivery.dart';

TransactionPdfDelivery prepareTransactionPdf(Uint8List bytes, String fileName,
        {web.Window? browserWindow}) =>
    _WebPdfDelivery(bytes, fileName, browserWindow ?? web.window);

class _WebPdfDelivery implements TransactionPdfDelivery {
  _WebPdfDelivery(Uint8List bytes, this.fileName, this._window) {
    final file = web.File([bytes.toJS].toJS, fileName,
        web.FilePropertyBag(type: 'application/pdf'));
    _data = web.ShareData(files: [file].toJS);
    _url = web.URL.createObjectURL(file);
  }

  final String fileName;
  final web.Window _window;
  late final web.ShareData _data;
  late final String _url;
  bool _disposed = false;

  @override
  bool get canShare {
    // Unsupported browsers may not expose canShare at all.
    try {
      return _window.navigator.canShare(_data);
    } catch (_) {
      return false;
    }
  }

  @override
  bool open() {
    final viewer = _window.open(_url, '_blank');
    if (viewer == null) return false;
    viewer.opener = null;
    return true;
  }

  @override
  void download() {
    final anchor = web.HTMLAnchorElement()
      ..href = _url
      ..download = fileName
      ..rel = 'noopener'
      ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    try {
      anchor.click();
    } finally {
      anchor.remove();
    }
  }

  @override
  Future<bool> share() async {
    try {
      // No await before share: Android requires a fresh user gesture.
      await _window.navigator.share(_data).toDart;
      return true;
    } catch (error) {
      if (error is web.DOMException && error.name == 'AbortError') return false;
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Allow an opened PDF viewer/download to finish reading after dismissal.
    Timer(const Duration(minutes: 10), () => web.URL.revokeObjectURL(_url));
  }
}

Future<bool> saveTransactionPdf(Uint8List bytes, String fileName) async {
  final document = prepareTransactionPdf(bytes, fileName);
  try {
    document.download();
    return true;
  } finally {
    document.dispose();
  }
}
