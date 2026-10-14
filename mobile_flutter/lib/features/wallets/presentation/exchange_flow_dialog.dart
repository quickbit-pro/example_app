import '../../../core/widgets/app_states.dart';
import '../../../brands/example/example.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/models/banking_models.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/exchange_models.dart';
import '../domain/wallet_models.dart';
import '../data/wallet_providers.dart';
import '../domain/receiving_account_details.dart';
import 'exchange_support.dart';

enum ExchangeFlow { convert, fund, withdraw }

int exchangeChainId(String network) {
  final n = network.toLowerCase();
  if (n.contains('tron') || n.contains('trx')) return -200;
  if (n.contains('polygon') || n.contains('matic')) return 137;
  if (n.contains('arbitrum') || n.contains('arb')) return 42161;
  if (n.contains('optimism') || n == 'op') return 10;
  if (n.contains('avalanche') || n == 'avax') return 43114;
  if (n.contains('ethereum') || n == 'eth' || n == 'erc20') return 1;
  return 0;
}

String exchangeBudgetCurrency(PlatformResource budget) =>
    (budget.metadata['currency'] ?? budget.metadata['Currency'] ?? 'EUR')
        .toString()
        .toUpperCase();

class ExchangeFlowDialog extends ConsumerStatefulWidget {
  const ExchangeFlowDialog(
      {super.key,
      required this.flow,
      required this.overview,
      required this.outflowsEnabled,
      this.budgets = const [],
      this.wallets = const []});
  final ExchangeFlow flow;
  final BoomFiExchangeOverview overview;
  final bool outflowsEnabled;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  @override
  ConsumerState<ExchangeFlowDialog> createState() => _ExchangeFlowDialogState();
}

class _ExchangeFlowDialogState extends ConsumerState<ExchangeFlowDialog> {
  String? sourceKey,
      destinationKey,
      budgetId,
      walletKey,
      selectedFundingCurrency;
  String amount = '', address = '', bankChoice = 'new';
  Map<String, dynamic> bank = {'beneficiaryType': 'individual'};
  bool sendToCard = false;
  AsyncValue<List<HoppaWalletAsset>> depositWallets = const AsyncLoading();
  List<Payee> equalsPayees = [];
  Map<String, dynamic>? quote;
  List<Map<String, dynamic>> destinations = [];
  List<ReceivingAccountDetails> receiving = [];
  bool busy = false, accepted = false, review = false, submitted = false;
  String? error, actionUrl;
  final idempotencyKey =
      'mobile-exchange-${DateTime.now().microsecondsSinceEpoch}';
  Timer? timer;
  List<BoomFiExchangeBalance> get balances => widget.overview.balances
      .where((b) => widget.flow == ExchangeFlow.withdraw || widget.overview.canTrade(b.currency)).toList();
  List<String> fundingCurrencies(PlatformResource b) {
    final values = exchangeValue(b.metadata, 'supportedCurrencies');
    return (values is List
            ? values.map((v) => v.toString().toUpperCase())
            : [exchangeBudgetCurrency(b)])
        .where(widget.overview.fiatFundingCurrencies.contains)
        .toSet()
        .toList();
  }

  List<PlatformResource> get budgets =>
      widget.budgets.where((b) => fundingCurrencies(b).isNotEmpty).toList();
  String get fundingCurrency => budget == null
      ? ''
      : fundingCurrencies(budget!).contains(selectedFundingCurrency)
          ? selectedFundingCurrency!
          : fundingCurrencies(budget!).first;
  List<HoppaWalletAsset> get wallets => (depositWallets.valueOrNull ?? widget.wallets)
      .where((w) =>
          w.address.isNotEmpty &&
          exchangeChainId(w.network) != 0 &&
          ['USDC', 'USDT'].contains(w.symbol.toUpperCase()) &&
          (widget.flow != ExchangeFlow.fund || widget.overview.canTrade(w.symbol)))
      .toList();
  PlatformResource? get budget =>
      budgets.where((x) => x.id == budgetId).firstOrNull ?? budgets.firstOrNull;
  String walletId(HoppaWalletAsset w) =>
      '${w.walletId}:${w.symbol}:${w.network}:${w.address}';
  HoppaWalletAsset? get wallet =>
      wallets.where((x) => walletId(x) == walletKey).firstOrNull ??
      wallets.firstOrNull;
  // Conversion spends the shared currency balance; retain a real provider
  // account for quotes while keeping withdrawal network routes separate.
  List<BoomFiExchangeBalance> get sources => (widget.flow == ExchangeFlow.convert
          ? widget.overview.displayBalances
              .where((b) => widget.overview.canTrade(b.currency))
          : balances)
      .where((b) => widget.flow == ExchangeFlow.fund
          ? !b.isCrypto && b.currency == fundingCurrency
          : widget.flow == ExchangeFlow.withdraw
              ? b.isCrypto || b.currency == 'EUR'
              : true)
      .toList();
  BoomFiExchangeBalance? get source =>
      sources.where((b) => b.key == sourceKey).firstOrNull ??
      (widget.flow == ExchangeFlow.fund
          ? null
          : sources.where((b) => b.amount > 0).firstOrNull) ??
      sources.firstOrNull;
  List<BoomFiExchangeBalance> get targets => balances
      .where((b) => widget.flow == ExchangeFlow.fund
          ? wallet != null &&
              b.currency == wallet!.symbol.toUpperCase() &&
              b.chainId == exchangeChainId(wallet!.network)
          : source != null &&
              b.isCrypto != source!.isCrypto &&
              (b.isCrypto || b.currency == 'EUR'))
      .toList();
  BoomFiExchangeBalance? get destination =>
      targets.where((b) => b.key == destinationKey).firstOrNull ??
      targets.firstOrNull;
  Map<String, String> get cryptoDestinations => {
        for (final d in destinations.where((d) =>
            exchangeText(d, 'type') == 'Digital' &&
            exchangeValue(d, 'enabled') == true &&
            (exchangeValue(d, 'currencies') as List? ?? [])
                .contains(source?.currency) &&
            exchangeValue(d, 'chainId') == source?.chainId &&
            exchangeText(d, 'address').isNotEmpty))
          exchangeText(d, 'address'): exchangeText(d, 'name').isEmpty
              ? exchangeText(d, 'address')
              : exchangeText(d, 'name'),
        for (final w in wallets.where((w) =>
            w.symbol.toUpperCase() == source?.currency &&
            exchangeChainId(w.network) == source?.chainId))
          w.address: 'Crypto card · ${w.shortAddress}',
      };
  bool get canSendToCard => widget.flow == ExchangeFlow.convert &&
      source?.isCrypto == false && destination?.isCrypto == true;
  List<HoppaWalletAsset> get cardDestinations => (depositWallets.valueOrNull ?? const <HoppaWalletAsset>[]).where((w) =>
      w.symbol.toUpperCase() == destination?.currency &&
      exchangeChainId(w.network) == destination?.chainId).toList();
  HoppaWalletAsset? get cardDestination => cardDestinations
      .where((w) => walletId(w) == walletKey).firstOrNull ?? cardDestinations.firstOrNull;
  List<Payee> get eligibleEqualsPayees => equalsPayees.where((p) =>
      (p.provider.isEmpty || p.provider.toLowerCase().replaceAll(' ', '').contains('equals')) &&
      !p.requiresConfirmation && !['disabled', 'deleted', 'rejected', 'inactive'].contains(p.status.toLowerCase()) &&
      (p.currency.isEmpty || p.currency.toUpperCase() == bankCurrency) &&
      RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$').hasMatch(p.accountReference.replaceAll(' ', '').toUpperCase())).toList();
  List<ReceivingAccountDetails> get eligibleReceiving => receiving.where((r) =>
      r.currencies.isEmpty || r.currencies.contains(bankCurrency)).toList();
  String payeeLabel(Payee p) {
    final iban = p.accountReference.replaceAll(' ', '');
    return 'Saved bank recipient · ${p.name} · ${iban.substring(0, 2)}…${iban.substring(iban.length - 4)}';
  }
  String? get bankCurrency => widget.flow == ExchangeFlow.withdraw ? source?.currency : destination?.currency;
  List<Map<String, dynamic>> get savedBanks => destinations.where((d) =>
      exchangeText(d, 'type').toLowerCase() == 'fiat' &&
      exchangeValue(d, 'enabled') == true &&
      int.tryParse(exchangeText(d, 'id')) != null &&
      ((exchangeValue(d, 'currencies') as List? ?? []).isEmpty ||
       (exchangeValue(d, 'currencies') as List).any((c) => c.toString().toUpperCase() == bankCurrency))).toList();
  Map<String, dynamic>? get savedBank => savedBanks.where((d) => 'saved:${exchangeText(d, 'id')}' == bankChoice).firstOrNull;
  String bankLabel(Map<String, dynamic> d) => [exchangeText(d, 'name'), exchangeText(d, 'bankName'), exchangeText(d, 'accountNumberHint')]
      .where((v) => v.isNotEmpty).join(' · ');
  bool get needsBank => widget.flow == ExchangeFlow.withdraw
      ? source?.isCrypto == false
      : widget.flow == ExchangeFlow.convert &&
          source?.isCrypto == true &&
          destination != null;
  bool get locked => busy || review || submitted;
  DateTime? get expiry =>
      DateTime.tryParse(exchangeText(quote ?? {}, 'expiry'));
  bool get expired =>
      quote != null &&
      (expiry == null ||
          !expiry!.isAfter(DateTime.now().add(const Duration(seconds: 2))));
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && quote != null) setState(() {});
    });
    loadDestinations();
  }

  Future<void> loadDestinations() async {
    try {
      final api = ref.read(mobilePlatformApiProvider);
      final saved = await api.getExchangeDestinations();
      if (mounted) setState(() => destinations = saved);
    } catch (_) {/* Manual destination remains available. */}
    try {
      final accounts =
          await ref.read(mobilePlatformApiProvider).getEqualsBankingInfos();
      if (mounted) {
        setState(() => receiving = {
              for (final a in receivingAccountsFromResources(accounts)
                  .where((a) => a.isIban))
                a.accountNumber: a
            }.values.toList());
      }
    } catch (_) {/* New payee remains available. */}
    try {
      final payees = await ref.read(payeesProvider.future);
      if (mounted) setState(() => equalsPayees = payees);
    } catch (_) {/* Manual bank details remain available. */}
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void edit(VoidCallback action) => setState(() {
        action();
        quote = null;
        review = false;
        accepted = false;
        error = null;
      });
  Widget balanceChoice(String label, List<BoomFiExchangeBalance> choices,
          BoomFiExchangeBalance? selected, ValueChanged<String?> onChanged,
          {bool showNetwork = true}) =>
      ExchangeFieldLabel(
          label: label,
          child: DropdownButtonFormField<String>(
              key: ValueKey('$label-${selected?.key}'),
              initialValue: selected?.key,
              isExpanded: true,
              decoration:
                  const InputDecoration(hintText: 'No available account'),
              items: choices
                  .map((b) => DropdownMenuItem(
                      value: b.key,
                      child: Text(
                          '${b.currency}${showNetwork && b.isCrypto ? ' · ${b.chainName}' : ''} · ${b.amount}',
                          overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: locked || choices.isEmpty ? null : onChanged));
  Future<void> prepare() async {
    final number = double.tryParse(amount.replaceAll(',', '.'));
    if (source == null || number == null || !number.isFinite || number <= 0) {
      setState(() => error = 'Enter a valid amount and select an account.');
      return;
    }
    if (widget.flow != ExchangeFlow.fund && number > source!.amount) {
      setState(() => error = 'Amount exceeds the available balance.');
      return;
    }
    if (canSendToCard && sendToCard && cardDestination == null) {
      setState(() => error = 'Select a currency and network supported by your crypto card account.');
      return;
    }
    if (needsBank && bankChoice.startsWith('saved:') && savedBank == null) {
      setState(() => error = 'Select a saved bank account supporting the destination currency.');
      return;
    }
    if (needsBank && savedBank == null && !exchangeBankComplete(bank)) {
      setState(() =>
          error = 'Enter a valid IBAN and complete the bank destination.');
      return;
    }
    if (widget.flow == ExchangeFlow.withdraw &&
        source!.isCrypto &&
        address.trim().isEmpty) {
      setState(() => error = 'Enter or select a crypto destination.');
      return;
    }
    if (widget.flow != ExchangeFlow.withdraw && destination == null) {
      setState(() => error = 'No matching exchange destination is available.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      Map<String, dynamic>? result;
      if (widget.flow != ExchangeFlow.withdraw) {
        result = await ref.read(mobilePlatformApiProvider).getExchangeQuote(
            source: source!,
            destination: destination!,
            sellAmount: amount.replaceAll(',', '.'),
            bankWithdrawal: needsBank ? Map.of(bank) : null,
            interlaceDestinationAddress: canSendToCard && sendToCard ? cardDestination!.address : null);
      }
      if (!mounted) return;
      setState(() {
        quote = result;
        review = true;
        accepted = false;
      });
    } catch (e) {
      if (mounted) setState(() => error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm() async {
    if (busy ||
        submitted ||
        !accepted ||
        !widget.outflowsEnabled ||
        !review ||
        (quote != null && expired)) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final api = ref.read(mobilePlatformApiProvider);
      Map<String, dynamic> result;
      if (widget.flow == ExchangeFlow.fund) {
        result = await api.fundExchange({
          'idempotencyKey': idempotencyKey,
          'sourceBudgetId': budget!.id,
          'fiatCurrency': source!.currency,
          'fiatAmount': double.parse(amount.replaceAll(',', '.')),
          'cryptoCurrency': wallet!.symbol.toUpperCase(),
          'chainId': exchangeChainId(wallet!.network),
          'destinationAddress': wallet!.address
        });
      } else if (widget.flow == ExchangeFlow.withdraw) {
        // A payout may have reached the provider even if its response was lost.
        submitted = true;
        result = source!.isCrypto
            ? await api.withdrawExchangeCrypto({
                'accountRef': source!.accountId.toString(),
                'amount': amount.replaceAll(',', '.'),
                'ccy': source!.currency,
                'chainId': source!.chainId,
                'walletAddress': address.trim(),
                'tokenAddress': source!.tokenAddress
              })
            : await api.withdrawExchangeFiat({
                ...bank,
                'amount': amount.replaceAll(',', '.'),
                'currency': source!.currency
              });
      } else {
        final id = exchangeText(quote!, 'session').isNotEmpty
            ? exchangeText(quote!, 'session')
            : exchangeText(quote!, 'quoteId');
        if (id.isEmpty) {
          throw StateError(
              'The quote identifier is missing. Request a new quote.');
        }
        final acceptedResult = await api.acceptExchangeQuote(id);
        result = {'message': acceptedResult.message};
      }
      ref.invalidate(exchangeTransfersProvider);
      ref.invalidate(exchangeOverviewProvider);
      if (!mounted) return;
      final url = exchangeActionUrl(result);
      if (url != null) {
        setState(() {
          actionUrl = url;
          submitted = true;
        });
        return;
      }
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(exchangeText(result, 'message').isEmpty
              ? 'Exchange request submitted'
              : exchangeText(result, 'message'))));
    } catch (e) {
      if (mounted) {
        setState(() => error = submitted
            ? 'The payout outcome needs checking. Refresh transfers before making another withdrawal.'
            : friendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    depositWallets = ref.watch(exchangeCardDepositAddressesProvider);
    if (widget.flow == ExchangeFlow.fund &&
        (budget == null || wallet == null)) {
      return AlertDialog(
          title: const Text('Fiat to crypto'),
          content: const Text(
              'No compatible fiat funding account and crypto destination are available.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ]);
    }
    final title = widget.flow == ExchangeFlow.fund
        ? (context.isExampleTheme
            ? 'Fiat account to Crypto card'
            : 'Fiat account → Crypto card')
        : widget.flow == ExchangeFlow.withdraw
            ? 'Withdraw from Exchange'
            : 'Convert currency';
    final fees = exchangeMap(exchangeValue(quote ?? {}, 'fees'));
    return PopScope(
        canPop: !busy,
        child: ExchangeDialog(
            title: title,
            subtitle: widget.flow == ExchangeFlow.withdraw
                ? 'Send funds to your bank account or crypto wallet.'
                : 'Choose your accounts and amount, then review before confirming.',
            actions: [
              TextButton(
                  onPressed: busy ? null : () => Navigator.pop(context),
                  child: Text(submitted ? 'Close' : 'Cancel')),
              if (review && !submitted)
                TextButton(
                    onPressed: busy ? null : () => edit(() {}),
                    child: const Text('Edit / refresh quote')),
              if (!submitted)
                _primaryAction(context,
                    onPressed: busy ||
                            source == null ||
                            (widget.flow != ExchangeFlow.fund &&
                                source!.amount <= 0) ||
                            (widget.flow != ExchangeFlow.withdraw &&
                                destination == null)
                        ? null
                        : review
                            ? (!accepted ||
                                    !widget.outflowsEnabled ||
                                    (quote != null && expired)
                                ? null
                                : confirm)
                            : prepare,
                    label: review
                        ? (widget.flow == ExchangeFlow.fund
                            ? 'Confirm and fund'
                            : widget.flow == ExchangeFlow.withdraw
                                ? 'Confirm withdrawal'
                                : 'Confirm exchange')
                        : widget.flow == ExchangeFlow.withdraw
                            ? 'Review withdrawal'
                            : 'Get quote'),
            ],
            child: ExchangeFormColumn(children: [
              if (widget.flow == ExchangeFlow.fund) ...[
                ExchangeFieldLabel(
                    label: 'Source fiat account',
                    child: DropdownButtonFormField<String>(
                        initialValue: budget!.id,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            hintText: 'Select an account'),
                        items: budgets
                            .map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text(b.title,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: locked
                            ? null
                            : (v) => edit(() {
                                  budgetId = v;
                                  sourceKey = null;
                                }))),
                ExchangeFieldLabel(
                    label: 'Fiat currency',
                    child: DropdownButtonFormField<String>(
                        key: ValueKey('funding-$fundingCurrency'),
                        initialValue: fundingCurrency,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            hintText: 'Select an account'),
                        items: fundingCurrencies(budget!)
                            .map((c) =>
                                DropdownMenuItem(value: c, child: Text(c)))
                            .toList(),
                        onChanged: locked
                            ? null
                            : (v) => edit(() {
                                  selectedFundingCurrency = v;
                                  sourceKey = null;
                                }))),
                ExchangeFieldLabel(
                    label: 'Crypto card destination',
                    child: DropdownButtonFormField<String>(
                        initialValue: walletId(wallet!),
                        isExpanded: true,
                        decoration: const InputDecoration(
                            hintText: 'Select an account'),
                        items: wallets
                            .map((w) => DropdownMenuItem(
                                value: walletId(w),
                                child: Text(
                                    '${w.symbol} · ${w.network} · ${w.shortAddress}',
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged:
                            locked ? null : (v) => edit(() => walletKey = v))),
              ],
              balanceChoice(
                  'From',
                  sources,
                  source,
                  (v) => edit(() {
                        sourceKey = v;
                        destinationKey = null;
                        address = '';
                        sendToCard = false;
                        bankChoice = 'new';
                        bank = {'beneficiaryType': 'individual'};
                      }),
                  showNetwork: widget.flow != ExchangeFlow.convert),
              if (widget.flow == ExchangeFlow.convert)
                balanceChoice('To', targets, destination,
                    (v) => edit(() { destinationKey = v; sendToCard = false; bankChoice = 'new'; bank = {'beneficiaryType': 'individual'}; })),
              if (source != null &&
                  source!.amount <= 0 &&
                  widget.flow != ExchangeFlow.fund)
                const ExchangeNotice(
                    'There are no funds available in this account. Deposit funds to continue.'),
              if (widget.flow != ExchangeFlow.withdraw && destination == null)
                const ExchangeNotice(
                    'No compatible currency account is available yet. Refresh your exchange accounts and try again.'),
              ExchangeFieldLabel(
                  label: 'Amount (${source?.currency ?? ''})',
                  child: TextField(
                      key: const ValueKey('exchange-amount'),
                      enabled: !locked,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(hintText: '0.00'),
                      onChanged: (v) => edit(() => amount = v))),
              if (widget.flow != ExchangeFlow.withdraw && !widget.overview.canTrade('USDT'))
                const ExchangeNotice('USDT cannot be exchanged through BoomFi for EU residents. Use USDC instead.'),
              if (canSendToCard) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Send to my crypto card account'),
                  subtitle: const Text('Optional · Deliver the converted crypto after settlement, ready for a card top-up.'),
                  value: sendToCard,
                  onChanged: locked || !widget.outflowsEnabled || cardDestinations.isEmpty
                      ? null : (v) => edit(() => sendToCard = v),
                ),
                if (widget.overview.canTrade('USDT') && !balances.any((b) => b.currency == 'USDT' && b.isCrypto))
                  const ExchangeNotice('USDT is not enabled for conversion on your Exchange account.'),
                if (depositWallets.isLoading)
                  const ExchangeNotice('Loading your crypto card deposit addresses…')
                else if (depositWallets.hasError) ...[
                  const ExchangeNotice('Could not load your crypto card deposit addresses.'),
                  TextButton.icon(
                    onPressed: locked ? null : () {
                      ref.invalidate(depositAddressesProvider);
                      ref.invalidate(exchangeCardDepositAddressesProvider);
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry deposit addresses'),
                  ),
                ] else if (cardDestinations.isEmpty)
                  const ExchangeNotice('No crypto card deposit address matches this currency and network. Choose another network.'),
                if (sendToCard && cardDestination != null)
                  ExchangeFieldLabel(label: 'Crypto card deposit account', child: DropdownButtonFormField<String>(
                    key: ValueKey('card-delivery-${destination?.key}'),
                    initialValue: walletId(cardDestination!), isExpanded: true,
                    items: cardDestinations.map((w) => DropdownMenuItem(value: walletId(w),
                      child: Text('${w.symbol} · ${w.network} · ${w.shortAddress}', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: locked ? null : (v) => edit(() => walletKey = v))),
              ],
              if (needsBank) ...[
                const ExchangeNotice(
                    'EUR proceeds are sent to your bank account after settlement. Fiat can remain in Exchange for up to 24 hours.'),
                if (savedBanks.isNotEmpty || eligibleReceiving.isNotEmpty || eligibleEqualsPayees.isNotEmpty)
                  ExchangeFieldLabel(
                      label: 'Receive fiat in',
                      child: DropdownButtonFormField<String>(
                          key: ValueKey('bank-destination-$bankCurrency'),
                          initialValue: bankChoice.startsWith('saved:') && savedBank == null ? 'new' : bankChoice,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              hintText: 'Select an account'),
                          items: [
                            const DropdownMenuItem(
                                value: 'new', child: Text('New payee')),
                            for (final d in savedBanks)
                              DropdownMenuItem(value: 'saved:${exchangeText(d, 'id')}',
                                  child: Text(bankLabel(d), overflow: TextOverflow.ellipsis)),
                            for (final p in eligibleEqualsPayees)
                              DropdownMenuItem(value: 'equals-payee:${p.id}',
                                  child: Text(payeeLabel(p), overflow: TextOverflow.ellipsis)),
                            for (final r in eligibleReceiving)
                              DropdownMenuItem(
                                  value: r.accountNumber,
                                  child: Text('My Equals account · ${r.holder} · ${r.maskedIdentifier}',
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: locked
                              ? null
                              : (v) => edit(() {
                                    bankChoice = v ?? 'new';
                                    if (savedBank != null) {
                                      bank = {'externalAccountId': int.parse(exchangeText(savedBank!, 'id'))};
                                      return;
                                    }
                                    final p = eligibleEqualsPayees.where((p) => 'equals-payee:${p.id}' == v).firstOrNull;
                                    if (p != null) {
                                      final iban = p.accountReference.replaceAll(' ', '').toUpperCase();
                                      bank = {
                                        'beneficiaryType': p.firstName.isNotEmpty && p.lastName.isNotEmpty ? 'individual' : 'business',
                                        'name': p.name, 'accountNumber': iban,
                                        'bankName': p.bankName, 'accountHolderName': p.name,
                                        'country': iban.substring(0, 2),
                                        'firstName': p.firstName, 'lastName': p.lastName,
                                      };
                                      return;
                                    }
                                    final r = receiving
                                        .where((r) => r.accountNumber == v)
                                        .firstOrNull;
                                    bank = {
                                      'beneficiaryType':
                                          'individual',
                                      'name': r == null
                                          ? ''
                                          : 'EqualsMoney receiving account',
                                      'accountNumber': r?.accountNumber ?? '',
                                      'bankName': r?.bankName ?? '',
                                      'accountHolderName': r?.holder ?? '',
                                      'country': r == null
                                          ? ''
                                          : r.accountNumber
                                              .substring(0, 2)
                                              .toUpperCase(),
                                    };
                                  }))),
                if (savedBank != null)
                  ExchangeNotice(bankLabel(savedBank!))
                else ExchangeBankFields(
                    key: ValueKey(bankChoice),
                    value: bank,
                    enabled: !locked,
                    onChanged: (v) => edit(() => bank = v)),
              ],
              if (widget.flow == ExchangeFlow.withdraw &&
                  source?.isCrypto == true) ...[
                if (cryptoDestinations.isNotEmpty)
                  ExchangeFieldLabel(
                      label: 'Saved destination',
                      child: DropdownButtonFormField<String>(
                          key: ValueKey(source!.key),
                          isExpanded: true,
                          decoration: const InputDecoration(
                              hintText: 'Choose a saved wallet'),
                          items: [
                            for (final entry in cryptoDestinations.entries)
                              DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value,
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: locked
                              ? null
                              : (v) => edit(() => address = v ?? ''))),
                ExchangeFieldLabel(
                    label: 'Destination address',
                    child: TextFormField(
                        key: ValueKey(
                            'address-${source?.key}-${cryptoDestinations.containsKey(address) ? address : 'manual'}'),
                        initialValue: address,
                        enabled: !locked,
                        decoration: InputDecoration(
                            hintText: 'Enter ${source!.chainName} address'),
                        onChanged: (v) {
                          address = v;
                          accepted = false;
                        })),
                ExchangeNotice(
                    'Send only to a ${source!.chainName} address. Transfers to the wrong network cannot be recovered.'),
              ],
              if (review) ...[
                const Divider(),
                Text('You send $amount ${source?.currency ?? ''}'),
                if (quote != null) ...[
                  Text(
                      'You receive ${exchangeText(quote!, 'buy_amount')} ${exchangeText(quote!, 'buy_currency')}'),
                  Text('Rate: ${exchangeText(quote!, 'rate')}'),
                  Text(
                      'Fee: ${exchangeText(fees, 'total_fee')} ${exchangeText(fees, 'fee_ccy')}'),
                  Text(expired
                      ? 'Quote expired — request a fresh quote.'
                      : 'Quote valid until ${expiry!.toLocal()}'),
                ],
                if (canSendToCard && sendToCard && cardDestination != null)
                  SelectableText('After settlement: ${destination!.currency} → Crypto card account\n${cardDestination!.network} · ${cardDestination!.address}'),
                if (needsBank)
                  SelectableText(
                      savedBank != null ? bankLabel(savedBank!) : '${bank['accountHolderName']} · ${bank['accountNumber']}'),
                if (widget.flow == ExchangeFlow.withdraw &&
                    source?.isCrypto == true)
                  SelectableText(address),
                if (widget.flow == ExchangeFlow.fund)
                  const Text(
                      'After funding, rates within ±0.5% are accepted automatically. Larger changes require your approval.'),
                ExchangeTerms(
                    accepted: accepted,
                    onChanged: (v) => setState(() => accepted = v),
                    enabled: !busy && !submitted,
                    withdrawal: widget.flow == ExchangeFlow.withdraw),
              ],
              if (actionUrl != null)
                TextButton(
                    onPressed: () => openExchangeUrl(actionUrl!),
                    child: const Text('Complete provider verification')),
              if (error != null) ExchangeNotice(error!, isError: true),
              if (busy) const LinearProgressIndicator(),
            ])));
  }
}

Widget _primaryAction(BuildContext context,
        {required String label, required VoidCallback? onPressed}) =>
    FilledButton(onPressed: onPressed, child: Text(label));
