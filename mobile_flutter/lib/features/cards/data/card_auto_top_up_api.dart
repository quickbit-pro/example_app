import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/dio_provider.dart';

final cardAutoTopUpApiProvider =
    Provider((ref) => CardAutoTopUpApi(ref.watch(dioProvider)));

class CardAutoTopUpApi {
  const CardAutoTopUpApi(this.dio);
  final Dio dio;
  Future<Map<String, dynamic>> load(String cardId) async =>
      _settings(await dio.get<Map<String, dynamic>>(
          '/api/v1/mobile/cards/${Uri.encodeComponent(cardId)}/auto-topup'));
  Future<Map<String, dynamic>> save(
      String mode, Map<String, dynamic> settings) async {
    if (!const {'low-balance', 'failed-tx', 'deposit'}.contains(mode)) {
      throw ArgumentError.value(mode);
    }
    return _settings(await dio.post<Map<String, dynamic>>(
        '/api/v1/mobile/cards/auto-topup/$mode',
        data: settings));
  }

  Map<String, dynamic> _settings(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null || data['success'] != true) {
      throw StateError(data?['message']?.toString() ??
          'Automatic top-up settings could not be loaded.');
    }
    return data;
  }
}
