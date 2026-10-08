import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

const defaultEqualsPaymentServicesDisclosure =
    'Hoppacard Holding BV, registered address Beemdstraat 5, 5653MA Eindhoven. '
    'Company registered in The Netherlands. Equals Money Plc is authorised as a '
    'Payment Institution by the Financial Conduct Authority (FCA) with Firm '
    'Reference Number (FRN) 488396. Company registered in England & Wales No. '
    '05539698. Registered Office: 3rd Floor, Vintners’ Place, 68 Upper Thames St, '
    'London, EC4V 3BJ. Cards are issued by Equals Money International Limited '
    'pursuant to licence by Mastercard International Inc. Equals Money International '
    'Limited is authorised as an Electronic Money Institution by the FCA with FRN '
    '900493. Mastercard is a registered trademark, and the circles design is a '
    'trademark of Mastercard International Incorporated.';

const _euCountryCodes = {
  'AT',
  'BE',
  'BG',
  'HR',
  'CY',
  'CZ',
  'DK',
  'EE',
  'FI',
  'FR',
  'DE',
  'GR',
  'HU',
  'IE',
  'IT',
  'LV',
  'LT',
  'LU',
  'MT',
  'NL',
  'PL',
  'PT',
  'RO',
  'SK',
  'SI',
  'ES',
  'SE',
};

String resolveEqualsPaymentServicesDisclosure({
  required String localeCountryCode,
  required String defaultRegion,
  String? euDisclosure,
  String? ukDisclosure,
}) {
  final country = localeCountryCode.trim().toUpperCase();
  final useEu = country.isNotEmpty
      ? _euCountryCodes.contains(country)
      : defaultRegion.trim().toUpperCase() != 'UK';
  final configured = useEu ? euDisclosure : ukDisclosure;
  final text = configured?.trim().isNotEmpty == true
      ? configured!.trim()
      : defaultEqualsPaymentServicesDisclosure;
  return text.toUpperCase().startsWith('FIAT ACCOUNTS')
      ? text
      : 'FIAT ACCOUNTS: $text';
}

Future<void> showPaymentServicesDisclosure(
  BuildContext context, {
  required String disclosure,
}) =>
    showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Payment Services Disclosure')),
            leading: Builder(
              builder: (dialogContext) => IconButton(
                tooltip: context.tr('Close'),
                onPressed: () => Navigator.of(dialogContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 100),
            children: [
              const Icon(Icons.account_balance_outlined, size: 44),
              const SizedBox(height: 20),
              Text(
                disclosure,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      height: 1.65,
                    ),
              ),
            ],
          ),
        ),
      ),
    );

class PaymentServicesDisclosureButton extends StatelessWidget {
  const PaymentServicesDisclosureButton({required this.disclosure, super.key});

  final String disclosure;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.info_outline_rounded),
        title: Text(context.tr('Payment Services Disclosure')),
        subtitle: Text(context.tr('Regulatory information')),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => showPaymentServicesDisclosure(
          context,
          disclosure: disclosure,
        ),
      );
}
