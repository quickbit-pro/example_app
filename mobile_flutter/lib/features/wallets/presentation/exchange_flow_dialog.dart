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
import '../domain/exchange_transfer_routes.dart';
export '../domain/exchange_transfer_routes.dart' show exchangeChainId;
import '../data/wallet_providers.dart';
import '../domain/receiving_account_details.dart';
import 'exchange_support.dart';
import 'exchange_quote_error.dart';
import '../../../core/l10n/app_localizations.dart';

enum ExchangeFlow { convert, fund, withdraw }

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
      this.onConvertToEur,
      this.budgets = const [],
      this.wallets = const []});
  final ExchangeFlow flow;
  final BoomFiExchangeOverview overview;
  final bool outflowsEnabled;
  final Future<void> Function(PlatformResource budget)? onConvertToEur;
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
  List<PlatformResource>? refreshedBudgets;
  bool fundingBalanceRefreshFailed = false;
  String idempotencyKey =
      'mobile-exchange-${DateTime.now().microsecondsSinceEpoch}';
  final scrollController = ScrollController();
  Timer? timer, quoteRefreshTimer;
  bool refreshingQuote = false, quoteRefreshFailed = false, quoteChanged = false;
  List<BoomFiExchangeBalance> get balances => widget.overview.balances
      .where((b) =>
          widget.flow == ExchangeFlow.withdraw ||
          widget.overview.canTrade(b.currency))
      .toList();
  List<String> fundingCurrencies(PlatformResource b) {
    // Equals can add EUR through conversion even when it is not funded yet.
    return widget.overview.fiatFundingCurrencies.contains('EUR') ? ['EUR'] : [];
  }

  List<PlatformResource> get budgets => (refreshedBudgets ?? widget.budgets)
      .where((b) => fundingCurrencies(b).isNotEmpty)
      .toList();
  String get fundingCurrency => budget == null
      ? ''
      : fundingCurrencies(budget!).contains(selectedFundingCurrency)
          ? selectedFundingCurrency!
          : fundingCurrencies(budget!).first;
  List<HoppaWalletAsset> get wallets => exchangeTransferRoutes(
          depositWallets.valueOrNull ?? widget.wallets, widget.wallets)
      .where((w) =>
          w.address.isNotEmpty &&
          exchangeChainId(w.network) != 0 &&
          ['USDC', 'USDT'].contains(w.symbol.toUpperCase()) &&
          (widget.flow != ExchangeFlow.fund ||
              (widget.overview.canTrade(w.symbol) &&
                  widget.overview.balances.any((b) =>
                      b.currency == w.symbol.toUpperCase() &&
                      b.chainId == exchangeChainId(w.network)))))
      .toList();
  PlatformResource? get budget =>
      budgets.where((x) => x.id == budgetId).firstOrNull ?? budgets.firstOrNull;
  String walletId(HoppaWalletAsset w) =>
      '${w.walletId}:${w.symbol}:${w.network}:${w.address}';
  List<HoppaWalletAsset> get walletChoices => widget.flow == ExchangeFlow.fund
      ? exchangeTransferCurrencyRoutes(wallets, canTrade: widget.overview.canTrade)
      : wallets;
  HoppaWalletAsset? get wallet =>
      walletChoices.where((x) => walletId(x) == walletKey).firstOrNull ??
      walletChoices.firstOrNull;
  // Conversion spends the shared currency balance; retain a real provider
  // account for quotes while keeping withdrawal network routes separate.
  List<BoomFiExchangeBalance> get sources =>
      (widget.flow == ExchangeFlow.convert
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
  bool get canSendToCard =>
      widget.flow == ExchangeFlow.convert &&
      source?.isCrypto == false &&
      destination?.isCrypto == true;
  List<HoppaWalletAsset> get cardDestinations =>
      (depositWallets.valueOrNull ?? const <HoppaWalletAsset>[])
          .where((w) =>
              w.symbol.toUpperCase() == destination?.currency &&
              exchangeChainId(w.network) == destination?.chainId)
          .toList();
  HoppaWalletAsset? get cardDestination =>
      cardDestinations.where((w) => walletId(w) == walletKey).firstOrNull ??
      cardDestinations.firstOrNull;
  List<Payee> get eligibleEqualsPayees => equalsPayees
      .where((p) =>
          (p.provider.isEmpty ||
              p.provider
                  .toLowerCase()
                  .replaceAll(' ', '')
                  .contains('equals')) &&
          !p.requiresConfirmation &&
          !['disabled', 'deleted', 'rejected', 'inactive']
              .contains(p.status.toLowerCase()) &&
          (p.currency.isEmpty || p.currency.toUpperCase() == bankCurrency) &&
          RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$')
              .hasMatch(p.accountReference.replaceAll(' ', '').toUpperCase()))
      .toList();
  List<ReceivingAccountDetails> get eligibleReceiving => receiving
      .where((r) => r.currencies.isEmpty || r.currencies.contains(bankCurrency))
      .toList();
  String payeeLabel(Payee p) {
    final iban = p.accountReference.replaceAll(' ', '');
    return 'Saved bank recipient · ${p.name} · ${iban.substring(0, 2)}…${iban.substring(iban.length - 4)}';
  }

  String? get bankCurrency => widget.flow == ExchangeFlow.withdraw
      ? source?.currency
      : destination?.currency;
  List<Map<String, dynamic>> get savedBanks => destinations
      .where((d) =>
          exchangeText(d, 'type').toLowerCase() == 'fiat' &&
          exchangeValue(d, 'enabled') == true &&
          int.tryParse(exchangeText(d, 'id')) != null &&
          ((exchangeValue(d, 'currencies') as List? ?? []).isEmpty ||
              (exchangeValue(d, 'currencies') as List)
                  .any((c) => c.toString().toUpperCase() == bankCurrency)))
      .toList();
  Map<String, dynamic>? get savedBank => savedBanks
      .where((d) => 'saved:${exchangeText(d, 'id')}' == bankChoice)
      .firstOrNull;
  String bankLabel(Map<String, dynamic> d) => [
        exchangeText(d, 'name'),
        exchangeText(d, 'bankName'),
        exchangeText(d, 'accountNumberHint')
      ].where((v) => v.isNotEmpty).join(' · ');
  bool get needsBank => widget.flow == ExchangeFlow.withdraw
      ? source?.isCrypto == false
      : widget.flow == ExchangeFlow.convert &&
          source?.isCrypto == true &&
          destination != null;
  BoomFiFeesAndLimits? get inputLimits => widget.flow == ExchangeFlow.fund
      ? widget.overview.fiatFundingFeesAndLimits[fundingCurrency]
      : widget.flow == ExchangeFlow.withdraw && source != null
          ? widget.overview.feesFor(source!)
          : null;
  bool get hasDeliveryWithdrawal =>
      widget.flow == ExchangeFlow.fund ||
      (widget.flow == ExchangeFlow.convert &&
          (needsBank || (canSendToCard && sendToCard)));
  BoomFiFeesAndLimits? get deliveryLimits =>
      hasDeliveryWithdrawal && destination != null
          ? widget.overview.feesFor(destination!)
          : null;
  String? inputLimitError() => source == null
      ? null
      : inputLimits?.validate(amount, source!.currency,
          withdrawal: widget.flow == ExchangeFlow.withdraw);
  String? deliveryLimitError(Map<String, dynamic>? value) {
    final limits = deliveryLimits;
    if (limits == null || !limits.hasWithdrawalLimits) { return null; }
    final received = exchangeText(value ?? {}, 'buy_amount');
    final currency = exchangeText(value ?? {}, 'buy_currency').toUpperCase();
    if (received.isEmpty || currency != destination?.currency) {
      return 'The provider has not returned an amount to check against the withdrawal limits. Request a new quote.';
    }
    return limits.validate(received, currency, withdrawal: true);
  }

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
    if (widget.flow == ExchangeFlow.fund) {
      budgetId = widget.budgets.firstOrNull?.id;
    }
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && quote != null) setState(() {});
    });
    loadDestinations();
  }

  void scheduleQuoteRefresh({bool retry = false}) {
    quoteRefreshTimer?.cancel();
    if (!mounted || !review || submitted || quote == null) return;
    final remaining = expiry?.difference(DateTime.now());
    if (!retry && remaining == null) return;
    final delay = retry
        ? const Duration(seconds: 10)
        : remaining! > const Duration(seconds: 6)
            ? remaining - const Duration(seconds: 5)
            : const Duration(seconds: 1);
    quoteRefreshTimer = Timer(delay, () {
      if (mounted && review && !submitted && !busy) {
        unawaited(prepare(refresh: true));
      }
    });
  }

  bool sameQuoteTerms(Map<String, dynamic> previous, Map<String, dynamic> next) {
    bool sameValue(String a, String b) {
      final numberA = double.tryParse(a);
      final numberB = double.tryParse(b);
      return numberA != null && numberB != null ? numberA == numberB : a == b;
    }
    for (final field in ['buy_amount', 'buy_currency', 'rate']) {
      if (!sameValue(exchangeText(previous, field), exchangeText(next, field))) return false;
    }
    final previousFees = exchangeMap(exchangeValue(previous, 'fees'));
    final nextFees = exchangeMap(exchangeValue(next, 'fees'));
    return sameValue(exchangeText(previousFees, 'total_fee'), exchangeText(nextFees, 'total_fee')) &&
        exchangeText(previousFees, 'fee_ccy') == exchangeText(nextFees, 'fee_ccy');
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
    quoteRefreshTimer?.cancel();
    scrollController.dispose();
    super.dispose();
  }

  void edit(VoidCallback action) => setState(() {
        quoteRefreshTimer?.cancel();
        quoteRefreshFailed = false;
        quoteChanged = false;
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
  void scrollToResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> prepare({bool refresh = false}) async {
    if (!refresh) FocusScope.of(context).unfocus();
    await prepareQuote(refresh: refresh);
    if (!refresh && mounted) scrollToResult();
  }

  Future<void> prepareQuote({bool refresh = false}) async {
    if (busy || submitted || (refresh && !review)) return;
    if (fundingBalanceRefreshFailed) return;
    final number = double.tryParse(amount.replaceAll(',', '.'));
    if (source == null || number == null || !number.isFinite || number <= 0) {
      setState(() => error = 'Enter a valid amount and select an account.');
      return;
    }
    final limitError = inputLimitError();
    if (limitError != null) {
      setState(() => error = limitError);
      return;
    }
    if (widget.flow != ExchangeFlow.fund && number > source!.amount) {
      setState(() => error = 'Amount exceeds the available balance.');
      return;
    }
    if (widget.flow == ExchangeFlow.fund &&
        number > (exchangeBudgetBalances(budget!)['EUR'] ?? 0)) {
      setState(() => error =
          'Convert funds to EUR in this Fiat account before transferring, or enter an amount within your EUR balance.');
      return;
    }
    if (canSendToCard && sendToCard && cardDestination == null) {
      setState(() => error =
          'Select a currency and network supported by your payment card wallet.');
      return;
    }
    if (needsBank && bankChoice.startsWith('saved:') && savedBank == null) {
      setState(() => error =
          'Select a saved bank account supporting the destination currency.');
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
    quoteRefreshTimer?.cancel();
    final previousQuote = quote;
    setState(() {
      busy = true;
      refreshingQuote = refresh;
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
            interlaceDestinationAddress:
                canSendToCard && sendToCard ? cardDestination!.address : null);
      }
      if (!mounted) return;
      final limitError = deliveryLimitError(result);
      if (limitError != null) {
        setState(() {
          error = limitError;
          if (refresh) {
            quoteRefreshFailed = true;
            accepted = false;
          }
        });
        if (refresh) scheduleQuoteRefresh(retry: true);
        return;
      }
      if (result != null) {
        final nextExpiry = DateTime.tryParse(exchangeText(result, 'expiry'));
        if (nextExpiry == null || !nextExpiry.isAfter(DateTime.now().add(const Duration(seconds: 2)))) {
          throw StateError('The provider returned an expired quote. Request a new quote.');
        }
      }
      final changed = refresh && previousQuote != null && result != null &&
          !sameQuoteTerms(previousQuote, result);
      setState(() {
        quote = result;
        review = true;
        quoteRefreshFailed = false;
        quoteChanged = changed || (refresh && quoteChanged && !accepted);
        accepted = refresh && !changed && accepted;
      });
      scheduleQuoteRefresh();
    } catch (e) {
      if (mounted) {
        setState(() {
          error = exchangeQuoteError(e, cardDelivery: canSendToCard && sendToCard);
          if (refresh) {
            quoteRefreshFailed = true;
            accepted = false;
          }
        });
        if (refresh) scheduleQuoteRefresh(retry: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          refreshingQuote = false;
        });
      }
    }
  }

  Future<void> confirm() async {
    if (busy ||
        quoteRefreshFailed ||
        submitted ||
        !accepted ||
        !widget.outflowsEnabled ||
        !review ||
        (quote != null && expired)) {
      return;
    }
    final limitError = inputLimitError() ?? deliveryLimitError(quote);
    if (limitError != null) {
      setState(() => error = limitError);
      return;
    }
    quoteRefreshTimer?.cancel();
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
      if (widget.flow == ExchangeFlow.fund && result['success'] == false) {
        final transfer = result['transfer'];
        final definitelyUnsent = transfer is Map && transfer['status'] == 'failed' &&
            (transfer['sourceTransferId'] ?? '').toString().trim().isEmpty &&
            (transfer['boomFiOrderId'] ?? '').toString().trim().isEmpty &&
            (result['equalsPaymentId'] ?? '').toString().trim().isEmpty;
        if (definitelyUnsent) {
          // A saved terminal failure cannot be resubmitted with its old key.
          // Start a new attempt only after the user reviews and confirms again.
          idempotencyKey = 'mobile-exchange-${DateTime.now().microsecondsSinceEpoch}';
        } else {
          submitted = true;
        }
        throw StateError(exchangeText(result, 'message').isEmpty
            ? 'The transfer was not completed. Check its status before trying again.'
            : exchangeText(result, 'message'));
      }
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
        setState(() {
          error = submitted
              ? 'The transfer outcome needs checking. Refresh transfers before sending again.'
              : friendlyErrorMessage(e);
          if (widget.flow == ExchangeFlow.fund && !submitted) {
            // Preserve the key unless a returned terminal result proved no payment was sent.
            // No quote refresh is scheduled after a submission error.
            quote = null;
            review = false;
            accepted = false;
            quoteChanged = false;
            quoteRefreshFailed = false;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        if (error != null) scrollToResult();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final inputFeeDetails = (inputLimits ?? const BoomFiFeesAndLimits()).descriptions(
        source?.currency ?? '', withdrawal: widget.flow == ExchangeFlow.withdraw);
    final deliveryFeeDetails = (deliveryLimits ?? const BoomFiFeesAndLimits()).descriptions(
        destination?.currency ?? '', withdrawal: true);

    depositWallets = ref.watch(exchangeCardDepositAddressesProvider);
    if (widget.flow == ExchangeFlow.fund &&
        (budget == null || wallet == null)) {
      return AlertDialog(
          title: const Text('Fiat to crypto'),
          content: Text(budget == null
              ? 'A Fiat account supporting EUR and Exchange EUR funding details are required.'
              : depositWallets.isLoading
                  ? 'Loading your Crypto card receiving networks…'
                  : depositWallets.hasError
                      ? 'Could not load your Crypto card receiving networks. Please retry.'
                      : 'No Crypto card receiving address matches an available BoomFi crypto network.'),
          actions: [
            if (depositWallets.hasError)
              TextButton(
                  onPressed: () {
                    ref.invalidate(depositAddressesProvider);
                    ref.invalidate(exchangeCardDepositAddressesProvider);
                  },
                  child: const Text('Retry')),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'))
          ]);
    }
    final title = widget.flow == ExchangeFlow.fund
        ? (context.isExampleTheme
            ? 'Fiat account to Crypto card'
            : 'Fiat account to Crypto card')
        : widget.flow == ExchangeFlow.withdraw
            ? 'Withdraw from Exchange'
            : 'Convert currency';
    final fees = exchangeMap(exchangeValue(quote ?? {}, 'fees'));
    return PopScope(
        canPop: !busy,
        child: ExchangeDialog(
            scrollController: scrollController,
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
                    child: const Text('Edit')),
              if (!submitted)
                _primaryAction(context,
                    onPressed: busy || quoteRefreshFailed ||
                            fundingBalanceRefreshFailed ||
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
                const Text(
                    'Transfer EUR from your Fiat account, exchange it, and send crypto to your Crypto card. Review the quote before confirming.'),
                Text(
                    'Available in Fiat account: ${(exchangeBudgetBalances(budget!)['EUR'] ?? 0).toStringAsFixed(2)} EUR'),
                if (exchangeBudgetBalances(budget!)
                    .entries
                    .any((entry) => entry.key != 'EUR' && entry.value > 0)) ...[
                  const Text(
                      'Have funds in another currency? Convert them to EUR first, then continue here.'),
                  if (widget.onConvertToEur != null)
                    TextButton(
                        onPressed: locked
                            ? null
                            : () async {
                                final selectedBudget = budget!;
                                setState(() {
                                  busy = true;
                                  error = null;
                                  quote = null;
                                  accepted = false;
                                });
                                try {
                                  await widget.onConvertToEur!(selectedBudget);
                                  final updated =
                                      await ref.read(budgetsProvider.future);
                                  if (mounted) {
                                    setState(() => refreshedBudgets = updated);
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      fundingBalanceRefreshFailed = true;
                                      error =
                                          'Could not refresh your Fiat account balance. Close and reopen this transfer before continuing.';
                                    });
                                  }
                                } finally {
                                  if (mounted) setState(() => busy = false);
                                }
                              },
                        child: const Text('Convert to EUR')),
                ],
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
                    label: 'Crypto currency',
                    child: DropdownButtonFormField<String>(
                        initialValue: walletId(wallet!),
                        isExpanded: true,
                        decoration: const InputDecoration(
                            hintText: 'Select an account'),
                        items: walletChoices
                            .map((w) => DropdownMenuItem(
                                value: walletId(w),
                                child: Text(
                                    w.symbol,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged:
                            locked ? null : (v) => edit(() => walletKey = v))),
              ],
              if (widget.flow != ExchangeFlow.fund)
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
                balanceChoice(
                    'To',
                    targets,
                    destination,
                    (v) => edit(() {
                          destinationKey = v;
                          sendToCard = false;
                          bankChoice = 'new';
                          bank = {'beneficiaryType': 'individual'};
                        })),
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
              if ((widget.flow == ExchangeFlow.fund || widget.flow == ExchangeFlow.withdraw) && inputFeeDetails.isNotEmpty)
                ExchangeFeesSummary(
                  title: widget.flow == ExchangeFlow.withdraw ? 'Withdrawal fees and limits' : 'Deposit limits',
                  details: inputFeeDetails),
              if (hasDeliveryWithdrawal && destination != null && deliveryFeeDetails.isNotEmpty)
                ExchangeFeesSummary(title: 'After conversion', details: deliveryFeeDetails),
              if (canSendToCard) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Fund my payment card wallet')),
                  subtitle: const Text(
                      'Optional · Deliver the converted crypto after settlement, ready for a card top-up.'),
                  value: sendToCard,
                  onChanged: locked ||
                          !widget.outflowsEnabled ||
                          cardDestinations.isEmpty
                      ? null
                      : (v) => edit(() => sendToCard = v),
                ),
                if (widget.overview.canTrade('USDT') &&
                    !balances.any((b) => b.currency == 'USDT' && b.isCrypto))
                  const ExchangeNotice(
                      'USDT is not enabled for conversion on your Exchange account.'),
                if (depositWallets.isLoading)
                  const ExchangeNotice(
                      'Loading your payment card wallet addresses…')
                else if (depositWallets.hasError) ...[
                  const ExchangeNotice(
                      'Could not load your payment card wallet addresses.'),
                  TextButton.icon(
                    onPressed: locked
                        ? null
                        : () {
                            ref.invalidate(depositAddressesProvider);
                            ref.invalidate(
                                exchangeCardDepositAddressesProvider);
                          },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry deposit addresses'),
                  ),
                ] else if (cardDestinations.isEmpty)
                  const ExchangeNotice(
                      'No payment card wallet address matches this currency and network. Choose another network.'),
                if (sendToCard && cardDestination != null)
                  ExchangeFieldLabel(
                      label: 'Payment card wallet',
                      child: DropdownButtonFormField<String>(
                          key: ValueKey('card-delivery-${destination?.key}'),
                          initialValue: walletId(cardDestination!),
                          isExpanded: true,
                          items: cardDestinations
                              .map((w) => DropdownMenuItem(
                                  value: walletId(w),
                                  child: Text(
                                      '${w.symbol} · ${w.network} · ${w.shortAddress}',
                                      overflow: TextOverflow.ellipsis)))
                              .toList(),
                          onChanged: locked
                              ? null
                              : (v) => edit(() => walletKey = v))),
              ],
              if (needsBank) ...[
                const ExchangeNotice(
                    'EUR proceeds are sent to your bank account after settlement. Fiat can remain in Exchange for up to 24 hours.'),
                if (savedBanks.isNotEmpty ||
                    eligibleReceiving.isNotEmpty ||
                    eligibleEqualsPayees.isNotEmpty)
                  ExchangeFieldLabel(
                      label: 'Receive fiat in',
                      child: DropdownButtonFormField<String>(
                          key: ValueKey('bank-destination-$bankCurrency'),
                          initialValue: bankChoice.startsWith('saved:') &&
                                  savedBank == null
                              ? 'new'
                              : bankChoice,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              hintText: 'Select an account'),
                          items: [
                            const DropdownMenuItem(
                                value: 'new', child: Text('New payee')),
                            for (final d in savedBanks)
                              DropdownMenuItem(
                                  value: 'saved:${exchangeText(d, 'id')}',
                                  child: Text(bankLabel(d),
                                      overflow: TextOverflow.ellipsis)),
                            for (final p in eligibleEqualsPayees)
                              DropdownMenuItem(
                                  value: 'equals-payee:${p.id}',
                                  child: Text(payeeLabel(p),
                                      overflow: TextOverflow.ellipsis)),
                            for (final r in eligibleReceiving)
                              DropdownMenuItem(
                                  value: r.accountNumber,
                                  child: Text(
                                      'My Fiat account · ${r.holder} · ${r.maskedIdentifier}',
                                      overflow: TextOverflow.ellipsis))
                          ],
                          onChanged: locked
                              ? null
                              : (v) => edit(() {
                                    bankChoice = v ?? 'new';
                                    if (savedBank != null) {
                                      bank = {
                                        'externalAccountId': int.parse(
                                            exchangeText(savedBank!, 'id'))
                                      };
                                      return;
                                    }
                                    final p = eligibleEqualsPayees
                                        .where(
                                            (p) => 'equals-payee:${p.id}' == v)
                                        .firstOrNull;
                                    if (p != null) {
                                      final iban = p.accountReference
                                          .replaceAll(' ', '')
                                          .toUpperCase();
                                      bank = {
                                        'beneficiaryType':
                                            p.firstName.isNotEmpty &&
                                                    p.lastName.isNotEmpty
                                                ? 'individual'
                                                : 'business',
                                        'name': p.name,
                                        'accountNumber': iban,
                                        'bankName': p.bankName,
                                        'accountHolderName': p.name,
                                        'country': iban.substring(0, 2),
                                        'firstName': p.firstName,
                                        'lastName': p.lastName,
                                      };
                                      return;
                                    }
                                    final r = receiving
                                        .where((r) => r.accountNumber == v)
                                        .firstOrNull;
                                    bank = {
                                      'beneficiaryType': 'individual',
                                      'name': r == null
                                          ? ''
                                          : 'Fiat receiving account',
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
                else
                  ExchangeBankFields(
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
                  Text(refreshingQuote
                      ? 'Updating quote…'
                      : quoteRefreshFailed
                          ? 'Quote refresh failed. Retrying automatically…'
                          : expired
                              ? 'Updating expired quote…'
                              : 'Quote refreshes automatically.'),
                  if (quoteChanged)
                    const ExchangeNotice('The rate or fees changed. Review the updated quote and confirm your agreement again.'),
                  if (quoteRefreshFailed && !busy)
                    TextButton(onPressed: () => prepare(refresh: true),
                        child: const Text('Retry quote now')),
                ],
                if (canSendToCard && sendToCard && cardDestination != null)
                  SelectableText(
                      'After settlement: ${destination!.currency} → Crypto card account\n${cardDestination!.network} · ${cardDestination!.address}'),
                if (needsBank)
                  SelectableText(savedBank != null
                      ? bankLabel(savedBank!)
                      : '${bank['accountHolderName']} · ${bank['accountNumber']}'),
                if (widget.flow == ExchangeFlow.withdraw &&
                    source?.isCrypto == true)
                  SelectableText(address),
                if (widget.flow == ExchangeFlow.fund)
                  const Text(
                      'After funding, rates within ±0.5% are accepted automatically. Larger changes require your approval.'),
                ExchangeTerms(
                    accepted: accepted,
                    onChanged: (v) => setState(() {
                      accepted = v;
                      if (v) quoteChanged = false;
                    }),
                    enabled: !busy && !submitted && !quoteRefreshFailed && !expired,
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
