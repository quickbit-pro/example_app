import 'package:dio/dio.dart';
import '../../../core/widgets/app_states.dart';

String exchangeQuoteError(Object error, {required bool cardDelivery}) {
  var message = friendlyErrorMessage(error).replaceAll('BoomFi', 'ZBX');
  if (message == 'We could not process the Exchange request.' ||
      message == 'We could not complete that request. Please try again.') {
    message = cardDelivery
        ? 'We could not get a quote for conversion and payment card wallet funding. Check the selected currency and network, or turn off wallet funding to request a conversion-only quote.'
        : 'We could not get an exchange quote. Check the amount and selected accounts, then request a new quote.';
  }
  if (error is DioException) {
    final data = error.response?.data;
    final reference = data is Map ? data['traceId'] : null;
    if (reference is String &&
        RegExp(r'^[A-Za-z0-9:_-]{1,100}$').hasMatch(reference)) {
      message += '\nSupport reference: $reference';
    }
  }
  return message;
}
