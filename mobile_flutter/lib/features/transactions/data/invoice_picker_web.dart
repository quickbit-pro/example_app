import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'invoice_file.dart';

class InvoicePicker {
  InvoicePicker({this.openDialog});
  final void Function(web.HTMLInputElement)? openDialog;
  Future<InvoiceFile?> pick({required bool camera}) async {
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = camera
          ? 'image/*'
          : '.jpg,.jpeg,.png,.webp,.pdf,image/jpeg,image/png,image/webp,application/pdf'
      ..style.display = 'none';
    input.setAttribute('data-invoice-picker', 'true');
    if (camera) input.setAttribute('capture', 'environment');
    final result = Completer<InvoiceFile?>();
    // Keep the input attached until change/cancel. Window focus is not cancellation:
    // phone photo pickers can return focus before the selected file is ready.
    bool reading = false;
    Future<void> readFile() async {
      if (result.isCompleted || reading) return;
      reading = true;
      try {
        final file = input.files?.item(0);
        if (file == null) {
          result.complete(null);
          return;
        }
        if (file.size == 0 || file.size > 10 * 1024 * 1024) {
          throw const FormatException('Choose an invoice up to 10 MB.');
        }
        final bytes = (await file.arrayBuffer().toDart).toDart.asUint8List();
        if (!result.isCompleted) result.complete(InvoiceFile(bytes, file.name));
      } catch (error, stack) {
        if (!result.isCompleted) result.completeError(error, stack);
      }
    }

    input.onchange = ((web.Event _) {
      unawaited(readFile());
    }).toJS;
    input.oncancel = ((web.Event _) {
      if (!result.isCompleted && !reading) result.complete(null);
    }).toJS;
    input.onerror = ((web.Event _) {
      if (!result.isCompleted) {
        result.completeError(const FormatException(
            'Could not read this photo. Try Choose file.'));
      }
    }).toJS;
    web.document.body!.appendChild(input);
    try {
      if (openDialog == null) {
        input.click();
      } else {
        openDialog!(input);
      }
      return await result.future.timeout(const Duration(minutes: 5),
          onTimeout: () => throw const FormatException(
              'File selection timed out. Please choose your invoice again.'));
    } finally {
      input.onchange = null;
      input.oncancel = null;
      input.onerror = null;
      input.remove();
    }
  }
}
