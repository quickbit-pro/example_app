import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_quote_error.dart';

void main() {
  DioException failure(String title, String trace) => DioException(
      requestOptions: RequestOptions(path: '/quote'),
      response: Response(
          requestOptions: RequestOptions(path: '/quote'),
          statusCode: 400,
          data: {'title': title, 'traceId': trace}));
  test(
      'generic delivery error explains next action and includes support reference',
      () {
    final text = exchangeQuoteError(
        failure('We could not process the Exchange request.', 'req-123'),
        cardDelivery: true);
    expect(text, contains('conversion-only quote'));
    expect(text, contains('Support reference: req-123'));
    expect(text, isNot(contains('insufficient')));
  });
  test('specific reason survives and unsafe support references are omitted',
      () {
    final text = exchangeQuoteError(
        failure('Minimum withdrawal is 10 USDC.', 'https://secret.invalid'),
        cardDelivery: true);
    expect(text, 'Minimum withdrawal is 10 USDC.');
  });
}
