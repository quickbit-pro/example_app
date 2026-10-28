import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_provider.dart';

final equalsPaymentConfirmationApiProvider =
    Provider((ref) => EqualsPaymentConfirmationApi(ref.watch(dioProvider)));

class EqualsPaymentConfirmationApi {
  EqualsPaymentConfirmationApi(this.dio);
  final Dio dio;

  Future<Uint8List> download(String transactionId,
      {CancelToken? cancelToken}) async {
    if (!RegExp(r'^[1-9][0-9]*$').hasMatch(transactionId)) {
      throw const FormatException('Invalid transaction.');
    }
    final response = await dio.get<List<int>>(
      '/api/v1/mobile/transactions/$transactionId/equals-money/payment-confirmation',
      cancelToken: cancelToken,
      options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
          extra: {'sensitiveRequest': true}),
    );
    final bytes = Uint8List.fromList(response.data ?? const []);
    if (bytes.length < 5 || String.fromCharCodes(bytes.take(5)) != '%PDF-') {
      throw const FormatException('The payment confirmation was not a PDF.');
    }
    return bytes;
  }
}
