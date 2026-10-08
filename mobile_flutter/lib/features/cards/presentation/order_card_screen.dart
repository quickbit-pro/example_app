import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example_colors.dart';
import '../../../brands/example/example_tilt.dart';
import '../../../brands/example/example_glass_button.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import '../../../flavors.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/card_discount.dart';
import '../../../core/models/equals_money.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/tier_details_sheet.dart';
import '../../signup/presentation/legal_agreements.dart';
import 'card_order_failure.dart';
import 'widgets/card_face.dart';
import 'widgets/neo_bank_card.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class OrderCardScreen extends ConsumerStatefulWidget {
  const OrderCardScreen({super.key});

  @override
  ConsumerState<OrderCardScreen> createState() => _OrderCardScreenState();
}

class _OrderCardScreenState extends ConsumerState<OrderCardScreen> {
  PlatformResource? _resolvedTier;
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController(text: 'New card');
  final _addressLine1Controller = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController(text: 'US');
  final _postalCodeController = TextEditingController();
  final _budgetNameController = TextEditingController();
  final _discountController = TextEditingController();
  CardDiscount? _discount;
  String? _appliedDiscountCode;
  String? _discountError;
  bool _validatingDiscount = false;
  int _discountRequest = 0;
  int _selectedCardIndex = 0;
  String? _selectedBudgetId;
  int _selectedSkinIndex = 0;

  @override
  void initState() {
    super.initState();
    // Repaint preview as user types the label.
    _labelController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressLine1Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _postalCodeController.dispose();
    _budgetNameController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final actionState = ref.watch(bankingActionControllerProvider);
    final platformActionState = ref.watch(platformActionControllerProvider);
    final currentTier = ref.watch(currentTierProvider);
    final tiers = ref.watch(tiersProvider);
    final budgets = ref.watch(budgetsProvider);

    ref.listen(bankingActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          if ((previous?.isLoading != true || previous?.hasValue != true)) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.tr('Card ordered'))),
          );
          context.go('/cards');
        },
        error: (error, stackTrace) => _showOrderFailure(error),
      );
    });

    ref.listen(platformActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if ((previous?.isLoading == true && previous?.hasValue == true) &&
              result != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result.message)),
            );
          }
        },
        error: (error, stackTrace) =>
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        ),
      );
    });

    final issuerStatus = ref.watch(kycDetailedStatusProvider);
    if (issuerStatus.isLoading ||
        issuerStatus.hasError ||
        issuerStatus.valueOrNull?.interlaceKycApproved != true) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Order card'))),
        body: issuerStatus.isLoading
            ? LoadingState(label: context.tr('Checking card verification'))
            : issuerStatus.hasError
                ? ErrorState(
                    error: issuerStatus.error!,
                    title: 'Unable to check card verification',
                    onRetry: () => ref.invalidate(kycDetailedStatusProvider),
                  )
                : EmptyState(
                    title: 'Card verification pending',
                    message:
                        'Interlace must approve your verification before you can order a card.',
                    icon: Icons.verified_user_outlined,
                    action: FilledButton(
                      onPressed: () =>
                          ref.invalidate(kycDetailedStatusProvider),
                      child: Text(context.tr('Refresh status')),
                    ),
                  ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Order card'))),
      body: currentTier.when(
        data: (tier) {
          if (tier == null || _tierId(tier) == null) {
            return _NoTierSelected(tiers: tiers);
          }
          final tierId = _tierId(tier)!.toString();
          final cardTier = ref.watch(cardTierProvider(tierId));

          Widget orderForm(PlatformResource resolvedTier) {
            _resolvedTier = resolvedTier;
            final options = _cardOptionsForTier(resolvedTier);
            if (_selectedCardIndex >= options.length) {
              _selectedCardIndex = 0;
            }

            var stepIndex = 0;
            String nextStep() => '${++stepIndex}';
            final issuerDesign = options.isNotEmpty &&
                options[_selectedCardIndex].artworkUrl.isNotEmpty;
            final wide = context.isExampleTheme &&
                MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
            final padding = EdgeInsets.fromLTRB(
              wide ? 40 : 16,
              wide ? 24 : 12,
              wide ? 40 : 16,
              _bottomNavigationClearance(context),
            );
            final heroChildren = <Widget>[
              // Live preview hero. Repaints on label/skin/option change.
              _OrderPreviewHero(
                label: _labelController.text.trim().isEmpty
                    ? context.tr('New card')
                    : _labelController.text,
                option: options.isEmpty ? null : options[_selectedCardIndex],
                skin: NeoCardSkin
                    .all[_selectedSkinIndex % NeoCardSkin.all.length],
              ),
            ];
            final stepChildren = <Widget>[
              if (options.isEmpty)
                EmptyState(
                  title: context.tr('No card types in this tier'),
                  message: context.tr(
                      'Select another tier or contact support to enable card ordering.'),
                  icon: Icons.credit_card_off_outlined,
                )
              else ...[
                _SectionLabel(
                  step: nextStep(),
                  title: context.tr('Choose your card'),
                  subtitle: context.tr('{p0} option{p1} in {p2}', {
                    'p0': options.length,
                    'p1': options.length == 1 ? '' : 's',
                    'p2': _tierTitle(resolvedTier)
                  }),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 132,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => _CardTypePickerTile(
                      option: options[index],
                      selected: index == _selectedCardIndex,
                      onTap: () => setState(() => _selectedCardIndex = index),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _discountField(actionState.isLoading),
                const SizedBox(height: 12),
                _CostsPanel(
                  option: options[_selectedCardIndex],
                  tier: resolvedTier,
                  discount: _discount,
                ),
                // The issuer's own artwork is the only design for that
                // card, so the design step only appears when there is a
                // choice to make.
                if (!issuerDesign) ...[
                  const SizedBox(height: 22),
                  _SectionLabel(
                    step: nextStep(),
                    title: context.tr('Pick a design'),
                    subtitle: context.tr(
                        'A fallback preview is used because the issuer did not supply artwork.'),
                  ),
                  const SizedBox(height: 10),
                  _SkinPicker(
                    selectedIndex: _selectedSkinIndex,
                    onSelect: (i) => setState(() => _selectedSkinIndex = i),
                  ),
                ],
                const SizedBox(height: 22),
                _SectionLabel(
                  step: nextStep(),
                  title: context.tr('Name your card'),
                  subtitle: context.tr('A label that shows up in your wallet.'),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _labelController,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Card label'),
                    hintText:
                        context.tr('e.g. Daily spend, Travel, Subscriptions'),
                    prefixIcon: const Icon(Icons.badge_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.tr('Enter a card label');
                    }
                    return null;
                  },
                ),
                if (options[_selectedCardIndex].isEqualsMoney) ...[
                  const SizedBox(height: 22),
                  _SectionLabel(
                    step: nextStep(),
                    title: context.tr('Link a budget'),
                    subtitle:
                        context.tr('Fiat cards must be linked to a budget.'),
                  ),
                  const SizedBox(height: 10),
                  budgets.when(
                    data: (items) => _EqualsBudgetSelector(
                      budgets: _equalsBudgetAccounts(items),
                      cardCurrency: options[_selectedCardIndex].currency,
                      selectedBudgetId: _selectedBudgetId,
                      isBusy: platformActionState.isLoading,
                      onChanged: (value) =>
                          setState(() => _selectedBudgetId = value),
                      onCreateBudget: () => _showCreateBudgetDialog(
                        options[_selectedCardIndex].currency,
                      ),
                    ),
                    error: (error, stackTrace) => ErrorState(
                      error: error,
                      onRetry: () => ref.invalidate(budgetsProvider),
                    ),
                    loading: () =>
                        LoadingState(label: context.tr('Loading budgets')),
                  ),
                ],
                if (!options[_selectedCardIndex].isVirtual) ...[
                  const SizedBox(height: 22),
                  _SectionLabel(
                    step: options[_selectedCardIndex].isEqualsMoney ? '5' : '4',
                    title: context.tr('Shipping address'),
                    subtitle: context.tr('Where should we deliver your card?'),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _addressLine1Controller,
                    decoration: InputDecoration(
                      labelText: context.tr('Address line 1'),
                      prefixIcon: const Icon(Icons.home_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter address line 1'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _cityController,
                    decoration: InputDecoration(
                      labelText: context.tr('City'),
                      prefixIcon: const Icon(Icons.location_city_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter city'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _stateController,
                          decoration: InputDecoration(
                            labelText: context.tr('State'),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter state'
                                  : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _countryController,
                          textCapitalization: TextCapitalization.characters,
                          decoration: InputDecoration(
                            labelText: context.tr('Country'),
                          ),
                          validator: (value) =>
                              value == null || value.trim().length != 2
                                  ? 'Use ISO code'
                                  : null,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _postalCodeController,
                    decoration: InputDecoration(
                      labelText: context.tr('Postal code'),
                      prefixIcon: const Icon(Icons.markunread_mailbox_outlined),
                    ),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter postal code'
                        : null,
                  ),
                ],
                const SizedBox(height: 28),
                if (!options[_selectedCardIndex].canOrder) ...[
                  EmptyState(
                    title: context.tr('Card type unavailable'),
                    message: context.tr(
                        'This card type is missing its ordering reference. Select another card type or contact support.'),
                    icon: Icons.credit_card_off_outlined,
                  ),
                  const SizedBox(height: 16),
                ],
                Builder(
                  builder: (context) {
                    final busy = actionState.isLoading;
                    final blocked = busy ||
                        _validatingDiscount ||
                        platformActionState.isLoading ||
                        !options[_selectedCardIndex].canOrder;
                    final label = context.tr('Confirm & order {p0}',
                        {'p0': options[_selectedCardIndex].name});
                    if (!context.isExampleTheme) {
                      return SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: blocked
                              ? null
                              : () => _confirmAndSubmit(
                                    options[_selectedCardIndex],
                                  ),
                          icon: busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: AppProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.lock_outline),
                          label: Text(
                            label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      );
                    }
                    // The one moment of the order flow. The glass CTA holds
                    // its silhouette and position while the request is in
                    // flight instead of swapping to a spinner-shaped button,
                    // and a screen reader hears "…, in progress".
                    return SizedBox(
                      width: double.infinity,
                      child: ExampleGlassButton(
                        label: label,
                        icon: Icons.lock_outline,
                        loading: busy,
                        onPressed: blocked
                            ? null
                            : () => _confirmAndSubmit(
                                  options[_selectedCardIndex],
                                ),
                      ),
                    );
                  },
                ),
              ],
            ];
            if (wide) {
              // Desktop: the live preview and tier stay on the left while the
              // form steps sit in a panel on the right, like the card pages.
              return Form(
                key: _formKey,
                child: SingleChildScrollView(
                  padding: padding,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      // Both columns share one height: the tier panel grows
                      // to meet the bottom edge of the steps panel.
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: heroChildren,
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              flex: 6,
                              child: ExampleGlassPanel(
                                radius: 24,
                                borderAlpha: .22,
                                padding:
                                    const EdgeInsets.fromLTRB(26, 24, 26, 26),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: stepChildren,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Form(
              key: _formKey,
              child: ListView(
                padding: padding,
                children: [
                  ...heroChildren,
                  const SizedBox(height: 22),
                  ...stepChildren,
                ],
              ),
            );
          }

          return tiers.when(
            data: (items) {
              final listTier = _tierWithCardOptions(tier, items);
              return cardTier.when(
                data: (detailTier) {
                  if (_cardOptionsForTier(detailTier).isNotEmpty) {
                    return orderForm(_mergeTierDisplay(listTier, detailTier));
                  }

                  return orderForm(listTier);
                },
                error: (error, stackTrace) => _cardOptionsForTier(listTier)
                        .isEmpty
                    ? ErrorState(
                        error: error,
                        onRetry: () => ref.invalidate(cardTierProvider(tierId)),
                      )
                    : orderForm(listTier),
                loading: () => _cardOptionsForTier(listTier).isEmpty
                    ? LoadingState(label: context.tr('Loading tier cards'))
                    : orderForm(listTier),
              );
            },
            error: (error, stackTrace) => _cardOptionsForTier(tier).isEmpty
                ? ErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(tiersProvider),
                  )
                : orderForm(tier),
            loading: () => _cardOptionsForTier(tier).isEmpty
                ? LoadingState(label: context.tr('Loading tier cards'))
                : orderForm(tier),
          );
        },
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(currentTierProvider),
        ),
        loading: () => LoadingState(label: context.tr('Loading current tier')),
      ),
    );
  }

  double _bottomNavigationClearance(BuildContext context) {
    return MediaQuery.paddingOf(context).bottom + 148;
  }

  Widget _discountField(bool ordering) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('Have a discount code?'),
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('card-discount-code'),
                controller: _discountController,
                enabled: !ordering,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration:
                    InputDecoration(labelText: context.tr('Discount code')),
                onChanged: (_) => setState(() {
                  // Invalidate both the applied code and any older request.
                  _discountRequest++;
                  _validatingDiscount = false;
                  _discount = null;
                  _appliedDiscountCode = null;
                  _discountError = null;
                }),
                onFieldSubmitted: (_) {
                  if (!_validatingDiscount && !ordering) _applyDiscount();
                },
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: ordering ||
                      _validatingDiscount ||
                      _discountController.text.trim().isEmpty
                  ? null
                  : _applyDiscount,
              child:
                  Text(context.tr(_validatingDiscount ? 'Applying…' : 'Apply')),
            ),
          ],
        ),
        if (_discountError != null || _appliedDiscountCode != null) ...[
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              _discountError ?? context.tr('Discount applied!'),
              style: TextStyle(
                  color: _discountError != null
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary),
            ),
          ),
        ],
      ],
    );
    if (context.isExampleTheme) {
      return ExampleGlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: content,
      );
    }
    return NeoSurfaceCard(child: content);
  }

  Future<void> _applyDiscount() async {
    final code = _discountController.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final request = ++_discountRequest;
    setState(() {
      _validatingDiscount = true;
      _discount = null;
      _appliedDiscountCode = null;
      _discountError = null;
    });
    try {
      final result =
          await ref.read(mobileBankingApiProvider).validateCardDiscount(code);
      if (!mounted || request != _discountRequest) return;
      setState(() {
        _discount = result.isValid ? result : null;
        _appliedDiscountCode = result.isValid ? code : null;
        _discountError = result.isValid
            ? null
            : result.errorMessage ?? context.tr('Invalid discount code');
      });
    } catch (error) {
      if (!mounted || request != _discountRequest) return;
      setState(() => _discountError = friendlyErrorMessage(error));
    } finally {
      if (mounted && request == _discountRequest) {
        setState(() => _validatingDiscount = false);
      }
    }
  }

  Future<void> _confirmAndSubmit(_OrderableCardType option) async {
    if (_validatingDiscount) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!option.canOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.tr('Select a card type that is available for ordering.')),
        ),
      );
      return;
    }
    if (option.isEqualsMoney &&
        (_selectedBudgetId == null || _selectedBudgetId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('Select a fiat budget for this card.')),
        ),
      );
      return;
    }

    final config = ref.read(mobileTenantConfigProvider).valueOrNull;
    final appName = AppDesignTheme.nameOf(context);
    final specs = cardOrderAgreementSpecs(
      config,
      appName:
          appName.isNotEmpty ? appName : AppBranding.fromEnvironment().appName,
    );
    final accepted = <LegalAgreementKey>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final intro = Text(
            context.tr('Check every detail before placing the order.'),
            style: Theme.of(dialogContext).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(dialogContext).colorScheme.onSurfaceVariant,
                ),
          );
          final preview = Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: ExampleTiltCard(
                child: NeoBankCard(
                  label: _labelController.text.trim().isEmpty
                      ? context.tr('New card')
                      : _labelController.text.trim(),
                  last4: '••••',
                  network: '',
                  virtual: option.isVirtual,
                  holderName: 'YOUR NAME',
                  skin: NeoCardSkin
                      .all[_selectedSkinIndex % NeoCardSkin.all.length],
                  artworkUrl: option.artworkUrl,
                  artworkAlt: option.artworkAlt,
                  textColorHex: option.textColorHex,
                ),
              ),
            ),
          );
          final summary = NeoSurfaceCard(
            child: Column(
              children: [
                _SummaryRow(label: context.tr('Type'), value: option.name),
                _SummaryRow(
                  label: context.tr('Format'),
                  value: option.isVirtual ? 'Virtual' : 'Physical',
                ),
                _SummaryRow(
                    label: context.tr('Currency'), value: option.currency),
                if (_appliedDiscountCode != null)
                  _SummaryRow(
                      label: context.tr('Discount code'),
                      value: _appliedDiscountCode!),
                if (!option.isVirtual)
                  _SummaryRow(
                    label: context.tr('Ships to'),
                    value: [
                      _addressLine1Controller.text.trim(),
                      _cityController.text.trim(),
                      _countryController.text.trim().toUpperCase(),
                    ].where((part) => part.isNotEmpty).join(', '),
                  ),
              ],
            ),
          );
          final costs = _CostsPanel(
              option: option, tier: _resolvedTier, discount: _discount);
          final agreements = LegalAgreementsSection(
            specs: specs,
            accepted: accepted,
            onChanged: (key, value) => setDialogState(() {
              if (value) {
                accepted.add(key);
              } else {
                accepted.remove(key);
              }
            }),
          );

          return NeoFullScreenDialog(
            title: context.tr('Review cost and agreements'),
            // On wide web the review is two columns in a taller sheet, so
            // every agreement is on screen beside the card and its costs
            // instead of below them, past the fold.
            wideWidth: _reviewWideWidth,
            wideMaxHeight: 960,
            body: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _reviewTwoColumnWidth) {
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      intro,
                      const SizedBox(height: 20),
                      preview,
                      const SizedBox(height: 20),
                      summary,
                      const SizedBox(height: 12),
                      costs,
                      const SizedBox(height: 18),
                      agreements,
                    ],
                  );
                }
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    intro,
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              preview,
                              const SizedBox(height: 20),
                              summary,
                              const SizedBox(height: 12),
                              costs,
                            ],
                          ),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: agreements),
                      ],
                    ),
                  ],
                );
              },
            ),
            primaryLabel: context.tr('Accept & order card'),
            primaryIcon: Icons.lock_outline,
            onPrimary: allLegalAgreementsAccepted(specs, accepted)
                ? () => Navigator.of(dialogContext).pop(true)
                : null,
          );
        },
      ),
    );
    if (confirmed != true || !mounted) return;
    _submit(option, legalAgreementsPayload(specs, accepted, config));
  }

  /// An order the issuer could not charge gets a dialog that leads straight
  /// to the two ways of finding the money: topping up the balance on the
  /// crypto accounts screen, or unloading an existing card. Everything else
  /// stays a plain notice.
  void _showOrderFailure(Object error) {
    final failure =
        describeCardOrderFailure(error, AppLocalizations.of(context));
    if (failure is! CardOrderInsufficientFunds) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure.message)),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Not enough balance')),
        content: Text(failure.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(context.tr('Back')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go(AppRoutes.cards);
            },
            child: Text(context.tr('Unload card')),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.go(AppRoutes.walletBalances);
            },
            child: Text(context.tr('Top up balance')),
          ),
        ],
      ),
    );
  }

  void _submit(
    _OrderableCardType option,
    Map<String, dynamic> legalAgreements,
  ) {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (!option.canOrder) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.tr('Select a card type that is available for ordering.')),
        ),
      );
      return;
    }
    if (option.isEqualsMoney &&
        (_selectedBudgetId == null || _selectedBudgetId!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('Select a fiat budget for this card.')),
        ),
      );
      return;
    }

    ref.read(bankingActionControllerProvider.notifier).orderCard(
          label: _labelController.text.trim(),
          virtual: option.isVirtual,
          currency: option.currency,
          cardTypeId: option.cardTypeId,
          productCode: option.productCode,
          addressLine1:
              option.isVirtual ? null : _addressLine1Controller.text.trim(),
          city: option.isVirtual ? null : _cityController.text.trim(),
          state: option.isVirtual ? null : _stateController.text.trim(),
          country: option.isVirtual
              ? null
              : _countryController.text.trim().toUpperCase(),
          postalCode:
              option.isVirtual ? null : _postalCodeController.text.trim(),
          budgetId: option.isEqualsMoney ? _selectedBudgetId : null,
          discountCode: _appliedDiscountCode,
          legalAgreements: legalAgreements,
        );
  }

  Future<void> _showCreateBudgetDialog(String currency) async {
    final normalizedCurrency = currency.trim().toUpperCase();
    _budgetNameController.text = '$normalizedCurrency Card Budget';
    final selectedCurrencies = <String>{normalizedCurrency};

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => NeoFullScreenDialog(
          title: context.tr('Create budget'),
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                TextField(
                  controller: _budgetNameController,
                  decoration: InputDecoration(
                    labelText: context.tr('Budget name'),
                    helperText: context.tr('{p0} is required for this card.',
                        {'p0': normalizedCurrency}),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Currencies'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _EqualsCurrencyChecklist(
                    selectedCurrencies: selectedCurrencies,
                    lockedCurrency: normalizedCurrency,
                    onChanged: (currency, selected) {
                      setDialogState(() {
                        if (selected) {
                          selectedCurrencies.add(currency);
                        } else if (currency != normalizedCurrency) {
                          selectedCurrencies.remove(currency);
                        }
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          primaryLabel: 'Create budget',
          primaryIcon: Icons.add_rounded,
          onPrimary: selectedCurrencies.isEmpty
              ? null
              : () => Navigator.of(context).pop(true),
        ),
      ),
    );

    final name = _budgetNameController.text.trim();
    if (confirmed != true || name.isEmpty || !mounted) {
      return;
    }

    try {
      final result = await ref.read(mobilePlatformApiProvider).createBudget(
            name: name,
            currencies: _orderedSelectedCurrencies(selectedCurrencies),
          );
      ref.invalidate(budgetsProvider);
      final budgetId = _textValue(result.metadata, const [
        'budgetId',
        'BudgetId',
        'accountId',
        'AccountId',
        'id',
        'Id',
      ]);
      if (budgetId != null) {
        setState(() => _selectedBudgetId = budgetId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result.message)),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    }
  }
}

class _EqualsBudgetSelector extends StatelessWidget {
  const _EqualsBudgetSelector({
    required this.budgets,
    required this.cardCurrency,
    required this.selectedBudgetId,
    required this.isBusy,
    required this.onChanged,
    required this.onCreateBudget,
  });

  final List<PlatformResource> budgets;
  final String cardCurrency;
  final String? selectedBudgetId;
  final bool isBusy;
  final ValueChanged<String?> onChanged;
  final VoidCallback onCreateBudget;

  @override
  Widget build(BuildContext context) {
    final normalizedCurrency = cardCurrency.trim().toUpperCase();
    final compatible = budgets
        .where(
            (budget) => _budgetCurrencies(budget).contains(normalizedCurrency))
        .toList();
    final selectableBudgets = compatible.isEmpty ? budgets : compatible;
    final selected =
        selectableBudgets.any((budget) => _budgetId(budget) == selectedBudgetId)
            ? selectedBudgetId
            : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Assign this card to a budget'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('Fiat cards must be linked to a spending budget.'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (selectableBudgets.isEmpty)
              EmptyState(
                title: context.tr('No budgets available'),
                message: context
                    .tr('Create a budget first, then continue ordering.'),
                icon: Icons.savings_outlined,
              )
            else
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: InputDecoration(labelText: context.tr('Budget')),
                items: [
                  for (final budget in selectableBudgets)
                    DropdownMenuItem(
                      value: _budgetId(budget),
                      child: Text(_budgetTitle(budget)),
                    ),
                ],
                onChanged: isBusy ? null : onChanged,
                validator: (value) =>
                    value == null || value.isEmpty ? 'Select a budget' : null,
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: isBusy ? null : onCreateBudget,
                icon: const Icon(Icons.add),
                label: Text(context.tr('Create budget')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EqualsCurrencyChecklist extends StatelessWidget {
  const _EqualsCurrencyChecklist({
    required this.selectedCurrencies,
    required this.onChanged,
    this.lockedCurrency,
  });

  final Set<String> selectedCurrencies;
  final String? lockedCurrency;
  final void Function(String currency, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    final locked = lockedCurrency?.trim().toUpperCase();

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: equalsSupportedCurrencyCodes.length,
        itemBuilder: (context, index) {
          final currency = equalsSupportedCurrencyCodes[index];
          final selected = selectedCurrencies.contains(currency);
          final lockedSelected = currency == locked;

          return CheckboxListTile(
            dense: true,
            value: selected,
            onChanged: lockedSelected
                ? null
                : (value) => onChanged(currency, value == true),
            title: Text(currency),
            subtitle: lockedSelected ? Text(context.tr('Required')) : null,
            controlAffinity: ListTileControlAffinity.leading,
          );
        },
      ),
    );
  }
}

/// Width of the order review on wide web, and the body width from which it
/// sets the agreements beside the card instead of under it.
const double _reviewWideWidth = 960;
const double _reviewTwoColumnWidth = 820;

class _NoTierSelected extends ConsumerWidget {
  const _NoTierSelected({required this.tiers});

  final AsyncValue<List<PlatformResource>> tiers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EmptyState(
          title: context.tr('Select a tier first'),
          message: context.tr(
              'Choose a subscription tier to unlock eligible card types and limits.'),
          icon: Icons.workspace_premium_outlined,
        ),
        const SizedBox(height: 16),
        Text(context.tr('Available tiers'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        tiers.when(
          data: (items) => items.isEmpty
              ? EmptyState(
                  title: context.tr('No tiers available'),
                  message: context
                      .tr('Tier options will appear here when available.'),
                  icon: Icons.workspace_premium_outlined,
                )
              : Column(
                  children: [
                    for (final tier in items) _TierChoiceCard(tier: tier),
                  ],
                ),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(tiersProvider),
          ),
          loading: () => LoadingState(label: context.tr('Loading tiers')),
        ),
      ],
    );
  }
}

class _TierChoiceCard extends ConsumerWidget {
  const _TierChoiceCard({required this.tier});

  final PlatformResource tier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);

    return Card(
      child: ListTile(
        leading: const Icon(Icons.workspace_premium_outlined),
        title: Text(_tierTitle(tier)),
        subtitle: Text(
          _tierDetails(tier).isEmpty
              ? context.tr('Review this tier before selecting it.')
              : _tierDetails(tier).join(' • '),
        ),
        // The row opens what the plan includes; only the button picks it.
        onTap: () => showTierDetailsSheet(
          context,
          tier: tier,
          onChoose:
              action.isLoading ? null : () => _selectTier(context, ref, tier),
        ),
        trailing: FilledButton(
          onPressed:
              action.isLoading ? null : () => _selectTier(context, ref, tier),
          child: Text(context.tr('Select')),
        ),
      ),
    );
  }
}

class _OrderableCardType {
  const _OrderableCardType({
    required this.name,
    required this.isVirtual,
    required this.currency,
    this.bankProvider = '',
    this.cardTypeId,
    this.productCode,
    this.details = 'Available with current tier',
    this.artworkUrl = '',
    this.artworkAlt = '',
    this.textColorHex = '',
    this.issueFee,
    this.monthlyFee,
    this.yearlyFee,
    this.feeCurrency = 'USD',
    this.tierOverridesMonthly = false,
    this.tierOverridesYearly = false,
    this.replacementFee,
    this.customerPaysProduction = false,
    this.customerPaysShipping = false,
  });

  final String name;
  final bool isVirtual;
  final String currency;
  final String bankProvider;
  final int? cardTypeId;
  final String? productCode;
  final String details;
  final String artworkUrl;
  final String artworkAlt;
  final String textColorHex;

  /// Programme pricing as returned by the issuer; null means not listed.
  final String? issueFee;
  final String? monthlyFee;
  final String? yearlyFee;
  final String feeCurrency;

  /// When set, the tier's monthly price replaces the card's own.
  final bool tierOverridesMonthly;
  final bool tierOverridesYearly;
  final String? replacementFee;
  final bool customerPaysProduction;
  final bool customerPaysShipping;

  bool get canOrder =>
      cardTypeId != null || (productCode != null && productCode!.isNotEmpty);

  bool get isEqualsMoney {
    final normalized = bankProvider.toLowerCase().trim();
    return normalized == 'equalsmoney' || normalized == 'equals money';
  }
}

List<_OrderableCardType> _cardOptionsForTier(PlatformResource tier) {
  final cards = _listFromMetadata(tier.metadata, const [
    'availableCardTypes',
    'AvailableCardTypes',
    'cardTypes',
    'CardTypes',
    'cardBenefits',
    'CardBenefits',
    'cardTiers',
    'CardTiers',
    'cardTypeTiers',
    'CardTypeTiers',
    'cards',
    'Cards',
  ]);

  return cards
      .where((card) => _boolValue(card, const ['isActive', 'active']) != false)
      .map(_cardOptionFromMap)
      .whereType<_OrderableCardType>()
      .toList();
}

PlatformResource _tierWithCardOptions(
  PlatformResource currentTier,
  List<PlatformResource> tiers,
) {
  if (_cardOptionsForTier(currentTier).isNotEmpty) {
    return currentTier;
  }

  final currentTierId = _tierId(currentTier);
  for (final tier in tiers) {
    if (currentTierId != null && _tierId(tier) == currentTierId) {
      return tier;
    }
  }

  final currentTitle = _tierTitle(currentTier).toLowerCase();
  for (final tier in tiers) {
    if (_tierTitle(tier).toLowerCase() == currentTitle) {
      return tier;
    }
  }

  return currentTier;
}

PlatformResource _mergeTierDisplay(
  PlatformResource displayTier,
  PlatformResource cardOptionsTier,
) {
  return PlatformResource(
    id: displayTier.id,
    title: displayTier.title,
    subtitle: displayTier.subtitle,
    metadata: {
      ...displayTier.metadata,
      ...cardOptionsTier.metadata,
      if (displayTier.metadata['tierName'] != null)
        'tierName': displayTier.metadata['tierName'],
      if (displayTier.metadata['TierName'] != null)
        'TierName': displayTier.metadata['TierName'],
      if (displayTier.metadata['name'] != null)
        'name': displayTier.metadata['name'],
      if (displayTier.metadata['Name'] != null)
        'Name': displayTier.metadata['Name'],
      if (displayTier.metadata['tierLevel'] != null)
        'tierLevel': displayTier.metadata['tierLevel'],
      if (displayTier.metadata['TierLevel'] != null)
        'TierLevel': displayTier.metadata['TierLevel'],
      if (displayTier.metadata['level'] != null)
        'level': displayTier.metadata['level'],
      if (displayTier.metadata['Level'] != null)
        'Level': displayTier.metadata['Level'],
    },
  );
}

_OrderableCardType? _cardOptionFromMap(Map<String, dynamic> json) {
  final nestedCardType = _mapValue(json, const ['cardType', 'CardType']);
  final cardType = nestedCardType == null
      ? json
      : {
          ...nestedCardType,
          ...json,
          'name': nestedCardType['name'] ?? nestedCardType['Name'],
          'code': nestedCardType['code'] ?? nestedCardType['Code'],
          'description':
              nestedCardType['description'] ?? nestedCardType['Description'],
          'features': nestedCardType['features'] ?? nestedCardType['Features'],
          'monthlyFee':
              nestedCardType['monthlyFee'] ?? nestedCardType['MonthlyFee'],
          'issuanceFee':
              nestedCardType['issuanceFee'] ?? nestedCardType['IssuanceFee'],
          'replacementFee': nestedCardType['replacementFee'] ??
              nestedCardType['ReplacementFee'],
          'currencyCode':
              nestedCardType['currencyCode'] ?? nestedCardType['CurrencyCode'],
          'isVirtual':
              nestedCardType['isVirtual'] ?? nestedCardType['IsVirtual'],
          'isPhysical':
              nestedCardType['isPhysical'] ?? nestedCardType['IsPhysical'],
        };
  final id = _intValue(json, const ['cardTypeId', 'CardTypeId']) ??
      _intValue(json, const [
        'cardTypeTierId',
        'CardTypeTierId',
      ]) ??
      _intValue(cardType, const ['cardTypeTierId', 'CardTypeTierId']) ??
      _intValue(cardType, const ['cardTypeId', 'CardTypeId', 'id', 'Id']);
  final productCode = _textValue(cardType, const [
    'productCode',
    'ProductCode',
    'code',
    'Code',
    'cardType',
    'CardType',
    'type',
    'Type',
  ]);
  final name = _textValue(cardType, const [
        'name',
        'Name',
        'displayName',
        'DisplayName',
        'cardTypeName',
        'CardTypeName',
        'cardType',
        'CardType',
        'productCode',
        'ProductCode',
      ]) ??
      'Card type';
  final normalized = '$name ${productCode ?? ''}'.toLowerCase();
  final isPhysical =
      _boolValue(cardType, const ['isPhysical', 'physical', 'IsPhysical']) ??
          normalized.contains('physical');
  final isVirtual = !isPhysical;
  final fee = _textValue(cardType, const [
    'monthlyFee',
    'MonthlyFee',
    'monthlySubscriptionFee',
    'MonthlySubscriptionFee',
  ]);
  final yearlyFee = _textValue(cardType, const [
    'yearlyFee',
    'YearlyFee',
    'yearlySubscriptionFee',
    'YearlySubscriptionFee',
  ]);
  final dailyLimit = _textValue(cardType, const [
    'dailyLimit',
    'DailyLimit',
    'dailySpendLimit',
    'DailySpendLimit',
  ]);
  final monthlyLimit = _textValue(cardType, const [
    'monthlyLimit',
    'MonthlyLimit',
    'monthlySpendLimit',
    'MonthlySpendLimit',
  ]);
  final issueFee = _textValue(cardType, const [
    'issueFee',
    'IssueFee',
    'issuanceFee',
    'IssuanceFee',
    'cardFee',
    'CardFee',
    'price',
    'Price',
  ]);
  final tierOverridesMonthly = _boolValue(json, const [
        'tierOverridesCardMonthly',
        'TierOverridesCardMonthly',
      ]) ??
      _boolValue(cardType, const [
        'tierOverridesCardMonthly',
        'TierOverridesCardMonthly',
      ]) ??
      false;
  final customerPaysShipping = _boolValue(cardType, const [
        'customerPaysForShippment',
        'CustomerPaysForShippment',
        'customerPaysForShipment',
        'CustomerPaysForShipment',
      ]) ??
      false;
  final replacementFee = _textValue(cardType, const [
    'replacementFee',
    'ReplacementFee',
  ]);
  final currency = _textValue(cardType, const [
    'currency',
    'Currency',
    'currencyCode',
    'CurrencyCode',
  ]);
  final bankProvider = _bankProvider(cardType);
  final artworkUrl = _normalizeCardArtworkUrl(_textValue(cardType, const [
    'cardImageUrl',
    'CardImageUrl',
    'cardPreviewUrl',
    'CardPreviewUrl',
    'cardThumbnailUrl',
    'CardThumbnailUrl',
    'imageUrl',
    'ImageUrl',
  ]));
  final artworkAlt = _textValue(cardType, const [
        'cardImageAlt',
        'CardImageAlt',
        'imageAlt',
        'ImageAlt',
      ]) ??
      '';
  final textColorHex = _textValue(cardType, const [
        'cardTextColor',
        'CardTextColor',
        'textColor',
        'TextColor',
      ]) ??
      '';
  final description = _textValue(cardType, const [
    'cardDescription',
    'CardDescription',
    'description',
    'Description',
  ]);
  final freeCards = _textValue(json, const [
    'freeCardsIncluded',
    'FreeCardsIncluded',
  ]);
  final maxCards = _textValue(json, const [
    'maxCards',
    'MaxCards',
  ]);
  final features = _displayListValues(cardType, const [
    'cardFeatures',
    'CardFeatures',
    'features',
    'Features',
  ]);

  return _OrderableCardType(
    name: friendlyStatus(name),
    isVirtual: isVirtual,
    currency: currency ?? 'USD',
    bankProvider: bankProvider,
    cardTypeId: id,
    productCode: productCode,
    artworkUrl: artworkUrl,
    artworkAlt: artworkAlt,
    textColorHex: textColorHex,
    issueFee: issueFee,
    monthlyFee: fee,
    yearlyFee: yearlyFee,
    feeCurrency: currency ?? 'USD',
    tierOverridesMonthly: tierOverridesMonthly,
    tierOverridesYearly: _boolValue(cardType, const [
          'tierOverridesCardYearly',
          'TierOverridesCardYearly',
        ]) ??
        false,
    replacementFee: replacementFee,
    customerPaysProduction: _boolValue(cardType, const [
          'customerPaysForProduction',
          'CustomerPaysForProduction',
        ]) ??
        false,
    customerPaysShipping: customerPaysShipping,
    details: [
      isVirtual ? 'Virtual' : 'Physical',
      if (description != null) friendlyStatus(description),
      if (freeCards != null) 'Free cards $freeCards',
      if (maxCards != null) 'Max cards $maxCards',
      if (monthlyLimit != null) 'Monthly limit $monthlyLimit',
      if (dailyLimit != null) 'Daily limit $dailyLimit',
      if (issueFee != null) 'Issue fee ${_moneyText(issueFee, currency)}',
      if (replacementFee != null)
        'Replacement fee ${_moneyText(replacementFee, currency)}',
      if (fee != null) 'Monthly fee ${_moneyText(fee, currency)}',
      if (yearlyFee != null) 'Yearly fee ${_moneyText(yearlyFee, currency)}',
      if (bankProvider == 'equalsmoney') 'Fiat account',
      ...features.map(friendlyStatus),
      if (id == null && (productCode == null || productCode.isEmpty))
        'Ordering reference missing',
    ].join(' • '),
  );
}

String _normalizeCardArtworkUrl(String? value) {
  final normalized = value?.trim() ?? '';
  final markdownLink =
      RegExp(r'^\[[^\]]*\]\((https?://[^)]+)\)$').firstMatch(normalized);
  return markdownLink?.group(1) ?? normalized;
}

List<PlatformResource> _equalsBudgetAccounts(List<PlatformResource> budgets) {
  return budgets.where(_isEqualsBudgetAccount).toList()
    ..sort((left, right) {
      final leftMain = _isEqualsMainBudget(left);
      final rightMain = _isEqualsMainBudget(right);
      if (leftMain != rightMain) {
        return leftMain ? -1 : 1;
      }

      return _budgetTitle(left).compareTo(_budgetTitle(right));
    });
}

List<String> _orderedSelectedCurrencies(Set<String> selectedCurrencies) {
  return [
    for (final currency in equalsSupportedCurrencyCodes)
      if (selectedCurrencies.contains(currency)) currency,
  ];
}

bool _isEqualsBudgetAccount(PlatformResource budget) {
  final provider = _textValue(budget.metadata, const [
    'provider',
    'Provider',
    'bankProvider',
    'BankProvider',
  ])?.toLowerCase();
  final providerType = _textValue(budget.metadata, const [
    'providerType',
    'ProviderType',
    'bankProviderType',
    'BankProviderType',
  ]);
  final isEqualsProvider = provider == 'equalsmoney' ||
      provider == 'equals money' ||
      providerType == '2';
  final accountType = _textValue(budget.metadata, const [
    'accountType',
    'AccountType',
    'type',
    'Type',
  ])?.toLowerCase();

  return isEqualsProvider &&
      (accountType == 'budget' || accountType == 'accountbalance');
}

bool _isEqualsMainBudget(PlatformResource budget) {
  return _budgetTitle(budget).toLowerCase().trim() == 'account balance';
}

String _budgetId(PlatformResource budget) {
  return _textValue(budget.metadata, const [
        'accountId',
        'AccountId',
        'budgetId',
        'BudgetId',
        'id',
        'Id',
      ]) ??
      budget.id;
}

String _budgetTitle(PlatformResource budget) {
  return _textValue(budget.metadata, const [
        'displayName',
        'DisplayName',
        'name',
        'Name',
        'title',
        'Title',
      ]) ??
      budget.title;
}

List<String> _budgetCurrencies(PlatformResource budget) {
  final values = <String>{
    ..._listTextValue(budget.metadata, const [
      'supportedCurrencies',
      'SupportedCurrencies',
      'currencies',
      'Currencies',
    ]),
    for (final bankAccount in _listMapValue(budget.metadata, const [
      'linkedBankAccounts',
      'LinkedBankAccounts',
    ]))
      if (_textValue(bankAccount, const ['currency', 'Currency']) != null)
        _textValue(bankAccount, const ['currency', 'Currency'])!,
  };

  return values
      .map((item) => item.trim().toUpperCase())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _bankProvider(Map<String, dynamic> cardType) {
  final provider = _textValue(cardType, const [
    'bankProvider',
    'BankProvider',
    'provider',
    'Provider',
    'providerName',
    'ProviderName',
  ]);
  if (provider != null) {
    final normalized = provider.toLowerCase().replaceAll(' ', '');
    if (normalized == 'equalsmoney' || normalized == '2') {
      return 'equalsmoney';
    }
    return normalized;
  }

  final providerType = _textValue(cardType, const [
    'bankProviderType',
    'BankProviderType',
    'providerType',
    'ProviderType',
  ]);

  return providerType == '2' ? 'equalsmoney' : '';
}

void _selectTier(BuildContext context, WidgetRef ref, PlatformResource tier) {
  final tierId = _tierId(tier);
  if (tierId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context
            .tr('This tier is missing the identifier needed to select it.')),
      ),
    );
    return;
  }

  ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.selectTier(
          tierId: tierId,
          tierCycle: _tierCycle(tier),
        ),
      );
}

String _tierTitle(PlatformResource tier) {
  final title = _textValue(tier.metadata, const [
    'tierName',
    'TierName',
    'name',
    'Name',
    'displayName',
    'DisplayName',
  ]);
  if (title != null && !_looksTechnicalId(title)) {
    return friendlyStatus(title);
  }

  final fallback = tier.title.trim();
  if (fallback.isNotEmpty && !_looksTechnicalId(fallback)) {
    return friendlyStatus(fallback);
  }

  return 'Tier ${_tierId(tier) ?? ''}'.trim();
}

int? _tierId(PlatformResource tier) {
  final value = _textValue(tier.metadata, const [
        'tierId',
        'TierId',
        'selectedTierId',
        'SelectedTierId',
        'id',
        'Id',
      ]) ??
      (tier.id.trim().isEmpty || tier.id == 'item' ? null : tier.id);

  return value == null ? null : int.tryParse(value);
}

List<String> _tierDetails(PlatformResource tier) {
  final metadata = tier.metadata;
  final values = [
    _textValue(metadata, const ['tierLevel', 'TierLevel', 'level', 'Level']),
    _textValue(metadata, const ['maxCards', 'MaxCards']),
    _textValue(metadata, const ['monthlyLimit', 'MonthlyLimit']),
    _textValue(metadata, const ['dailyLimit', 'DailyLimit']),
  ];
  final labels = ['Level', 'Cards', 'Monthly', 'Daily'];

  return [
    for (var index = 0; index < values.length; index++)
      if (values[index] != null) '${labels[index]} ${values[index]}',
  ];
}

String? _tierCycle(PlatformResource tier) {
  return _textValue(tier.metadata, const [
    'tierCycle',
    'TierCycle',
    'billingCycle',
    'BillingCycle',
    'tierBillingCycle',
    'TierBillingCycle',
    'cycle',
    'Cycle',
  ]);
}

List<Map<String, dynamic>> _listFromMetadata(
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is List) {
      return value.whereType<Map>().map(_stringMap).toList();
    }
  }

  final nestedData = metadata['data'] ?? metadata['Data'];
  if (nestedData is Map) {
    final nestedItems = _listFromMetadata(_stringMap(nestedData), keys);
    if (nestedItems.isNotEmpty) {
      return nestedItems;
    }
  }

  final nestedList = metadata['list'] ?? metadata['List'];
  if (nestedList is List) {
    final listItems = nestedList.whereType<Map>().map(_stringMap).toList();
    if (listItems.isNotEmpty) {
      return listItems;
    }
  }

  final nestedTier = metadata['tier'] ?? metadata['Tier'];
  if (nestedTier is Map) {
    return _listFromMetadata(_stringMap(nestedTier), keys);
  }

  return const [];
}

Map<String, dynamic>? _mapValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is Map) {
      return _stringMap(value);
    }
  }

  return null;
}

Map<String, dynamic> _stringMap(Map value) {
  return value.map((key, item) => MapEntry(key.toString(), item));
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}

int? _intValue(Map<String, dynamic> json, List<String> keys) {
  final value = _textValue(json, keys);
  return value == null ? null : int.tryParse(value);
}

bool? _boolValue(Map<String, dynamic> json, List<String> keys) {
  final value = _textValue(json, keys)?.toLowerCase();
  if (value == 'true') {
    return true;
  }
  if (value == 'false') {
    return false;
  }

  return null;
}

String _moneyText(String amount, String? currency) {
  if (currency == null || currency.trim().isEmpty) {
    return amount;
  }

  return '$amount $currency';
}

List<String> _displayListValues(
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  final values = <String>[];
  for (final key in keys) {
    _appendDisplayValues(values, metadata[key]);
  }

  return values;
}

List<String> _listTextValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }

  return const [];
}

List<Map<String, dynamic>> _listMapValue(
  Map<String, dynamic> json,
  List<String> keys,
) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) =>
              item.map((key, value) => MapEntry(key.toString(), value)))
          .toList();
    }
  }

  return const [];
}

void _appendDisplayValues(List<String> values, Object? value) {
  if (value == null) {
    return;
  }
  if (value is List) {
    for (final item in value) {
      _appendDisplayValues(values, item);
    }
    return;
  }
  if (value is Map) {
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    final text = _textValue(json, const [
      'name',
      'Name',
      'title',
      'Title',
      'label',
      'Label',
      'description',
      'Description',
      'feature',
      'Feature',
    ]);
    if (text != null) {
      values.add(text);
    }
    return;
  }

  values.add(value.toString());
}

bool _looksTechnicalId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }

  return RegExp(r'^[a-z]+_[a-z0-9_]+$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^[0-9a-f]{8}-[0-9a-f-]{27,}$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^\d+$').hasMatch(normalized);
}

// ============================================================================
// New neo-bank ordering UI helpers
// ============================================================================

class _OrderPreviewHero extends StatelessWidget {
  const _OrderPreviewHero({
    required this.label,
    required this.option,
    required this.skin,
  });

  final String label;
  final _OrderableCardType? option;
  final NeoCardSkin skin;

  @override
  Widget build(BuildContext context) {
    // The order screen has exactly one job before the form: show the object.
    // ether.fi stops its page dead with "Your card is ready" at 80 px; we
    // answer with the card itself, in the material, tiltable under a pointer
    // before it is ordered. Bounded to 440 so a 1440 desktop shows a card
    // rather than a billboard.
    final preview = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: AspectRatio(
          aspectRatio: CardFace.aspectRatio,
          child: ExampleTiltCard(
            child: context.isExampleTheme
                ? CardFace(
                    enableHoverTilt: false,
                    card: _previewCard,
                    status: CardStatus.pending,
                    semanticsLabel: 'Preview of $label, '
                        '${option?.isVirtual ?? true ? 'virtual' : 'physical'} '
                        'card',
                  )
                : NeoBankCard(
                    label: label,
                    last4: '••••',
                    network: '',
                    virtual: option?.isVirtual ?? true,
                    skin: skin,
                    holderName: 'YOUR NAME',
                    artworkUrl: option?.artworkUrl,
                    artworkAlt: option?.artworkAlt,
                    textColorHex: option?.textColorHex,
                  ),
          ),
        ),
      ),
    );
    // No ExampleSheenScope here on purpose: the living card owns its arrival
    // pass outright and needs no scope clock, so adding one would only put a
    // second host budget on a route that has exactly one moment.
    return preview;
  }

  /// The card as it will exist, built from what the form knows so far. Zeroed
  /// money because nothing has been issued: the face never prints a balance.
  PaymentCard get _previewCard => PaymentCard(
        id: 'preview',
        label: label,
        last4: '',
        network: '',
        currency: option?.currency ?? 'USD',
        status: CardStatus.pending,
        balance: Money(currency: option?.currency ?? 'USD', minorUnits: 0),
        spendThisMonth:
            Money(currency: option?.currency ?? 'USD', minorUnits: 0),
        limit: Money(currency: option?.currency ?? 'USD', minorUnits: 0),
        virtual: option?.isVirtual ?? true,
        cardImageUrl: option?.artworkUrl ?? '',
        cardImageAlt: option?.artworkAlt ?? '',
        cardTextColor: option?.textColorHex ?? '',
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.step,
    required this.title,
    required this.subtitle,
  });

  final String step;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.primaryContainer,
          ),
          child: Text(
            step,
            style: TextStyle(
              color: colors.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CardTypePickerTile extends StatelessWidget {
  const _CardTypePickerTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _OrderableCardType option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      label:
          '${option.name}, ${option.currency}, ${option.isVirtual ? 'Virtual' : 'Physical'}',
      checked: selected,
      inMutuallyExclusiveGroup: true,
      enabled: option.canOrder,
      onTap: option.canOrder ? onTap : null,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: option.canOrder ? onTap : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 200,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: selected
                ? colors.primaryContainer.withValues(alpha: 0.6)
                : colors.surfaceContainerHigh,
            border: Border.all(
              color: selected ? colors.primary : colors.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (option.artworkUrl.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.network(
                        webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                        option.artworkUrl,
                        width: 42,
                        height: 27,
                        fit: BoxFit.cover,
                        semanticLabel: option.artworkAlt.isEmpty
                            ? context.tr('Card design')
                            : option.artworkAlt,
                        errorBuilder: (_, __, ___) => Icon(
                          option.isVirtual
                              ? Icons.smartphone_rounded
                              : Icons.credit_card,
                          color: selected ? colors.primary : colors.onSurface,
                          size: 22,
                        ),
                      ),
                    )
                  else
                    Icon(
                      option.isVirtual
                          ? Icons.smartphone_rounded
                          : Icons.credit_card,
                      color: selected ? colors.primary : colors.onSurface,
                      size: 22,
                    ),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle, color: colors.primary, size: 20),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                option.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                '${option.currency} • ${option.isVirtual ? 'Virtual' : 'Physical'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
              if (!option.canOrder) ...[
                const SizedBox(height: 6),
                Text(
                  context.tr('Unavailable'),
                  style: TextStyle(
                    color: colors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SkinPicker extends StatelessWidget {
  const _SkinPicker({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: NeoCardSkin.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final skin = NeoCardSkin.all[index];
          final skinColors = skin.colorsFor(context);
          final selected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onSelect(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  colors: skinColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.transparent,
                  width: 3,
                ),
                boxShadow: [
                  if (selected)
                    BoxShadow(
                      color: skinColors.last.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                ],
              ),
              alignment: Alignment.bottomLeft,
              padding: const EdgeInsets.all(8),
              child: Text(
                skin.name,
                style: TextStyle(
                  color: context.brandDesign.color(
                      Theme.of(context).brightness, 'cardForeground',
                      fallback: Colors.white),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Costs the customer commits to by ordering, resolved from the card type
/// and, where the programme says so, the tier's own monthly price.
class _CardCosts {
  const _CardCosts(this.rows);

  factory _CardCosts.from(_OrderableCardType option, PlatformResource? tier,
      [CardDiscount? discount, bool applyTierOverrides = true]) {
    String? tierFee(String period) => tier == null
        ? null
        : _textValue(tier.metadata, [
            '${period}Fee',
            '${period[0].toUpperCase()}${period.substring(1)}Fee',
            '${period}SubscriptionFee',
            '${period[0].toUpperCase()}${period.substring(1)}SubscriptionFee',
            '${period}Price',
            '${period[0].toUpperCase()}${period.substring(1)}Price',
          ]);
    String label(String? value, [String? fee]) {
      if (value == null || value.trim().isEmpty) return 'Not listed';
      final base = double.tryParse(value.replaceAll(',', '.'));
      final amount = base == null || fee == null
          ? base
          : discount?.price(base, fee) ?? base;
      if (amount == 0) return 'Free';
      return _moneyText(
          amount?.toStringAsFixed(2) ?? value, option.feeCurrency);
    }

    return _CardCosts([
      ('Card issue fee', label(option.issueFee, 'buy')),
      (
        'Monthly fee',
        label(
            option.tierOverridesMonthly && applyTierOverrides
                ? tierFee('monthly')
                : option.monthlyFee,
            'monthly')
      ),
      (
        'Yearly fee',
        label(
            option.tierOverridesYearly && applyTierOverrides
                ? tierFee('yearly')
                : option.yearlyFee,
            'yearly')
      ),
      if ((double.tryParse(option.replacementFee ?? '') ?? 0) > 0)
        ('Replacement fee', label(option.replacementFee)),
      if (!option.isVirtual) ...[
        (
          'Production',
          option.customerPaysProduction ? 'Charged by the issuer' : 'Included'
        ),
        (
          'Delivery',
          option.customerPaysShipping ? 'Charged by the issuer' : 'Included'
        ),
      ],
    ]);
  }

  final List<(String, String)> rows;
}

class _CostsPanel extends StatelessWidget {
  const _CostsPanel({required this.option, required this.tier, this.discount});

  final _OrderableCardType option;
  final PlatformResource? tier;
  final CardDiscount? discount;

  @override
  Widget build(BuildContext context) {
    final costs = _CardCosts.from(option, tier, discount);
    final original = Map.fromEntries(
        _CardCosts.from(option, tier, null, discount?.isValid == true)
            .rows
            .map((row) => MapEntry(row.$1, row.$2)));
    const fees = {
      'Card issue fee': 'buy',
      'Monthly fee': 'monthly',
      'Yearly fee': 'yearly'
    };
    String? annotation(String name) {
      final fee = fees[name];
      if (fee == null) return null;
      return discount?.description(fee) ??
          ((fee == 'monthly' && option.tierOverridesMonthly) ||
                  (fee == 'yearly' && option.tierOverridesYearly)
              ? 'Tier override'
              : null);
    }

    final isExample = context.isExampleTheme;
    final rows = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Costs'),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isExample ? ExamplePalette.of(context).ink : null,
          ),
        ),
        const SizedBox(height: 6),
        for (final row in costs.rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Text(
                  row.$1,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: isExample
                        ? ExamplePalette.of(context).textSecondary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (original[row.$1] != row.$2 &&
                          original[row.$1] != 'Not listed')
                        Text(original[row.$1]!,
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                              fontSize: 11,
                            )),
                      Text(
                        row.$2,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color:
                              isExample ? ExamplePalette.of(context).ink : null,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (annotation(row.$1) != null)
                        Text(context.tr(annotation(row.$1)!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Theme.of(context).colorScheme.primary,
                            )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 4),
        Text(
          context.tr(
              'The issue fee is charged when the card is created; the monthly fee is charged from your card balance each month.'),
          style: TextStyle(
            fontSize: 11.5,
            height: 1.4,
            color: isExample
                ? ExamplePalette.of(context).textTertiary
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (!isExample) {
      return NeoSurfaceCard(child: rows);
    }
    return ExampleGlassPanel(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: rows,
    );
  }
}
