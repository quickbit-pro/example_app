import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

Future<bool> showOnboardingPayment(BuildContext context,
    {required String publishableKey, required String clientSecret}) async {
  Stripe.publishableKey = publishableKey;
  await Stripe.instance.applySettings();
  await Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'Account onboarding',
          style: ThemeMode.system));
  try {
    await Stripe.instance.presentPaymentSheet();
    // Only the server's webhook-confirmed status can unlock onboarding.
    return true;
  } on StripeException catch (error) {
    if (error.error.code == FailureCode.Canceled) return false;
    rethrow;
  }
}
