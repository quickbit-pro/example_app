import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/api/auth_token_provider.dart';

final transactionDocumentsApiProvider =
    Provider((ref) => TransactionDocumentsApi(ref.watch(dioProvider)));
final transactionDocumentsProvider = FutureProvider.autoDispose
    .family<List<TransactionDocument>, String>((ref, id) {
  ref.watch(authSessionGenerationProvider);
  final cancel = CancelToken();
  ref.onDispose(() => cancel.cancel());
  return ref
      .watch(transactionDocumentsApiProvider)
      .list(id, cancelToken: cancel);
});

class TransactionDocument {
  const TransactionDocument(
      {required this.id,
      required this.documentId,
      required this.filename,
      required this.contentType,
      required this.byteLength});
  factory TransactionDocument.fromJson(Map<String, dynamic> json) {
    final document = json['document'] as Map<String, dynamic>;
    return TransactionDocument(
        id: json['id'] as String,
        documentId: document['id'] as String,
        filename: document['fileName'] as String,
        contentType: document['contentType'] as String,
        byteLength: (document['byteLength'] as num).toInt());
  }
  final String id, documentId, filename, contentType;
  final int byteLength;
  bool get isPdf => contentType == 'application/pdf';
}

class TransactionDocumentsApi {
  TransactionDocumentsApi(this.dio);
  final Dio dio;
  static const base = '/api/v1/mobile/transaction-documents';
  Options get _options => Options(extra: {'sensitiveRequest': true});
  Future<List<TransactionDocument>> list(String transactionId,
      {CancelToken? cancelToken}) async {
    final response = await dio.get<List<dynamic>>(base,
        queryParameters: {'transactionId': transactionId},
        options: _options,
        cancelToken: cancelToken);
    return (response.data ?? [])
        .map((row) =>
            TransactionDocument.fromJson(Map<String, dynamic>.from(row as Map)))
        .toList();
  }

  Future<void> attach(String transactionId, String documentId) async {
    await dio.post(base,
        data: {'transactionId': transactionId, 'documentId': documentId},
        options: _options);
  }

  Future<void> remove(String id) async =>
      dio.delete<void>('$base/${Uri.encodeComponent(id)}', options: _options);
}
