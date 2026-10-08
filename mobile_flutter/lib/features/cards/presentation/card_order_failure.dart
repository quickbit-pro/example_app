import 'package:dio/dio.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/widgets/app_states.dart';

/// Backend problem code for an order the issuer could not charge.
const cardOrderInsufficientFundsCode = 'mobile.cards.create.insufficient_funds';

/// The order screen's reading of a failed card order.
sealed class CardOrderFailure {
  const CardOrderFailure(this.message);

  /// Customer-facing text, already translated.
  final String message;
}

/// The balance does not cover the card fee; the customer can top up the
/// balance or unload money from an existing card and order again.
final class CardOrderInsufficientFunds extends CardOrderFailure {
  const CardOrderInsufficientFunds(super.message, {this.requiredAmount});

  /// The fee the issuer asked for, e.g. "5.00 USD", when it was reported.
  final String? requiredAmount;
}

/// Any other failure, shown as a plain notice.
final class CardOrderGenericFailure extends CardOrderFailure {
  const CardOrderGenericFailure(super.message);
}

final _requiredAmountPattern =
    RegExp(r'card fee of (\d[\d,]*(?:\.\d+)? [A-Z]{3})');

CardOrderFailure describeCardOrderFailure(
    Object error, AppLocalizations translations) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map && data['code'] == cardOrderInsufficientFundsCode) {
      final title = data['title']?.toString() ?? '';
      final amount = _requiredAmountPattern.firstMatch(title)?.group(1);
      final message = amount == null
          ? translations.translate(
              'Your balance does not cover the card fee. Top up your balance or unload a card, then order again.')
          : translations.translate(
              'Your balance does not cover the card fee of {p0}. Top up your balance or unload a card, then order again.',
              {'p0': amount});
      return CardOrderInsufficientFunds(message, requiredAmount: amount);
    }
  }
  return CardOrderGenericFailure(
      translations.translate(friendlyErrorMessage(error)));
}
