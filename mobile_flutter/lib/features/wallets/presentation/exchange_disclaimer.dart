import 'package:flutter/material.dart';
import 'exchange_support.dart';
import 'exchange_reference_data.dart';

// Wording shared with the dashboard's crypto-services-disclaimer.tsx.
const cryptoServicesDisclaimer =
    r'''Crypto-asset exchange services are provided by Zillion Bits Ltd (ZBX), a company registered in Malta under Company Registration No. C 88757 and authorised by the Malta Financial Services Authority (MFSA) as a Crypto-Asset Service Provider (CASP) under the EU Markets in Crypto-Assets Regulation (MiCAR), Authorisation ID ZBL-24354. ZBX is additionally authorised to provide payment services in relation to Electronic Money Tokens (EMTs) under Authorisation ID ZBL-28410.

All crypto exchange transactions, including the exchange of crypto-assets for fiat funds and crypto-assets for other crypto-assets, are executed by ZBX. Fiat and crypto assets associated with these exchange operations are held, safeguarded or custodied by ZBX and/or its appointed regulated banking, payment and custody partners, as applicable.

Hoppa Global / Hoppacard acts solely as the technology, integration and facilitation layer and does not execute crypto exchange transactions or hold, safeguard or custody customer fiat or crypto assets.''';

class ExchangeDisclaimer extends StatelessWidget {
  const ExchangeDisclaimer({super.key});

  void _show(BuildContext context, String title, String text) =>
      showDialog<void>(
          context: context,
          builder: (context) => ExchangeDialog(
              title: title,
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'))
              ],
              child: SelectableText(text,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.5))));

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, children: [
        TextButton.icon(
            icon: const Icon(Icons.info_outline, size: 18),
            onPressed: () => _show(context, 'Crypto Services Disclaimer',
                cryptoServicesDisclaimer),
            label: const Text('Crypto Services Disclaimer')),
        TextButton(
            onPressed: () => _show(context,
                'Crypto Exchange — Terms & Disclosures', exchangeTerms),
            child: const Text('ZBX Terms & Risk Disclosure')),
      ]);
}
