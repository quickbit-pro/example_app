import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/crypto/crypto_address_validator.dart';
import '../../../core/formatters/amount_input.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../auth/presentation/example_otp_field.dart';
import '../../platform/application/platform_providers.dart';
import '../data/wallet_providers.dart';
import '../domain/wallet_models.dart';
import '../domain/withdrawal_models.dart';
import '../domain/withdrawal_networks.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

const double _exampleColumnWidth = 520;

const EdgeInsets _bareRowPadding = EdgeInsets.symmetric(
  horizontal: AppSpacing.md,
  vertical: AppSpacing.sm,
);

Future<void> showCryptoWithdrawalDialog(
  BuildContext context, {
  required HoppaWalletAsset asset,
}) =>
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _CryptoWithdrawalDialog(asset: asset),
    );

class _CryptoWithdrawalDialog extends ConsumerStatefulWidget {
  const _CryptoWithdrawalDialog({required this.asset});

  final HoppaWalletAsset asset;

  @override
  ConsumerState<_CryptoWithdrawalDialog> createState() =>
      _CryptoWithdrawalDialogState();
}

class _CryptoWithdrawalDialogState
    extends ConsumerState<_CryptoWithdrawalDialog> {
  final _amountController = TextEditingController();
  final _addressController = TextEditingController();
  final _otpController = TextEditingController();

  late HoppaWalletAsset _asset = widget.asset;
  String _chain = 'ETH';
  String? _addressError;
  CryptoWithdrawalBalance? _balance;
  CryptoWithdrawalQuote? _quote;
  CryptoWithdrawalResult? _start;
  bool _confirmed = false;
  bool _loading = false;
  String? _error;

  bool _networkOpen = false;

  String get _currency => _asset.symbol.toUpperCase();
  Map<String, String> get _networks => withdrawalNetworksFor(_currency);
  bool get _addressValid =>
      _networks.containsKey(_chain) &&
      CryptoAddressValidator.validate(_addressController.text, network: _chain)
          .isValid;
  String? get _amountProblem {
    if (_amountController.text.trim().isEmpty) return null;
    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null ||
        !amount.isFinite ||
        amount < minimumCryptoWithdrawal) {
      return context.tr('Minimum withdrawal is 5 {p0}.', {'p0': _currency});
    }
    if (amount > _available) {
      return context.tr('Amount exceeds the available balance.');
    }
    return null;
  }

  bool get _canReview {
    final amount = double.tryParse(_amountController.text.trim());
    return amount != null &&
        amount.isFinite &&
        amount >= minimumCryptoWithdrawal &&
        amount <= _available &&
        _addressValid;
  }

  @override
  void initState() {
    super.initState();
    _amountController.addListener(_amountChanged);
  }

  void _amountChanged() {
    setState(() {});
  }

  void _selectAsset(HoppaWalletAsset asset) {
    setState(() {
      _asset = asset;
      if (!_networks.containsKey(_chain)) {
        _chain = _networks.keys.firstOrNull ?? '';
      }
      _addressError = _addressController.text.trim().isEmpty
          ? null
          : CryptoAddressValidator.validate(_addressController.text,
                  network: _chain)
              .error;
      _confirmed = false;
      _networkOpen = false;
      _quote = null;
      _balance = null;
      _error = null;
      _amountController.clear();
    });
  }

  /// Validates the destination for the selected network; returns true when
  /// it can be submitted.
  bool _checkAddress({bool showError = true}) {
    final check = CryptoAddressValidator.validate(
      _addressController.text,
      network: _chain,
    );
    setState(() => _addressError =
        check.isValid || (!showError && _addressController.text.trim().isEmpty)
            ? null
            : check.error);
    return check.isValid;
  }

  bool get _isOtpStep => _start?.verificationToken.isNotEmpty == true;
  double get _available => math.min(
        _asset.amount,
        _balance?.availableFor(_currency) ?? _asset.amount,
      );

  @override
  void dispose() {
    _amountController.dispose();
    _addressController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _review() async {
    final amount = double.tryParse(_amountController.text.trim());
    final address = _addressController.text.trim();
    if (!_networks.containsKey(_chain) || !_checkAddress()) return;
    if (amount == null ||
        !amount.isFinite ||
        amount < minimumCryptoWithdrawal) {
      setState(() => _error = 'Enter an amount of at least 5 $_currency.');
      return;
    }
    if (amount > _available) {
      setState(() => _error =
          'Your available $_currency balance is ${_asset.amount.toStringAsFixed(6)}.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(mobilePlatformApiProvider);
      final balance = await api.getCryptoWithdrawalAvailableBalance();
      final available = math.min(
        _asset.amount,
        balance.availableFor(_currency),
      );
      if (amount > available) {
        throw Exception(
          'Your available $_currency withdrawal balance is ${available.toStringAsFixed(6)}.',
        );
      }
      final quote = await api.getCryptoWithdrawalFeeAndQuota(
        chain: _chain,
        address: address,
        currency: _currency,
        amount: _amountController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _balance = balance;
        _quote = quote;
        _confirmed = false;
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestCode() async {
    if (!_confirmed) {
      setState(() => _error = 'Confirm the reviewed withdrawal details.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).createCryptoWithdrawal(
                currency: _currency,
                chain: _chain,
                amount: _amountController.text.trim(),
                destinationAddress: _addressController.text.trim(),
              );
      if (!result.success) {
        throw Exception(
          result.message.isEmpty
              ? 'The withdrawal could not be started.'
              : result.message,
        );
      }
      if (!mounted) return;
      if (result.verificationToken.isEmpty && !result.otpRequired) {
        _complete(result);
        return;
      }
      if (result.verificationToken.isEmpty) {
        throw Exception('A verification token was not returned. Try again.');
      }
      setState(() {
        _start = result;
        _otpController.clear();
      });
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 8) {
      setState(() => _error = 'Enter the full 8-digit verification code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).confirmCryptoWithdrawal(
                verificationToken: _start!.verificationToken,
                otpCode: otp,
              );
      if (!result.success) {
        throw Exception(
          result.message.isEmpty
              ? 'The verification code could not be confirmed.'
              : result.message,
        );
      }
      if (mounted) _complete(result);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).resendCryptoWithdrawalOtp(
                verificationToken: _start!.verificationToken,
              );
      if (!result.success) {
        throw Exception(
          result.message.isEmpty
              ? 'A new code could not be sent.'
              : result.message,
        );
      }
      _otpController.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message.isEmpty
                ? context.tr('A new verification code was sent.')
                : result.message),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _complete(CryptoWithdrawalResult result) {
    ref.invalidate(hoppaWalletAssetsProvider);
    ref.invalidate(userAssetsProvider);
    ref.invalidate(userWalletsProvider);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message.isEmpty
            ? context.tr('Withdrawal submitted successfully.')
            : result.message),
      ),
    );
  }

  void _editDetails() => setState(() {
        _quote = null;
        _confirmed = false;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final primaryLabel = _isOtpStep
        ? 'Confirm withdrawal'
        : _quote == null
            ? 'Review withdrawal'
            : 'Send verification code';
    final primaryAction =
        _loading || (!_isOtpStep && _quote == null && !_canReview)
            ? null
            : _isOtpStep
                ? _confirmOtp
                : _quote == null
                    ? _review
                    : _requestCode;

    final isExample = context.isExampleTheme;
    final destructive = isExample && _isOtpStep;

    final Widget cta = isExample
        ? ExampleGlassButton(
            label: primaryLabel,
            tone: destructive
                ? ExampleGlassButtonTone.danger
                : ExampleGlassButtonTone.primary,
            loading: _loading,
            sheen: false,
            semanticsLabel: destructive
                ? context.tr(
                    '{p0}. This sends the funds and cannot be reversed',
                    {'p0': primaryLabel})
                : null,
            onPressed: primaryAction,
          )
        : FilledButton(
            onPressed: primaryAction,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15),
              child: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: AppProgressIndicator(strokeWidth: 2),
                    )
                  : Text(primaryLabel),
            ),
          );

    final body = ListView(
      padding: isExample
          ? const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xl,
            )
          : const EdgeInsets.fromLTRB(20, 16, 20, 120),
      children: [
        if (_isOtpStep)
          isExample ? _exampleOtpStep(context) : _buildOtpStep(context)
        else if (_quote != null)
          isExample ? _exampleReview(context) : _buildReview(context)
        else
          isExample ? _exampleDetails(context) : _buildDetails(context),
        if (!isExample && _error != null) ...[
          const SizedBox(height: AppSpacing.md),
          _InlineError(message: _error!),
        ],
      ],
    );

    final scaffold = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_isOtpStep
            ? context.tr('Verify withdrawal')
            : context.tr('Withdraw {p0}', {'p0': _currency})),
        actions: [
          IconButton(
            tooltip: context.tr('Close'),
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: isExample ? _column(body) : body,
      bottomNavigationBar: isExample
          ? _ExampleCtaBar(
              child: _column(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      _InlineError(message: _error!),
                      const SizedBox(height: AppSpacing.sm),
                    ],
                    cta,
                  ],
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: cta,
              ),
            ),
    );

    return FractionallySizedBox(
      heightFactor: .93,
      child: ExampleAliveLayer(enabled: isExample, child: scaffold),
    );
  }

  Widget _column(Widget child) => Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _exampleColumnWidth),
          child: child,
        ),
      );

  Widget _buildDetails(BuildContext context) {
    if (_quote != null) return _buildReview(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_available < minimumCryptoWithdrawal)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(context.tr(
                'This wallet is below the minimum withdrawal of 5 {p0}. Deposit more to continue.',
                {'p0': _currency})),
          ),
        Text(
          context.tr('Send stablecoins to an external wallet'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.tr(
              'Check the network and address carefully. Crypto transfers cannot be reversed.'),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        NeoSurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('From'),
                  style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: AppSpacing.xs),
              Builder(
                builder: (context) {
                  final options = _assetOptions();
                  if (options.length <= 1) {
                    return _AssetRow(asset: _asset, currency: _currency);
                  }
                  return DropdownButtonFormField<String>(
                    key: ValueKey(_currency),
                    initialValue: _currency,
                    // The closed field lays its child out unconstrained, so
                    // the row only gets a full width when expanded.
                    isExpanded: true,
                    selectedItemBuilder: (context) => [
                      for (final option in options)
                        _AssetRow(
                          asset: option,
                          currency: option.symbol.toUpperCase(),
                        ),
                    ],
                    decoration: const InputDecoration(
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final option in options)
                        DropdownMenuItem(
                          value: option.symbol.toUpperCase(),
                          child: _AssetRow(
                            asset: option,
                            currency: option.symbol.toUpperCase(),
                          ),
                        ),
                    ],
                    onChanged: _loading
                        ? null
                        : (value) {
                            final next = options.where(
                              (o) => o.symbol.toUpperCase() == value,
                            );
                            if (next.isNotEmpty) _selectAsset(next.first);
                          },
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<String>(
          key: ValueKey('network-$_currency-$_chain'),
          initialValue: _chain,
          decoration: InputDecoration(labelText: context.tr('Network')),
          items: [
            for (final entry in _networks.entries)
              DropdownMenuItem(
                value: entry.key,
                child: Text('${entry.value} (${entry.key})'),
              ),
          ],
          onChanged: _loading
              ? null
              : (value) {
                  if (value != null) _selectChain(value);
                },
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _addressController,
          enabled: !_loading,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _checkAddress(showError: false),
          decoration: InputDecoration(
            labelText: context.tr('Destination wallet address'),
            helperText: CryptoAddressValidator.hint(
              CryptoAddressValidator.familyForNetwork(_chain),
            ),
            errorText: _addressError,
            errorMaxLines: 3,
            suffixIcon: _addressValid
                ? Icon(Icons.check_circle_rounded,
                    color: context.brandDesign.color(
                        Theme.of(context).brightness, 'success',
                        fallback: Colors.green))
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _amountController,
          enabled: !_loading,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
          ],
          decoration: InputDecoration(
            labelText: context.tr('Amount ({p0})', {'p0': _currency}),
            errorText: _amountProblem,
            errorMaxLines: 3,
            helperText: context.tr('Minimum 5 {p0} · Available {p1}',
                {'p0': _currency, 'p1': _asset.amount.toStringAsFixed(6)}),
            suffixIcon: TextButton(
              onPressed: _loading || _available < minimumCryptoWithdrawal
                  ? null
                  : () => _amountController.text =
                      maxAmountInput(_available, decimals: 2),
              child: Text(context.tr('Max')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReview(BuildContext context) {
    final quote = _quote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Review withdrawal'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(context
            .tr('A verification code will be emailed after you continue.')),
        const SizedBox(height: AppSpacing.lg),
        NeoSurfaceCard(
          child: Column(
            children: [
              _ReviewRow(
                  label: context.tr('You send'),
                  value: '${_amountController.text} $_currency'),
              _ReviewRow(
                  label: context.tr('Network'),
                  value: '${_networks[_chain]} ($_chain)'),
              _ReviewRow(
                  label: context.tr('Available'),
                  value: '${_available.toStringAsFixed(6)} $_currency'),
              for (final fee in quote.fees)
                _ReviewRow(
                  label: _feeLabel(fee.type),
                  value: '${fee.amount.toStringAsFixed(6)} ${fee.currency}',
                ),
              if (quote.crossChainAmount.isNotEmpty)
                _ReviewRow(
                  label: context.tr('Cross-chain amount'),
                  value: quote.crossChainAmount,
                ),
              const Divider(),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _addressController.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: context.brandDesign.isConfigured
                            ? context.brandDesign.monoFontFamily
                            : 'monospace',
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _confirmed,
          onChanged: _loading
              ? null
              : (value) => setState(() => _confirmed = value ?? false),
          title: Text(
              context.tr('I checked the network, address, amount, and fees')),
          subtitle: Text(context.tr('This transfer cannot be reversed.')),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        TextButton.icon(
          onPressed: _loading ? null : _editDetails,
          icon: const Icon(Icons.edit_outlined),
          label: Text(context.tr('Edit details')),
        ),
      ],
    );
  }

  Widget _buildOtpStep(BuildContext context) {
    final expiresAt = _start?.otpExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.mark_email_read_outlined, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          context.tr('Check your email'),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _start!.message.isEmpty
              ? context.tr(
                  'Enter the 8-digit code sent to your registered email address.')
              : _start!.message,
        ),
        if (expiresAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('Code expires at {p0}.', {
              'p0': TimeOfDay.fromDateTime(expiresAt.toLocal()).format(context)
            }),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ExampleOtpField(
          controller: _otpController,
          length: 8,
          enabled: !_loading,
          label: context.tr('Verification code'),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _loading ? null : _resend,
            child: Text(context.tr('Resend code')),
          ),
        ),
      ],
    );
  }

  Widget _exampleDetails(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final options = _assetOptions();
    final pending =
        ref.watch(hoppaWalletAssetsProvider).isLoading && options.length < 2;
    final family = CryptoAddressValidator.familyForNetwork(_chain);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_available < minimumCryptoWithdrawal)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(context.tr(
                'This wallet is below the minimum withdrawal of 5 {p0}. Deposit more to continue.',
                {'p0': _currency})),
          ),
        _ExampleStepHeading(
          step: 1,
          title: context.tr('Send to an external wallet'),
          body: context.tr(
              'Check the network and the address before you continue. A crypto transfer cannot be reversed or recalled.'),
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleListGroup(
          title: context.tr('From'),
          level: 2,
          children: [
            for (final option in options)
              _exampleWalletRow(context, option, options.length == 1),
            if (pending)
              const ExampleSkeleton.row(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleListGroup(
          title: context.tr('Network'),
          level: 2,
          dividerInset: AppSpacing.md,
          children: _networkOpen
              ? [
                  for (final entry in _networks.entries)
                    ExampleRow(
                      title: entry.value,
                      subtitle: _networkShape(entry.key),
                      padding: _bareRowPadding,
                      semanticsLabel: entry.key == _chain
                          ? '${entry.value}, ${_networkShape(entry.key)}, '
                              'selected'
                          : 'Send on ${entry.value}, '
                              '${_networkShape(entry.key)}',
                      onTap: _loading ? null : () => _selectChain(entry.key),
                      trailing: entry.key == _chain
                          ? Icon(
                              Icons.check_rounded,
                              size: 20,
                              color: palette.accent,
                            )
                          : null,
                    ),
                ]
              : [
                  ExampleRow(
                    title: _networks[_chain] ?? _chain,
                    subtitle: _networkShape(_chain),
                    padding: _bareRowPadding,
                    trailing: ExampleRow.chevron,
                    semanticsLabel: 'Network, ${_networks[_chain] ?? _chain}. '
                        'Change network',
                    onTap: _loading
                        ? null
                        : () => setState(() => _networkOpen = true),
                  ),
                ],
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleSectionTitle(title: context.tr('Send to')),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _addressController,
          enabled: !_loading,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: (_) => _checkAddress(showError: false),
          decoration: InputDecoration(
            labelText: context.tr('Destination wallet address'),
            helperText: CryptoAddressValidator.hint(family),
            helperMaxLines: 2,
            errorText: _addressError,
            errorMaxLines: 3,
            suffixIcon: _addressValid
                ? Icon(Icons.check_circle_rounded, color: palette.success)
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleSectionTitle(title: context.tr('Amount')),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _amountController,
          enabled: !_loading,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: ExampleTextStyles.amount(
            context,
            size: ExampleAmountSize.small,
          ).copyWith(color: palette.ink),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,8}')),
          ],
          decoration: InputDecoration(
            labelText: context.tr('Amount ({p0})', {'p0': _currency}),
            errorText: _amountProblem,
            errorMaxLines: 3,
            helperText: 'Minimum 5 $_currency  ·  Available '
                '${Money.formatAmount(_currency, _available)}',
            helperMaxLines: 2,
            suffixIcon: TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
                foregroundColor: palette.accent,
                tapTargetSize: MaterialTapTargetSize.padded,
              ),
              onPressed: _loading || _available < minimumCryptoWithdrawal
                  ? null
                  : () => _amountController.text =
                      maxAmountInput(_available, decimals: 2),
              child: Text(context.tr('Max')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _exampleWalletRow(
    BuildContext context,
    HoppaWalletAsset option,
    bool only,
  ) {
    final symbol = option.symbol.toUpperCase();
    final selected = symbol == _currency;
    final balance = Money.formatAmount(symbol, option.amount);
    return ExampleRow(
      title: context.tr('{p0} Wallet', {'p0': symbol}),
      subtitle: balance,
      leading: ExampleCurrencyAvatar(code: symbol, size: 32),
      trailing: selected
          ? Icon(
              Icons.check_rounded,
              size: 20,
              color: ExamplePalette.of(context).accent,
            )
          : null,
      semanticsLabel: selected
          ? context
              .tr('{p0} wallet, {p1}, selected', {'p0': symbol, 'p1': balance})
          : context.tr(
              'Send from the {p0} wallet, {p1}', {'p0': symbol, 'p1': balance}),
      onTap: only || _loading ? null : () => _selectAsset(option),
    );
  }

  Widget _exampleReview(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final quote = _quote!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ExampleStepHeading(
          step: 2,
          title: context.tr('Review withdrawal'),
          body: context
              .tr('A verification code will be emailed after you continue.'),
        ),
        const SizedBox(height: AppSpacing.lg),
        _ExampleWithdrawalLedger(
          currency: _currency,
          sendAmount: double.tryParse(_amountController.text.trim()),
          network: '${_networks[_chain]} ($_chain)',
          available: _available,
          fees: quote.fees,
          crossChainAmount: quote.crossChainAmount,
          address: _addressController.text.trim(),
        ),
        const SizedBox(height: AppSpacing.md),
        _ExampleConfirmCheck(
          value: _confirmed,
          onChanged:
              _loading ? null : (value) => setState(() => _confirmed = value),
        ),
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: palette.accent,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
            ),
            onPressed: _loading ? null : _editDetails,
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(context.tr('Edit details')),
          ),
        ),
      ],
    );
  }

  Widget _exampleOtpStep(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final expiresAt = _start?.otpExpiresAt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 40,
          color: palette.accent,
        ),
        const SizedBox(height: AppSpacing.md),
        _ExampleStepHeading(
          step: 3,
          title: context.tr('Check your email'),
          body: _start!.message.isEmpty
              ? context.tr(
                  'Enter the 8-digit code sent to your registered email address.')
              : _start!.message,
        ),
        if (expiresAt != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Code expires at '
            '${TimeOfDay.fromDateTime(expiresAt.toLocal()).format(context)}.',
            style: TextStyle(fontSize: 12, color: palette.textTertiary),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        ExampleOtpField(
          controller: _otpController,
          length: 8,
          enabled: !_loading,
          label: context.tr('Verification code'),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: palette.accent,
            ),
            onPressed: _loading ? null : _resend,
            child: Text(context.tr('Resend code')),
          ),
        ),
      ],
    );
  }

  void _selectChain(String chain) {
    if (!_networks.containsKey(chain)) return;
    setState(() {
      _chain = chain;
      _networkOpen = false;
    });
    if (_addressController.text.trim().isNotEmpty) _checkAddress();
  }

  static String _networkShape(String chain) =>
      switch (CryptoAddressValidator.familyForNetwork(chain)) {
        CryptoAddressFamily.evm => '$chain  ·  0x address',
        CryptoAddressFamily.tron => '$chain  ·  T address',
        null => chain,
      };
}

class _ExampleCtaBar extends StatelessWidget {
  const _ExampleCtaBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          border: Border(
            top: BorderSide(color: ExamplePalette.of(context).borderSubtle),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: child,
          ),
        ),
      );
}

class _ExampleStepHeading extends StatelessWidget {
  const _ExampleStepHeading({
    required this.title,
    required this.body,
    required this.step,
  });

  final String title;
  final String body;

  final int step;

  static const int steps = 3;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('STEP {p0} OF {p1}', {'p0': step, 'p1': steps}),
          style: ExampleTextStyles.label(context),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          title,
          style: TextStyle(
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: -.3,
            color: palette.ink,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          body,
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: palette.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _ExampleConfirmCheck extends StatelessWidget {
  const _ExampleConfirmCheck({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final enabled = onChanged != null;
    return Material(
      color: ExampleSurface.of(context, 2),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(
          color: value ? palette.borderEmphasis : palette.borderSubtle,
        ),
      ),
      child: CheckboxListTile(
        value: value,
        onChanged: enabled ? (next) => onChanged!(next ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        activeColor: palette.fill,
        checkColor: palette.onFill,
        side: BorderSide(color: palette.borderEmphasis, width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.lg),
        ),
        title: Text(
          context.tr('I checked the network, address, amount and fees'),
          style: TextStyle(
            fontSize: 13.5,
            height: 1.35,
            fontWeight: FontWeight.w600,
            color: palette.ink,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            context.tr('This transfer cannot be reversed.'),
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: palette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleWithdrawalLedger extends StatelessWidget {
  const _ExampleWithdrawalLedger({
    required this.currency,
    required this.sendAmount,
    required this.network,
    required this.available,
    required this.fees,
    required this.crossChainAmount,
    required this.address,
  });

  final String currency;
  final double? sendAmount;
  final String network;
  final double available;
  final List<CryptoWithdrawalFee> fees;
  final String crossChainAmount;
  final String address;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LedgerLine(
            label: context.tr('You send'),
            amount: sendAmount,
            currency: currency,
            first: true,
          ),
          for (final fee in fees)
            _LedgerLine(
              label: _feeLabel(fee.type),
              amount: fee.amount,
              currency: fee.currency,
            ),
          if (crossChainAmount.isNotEmpty)
            _LedgerLine(
                label: context.tr('Cross-chain amount'),
                value: crossChainAmount),
          _LedgerLine(
            label: context.tr('Available to send'),
            amount: available,
            currency: currency,
          ),
          _LedgerLine(label: context.tr('Network'), value: network),
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: palette.borderSubtle)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr('DESTINATION'),
                    style: ExampleTextStyles.label(context)),
                const SizedBox(height: AppSpacing.xs),
                ExampleMono(
                  address,
                  size: 12.5,
                  group: 4,
                  maxLines: 6,
                  color: palette.ink,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerLine extends StatelessWidget {
  const _LedgerLine({
    required this.label,
    this.value,
    this.amount,
    this.currency = '',
    this.first = false,
  }) : assert(
          value != null || currency != '',
          'a money line needs a currency, a text line needs a value',
        );

  final String label;

  final String? value;

  final double? amount;
  final String currency;
  final bool first;

  static const int _labelFlex = 5;

  static const int _figureFlex = 7;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final text = value;
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs + 2,
      ),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: palette.borderSubtle)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: _labelFlex,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                color: palette.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: _figureFlex,
            child: text != null
                ? Text(
                    text,
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                    ),
                  )
                : ExampleAmount(
                    amount: amount,
                    currency: currency,
                    size: ExampleAmountSize.inline,
                    code: ExampleAmountCode.always,
                    animate: false,
                    textAlign: TextAlign.end,
                    color: palette.ink,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(label)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!context.isExampleTheme) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(message)),
            ],
          ),
        ),
      );
    }

    final palette = ExamplePalette.of(context);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 2),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: palette.danger.withValues(alpha: .38)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: palette.danger,
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _feeLabel(String type) => switch (type.toUpperCase()) {
      'GAS' => 'Network fee',
      'CROSS_CHAIN' => 'Cross-chain fee',
      _ => 'Fee',
    };

extension on _CryptoWithdrawalDialogState {
  /// Stablecoin wallets the customer can withdraw from; the dialog's initial
  /// asset is always included even while balances are still loading.
  List<HoppaWalletAsset> _assetOptions() {
    final loaded = ref.watch(hoppaWalletAssetsProvider).valueOrNull ?? const [];
    final bySymbol = <String, HoppaWalletAsset>{};
    for (final asset in loaded) {
      final symbol = asset.symbol.toUpperCase();
      if (symbol != 'USDC' && symbol != 'USDT') continue;
      final existing = bySymbol[symbol];
      if (existing == null || asset.amount > existing.amount) {
        bySymbol[symbol] = asset;
      }
    }
    bySymbol.putIfAbsent(_currency, () => _asset);
    final options = bySymbol.values.toList()
      ..sort((a, b) => a.symbol.compareTo(b.symbol));
    return options;
  }
}

class _AssetRow extends StatelessWidget {
  const _AssetRow({required this.asset, required this.currency});

  final HoppaWalletAsset asset;
  final String currency;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          CurrencyLogo(symbol: currency, fallbackIcon: Icons.token_outlined),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              context.tr('{p0} Wallet', {'p0': currency}),
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('${asset.amount.toStringAsFixed(6)} $currency'),
        ],
      );
}
