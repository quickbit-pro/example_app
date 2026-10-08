import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../wallets/data/wallet_providers.dart';
import '../../wallets/domain/wallet_models.dart';
import 'transak_checkout_dialog.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

const _buyAssets = ['USDC', 'USDT'];
const _quickAmounts = [50.0, 100.0, 250.0, 500.0];

Future<void> showBuyCryptoSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: .93,
        child: BuyCryptoScreen(asSheet: true),
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

class BuyCryptoScreen extends ConsumerStatefulWidget {
  const BuyCryptoScreen({this.asSheet = false, super.key});

  final bool asSheet;

  @override
  ConsumerState<BuyCryptoScreen> createState() => _BuyCryptoScreenState();
}

class _BuyCryptoScreenState extends ConsumerState<BuyCryptoScreen> {
  final _amountController = TextEditingController();
  String _asset = 'USDC';
  bool _submitting = false;
  String? _error;
  String? _checkoutUrl;
  String? _orderId;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  double get _amount =>
      double.tryParse(_amountController.text.replaceAll(',', '.')) ?? 0;

  HoppaWalletAsset? _addressFor(List<HoppaWalletAsset> addresses) {
    for (final asset in addresses) {
      if (asset.symbol.toUpperCase() == _asset && asset.address.isNotEmpty) {
        return asset;
      }
    }
    return null;
  }

  Future<void> _submit(HoppaWalletAsset? destination) async {
    if (destination == null) {
      setState(() => _error =
          'No $_asset deposit address is available yet. Complete verification and try again.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await ref.read(mobileBankingApiProvider).buyCryptoWithCard(
            token: _asset,
            walletAddress: destination.address,
            usdAmount: _amount,
          );
      final success = _bool(result['success'] ?? result['Success']) ?? true;
      final url = _text(result['transakUrl'] ?? result['TransakUrl']);
      if (!success || url == null) {
        throw StateError(
          _text(result['errorMessage'] ?? result['ErrorMessage']) ??
              _text(result['message'] ?? result['Message']) ??
              'The purchase could not be started. Try again in a moment.',
        );
      }
      setState(() {
        _checkoutUrl = url;
        _orderId = _text(result['orderId'] ?? result['OrderId']);
      });
      await _openCheckout(url);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openCheckout(String url) async {
    if (!mounted) return;
    await showTransakCheckout(context, url);
    if (!mounted) return;
    // Balances update once Transak confirms the payment; refresh optimistically.
    ref.invalidate(hoppaWalletAddressesProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) return _buildLegacy(context);
    final addresses = ref.watch(hoppaWalletAddressesProvider);
    final isExample = context.isExampleTheme;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final amount = _amount;

    Widget form(List<HoppaWalletAsset> available) {
      final destination = _addressFor(available);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSectionTitle(title: context.tr('Stablecoin')),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (final symbol in _buyAssets) ...[
                Expanded(
                  child: _AssetChoice(
                    symbol: symbol,
                    network: available
                        .where((a) => a.symbol.toUpperCase() == symbol)
                        .map((a) => a.network)
                        .firstWhere((n) => n.isNotEmpty, orElse: () => ''),
                    selected: _asset == symbol,
                    onTap: () => setState(() {
                      _asset = symbol;
                      _checkoutUrl = null;
                      _error = null;
                    }),
                  ),
                ),
                if (symbol != _buyAssets.last)
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
                  context.tr('You pay'),
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
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => setState(() {
                          _checkoutUrl = null;
                          _error = null;
                        }),
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
                    const ExamplePill(
                        label: 'USD',
                        color: ExampleColors.lavender,
                        fontSize: 12),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final quick in _quickAmounts)
                      _QuickAmount(
                        amount: quick,
                        selected: amount == quick,
                        onTap: () => setState(() {
                          _amountController.text = quick.toStringAsFixed(0);
                          _checkoutUrl = null;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _OrderLedger(
            asset: _asset,
            amount: amount,
            destination: destination,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: TextStyle(
                  color: ExampleInk.accent(context, ExampleColors.danger),
                  fontSize: 12.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (_checkoutUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            ExampleGlassPanel(
              radius: AppRadii.sm,
              emphasis: true,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Complete the payment with Transak'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Finish the card payment in the Transak checkout. Your $_asset arrives in the wallet once Transak confirms it, usually within a few minutes.'
                    '${_orderId != null ? ' Order $_orderId.' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openCheckout(_checkoutUrl!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(context.tr('Reopen checkout')),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          _BuyCta(
            label: amount <= 0
                ? context.tr('Enter an amount')
                : context.tr('Buy {p0} USD of {p1}',
                    {'p0': amount.toStringAsFixed(2), 'p1': _asset}),
            busy: _submitting,
            onPressed:
                amount <= 0 || _submitting ? null : () => _submit(destination),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
                'Transak is our card payment partner. Fees and the final rate are shown in the Transak checkout before you confirm.'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: ExampleInk.tertiary(context),
            ),
          ),
        ],
      );
    }

    final body = addresses.when(
      data: form,
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(hoppaWalletAddressesProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading wallets')),
    );

    if (widget.asSheet) {
      return _aliveLayer(
        context,
        Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(context.tr('Buy crypto')),
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
          title: Text(context.tr('Buy crypto')),
          leading: IconButton(
            tooltip: context.tr('Back'),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
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
    final addresses = ref.watch(hoppaWalletAddressesProvider);
    final isExample = context.isExampleTheme;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final amount = _amount;

    Widget form(List<HoppaWalletAsset> available) {
      final destination = _addressFor(available);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSectionTitle(title: context.tr('Stablecoin')),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final symbol in _buyAssets) ...[
                Expanded(
                  child: _LegacyAssetChoice(
                    symbol: symbol,
                    network: available
                        .where((a) => a.symbol.toUpperCase() == symbol)
                        .map((a) => a.network)
                        .firstWhere((n) => n.isNotEmpty, orElse: () => ''),
                    selected: _asset == symbol,
                    onTap: () => setState(() {
                      _asset = symbol;
                      _checkoutUrl = null;
                      _error = null;
                    }),
                  ),
                ),
                if (symbol != _buyAssets.last) const SizedBox(width: 8),
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
                Text(
                  context.tr('You pay'),
                  style: TextStyle(
                      fontSize: 12.5,
                      color: context.brandDesign.color(
                          Theme.of(context).brightness, 'textSecondary',
                          fallback: ExampleColors.textSecondary)),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        onChanged: (_) => setState(() {
                          _checkoutUrl = null;
                          _error = null;
                        }),
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
                    const ExamplePill(
                        label: 'USD',
                        color: ExampleColors.lavender,
                        fontSize: 12),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final quick in _quickAmounts)
                      ActionChip(
                        label: Text('\$${quick.toStringAsFixed(0)}'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() {
                          _amountController.text = quick.toStringAsFixed(0);
                          _checkoutUrl = null;
                          _error = null;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ExampleGlassPanel(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LegacyInfoRow(
                  label: context.tr('You receive'),
                  value: amount > 0
                      ? '≈ ${amount.toStringAsFixed(2)} $_asset'
                      : '—',
                ),
                const SizedBox(height: 6),
                _LegacyInfoRow(
                  label: context.tr('Delivered to'),
                  value: destination == null
                      ? 'No $_asset address yet'
                      : '${destination.shortAddress}'
                          '${destination.network.isNotEmpty ? ' · ${destination.network}' : ''}',
                  warning: destination == null,
                ),
                const SizedBox(height: 6),
                _LegacyInfoRow(
                    label: context.tr('Payment'), value: 'Card via Transak'),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(
                  color: context.brandDesign.color(
                      Theme.of(context).brightness, 'warning',
                      fallback: ExampleColors.warning),
                  fontSize: 12.5),
            ),
          ],
          if (_checkoutUrl != null) ...[
            const SizedBox(height: 12),
            ExampleGlassPanel(
              radius: 16,
              emphasis: true,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Complete the payment with Transak'),
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'ink',
                            fallback: ExampleColors.pearl)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Finish the card payment in the Transak checkout. Your $_asset arrives in the wallet once Transak confirms it, usually within a few minutes.'
                    '${_orderId != null ? ' Order $_orderId.' : ''}',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.brandDesign
                          .color(Theme.of(context).brightness, 'ink',
                              fallback: ExampleColors.pearl)
                          .withValues(alpha: .7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => _openCheckout(_checkoutUrl!),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: Text(context.tr('Reopen checkout')),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: amount <= 0 || _submitting
                  ? null
                  : () => _submit(destination),
              icon: _submitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.credit_card_rounded, size: 20),
              label: Text(
                amount <= 0
                    ? context.tr('Enter an amount')
                    : context.tr('Buy {p0} USD of {p1}',
                        {'p0': amount.toStringAsFixed(2), 'p1': _asset}),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr(
                'Transak is our card payment partner. Fees and the final rate are shown in the Transak checkout before you confirm.'),
            style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: context.brandDesign.color(
                    Theme.of(context).brightness, 'textTertiary',
                    fallback: ExampleColors.textTertiary)),
          ),
        ],
      );
    }

    final body = addresses.when(
      data: form,
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(hoppaWalletAddressesProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading wallets')),
    );

    if (widget.asSheet) {
      return Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(context.tr('Buy crypto')),
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
          title: Text(context.tr('Buy crypto')),
          leading: IconButton(
            tooltip: context.tr('Back'),
            onPressed: () =>
                context.canPop() ? context.pop() : context.go('/home'),
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

class _BuyCta extends StatelessWidget {
  const _BuyCta({
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
      // hears "Buy, in progress".
      return ExampleGlassButton(
        label: label,
        icon: Icons.credit_card_rounded,
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
            : const Icon(Icons.credit_card_rounded, size: 20),
        label: Text(label),
      ),
    );
  }
}

class _QuickAmount extends StatelessWidget {
  const _QuickAmount({
    required this.amount,
    required this.selected,
    required this.onTap,
  });

  final double amount;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final label = '\$${amount.toStringAsFixed(0)}';
    return ExamplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      semanticsLabel: context.tr(
          'Pay {p0}{p1}', {'p0': label, 'p1': selected ? ', selected' : ''}),
      child: AnimatedContainer(
        duration: ExampleMotion.of(context, ExampleMotion.state),
        curve: ExampleMotion.arrive,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(
                  alpha: ExampleTheme.isLight(context) ? .10 : .16)
              : ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.fromBorderSide(
            selected
                ? BorderSide(color: accent.withValues(alpha: .55))
                : ExampleBorders.subtleSideOf(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? accent : ExampleInk.secondary(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _AssetChoice extends StatelessWidget {
  const _AssetChoice({
    required this.symbol,
    required this.network,
    required this.selected,
    required this.onTap,
  });

  final String symbol;
  final String network;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final caption = network.isEmpty ? context.tr('Stablecoin') : network;
    return ExamplePressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      semanticsLabel: context.tr('{p0} on {p1}{p2}',
          {'p0': symbol, 'p1': caption, 'p2': selected ? ', selected' : ''}),
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
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ExampleInk.tertiary(context),
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

class _OrderLedger extends StatelessWidget {
  const _OrderLedger({
    required this.asset,
    required this.amount,
    required this.destination,
  });

  final String asset;
  final double amount;
  final HoppaWalletAsset? destination;

  @override
  Widget build(BuildContext context) {
    final target = destination;
    return ExampleListGroup(
      dividerInset: AppSpacing.md,
      children: [
        ExampleRow(
          title: context.tr('You receive'),
          minHeight: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          trailing: ExampleRowValue(
            value: amount > 0
                ? '≈ ${_amountLabel(asset, amount)}'
                : ExampleAmount.placeholder,
          ),
        ),
        ExampleRow(
          title: context.tr('Delivered to'),
          subtitle:
              target == null || target.network.isEmpty ? null : target.network,
          minHeight: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          trailing: target == null
              ? ExampleRowValue(
                  value: 'No address yet',
                  color: ExampleInk.accent(context, ExampleColors.warning),
                )
              : ExampleMono(
                  target.address,
                  truncate: ExampleMonoTruncate.middle,
                  size: 12.5,
                  weight: FontWeight.w500,
                  color: ExampleInk.primary(context),
                ),
        ),
        ExampleRow(
          title: context.tr('Payment'),
          minHeight: 44,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xxs,
          ),
          trailing: const ExampleRowValue(value: 'Card · Transak'),
        ),
      ],
    );
  }
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool? _bool(Object? value) {
  if (value is bool) return value;
  if (value is String) {
    if (value.toLowerCase() == 'true') return true;
    if (value.toLowerCase() == 'false') return false;
  }
  return null;
}

class _LegacyAssetChoice extends StatelessWidget {
  const _LegacyAssetChoice({
    required this.symbol,
    required this.network,
    required this.selected,
    required this.onTap,
  });

  final String symbol;
  final String network;
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
                    network.isEmpty ? context.tr('Stablecoin') : network,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

class _LegacyInfoRow extends StatelessWidget {
  const _LegacyInfoRow({
    required this.label,
    required this.value,
    this.warning = false,
  });

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  color: context.brandDesign.color(
                      Theme.of(context).brightness, 'textSecondary',
                      fallback: ExampleColors.textSecondary))),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: warning
                    ? context.brandDesign.color(
                        Theme.of(context).brightness, 'warning',
                        fallback: ExampleColors.warning)
                    : context.brandDesign.color(
                        Theme.of(context).brightness, 'ink',
                        fallback: ExampleColors.pearl),
              ),
            ),
          ),
        ],
      );
}
