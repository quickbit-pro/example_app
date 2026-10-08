import 'dart:typed_data';

import 'transaction_pdf_delivery.dart';

TransactionPdfDelivery prepareTransactionPdf(
        Uint8List bytes, String fileName) =>
    throw UnsupportedError('Browser PDF actions are unavailable.');

Future<bool> saveTransactionPdf(Uint8List bytes, String fileName) =>
    Future.error(UnsupportedError('PDF download is unavailable.'));
