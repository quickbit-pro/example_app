import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:flutter_stripe_web/flutter_stripe_web.dart';

Future<bool> showOnboardingPayment(BuildContext context,
    {required String publishableKey, required String clientSecret}) async {
  Stripe.publishableKey = publishableKey;
  await Stripe.instance.applySettings();
  if (!context.mounted) return false;
  return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _StripeDialog(clientSecret: clientSecret)) ??
      false;
}

class _StripeDialog extends StatefulWidget {
  const _StripeDialog({required this.clientSecret});
  final String clientSecret;
  @override
  State<_StripeDialog> createState() => _StripeDialogState();
}

class _StripeDialogState extends State<_StripeDialog> {
  bool _complete = false;
  bool _busy = false;
  String? _error;
  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await WebStripe.instance.confirmPaymentElement(
          ConfirmPaymentElementOptions(
              confirmParams: ConfirmPaymentParams(
                  return_url: Uri.base.replace(query: '').toString()),
              redirect: PaymentConfirmationRedirect.ifRequired));
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Payment could not be confirmed. Check your details and try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: AlertDialog(
          title: const Text('Secure card payment'),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                PaymentElement(
                    clientSecret: widget.clientSecret,
                    onCardChanged: (details) =>
                        setState(() => _complete = details?.complete == true)),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: _busy || !_complete ? null : _confirm,
                child:
                    Text(_busy ? 'Confirming payment…' : 'Pay and continue')),
          ]));
}
