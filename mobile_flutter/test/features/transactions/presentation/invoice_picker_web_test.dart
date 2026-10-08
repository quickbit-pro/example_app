@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:mobile_flutter/features/transactions/data/invoice_picker_web.dart';

void main() {
  test('returning window focus cannot discard a delayed photo selection',
      () async {
    late web.HTMLInputElement input;
    final picker = InvoicePicker(openDialog: (element) => input = element);
    var completed = false;
    final pending = picker.pick(camera: false)..then((_) => completed = true);
    web.window.dispatchEvent(web.Event('focus'));
    await Future<void>.delayed(const Duration(milliseconds: 1300));
    expect(completed, isFalse);
    expect(input.isConnected, isTrue);
    final data = web.DataTransfer();
    data.items.add(web.File(
        [
          Uint8List.fromList([1, 2, 3]).toJS
        ].toJS,
        'photo.png',
        web.FilePropertyBag(type: 'image/png')));
    input.files = data.files;
    input.dispatchEvent(web.Event('change'));
    final file = await pending;
    expect(file!.filename, 'photo.png');
    expect(file.bytes, [1, 2, 3]);
    expect(input.isConnected, isFalse);
  });
  test('camera capture and cancellation leave no stale file input', () async {
    late web.HTMLInputElement input;
    final pending = InvoicePicker(openDialog: (element) => input = element)
        .pick(camera: true);
    expect(input.getAttribute('capture'), 'environment');
    input.dispatchEvent(web.Event('cancel'));
    expect(await pending, isNull);
    expect(input.isConnected, isFalse);
  });
}
