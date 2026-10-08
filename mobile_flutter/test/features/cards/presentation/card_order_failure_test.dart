import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/features/cards/presentation/card_order_failure.dart';

void main() {
  const en = AppLocalizations(Locale('en'), {});
  DioException failure(int status, Object? data) {
    final request = RequestOptions(path: '/api/v1/mobile/cards');
    return DioException(
        requestOptions: request,
        response:
            Response(requestOptions: request, statusCode: status, data: data));
  }

  test('insufficient funds carries the required amount and both remedies', () {
    final result = describeCardOrderFailure(
        failure(422, {
          'code': cardOrderInsufficientFundsCode,
          'title':
              'Your balance does not cover the card fee of 5.00 USD. Top up your balance or unload a card, then order again.',
        }),
        en);

    final funds = result as CardOrderInsufficientFunds;
    expect(funds.requiredAmount, '5.00 USD');
    expect(funds.message, contains('5.00 USD'));
    expect(funds.message, contains('unload a card'));
  });

  test('insufficient funds without a reported amount still names the remedies',
      () {
    final result = describeCardOrderFailure(
        failure(422, {
          'code': cardOrderInsufficientFundsCode,
          'title': 'Your balance does not cover the card fee.',
        }),
        en);

    final funds = result as CardOrderInsufficientFunds;
    expect(funds.requiredAmount, isNull);
    expect(funds.message, contains('Top up your balance'));
  });

  test('other refusals stay generic notices with the backend title', () {
    final result = describeCardOrderFailure(
        failure(422, {
          'code': 'mobile.cards.create.phone_required',
          'title': 'A phone number is required to order a card.',
        }),
        en);

    expect(result, isA<CardOrderGenericFailure>());
    expect(result.message, 'A phone number is required to order a card.');
  });
}
