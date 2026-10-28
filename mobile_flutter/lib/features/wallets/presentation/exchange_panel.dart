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
    void open(ExchangeFlow flow) => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ExchangeFlowDialog(
            flow: flow,
            overview: overview,
            outflowsEnabled: outflowsEnabled,
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
    final eligibleWallets = wallets
        .where((w) =>
            w.walletId.isNotEmpty &&
            ['USDC', 'USDT'].contains(w.symbol.toUpperCase()) &&
            exchangeChainId(w.network) != 0)
        .toList();
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
              _showCryptoToEqualsDialog(
                  context, ref, overview, budgets, eligibleWallets);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'destinations', child: Text('Saved destinations')),
            PopupMenuItem(
                value: 'fund',
                enabled: outflowsEnabled &&
                    budgets.isNotEmpty &&
                    eligibleWallets.isNotEmpty,
                child: const Text('Fiat account to crypto wallet')),
            PopupMenuItem(
                value: 'sell',
                enabled: outflowsEnabled &&
                    budgets.isNotEmpty &&
                    eligibleWallets.isNotEmpty,
                child: const Text('Crypto wallet to fiat account')),
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
      ExchangeDepositHistory(deposits: overview.deposits),
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
  var termsAccepted = false;
  final reference = 'mobile-equals-${DateTime.now().microsecondsSinceEpoch}';

  Map<String, Object?> request() => {
        'boomFiAccountId': overview.accountId.toString(),
        'reference': reference,
        'chainId': _chainId(wallet.network),
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
                initialValue: wallet.walletId,
                isExpanded: true,
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
                onChanged: busy || verificationToken.isNotEmpty
                    ? null
                    : (value) => setState(() {
                          wallet = wallets
                              .firstWhere((item) => item.walletId == value);
                          quote = null;
                          termsAccepted = false;
                        }),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: budget.id,
                isExpanded: true,
                decoration: InputDecoration(
                    labelText: context.tr('Equals destination')),
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
                          fiatCurrency = _resourceCurrency(budget);
                          quote = null;
                          termsAccepted = false;
                        }),
              ),
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

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
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
