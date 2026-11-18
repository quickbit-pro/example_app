import 'package:dio/dio.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/l10n/message_format.dart';

String exchangeQuoteError(Object error,
    {required bool cardDelivery,
    String Function(String, [Map<String, Object?>]) translate =
        formatAppMessage}) {
  var message = friendlyErrorMessage(error);
  if (message == 'We could not process the Exchange request.' ||
      message == 'We could not complete that request. Please try again.') {
    message = cardDelivery
        ? 'We could not get a quote for conversion and payment card wallet funding. Check the selected currency and network, or turn off wallet funding to request a conversion-only quote.'
        : 'We could not get an exchange quote. Check the amount and selected accounts, then request a new quote.';
  }
  message = translate(message);
  if (error is DioException) {
    final data = error.response?.data;
    final reference = data is Map ? data['traceId'] : null;
    if (reference is String &&
        RegExp(r'^[A-Za-z0-9:_-]{1,100}$').hasMatch(reference)) {
      message += '\n${translate('Support reference')}: $reference';
    }
  }
  return message;
}
