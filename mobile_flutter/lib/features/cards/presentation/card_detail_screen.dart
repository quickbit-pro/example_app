import 'card_auto_top_up_sheet.dart';
import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/routes.dart';
import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../brands/example/example_tilt.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../../auth/application/biometric_providers.dart';
import '../../auth/data/biometric_authenticator.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../transactions/domain/transaction_identity.dart';
import '../../wallets/data/wallet_providers.dart';
import '../../wallets/domain/wallet_models.dart';
import '../domain/card_transaction_activity.dart';
import 'add_to_wallet_sheet.dart';
import '../domain/card_top_up_balance.dart';
import 'card_transactions_screen.dart' show cardActivityIsMoneyIn;
import 'widgets/secure_card_frame.dart';
import '../domain/card_control_capabilities.dart';
import 'widgets/card_face.dart';
import 'widgets/card_ledger.dart';
import 'widgets/neo_bank_card.dart';
import 'set_card_pin_sheet.dart';
import 'card_limits_sheet.dart';
import '../domain/card_limits.dart';

class CardDetailScreen extends ConsumerStatefulWidget {
  const CardDetailScreen({
    required this.cardId,
    this.asTab = false,
    super.key,
  });

  final String cardId;

  /// Hosted by the Cards tab: no back arrow, "Cards" title, and the hero
  /// card swipes between the customer's cards.
  final bool asTab;

  @override
  ConsumerState<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends ConsumerState<CardDetailScreen> {
  CardStatus? _localStatus;

  /// The auto-freeze switch as the customer last set it, shown ahead of the
  /// server's answer so the toggle moves under the finger; dropped on failure
  /// and when another card is selected.
  bool? _autoFreezeOverride;
  bool _autoFreezeBusy = false;
  String? _secureCardWidgetUrl;
  bool _secureCardLoading = false;

  /// True from the tap on Manage balance until its dialog has closed. The
  /// dialog only appears once the balances have been re-fetched, and every
  /// tap that landed during that wait used to open a copy of its own behind
  /// the first, so a customer who pressed twice on a slow link had two or
  /// three sheets to close after one top-up.
  bool _balanceDialogOpen = false;
  int _secureRequestId = 0;
  bool _secureRecoveryAttempted = false;
  Future<void>? _refreshInFlight;

  /// Card currently shown; changes when the hero is swiped.
  late String _cardId = widget.cardId;
  PageController? _heroController;

  @override
  void didUpdateWidget(covariant CardDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId == widget.cardId) return;
    _selectCard(widget.cardId);
  }

  @override
  void dispose() {
    _heroController?.dispose();
    super.dispose();
  }

  final _prefetched = <String>{};

  /// Loads detail, controls, limits and activity for the cards either side
  /// of the one in view. Providers are cached per card, so the data is
  /// already there when the customer swipes.
  void _prefetchNeighbours(List<PaymentCard>? cards) {
    if (cards == null) return;
    final open =
        cards.where((item) => item.status != CardStatus.cancelled).toList();
    final index = open.indexWhere((item) => item.id == _cardId);
    if (index < 0) return;
    for (final neighbour in [index - 1, index + 1]) {
      if (neighbour < 0 || neighbour >= open.length) continue;
      final id = open[neighbour].id;
      if (!_prefetched.add(id)) continue;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final future in <Future<Object?>>[
          ref.read(cardDetailProvider(id).future),
          ref.read(cardControlCapabilitiesProvider(id).future),
          ref.read(cardLimitsProvider(id).future),
          ref.read(cardTransactionsProvider(id).future),
        ]) {
          unawaited(future.then<void>((_) {}, onError: (Object _) {}));
        }
      });
    }
  }

  void _selectCard(String cardId) {
    if (cardId == _cardId) return;
    setState(() {
      _cardId = cardId;
      _localStatus = null;
      _autoFreezeOverride = null;
      _autoFreezeBusy = false;
      _secureRequestId++;
      _secureRecoveryAttempted = false;
      _secureCardWidgetUrl = null;
      _secureCardLoading = false;
    });
  }

  void _showSnackBar(BuildContext context, String message) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExample = ref.watch(appConfigProvider).branding.isExample;
    final cardDetail = ref.watch(cardDetailProvider(_cardId));
    final cardList = ref.watch(cardsProvider);
    final cardActivity = ref.watch(cardTransactionsProvider(_cardId));
    final cardControls = ref.watch(cardControlCapabilitiesProvider(_cardId));
    final actionState = ref.watch(bankingActionControllerProvider);
    final platformActionState = ref.watch(platformActionControllerProvider);

    // Only react to loading states triggered by an action; the notifier's
    // first build also passes through loading and must stay silent.
    bool wasRunning(AsyncValue<Object?>? previous) =>
        previous?.isLoading == true && previous?.hasValue == true;
    ref.listen(bankingActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          if (wasRunning(previous)) {
            _showSnackBar(context, 'Card updated');
          }
        },
        error: (error, stackTrace) {
          if (wasRunning(previous)) {
            _showSnackBar(context, friendlyErrorMessage(error));
          }
        },
      );
    });
    ref.listen(platformActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (!wasRunning(previous) || result == null) {
            return;
          }
          _showSnackBar(context, result.message);
        },
        error: (error, stackTrace) {
          if (wasRunning(previous)) {
            _showSnackBar(context, friendlyErrorMessage(error));
          }
        },
      );
    });

    // The list summary keeps paging responsive while full detail refreshes.
    final listed =
        cardList.valueOrNull?.where((item) => item.id == _cardId).firstOrNull;
    final effectiveDetail =
        cardDetail.isLoading && !cardDetail.hasValue && listed != null
            ? AsyncData<PaymentCard>(listed)
            : cardDetail;
    if (widget.asTab) _prefetchNeighbours(cardList.valueOrNull);
    return _SheenLayer(
      enabled: isExample,
      child: effectiveDetail.when(
        data: (card) {
          CardStatus? listedStatus;
          for (final listedCard
              in cardList.valueOrNull ?? const <PaymentCard>[]) {
            if (listedCard.id == _cardId) {
              listedStatus = listedCard.status;
              break;
            }
          }
          final status = _localStatus ?? listedStatus ?? card.status;
          final limitControls = cardControls.valueOrNull;
          final limitsInfo = ref.watch(cardLimitsProvider(_cardId)).valueOrNull;
          final canSetLimits = limitsInfo?.canUpdate == true ||
              limitControls?.canUpdateLimits == true;
          // Two columns need room for the 400pt card column plus details.
          final desktop = isExample && MediaQuery.sizeOf(context).width >= 1180;
          final secureRequest = _secureRequestId;
          final stage = _SecureCardStage(
            card: card,
            status: status,
            isExample: isExample,
            secureUrl: _secureCardWidgetUrl,
            loading: _secureCardLoading,
            onReady: () {
              if (mounted && secureRequest == _secureRequestId) {
                setState(() => _secureCardLoading = false);
              }
            },
            onRefresh: () {
              if (mounted && secureRequest == _secureRequestId) {
                unawaited(_requestSecureCardSession(card));
              }
            },
            onError: (message) {
              if (!mounted || secureRequest != _secureRequestId) return;
              if (!_secureRecoveryAttempted) {
                _secureRecoveryAttempted = true;
                unawaited(_requestSecureCardSession(card, recovery: true));
              } else {
                _hideSecureCardDetails();
                _showSnackBar(context,
                    'Secure card details could not be loaded. Please try revealing them again.');
              }
            },
          );
          // On the Cards tab the hero swipes between open cards; every other
          // section below follows the card in view.
          final swipeCards = widget.asTab && isExample && !desktop
              ? (cardList.valueOrNull ?? const <PaymentCard>[])
                  .where((item) => item.status != CardStatus.cancelled)
                  .toList()
              : const <PaymentCard>[];
          final heroSection = <Widget>[
            if (swipeCards.length > 1)
              _HeroCarousel(
                cards: swipeCards,
                selectedId: _cardId,
                controller: _heroController ??= PageController(
                  initialPage: math.max(
                    0,
                    swipeCards.indexWhere((item) => item.id == _cardId),
                  ),
                ),
                stage: stage,
                revealed: _secureCardWidgetUrl != null && !_secureCardLoading,
                onHideSecure: _hideSecureCardDetails,
                onSelected: (item) => _selectCard(item.id),
              )
            else
              stage,
            if (card.isEqualsMoney) const SafeguardingStatementButton(),
          ];
          // No push provisioning yet: on a phone the card is typed into the
          // Wallet app by hand, so the page says how. Anywhere else the row
          // would be a promise the device cannot keep, so it is absent.
          final wallet = mobileWalletForDevice();
          final Widget? walletTile =
              status == CardStatus.active && wallet != null
                  ? _ControlTile(
                      enabled: true,
                      icon: Icons.wallet_rounded,
                      title: context.tr(wallet.rowTitle),
                      subtitle: context.tr(wallet.rowSubtitle),
                      exampleSubtitle: context.tr(wallet.rowSubtitleShort),
                      onTap: () => showAddToWalletSheet(
                        context,
                        wallet: wallet,
                        card: card,
                        onShowCardDetails: _secureCardWidgetUrl != null
                            ? null
                            : () => _showSecureCardDetails(context, ref, card),
                      ),
                    )
                  : null;
          final actionSection = <Widget>[
            SizedBox(height: isExample ? AppSpacing.md : 16),
            _ActionGrid(
              isExample: isExample,
              isBusy: actionState.isLoading ||
                  platformActionState.isLoading ||
                  _secureCardLoading ||
                  _balanceDialogOpen,
              frozen: status == CardStatus.frozen,
              secureVisible:
                  _secureCardWidgetUrl != null && !_secureCardLoading,
              onTopUp: () => _openBalanceDialog(context, ref, card),
              onToggleFreeze: () => _toggleFreeze(context, ref, card, status),
              onTransactions: () =>
                  context.go('/cards/${card.id}/transactions'),
              onSecureDetails: () => _secureCardWidgetUrl != null
                  ? _hideSecureCardDetails()
                  : _showSecureCardDetails(context, ref, card),
              canUpdateLimits: canSetLimits,
              onLimits: canSetLimits
                  ? () => showCardLimitsSheet(context, ref, card: card)
                  : null,
            ),
          ];
          // The same row again, straight under the controls: a customer who
          // wants to pay with the phone should not have to scroll to Card
          // controls to find out how. It still lives there too.
          final walletSection = <Widget>[
            if (walletTile != null) ...[
              SizedBox(height: isExample ? AppSpacing.md : 16),
              if (isExample)
                ExampleListGroup(children: [walletTile])
              else
                walletTile,
              const WalletBalanceNote(),
            ],
          ];
          final moneyBusy = actionState.isLoading ||
              platformActionState.isLoading ||
              _balanceDialogOpen;
          final canMoveMoney = status != CardStatus.frozen && !moneyBusy;
          final balanceSection = <Widget>[
            if (isExample) ...[
              const SizedBox(height: AppSpacing.md),
              _CardBalanceBlock(card: card),
              const SizedBox(height: AppSpacing.md),
              // The one decisive action on the page. Everything else here is
              // a control, a fact or a list row, so the glass stays rare
              // enough to mean something.
              ExampleGlassButton(
                label: context.tr('Manage balance'),
                icon: Icons.add_rounded,
                loading: moneyBusy,
                onPressed: canMoveMoney
                    ? () => _openBalanceDialog(context, ref, card)
                    : null,
                semanticsLabel: status == CardStatus.frozen
                    ? context.tr(
                        'Manage balance, unavailable while this card is frozen')
                    : null,
              ),
              if (status == CardStatus.frozen) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  context.tr('Unfreeze this card to move money.'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ExampleInk.secondary(context),
                      ),
                ),
              ],
            ],
          ];
          // The card's own facts. Desktop used to be the only place these
          // rendered, which left a phone with no way to read the card's
          // number, type or currency at all.
          List<Widget> detailsSection({bool leading = false}) => isExample
              ? [
                  if (!leading) const SizedBox(height: AppSpacing.lg),
                  _ExampleCardDetailsPanel(
                    card: card,
                    status: status,
                    controls: limitControls,
                    limits: limitsInfo,
                  ),
                ]
              : [
                  if (card.discountCode.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    NeoSurfaceCard(
                        child: ListTile(
                      leading: const Icon(Icons.local_offer_outlined),
                      title: Text(context.tr('Discount code')),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card.discountCode),
                          Text(context.tr('Applied when ordering this card')),
                        ],
                      ),
                    )),
                  ],
                ];
          // A titled run of rows. Example puts them on one surface with hairline
          // dividers; every other brand keeps the stack of NeoSurfaceCards it
          // renders today.
          List<Widget> section(String title, List<Widget> tiles) => isExample
              ? [
                  const SizedBox(height: AppSpacing.lg),
                  ExampleSectionTitle(title: title),
                  const SizedBox(height: AppSpacing.xs),
                  ExampleListGroup(children: tiles),
                ]
              : [
                  const SizedBox(height: 16),
                  _SectionTitle(title),
                  const SizedBox(height: 8),
                  ...tiles,
                ];
          final activitySection = <Widget>[
            SizedBox(height: isExample ? AppSpacing.lg : 16),
            if (isExample)
              ExampleSectionTitle(
                title: context.tr('Recent transactions'),
                action: context.tr('View all'),
                onAction: () => context.go('/cards/${card.id}/transactions'),
              )
            else
              const _SectionTitle('Recent card activity'),
            SizedBox(height: isExample ? AppSpacing.xs : 8),
            cardActivity.when(
              data: (items) {
                // The same grouping as the full card ledger: a fee rides on
                // the purchase it charged instead of taking its own row.
                final grouped = {
                  for (final row in groupCardFees([
                    for (final resource in items)
                      LedgerTransaction.fromJson(
                          {...resource.metadata, 'id': resource.id}),
                  ]))
                    row.id: row
                };
                final activity = [
                  for (final resource in items)
                    if (grouped[resource.id] case final ledger?)
                      (
                        item: CardTransactionActivity.fromResource(resource),
                        timeLabel: _cardPreviewTime(resource),
                        ledger: ledger,
                      ),
                ].take(isExample ? 4 : 3).toList();
                if (items.isEmpty) {
                  return const _EmptyActivityPanel();
                }
                final identity = transactionCardIdentityLabel(card.id, [card]);
                void open(CardTransactionActivity item) => context.go(
                      '/transactions/${Uri.encodeComponent(item.reference)}'
                      '?cardId=${Uri.encodeComponent(_cardId)}',
                    );
                if (isExample) {
                  return ExampleListGroup(
                    children: [
                      for (final item in activity)
                        _ExampleActivityRow(
                          item: item.item,
                          timeLabel: item.timeLabel,
                          ledger: item.ledger,
                          identityLabel: identity,
                          onTap: () => open(item.item),
                        ),
                    ],
                  );
                }
                return NeoGroupedCard(
                  children: [
                    for (final item in activity)
                      _ActivityTile(
                        item: item.item,
                        timeLabel: item.timeLabel,
                        ledger: item.ledger,
                        identityLabel: identity,
                        onTap: () => open(item.item),
                      ),
                  ],
                );
              },
              error: (error, stackTrace) => isExample
                  ? ExampleErrorState(
                      compact: true,
                      title: context.tr('Activity did not load'),
                      error: error,
                      onRetry: () =>
                          ref.invalidate(cardTransactionsProvider(_cardId)),
                    )
                  : ErrorState(
                      error: error,
                      onRetry: () =>
                          ref.invalidate(cardTransactionsProvider(_cardId)),
                    ),
              loading: () => isExample
                  ? const _ActivitySkeleton()
                  : LoadingState(label: context.tr('Loading card activity')),
            ),
          ];
          // Both of these opened the identical dialog and produced the
          // identical result, which is a false choice rather than two
          // controls. On Example the load direction is now the glass CTA above
          // the section, so only the other direction is left here.
          final autoReloadTiles = <Widget>[
            if (isExample &&
                !card.isEqualsMoney &&
                card.currency.toUpperCase() == 'USD')
              _ControlTile(
                enabled: !moneyBusy,
                icon: Icons.autorenew_rounded,
                title: context.tr('Auto-Reload'),
                subtitle: context.tr('Manage automatic card top-ups'),
                onTap: () => showCardAutoTopUp(context, card),
              ),
          ];
          final autoReloadSection = autoReloadTiles.isEmpty
              ? const <Widget>[]
              : section('Automatic funding', autoReloadTiles);
          final movementTiles = <Widget>[
            if (isExample)
              _ControlTile(
                enabled: !moneyBusy,
                icon: Icons.north_east_rounded,
                title: context.tr('Move money off card'),
                subtitle: context.tr('Back to your account'),
                onTap: () => _openBalanceDialog(
                  context,
                  ref,
                  card,
                  action: _CardBalanceAction.unload,
                ),
              )
            else ...[
              _ControlTile(
                enabled: !actionState.isLoading && !_balanceDialogOpen,
                icon: Icons.add_card_outlined,
                title: context.tr('Load card'),
                subtitle: context.tr('Move money onto this card'),
                onTap: () => _openBalanceDialog(context, ref, card),
              ),
              _ControlTile(
                enabled: !platformActionState.isLoading && !_balanceDialogOpen,
                icon: Icons.remove_circle_outline,
                title: context.tr('Unload card'),
                subtitle: context.tr('Move money back to balance'),
                onTap: () => _openBalanceDialog(context, ref, card),
              ),
            ],
          ];
          final movementSection = status == CardStatus.frozen
              ? const <Widget>[]
              : section('Money movement', movementTiles);
          final controlTiles = <Widget>[
            if (!card.virtual) ...[
              _ControlTile(
                enabled: !platformActionState.isLoading,
                icon: Icons.verified_outlined,
                title: context.tr('Activate card'),
                subtitle: context.tr('Complete activation after delivery'),
                exampleSubtitle: 'After it arrives',
                onTap: () => _runConfirmedPlatformAction(
                  context,
                  ref,
                  title: context.tr('Activate card?'),
                  message: context.tr(
                      'Activate only after the cardholder has received and verified this card.'),
                  confirmLabel: context.tr('Activate'),
                  action: (api) => api.activateCard(card.id),
                ),
              ),
            ],
            if (card.canSetPin)
              _ControlTile(
                enabled: !platformActionState.isLoading,
                icon: Icons.pin_outlined,
                title: context.tr('Set PIN'),
                subtitle: context.tr('Choose a 6-digit PIN for this card'),
                onTap: () => _setPin(context, ref, card),
              ),
            _ControlTile(
              enabled: !platformActionState.isLoading,
              icon: Icons.visibility_outlined,
              title: _secureCardWidgetUrl == null
                  ? context.tr('Show secure card data')
                  : context.tr('Hide secure card data'),
              subtitle:
                  context.tr('View card number, expiry date and security code'),
              exampleSubtitle: 'Number, expiry and CVV',
              onTap: () => _secureCardWidgetUrl != null
                  ? _hideSecureCardDetails()
                  : _showSecureCardDetails(context, ref, card),
            ),
            if (walletTile != null) walletTile,
            if (canSetLimits)
              _ControlTile(
                enabled: !platformActionState.isLoading,
                icon: Icons.tune_rounded,
                title: context.tr('Spending limits'),
                subtitle: _limitsSummary(limitsInfo),
                onTap: () => showCardLimitsSheet(context, ref, card: card),
              ),
            // Its own row, not a line inside Spending limits: the switch is
            // the whole setting, so it sits where the eye can find it. The
            // issuer does the freezing (ten minutes after an unfreeze); this
            // only forwards on/off. It does not wait for the capabilities
            // call either: a failed lookup leaves it reading "off" until the
            // issuer answers.
            _ControlTile(
              enabled: !_autoFreezeBusy,
              icon: Icons.shield_outlined,
              title: context.tr('Auto freeze'),
              subtitle: context
                  .tr('Freeze this card automatically again after 10 minutes'),
              exampleSubtitle: context.tr('Freezes again after 10 minutes'),
              onTap: null,
              trailing: _ControlSwitch(
                value: _autoFreezeOverride ??
                    cardControls.valueOrNull?.autoFreezeEnabled ??
                    false,
                semanticsLabel: context.tr('Auto freeze'),
                onChanged: _autoFreezeBusy
                    ? null
                    : (value) => _setAutoFreeze(ref, card, value),
              ),
            ),
            ...cardControls.maybeWhen(
              data: (controls) => [
                if (controls.canMerchantLock)
                  _ControlTile(
                    enabled: true,
                    icon: Icons.storefront_outlined,
                    title: controls.isMerchantLocked
                        ? context.tr('Merchant locked')
                        : context.tr('Merchant lock available'),
                    subtitle: controls.isMerchantLocked
                        ? (controls.lockedMerchantName.isEmpty
                            ? context.tr(
                                'This card is restricted to its assigned merchant.')
                            : context.tr('Restricted to {p0}.',
                                {'p0': controls.lockedMerchantName}))
                        : context.tr(
                            'Available for this card product; assignment is managed by the card issuer.'),
                    exampleSubtitle: controls.isMerchantLocked
                        ? (controls.lockedMerchantName.isEmpty
                            ? 'Locked to one merchant'
                            : 'Locked to ${controls.lockedMerchantName}')
                        : 'Managed by the issuer',
                    onTap: null,
                  ),
                if (controls.canControlOnlinePayments ||
                    controls.canControlContactless ||
                    controls.canControlAtm ||
                    controls.canControlInternational)
                  _ControlTile(
                    enabled: true,
                    icon: Icons.admin_panel_settings_outlined,
                    title: context.tr('Advanced controls'),
                    subtitle: _advancedControlSummary(controls),
                    exampleSubtitle: _advancedControlSummaryShort(controls),
                    onTap: null,
                  ),
              ],
              orElse: () => const <Widget>[],
            ),
            _ControlTile(
              enabled: !platformActionState.isLoading,
              icon: Icons.cancel_outlined,
              title: context.tr('Cancel card'),
              subtitle: context.tr('Permanently close this card'),
              destructive: true,
              onTap: () => _runConfirmedPlatformAction(
                context,
                ref,
                title: context.tr('Cancel card?'),
                message: context.tr(
                    'This permanently closes the card and cannot be undone.'),
                confirmLabel: context.tr('Cancel card'),
                action: (api) => api.cancelCard(card.id),
                destructive: true,
              ),
            ),
          ];
          final controlSection = section('Card controls', controlTiles);
          return Scaffold(
            appBar: AppBar(
              centerTitle: isExample && !desktop,
              automaticallyImplyLeading: !widget.asTab,
              leading: isExample && !desktop && !widget.asTab
                  ? IconButton(
                      tooltip: context.tr('Back'),
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(AppRoutes.cards),
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          size: 19),
                    )
                  : null,
              title: Text(widget.asTab
                  ? context.tr('Cards')
                  : isExample
                      ? context.tr('My Card')
                      : context.tr('Card controls')),
              actions: [
                RefreshAction(onRefresh: () => _refreshCard(card)),
                if (widget.asTab)
                  TextButton(
                    onPressed: () => context.go(AppRoutes.orderCard),
                    child: Text(context.tr('Order card')),
                  ),
                if (isExample && !desktop) ...[
                  IconButton(
                    tooltip: context.tr('Settings'),
                    onPressed: () => context.go(AppRoutes.profile),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const SizedBox(width: 6),
                ],
              ],
            ),
            body: ExampleBackdrop(
              child: RefreshIndicator(
                onRefresh: () => _refreshCard(card),
                child: desktop
                    ? ListView(
                        padding: const EdgeInsets.fromLTRB(40, 28, 40, 40),
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 400,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...heroSection,
                                    ...actionSection,
                                    ...walletSection,
                                    ...balanceSection,
                                    ...autoReloadSection,
                                    ...movementSection,
                                  ],
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    ...detailsSection(leading: true),
                                    ...activitySection,
                                    ...controlSection,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : ListView(
                        padding: EdgeInsets.fromLTRB(
                          isExample ? 20 : 16,
                          isExample ? 6 : 12,
                          isExample ? 20 : 16,
                          isExample ? 28 : 110,
                        ),
                        children: [
                          ...heroSection,
                          ...actionSection,
                          ...walletSection,
                          ...balanceSection,
                          ...activitySection,
                          ...detailsSection(),
                          ...autoReloadSection,
                          ...movementSection,
                          ...controlSection,
                        ],
                      ),
              ),
            ),
          );
        },
        error: (error, stackTrace) => Scaffold(
          appBar: AppBar(
              title:
                  Text(isExample ? context.tr('My Card') : context.tr('Card'))),
          body: isExample
              ? ExampleBackdrop(
                  child: ExampleErrorState(
                    title: context.tr('Card did not load'),
                    error: error,
                    onRetry: () => ref.invalidate(cardDetailProvider(_cardId)),
                    secondaryLabel: 'Back to cards',
                    onSecondary: () => context.go(AppRoutes.cards),
                  ),
                )
              : ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(cardDetailProvider(_cardId)),
                ),
        ),
        loading: () => Scaffold(
          appBar: AppBar(
              title:
                  Text(isExample ? context.tr('My Card') : context.tr('Card'))),
          body: isExample
              ? const ExampleBackdrop(child: _CardDetailSkeleton())
              : LoadingState(label: context.tr('Loading card')),
        ),
      ),
    );
  }

  /// Every route into Manage balance on this screen goes through here so
  /// the second tap of a double tap is swallowed rather than queued.
  Future<void> _openBalanceDialog(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card, {
    _CardBalanceAction action = _CardBalanceAction.load,
  }) async {
    if (_balanceDialogOpen) return;
    setState(() => _balanceDialogOpen = true);
    try {
      await _showTopUpDialog(context, ref, card, action: action);
    } finally {
      if (mounted) setState(() => _balanceDialogOpen = false);
    }
  }

  Future<void> _toggleFreeze(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
    CardStatus status,
  ) async {
    final shouldFreeze = status != CardStatus.frozen;
    final confirmed = await _confirmCardAction(
      context,
      title: shouldFreeze
          ? context.tr('Freeze card?')
          : context.tr('Unfreeze card?'),
      message: shouldFreeze
          ? context.tr('Card payments will be blocked until you unfreeze it.')
          : context.tr('Card payments will be allowed again.'),
      confirmLabel:
          shouldFreeze ? context.tr('Freeze') : context.tr('Unfreeze'),
    );
    if (!confirmed) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    setState(() {
      _localStatus = shouldFreeze ? CardStatus.frozen : CardStatus.active;
    });
    await ref
        .read(bankingActionControllerProvider.notifier)
        .freezeCard(card.id, shouldFreeze);
  }

  Future<void> _setAutoFreeze(
    WidgetRef ref,
    PaymentCard card,
    bool enabled,
  ) async {
    setState(() {
      _autoFreezeOverride = enabled;
      _autoFreezeBusy = true;
    });
    await ref
        .read(platformActionControllerProvider.notifier)
        .run((api) => api.setCardAutoFreeze(card.id, enabled));
    if (!mounted) return;
    final failed = ref.read(platformActionControllerProvider).hasError;
    ref.invalidate(cardControlCapabilitiesProvider(card.id));
    setState(() {
      _autoFreezeBusy = false;
      if (failed) _autoFreezeOverride = null;
    });
  }

  Future<void> _setPin(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
  ) async {
    final pin = await showSetCardPinSheet(context, card);
    if (pin == null || !context.mounted) return;
    ref
        .read(platformActionControllerProvider.notifier)
        .run((api) => api.setCardPin(card.id, pin));
  }

  Future<void> _runConfirmedPlatformAction(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String message,
    required String confirmLabel,
    required Future<ActionResult> Function(dynamic api) action,
    bool destructive = false,
  }) async {
    final confirmed = await _confirmCardAction(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
    );
    if (!confirmed) {
      return;
    }

    await ref.read(platformActionControllerProvider.notifier).run(action);
  }

  Future<void> _showSecureCardDetails(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
  ) async {
    if (kIsWeb) {
      // Browsers only prompt when the user enrolled a passkey from Settings;
      // the issuer widget is a single-use session that renders in the card.
      BiometricEnrollment? enrollment;
      try {
        enrollment = await ref.read(biometricEnrollmentProvider.future);
      } catch (_) {
        enrollment = null;
      }
      if (!context.mounted || card.id != _cardId) return;
      if (enrollment != null && enrollment.enabled && enrollment.hasToken) {
        final gate =
            await ref.read(biometricAuthenticatorProvider).authenticate(
                  reason: 'Confirm your identity to reveal secure card details',
                );
        if (!context.mounted || card.id != _cardId) return;
        if (gate != BiometricAuthResult.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text(context.tr('Identity confirmation was not completed.')),
            ),
          );
          return;
        }
      }
      await _requestSecureCardSession(card);
      return;
    }
    final capability =
        await ref.read(biometricAuthenticatorProvider).capability();
    if (!context.mounted || card.id != _cardId) return;
    if (!capability.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
                'Set up Face ID or fingerprint on this device to reveal card details.'),
          ),
        ),
      );
      return;
    }

    final biometricResult =
        await ref.read(biometricAuthenticatorProvider).authenticate(
              reason: 'Confirm your identity to reveal secure card details',
            );
    if (!context.mounted || card.id != _cardId) return;
    if (biometricResult != BiometricAuthResult.success) {
      final message = biometricResult == BiometricAuthResult.lockedOut
          ? context
              .tr('Biometrics are locked. Unlock your device and try again.')
          : context.tr('Identity confirmation was not completed.');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }

    await _requestSecureCardSession(card);
  }

  void _hideSecureCardDetails() {
    setState(() {
      _secureRequestId++;
      _secureCardWidgetUrl = null;
      _secureCardLoading = false;
    });
  }

  Future<void> _requestSecureCardSession(PaymentCard card,
      {bool recovery = false}) async {
    if (!mounted || card.id != _cardId) return;
    final requestId = ++_secureRequestId;
    if (!recovery) _secureRecoveryAttempted = false;
    setState(() {
      // Session URLs are single-use: discard the old frame before asking
      // Hoppa for a new one. Never reload a previously consumed URL.
      _secureCardWidgetUrl = null;
      _secureCardLoading = true;
    });
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).getCardWidget(card.id);
      if (!mounted || requestId != _secureRequestId || card.id != _cardId) {
        return;
      }
      final rawUrl = _secureWidgetUrl(result.metadata);
      if (rawUrl == null) {
        throw Exception('The secure card widget is temporarily unavailable.');
      }
      setState(() => _secureCardWidgetUrl = _secureWidgetPresentationUrl(
          rawUrl, card,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor));
    } catch (error) {
      if (!mounted || requestId != _secureRequestId) return;
      setState(() => _secureCardLoading = false);
      _showSnackBar(context, friendlyErrorMessage(error));
    }
  }

  Future<void> _refreshCard(PaymentCard card) {
    return _refreshInFlight ??= _performCardRefresh(card).whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<void> _performCardRefresh(PaymentCard card) async {
    final renewSecure = _secureCardWidgetUrl != null || _secureCardLoading;
    final requestId = ++_secureRequestId;
    setState(() {
      _secureCardWidgetUrl = null;
      _secureCardLoading = renewSecure;
    });
    try {
      await Future.wait([
        ref.refresh(cardDetailProvider(card.id).future),
        ref.refresh(cardTransactionsProvider(card.id).future),
        ref.refresh(cardControlCapabilitiesProvider(card.id).future),
      ]);
    } finally {
      if (mounted &&
          requestId == _secureRequestId &&
          card.id == _cardId &&
          renewSecure) {
        await _requestSecureCardSession(card);
      }
    }
  }

  Future<bool> _confirmCardAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(context.tr('Back')),
              ),
              _DialogConfirm(
                label: confirmLabel,
                destructive: destructive,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ) ??
        false;
  }
}

/// A dialog's confirming action.
///
/// `AlertDialog.actions` is an `OverflowBar`, which lays its children out
/// unbounded — so the glass CTA hugs its label instead of expanding, and its
/// height drops to the 44 pt target floor rather than the 54 pt a page CTA
/// stands at. It also holds still: a dialog is already the moving object on
/// screen while it is open.
///
/// Every other brand keeps the `FilledButton` it renders today, including the
/// `colorScheme.error` fill on a destructive confirm.
class _DialogConfirm extends StatelessWidget {
  const _DialogConfirm({
    required this.label,
    required this.onPressed,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleGlassButton(
        label: label,
        onPressed: onPressed,
        tone: destructive
            ? ExampleGlassButtonTone.danger
            : ExampleGlassButtonTone.primary,
        sheen: false,
        expand: false,
        height: 44,
      );
    }
    return FilledButton(
      style: destructive
          ? FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            )
          : null,
      onPressed: onPressed,
      child: Text(label),
    );
  }
}

enum _CardBalanceAction { load, unload }

class _CardTopUpSubmission {
  const _CardTopUpSubmission({required this.amount, required this.action});

  final Money amount;
  final _CardBalanceAction action;
}

class _BudgetTransferSubmission {
  const _BudgetTransferSubmission({
    required this.sourceBudgetId,
    required this.amount,
  });

  final String sourceBudgetId;
  final Money amount;
}

Future<_BudgetTransferSubmission?> _showBudgetTransferDialog(
  BuildContext context, {
  required PlatformResource targetBudget,
  required List<PlatformResource> sourceBudgets,
  required String fallbackCurrency,
}) {
  var sourceBudgetId = _budgetId(sourceBudgets.first);
  var amountText = '';
  var currency =
      _sharedBudgetCurrencies(sourceBudgets.first, targetBudget).firstOrNull ??
          fallbackCurrency;

  return showDialog<_BudgetTransferSubmission>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final selectedSource = sourceBudgets.firstWhere(
          (budget) => _budgetId(budget) == sourceBudgetId,
          orElse: () => sourceBudgets.first,
        );
        final currencies = _sharedBudgetCurrencies(
          selectedSource,
          targetBudget,
        );
        if (currencies.isNotEmpty && !currencies.contains(currency)) {
          currency = currencies.first;
        }
        final amount = _parseMoney(amountText, currency);

        return NeoFullScreenDialog(
          title: context.tr('Top up {p0}', {'p0': _budgetTitle(targetBudget)}),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: sourceBudgetId,
                  decoration:
                      InputDecoration(labelText: context.tr('Source budget')),
                  items: [
                    for (final budget in sourceBudgets)
                      DropdownMenuItem(
                        value: _budgetId(budget),
                        child: Text(_budgetTitle(budget)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => sourceBudgetId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration:
                      InputDecoration(labelText: context.tr('Currency')),
                  items: [
                    for (final option
                        in (currencies.isEmpty ? [currency] : currencies))
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => currency = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  onChanged: (value) {
                    setDialogState(() => amountText = value);
                  },
                  decoration: InputDecoration(labelText: context.tr('Amount')),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
          primaryLabel: 'Transfer',
          primaryIcon: Icons.arrow_forward_rounded,
          onPrimary: amount.minorUnits <= 0
              ? null
              : () => Navigator.of(context).pop(
                    _BudgetTransferSubmission(
                      sourceBudgetId: sourceBudgetId,
                      amount: amount,
                    ),
                  ),
        );
      },
    ),
  );
}

/// Smallest card load the issuer accepts, in minor units (10.00 USD).
const kCardTopUpMinimumMinorUnits = 1000;

class _CardTopUpDialog extends StatefulWidget {
  const _CardTopUpDialog({
    required this.card,
    required this.currency,
    required this.cardBalance,
    required this.interlaceBalances,
    required this.estimateTopUp,
    this.initialAction = _CardBalanceAction.load,
  });

  /// The same card captured by the caller for the eventual load/unload.
  final PaymentCard card;

  /// The segment the dialog opens on.
  final _CardBalanceAction initialAction;

  final String currency;
  final Money cardBalance;
  final List<HoppaWalletAsset> interlaceBalances;
  final Future<QuantumTopUpEstimate> Function(Money amount) estimateTopUp;

  @override
  State<_CardTopUpDialog> createState() => _CardTopUpDialogState();
}

class _CardTopUpDialogState extends State<_CardTopUpDialog> {
  final TextEditingController _controller = TextEditingController();
  late _CardBalanceAction _action;
  int _estimateVersion = 0;
  bool _loadingEstimate = false;
  QuantumTopUpEstimate? _estimate;
  String? _estimateError;

  @override
  void initState() {
    super.initState();
    _action = widget.initialAction;
    _controller.addListener(_scheduleEstimate);
  }

  @override
  void dispose() {
    _estimateVersion++;
    _controller
      ..removeListener(_scheduleEstimate)
      ..dispose();
    super.dispose();
  }

  Money? get _amount {
    final value = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      return null;
    }
    return Money(
      currency: widget.currency,
      minorUnits: (value * 100).round(),
    );
  }

  void _scheduleEstimate() {
    final version = ++_estimateVersion;
    final amount = _amount;
    if (amount == null || _action == _CardBalanceAction.unload) {
      setState(() {
        _loadingEstimate = false;
        _estimate = null;
        _estimateError = null;
      });
      return;
    }

    setState(() {
      _loadingEstimate = true;
      _estimateError = null;
    });

    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!mounted || version != _estimateVersion) {
        return;
      }
      try {
        final estimate = await widget.estimateTopUp(amount);
        if (!mounted || version != _estimateVersion) {
          return;
        }
        setState(() {
          _loadingEstimate = false;
          _estimate = estimate;
          _estimateError = estimate.success
              ? null
              : fallbackText(estimate.message ?? '', 'Failed to get estimate');
        });
      } catch (error) {
        if (!mounted || version != _estimateVersion) {
          return;
        }
        setState(() {
          _loadingEstimate = false;
          _estimate = null;
          _estimateError = friendlyErrorMessage(error);
        });
      }
    });
  }

  void _selectAction(_CardBalanceAction next) {
    if (next == _action) return;
    setState(() {
      _action = next;
      _estimateVersion++;
      _loadingEstimate = false;
      _estimate = null;
      _estimateError = null;
    });
    _scheduleEstimate();
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final amount = _amount;
    final available = _action == _CardBalanceAction.load
        ? cardTopUpAvailable(widget.interlaceBalances)
        : widget.cardBalance.minorUnits / 100;
    final exceedsBalance =
        amount != null && amount.minorUnits / 100 > available;
    // The card issuer only accepts loads of at least 10 USD.
    final belowMinimum = _action == _CardBalanceAction.load &&
        amount != null &&
        amount.minorUnits > 0 &&
        amount.minorUnits < kCardTopUpMinimumMinorUnits;
    return NeoFullScreenDialog(
      title: context.tr('Manage balance'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ManagedCardIdentity(card: widget.card),
            const SizedBox(height: 16),
            if (isExample)
              ExampleSegmentedControl<_CardBalanceAction>(
                height: 44,
                selected: _action,
                onChanged: _selectAction,
                segments: [
                  (value: _CardBalanceAction.load, label: context.tr('Top up')),
                  (
                    value: _CardBalanceAction.unload,
                    label: context.tr('Unload')
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_CardBalanceAction>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: _CardBalanceAction.load,
                      icon: const Icon(Icons.add_card_outlined),
                      label: Text(context.tr('Top up')),
                    ),
                    ButtonSegment(
                      value: _CardBalanceAction.unload,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(context.tr('Unload')),
                    ),
                  ],
                  selected: {_action},
                  onSelectionChanged: (selection) =>
                      _selectAction(selection.first),
                ),
              ),
            const SizedBox(height: 16),
            if (_action == _CardBalanceAction.load)
              _CryptoCardBalancesPanel(balances: widget.interlaceBalances)
            else
              _BalanceSummary(
                label: context.tr('Available on card'),
                value: widget.cardBalance.formatted,
                icon: Icons.credit_card_rounded,
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: context.tr('Amount'),
                prefixIcon: const Icon(Icons.payments_outlined),
                suffixText: widget.currency,
                helperText: _action == _CardBalanceAction.load
                    ? context.tr(
                        'Minimum load is {p0} 10.00', {'p0': widget.currency})
                    : null,
                errorText: exceedsBalance
                    ? _action == _CardBalanceAction.load
                        ? context.tr(
                            'Amount exceeds the combined USD, USDT and USDC balance.')
                        : context
                            .tr('Amount exceeds the available card balance.')
                    : belowMinimum
                        ? context.tr('The minimum load is {p0} 10.00.',
                            {'p0': widget.currency})
                        : null,
              ),
            ),
            const SizedBox(height: 12),
            _BalancePercentageSelector(
              available: available,
              wholeDollarMax: _action == _CardBalanceAction.load,
              onSelected: (value) => _writeAmount(_controller, value),
            ),
            // A dropdown with one option and `onChanged: null` is not a
            // choice, and the currency it names is already the amount
            // field's suffix. Example drops it; every other brand keeps the
            // field it has today.
            if (!isExample) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: 'USD',
                decoration:
                    InputDecoration(labelText: context.tr('Currency/Token')),
                items: const [
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                ],
                onChanged: null,
              ),
            ],
            if (_action == _CardBalanceAction.load && _loadingEstimate) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('Calculating fees...'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isExample ? ExampleInk.secondary(context) : null,
                    ),
              ),
            ],
            if (_action == _CardBalanceAction.load &&
                _estimate != null &&
                _estimate!.success) ...[
              const SizedBox(height: 12),
              _CardTopUpEstimatePanel(
                amount: amount,
                estimate: _estimate!,
              ),
            ],
            if (_action == _CardBalanceAction.load &&
                _estimateError != null) ...[
              const SizedBox(height: 12),
              Text(
                _estimateError!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: isExample
                          ? ExamplePalette.of(context).danger
                          : Theme.of(context).colorScheme.error,
                    ),
              ),
            ],
          ],
        ),
      ),
      primaryLabel:
          _action == _CardBalanceAction.load ? 'Add to card' : 'Unload card',
      primaryIcon: _action == _CardBalanceAction.load
          ? Icons.add_rounded
          : Icons.remove_rounded,
      onPrimary:
          amount == null || available <= 0 || exceedsBalance || belowMinimum
              ? null
              : () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  Navigator.of(context).pop(
                    _CardTopUpSubmission(amount: amount, action: _action),
                  );
                },
    );
  }
}

/// Identifies the card receiving or releasing money, independently of its
/// artwork and the funding wallet. The number always comes from the provider.
class _ManagedCardIdentity extends StatelessWidget {
  const _ManagedCardIdentity({required this.card});

  final PaymentCard card;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last4 = card.last4.trim();
    return Semantics(
      label: context.tr('Manage balance for {p0}, {p1}', {
        'p0': card.displayLabel,
        'p1': cardMetaSemantics(card, context: context)
      }),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            last4.isEmpty
                ? context.tr('Selected card')
                : context.tr('Card ending in {p0}', {'p0': last4}),
            key: const ValueKey('managed-card-last4'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.displayLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: context.isExampleTheme
                  ? ExampleInk.secondary(context)
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancePercentageSelector extends StatelessWidget {
  const _BalancePercentageSelector({
    required this.available,
    required this.onSelected,
    this.wholeDollarMax = false,
  });

  final double available;
  final bool wholeDollarMax;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    const options = <(String, double)>[
      ('25%', .25),
      ('50%', .50),
      ('75%', .75),
      ('MAX', 1),
    ];
    final enabled = available > 0;

    if (context.isExampleTheme) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Quick amount'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              for (var index = 0; index < options.length; index++) ...[
                if (index > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: _QuickAmountChip(
                    label: options[index].$1,
                    enabled: enabled,
                    onTap: () => onSelected(
                      cardBalanceQuickAmount(available, options[index].$2,
                          wholeDollarMax: wholeDollarMax),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Quick amount'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var index = 0; index < options.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: enabled
                      ? () => onSelected(
                            cardBalanceQuickAmount(
                              available,
                              options[index].$2,
                              wholeDollarMax: wholeDollarMax,
                            ),
                          )
                      : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    minimumSize: const Size(0, 42),
                  ),
                  child: Text(options[index].$1),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One of the four quick-amount buttons, in the house's control shape.
///
/// `OutlinedButton`'s 42 pt minimum sits under the 44 pt floor and its edge
/// comes from the Material outline, so Example draws its own: a level-1 pill
/// with a [ExampleBorders.controlSideOf] boundary, which is the token that
/// carries the 3:1 rule for something the user operates.
class _QuickAmountChip extends StatelessWidget {
  const _QuickAmountChip({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ExamplePressable(
      enabled: enabled,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      semanticsLabel: label == 'MAX'
          ? context.tr('Use the whole available balance')
          : context.tr(
              'Set the amount to {p0} of the available balance', {'p0': label}),
      child: Opacity(
        opacity: enabled ? 1 : ExampleOpacity.disabled,
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.fromBorderSide(
              ExampleBorders.controlSideOf(context),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ExampleInk.primary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

void _writeAmount(TextEditingController controller, double value) {
  final text = value.toStringAsFixed(2);
  controller
    ..text = text
    ..selection = TextSelection.collapsed(offset: text.length);
}

class _CryptoCardBalancesPanel extends StatelessWidget {
  const _CryptoCardBalancesPanel({required this.balances});

  final List<HoppaWalletAsset> balances;

  @override
  Widget build(BuildContext context) {
    final visible = [...balances]..sort((left, right) {
        if (left.symbol == 'USD' && right.symbol != 'USD') return -1;
        if (right.symbol == 'USD' && left.symbol != 'USD') return 1;
        return left.symbol.compareTo(right.symbol);
      });

    if (context.isExampleTheme) {
      // A wrap of chips hides the one number that decides whether the
      // transfer can happen. As rows, the symbols stack and the balances
      // right-align into a tabular column you can compare down.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExampleListGroup(
            title: context.tr('Crypto card balances'),
            children: visible.isEmpty
                ? [
                    ExampleRow(
                      title: context.tr('Balances are unavailable'),
                      subtitle: context.tr('Try again in a moment'),
                    ),
                  ]
                : [
                    for (final balance in visible)
                      ExampleRow(
                        leading: CurrencyLogo(
                          symbol: balance.symbol,
                          size: 28,
                          fallbackIcon: balance.symbol == 'USD'
                              ? Icons.account_balance_wallet_outlined
                              : Icons.currency_exchange_rounded,
                        ),
                        title: balance.symbol,
                        subtitle: cardTopUpFundingCurrencies
                                .contains(balance.symbol.toUpperCase())
                            ? context.tr('Available for top-up')
                            : null,
                        trailing: ExampleRowValue(
                          value: balance.amount.toStringAsFixed(2),
                        ),
                      ),
                  ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
                'USD, USDT and USDC count toward your available top-up balance.'),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: ExampleInk.tertiary(context),
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Crypto card balances'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr(
                'USD, USDT and USDC count toward your available top-up balance.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Text(
              context.tr('Balances are temporarily unavailable.'),
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final balance in visible)
                  Chip(
                    avatar: CurrencyLogo(
                      symbol: balance.symbol,
                      size: 20,
                      fallbackIcon: balance.symbol == 'USD'
                          ? Icons.account_balance_wallet_outlined
                          : Icons.currency_exchange_rounded,
                    ),
                    label: Text(
                      '${balance.amount.toStringAsFixed(2)} ${balance.symbol}',
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleListGroup(
        children: [
          ExampleRow(
            leading: ExampleIconTile(
              icon: icon,
              color: ExamplePalette.of(context).accent,
            ),
            title: label,
            trailing: ExampleRowValue(value: value),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CardTopUpEstimatePanel extends StatelessWidget {
  const _CardTopUpEstimatePanel({
    required this.amount,
    required this.estimate,
  });

  final Money? amount;
  final QuantumTopUpEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final fee = estimate.topUpFee;
    final feePercent = estimate.topUpFeePercent;
    final amountMajor = (amount?.minorUnits ?? 0) / 100;
    final amountAdded =
        fee == null ? null : (amountMajor - fee).clamp(0, double.infinity);

    if (context.isExampleTheme) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: ExampleBorders.subtleOf(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PanelLabel('Estimated top-up fees'),
            const SizedBox(height: AppSpacing.xxs),
            if (feePercent != null)
              _TopUpQuoteDetail(
                label: context.tr('Top-up fee'),
                value: '${(feePercent * 100).toStringAsFixed(2)}%',
              ),
            if (fee != null)
              _TopUpQuoteDetail(
                label: context.tr('Fee amount'),
                value: '\$${fee.toStringAsFixed(2)} USD',
              ),
            // The figure the whole panel exists to produce, so it is the
            // one line that is allowed to be loud.
            if (amountAdded != null)
              _TopUpQuoteDetail(
                label: context.tr('Added to card'),
                value: '\$${amountAdded.toStringAsFixed(2)} USD',
                emphasis: true,
              ),
            if (estimate.usdt != null || estimate.usdc != null) ...[
              const SizedBox(height: AppSpacing.md),
              const _PanelLabel('Exchange quotes'),
              const SizedBox(height: AppSpacing.xs),
              if (estimate.usdt != null)
                _TopUpExchangeQuote(asset: 'USDT', quote: estimate.usdt!),
              if (estimate.usdt != null && estimate.usdc != null)
                const SizedBox(height: AppSpacing.xs),
              if (estimate.usdc != null)
                _TopUpExchangeQuote(asset: 'USDC', quote: estimate.usdc!),
            ],
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Estimated top-up fees'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          if (feePercent != null)
            Text(context.tr('Top-up fee: {p0}%',
                {'p0': (feePercent * 100).toStringAsFixed(2)})),
          if (fee != null)
            Text(context
                .tr('Fee amount: \${p0} USD', {'p0': fee.toStringAsFixed(2)})),
          if (amountAdded != null)
            Text(
              context.tr('Amount added to card: \${p0} USD',
                  {'p0': amountAdded.toStringAsFixed(2)}),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          if (estimate.usdt != null || estimate.usdc != null) ...[
            const SizedBox(height: 14),
            Text(
              context.tr('Exchange quotes'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            if (estimate.usdt != null)
              _TopUpExchangeQuote(asset: 'USDT', quote: estimate.usdt!),
            if (estimate.usdt != null && estimate.usdc != null)
              const SizedBox(height: 8),
            if (estimate.usdc != null)
              _TopUpExchangeQuote(asset: 'USDC', quote: estimate.usdc!),
          ],
        ],
      ),
    );
  }
}

class _TopUpExchangeQuote extends StatelessWidget {
  const _TopUpExchangeQuote({required this.asset, required this.quote});

  final String asset;
  final QuantumTopUpQuote quote;

  @override
  Widget build(BuildContext context) {
    final baseCurrency = fallbackText(quote.baseCurrency, 'USD');
    final quoteCurrency = fallbackText(quote.quoteCurrency, asset);
    final receivedCurrency = fallbackText(quote.rfqCurrency, quoteCurrency);
    final feeCurrency = fallbackText(quote.feeCurrency ?? '', quoteCurrency);

    if (context.isExampleTheme) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          // One level above the panel it sits in, which is how the system
          // says "inside", without drawing a card inside a card.
          color: ExampleSurface.of(context, 2),
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CurrencyLogo(symbol: asset, size: 22),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  asset,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            _TopUpQuoteDetail(
              label: context.tr('Exchange rate'),
              value:
                  '1 $baseCurrency = ${_quoteNumber(quote.rate, decimals: 6)} $quoteCurrency',
            ),
            _TopUpQuoteDetail(
              label: context.tr('Estimated amount'),
              value: '${_quoteNumber(quote.rfqAmount)} $receivedCurrency',
            ),
            _TopUpQuoteDetail(
              label: context.tr('Exchange fee'),
              value: '${_quoteNumber(quote.fee)} $feeCurrency',
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CurrencyLogo(symbol: asset, size: 24),
              const SizedBox(width: 8),
              Text(asset, style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 6),
          _TopUpQuoteDetail(
            label: context.tr('Exchange rate'),
            value:
                '1 $baseCurrency = ${_quoteNumber(quote.rate, decimals: 6)} $quoteCurrency',
          ),
          _TopUpQuoteDetail(
            label: context.tr('Estimated amount'),
            value: '${_quoteNumber(quote.rfqAmount)} $receivedCurrency',
          ),
          _TopUpQuoteDetail(
            label: context.tr('Exchange fee'),
            value: '${_quoteNumber(quote.fee)} $feeCurrency',
          ),
        ],
      ),
    );
  }
}

/// A small all-caps-weight label above a run of facts inside a panel.
class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          color: ExampleInk.secondary(context),
        ),
      );
}

class _TopUpQuoteDetail extends StatelessWidget {
  const _TopUpQuoteDetail({
    required this.label,
    required this.value,
    this.emphasis = false,
  });

  final String label;
  final String value;

  /// The conclusion of the arithmetic above it: primary ink, heavier.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xxs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: ExampleInk.secondary(context),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: emphasis ? 13.5 : 12.5,
                  height: 1.35,
                  fontWeight: emphasis ? FontWeight.w700 : FontWeight.w600,
                  color: ExampleInk.primary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
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

String _quoteNumber(double value, {int decimals = 2}) {
  final fixed = value.toStringAsFixed(decimals);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// Desktop "Card details" panel from the D4 artboard: cardholder-facing facts
/// that the API already exposes for a card.
/// The card's own facts, as a titled run of rows.
///
/// This was a two-column grid of 13.5 px facts inside a `ExampleGlassPanel`,
/// and it rendered only above 1180 logical pixels — so the screen you open to
/// read a card's number never showed one on a phone. The grid also gave every
/// fact exactly half the panel and clipped the overflow, which truncated
/// `**** **** **** 4271` at 375 before the text scale was raised at all.
///
/// Rows fix both. The label is the row title, the value sits on the right
/// with a real measure behind [_DetailValue], the masked number is set in
/// Geist Mono like every other account identifier in the app, and the limits
/// are read as money in the card's currency instead of a raw `500.0`.
class _ExampleCardDetailsPanel extends StatelessWidget {
  const _ExampleCardDetailsPanel({
    required this.card,
    required this.status,
    required this.controls,
    this.limits,
  });

  final PaymentCard card;
  final CardStatus status;
  final CardControlCapabilities? controls;
  final CardLimitsInfo? limits;

  @override
  Widget build(BuildContext context) {
    final statusLabel = switch (status) {
      CardStatus.active => 'Active',
      CardStatus.frozen => 'Frozen',
      CardStatus.pending => 'Pending',
      CardStatus.cancelled => 'Closed',
    };
    final network = card.network.trim();
    // One fact per row. `Physical · Mastercard` in a single value ran past
    // the value's measure at a 1.3 text scale and ellipsised the network
    // away, which is the half a cardholder is actually looking for.
    final type = card.virtual ? 'Virtual' : 'Physical';
    final currency = _cardCurrency(card);
    final info = this.limits;
    final limits = info != null && (info.hasCurrent || info.hasCaps)
        ? <String, Object?>{
            for (final period in info.periods)
              if (period.current != null || period.hasCap)
                period.label: period.current == null
                    ? 'Up to ${cardLimitLabel(info.currency, period.cap!)}'
                    : period.hasCap
                        ? '${cardLimitLabel(info.currency, period.current!)} of ${cardLimitLabel(info.currency, period.cap!)}'
                        : cardLimitLabel(info.currency, period.current!),
          }
        : (controls?.limits ?? const <String, dynamic>{});
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Card details')),
        const SizedBox(height: AppSpacing.xs),
        ExampleListGroup(
          dividerInset: AppSpacing.md,
          children: [
            ExampleRow(
              title: context.tr('Status'),
              trailing: _DetailValue(
                context.tr(statusLabel),
                color: exampleStatusInk(context, status),
              ),
              semanticsLabel: context.tr('Status, {p0}', {'p0': statusLabel}),
            ),
            ExampleRow(
              title: context.tr('Number'),
              trailing: card.last4.isEmpty
                  ? const _DetailValue('Not issued yet')
                  : ExcludeSemantics(
                      child: ExampleMono(
                        '•••• ${card.last4}',
                        size: 14,
                        weight: FontWeight.w500,
                      ),
                    ),
              // Screen readers get the four digits spaced so they are read
              // out one at a time rather than as a single number.
              semanticsLabel: card.last4.isEmpty
                  ? context.tr('Card number, not issued yet')
                  : context.tr('Card number, ending {p0}',
                      {'p0': card.last4.split('').join(' ')}),
            ),
            ExampleRow(
              title: context.tr('Type'),
              trailing: _DetailValue(type),
              semanticsLabel: context.tr('Type, {p0}', {'p0': type}),
            ),
            if (card.discountCode.isNotEmpty)
              ExampleRow(
                title: context.tr('Discount code'),
                subtitle: context.tr('Applied when ordering this card'),
                subtitleMaxLines: null,
                trailing: Flexible(
                    child: Text(card.discountCode,
                        textAlign: TextAlign.end,
                        style: Theme.of(context).textTheme.titleSmall)),
                semanticsLabel:
                    '${context.tr('Discount code')}, ${card.discountCode}',
              ),
            if (network.isNotEmpty)
              ExampleRow(
                title: context.tr('Network'),
                trailing: _DetailValue(cardNetworkName(network)),
                semanticsLabel: context
                    .tr('Network, {p0}', {'p0': cardNetworkName(network)}),
              ),
            ExampleRow(
              title: context.tr('Provider'),
              trailing: _DetailValue(card.providerLabel),
              semanticsLabel:
                  context.tr('Provider, {p0}', {'p0': card.providerLabel}),
            ),
            ExampleRow(
              title: context.tr('Currency'),
              trailing: _DetailValue(currency.toUpperCase()),
              semanticsLabel:
                  context.tr('Currency, {p0}', {'p0': currency.toUpperCase()}),
            ),
          ],
        ),
        if (limits.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          ExampleSectionTitle(title: context.tr('Spending limits')),
          const SizedBox(height: AppSpacing.xs),
          ExampleListGroup(
            dividerInset: AppSpacing.md,
            children: [
              for (final entry in limits.entries)
                ExampleRow(
                  title: _limitLabel(entry.key),
                  trailing: _DetailValue(_limitValue(currency, entry.value)),
                  semanticsLabel: '${_limitLabel(entry.key)} limit, '
                      '${_limitValue(currency, entry.value)}',
                ),
            ],
          ),
        ],
      ],
    );
  }

  String _limitLabel(String key) {
    final spaced = key
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAllMapped(
          RegExp(r'([a-z0-9])([A-Z])'),
          (match) => '${match.group(1)} ${match.group(2)}',
        )
        .trim();
    return spaced.isEmpty
        ? 'Limit'
        : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
  }

  /// `500.0` is a debug print, not a limit. Anything numeric is read back as
  /// money in the card's own currency; anything else is passed through, and a
  /// missing limit says so in words rather than in a dash the bundled font
  /// subset may not carry.
  String _limitValue(String currency, Object? raw) {
    if (raw == null) return 'Not set';
    final number =
        raw is num ? raw.toDouble() : double.tryParse(raw.toString().trim());
    if (number == null) {
      final text = raw.toString().trim();
      return text.isEmpty ? 'Not set' : text;
    }
    return Money(
      currency: currency,
      minorUnits: (number * 100).round(),
    ).formatted;
  }
}

/// A fact's value on the right of a [ExampleRow].
///
/// [ExampleRowValue] is the money column: one line, no wrap, no ellipsis, and
/// it takes its intrinsic width out of the row *before* the title column gets
/// any — which is right for `-$174.25` and wrong for a provider name, because
/// a long one pushes the label to zero width and then overflows the row. A
/// fact is not money, so it is capped at a readable measure and ellipsises
/// inside it.
class _DetailValue extends StatelessWidget {
  const _DetailValue(this.value, {this.color});

  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 180),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
        style: (theme.textTheme.titleSmall ??
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
            .copyWith(
          fontWeight: FontWeight.w600,
          color: tint == null
              ? ExampleInk.primary(context)
              : ExampleInk.accent(context, tint),
          height: 1.3,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _CardHero extends StatelessWidget {
  const _CardHero({required this.card, required this.status});

  final PaymentCard card;
  final CardStatus status;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      // The stage hands down a tight box at the ISO ratio; the face takes its
      // height from there so the living card never has to guess.
      return LayoutBuilder(
        builder: (context, constraints) => CardFace(
          showBalance: true,
          enableHoverTilt: false,
          card: card,
          status: status,
          frozen: status == CardStatus.frozen,
          height: constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : CardFace.heightFor(constraints.maxWidth),
        ),
      );
    }
    return NeoBankCard(
      label: fallbackText(card.label, 'Card'),
      last4: card.last4,
      network: card.network,
      virtual: card.virtual,
      status: status,
      balanceText: card.balance.formatted,
      skin: NeoCardSkin.fromSeed(card.id.isEmpty ? card.label : card.id),
      artworkUrl: card.artworkUrl,
      artworkAlt: card.cardImageAlt,
      textColorHex: card.cardTextColor,
    );
  }
}

/// Hero page view for the Cards tab: the selected page shows the live
/// [_SecureCardStage] (so reveal and freeze keep working), the neighbours
/// show their plain faces, and dots underneath mark the position.
class _HeroCarousel extends StatelessWidget {
  const _HeroCarousel({
    required this.cards,
    required this.selectedId,
    required this.controller,
    required this.stage,
    required this.revealed,
    required this.onHideSecure,
    required this.onSelected,
  });

  final List<PaymentCard> cards;
  final String selectedId;
  final PageController controller;
  final Widget stage;

  /// Keep touches inside the issuer frame while its copy controls are visible.
  final bool revealed;
  final VoidCallback onHideSecure;
  final ValueChanged<PaymentCard> onSelected;

  void _changePage(int page) {
    onHideSecure();
    controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final index =
        math.max(0, cards.indexWhere((item) => item.id == selectedId));
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1.586,
          child: PageView.builder(
            controller: controller,
            physics: revealed ? const NeverScrollableScrollPhysics() : null,
            clipBehavior: Clip.none,
            itemCount: cards.length,
            onPageChanged: (page) => onSelected(cards[page]),
            itemBuilder: (context, page) {
              final item = cards[page];
              Widget face = _CardHero(card: item, status: item.status);
              if (item.id == selectedId) {
                // Never cover the secure iframe with a pointer interceptor:
                // copy taps must reach the issuer and keep the session open.
                face = stage;
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: face,
              );
            },
          ),
        ),
        if (revealed)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: context.tr('Previous card'),
                onPressed: index > 0 ? () => _changePage(index - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: context.tr('Next card'),
                onPressed: index < cards.length - 1
                    ? () => _changePage(index + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        const SizedBox(height: 12),
        Semantics(
          label: context
              .tr('Card {p0} of {p1}', {'p0': index + 1, 'p1': cards.length}),
          excludeSemantics: true,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var dot = 0; dot < cards.length; dot++)
                    AnimatedContainer(
                      key: ValueKey('card-page-indicator-${cards[dot].id}'),
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      margin: EdgeInsets.symmetric(
                        horizontal: cards.length > 10 ? 2 : 4,
                      ),
                      width: dot == index ? 22 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: dot == index
                            ? ExamplePalette.of(context).accent
                            : ExampleInk.secondary(context),
                      ),
                    ),
                ],
              ),
              if (cards.length > 5) ...[
                const SizedBox(height: 8),
                Text(
                  context.tr(
                      '{p0} of {p1}', {'p0': index + 1, 'p1': cards.length}),
                  style: TextStyle(
                    fontSize: 12,
                    color: ExampleInk.secondary(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SecureCardStage extends StatelessWidget {
  const _SecureCardStage({
    required this.card,
    required this.status,
    required this.isExample,
    required this.secureUrl,
    required this.loading,
    required this.onReady,
    required this.onError,
    required this.onRefresh,
  });

  final PaymentCard card;
  final CardStatus status;
  final bool isExample;
  final String? secureUrl;
  final bool loading;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final revealed = secureUrl != null && !loading;
    final artworkPalette =
        ExamplePalette.fromDesign(Brightness.dark, context.brandDesign);
    // 700 ms of rotation is exactly the kind of motion a viewer who has asked
    // for reduced motion is asking not to see, and a flip cannot be made
    // "gentler" — it either turns or it does not. Under reduced motion the
    // tween collapses to zero and the secure face is simply there.
    const flip = Duration(milliseconds: 700);
    // ISO card proportions so the issuer's secure face fits without cropping.
    return AspectRatio(
      aspectRatio: isExample ? CardFace.aspectRatio : 8 / 5,
      child: TweenAnimationBuilder<double>(
        duration: isExample ? ExampleMotion.of(context, flip) : flip,
        curve: Curves.easeInOutCubic,
        tween: Tween(end: revealed ? 1 : 0),
        builder: (context, progress, _) {
          // The issuer frame is a platform view: a zero-opacity subtree is
          // not composited on the web, so the page would only start loading
          // once the flip reveals it. Keep it painted (unrotated) beneath an
          // opaque backdrop while it loads, and rotate it in only for the
          // second half of the flip.
          final frontShown = progress <= .5;
          return Stack(
            fit: StackFit.expand,
            // The living card seats itself with a shadow that falls below its
            // own edge, and a Stack clips hard by default — which sliced the
            // daylight ambient off flush with the artwork and put the hero
            // back to floating on paper. The stage is inset by the screen's
            // own padding, so the fall has somewhere to land.
            clipBehavior: Clip.none,
            children: [
              if (secureUrl != null)
                _CardFlipFace(
                  angle: frontShown ? 0 : math.pi * (1 - progress),
                  visible: true,
                  child: _SecureCardInline(
                    key: ValueKey(secureUrl),
                    url: secureUrl!,
                    onReady: onReady,
                    onError: onError,
                    onRefresh: onRefresh,
                  ),
                ),
              if (frontShown) ...[
                if (secureUrl != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: artworkPalette.navigation,
                      borderRadius: const BorderRadius.all(Radius.circular(18)),
                    ),
                  ),
                _CardFlipFace(
                  angle: math.pi * progress,
                  visible: true,
                  child: ExampleTiltCard(
                    enabled: isExample && progress == 0 && !loading,
                    child: _CardHero(card: card, status: status),
                  ),
                ),
              ],
              if (loading)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.all(Radius.circular(AppRadii.md)),
                  child: isExample
                      // The artwork stays night in both themes, so this scrim
                      // and its label are pinned to the Twilight palette
                      // rather than the page's. `LoadingState` follows the
                      // page, which put night ink on a night scrim in
                      // daylight and made the label invisible.
                      ? ColoredBox(
                          color: artworkPalette.paper.withValues(alpha: .72),
                          child: Semantics(
                            liveRegion: true,
                            label: context.tr('Loading secure card details'),
                            child: ExcludeSemantics(
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox.square(
                                      dimension: 22,
                                      child: context.brandDesign.isConfigured
                                          ? AppProgressIndicator(
                                              strokeWidth: 2,
                                              color: artworkPalette.accent,
                                            )
                                          : CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: artworkPalette.accent,
                                            ),
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      context.tr('Loading secure card details'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: artworkPalette.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      : ColoredBox(
                          color: context.brandDesign
                              .color(
                                  Theme.of(context).brightness, 'cardOverlay',
                                  fallback: Colors.black)
                              .withValues(alpha: Colors.black54.a),
                          child: LoadingState(
                            label: context.tr('Loading secure card details'),
                          ),
                        ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CardFlipFace extends StatelessWidget {
  const _CardFlipFace({
    required this.angle,
    required this.visible,
    required this.child,
  });

  final double angle;
  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final transform = Matrix4.identity()
      ..setEntry(3, 2, .001)
      ..rotateY(angle);
    return IgnorePointer(
      ignoring: !visible,
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: Transform(
          alignment: Alignment.center,
          transform: transform,
          child: child,
        ),
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.isBusy,
    required this.frozen,
    required this.secureVisible,
    required this.onTopUp,
    required this.onToggleFreeze,
    required this.onTransactions,
    required this.onSecureDetails,
    required this.isExample,
    required this.canUpdateLimits,
    required this.onLimits,
  });

  final bool isBusy;
  final bool frozen;
  final bool secureVisible;
  final VoidCallback onTopUp;
  final VoidCallback onToggleFreeze;
  final VoidCallback onTransactions;
  final VoidCallback onSecureDetails;
  final bool isExample;
  final bool canUpdateLimits;
  final VoidCallback? onLimits;

  @override
  Widget build(BuildContext context) {
    if (isExample) {
      return Row(
        children: [
          _ExampleControlAction(
            icon: secureVisible
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
            label: secureVisible ? context.tr('Hide') : context.tr('View'),
            onTap: isBusy ? null : onSecureDetails,
          ),
          _ExampleControlAction(
            icon: frozen ? Icons.lock_open_rounded : Icons.ac_unit_rounded,
            label: frozen ? context.tr('Unfreeze') : context.tr('Freeze'),
            onTap: isBusy ? null : onToggleFreeze,
          ),
          // A control that can never fire is not a control: when the card
          // product does not support limits the action is dropped rather than
          // left dimmed forever.
          if (canUpdateLimits)
            _ExampleControlAction(
              icon: Icons.tune_rounded,
              label: context.tr('Limits'),
              onTap: isBusy ? null : onLimits,
            ),
          // Was labelled "More" behind a horizontal-dots glyph, and went
          // straight to the transaction list. It is one destination, so it is
          // named after it.
          _ExampleControlAction(
            icon: Icons.receipt_long_outlined,
            label: context.tr('Activity'),
            onTap: isBusy ? null : onTransactions,
          ),
        ],
      );
    }
    return Row(
      children: [
        NeoQuickAction(
          icon: Icons.account_balance_wallet_outlined,
          label: context.tr('Balance'),
          onTap: isBusy || frozen ? null : onTopUp,
        ),
        const SizedBox(width: AppSpacing.xs),
        NeoQuickAction(
          icon: frozen ? Icons.lock_open_outlined : Icons.lock_outline,
          label: frozen ? context.tr('Unfreeze') : context.tr('Freeze'),
          onTap: isBusy ? null : onToggleFreeze,
        ),
        const SizedBox(width: AppSpacing.xs),
        NeoQuickAction(
          icon: Icons.receipt_long_outlined,
          label: context.tr('Activity'),
          onTap: isBusy ? null : onTransactions,
        ),
        const SizedBox(width: AppSpacing.xs),
        NeoQuickAction(
          icon: secureVisible
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          label: secureVisible ? context.tr('Hide') : context.tr('Details'),
          onTap: isBusy ? null : onSecureDetails,
        ),
      ],
    );
  }
}

/// One circle action under the card face.
///
/// The freeze control swaps between two states, so its glyph and label ride a
/// [ExampleStateSwitch]: 200 ms fade with a 2 pt rise, instant under reduced
/// motion. Nothing here moves on arrival — the card's specular pass owns that
/// beat — and the actions themselves are pressed hundreds of times a month, so
/// they get the 120 ms press and nothing more.
class _ExampleControlAction extends StatelessWidget {
  const _ExampleControlAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final theme = Theme.of(context);
    return Expanded(
      child: ExamplePressable(
        onTap: onTap,
        enabled: enabled,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        semanticsLabel: label,
        child: Opacity(
          opacity: enabled ? 1 : ExampleOpacity.disabled,
          child: ExampleStateSwitch(
            child: KeyedSubtree(
              key: ValueKey<String>(label),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ExampleSurface.of(context, 2),
                      border: ExampleBorders.subtleOf(context),
                    ),
                    child: Icon(
                      icon,
                      color: ExampleInk.primary(context),
                      size: 19,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ExampleInk.secondary(context),
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
}

/// A card transaction as a [ExampleRow]: the list rhythm every Example screen
/// shares, with the amount tabular on the right.
///
/// Two things were wrong rather than plain. The direction came from
/// `CardTransactionActivity.isCredit`, which is inverted, so a groceries
/// purchase arrived green with a `+` and a downward arrow; it now runs through
/// [cardActivityIsMoneyIn], shared with the full ledger so the two screens
/// cannot disagree about which way money moved. And every settled purchase
/// carried a "Completed" caption, which is the normal case on a card and
/// therefore says nothing — only the states that ask something of the holder
/// keep the caption slot now.
class _ExampleActivityRow extends StatelessWidget {
  const _ExampleActivityRow({
    required this.item,
    required this.timeLabel,
    required this.identityLabel,
    required this.onTap,
    this.ledger,
  });

  final CardTransactionActivity item;

  /// The ledger view of this row after fee grouping, when the card feed
  /// carried one; its fees ride on the amount and in the descriptor.
  final LedgerTransaction? ledger;
  final String timeLabel;
  final String? identityLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    // The card's own currency, so this column reconciles with the balance
    // directly above it; the original sits in the descriptor when it differs.
    final fees = ledger?.cardFees ?? const <LedgerTransaction>[];
    final settlement =
        fees.isNotEmpty ? cardListAmount(ledger!) : item.settlementAmount;
    final moneyIn = cardActivityIsMoneyIn(item);
    final title = item.title.trim().isEmpty
        ? (item.subtitle.trim().isEmpty
            ? context.tr('Card activity')
            : item.subtitle)
        : item.title;
    // Keep the original FX amount alongside the date and card identity.
    // Each fact can wrap at narrow widths without squeezing the amount.
    final original = item.transactionAmount;
    final foreign =
        original != null && original.currency != settlement.currency;
    final descriptor = foreign
        ? original.formatted.replaceFirst('-', '')
        : (item.title.trim().isEmpty ? '' : item.subtitle.trim());
    final details = [
      timeLabel,
      if (identityLabel != null) identityLabel!,
      if (descriptor.isNotEmpty) descriptor,
      if (ledger != null)
        if (cardFeeCaption(ledger!) case final caption?) caption,
    ];
    final attention = _exampleAttentionStatus(item.status);
    final tone = _cardActivityStatusTone(item.status);
    final magnitude = settlement.formatted.replaceFirst('-', '');
    final value = settlement.minorUnits == 0
        ? magnitude
        : '${moneyIn ? '+' : '-'}$magnitude';
    return ExampleRow(
      leading: ExampleIconTile(
        icon: moneyIn ? Icons.south_rounded : _activityIconFor(item.category),
        color: moneyIn ? palette.success : palette.accent,
      ),
      title: title,
      subtitle: details.join('\n'),
      subtitleMaxLines: null,
      trailing: ExampleRowValue(
        value: value,
        caption: attention,
        color: moneyIn ? palette.success : null,
        captionColor: attention == null
            ? null
            : (tone == FinanceStatusTone.danger
                ? palette.danger
                : tone == FinanceStatusTone.warning
                    ? palette.warning
                    : null),
      ),
      semanticsLabel: [
        title,
        ...details,
        '${moneyIn ? 'received' : 'spent'} $magnitude',
        if (attention != null) attention,
      ].join(', '),
      onTap: onTap,
    );
  }
}

/// Which statuses earn the caption slot on a Example row.
///
/// A settled purchase is what a card does all day, so it is left unmarked and
/// the row reads as a clean line of money. Anything that is still moving, or
/// that failed, is called out. Returns null when there is nothing to say.
String? _exampleAttentionStatus(String value) {
  final normalised = value.toLowerCase().replaceAll('_', ' ').trim();
  if (normalised.isEmpty) return null;
  const quiet = <String>{
    'complete',
    'completed',
    'closed',
    'settled',
    'booked',
    'approved',
    'posted',
  };
  if (quiet.contains(normalised)) return null;
  // Hoppa's card ledger says "fail" for a declined purchase.
  if (normalised == 'fail') return 'Failed';
  final raw = value.trim();
  return '${raw[0].toUpperCase()}${raw.substring(1)}';
}

/// The card's own balance, and how far its month has run against its limit.
///
/// Replaces the hand-mixed gradient box that carried a 20 px balance: the
/// number is now a [ExampleAmount] at `large`, and the panel is a real surface
/// step with the daylight ambient under it.
///
/// It is deliberately not a button any more. The panel used to be the only
/// way to add money — a whole-panel tap hinted at by a small `+` tile in the
/// corner, which is an affordance you have to already know about. The screen
/// now carries an explicit `ExampleGlassButton` directly beneath it, so this
/// block goes back to doing one job: stating the balance and how far the
/// month has run against the limit.
class _CardBalanceBlock extends StatelessWidget {
  const _CardBalanceBlock({required this.card});

  final PaymentCard card;

  @override
  Widget build(BuildContext context) {
    final balance = card.balance;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        14,
        AppSpacing.md,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('CARD BALANCE'),
                      style: ExampleTextStyles.label(context),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    ExampleAmount(
                      amount: balance.minorUnits / 100,
                      currency: balance.currency,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 1,
            child: ColoredBox(color: ExampleBorders.subtleSideOf(context).color),
          ),
          const SizedBox(height: AppSpacing.sm),
          CardSpendMeter(
            spent: card.spendThisMonth.minorUnits.abs() / 100,
            limit: card.limit.minorUnits / 100,
            currency: card.spendThisMonth.currency,
          ),
        ],
      ),
    );
  }
}

/// The page's loading state: the shape of the card screen, held still.
///
/// A spinner tells you to wait; a skeleton tells you what is coming, and this
/// one is measured off the real page — the artwork at the ISO ratio, the four
/// circle actions, the balance panel with its rule and meter, the CTA at its
/// resting height, then a titled group of rows. Every block is
/// `sheen: false` and the whole column is ONE `ExampleSheen.text` host, so the
/// screen costs one sweep rather than a dozen `saveLayer`s.
class _CardDetailSkeleton extends StatelessWidget {
  const _CardDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('Loading card'),
      liveRegion: true,
      excludeSemantics: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ExampleSheen.text(
            intensity: ExampleSheenIntensity.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => ExampleSkeleton.card(
                    height: CardFace.heightFor(constraints.maxWidth),
                    sheen: false,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      const Expanded(
                        child: Column(
                          children: [
                            ExampleSkeleton.avatar(size: 44, sheen: false),
                            SizedBox(height: AppSpacing.xxs),
                            ExampleSkeleton.line(
                              width: 30,
                              height: 9,
                              sheen: false,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    14,
                    AppSpacing.md,
                    AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: ExampleSurface.of(context, 1),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: ExampleBorders.subtleOf(context),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ExampleSkeleton.line(width: 96, height: 9, sheen: false),
                      SizedBox(height: AppSpacing.xxs),
                      ExampleSkeleton.amount(sheen: false),
                      SizedBox(height: AppSpacing.md),
                      ExampleSkeleton.line(
                        widthFactor: .55,
                        height: 10,
                        sheen: false,
                      ),
                      SizedBox(height: AppSpacing.xs),
                      ExampleSkeleton(height: 6, sheen: false),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                const ExampleSkeleton(
                  height: 54,
                  radius: AppRadii.pill,
                  sheen: false,
                ),
                const SizedBox(height: AppSpacing.lg),
                const ExampleSkeleton.line(width: 132, height: 11, sheen: false),
                const SizedBox(height: AppSpacing.sm),
                const _SkeletonGroup(rows: 3),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The activity section while it loads: four rows the shape of the four that
/// will arrive, under one sheen host.
class _ActivitySkeleton extends StatelessWidget {
  const _ActivitySkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('Loading card activity'),
      liveRegion: true,
      excludeSemantics: true,
      child: const ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: _SkeletonGroup(rows: 4),
      ),
    );
  }
}

/// A `ExampleListGroup`'s silhouette with nothing in it yet.
class _SkeletonGroup extends StatelessWidget {
  const _SkeletonGroup({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows; i++) const ExampleSkeleton.row(),
        ],
      ),
    );
  }
}

/// One sheen clock for the screen, and only for Example.
class _SheenLayer extends StatelessWidget {
  const _SheenLayer({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled || ExampleSheenScope.existsAbove(context)) return child;
    return ExampleSheenScope(child: child);
  }
}

/// White-label card activity row. The Example rendering is [_ExampleActivityRow].
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.item,
    required this.timeLabel,
    this.ledger,
    required this.identityLabel,
    required this.onTap,
  });

  final CardTransactionActivity item;
  final LedgerTransaction? ledger;
  final String timeLabel;
  final String? identityLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = ledger != null && ledger!.cardFees.isNotEmpty
        ? cardListAmount(ledger!)
        : item.displayAmount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FinanceTransactionRow(
          onTap: onTap,
          logoUrl: item.merchantLogoUrl,
          currency: amount.currency,
          fallbackIcon: _activityIconFor(item.category),
          title: item.title,
          subtitle: item.subtitle,
          amount: amount.formatted,
          amountColor: item.isCredit
              ? context.brandDesign.color(
                  Theme.of(context).brightness, 'success',
                  fallback: Colors.green.shade700)
              : null,
          secondaryAmount: item.secondarySettlementAmount?.formatted,
          status: item.status,
          statusTone: _cardActivityStatusTone(item.status),
        ),
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(left: 72, right: 16, bottom: 12),
            child: Text(
              [
                timeLabel,
                if (identityLabel != null) identityLabel!,
                if (ledger != null)
                  if (cardFeeCaption(ledger!) case final caption?) caption,
              ].join('\n'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ),
      ],
    );
  }
}

FinanceStatusTone _cardActivityStatusTone(String value) {
  final status = value.toLowerCase().replaceAll('_', ' ').trim();
  if (const {'complete', 'completed', 'closed', 'settled'}.contains(status)) {
    return FinanceStatusTone.success;
  }
  if (const {'failed', 'fail', 'declined', 'rejected', 'cancelled', 'canceled'}
      .contains(status)) {
    return FinanceStatusTone.danger;
  }
  if (const {'pending', 'processing', 'in progress'}.contains(status)) {
    return FinanceStatusTone.warning;
  }
  return FinanceStatusTone.neutral;
}

class _EmptyActivityPanel extends StatelessWidget {
  const _EmptyActivityPanel();

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleEmptyState(
        compact: true,
        icon: Icons.receipt_long_outlined,
        title: context.tr('No activity yet'),
        body: context.tr('Purchases on this card appear here as they post.'),
      );
    }
    return _Panel(
      child: Row(
        children: [
          const Icon(Icons.receipt_long_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
                context.tr('No card activity has posted for this card yet.')),
          ),
        ],
      ),
    );
  }
}

class _ControlTile extends StatelessWidget {
  const _ControlTile({
    required this.enabled,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
    this.exampleSubtitle,
    this.trailing,
  });

  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;

  /// Replaces the chevron: a switch for a row that is a setting rather than
  /// a door to one.
  final Widget? trailing;

  /// Shorter copy for the Example rendering only.
  ///
  /// A `ListTile` subtitle wraps to as many lines as it needs, so every other
  /// brand can carry a sentence; a [ExampleRow] subtitle is deliberately one
  /// line, and at 375 with a 1.3 text scale it has about 219 pt to say it in.
  /// "View card number, expiry date and security code" does not fit in that,
  /// and an ellipsised explanation explains nothing. Rather than shorten the
  /// copy for every tenant, the row takes a second, tighter phrasing that
  /// only Example reads — white-label pixels are untouched.
  final String? exampleSubtitle;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      final palette = ExamplePalette.of(context);
      // Danger lives on the glyph, never on the row's title: one red mark is
      // a warning, a red line of text is an alarm.
      return ExampleRow(
        leading: ExampleIconTile(
          icon: icon,
          color: destructive ? palette.danger : palette.accent,
        ),
        title: title,
        subtitle: exampleSubtitle ?? subtitle,
        trailing: trailing ?? (onTap == null ? null : ExampleRow.chevron),
        enabled: enabled,
        onTap: onTap,
      );
    }
    final color = destructive ? Theme.of(context).colorScheme.error : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: NeoSurfaceCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          enabled: enabled,
          leading: Icon(icon, color: color),
          title: Text(title, style: TextStyle(color: color)),
          subtitle: Text(subtitle),
          trailing: trailing ??
              (onTap == null ? null : const Icon(Icons.chevron_right)),
          onTap: enabled ? onTap : null,
        ),
      ),
    );
  }
}

/// The switch a [_ControlTile] carries when the row is itself the setting.
///
/// On Example it is the Material switch with zero padding, for the same reason
/// Settings uses that shape: the Cupertino control ignores `SwitchThemeData`
/// and its off state fell below contrast on paper, and the 60 pt Material box
/// would park the track 4 px inboard of the chevrons above and below it.
/// Other brands keep the platform control the rest of their screens use.
class _ControlSwitch extends StatelessWidget {
  const _ControlSwitch({
    required this.value,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final bool value;

  /// The setting's name: the row's text is not part of the switch node, so
  /// without it a screen reader announces an unnamed toggle.
  final String semanticsLabel;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticsLabel,
        child: context.isExampleTheme
            ? Switch(
                value: value,
                padding: EdgeInsets.zero,
                onChanged: onChanged,
              )
            : Switch.adaptive(value: value, onChanged: onChanged),
      );
}

/// The same facts in a row's worth of words.
///
/// The long form is a sentence, which a [ExampleRow] cannot hold on one line;
/// this is the list on its own, in the shortest honest words — "tap" for
/// contactless, "abroad" for international — so all four still fit at 375
/// with a 1.3 text scale.
String _advancedControlSummaryShort(CardControlCapabilities controls) {
  final labels = <String>[
    if (controls.canControlOnlinePayments) 'Online',
    if (controls.canControlContactless) 'tap',
    if (controls.canControlAtm) 'ATM',
    if (controls.canControlInternational) 'abroad',
  ];
  if (labels.isEmpty) return 'Supported by this card';
  return labels.join(', ');
}

String _advancedControlSummary(CardControlCapabilities controls) {
  final labels = <String>[
    if (controls.canControlOnlinePayments) 'online',
    if (controls.canControlContactless) 'contactless',
    if (controls.canControlAtm) 'ATM',
    if (controls.canControlInternational) 'international',
  ];
  return '${labels.join(', ')} controls supported by this card product.';
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NeoSurfaceCard(child: child);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: context.isExampleTheme
                ? Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    )
                : Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ],
    );
  }
}

IconData _activityIconFor(CardTransactionCategory category) {
  return switch (category) {
    CardTransactionCategory.purchase => Icons.shopping_bag_outlined,
    CardTransactionCategory.crypto => Icons.currency_bitcoin,
    CardTransactionCategory.control => Icons.tune,
  };
}

String _cardCurrency(PaymentCard card) {
  if (card.currency.trim().isNotEmpty) {
    return card.currency;
  }
  if (card.limit.currency.trim().isNotEmpty) {
    return card.limit.currency;
  }
  if (card.spendThisMonth.currency.trim().isNotEmpty) {
    return card.spendThisMonth.currency;
  }

  return 'EUR';
}

String? _secureWidgetUrl(Map<String, dynamic> data) {
  for (final key in const [
    'widgetUrl',
    'WidgetUrl',
    'url',
    'Url',
    'iframeUrl',
    'IframeUrl',
  ]) {
    final value = data[key]?.toString().trim();
    if (value != null && value.startsWith(RegExp(r'https?://'))) {
      return value;
    }
  }

  for (final key in const ['data', 'Data', 'result', 'Result']) {
    final nested = data[key];
    if (nested is Map<String, dynamic>) {
      final value = _secureWidgetUrl(nested);
      if (value != null) {
        return value;
      }
    } else if (nested is Map) {
      final normalized =
          nested.map((key, value) => MapEntry(key.toString(), value));
      final value = _secureWidgetUrl(normalized);
      if (value != null) {
        return value;
      }
    }
  }

  return null;
}

String _secureWidgetPresentationUrl(
  String value,
  PaymentCard card, {
  required Color backgroundColor,
}) {
  final uri = Uri.parse(value);
  final parameters = <String, String>{
    ...uri.queryParameters,
    'show-new': 'true',
    'backgroundColor': _hexColor(backgroundColor),
    'cardForm': card.virtual ? 'Virtual' : 'Physical',
    'cardStatus': card.statusLabel,
    'cardCurrency': card.currency,
  };
  if (card.secureArtworkUrl.isNotEmpty) {
    parameters['cardBackground'] = card.secureArtworkUrl;
  }
  if (card.cardTextColor.isNotEmpty) {
    parameters['cardTextColor'] = card.cardTextColor;
  }
  parameters['cardLabel'] =
      card.cardTypeName.isNotEmpty ? card.cardTypeName : card.displayLabel;
  if (card.network.isNotEmpty) parameters['cardNetwork'] = card.network;
  if (kIsWeb) {
    // Lets the widget page post its status back to this app only.
    parameters['parentOrigin'] = Uri.base.origin;
  }
  return uri.replace(queryParameters: parameters).toString();
}

String _hexColor(Color color) {
  final value = color.toARGB32() & 0x00ffffff;
  return '#${value.toRadixString(16).padLeft(6, '0')}';
}

// Some issuer pages render a session error without posting a status message.
// Observe that specific error heading without exporting any card data.
const _secureCardStatusScript = r'''(() => {
  if (window.__cardSecureStatusInstalled) return;
  window.__cardSecureStatusInstalled = true;
  let reported = false;
  const report = () => {
    if (reported) return;
    reported = true;
    CardSecureStatus.postMessage(JSON.stringify({
      type: 'card-secure-widget-status', status: 'error'
    }));
  };
  window.addEventListener('message', (event) => {
    if (event.source !== window || event.origin !== window.location.origin) return;
    if (event.data && event.data.type === 'card-secure-widget-status' &&
        event.data.status === 'error') report();
  });
  const check = () => {
    const nodes = document.createTreeWalker(document.documentElement, NodeFilter.SHOW_TEXT);
    while (nodes.nextNode()) {
      if (nodes.currentNode.textContent.trim() === 'Unable to Load Card Data') {
        report();
        break;
      }
    }
  };
  check();
  new MutationObserver(check).observe(document.documentElement, {
    childList: true, subtree: true, characterData: true
  });
})();''';

class _SecureCardInline extends StatefulWidget {
  const _SecureCardInline({
    required this.url,
    required this.onReady,
    required this.onError,
    required this.onRefresh,
    super.key,
  });

  final String url;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final VoidCallback onRefresh;

  @override
  State<_SecureCardInline> createState() => _SecureCardInlineState();
}

class _SecureCardInlineState extends State<_SecureCardInline> {
  WebViewController? _controller;
  Timer? _readyTimer;
  bool _readyReported = false;
  bool _failed = false;

  bool _pageLoaded = false;

  void _reportError() {
    if (!mounted || _failed) return;
    _failed = true;
    _readyTimer?.cancel();
    widget.onError('Secure card data could not be loaded.');
  }

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..addJavaScriptChannel(
        'CardSecureStatus',
        onMessageReceived: (message) {
          if (!mounted || _failed) return;
          try {
            final payload = jsonDecode(message.message);
            if (payload is Map &&
                payload['type'] == 'card-secure-widget-status' &&
                payload['status'] == 'error') {
              _reportError();
            }
          } on FormatException {
            // Ignore messages outside the widget status protocol.
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_pageLoaded &&
                request.isMainFrame &&
                request.url == widget.url) {
              if (mounted && !_failed) {
                _failed = true;
                _readyTimer?.cancel();
                widget.onRefresh();
              }
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageFinished: (_) {
            _pageLoaded = true;
            if (!mounted || _failed) return;
            // Forward status only; secure card fields stay inside the WebView.
            unawaited(_controller!.runJavaScript(_secureCardStatusScript));
            if (_readyTimer != null || _readyReported) return;
            _readyTimer = Timer(const Duration(seconds: 2), () {
              if (!mounted || _failed) return;
              _readyReported = true;
              widget.onReady();
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true) _reportError();
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The widget page draws the card edge-to-edge on a transparent page;
    // clip to the same radius as the front face so the flip looks seamless.
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: kIsWeb
            // The widget page keeps a small gutter around its card; scale it
            // up a touch so the gutter is cropped by the rounded clip.
            ? Transform.scale(
                scale: 1.045,
                child: SecureCardFrame(
                  url: widget.url,
                  onReady: widget.onReady,
                  onError: widget.onError,
                  onRefresh: widget.onRefresh,
                ),
              )
            : WebViewWidget(controller: _controller!),
      ),
    );
  }
}

PlatformResource? _targetBudgetForCard(
  PaymentCard card,
  List<PlatformResource> budgets,
) {
  final cardBudgetId = card.budgetId.trim();
  if (cardBudgetId.isEmpty) {
    return null;
  }

  for (final budget in budgets) {
    if (_budgetId(budget) == cardBudgetId) {
      return budget;
    }
  }

  return null;
}

List<PlatformResource> _equalsBudgetAccounts(List<PlatformResource> budgets) {
  return budgets.where(_isEqualsBudgetTransferSource).toList()
    ..sort((left, right) {
      final leftMain = _isEqualsMainBudget(left);
      final rightMain = _isEqualsMainBudget(right);
      if (leftMain != rightMain) {
        return leftMain ? -1 : 1;
      }
      return _budgetTitle(left).compareTo(_budgetTitle(right));
    });
}

bool _isEqualsBudgetTransferSource(PlatformResource budget) {
  final provider = _textValue(budget.metadata, const [
    'provider',
    'Provider',
    'bankProvider',
    'BankProvider',
  ])?.toLowerCase().replaceAll(' ', '');
  final providerType = _textValue(budget.metadata, const [
    'providerType',
    'ProviderType',
    'bankProviderType',
    'BankProviderType',
  ]);
  final accountType = _textValue(budget.metadata, const [
    'accountType',
    'AccountType',
    'type',
    'Type',
  ])?.toLowerCase();

  return (provider == 'equalsmoney' || providerType == '2') &&
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

List<String> _sharedBudgetCurrencies(
  PlatformResource left,
  PlatformResource right,
) {
  final leftCurrencies = _budgetCurrencies(left).toSet();
  final rightCurrencies = _budgetCurrencies(right).toSet();
  if (leftCurrencies.isEmpty) {
    return rightCurrencies.toList();
  }
  if (rightCurrencies.isEmpty) {
    return leftCurrencies.toList();
  }

  return leftCurrencies.intersection(rightCurrencies).toList()..sort();
}

Money _parseMoney(String value, String currency) {
  final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
  return Money(currency: currency, minorUnits: (parsed * 100).round());
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return null;
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
          .map(
            (item) => item.map(
              (key, value) => MapEntry(key.toString(), value),
            ),
          )
          .toList();
    }
  }

  return const [];
}

String _limitsSummary(CardLimitsInfo? info) {
  if (info == null) return 'Set daily, weekly and monthly limits';
  final parts = <String>[
    for (final period in info.periods)
      if (period.current != null)
        '${period.label} ${cardLimitLabel(info.currency, period.current!)}',
  ];
  if (parts.isEmpty) {
    return info.hasCaps
        ? 'No limits set · tier ceilings apply'
        : 'Set daily, weekly and monthly limits';
  }
  return parts.join(' · ');
}

/// Use the same API timestamp parser as Activity and receipts. Its compatibility
/// fallback is deliberately not displayed when the response has no date.
String _cardPreviewTime(PlatformResource resource) {
  final transaction = LedgerTransaction.fromJson(resource.metadata);
  return transaction.hasBookedAt
      ? DateFormat('d MMM yyyy · HH:mm').format(transaction.bookedAt.toLocal())
      : 'Date unavailable';
}

/// Opens the existing balance flow directly from Home, with Top up selected.
Future<void> showCardTopUp(
  BuildContext context,
  WidgetRef ref,
  PaymentCard card,
) =>
    _showTopUpDialog(context, ref, card, showFeedback: true);

Future<void> _showTopUpDialog(
  BuildContext context,
  WidgetRef ref,
  PaymentCard card, {
  // Which way the money is meant to go. Both directions land in the same
  // dialog, so the control that opened it has to say which segment it
  // meant; a row labelled "off card" that opens on "Top up" is a lie.
  // White-label keeps the old default on both of its rows, so its dialog
  // opens exactly as it does today.
  _CardBalanceAction action = _CardBalanceAction.load,
  bool showFeedback = false,
}) async {
  if (card.isEqualsMoney) {
    await _showEqualsCardBudgetTopUp(
      context,
      ref,
      card,
      showFeedback: showFeedback,
    );
    return;
  }

  final currency = _cardCurrency(card);
  var interlaceBalances = const <HoppaWalletAsset>[];
  try {
    // Reopening Manage balance must include newly deposited funds.
    ref
      ..invalidate(userAssetsProvider)
      ..invalidate(userWalletsProvider)
      ..invalidate(walletsProvider)
      ..invalidate(hoppaWalletAssetsProvider);
    interlaceBalances = await ref.read(hoppaWalletAssetsProvider.future);
  } catch (_) {
    // The top-up action remains available when balances cannot be refreshed;
    // the provider still validates available funds before execution.
  }
  if (!context.mounted) {
    return;
  }
  final submission = await _showCardTopUpDialog(
    context,
    ref,
    card: card,
    currency: currency,
    cardBalance: card.balance,
    interlaceBalances: interlaceBalances,
    initialAction: action,
  );

  if (submission == null || !context.mounted) {
    return;
  }
  await Future<void>.delayed(const Duration(milliseconds: 120));
  if (!context.mounted) {
    return;
  }

  if (submission.action == _CardBalanceAction.unload) {
    await ref.read(platformActionControllerProvider.notifier).run(
          (api) => api.unloadCard(cardId: card.id, amount: submission.amount),
        );
  } else {
    await ref
        .read(bankingActionControllerProvider.notifier)
        .topUpCard(cardId: card.id, amount: submission.amount, token: 'USD');
  }
  if (!context.mounted) return;
  if (showFeedback) {
    _showHomeBalanceResult(
      context,
      submission.action == _CardBalanceAction.unload
          ? ref.read(platformActionControllerProvider).error
          : ref.read(bankingActionControllerProvider).error,
    );
  }
  ref
    ..invalidate(portfolioEstimateProvider)
    ..invalidate(cardDetailProvider(card.id))
    ..invalidate(cardTransactionsProvider(card.id))
    ..invalidate(cardsProvider)
    ..invalidate(userAssetsProvider)
    ..invalidate(userWalletsProvider)
    ..invalidate(walletsProvider)
    ..invalidate(hoppaWalletAssetsProvider)
    ..invalidate(dashboardProvider);
}

Future<void> _showEqualsCardBudgetTopUp(
  BuildContext context,
  WidgetRef ref,
  PaymentCard card, {
  bool showFeedback = false,
}) async {
  List<PlatformResource> budgets;
  try {
    budgets = _equalsBudgetAccounts(await ref.read(budgetsProvider.future));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    }
    return;
  }

  final accountBalanceOnly =
      budgets.length == 1 && _isEqualsMainBudget(budgets.first);
  if (accountBalanceOnly) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
                'No top-up is needed. Account Balance funds are already accessible by the card.'),
          ),
        ),
      );
    }
    return;
  }

  final targetBudget = _targetBudgetForCard(card, budgets);
  if (targetBudget == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(context.tr('This fiat card is missing its linked budget.')),
        ),
      );
    }
    return;
  }

  final sourceBudgets = budgets
      .where((budget) => _budgetId(budget) != _budgetId(targetBudget))
      .toList();
  if (sourceBudgets.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr(
                'No top-up is needed. This card already uses the only available budget.'),
          ),
        ),
      );
    }
    return;
  }
  if (!context.mounted) {
    return;
  }

  final submission = await _showBudgetTransferDialog(
    context,
    targetBudget: targetBudget,
    sourceBudgets: sourceBudgets,
    fallbackCurrency: _cardCurrency(card),
  );
  if (submission == null || !context.mounted) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.transferBudget(
          fromBudgetId: submission.sourceBudgetId,
          toBudgetId: _budgetId(targetBudget),
          amount: submission.amount,
        ),
      );
  if (!context.mounted) return;
  if (showFeedback) {
    _showHomeBalanceResult(
      context,
      ref.read(platformActionControllerProvider).error,
    );
  }
  ref
    ..invalidate(portfolioEstimateProvider)
    ..invalidate(cardDetailProvider(card.id))
    ..invalidate(cardTransactionsProvider(card.id))
    ..invalidate(cardsProvider)
    ..invalidate(dashboardProvider)
    ..invalidate(budgetsProvider);
}

Future<_CardTopUpSubmission?> _showCardTopUpDialog(
  BuildContext context,
  WidgetRef ref, {
  required PaymentCard card,
  required String currency,
  required Money cardBalance,
  required List<HoppaWalletAsset> interlaceBalances,
  _CardBalanceAction initialAction = _CardBalanceAction.load,
}) {
  return showDialog<_CardTopUpSubmission>(
    context: context,
    builder: (context) => _CardTopUpDialog(
      card: card,
      initialAction: initialAction,
      currency: currency,
      cardBalance: cardBalance,
      interlaceBalances: interlaceBalances,
      estimateTopUp: (amount) => ref
          .read(mobilePlatformApiProvider)
          .getQuantumTopUpEstimate(amount: amount),
    ),
  );
}

// The Home shortcut has no card-screen action listeners to report a result.
void _showHomeBalanceResult(BuildContext context, Object? error) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error == null
            ? context.tr('Card balance updated')
            : friendlyErrorMessage(error),
      ),
    ),
  );
}
