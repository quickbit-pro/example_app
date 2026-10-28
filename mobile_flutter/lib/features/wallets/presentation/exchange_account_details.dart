import '../../../core/widgets/app_states.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../shared/widgets/currency_logo.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/application/platform_providers.dart';
import 'exchange_support.dart';
import 'exchange_bank_deposit_details.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routes.dart';
import '../../money/domain/bank_payee_draft.dart';
import 'exchange_deposit_address.dart';
import 'exchange_destination_form.dart';
import 'exchange_disclaimer.dart';

class ExchangeAccountDetails extends ConsumerStatefulWidget {
  const ExchangeAccountDetails(
      {super.key, this.destinations = false, this.outflowsEnabled = false});
  final bool destinations, outflowsEnabled;
  @override
  ConsumerState<ExchangeAccountDetails> createState() =>
      _ExchangeAccountDetailsState();
}

class _ExchangeAccountDetailsState
    extends ConsumerState<ExchangeAccountDetails> {
  List<Map<String, dynamic>> accounts = [];
  Set<String> restrictedTradingCurrencies = {};
  bool accepted = false, busy = false;
  String? error;
  String? payInError;
  final selectedNetworks = <String, int>{};
  final requestedNetworks = <(String, int)>{};
  final generatedAccounts = <(String, int), Map<String, dynamic>>{};
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    if (!widget.destinations) {
      timer = Timer.periodic(const Duration(seconds: 15), (_) => load());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = ref.read(mobilePlatformApiProvider);
      if (widget.destinations) {
        final result = await api.getExchangeDestinations();
        if (mounted) setState(() => accounts = result);
      } else {
        final result = await api.getExchangeSettlementAccounts();
        if (mounted) {
          setState(() {
            accepted = exchangeText(result, 'kycStatus') == 'accepted';
            restrictedTradingCurrencies = (exchangeValue(result, 'restrictedTradingCurrencies') as List? ?? [])
                .map((c) => c.toString().trim().toUpperCase()).toSet();
            final providerAccounts =
                (exchangeValue(result, 'accounts') as List? ?? [])
                    .map(exchangeMap)
                    .toList();
            // Only addresses issued through pay-in provisioning may be used.
            // Default crypto accounts are settlement metadata, not deposit rails.
            for (final account in providerAccounts) {
              final currency = provisionedCurrency(account);
              final chain = int.tryParse(exchangeText(account, 'chainId'));
              if (currency != null &&
                  chain != null &&
                  exchangeDepositAddress(
                          chain, exchangeText(account, 'address')) !=
                      null) {
                requestedNetworks.add((currency, chain));
              }
            }
            accounts = providerAccounts
                .where((account) =>
                    isBank(account) || provisionedCurrency(account) != null)
                // Providers can include empty settlement placeholders alongside
                // issued accounts. Keep identifiable pending accounts and usable
                // deposit details, but do not render anonymous placeholders.
                .where((account) =>
                    (exchangeValue(account, 'currencies') as List? ?? [])
                        .whereType<String>()
                        .any((currency) => currency.trim().isNotEmpty) ||
                    (exchangeValue(account, 'ready') == true &&
                        exchangeValue(account, 'chainId') != null &&
                        exchangeText(account, 'address').trim().isNotEmpty))
                .map((account) => isBank(account)
                    ? account
                    : {
                        ...account,
                        'currencies': [provisionedCurrency(account)!],
                      })
                .toList();
            final readyBankCurrencies = accounts
                .where((a) =>
                    isBank(a) &&
                    exchangeValue(a, 'ready') == true &&
                    exchangeText(a, 'address').trim().isNotEmpty)
                .expand(accountCurrencies)
                .toSet();
            accounts.removeWhere((a) =>
                isBank(a) &&
                exchangeText(a, 'address').trim().isEmpty &&
                accountCurrencies(a).isNotEmpty &&
                accountCurrencies(a).every(readyBankCurrencies.contains));
            for (final generated in generatedAccounts.values) {
              if (!accounts.any((account) =>
                  exchangeText(account, 'chainId') ==
                      exchangeText(generated, 'chainId') &&
                  exchangeText(account, 'address') ==
                      exchangeText(generated, 'address') &&
                  accountCurrencies(account)
                      .contains(accountCurrencies(generated).single))) {
                accounts.add(generated);
              }
            }
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = widget.destinations
            ? 'We couldn’t load your saved destinations. Please try again.'
            : 'We couldn’t refresh your deposit details. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  static const depositNetworks = {
    'USDC': [1, -200, 1399811149],
    'USDT': [1, -200],
  };

  String? provisionedCurrency(Map<String, dynamic> account) {
    final chain = int.tryParse(exchangeText(account, 'chainId'));
    if (chain == null) return null;
    final match = RegExp(r'^deposit-[0-9]+-[0-9]+-(usdc|usdt)-' '$chain' r'$')
        .firstMatch(exchangeText(account, 'reference'));
    final currency = match?.group(1)?.toUpperCase();
    if (currency == null ||
        !(depositNetworks[currency]?.contains(chain) ?? false)) {
      return null;
    }
    final currencies = accountCurrencies(account);
    return currencies.isEmpty || currencies.contains(currency)
        ? currency
        : null;
  }

  Future<void> createDepositAddress(String currency, int chain) async {
    if (busy || !accepted || widget.destinations || restrictedTradingCurrencies.contains(currency)) return;
    setState(() {
      busy = true;
      payInError = null;
    });
    try {
      final result = await ref
          .read(mobilePlatformApiProvider)
          .createExchangePayInAddress(currency: currency, chainId: chain);
      final wallet = exchangeMap(exchangeValue(result, 'depositWallet'));
      final address = exchangeText(wallet, 'address').trim();
      if (exchangeText(wallet, 'chainId') != '$chain' ||
          exchangeDepositAddress(chain, address) == null) {
        throw StateError('The provider returned incomplete deposit details.');
      }
      if (!mounted) return;
      setState(() {
        requestedNetworks.add((currency, chain));
        final status = exchangeText(wallet, 'status').toLowerCase();
        final state = exchangeText(wallet, 'state').toLowerCase();
        // The chain-scoped endpoint does not require currency metadata.
        final currencies = exchangeValue(wallet, 'currencies') as List? ?? [];
        if ((currencies.isEmpty ||
                accountCurrencies(wallet).contains(currency)) &&
            exchangeValue(wallet, 'enabled') != false &&
            exchangeValue(wallet, 'ready') != false &&
            (exchangeValue(wallet, 'ready') == true ||
                status == 'ready' ||
                state == 'ready') &&
            (status.isEmpty || status == 'ready') &&
            (state.isEmpty || state == 'ready')) {
          generatedAccounts[(currency, chain)] = {
            ...wallet,
            'chainId': chain,
            'currencies': [currency],
            'address': address,
            'ready': true,
          };
        }
        busy = false;
      });
      await load();
    } catch (_) {
      if (mounted) {
        setState(() => payInError =
            'Could not create the $currency deposit address. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool isBank(Map<String, dynamic> account) =>
      exchangeText(account, 'chainId') == '0' ||
      exchangeText(account, 'type') == 'Fiat';

  List<String> accountCurrencies(Map<String, dynamic> account) =>
      (exchangeValue(account, 'currencies') as List? ?? [])
          .whereType<String>()
          .map((currency) => currency.trim().toUpperCase())
          .where((currency) => currency.isNotEmpty)
          .toSet()
          .toList();

  bool isGrouped(Map<String, dynamic> account) =>
      !isBank(account) &&
      int.tryParse(exchangeText(account, 'chainId')) != null &&
      accountCurrencies(account).isNotEmpty;

  Map<String, Map<int, Map<String, dynamic>?>> get currencyGroups {
    final groups = <String, Map<int, Map<String, dynamic>?>>{};
    for (final account in accounts.where(isGrouped)) {
      final chain = int.parse(exchangeText(account, 'chainId'));
      for (final currency in accountCurrencies(account)) {
        final networks = groups.putIfAbsent(currency, () => {});
        // Prefer usable details if the provider lists several accounts per rail.
        if (networks[chain] == null ||
            exchangeValue(networks[chain]!, 'ready') != true) {
          networks[chain] = account;
        }
      }
    }
    if (accepted) {
      for (final entry in depositNetworks.entries) {
        final networks = groups.putIfAbsent(entry.key, () => {});
        for (final chain in entry.value) {
          networks.putIfAbsent(chain, () => null);
        }
      }
    }
    groups.removeWhere((currency, _) => restrictedTradingCurrencies.contains(currency));
    return groups;
  }

  String networkLabel(int chain) => switch (chain) {
        1 => 'Ethereum (ERC20)',
        -200 => 'Tron (TRC20)',
        _ => exchangeNetworkName(chain),
      };

  Widget currencyDepositCard(
      String currency, Map<int, Map<String, dynamic>?> networks) {
    final theme = Theme.of(context);
    final saved = selectedNetworks[currency];
    final chain = networks.containsKey(saved)
        ? saved!
        : networks.keys.firstWhere(
            (key) => exchangeValue(networks[key] ?? {}, 'ready') == true,
            orElse: () => networks.keys.first);
    final account = networks[chain];
    final address =
        exchangeDepositAddress(chain, exchangeText(account ?? {}, 'address'));
    final ready = accepted &&
        error == null &&
        address != null &&
        exchangeValue(account ?? {}, 'ready') == true;
    return Container(
      key: ValueKey('deposit-currency-$currency'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          CurrencyLogo(symbol: currency, size: 32),
          const SizedBox(width: 12),
          Text(currency,
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 20),
        DropdownButtonFormField<int>(
          key: ValueKey('deposit-network-$currency-$chain'),
          initialValue: chain,
          isExpanded: true,
          decoration: const InputDecoration(
              labelText: 'Network', prefixIcon: Icon(Icons.hub_outlined)),
          items: [
            for (final network in networks.keys)
              DropdownMenuItem(
                  value: network,
                  child: Text(networkLabel(network),
                      overflow: TextOverflow.ellipsis))
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => selectedNetworks[currency] = value);
            }
          },
        ),
        const SizedBox(height: 20),
        if (ready) ...[
          LayoutBuilder(
              builder: (context, constraints) => Center(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16)),
                      child: QrImageView(
                        key: ValueKey('deposit-qr-$currency-$chain'),
                        data: address,
                        size: (constraints.maxWidth - 24)
                            .clamp(0, 200)
                            .toDouble(),
                        backgroundColor: Colors.white,
                      ),
                    ),
                  )),
          const SizedBox(height: 16),
          Text('Deposit address', style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SelectableText(address,
              key: ValueKey('deposit-address-$currency'),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
          Text('Only send $currency on ${networkLabel(chain)}.',
              style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          OutlinedButton.icon(
              key: ValueKey('copy-deposit-$currency'),
              onPressed: () => copy(address, false),
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy address')),
        ] else if (!accepted)
          const Text(
              'Your exchange account must be approved before you can deposit.')
        else if (depositNetworks.containsKey(currency) &&
            account == null &&
            !requestedNetworks.contains((currency, chain)) &&
            error == null)
          OutlinedButton(
              key: ValueKey('create-${currency.toLowerCase()}-$chain'),
              onPressed:
                  busy ? null : () => createDepositAddress(currency, chain),
              child: const Text('Create deposit address'))
        else
          const Text(
              'These deposit details are not available yet. Refresh to check again.'),
      ]),
    );
  }

  Future<void> addDestination(bool bank) async {
    final saved = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExchangeDestinationForm(bank: bank));
    if (saved == null || !mounted) return;
    await load();
    if (!mounted) return;
    // Keep the confirmed provider result visible while its list catches up.
    final id = exchangeText(saved, 'id');
    if (id.isNotEmpty &&
        id != '0' &&
        !accounts.any((account) => exchangeText(account, 'id') == id)) {
      setState(() => accounts = [...accounts, saved]);
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Destination saved. No funds were transferred.')));
  }

  Future<void> remove(Map<String, dynamic> account) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
                title: const Text('Remove destination?'),
                content: const Text('Existing transfers are not cancelled.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Remove'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(mobilePlatformApiProvider)
          .deleteExchangeDestination(int.parse(exchangeText(account, 'id')));
      if (mounted) {
        setState(() => busy = false);
        await load();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          busy = false;
          error = friendlyErrorMessage(e);
        });
      }
    }
  }

  Future<void> copy(String text, bool bank) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(bank ? 'IBAN copied' : 'Address copied')));
    } catch (_) {
      if (mounted) {
        setState(() =>
            error = 'Could not copy. Select the address and copy it manually.');
      }
    }
  }

  Widget accountCard(Map<String, dynamic> a) {
    final colors = Theme.of(context).colorScheme;
    final currencies =
        (exchangeValue(a, 'currencies') as List? ?? []).join(' / ');
    final chain = exchangeValue(a, 'chainId');
    final bank = '$chain' == '0' || exchangeText(a, 'type') == 'Fiat';
    final address = widget.destinations
        ? exchangeText(a, 'address')
        : exchangeDepositAddress(
                int.tryParse('$chain'), exchangeText(a, 'address')) ??
            '';
    final ready = accepted &&
        error == null &&
        exchangeValue(a, 'ready') == true &&
        chain != null &&
        address.isNotEmpty;
    final name = exchangeText(a, 'name');
    final title = widget.destinations
        ? (name.isEmpty ? 'Saved destination' : name)
        : (currencies.isEmpty ? 'Deposit account' : currencies);
    return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(16)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(
                bank
                    ? Icons.account_balance_outlined
                    : Icons.account_balance_wallet_outlined,
                size: 24),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(title,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(bank ? (!widget.destinations && currencies == 'EUR' ? 'Bank transfer · SEPA' : 'Bank account') : exchangeNetworkName(chain),
                      style: Theme.of(context).textTheme.bodySmall),
                ]))
          ]),
          const SizedBox(height: 16),
          if (widget.destinations) ...[
            SelectableText(bank
                ? [
                    exchangeText(a, 'bankName'),
                    exchangeText(a, 'accountNumberHint'),
                    exchangeText(a, 'accountHolderNameHint'),
                    exchangeText(a, 'country')
                  ].where((x) => x.isNotEmpty).join(' · ')
                : address),
            const SizedBox(height: 12),
            Text(exchangeValue(a, 'enabled') == true
                ? 'Ready to use'
                : 'Not available for withdrawals'),
            if (widget.outflowsEnabled)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: busy ? null : () => remove(a),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('Remove'))),
          ] else if (ready && bank)
            ExchangeBankDepositDetails(account: a,
              onAddPayee: ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled == true
                  ? () {
                      final details = exchangeMap(exchangeValue(a, 'bank'));
                      final draft = BankPayeeDraft(
                        iban: address, accountHolder: exchangeText(details, 'accountHolderName'),
                        bankCountry: exchangeText(details, 'country').trim().toUpperCase(),
                        bic: exchangeText(details, 'bic'), bankName: exchangeText(details, 'name'),
                        bankAddress: exchangeText(details, 'address'),
                        paymentReference: exchangeText(a, 'paymentReference'));
                      final router = GoRouter.of(context);
                      Navigator.of(context).pop();
                      router.push(AppRoutes.payees, extra: draft);
                    } : null)
          else if (ready) ...[
            Text(bank ? 'IBAN' : 'Deposit address',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 8),
            SelectableText(address,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(height: 1.5)),
            for (final e in exchangeMap(exchangeValue(a, 'bank'))
                .entries
                .where((e) => e.value != null && e.value.toString().isNotEmpty))
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SelectableText(
                      '${e.key.replaceAll('_', ' ')}: ${e.value}')),
            const SizedBox(height: 12),
            if (!bank)
              Text('Only send $currencies on ${exchangeNetworkName(chain)}.',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                    onPressed: () => copy(address, bank),
                    icon: const Icon(Icons.copy_outlined, size: 18),
                    label: Text(bank ? 'Copy IBAN' : 'Copy address'))),
          ] else
            Text(
                accepted
                    ? 'These deposit details are not available yet. Refresh to check again.'
                    : 'Your exchange account must be approved before you can deposit.',
                style: Theme.of(context).textTheme.bodyMedium),
        ]));
  }

  @override
  Widget build(BuildContext context) => ExchangeDialog(
        width: widget.destinations ? 600 : 820,
        title: widget.destinations ? 'Saved destinations' : 'Deposit funds',
        subtitle: widget.destinations
            ? 'Bank accounts and crypto wallets saved for withdrawals.'
            : 'Use the correct currency and network for each deposit.',
        actions: [
          TextButton.icon(
              onPressed: busy ? null : load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Refresh')),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'))
        ],
        child: ExchangeFormColumn(children: [
          if (widget.destinations)
            Wrap(spacing: 12, runSpacing: 8, children: [
              OutlinedButton.icon(
                  onPressed: busy ? null : () => addDestination(true),
                  icon: const Icon(Icons.account_balance_outlined),
                  label: const Text('Add bank account')),
              OutlinedButton.icon(
                  onPressed: busy ? null : () => addDestination(false),
                  icon: const Icon(Icons.account_balance_wallet_outlined),
                  label: const Text('Add crypto address')),
            ]),
          if (busy) const LinearProgressIndicator(),
          if (error != null) ExchangeNotice(error!, isError: true),
          if (payInError != null) ExchangeNotice(payInError!, isError: true),
          if (accounts.isEmpty && !busy && error == null)
            ExchangeNotice(widget.destinations
                ? 'No saved destinations yet. Add a bank account or crypto address for future withdrawals.'
                : 'Your deposit details are being prepared. Refresh to check again.'),
          if (widget.destinations) ...[
            for (final account in accounts) accountCard(account),
            const ExchangeDisclaimer(),
          ] else ...[
            for (final account
                in accounts.where((account) => !isGrouped(account)))
              accountCard(account),
            for (final group in currencyGroups.entries)
              currencyDepositCard(group.key, group.value),
          ],
        ]),
      );
}
