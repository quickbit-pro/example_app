import 'exchange_onboarding_panel.dart';
import 'exchange_deposit_history.dart';
import 'exchange_flow_dialog.dart';
import 'exchange_disclaimer.dart';
import 'exchange_account_details.dart';
import 'exchange_verification_panel.dart';
import 'exchange_support.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../auth/presentation/example_otp_field.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/platform_widgets.dart';
import '../../rewards/domain/rewards_models.dart';
import '../domain/exchange_models.dart';
import '../domain/wallet_models.dart';
import '../domain/exchange_transfer_routes.dart';
import '../data/wallet_providers.dart';
import '../../crypto/presentation/crypto_trade_screen.dart';

Color _hairline(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? ExamplePalette.of(context).borderSubtle
        : ExamplePalette.of(context).borderSubtle.withValues(alpha: alpha);

class ExchangePanel extends ConsumerWidget {
  const ExchangePanel({
    required this.config,
    required this.budgets,
    required this.wallets,
    required this.transferSection,
    this.onConvertToEur,
    super.key,
  });

  final MobileTenantConfig config;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  final Widget transferSection;
  final Future<void> Function(PlatformResource budget)? onConvertToEur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(exchangeOverviewProvider);
    final isExample = context.isExampleTheme;

    return overview.when(
      skipLoadingOnReload: true,
      loading: () => isExample
          ? PlatformLoadingGroup(
              title: context.tr('Exchange balances'),
              rows: 3,
              label: context.tr('Loading Exchange'),
            )
          : LoadingState(label: context.tr('Loading Exchange')),
      error: (error, stackTrace) => isExample
          ? const _ExampleExchangeUnavailable()
          : ErrorState(
              error: error,
              onRetry: () => ref.invalidate(exchangeOverviewProvider),
            ),
      data: (data) {
        if (!data.isReady) {
          return const ExchangeOnboardingPanel(legacy: ExchangeVerificationPanel());
        }

        return _ReadyExchangePanel(
          overview: data,
          outflowsEnabled: config.walletOutflowsEnabled,
          budgets: budgets,
          wallets: wallets,
          transferSection: transferSection,
          onConvertToEur: onConvertToEur,
        );
      },
    );
  }
}

class _ExampleExchangeUnavailable extends ConsumerWidget {
  const _ExampleExchangeUnavailable();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Semantics(
        liveRegion: true,
        container: true,
        child: ExampleGlassPanel(
          radius: 20,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ExampleIconTile(
                    icon: Icons.swap_horiz_rounded,
                    color: ExamplePalette.of(context).warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('Exchange is not available right now'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                context.tr(
                    'The exchange provider did not return your balances. Your money and crypto accounts are not affected.'),
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: ExampleInk.secondary(context),
                ),
              ),
              const SizedBox(height: 14),
              ExampleGlassButton(
                label: context.tr('Try again'),
                icon: Icons.refresh_rounded,
                tone: ExampleGlassButtonTone.neutral,
                expand: false,
                sheen: false,
                height: 44,
                radius: 12,
                onPressed: () => ref.invalidate(exchangeOverviewProvider),
              ),
            ],
          ),
        ),
      );
}


/// Open the same funding flow from an individual Fiat account's Move menu.
Future<void> showFiatAccountToCryptoCardTransfer(
  BuildContext context,
  WidgetRef ref, {
  required PlatformResource sourceBudget,
  required List<PlatformResource> budgets,
  Future<void> Function(PlatformResource budget)? onConvertToEur,
}) async {
  try {
    final config = await ref.read(mobileTenantConfigProvider.future);
    if (!context.mounted) return;
    if (!config.boomFiExchangeEnabled || !config.equalsMoneyEnabled ||
        !config.walletOutflowsEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Transfers are currently unavailable for this account.')));
      return;
    }
    final overview = await ref.read(exchangeOverviewProvider.future);
    if (!context.mounted) return;
    if (!overview.isReady) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Complete Exchange setup before transferring.')));
      return;
    }
    final wallets = await ref.read(hoppaWalletAssetsProvider.future);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ExchangeFlowDialog(
        flow: ExchangeFlow.fund,
        overview: overview,
        outflowsEnabled: config.walletOutflowsEnabled,
        budgets: [sourceBudget, ...budgets.where((b) => b.id != sourceBudget.id)],
        wallets: wallets,
        onConvertToEur: onConvertToEur,
      ),
    );
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

/// Transfer shortcuts shared by the Money, Crypto and Exchange tab row.
class ExchangeAccountTransferActions extends ConsumerWidget {
  const ExchangeAccountTransferActions({this.config, this.budgets, this.wallets, this.onConvertToEur, super.key});
  final MobileTenantConfig? config;
  final List<PlatformResource>? budgets;
  final List<HoppaWalletAsset>? wallets;
  final Future<void> Function(PlatformResource budget)? onConvertToEur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenant = config ?? ref.watch(mobileTenantConfigProvider).valueOrNull;
    final overview = ref.watch(exchangeOverviewProvider).valueOrNull;
    if (tenant == null || overview == null || !overview.isReady) { return const SizedBox.shrink(); }
    final budgets = this.budgets ?? ref.watch(budgetsProvider).valueOrNull ?? <PlatformResource>[];
    final wallets = this.wallets ?? ref.watch(hoppaWalletAssetsProvider).valueOrNull ?? <HoppaWalletAsset>[];
    final outflowsEnabled = tenant.walletOutflowsEnabled;
    void open(ExchangeFlow flow) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExchangeFlowDialog(
            flow: flow,
            overview: overview,
            outflowsEnabled: outflowsEnabled,
            onConvertToEur: onConvertToEur,
            budgets: budgets,
            wallets: wallets));
    final addresses = budgets.isEmpty
        ? const AsyncData<List<HoppaWalletAsset>>([])
        : ref.watch(exchangeCardDepositAddressesProvider);
    final eligibleWallets = exchangeTransferRoutes(addresses.valueOrNull ?? wallets, wallets)
        .where((w) => overview.canTrade(w.symbol) && overview.balances.any((b) =>
            b.currency == w.symbol && b.chainId == exchangeChainId(w.network))).toList();
    final euroBudgets = budgets;
    final fundingWallets = eligibleWallets.where((w) => overview.canTrade(w.symbol) &&
        overview.balances.any((b) => b.currency == w.symbol && b.chainId == exchangeChainId(w.network))).toList();
    String? unavailable({required bool funding}) {
      if (!outflowsEnabled) { return 'Transfers are currently unavailable for this account.'; }
      if (euroBudgets.isEmpty) { return 'An active Fiat account is needed.'; }
      if (eligibleWallets.isEmpty) {
        if (addresses.isLoading) { return 'Loading your Crypto card transfer networks…'; }
        if (addresses.hasError) { return 'Could not load your Crypto card transfer networks. Please retry.'; }
        return 'No Crypto card transfer network matches an available BoomFi crypto account yet.';
      }
      if (funding && !overview.fiatFundingCurrencies.contains('EUR')) { return 'BoomFi has not provided EUR bank funding details for this account yet.'; }
      if (funding && fundingWallets.isEmpty) { return 'No matching crypto receiving network is available in BoomFi yet.'; }
      return null;
    }
    final fundReason = unavailable(funding: true);
    final sellReason = unavailable(funding: false);
    void sell() => _showCryptoToEqualsDialog(context, ref, overview, euroBudgets, eligibleWallets, wallets);

    Widget button(String label, String? reason, VoidCallback pressed) => Tooltip(
      message: reason ?? label,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        onPressed: reason == null ? pressed : null,
        child: Text(context.tr(label), textAlign: TextAlign.center),
      ),
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, constraints) {
        final funding = button('Fiat account to Crypto card', fundReason, () => open(ExchangeFlow.fund));
        final selling = button('Crypto card to Fiat account', sellReason, sell);
        if (constraints.maxWidth >= 600 * MediaQuery.textScalerOf(context).scale(1)) {
          return Row(children: [Expanded(child: funding), const SizedBox(width: 12), Expanded(child: selling)]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          funding, const SizedBox(height: 8), selling,
        ]);
      }),
      if (fundReason != null || sellReason != null) ...[
        const SizedBox(height: 8),
        for (final reason in {if (fundReason != null) fundReason, if (sellReason != null) sellReason})
          Text(context.tr(reason), style: Theme.of(context).textTheme.bodySmall),
        if (addresses.hasError)
          TextButton(onPressed: () { ref.invalidate(depositAddressesProvider); ref.invalidate(exchangeCardDepositAddressesProvider); },
              child: const Text('Retry transfer networks')),
      ],
    ]);
  }
}

class _ReadyExchangePanel extends ConsumerWidget {
  const _ReadyExchangePanel({
    required this.overview,
    required this.outflowsEnabled,
    required this.budgets,
    required this.wallets,
    required this.transferSection,
    this.onConvertToEur,
  });

  final BoomFiExchangeOverview overview;
  final bool outflowsEnabled;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  final Widget transferSection;
  final Future<void> Function(PlatformResource budget)? onConvertToEur;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(ExchangeFlow flow) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExchangeFlowDialog(
            flow: flow,
            overview: overview,
            outflowsEnabled: outflowsEnabled,
            onConvertToEur: onConvertToEur,
            budgets: budgets,
            wallets: wallets));
    final example = context.isExampleTheme;
    Widget action(String label, VoidCallback? onPressed,
            {bool primary = false}) =>
        example
            ? ExampleGlassButton(
                label: context.tr(label),
                onPressed: onPressed,
                expand: false,
                height: 44,
                radius: 12,
                tone: primary
                    ? ExampleGlassButtonTone.primary
                    : ExampleGlassButtonTone.neutral)
            : primary
                ? FilledButton(
                    onPressed: onPressed, child: Text(context.tr(label)))
                : OutlinedButton(
                    onPressed: onPressed, child: Text(context.tr(label)));
    final addresses = budgets.isEmpty
        ? const AsyncData<List<HoppaWalletAsset>>([])
        : ref.watch(exchangeCardDepositAddressesProvider);
    final eligibleWallets = exchangeTransferRoutes(addresses.valueOrNull ?? wallets, wallets)
        .where((w) => overview.canTrade(w.symbol) && overview.balances.any((b) =>
            b.currency == w.symbol && b.chainId == exchangeChainId(w.network))).toList();
    final euroBudgets = budgets;
    final fundingWallets = eligibleWallets.where((w) => overview.canTrade(w.symbol) &&
        overview.balances.any((b) => b.currency == w.symbol && b.chainId == exchangeChainId(w.network))).toList();
    String? unavailable({required bool funding}) {
      if (!outflowsEnabled) { return 'Transfers are currently unavailable for this account.'; }
      if (euroBudgets.isEmpty) { return 'An active Fiat account is needed.'; }
      if (eligibleWallets.isEmpty) {
        if (addresses.isLoading) { return 'Loading your Crypto card transfer networks…'; }
        if (addresses.hasError) { return 'Could not load your Crypto card transfer networks. Please retry.'; }
        return 'No Crypto card transfer network matches an available BoomFi crypto account yet.';
      }
      if (funding && !overview.fiatFundingCurrencies.contains('EUR')) { return 'BoomFi has not provided EUR bank funding details for this account yet.'; }
      if (funding && fundingWallets.isEmpty) { return 'No matching crypto receiving network is available in BoomFi yet.'; }
      return null;
    }
    final fundReason = unavailable(funding: true);
    final sellReason = unavailable(funding: false);
    void sell() => _showCryptoToEqualsDialog(context, ref, overview, euroBudgets, eligibleWallets, wallets);
    final hasFunds = overview.balances.any((b) => b.amount > 0);
    final canConvert = overview.balances.any((from) =>
        from.amount > 0 &&
        overview.balances.any((to) =>
            to.isCrypto != from.isCrypto &&
            (to.isCrypto || to.currency == 'EUR')));
    void details({bool destinations = false}) => showDialog<void>(
        context: context,
        builder: (_) => ExchangeAccountDetails(
            destinations: destinations, outflowsEnabled: outflowsEnabled));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Exchange',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (overview.accountName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(overview.accountName,
                style: Theme.of(context).textTheme.bodyMedium)
          ],
        ])),
        IconButton(
            tooltip: 'Refresh Exchange',
            onPressed: () {
              ref.invalidate(exchangeVerificationProvider);
              ref.invalidate(exchangeOverviewProvider);
              ref.invalidate(exchangeTransfersProvider);
              ref.invalidate(exchangeCardDepositAddressesProvider);
              ref.invalidate(depositAddressesProvider);
            },
            icon: const Icon(Icons.refresh)),
      ]),
      const SizedBox(height: 24),
      Wrap(spacing: 12, runSpacing: 12, children: [
        FilledButton.icon(
            onPressed: () => details(),
            icon: const Icon(Icons.add),
            label: const Text('Deposit')),
        action('Convert', canConvert ? () => open(ExchangeFlow.convert) : null),
        action(
            'Withdraw',
            outflowsEnabled &&
                    overview.balances.any((b) =>
                        b.amount > 0 && (b.isCrypto || b.currency == 'EUR'))
                ? () => open(ExchangeFlow.withdraw)
                : null),
        PopupMenuButton<String>(
          tooltip: 'More exchange options',
          onSelected: (value) {
            if (value == 'destinations') details(destinations: true);
            if (value == 'fund') open(ExchangeFlow.fund);
            if (value == 'sell') {
              sell();
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'destinations', child: Text('Saved destinations')),
            PopupMenuItem(
                value: 'fund',
                enabled: fundReason == null,
                child: const Text('Fiat account to Crypto card')),
            PopupMenuItem(
                value: 'sell',
                enabled: sellReason == null,
                child: const Text('Crypto card to Fiat account')),
          ],
          child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('More'),
                SizedBox(width: 4),
                Icon(Icons.expand_more, size: 20)
              ])),
        ),
      ]),
      if (hasFunds && (!outflowsEnabled || !canConvert)) ...[
        const SizedBox(height: 20),
        ExchangeNotice(!outflowsEnabled
            ? 'Withdrawals are currently unavailable for this account.'
            : 'Conversion will be available when a compatible currency account is ready.'),
      ],
      const ExchangeDisclaimer(),
      const SizedBox(height: 24),
      Text('Balances', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          final balances = overview.displayBalances;
          return Wrap(spacing: 16, runSpacing: 16, children: [
            for (final balance in balances)
              SizedBox(width: (constraints.maxWidth - 32) / 3,
                child: ExampleGlassPanel(padding: const EdgeInsets.all(20), child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(balance.currency, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    ExampleAmount(amount: balance.amount, currency: balance.currency, size: ExampleAmountSize.small),
                    const SizedBox(height: 4),
                    Text(balance.isCrypto ? 'Available across networks' : 'Available for conversion or withdrawal',
                      style: Theme.of(context).textTheme.bodySmall),
                  ]))),
          ]);
        }
        return Column(children: [
      if (example)
        ExampleListGroup(children: [
          for (final balance in overview.displayBalances)
            ExampleRow(
                title: balance.currency,
                subtitle: balance.isCrypto ? null : 'Fiat',
                trailing: ExampleAmount(
                    amount: balance.amount,
                    currency: balance.currency,
                    size: ExampleAmountSize.small))
        ])
      else
        for (final balance in overview.displayBalances)
          ListTile(
              title: Text(balance.currency),
              subtitle: balance.isCrypto ? null : const Text('Fiat'),
              trailing: Text(balance.amount.toString())),
        ]);
      }),
      const SizedBox(height: 28),
      ExchangeDepositHistory(deposits: overview.deposits,
          transfers: ref.watch(exchangeTransfersProvider).valueOrNull ?? const []),
      const SizedBox(height: 24),
      transferSection,
    ]);
  }
}

class _ExchangeFact extends StatelessWidget {
  const _ExchangeFact({required this.label, required this.value});
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label)),
        Flexible(child: Text(value, textAlign: TextAlign.end))
      ]));
}

String _formatRate(Object value) => value.toString();

class _QuoteReview extends StatelessWidget {
  const _QuoteReview({required this.quote});

  final Map<String, dynamic> quote;

  @override
  Widget build(BuildContext context) {
    final fees = _map(_value(quote, 'fees', 'Fees'));
    if (context.isExampleTheme) { return _example(context, fees); }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Quote review'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(context.tr(
                'Rate: {p0}', {'p0': _value(quote, 'rate', 'Rate') ?? '—'})),
            Text(
              context.tr('You receive: {p0} {p1}', {
                'p0': _value(quote, 'buy_amount', 'BuyAmount') ??
                    _value(quote, 'buyAmount', 'BuyAmount') ??
                    '—',
                'p1': _value(quote, 'buy_currency', 'BuyCurrency') ??
                    _value(quote, 'buyCurrency', 'BuyCurrency') ??
                    ''
              }),
            ),
            Text(
              context.tr('Fee: {p0} {p1}', {
                'p0': _value(fees, 'total_fee', 'TotalFee') ??
                    _value(fees, 'totalFee', 'TotalFee') ??
                    '—',
                'p1': _value(fees, 'fee_ccy', 'FeeCcy') ??
                    _value(fees, 'feeCcy', 'FeeCcy') ??
                    ''
              }),
            ),
            if ((_value(quote, 'expiry', 'Expiry')?.toString() ?? '')
                .isNotEmpty)
              Text(context.tr(
                  'Expires: {p0}', {'p0': _value(quote, 'expiry', 'Expiry')})),
          ],
        ),
      ),
    );
  }

  Widget _example(BuildContext context, Map<String, dynamic> fees) {
    final receive = _value(quote, 'buy_amount', 'BuyAmount') ??
        _value(quote, 'buyAmount', 'BuyAmount');
    final receiveCurrency = (_value(quote, 'buy_currency', 'BuyCurrency') ??
            _value(quote, 'buyCurrency', 'BuyCurrency') ??
            '')
        .toString()
        .trim();
    final receiveValue = double.tryParse(receive?.toString().trim() ?? '');
    final rate = _value(quote, 'rate', 'Rate');
    final fee = _value(fees, 'total_fee', 'TotalFee') ??
        _value(fees, 'totalFee', 'TotalFee');
    final feeCurrency = (_value(fees, 'fee_ccy', 'FeeCcy') ??
            _value(fees, 'feeCcy', 'FeeCcy') ??
            '')
        .toString()
        .trim();
    final expiry = (_value(quote, 'expiry', 'Expiry')?.toString() ?? '').trim();

    return ExampleGlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('You receive'),
            style: TextStyle(
              fontSize: 11.5,
              color: ExampleInk.tertiary(context),
            ),
          ),
          const SizedBox(height: 3),
          if (receiveValue != null)
            ExampleAmount(
              amount: receiveValue,
              currency: receiveCurrency,
              size: ExampleAmountSize.small,
              code: ExampleAmountCode.always,
            )
          else
            Text(
              '${receive ?? '—'} $receiveCurrency'.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: _hairline(context, .14)),
          const SizedBox(height: 9),
          _ExchangeFact(
            label: context.tr('Rate'),
            value: rate == null ? '—' : _formatRate(rate),
          ),
          const SizedBox(height: 4),
          _ExchangeFact(
            label: context.tr('Fee'),
            value: fee == null ? '—' : '$fee $feeCurrency'.trim(),
          ),
          if (expiry.isNotEmpty) ...[
            const SizedBox(height: 4),
            _ExchangeFact(label: context.tr('Quote expires'), value: expiry),
          ],
        ],
      ),
    );
  }
}

class _DropdownLabel extends StatelessWidget {
  const _DropdownLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => context.isExampleTheme
      ? Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)
      : Text(text);
}

class _TransferDialogTitle extends StatelessWidget {
  const _TransferDialogTitle({required this.example, required this.whiteLabel});

  final String example;
  final String whiteLabel;

  @override
  Widget build(BuildContext context) =>
      Text(context.isExampleTheme ? example : whiteLabel);
}

class _TransferDialogLede extends StatelessWidget {
  const _TransferDialogLede({required this.text, this.large = false});

  final String text;

  final bool large;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) { return PlatformLede(text: text); }
    return Text(
      text,
      style: large ? Theme.of(context).textTheme.bodyLarge : null,
    );
  }
}

Future<void> _showCryptoToEqualsDialog(
  BuildContext context,
  WidgetRef ref,
  BoomFiExchangeOverview overview,
  List<PlatformResource> budgets,
  List<HoppaWalletAsset> wallets,
  List<HoppaWalletAsset> balances,
) async {
  final currencyWallets = exchangeTransferCurrencyRoutes(
      wallets, canTrade: overview.canTrade);
  if (currencyWallets.isEmpty) return;
  var wallet = currencyWallets.first;
  var budget = budgets.first;
  var cryptoAmount = '';
  const fiatCurrency = 'EUR';
  var currentBalances = balances;
  var refreshing = false;
  String? balanceError;
  double available() => currentBalances.where((b) => b.symbol.toUpperCase() == wallet.symbol).firstOrNull?.amount ?? 0;
  double quantumAvailable() => currentBalances.where((b) => b.symbol.toUpperCase() == 'USD').firstOrNull?.amount ?? 0;
  Map<String, dynamic>? quote;
  String verificationToken = '';
  var otp = '';
  var busy = false;
  var termsAccepted = false;
  final reference = 'mobile-equals-${DateTime.now().microsecondsSinceEpoch}';

  Map<String, Object?> request() => {
        'boomFiAccountId': overview.accountId.toString(),
        'reference': reference,
        'chainId': exchangeChainId(wallet.network),
        'currency': wallet.symbol.toUpperCase(),
        'cryptoAmount': cryptoAmount.replaceAll(',', '.'),
        'fiatCurrency': fiatCurrency,
        'targetBudgetId': budget.id,
      };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => _FullScreenExchangeDialog(
        title: const _TransferDialogTitle(
          example: 'Crypto card to Fiat account',
          whiteLabel: 'Crypto card to Fiat account',
        ),
        canClose: !busy,
        primaryLabel: quote == null
            ? 'Get quote'
            : verificationToken.isEmpty
                ? 'Send verification code'
                : 'Confirm transfer',
        onPrimary: quote == null
            ? (busy || refreshing || balanceError != null ||
                    (double.tryParse(cryptoAmount.replaceAll(',', '.')) ?? 0) <=
                        0 ||
                    exchangeChainId(wallet.network) == 0 ||
                    (double.tryParse(cryptoAmount.replaceAll(',', '.')) ?? 0) > available()
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final result = await ref
                          .read(mobilePlatformApiProvider)
                          .getInterlaceToEqualsQuote(request());
                      if (context.mounted) setState(() => quote = result);
                    } catch (error) {
                      if (context.mounted) _showError(context, error);
                    } finally {
                      if (context.mounted) setState(() => busy = false);
                    }
                  })
            : verificationToken.isEmpty
                ? (busy || !termsAccepted
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final result = await ref
                              .read(mobilePlatformApiProvider)
                              .initiateInterlaceToEquals(request());
                          final token = (_value(
                                    result,
                                    'verificationToken',
                                    'VerificationToken',
                                  ) ??
                                  '')
                              .toString();
                          if (token.isEmpty) {
                            throw StateError(
                              'The provider did not return a verification token.',
                            );
                          }
                          setState(() => verificationToken = token);
                        } catch (error) {
                          if (context.mounted) _showError(context, error);
                        } finally {
                          if (context.mounted) setState(() => busy = false);
                        }
                      })
                : (busy || !termsAccepted || otp.length != 8
                    ? null
                    : () async {
                        setState(() => busy = true);
                        try {
                          final result = await ref
                              .read(mobilePlatformApiProvider)
                              .confirmInterlaceToEquals(
                                verificationToken: verificationToken,
                                otpCode: otp,
                              );
                          ref.invalidate(exchangeTransfersProvider);
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(result.message)),
                            );
                          }
                        } catch (error) {
                          if (context.mounted) _showError(context, error);
                        } finally {
                          if (context.mounted) setState(() => busy = false);
                        }
                      }),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TransferDialogLede(
                large: true,
                text: context.tr(
                    'Convert crypto and deliver the fiat proceeds to your fiat account.'),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: wallet.symbol,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr('Crypto currency')),
                items: [
                  for (final item in currencyWallets)
                    DropdownMenuItem(
                      value: item.symbol,
                      child: _DropdownLabel(
                        item.symbol,
                      ),
                    ),
                ],
                onChanged: busy || verificationToken.isNotEmpty
                    ? null
                    : (value) => setState(() {
                          wallet = currencyWallets.firstWhere(
                              (item) => item.symbol == value);
                          quote = null;
                          termsAccepted = false;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: budget.id,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr('Fiat account destination')),
                items: [
                  for (final item in budgets)
                    DropdownMenuItem(
                      value: item.id,
                      child: _DropdownLabel(item.title),
                    ),
                ],
                onChanged: busy || verificationToken.isNotEmpty
                    ? null
                    : (value) => setState(() {
                          budget =
                              budgets.firstWhere((item) => item.id == value);
                          quote = null;
                          termsAccepted = false;
                        }),
              ),
              const SizedBox(height: 12),
              Text('Available across networks: ${_amount(available())} ${wallet.symbol}'),
              const Text('You receive EUR in your Fiat account.'),
              if ((double.tryParse(cryptoAmount.replaceAll(',', '.')) ?? 0) > available() || available() <= 0) ...[
                const SizedBox(height: 8),
                const Text('Your crypto balance is insufficient. Convert Quantum USD first, then continue with this transfer.'),
                if (quantumAvailable() > 0)
                  TextButton(
                    onPressed: busy || refreshing || verificationToken.isNotEmpty ? null : () async {
                      setState(() { refreshing = true; quote = null; termsAccepted = false; balanceError = null; });
                      try {
                        await showCryptoExchangeSheet(context, initialAsset: wallet.symbol);
                        ref.invalidate(userAssetsProvider);
                        ref.invalidate(userWalletsProvider);
                        ref.invalidate(hoppaWalletAssetsProvider);
                        final updated = await ref.read(hoppaWalletAssetsProvider.future);
                        if (context.mounted) setState(() => currentBalances = updated);
                      } catch (_) {
                        if (context.mounted) setState(() => balanceError = 'Could not refresh your crypto balance. Close and reopen this transfer before continuing.');
                      } finally {
                        if (context.mounted) setState(() => refreshing = false);
                      }
                    },
                    child: Text('Convert Quantum USD to ${wallet.symbol}'),
                  )
                else
                  const Text('Add crypto or fund your Quantum USD balance to continue.'),
              ],
              if (refreshing) const Text('Refreshing your available balance…'),
              if (balanceError != null) Text(balanceError!),
              const SizedBox(height: 12),
              TextField(
                enabled: !busy && verificationToken.isEmpty,
                decoration: InputDecoration(
                    labelText:
                        context.tr('Amount ({p0})', {'p0': wallet.symbol})),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: busy || verificationToken.isNotEmpty
                    ? null
                    : (value) => setState(() {
                          cryptoAmount = value;
                          quote = null;
                          termsAccepted = false;
                        }),
              ),
              if (quote != null) ...[
                const SizedBox(height: 12),
                _QuoteReview(quote: quote!),
              ],
              if (quote != null)
                ExchangeTerms(
                    accepted: termsAccepted,
                    enabled: !busy && verificationToken.isEmpty,
                    onChanged: (v) => setState(() => termsAccepted = v)),
              if (verificationToken.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  context.tr('Email verification code'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                _ExchangeOtpField(
                  enabled: !busy,
                  onChanged: (value) => setState(() => otp = value.trim()),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

/// The eight code cells of the crypto-to-fiat confirmation. The dialog above
/// is a closure over plain locals, so the controller the cells need lives
/// here, where it is disposed with the route rather than guessed at after
/// `showDialog` returns.
class _ExchangeOtpField extends StatefulWidget {
  const _ExchangeOtpField({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  State<_ExchangeOtpField> createState() => _ExchangeOtpFieldState();
}

class _ExchangeOtpFieldState extends State<_ExchangeOtpField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExampleOtpField(
        controller: _controller,
        length: 8,
        enabled: widget.enabled,
        label: context.tr('Email verification code'),
        onChanged: widget.onChanged,
      );
}

class _FullScreenExchangeDialog extends StatelessWidget {
  const _FullScreenExchangeDialog({
    required this.title,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
    this.canClose = true,
  });

  final Widget title;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool canClose;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (kIsWeb && size.width >= 600) {
      return PopScope(
        canPop: canClose,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(
            horizontal: size.width < 720 ? 16 : 32,
            vertical: 24,
          ),
          child: Material(
            color: context.isExampleTheme
                ? ExampleSurface.navigationOf(context)
                : Theme.of(context).scaffoldBackgroundColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: context.isExampleTheme
                    ? _hairline(context, .16)
                    : Colors.transparent,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 680,
              height: (size.height - 48).clamp(380, 560).toDouble(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: DefaultTextStyle.merge(
                            style: Theme.of(context).textTheme.titleLarge,
                            child: title,
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('Close'),
                          visualDensity: VisualDensity.compact,
                          onPressed: canClose
                              ? () => Navigator.of(context).pop()
                              : null,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: SafeArea(top: false, child: child)),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          style: context.isExampleTheme
                              ? TextButton.styleFrom(
                                  minimumSize: const Size(64, 44),
                                )
                              : null,
                          onPressed: canClose
                              ? () => Navigator.of(context).pop()
                              : null,
                          child: Text(context.tr('Cancel')),
                        ),
                        const SizedBox(width: 10),
                        if (context.isExampleTheme)
                          SizedBox(
                            width: 180,
                            child: ExampleGlassButton(
                              label: primaryLabel,
                              height: 44,
                              onPressed: onPrimary,
                            ),
                          )
                        else
                          SizedBox(
                            width: 180,
                            height: 40,
                            child: FilledButton(
                              onPressed: onPrimary,
                              child: Text(primaryLabel),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: canClose,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: context.tr('Close'),
              onPressed: canClose ? () => Navigator.of(context).pop() : null,
              icon: const Icon(Icons.close),
            ),
            title: title,
          ),
          body: SafeArea(child: child),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: context.isExampleTheme
                  ? ExampleGlassButton(
                      label: primaryLabel,
                      height: 52,
                      onPressed: onPrimary,
                    )
                  : SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: onPrimary,
                        child: Text(primaryLabel),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) { return value; }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

Object? _value(Map<String, dynamic> json, String first, String second) =>
    json[first] ?? json[second];

String _amount(double value) => value.toStringAsFixed(6);

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(friendlyErrorMessage(error))),
  );
}
