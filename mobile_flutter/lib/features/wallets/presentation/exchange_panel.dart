import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../auth/presentation/example_otp_field.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/platform_widgets.dart';
import '../../rewards/domain/rewards_models.dart';
import '../domain/exchange_models.dart';
import '../domain/wallet_models.dart';

Color _fadedInk(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? (alpha >= .56
            ? ExamplePalette.of(context).textSecondary
            : ExamplePalette.of(context).textTertiary)
        : ExamplePalette.of(context).ink.withValues(alpha: alpha);

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
    super.key,
  });

  final MobileTenantConfig config;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  final Widget transferSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(exchangeOverviewProvider);
    final isExample = context.isExampleTheme;

    return overview.when(
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
          return const _ExchangeSetupState();
        }

        return _ReadyExchangePanel(
          overview: data,
          outflowsEnabled: config.walletOutflowsEnabled,
          budgets: budgets,
          wallets: wallets,
          transferSection: transferSection,
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

class _ExchangeSetupState extends StatelessWidget {
  const _ExchangeSetupState();

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleEmptyState(
        icon: Icons.hourglass_top_rounded,
        title: context.tr('Exchange is being switched on'),
        body: context.tr(
            'Balances and conversions appear here once the provider activates your organisation. Nothing is needed from you.'),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.hourglass_top,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('Exchange account setup in progress'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                  'Exchange is enabled for this app. Balances and actions will appear after the provider activates your organisation.'),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyExchangePanel extends ConsumerWidget {
  const _ReadyExchangePanel({
    required this.overview,
    required this.outflowsEnabled,
    required this.budgets,
    required this.wallets,
    required this.transferSection,
  });

  final BoomFiExchangeOverview overview;
  final bool outflowsEnabled;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  final Widget transferSection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (context.isExampleTheme) {
      return _ExampleReadyExchangePanel(
        overview: overview,
        outflowsEnabled: outflowsEnabled,
        budgets: budgets,
        wallets: wallets,
        transferSection: transferSection,
      );
    }
    final cryptoBalances = overview.balances.where((item) => item.isCrypto);
    final fiatBalances = overview.balances.where((item) => !item.isCrypto);
    final canExchange = cryptoBalances.isNotEmpty && fiatBalances.isNotEmpty;
    final equalsBudgets = _distinctBy(
      budgets.where((item) => item.id.isNotEmpty),
      (item) => item.id,
    );
    final cryptoWallets = _distinctBy(
      wallets.where((item) =>
          item.walletId.isNotEmpty &&
          const {'USDC', 'USDT'}.contains(item.symbol.toUpperCase())),
      (item) => item.walletId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Exchange account'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                if (overview.accountName.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    overview.accountName,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  context.tr(
                      'Convert balances or move money between your Crypto card and fiat account.'),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: canExchange
                          ? () => _showExchangeDialog(
                                context,
                                ref,
                                overview,
                                outflowsEnabled,
                              )
                          : null,
                      icon: const Icon(Icons.currency_exchange),
                      label: Text(context.tr('Exchange')),
                    ),
                    OutlinedButton.icon(
                      style: _exchangeActionStyle(context),
                      onPressed: outflowsEnabled &&
                              equalsBudgets.isNotEmpty &&
                              cryptoWallets.isNotEmpty
                          ? () => _showEqualsToCryptoDialog(
                                context,
                                ref,
                                equalsBudgets,
                              )
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(context.tr('Fiat → Crypto')),
                    ),
                    OutlinedButton.icon(
                      style: _exchangeActionStyle(context),
                      onPressed: outflowsEnabled &&
                              equalsBudgets.isNotEmpty &&
                              cryptoWallets.isNotEmpty
                          ? () => _showCryptoToEqualsDialog(
                                context,
                                ref,
                                overview,
                                equalsBudgets,
                                cryptoWallets,
                              )
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: Text(context.tr('Crypto → Fiat')),
                    ),
                  ],
                ),
                if (!outflowsEnabled) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                              'Quotes and balances are available. Money movement is locked until this white-label installation enables outflows.'),
                        ),
                      ),
                    ],
                  ),
                ] else if (equalsBudgets.isEmpty || cryptoWallets.isEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.info_outline, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          context.tr(
                              'BoomFi Exchange is ready. Fiat transfers become available after an active budget and a USDC or USDT wallet are linked to this account.'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(context.tr('Exchange balances'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        if (overview.balances.isEmpty)
          EmptyState(
            title: context.tr('No Exchange balances'),
            message:
                context.tr('Balances will appear after provider settlement.'),
            icon: Icons.account_balance_wallet_outlined,
          )
        else
          for (final balance in overview.balances)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CurrencyLogo(
                      symbol: balance.currency,
                      fallbackIcon: balance.isCrypto
                          ? Icons.token_outlined
                          : Icons.account_balance_wallet_outlined,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  balance.currency,
                                  style:
                                      Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              Text(
                                '${_exchangeBalanceAmount(balance.amount, isCrypto: balance.isCrypto)} ${balance.currency}',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  balance.isCrypto
                                      ? (balance.chainName.isEmpty
                                          ? context.tr('Chain {p0}',
                                              {'p0': balance.chainId})
                                          : balance.chainName)
                                      : context.tr('Fiat balance'),
                                ),
                              ),
                              if (balance.pendingAmount != 0)
                                Text(
                                  context.tr('{p0} pending', {
                                    'p0': _exchangeBalanceAmount(
                                        balance.pendingAmount,
                                        isCrypto: balance.isCrypto)
                                  }),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 18),
        transferSection,
      ],
    );
  }
}

/// Twilight "Accounts · Exchange" artboard: From/To swap cards, live rate and
/// fee from the BoomFi quote, and the exchange balances underneath.
class _ExampleReadyExchangePanel extends ConsumerStatefulWidget {
  const _ExampleReadyExchangePanel({
    required this.overview,
    required this.outflowsEnabled,
    required this.budgets,
    required this.wallets,
    required this.transferSection,
  });

  final BoomFiExchangeOverview overview;
  final bool outflowsEnabled;
  final List<PlatformResource> budgets;
  final List<HoppaWalletAsset> wallets;
  final Widget transferSection;

  @override
  ConsumerState<_ExampleReadyExchangePanel> createState() =>
      _ExampleReadyExchangePanelState();
}

class _ExampleReadyExchangePanelState
    extends ConsumerState<_ExampleReadyExchangePanel> {
  final _amountController = TextEditingController();
  String? _sourceKey;
  String? _destinationKey;
  Map<String, dynamic>? _quote;
  bool _busy = false;

  List<BoomFiExchangeBalance> get _balances =>
      _distinctBy(widget.overview.balances, (item) => item.key);

  BoomFiExchangeBalance? get _source =>
      _balances.where((item) => item.key == _sourceKey).firstOrNull ??
      _balances.firstOrNull;

  BoomFiExchangeBalance? get _destination =>
      _balances.where((item) => item.key == _destinationKey).firstOrNull ??
      _balances.where((item) => item.key != _source?.key).firstOrNull;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final balances = _balances;
    final source = _source;
    final destination = _destination;
    final amount = double.tryParse(_amountController.text.replaceAll(',', '.'));
    final canQuote = source != null &&
        destination != null &&
        source.key != destination.key &&
        (amount ?? 0) > 0 &&
        !_busy;
    final equalsBudgets = _distinctBy(
      widget.budgets.where((item) => item.id.isNotEmpty),
      (item) => item.id,
    );
    final cryptoWallets = _distinctBy(
      widget.wallets.where((item) =>
          item.walletId.isNotEmpty &&
          const {'USDC', 'USDT'}.contains(item.symbol.toUpperCase())),
      (item) => item.walletId,
    );
    final transfersAvailable = widget.outflowsEnabled &&
        equalsBudgets.isNotEmpty &&
        cryptoWallets.isNotEmpty;
    final quote = _quote;
    final receive = quote == null
        ? null
        : _value(quote, 'buy_amount', 'BuyAmount') ??
            _value(quote, 'buyAmount', 'BuyAmount');
    final rate = quote == null ? null : _value(quote, 'rate', 'Rate');
    final fees = quote == null ? null : _map(_value(quote, 'fees', 'Fees'));
    final fee = fees == null
        ? null
        : _value(fees, 'total_fee', 'TotalFee') ??
            _value(fees, 'totalFee', 'TotalFee');
    final feeCurrency = fees == null
        ? ''
        : (_value(fees, 'fee_ccy', 'FeeCcy') ??
                _value(fees, 'feeCcy', 'FeeCcy') ??
                '')
            .toString();
    final expiry = quote == null
        ? null
        : DateTime.tryParse(_value(quote, 'expiry', 'Expiry')?.toString() ?? '')
            ?.toLocal();
    final quoteId = quote == null ? '' : _quoteId(quote);

    final composer = <Widget>[
      if (balances.isEmpty)
        ExampleGlassPanel(
          child: Text(
            context
                .tr('Exchange balances appear here after provider settlement.'),
            style: TextStyle(color: ExampleInk.secondary(context)),
          ),
        )
      else ...[
        Stack(
          alignment: Alignment.center,
          children: [
            Column(
              children: [
                _ExchangeLeg(
                  label: context.tr('From'),
                  caption: context.tr('Exchange'),
                  balance: source,
                  options: balances,
                  onSelect: (item) => setState(() {
                    _sourceKey = item.key;
                    if (_destination?.key == item.key) {
                      _destinationKey = balances
                          .where((other) => other.key != item.key)
                          .firstOrNull
                          ?.key;
                    }
                    _quote = null;
                  }),
                  amountField: TextField(
                    controller: _amountController,
                    textAlign: TextAlign.end,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() => _quote = null),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      isDense: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _ExchangeLeg(
                  label: context.tr('To'),
                  caption: context.tr('Exchange'),
                  balance: destination,
                  options: balances,
                  onSelect: (item) => setState(() {
                    _destinationKey = item.key;
                    _quote = null;
                  }),
                  trailingCaption: 'Estimate',
                  amountField: ExampleStateSwitch(
                    alignment: Alignment.centerRight,
                    child: Text(
                      receive == null ? '—' : receive.toString(),
                      key: ValueKey<String>(
                        '${destination?.key ?? '—'}:${receive ?? ''}',
                      ),
                      textAlign: TextAlign.end,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: receive == null
                            ? _fadedInk(context, .4)
                            : ExampleInk.primary(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ExamplePressable(
              enabled: source != null && destination != null,
              semanticsLabel: source == null || destination == null
                  ? context.tr('Swap from and to')
                  : context.tr('Swap {p0} and {p1}',
                      {'p0': source.currency, 'p1': destination.currency}),
              borderRadius: const BorderRadius.all(Radius.circular(22)),
              onTap: source == null || destination == null
                  ? null
                  : () => setState(() {
                        _sourceKey = destination.key;
                        _destinationKey = source.key;
                        _quote = null;
                      }),
              child: SizedBox.square(
                dimension: 44,
                child: Center(
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: ExampleSurface.of(context, 3),
                      shape: BoxShape.circle,
                      border: Border.all(color: _hairline(context, .22)),
                    ),
                    child: Icon(
                      Icons.swap_vert_rounded,
                      size: 16,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _ExchangeFact(
          label: context.tr('Rate'),
          value: rate == null
              ? '—'
              : '1 ${source?.currency ?? ''} = ${_formatRate(rate)} ${destination?.currency ?? ''}',
        ),
        const SizedBox(height: 4),
        _ExchangeFact(
          label: context.tr('Fee'),
          value: fee == null ? '—' : '$fee $feeCurrency'.trim(),
        ),
        if (quote != null) ...[
          const SizedBox(height: 4),
          _ExchangeFact(
            label: context.tr('Quote valid until'),
            value: expiry == null
                ? 'Until accepted'
                : '${expiry.hour.toString().padLeft(2, '0')}:${expiry.minute.toString().padLeft(2, '0')}:${expiry.second.toString().padLeft(2, '0')}',
          ),
          if (!widget.outflowsEnabled) ...[
            const SizedBox(height: 8),
            Text(
              context.tr(
                  'Outflows are locked for this installation, so the quote cannot be accepted yet.'),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: ExamplePalette.of(context).warning,
              ),
            ),
          ],
        ],
        const SizedBox(height: 12),
        if (quote == null)
          ExampleGlassButton(
            label: context.tr('Review exchange'),
            height: 46,
            radius: 14,
            loading: _busy,
            loadingSemanticsLabel: 'Fetching a quote',
            onPressed: canQuote
                ? () => _fetchQuote(source, destination, amount!)
                : null,
          )
        else
          Row(
            children: [
              SizedBox(
                width: 120,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 46),
                    foregroundColor: ExampleInk.primary(context),
                    side: ExampleBorders.controlSideOf(context),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _busy ? null : () => setState(() => _quote = null),
                  child: Text(context.tr('Cancel')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ExampleGlassButton(
                  label: context.tr('Confirm'),
                  height: 46,
                  radius: 14,
                  loading: _busy,
                  loadingSemanticsLabel: 'Accepting the quote',
                  sheen: false,
                  onPressed: _busy || !widget.outflowsEnabled || quoteId.isEmpty
                      ? null
                      : () => _acceptQuote(quoteId),
                ),
              ),
            ],
          ),
        if (!widget.outflowsEnabled) ...[
          const SizedBox(height: 8),
          Text(
            context.tr(
                'Quotes and balances are available. Money movement is locked until outflows are enabled for this installation.'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: ExampleInk.tertiary(context),
            ),
          ),
        ],
      ],
      if (transfersAvailable) ...[
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ExchangeTransferButton(
                label: context.tr('Fiat to crypto'),
                icon: Icons.arrow_forward_rounded,
                onTap: () => _showEqualsToCryptoDialog(
                  context,
                  ref,
                  equalsBudgets,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ExchangeTransferButton(
                label: context.tr('Crypto to fiat'),
                icon: Icons.arrow_back_rounded,
                onTap: () => _showCryptoToEqualsDialog(
                  context,
                  ref,
                  widget.overview,
                  equalsBudgets,
                  cryptoWallets,
                ),
              ),
            ),
          ],
        ),
      ],
    ];
    final ledger = <Widget>[
      if (balances.isEmpty) ...[
        ExampleSectionTitle(title: context.tr('Exchange balances')),
        const SizedBox(height: 8),
        ExampleEmptyState(
          compact: true,
          title: context.tr('No Exchange balances'),
          body: context.tr('Balances appear here after provider settlement.'),
          icon: Icons.account_balance_wallet_outlined,
        ),
      ] else
        ExampleListGroup(
          title: context.tr('Exchange balances'),
          children: [
            for (final item in balances)
              ExampleRow(
                title: item.currency,
                subtitle: item.isCrypto && item.chainName.isNotEmpty
                    ? item.chainName
                    : null,
                leading: ExampleCurrencyAvatar(code: item.currency, size: 32),
                trailing: _ExchangeBalanceValue(balance: item),
              ),
          ],
        ),
      const SizedBox(height: 18),
      widget.transferSection,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 470,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: composer,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: ledger,
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [...composer, const SizedBox(height: 18), ...ledger],
        );
      },
    );
  }

  Future<void> _fetchQuote(
    BoomFiExchangeBalance source,
    BoomFiExchangeBalance destination,
    double amount,
  ) async {
    setState(() => _busy = true);
    try {
      final quote = await ref.read(mobilePlatformApiProvider).getExchangeQuote(
            source: source,
            destination: destination,
            sellAmount: amount.toString(),
          );
      if (!mounted) return;
      setState(() => _quote = quote);
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _acceptQuote(String quoteId) async {
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(mobilePlatformApiProvider)
          .acceptExchangeQuote(quoteId);
      ref.invalidate(exchangeOverviewProvider);
      if (!mounted) return;
      _amountController.clear();
      setState(() => _quote = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message)),
      );
    } catch (error) {
      if (mounted) _showError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// Rates arrive as raw doubles (`0.8460000000000001`); show at most six
/// significant decimals without trailing noise.
String _formatRate(Object rate) {
  final value = double.tryParse(rate.toString());
  if (value == null) return rate.toString();
  var text = value.toStringAsFixed(value >= 100 ? 2 : 6);
  if (text.contains('.')) {
    text =
        text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

class _ExchangeLeg extends StatelessWidget {
  const _ExchangeLeg({
    required this.label,
    required this.caption,
    required this.balance,
    required this.options,
    required this.onSelect,
    required this.amountField,
    this.trailingCaption,
  });

  final String label;
  final String caption;
  final BoomFiExchangeBalance? balance;
  final List<BoomFiExchangeBalance> options;
  final ValueChanged<BoomFiExchangeBalance> onSelect;
  final Widget amountField;
  final String? trailingCaption;

  static const int _identityFlex = 4;
  static const int _amountFlex = 6;

  @override
  Widget build(BuildContext context) {
    final current = balance;
    final key = ValueKey<String>(current?.key ?? '—');
    return ExampleGlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ExampleInk.tertiary(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ExampleInk.tertiary(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Flexible(
                flex: _identityFlex,
                fit: FlexFit.tight,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: ExampleStateSwitch(
                    alignment: Alignment.centerLeft,
                    child: KeyedSubtree(
                      key: key,
                      child: _identity(context, current),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                flex: _amountFlex,
                fit: FlexFit.tight,
                child: amountField,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ExampleStateSwitch(
                  alignment: Alignment.centerLeft,
                  child: KeyedSubtree(
                    key: key,
                    child: Text(
                      current == null
                          ? context.tr('Balance: —')
                          : context.tr('Balance: {p0} {p1}', {
                              'p0': _exchangeBalanceAmount(current.amount,
                                  isCrypto: current.isCrypto),
                              'p1': current.currency
                            }),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: ExampleInk.tertiary(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ),
              ),
              if (trailingCaption != null) ...[
                const SizedBox(width: AppSpacing.xs),
                Text(
                  trailingCaption!,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: ExampleInk.tertiary(context),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _identity(BuildContext context, BoomFiExchangeBalance? current) =>
      PopupMenuButton<BoomFiExchangeBalance>(
        tooltip: context.tr('{p0} balance, {p1}',
            {'p0': label, 'p1': current?.currency ?? 'none selected'}),
        onSelected: onSelect,
        padding: EdgeInsets.zero,
        itemBuilder: (context) => [
          for (final option in options)
            PopupMenuItem(
              value: option,
              child: Text(
                '${option.currency} · ${_exchangeBalanceAmount(option.amount, isCrypto: option.isCrypto)}',
              ),
            ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              height: 32,
              padding: const EdgeInsets.fromLTRB(6, 0, 8, 0),
              decoration: BoxDecoration(
                color: ExampleSurface.of(context, 2),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: _hairline(context, .12)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ExampleCurrencyAvatar(
                    code: current?.currency ?? '',
                    size: 20,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      current?.currency ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 16,
                    color: ExampleInk.secondary(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ExchangeBalanceValue extends StatelessWidget {
  const _ExchangeBalanceValue({required this.balance});

  final BoomFiExchangeBalance balance;

  @override
  Widget build(BuildContext context) {
    final pending = balance.pendingAmount;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ExampleAmount(
          amount: balance.amount,
          currency: balance.currency,
          size: ExampleAmountSize.inline,
          code: ExampleAmountCode.never,
          textAlign: TextAlign.end,
        ),
        if (pending != 0) ...[
          const SizedBox(height: 1),
          Text(
            context.tr('{p0} pending', {
              'p0': _exchangeBalanceAmount(pending, isCrypto: balance.isCrypto)
            }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              color: ExamplePalette.of(context).warning,
            ),
          ),
        ],
      ],
    );
  }
}

class _ExchangeFact extends StatelessWidget {
  const _ExchangeFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  color: ExampleInk.tertiary(context),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ExampleInk.primary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
}

class _ExchangeTransferButton extends StatelessWidget {
  const _ExchangeTransferButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: ExampleInk.primary(context),
          disabledForegroundColor: ExampleInk.primary(context)
              .withValues(alpha: ExampleOpacity.disabled),
          side: ExampleBorders.controlSideOf(context),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

ButtonStyle _exchangeActionStyle(BuildContext context) {
  final colors = Theme.of(context).colorScheme;
  return OutlinedButton.styleFrom(
    side: BorderSide(
      color: colors.outline.withValues(
        alpha: Theme.of(context).brightness == Brightness.light ? .55 : .8,
      ),
    ),
  );
}

Future<void> _showExchangeDialog(
  BuildContext context,
  WidgetRef ref,
  BoomFiExchangeOverview overview,
  bool outflowsEnabled,
) async {
  final balances = _distinctBy(overview.balances, (item) => item.key);
  var source = balances.first;
  var destination = balances.firstWhere(
    (item) => item.key != source.key,
    orElse: () => source,
  );
  var amount = '';
  Map<String, dynamic>? quote;
  var busy = false;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => _FullScreenExchangeDialog(
        title: Text(context.tr('Exchange balances')),
        canClose: !busy,
        primaryLabel: quote == null
            ? (busy ? 'Loading…' : 'Get quote')
            : (outflowsEnabled ? 'Accept quote' : 'Outflows locked'),
        onPrimary: quote == null
            ? (busy ||
                    source.key == destination.key ||
                    (double.tryParse(amount) ?? 0) <= 0
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final result = await ref
                          .read(mobilePlatformApiProvider)
                          .getExchangeQuote(
                            source: source,
                            destination: destination,
                            sellAmount: amount,
                          );
                      setState(() => quote = result);
                    } catch (error) {
                      if (context.mounted) _showError(context, error);
                    } finally {
                      if (context.mounted) setState(() => busy = false);
                    }
                  })
            : (!outflowsEnabled || busy || _quoteId(quote!).isEmpty
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final result = await ref
                          .read(mobilePlatformApiProvider)
                          .acceptExchangeQuote(_quoteId(quote!));
                      ref.invalidate(exchangeOverviewProvider);
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
              Text(
                context.tr(
                    'Review the live rate before any balance is exchanged.'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: source.key,
                decoration: InputDecoration(labelText: context.tr('From')),
                items: [
                  for (final item in balances)
                    DropdownMenuItem(
                      value: item.key,
                      child: Text(
                        '${item.currency} · ${_exchangeBalanceAmount(item.amount, isCrypto: item.isCrypto)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  source = balances.firstWhere((i) => i.key == value);
                  quote = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: destination.key,
                decoration: InputDecoration(labelText: context.tr('To')),
                items: [
                  for (final item in balances)
                    DropdownMenuItem(
                      value: item.key,
                      child: Text(item.currency),
                    ),
                ],
                onChanged: (value) => setState(() {
                  destination = balances.firstWhere((i) => i.key == value);
                  quote = null;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    InputDecoration(labelText: context.tr('Sell amount')),
                onChanged: (value) => setState(() {
                  amount = value;
                  quote = null;
                }),
              ),
              if (quote != null) ...[
                const SizedBox(height: 16),
                _QuoteReview(quote: quote!),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _QuoteReview extends StatelessWidget {
  const _QuoteReview({required this.quote});

  final Map<String, dynamic> quote;

  @override
  Widget build(BuildContext context) {
    final fees = _map(_value(quote, 'fees', 'Fees'));
    if (context.isExampleTheme) return _example(context, fees);
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
    if (context.isExampleTheme) return PlatformLede(text: text);
    return Text(
      text,
      style: large ? Theme.of(context).textTheme.bodyLarge : null,
    );
  }
}

Future<void> _showEqualsToCryptoDialog(
  BuildContext context,
  WidgetRef ref,
  List<PlatformResource> budgets,
) async {
  var budget = budgets.first;
  var currency = _resourceCurrency(budget);
  var amount = '';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => _FullScreenExchangeDialog(
        title: const _TransferDialogTitle(
          example: 'Fiat account to Crypto card',
          whiteLabel: 'Fiat account → Crypto card',
        ),
        primaryLabel: 'Review transfer',
        onPrimary: (double.tryParse(amount.replaceAll(',', '.')) ?? 0) <= 0
            ? null
            : () => Navigator.pop(context, true),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TransferDialogLede(
                text: context.tr(
                    'The exchange converts the selected fiat balance and sends USDC to your Crypto card wallet.'),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: budget.id,
                isExpanded: context.isExampleTheme,
                decoration:
                    InputDecoration(labelText: context.tr('Source budget')),
                items: [
                  for (final item in budgets)
                    DropdownMenuItem(
                      value: item.id,
                      child: _DropdownLabel(item.title),
                    ),
                ],
                onChanged: (value) => setState(() {
                  budget = budgets.firstWhere((item) => item.id == value);
                  currency = _resourceCurrency(budget);
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                    labelText: context.tr('Amount ({p0})', {'p0': currency})),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) => setState(() => amount = value),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final parsed = double.tryParse(amount.replaceAll(',', '.')) ?? 0;
  if (confirmed != true || parsed <= 0 || !context.mounted) return;
  try {
    final result =
        await ref.read(mobilePlatformApiProvider).createEqualsToInterlace(
              idempotencyKey:
                  'mobile-${budget.id}-${DateTime.now().microsecondsSinceEpoch}',
              budgetId: budget.id,
              fiatCurrency: currency,
              amount: parsed,
            );
    ref.invalidate(exchangeTransfersProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  } catch (error) {
    if (context.mounted) _showError(context, error);
  }
}

Future<void> _showCryptoToEqualsDialog(
  BuildContext context,
  WidgetRef ref,
  BoomFiExchangeOverview overview,
  List<PlatformResource> budgets,
  List<HoppaWalletAsset> wallets,
) async {
  var wallet = wallets.first;
  var budget = budgets.first;
  var cryptoAmount = '';
  var fiatCurrency = _resourceCurrency(budget);
  Map<String, dynamic>? quote;
  String verificationToken = '';
  var otp = '';
  var busy = false;

  Map<String, Object?> request() => {
        'boomFiAccountId': overview.accountId.toString(),
        'reference':
            'mobile-equals-${budget.id}-${DateTime.now().millisecondsSinceEpoch}',
        'chainId': _chainId(wallet.network),
        'currency': wallet.symbol.toUpperCase(),
        'cryptoAmount': cryptoAmount,
        'fiatCurrency': fiatCurrency,
        'targetBudgetId': budget.id,
      };

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => _FullScreenExchangeDialog(
        title: const _TransferDialogTitle(
          example: 'Crypto card to Fiat account',
          whiteLabel: 'Crypto card → Fiat account',
        ),
        canClose: !busy,
        primaryLabel: quote == null
            ? 'Get quote'
            : verificationToken.isEmpty
                ? 'Send verification code'
                : 'Confirm transfer',
        onPrimary: quote == null
            ? (busy ||
                    (double.tryParse(cryptoAmount.replaceAll(',', '.')) ?? 0) <=
                        0 ||
                    _chainId(wallet.network) == 0
                ? null
                : () async {
                    setState(() => busy = true);
                    try {
                      final result = await ref
                          .read(mobilePlatformApiProvider)
                          .getInterlaceToEqualsQuote(request());
                      setState(() => quote = result);
                    } catch (error) {
                      if (context.mounted) _showError(context, error);
                    } finally {
                      if (context.mounted) setState(() => busy = false);
                    }
                  })
            : verificationToken.isEmpty
                ? (busy
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
                : (busy || otp.length != 8
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
                initialValue: wallet.walletId,
                isExpanded: context.isExampleTheme,
                decoration: InputDecoration(
                    labelText: context.tr('Source crypto wallet')),
                items: [
                  for (final item in wallets)
                    DropdownMenuItem(
                      value: item.walletId,
                      child: _DropdownLabel(
                        '${item.symbol} · ${_amount(item.amount)}',
                      ),
                    ),
                ],
                onChanged: (value) => setState(() {
                  wallet = wallets.firstWhere((item) => item.walletId == value);
                  quote = null;
                }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: budget.id,
                isExpanded: context.isExampleTheme,
                decoration: InputDecoration(
                    labelText: context.tr('Equals destination')),
                items: [
                  for (final item in budgets)
                    DropdownMenuItem(
                      value: item.id,
                      child: _DropdownLabel(item.title),
                    ),
                ],
                onChanged: (value) => setState(() {
                  budget = budgets.firstWhere((item) => item.id == value);
                  fiatCurrency = _resourceCurrency(budget);
                  quote = null;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                decoration: InputDecoration(
                    labelText:
                        context.tr('Amount ({p0})', {'p0': wallet.symbol})),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: (value) => setState(() {
                  cryptoAmount = value;
                  quote = null;
                }),
              ),
              if (quote != null) ...[
                const SizedBox(height: 12),
                _QuoteReview(quote: quote!),
              ],
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

String _resourceCurrency(PlatformResource resource) {
  for (final key in const [
    'currency',
    'Currency',
    'currencyCode',
    'CurrencyCode',
  ]) {
    final value = resource.metadata[key]?.toString().trim().toUpperCase();
    if (value != null && value.length == 3) return value;
  }
  return 'EUR';
}

int _chainId(String network) {
  final value = network.trim().toLowerCase();
  if (value.contains('tron') || value.contains('trx')) return -200;
  if (value.contains('polygon') || value.contains('matic')) return 137;
  if (value.contains('arbitrum') || value.contains('arb')) return 42161;
  if (value.contains('optimism')) return 10;
  if (value.contains('avalanche') || value.contains('avax')) return 43114;
  if (value.contains('ethereum') || value.contains('eth')) return 1;
  return 0;
}

String _quoteId(Map<String, dynamic> quote) =>
    (_value(quote, 'session', 'Session') ??
            _value(quote, 'quoteId', 'QuoteId') ??
            '')
        .toString()
        .trim();

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

Object? _value(Map<String, dynamic> json, String first, String second) =>
    json[first] ?? json[second];

List<T> _distinctBy<T>(Iterable<T> items, String Function(T item) keyOf) {
  final seen = <String>{};
  return [
    for (final item in items)
      if (seen.add(keyOf(item))) item,
  ];
}

String _amount(double value) => value.toStringAsFixed(6);

String _exchangeBalanceAmount(
  double value, {
  required bool isCrypto,
}) =>
    isCrypto ? _amount(value) : value.toStringAsFixed(2);

void _showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(friendlyErrorMessage(error))),
  );
}
