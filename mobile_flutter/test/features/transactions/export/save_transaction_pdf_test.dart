import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/transactions/export/save_transaction_pdf_io.dart';

class _SavePicker extends FilePicker {
  _SavePicker(this.destination);

  final String? destination;
  Uint8List? receivedBytes;
  String? receivedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    receivedBytes = bytes;
    receivedName = fileName;
    return destination;
  }
}

void main() {
  test('cancelled save remains cancelled without writing a file', () async {
    final picker = _SavePicker(null);
    FilePicker.platform = picker;
    final bytes = Uint8List.fromList([37, 80, 68, 70]);
    expect(await saveTransactionPdf(bytes, 'activity.pdf'), isFalse);
    expect(picker.receivedBytes, same(bytes));
    expect(picker.receivedName, 'activity.pdf');
  });

  test('desktop save writes the PDF bytes to the user-selected path', () async {
    final directory = await Directory.systemTemp.createTemp('example-pdf-save-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/activity.pdf');
    FilePicker.platform = _SavePicker(file.path);
    final bytes = Uint8List.fromList([37, 80, 68, 70, 45, 49, 46, 55]);
    expect(await saveTransactionPdf(bytes, 'activity.pdf'), isTrue);
    expect(await file.readAsBytes(), bytes);
  });
}
