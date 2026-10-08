import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api/dio_provider.dart';
import '../api/auth_token_provider.dart';

final documentApiProvider =
    Provider((ref) => DocumentApi(ref.watch(dioProvider)));
final originalDocumentProvider =
    FutureProvider.autoDispose.family<Uint8List, String>((ref, id) {
  ref.watch(authSessionGenerationProvider);
  final cancel = CancelToken();
  ref.onDispose(() => cancel.cancel());
  return ref.watch(documentApiProvider).download(id, cancelToken: cancel);
});

class DocumentApi {
  DocumentApi(this.dio);
  final Dio dio;
  static const base = '/api/v1/mobile/documents';
  Future<String> upload(
      {required Uint8List bytes, required String filename}) async {
    final response = await dio.post<Map<String, dynamic>>(base,
        data: FormData.fromMap(
            {'file': MultipartFile.fromBytes(bytes, filename: filename)}),
        options: Options(
            sendTimeout: const Duration(seconds: 90),
            receiveTimeout: const Duration(seconds: 90),
            extra: {'sensitiveRequest': true}));
    final id = response.data?['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
          'The original document could not be saved. Please try again.');
    }
    return id;
  }

  Future<Uint8List> download(String id, {CancelToken? cancelToken}) async {
    final response = await dio.get<List<int>>(
        '$base/${Uri.encodeComponent(id)}/content',
        cancelToken: cancelToken,
        options: Options(
            responseType: ResponseType.bytes,
            extra: {'sensitiveRequest': true}));
    return Uint8List.fromList(response.data!);
  }
}
