import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/application/platform_providers.dart';
import '../../../core/widgets/app_states.dart';
import 'exchange_support.dart';
import 'exchange_deposit_address.dart';
import 'exchange_disclaimer.dart';

class ExchangeDestinationForm extends ConsumerStatefulWidget {
  const ExchangeDestinationForm({super.key, required this.bank});
  final bool bank;
  @override
  ConsumerState<ExchangeDestinationForm> createState() =>
      _ExchangeDestinationFormState();
}

class _ExchangeDestinationFormState
    extends ConsumerState<ExchangeDestinationForm> {
  Map<String, dynamic> bank = {'beneficiaryType': 'individual'};
  String name = '', address = '', currency = 'USDT';
  int chain = 1;
  bool confirmed = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    if (widget.bank) currency = 'EUR';
  }

  bool get addressValid => chain == -200
      ? address.startsWith('T') &&
          exchangeDepositAddress(chain, address) == address
      : RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address);
  bool get complete =>
      confirmed &&
      (widget.bank
          ? exchangeBankComplete(bank) &&
              (bank['accountNumber'] as String)
                  .startsWith(bank['country'] as String)
          : name.trim().isNotEmpty && name.length <= 100 && addressValid);

  Future<void> save() async {
    if (busy || !complete) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = ref.read(mobilePlatformApiProvider);
      final result = widget.bank
          ? await api.registerExchangeBank({
              'name': bank['name'],
              'currency': currency,
              'account_number': bank['accountNumber'],
              'bank_name': bank['bankName'],
              'account_holder_name': bank['accountHolderName'],
              'country': bank['country'],
              'beneficiary_type': bank['beneficiaryType'],
              if (bank['beneficiaryType'] == 'individual') ...{
                'first_name': bank['firstName'],
                'last_name': bank['lastName']
              },
            })
          : await api.registerExchangeCrypto({
              'name': name.trim(),
              'currency': currency,
              'chain_id': chain,
              'address': address
            });
      final id = int.tryParse(exchangeText(result, 'id'));
      if (id == null || id <= 0) {
        throw StateError(
            'The provider has not confirmed the saved destination. Refresh your destinations before retrying.');
      }
      if (mounted) {
        Navigator.pop(context, <String, dynamic>{
          ...result,
          'type': widget.bank ? 'Fiat' : 'Digital',
          'name': exchangeText(result, 'name').isEmpty
              ? (widget.bank ? bank['name'] : name.trim())
              : exchangeText(result, 'name'),
          'currencies': [currency],
          'chainId': widget.bank ? 0 : chain,
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !busy,
        child: ExchangeDialog(
          title: widget.bank ? 'Add bank account' : 'Add crypto address',
          subtitle:
              'Save a destination for future withdrawals. Saving does not transfer any funds.',
          actions: [
            TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('Cancel')),
            FilledButton(
                key: const ValueKey('save-exchange-destination'),
                onPressed: busy || !complete ? null : save,
                child: Text(busy ? 'Saving…' : 'Save destination')),
          ],
          child: ExchangeFormColumn(children: [
            if (error != null) ExchangeNotice(error!, isError: true),
            if (busy) const LinearProgressIndicator(),
            DropdownButtonFormField<String>(
              initialValue: currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: [
                for (final value
                    in widget.bank ? ['EUR', 'USD', 'GBP'] : ['USDC', 'USDT'])
                  DropdownMenuItem(value: value, child: Text(value))
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() {
                        currency = value!;
                        confirmed = false;
                      }),
            ),
            if (widget.bank)
              ExchangeBankFields(
                  value: bank,
                  enabled: !busy,
                  onChanged: (value) => setState(() {
                        bank = value;
                        confirmed = false;
                      }))
            else ...[
              TextFormField(
                  key: const ValueKey('destination-name'),
                  enabled: !busy,
                  maxLength: 100,
                  decoration:
                      const InputDecoration(labelText: 'Destination name'),
                  onChanged: (value) => setState(() {
                        name = value;
                        confirmed = false;
                      })),
              DropdownButtonFormField<int>(
                  initialValue: chain,
                  decoration: const InputDecoration(labelText: 'Network'),
                  items: const [
                    DropdownMenuItem(value: 1, child: Text('Ethereum (ERC20)')),
                    DropdownMenuItem(value: -200, child: Text('Tron (TRC20)')),
                    DropdownMenuItem(value: 137, child: Text('Polygon')),
                    DropdownMenuItem(value: 42161, child: Text('Arbitrum'))
                  ],
                  onChanged: busy
                      ? null
                      : (value) => setState(() {
                            chain = value!;
                            confirmed = false;
                          })),
              TextFormField(
                  key: const ValueKey('destination-address'),
                  enabled: !busy,
                  minLines: 1,
                  maxLines: 3,
                  autocorrect: false,
                  decoration: InputDecoration(
                      labelText: 'Wallet address',
                      errorText: address.isNotEmpty && !addressValid
                          ? 'Enter a valid address for the selected network.'
                          : null),
                  onChanged: (value) => setState(() {
                        address = value.trim();
                        confirmed = false;
                      })),
              const ExchangeNotice(
                  'Always check the recipient address and network before withdrawing. Transfers to the wrong address or network may be irreversible.'),
            ],
            CheckboxListTile(
                key: const ValueKey('confirm-destination-details'),
                contentPadding: EdgeInsets.zero,
                value: confirmed,
                onChanged: busy
                    ? null
                    : (value) => setState(() => confirmed = value == true),
                title:
                    const Text('I confirm the recipient details are correct.'),
                controlAffinity: ListTileControlAffinity.leading),
            const ExchangeDisclaimer(),
          ]),
        ),
      );
}
