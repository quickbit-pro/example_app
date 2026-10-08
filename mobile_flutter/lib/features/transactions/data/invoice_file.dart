import 'dart:typed_data';

class InvoiceFile {
  const InvoiceFile(this.bytes, this.filename);
  final Uint8List bytes;
  final String filename;
}
