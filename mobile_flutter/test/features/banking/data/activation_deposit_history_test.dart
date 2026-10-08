import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';

void main() {
  test('first deposit can be outside Home history and on a later page',
      () async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests.add(request.queryParameters);
        final page = request.queryParameters['page'] as int;
        handler.resolve(Response(requestOptions: request, data: {
          'data': [
            {
              'id': 'deposit-$page',
              'type': 'deposit',
              'amount': 25,
              'currency': 'USD',
              'status': page == 1 ? 'pending' : 'completed',
              'transactionDate': '2025-01-01T12:00:00Z'
            }
          ],
          'pagination': {'page': page, 'hasNext': page == 1},
        }));
      }));
    expect(await MobileBankingApi(dio).hasCompletedDeposit(), isTrue);
    expect(requests.length, 2);
    expect(
        requests
            .every((q) => q['types'] == 'deposit' && !q.containsKey('from')),
        isTrue);
  });
  test('pending deposits and internal card loads cannot complete first deposit',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        handler.resolve(Response(requestOptions: request, data: {
          'data': [
            {
              'id': 'pending',
              'type': 'crypto_deposit',
              'amount': 25,
              'currency': 'USDT',
              'status': 'pending'
            },
            {
              'id': 'load',
              'type': 'card_topup',
              'amount': 25,
              'currency': 'USD',
              'status': 'completed'
            },
          ],
          'pagination': {'hasNext': false},
        }));
      }));
    expect(await MobileBankingApi(dio).hasCompletedDeposit(), isFalse);
  });
  test('history outage stays unknown instead of reporting no deposit',
      () async {
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
          onRequest: (request, handler) =>
              handler.reject(DioException(requestOptions: request))));
    await expectLater(MobileBankingApi(dio).hasCompletedDeposit(),
        throwsA(isA<DioException>()));
  });
}
