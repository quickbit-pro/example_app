import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'exchange_support.dart';
import 'sepa_deposit_qr.dart';
import '../../../core/l10n/app_localizations.dart';

class ExchangeBankDepositDetails extends StatelessWidget {
  const ExchangeBankDepositDetails({super.key, required this.account, this.onAddPayee});
  final Map<String, dynamic> account;
  final VoidCallback? onAddPayee;

  @override
  Widget build(BuildContext context) {
    final bank = exchangeMap(exchangeValue(account, 'bank'));
    final iban = exchangeText(account, 'address');
    final beneficiary = exchangeText(bank, 'accountHolderName');
    final bic = exchangeText(bank, 'bic');
    // Account reference is an internal identifier, not a transfer reference.
    final reference = exchangeText(account, 'paymentReference');
    final currencies = exchangeValue(account, 'currencies') as List? ?? [];
    final qr = currencies.any((v) => '$v'.toUpperCase() == 'EUR')
        ? sepaDepositQr(
            iban: iban,
            beneficiary: beneficiary,
            bic: bic,
            paymentReference: reference)
        : null;
    final fields = <String, String>{
      'Account holder': beneficiary,
      'IBAN': iban,
      'BIC / SWIFT': bic,
      'Bank': exchangeText(bank, 'name'),
      'Bank country': exchangeText(bank, 'country'),
      'Bank address': exchangeText(bank, 'address'),
      'Payment reference': reference,
    }..removeWhere((_, value) => value.trim().isEmpty);
    Future<void> copy(String value) async {
      await Clipboard.setData(ClipboardData(text: value));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Bank details copied')));
      }
    }

    final details =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final field in fields.entries)
        Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr(field.key), style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: SelectableText(field.value, style: Theme.of(context).textTheme.bodyMedium)),
                IconButton(tooltip: context.tr('Copy {p0}', {'p0': context.tr(field.key)}),
                  onPressed: () => copy(field.value), icon: const Icon(Icons.copy_outlined, size: 18)),
              ]),
            ])),
      Wrap(spacing: 8, runSpacing: 8, children: [
        if (onAddPayee != null && qr != null)
          FilledButton.icon(onPressed: onAddPayee,
            icon: const Icon(Icons.person_add_alt), label: Text(context.tr('Add to Equals payees'))),
        OutlinedButton.icon(
            onPressed: () => copy(iban),
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: const Text('Copy IBAN')),
        OutlinedButton.icon(
            onPressed: () => copy(
                fields.entries.map((e) => '${e.key}: ${e.value}').join('\n')),
            icon: const Icon(Icons.copy_all_outlined, size: 18),
            label: const Text('Copy bank details')),
      ]),
    ]);
    final code = qr == null
        ? null
        : SizedBox(
            width: 232,
            child: Column(children: [
              Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.white,
                  child: Semantics(
                      label: 'SEPA bank transfer QR code',
                      image: true,
                      child: QrImageView(
                          data: qr,
                          size: 200,
                          padding: EdgeInsets.zero,
                          errorCorrectionLevel: QrErrorCorrectLevel.M,
                          eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square, color: Colors.black),
                          dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black)))),
              const SizedBox(height: 12),
              Text('Scan to deposit EUR',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              const Text(
                  'Scan with a banking app that supports SEPA QR payments. Enter the amount and review the details in your bank app.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('If scanning isn’t supported, copy the bank details.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ]));
    return LayoutBuilder(builder: (context, constraints) {
      if (code == null) return details;
      if (constraints.maxWidth >= 620) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: details),
          const SizedBox(width: 24),
          code
        ]);
      }
      return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [details, const SizedBox(height: 24), Center(child: code)]);
    });
  }
}
