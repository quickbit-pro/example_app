import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'invoice_file.dart';

class InvoicePicker {
  Future<InvoiceFile?> pick({required bool camera}) async {
    if (camera) {
      final file = await ImagePicker().pickImage(source: ImageSource.camera);
      if (file == null) return null;
      if (await file.length() > 10 * 1024 * 1024) {
        throw const FormatException('Choose an invoice up to 10 MB.');
      }
      return InvoiceFile(await file.readAsBytes(), file.name);
    }
    final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
        withData: true);
    if (result == null) return null;
    final file = result.files.single;
    if (file.size > 10 * 1024 * 1024) {
      throw const FormatException('Choose an invoice up to 10 MB.');
    }
    if (file.bytes == null) {
      throw const FormatException(
          'Could not read this file. Please choose it again.');
    }
    return InvoiceFile(file.bytes!, file.name);
  }
}
