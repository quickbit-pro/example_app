import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';

/// File contents work on both native platforms and the browser, where paths
/// are unavailable. Create a fresh multipart file for each HTTP attempt.
class UploadDocument {
  UploadDocument.fromPlatformFile(PlatformFile file)
      : name = file.name,
        bytes = file.bytes ?? Uint8List(0) {
    if (!mimeTypes.containsKey(file.extension?.toLowerCase())) {
      throw const FormatException('Choose a PDF, JPG, JPEG, or PNG file.');
    }
    if (bytes.isEmpty) {
      throw const FormatException(
          'The file could not be read. Please choose it again.');
    }
    if (bytes.length > maxBytes) {
      throw const FormatException('Choose a file smaller than 10 MB.');
    }
  }

  static const maxBytes = 10 * 1024 * 1024;
  static const mimeTypes = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
  };
  final String name;
  final Uint8List bytes;

  MultipartFile toMultipartFile() => MultipartFile.fromBytes(
        bytes,
        filename: name,
        contentType:
            DioMediaType.parse(mimeTypes[name.split('.').last.toLowerCase()]!),
      );
}
