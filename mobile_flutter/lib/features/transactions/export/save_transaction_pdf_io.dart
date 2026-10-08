import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'transaction_pdf_delivery.dart';

TransactionPdfDelivery prepareTransactionPdf(
        Uint8List bytes, String fileName) =>
    throw UnsupportedError('Browser PDF actions are unavailable.');

Future<bool> saveTransactionPdf(Uint8List bytes, String fileName) async {
  final location = await FilePicker.platform.saveFile(
    dialogTitle: 'Save PDF',
    fileName: fileName,
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    bytes: bytes,
  );
  if (location == null) return false;
  // The mobile plugin writes the bytes to the user-selected document URI.
  // Desktop pickers return a path only, which the app must then write.
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(location).writeAsBytes(bytes, flush: true);
  }
  return true;
}
