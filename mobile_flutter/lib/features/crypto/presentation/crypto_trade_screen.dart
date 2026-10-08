import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/formatters/amount_input.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../wallets/data/wallet_providers.dart';
import '../domain/crypto_models.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class CryptoTradeScreen extends ConsumerStatefulWidget {
  const CryptoTradeScreen({
    this.initialSide = CryptoTradeSide.buy,
    this.asSheet = false,
    super.key,
  });

  final CryptoTradeSide initialSide;

  final bool asSheet;

  @override
  ConsumerState<CryptoTradeScreen> createState() => _CryptoTradeScreenState();
}

const _exchangeAssets = ['USDC', 'USDT'];

Future<void> showCryptoExchangeSheet(
  BuildContext context, {
  CryptoTradeSide initialSide = CryptoTradeSide.buy,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: .93,
        child: CryptoTradeScreen(initialSide: initialSide, asSheet: true),
      ),
    );

String _amountLabel(String currency, double value) {
  final text = Money.formatAmount(currency, value);
  final code = currency.toUpperCase();
  return text.toUpperCase().contains(code) ? text : '$text $code';
}

Widget _aliveLayer(BuildContext context, Widget child) =>
    context.isExampleTheme && !ExampleSheenScope.existsAbove(context)
        ? ExampleSheenScope(child: child)
        : child;

class _CryptoTradeScreenState extends ConsumerState<CryptoTradeScreen> {
  final _amountController = TextEditingController();
  late CryptoTradeSide _side = widget.initialSide;
  String _asset = 'USDC';
  QuantumTopUpEstimate? _estimate;
  bool _estimating = false;
  String? _estimateError;
  Timer? _debounce;
  Map<String, dynamic>? _lastResult;

  @override
  void dispose() {
    _debounce?.cancel();
    _amountController.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  bool get _toCrypto => _side == CryptoTradeSide.buy;

  void _onAmountChanged() {
    setState(() => _lastResult = null);
    _debounce?.cancel();
    if (_toCrypto || _amount <= 0) {
      setState(() {
        _estimate = null;
        _estimateError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), _fetchEstimate);
  }

  Future<void> _fetchEstimate() async {
    final amount = _amount;
    if (amount <= 0) return;
    setState(() {
      _estimating = true;
      _estimateError = null;
    });
    try {
      final estimate = await ref
          .read(mobilePlatformApiProvider)
          .getQuantumTopUpEstimate(
            amount: Money(currency: 'USD', minorUnits: (amount * 100).round()),
          );
      if (!mounted) return;
      setState(() => _estimate = estimate);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _estimate = null;
        _estimateError = friendlyErrorMessage(error);
      });
    } finally {
      if (mounted) setState(() => _estimating = false);
    }
  }

  Future<void> _submit() async {
    final amount = _amount;
    if (amount <= 0) return;
    final minorUnits = (amount * 100).round();
    final notifier = ref.read(platformActionControllerProvider.notifier);
    await notifier.run((api) => _toCrypto
        ? api.exchangeQuantumUsdToCrypto(
            asset: _asset,
            amount: Money(currency: 'USD', minorUnits: minorUnits),
          )
        : api.transferCryptoToQuantumDashboard(
            sourceCurrency: _asset,
            destinationCurrency: 'USD',
            amount: Money(currency: _asset, minorUnits: minorUnits),
          ));
    final state = ref.read(platformActionControllerProvider);
    if (!mounted) return;
    if (state.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(state.error!))),
      );
      return;
    }
    final metadata = state.valueOrNull?.metadata ?? const <String, dynamic>{};
    if (metadata['success'] == false) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (metadata['errorMessage'] ??
                    metadata['message'] ??
                    'The exchange was not completed.')
                .toString(),
          ),
        ),
      );
      return;
    }
    ref.invalidate(userAssetsProvider);
    ref.invalidate(userWalletsProvider);
    ref.invalidate(hoppaWalletAssetsProvider);
    ref.invalidate(dashboardProvider);
    setState(() {
      _lastResult = metadata;
      _estimate = null;
    });
    _amountController.clear();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) return _buildLegacy(context);
    final wallets = ref.watch(hoppaWalletAssetsProvider);
    final action = ref.watch(platformActionControllerProvider);
    final isExample = context.isExampleTheme;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    double balanceOf(String symbol) =>
        wallets.valueOrNull
            ?.where((wallet) => wallet.symbol.trim().toUpperCase() == symbol)
            .fold<double>(0, (sum, wallet) => sum + wallet.amount) ??
        0;
    final sourceSymbol = _toCrypto ? 'USD' : _asset;
    final targetSymbol = _toCrypto ? _asset : 'USD';
    final available = balanceOf(sourceSymbol);
    final amount = _amount;
    final overBalance = amount > available && available > 0;

    final title = _toCrypto
        ? context.tr('Exchange to crypto')
        : context.tr('Exchange to USD');

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSegmentedControl<CryptoTradeSide>(
          segments: [
            (value: CryptoTradeSide.buy, label: context.tr('USD → crypto')),
            (value: CryptoTradeSide.sell, label: context.tr('Crypto → USD')),
          ],
          selected: _side,
          onChanged: (side) => setState(() {
            _side = side;
            _estimate = null;
            _lastResult = null;
          }),
        ),
        const SizedBox(height: AppSpacing.md),
        ExampleSectionTitle(title: context.tr('Stablecoin')),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (final symbol in _exchangeAssets) ...[
              Expanded(
                child: _AssetChoice(
                  symbol: symbol,
                  balance: balanceOf(symbol),
                  selected: _asset == symbol,
                  onTap: () => setState(() {
                    _asset = symbol;
                    _lastResult = null;
                  }),
                ),
              ),
              if (symbol != _exchangeAssets.last)
                const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ExampleGlassPanel(
          radius: AppRadii.md,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('You exchange'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: ExampleInk.secondary(context),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => _onAmountChanged(),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  ExamplePill(
                      label: sourceSymbol,
                      color: ExampleColors.lavender,
                      fontSize: 12),
                  if (available > 0) ...[
                    const SizedBox(width: AppSpacing.xs),
                    TextButton(
                      // 44 pt: the smallest control on the page still has to
                      // be reachable with a thumb.
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () {
                        _amountController.text = maxAmountInput(
                          available,
                          decimals: amountDecimalsFor(sourceSymbol),
                        );
                        _onAmountChanged();
                      },
                      child: Text(context.tr('Max')),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              // On its own line: at a large text size an "Available" figure
              // beside the label is the first thing to overflow.
              Text(
                context.tr('Available {p0}',
                    {'p0': _amountLabel(sourceSymbol, available)}),
                style: TextStyle(
                  fontSize: 11.5,
                  color: overBalance
                      ? ExampleInk.accent(context, ExampleColors.warning)
                      : ExampleInk.tertiary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _QuoteLedger(
          toCrypto: _toCrypto,
          asset: _asset,
          amount: amount,
          estimate: _estimate,
          loading: _estimating,
          error: _estimateError,
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _ResultPanel(
              result: _lastResult!, toCrypto: _toCrypto, asset: _asset),
        ],
        const SizedBox(height: AppSpacing.md),
        _ExchangeCta(
          label: amount <= 0
              ? context.tr('Enter an amount')
              : context.tr('Exchange {p0} to {p1}', {
                  'p0': _amountLabel(sourceSymbol, amount),
                  'p1': targetSymbol
                }),
          busy: action.isLoading,
          onPressed:
              amount <= 0 || action.isLoading || overBalance ? null : _submit,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.tr(
              'Exchanges settle inside your account at the provider rate shown; the fee is deducted before delivery.'),
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: ExampleInk.tertiary(context),
          ),
        ),
      ],
    );

    final body = wallets.when(
      data: (_) => form,
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(hoppaWalletAssetsProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading balances')),
    );

    if (widget.asSheet) {
      return _aliveLayer(
        context,
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(title),
            actions: [
              IconButton(
                tooltip: context.tr('Close'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [body],
          ),
        ),
      );
    }

    return ExampleGlow(
      child: Scaffold(
        backgroundColor: isExample ? Colors.transparent : null,
        appBar: AppBar(
          centerTitle: isExample && !desktop,
          title: Text(title),
          leading: IconButton(
            tooltip: context.tr('Back'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go('/wallets/assets'),
            icon: Icon(
              isExample ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back,
              size: isExample ? 19 : null,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: desktop
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      // Example puts the column straight on the atmosphere: a
                      // panel here would nest the ledger group inside a card.
                      child: isExample
                          ? body
                          : ExampleGlassPanel(
                              radius: 24,
                              borderAlpha: .22,
                              padding:
                                  const EdgeInsets.fromLTRB(24, 22, 24, 24),
                              child: body,
                            ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  children: [body],
                ),
        ),
      ),
    );
  }

  Widget _buildLegacy(BuildContext context) {
    final wallets = ref.watch(hoppaWalletAssetsProvider);
    final action = ref.watch(platformActionControllerProvider);
    final isExample = context.isExampleTheme;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    double balanceOf(String symbol) =>
        wallets.valueOrNull
            ?.where((wallet) => wallet.symbol.trim().toUpperCase() == symbol)
            .fold<double>(0, (sum, wallet) => sum + wallet.amount) ??
        0;
    final sourceSymbol = _toCrypto ? 'USD' : _asset;
    final targetSymbol = _toCrypto ? _asset : 'USD';
    final available = balanceOf(sourceSymbol);
    final amount = _amount;
    final overBalance = amount > available && available > 0;

    final title = _toCrypto
        ? context.tr('Exchange to crypto')
        : context.tr('Exchange to USD');

    final form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSegmentedControl<CryptoTradeSide>(
          segments: [
            (value: CryptoTradeSide.buy, label: context.tr('USD → crypto')),
            (value: CryptoTradeSide.sell, label: context.tr('Crypto → USD')),
          ],
          selected: _side,
          onChanged: (side) => setState(() {
            _side = side;
            _estimate = null;
            _lastResult = null;
          }),
        ),
        const SizedBox(height: 18),
        ExampleSectionTitle(title: context.tr('Stablecoin')),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final symbol in _exchangeAssets) ...[
              Expanded(
                child: _LegacyAssetChoice(
                  symbol: symbol,
                  balance: balanceOf(symbol),
                  selected: _asset == symbol,
                  onTap: () => setState(() {
                    _asset = symbol;
                    _lastResult = null;
                  }),
                ),
              ),
              if (symbol != _exchangeAssets.last) const SizedBox(width: 8),
            ],
          ],
        ),
        const SizedBox(height: 18),
        ExampleGlassPanel(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    context.tr('You exchange'),
                    style: TextStyle(
                        fontSize: 12.5,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'textSecondary',
                            fallback: ExampleColors.textSecondary)),
                  ),
                  const Spacer(),
                  Text(
                    context.tr('Available {p0}',
                        {'p0': _amountLabel(sourceSymbol, available)}),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: overBalance
                          ? context.brandDesign.color(
                              Theme.of(context).brightness, 'warning',
                              fallback: ExampleColors.warning)
                          : context.brandDesign.color(
                              Theme.of(context).brightness, 'textTertiary',
                              fallback: ExampleColors.textTertiary),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      onChanged: (_) => _onAmountChanged(),
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'ink',
                            fallback: ExampleColors.pearl),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                      decoration: const InputDecoration(
                        hintText: '0.00',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 6),
                      ),
                    ),
                  ),
                  ExamplePill(
                      label: sourceSymbol,
                      color: ExampleColors.lavender,
                      fontSize: 12),
                  if (available > 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () {
                        _amountController.text = maxAmountInput(
                          available,
                          decimals: amountDecimalsFor(sourceSymbol),
                        );
                        _onAmountChanged();
                      },
                      child: Text(context.tr('Max')),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _LegacyQuotePanel(
          toCrypto: _toCrypto,
          asset: _asset,
          amount: amount,
          estimate: _estimate,
          loading: _estimating,
          error: _estimateError,
        ),
        if (_lastResult != null) ...[
          const SizedBox(height: 12),
          _LegacyResultPanel(
              result: _lastResult!, toCrypto: _toCrypto, asset: _asset),
        ],
        const SizedBox(height: 18),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed:
                amount <= 0 || action.isLoading || overBalance ? null : _submit,
            icon: action.isLoading
                ? const SizedBox.square(
                    dimension: 18,
                    child: AppProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.swap_horiz_rounded, size: 20),
            label: Text(
              amount <= 0
                  ? context.tr('Enter an amount')
                  : context.tr('Exchange {p0} to {p1}', {
                      'p0': _amountLabel(sourceSymbol, amount),
                      'p1': targetSymbol
                    }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          context.tr(
              'Exchanges settle inside your account at the provider rate shown; the fee is deducted before delivery.'),
          style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: context.brandDesign.color(
                  Theme.of(context).brightness, 'textTertiary',
                  fallback: ExampleColors.textTertiary)),
        ),
      ],
    );

    final body = wallets.when(
      data: (_) => form,
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(hoppaWalletAssetsProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading balances')),
    );

    if (widget.asSheet) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(title),
          actions: [
            IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [body],
        ),
      );
    }

    return ExampleGlow(
      child: Scaffold(
        backgroundColor: isExample ? Colors.transparent : null,
        appBar: AppBar(
          centerTitle: isExample && !desktop,
          title: Text(title),
          leading: IconButton(
            tooltip: context.tr('Back'),
            onPressed: () => context.canPop()
                ? context.pop()
                : context.go('/wallets/assets'),
            icon: Icon(
              isExample ? Icons.arrow_back_ios_new_rounded : Icons.arrow_back,
              size: isExample ? 19 : null,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: desktop
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 40),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: ExampleGlassPanel(
                        radius: 24,
                        borderAlpha: .22,
                        padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
                        child: body,
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
                  children: [body],
                ),
        ),
      ),
    );
  }
}

class _ExchangeCta extends StatelessWidget {
  const _ExchangeCta({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      // The screen's one moment. `atmosphere` is the honest ground here: the
      // CTA sits directly on the ExampleGlow with nothing opaque between, so
      // the bounded blur has real backdrop to sample instead of sampling its
      // own fill.
      //
      // `loading` replaces the old inline spinner, which swapped only the
      // leading icon and left the label unchanged — visually the button
      // looked idle while a card payment was being started, and a screen
      // reader was told nothing at all. The silhouette, width and position
      // now hold while the label becomes a ring, and assistive technology
      // hears "Exchange, in progress".
      return ExampleGlassButton(
        label: label,
        icon: Icons.swap_horiz_rounded,
        ground: ExampleGlassGround.atmosphere,
        loading: busy,
        sheen: true,
        onPressed: onPressed,
      );
    }
    return SizedBox(
      height: 50,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: busy
            ? const SizedBox.square(
                dimension: 18,
                child: AppProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.swap_horiz_rounded, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _AssetChoice extends StatelessWidget {
  const _AssetChoice({
    required this.symbol,
    required this.balance,
    required this.selected,
    required this.onTap,
  });

  final String symbol;
  final double balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final formatted = Money.formatAmount(symbol, balance);
    return ExamplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      semanticsLabel: '$symbol, $formatted'
          '${selected ? ', selected' : ''}',
      child: ExampleGlassPanel(
        radius: AppRadii.sm,
        borderAlpha: selected ? .5 : .16,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: [
            ExampleCurrencyAvatar(code: symbol, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  Text(
                    formatted,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ExampleInk.tertiary(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            ExampleStateSwitch(
              child: Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                key: ValueKey(selected),
                size: 18,
                color: selected
                    ? ExampleInk.accent(context, ExampleColors.iris)
                    : ExampleInk.tertiary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteLedger extends StatelessWidget {
  const _QuoteLedger({
    required this.toCrypto,
    required this.asset,
    required this.amount,
    required this.estimate,
    required this.loading,
    required this.error,
  });

  final bool toCrypto;
  final String asset;
  final double amount;
  final QuantumTopUpEstimate? estimate;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final quote = estimate == null
        ? null
        : asset == 'USDT'
            ? estimate!.usdt
            : estimate!.usdc;
    final rows = <(String, String)>[];
    if (amount <= 0) {
      rows.add(('Rate', ExampleAmount.placeholder));
      rows.add(('Fee', ExampleAmount.placeholder));
      rows.add(('You receive', ExampleAmount.placeholder));
    } else if (toCrypto) {
      // The provider prices USD → stablecoin at conversion time; 1:1 is the
      // reference the customer can expect, fee deducted on delivery.
      rows.add(('Reference rate', '1 USD ≈ 1 $asset'));
      rows.add(('Fee', 'Confirmed by the provider'));
      rows.add(('You receive', '≈ ${_amountLabel(asset, amount)}'));
    } else if (loading || error != null) {
      rows.add(('Rate', ExampleAmount.placeholder));
      rows.add(('Fee', ExampleAmount.placeholder));
      rows.add(('You receive', ExampleAmount.placeholder));
    } else if (quote != null) {
      final rate = quote.rate > 0 ? quote.rate : 1.0;
      // The card issuer charges 0.01% on stablecoin → USD conversions. Use
      // the quote's fee when it carries one, otherwise apply that rate.
      final providerFee = quote.fee > 0 ? quote.fee : amount * 0.0001;
      final feeCurrency = quote.fee > 0 ? (quote.feeCurrency ?? 'USD') : asset;
      final received = quote.rfqAmount > 0
          ? quote.rfqAmount
          : (amount - (feeCurrency == asset ? providerFee : 0)) * rate -
              (feeCurrency == asset ? 0 : providerFee);
      rows.add(('Rate', '1 $asset = ${_amountLabel('USD', rate)}'));
      rows.add(('Fee (0.01%)', _amountLabel(feeCurrency, providerFee)));
      rows.add(
          ('You receive', _amountLabel('USD', received < 0 ? 0 : received)));
    } else {
      rows.add(('Rate', ExampleAmount.placeholder));
      rows.add(('Fee', ExampleAmount.placeholder));
      rows.add(('You receive', ExampleAmount.placeholder));
    }

    final message = error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleStateSwitch(
          alignment: Alignment.topCenter,
          child: ExampleListGroup(
            key: ValueKey(rows.map((row) => '${row.$1}=${row.$2}').join('|')),
            dividerInset: AppSpacing.md,
            children: [
              for (final row in rows)
                ExampleRow(
                  title: row.$1,
                  minHeight: 44,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xxs,
                  ),
                  trailing: ExampleRowValue(value: row.$2),
                ),
            ],
          ),
        ),
        if (loading) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('Fetching the provider quote…'),
            style: TextStyle(
              fontSize: 11.5,
              color: ExampleInk.tertiary(context),
            ),
          ),
        ],
        if (message != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: ExampleInk.accent(context, ExampleColors.danger),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel(
      {required this.result, required this.toCrypto, required this.asset});

  final Map<String, dynamic> result;
  final bool toCrypto;
  final String asset;

  String? _num(List<String> keys) {
    for (final key in keys) {
      final value = result[key];
      if (value is num) return value.toStringAsFixed(2);
      if (value is String && double.tryParse(value) != null) {
        return double.parse(value).toStringAsFixed(2);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final received = _num(const [
      'cryptoAmountReceived',
      'CryptoAmountReceived',
      'destinationAmount',
      'DestinationAmount',
      'receivedAmount'
    ]);
    final rate = _num(const ['rate', 'Rate']);
    final fee = _num(const ['fee', 'Fee']);
    return ExampleGlassPanel(
      radius: AppRadii.sm,
      borderAlpha: .4,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: ExampleInk.accent(context, ExampleColors.success), size: 22),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Exchange completed'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (received != null)
                      'Received $received ${toCrypto ? asset : 'USD'}',
                    if (rate != null) 'Rate $rate',
                    if (fee != null) 'Fee $fee',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12,
                    color: ExampleInk.secondary(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegacyAssetChoice extends StatelessWidget {
  const _LegacyAssetChoice({
    required this.symbol,
    required this.balance,
    required this.selected,
    required this.onTap,
  });

  final String symbol;
  final double balance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        radius: 14,
        borderAlpha: selected ? .5 : .16,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        onTap: onTap,
        child: Row(
          children: [
            ExampleCurrencyAvatar(code: symbol, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    symbol,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: context.brandDesign.color(
                          Theme.of(context).brightness, 'ink',
                          fallback: ExampleColors.pearl),
                    ),
                  ),
                  Text(
                    Money.formatAmount(symbol, balance),
                    style: TextStyle(
                        fontSize: 11.5,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'textTertiary',
                            fallback: ExampleColors.textTertiary)),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 18,
              color: selected
                  ? context.brandDesign.color(
                      Theme.of(context).brightness, 'accent',
                      fallback: ExampleColors.iris)
                  : context.brandDesign.color(
                      Theme.of(context).brightness, 'textTertiary',
                      fallback: ExampleColors.textTertiary),
            ),
          ],
        ),
      );
}

class _LegacyQuotePanel extends StatelessWidget {
  const _LegacyQuotePanel({
    required this.toCrypto,
    required this.asset,
    required this.amount,
    required this.estimate,
    required this.loading,
    required this.error,
  });

  final bool toCrypto;
  final String asset;
  final double amount;
  final QuantumTopUpEstimate? estimate;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final quote = estimate == null
        ? null
        : asset == 'USDT'
            ? estimate!.usdt
            : estimate!.usdc;
    final rows = <(String, String)>[];
    if (amount <= 0) {
      rows.add(('Rate', '—'));
      rows.add(('Fee', '—'));
      rows.add(('You receive', '—'));
    } else if (toCrypto) {
      // The provider prices USD → stablecoin at conversion time; 1:1 is the
      // reference the customer can expect, fee deducted on delivery.
      rows.add(('Reference rate', '1 USD ≈ 1 $asset'));
      rows.add(('Fee', 'Confirmed by the provider'));
      rows.add(('You receive', '≈ ${_amountLabel(asset, amount)}'));
    } else if (loading) {
      rows.add(('Quote', 'Fetching…'));
    } else if (error != null) {
      rows.add(('Quote', error!));
    } else if (quote != null) {
      final rate = quote.rate > 0 ? quote.rate : 1.0;
      // The card issuer charges 0.01% on stablecoin → USD conversions. Use
      // the quote's fee when it carries one, otherwise apply that rate.
      final providerFee = quote.fee > 0 ? quote.fee : amount * 0.0001;
      final feeCurrency = quote.fee > 0 ? (quote.feeCurrency ?? 'USD') : asset;
      final received = quote.rfqAmount > 0
          ? quote.rfqAmount
          : (amount - (feeCurrency == asset ? providerFee : 0)) * rate -
              (feeCurrency == asset ? 0 : providerFee);
      rows.add(('Rate', '1 $asset = ${_amountLabel('USD', rate)}'));
      rows.add(('Fee (0.01%)', _amountLabel(feeCurrency, providerFee)));
      rows.add(
          ('You receive', _amountLabel('USD', received < 0 ? 0 : received)));
    } else {
      rows.add(('Quote', 'Enter an amount to see the rate'));
    }
    return ExampleGlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Text(row.$1,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: context.brandDesign.color(
                              Theme.of(context).brightness, 'textSecondary',
                              fallback: ExampleColors.textSecondary))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'ink',
                            fallback: ExampleColors.pearl),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LegacyResultPanel extends StatelessWidget {
  const _LegacyResultPanel(
      {required this.result, required this.toCrypto, required this.asset});

  final Map<String, dynamic> result;
  final bool toCrypto;
  final String asset;

  String? _num(List<String> keys) {
    for (final key in keys) {
      final value = result[key];
      if (value is num) return value.toStringAsFixed(2);
      if (value is String && double.tryParse(value) != null) {
        return double.parse(value).toStringAsFixed(2);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final received = _num(const [
      'cryptoAmountReceived',
      'CryptoAmountReceived',
      'destinationAmount',
      'DestinationAmount',
      'receivedAmount'
    ]);
    final rate = _num(const ['rate', 'Rate']);
    final fee = _num(const ['fee', 'Fee']);
    return ExampleGlassPanel(
      radius: 16,
      borderAlpha: .4,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded,
              color: context.brandDesign.color(
                  Theme.of(context).brightness, 'success',
                  fallback: ExampleColors.success),
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Exchange completed'),
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: context.brandDesign.color(
                          Theme.of(context).brightness, 'ink',
                          fallback: ExampleColors.pearl)),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (received != null)
                      'Received $received ${toCrypto ? asset : 'USD'}',
                    if (rate != null) 'Rate $rate',
                    if (fee != null) 'Fee $fee',
                  ].join(' · '),
                  style: TextStyle(
                      fontSize: 12,
                      color: context.brandDesign.color(
                          Theme.of(context).brightness, 'textSecondary',
                          fallback: ExampleColors.textSecondary)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
