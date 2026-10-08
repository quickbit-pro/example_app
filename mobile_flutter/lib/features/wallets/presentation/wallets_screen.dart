import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/equals_money.dart';
import '../../../core/formatters/transaction_display.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../../shared/widgets/refresh_when_visible.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/platform_widgets.dart';
import '../../banking/application/banking_providers.dart';
import '../../money/presentation/accounts_hub_header.dart';
import '../../money/domain/balance_value_order.dart';
import '../../transactions/application/transaction_identity_provider.dart';
import '../../transactions/domain/transaction_scope.dart';
import '../../transactions/export/transaction_pdf_export_button.dart';
import '../data/wallet_providers.dart';
import '../domain/exchange_models.dart';
import '../domain/wallet_models.dart';
import '../domain/receiving_account_details.dart';
import '../../crypto/crypto.dart';
import 'crypto_withdrawal_dialog.dart';
import 'deposit_address_dialog.dart';
import 'exchange_panel.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

/// Example ink at a Twilight alpha, re-earned on paper.
///
/// Twilight keeps the exact `pearl.withValues(alpha: …)` these screens
/// already rendered. On paper a faded pearl is a grey with nothing left to
/// read, so the alpha snaps to the named daylight inks: night .72 above .56
/// and night .50 below it, the two values the token layer proves at 7.60:1
/// and 3.58:1 on `lightPaper`.
Color _fadedInk(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? (alpha >= .56
            ? ExamplePalette.of(context).textSecondary
            : ExamplePalette.of(context).textTertiary)
        : ExamplePalette.of(context).ink.withValues(alpha: alpha);

/// A lavender hairline at a Twilight alpha; the daylight hairline on paper.
///
/// Lavender .12 to .20 vanishes on white, so every daylight edge resolves to
/// the one `lightBorderSubtle` the vocabulary defines — as quiet on paper as
/// lavender .14 is on night.
Color _hairline(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? ExamplePalette.of(context).borderSubtle
        : ExamplePalette.of(context).borderSubtle.withValues(alpha: alpha);

/// A translucent panel fill: the level-1 surface at [alpha] on night, opaque
/// white on paper, where a translucent panel over the light atmosphere reads
/// as a smudge rather than as a card.
Color _panelFill(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? ExamplePalette.of(context).surface
        : ExamplePalette.of(context).surface.withValues(alpha: alpha);

/// A well sunk into a panel — the ground behind an inline dropdown. Night
/// darkens below the panel; paper cannot go lighter than white, so it steps
/// up to the level-2 lavender tint instead.
Color _wellFill(BuildContext context, double alpha) =>
    ExampleTheme.isLight(context)
        ? ExamplePalette.of(context).surfaceSubtle
        : ExamplePalette.of(context).paper.withValues(alpha: alpha);

/// Loading for a wallet section.
///
/// On Example a group of skeleton rows shaped like the list that is landing, so
/// the page holds its height instead of jumping when the data arrives; on
/// every other tenant the shared spinner, unchanged. [PlatformLoadingGroup]
/// registers one sheen host for the whole column, never one per row.
class _WalletsLoading extends StatelessWidget {
  const _WalletsLoading({required this.label, this.title, this.rows = 4});

  final String label;
  final String? title;
  final int rows;

  @override
  Widget build(BuildContext context) => context.isExampleTheme
      ? PlatformLoadingGroup(title: title, rows: rows, label: label)
      : LoadingState(label: label);
}

const _topUpSourceSymbols = {'USDT', 'USDC'};
const _convertTargetSymbols = ['USDC', 'USDT'];

class WalletsScreen extends ConsumerStatefulWidget {
  const WalletsScreen({
    this.initialView = WalletView.assets,
    this.embedded = false,
    this.initialBudgetId = '',
    this.initialCurrency = '',
    super.key,
  });

  static const routePath = '/wallets';
  static const assetsRoutePath = '/wallets/assets';
  static const addressesRoutePath = '/wallets/addresses';
  static const balancesRoutePath = '/wallets/balances';
  static const exchangeRoutePath = '/wallets/exchange';

  final WalletView initialView;
  final bool embedded;
  final String initialBudgetId;
  final String initialCurrency;

  @override
  ConsumerState<WalletsScreen> createState() => _WalletsScreenState();
}

class _WalletsScreenState extends ConsumerState<WalletsScreen> {
  late WalletView _view = widget.initialView;
  late String _selectedCurrency = widget.initialCurrency.trim().toUpperCase();
  String _openedAccountSelection = '';

  @override
  void didUpdateWidget(covariant WalletsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialView != widget.initialView) {
      _view = widget.initialView;
    }
    if (oldWidget.initialCurrency != widget.initialCurrency ||
        oldWidget.initialBudgetId != widget.initialBudgetId) {
      _selectedCurrency = widget.initialCurrency.trim().toUpperCase();
      _openedAccountSelection = '';
    }
  }

  void _openInitialAccount(
    List<PlatformResource> resources,
    String disclosure,
  ) {
    final requestedId = widget.initialBudgetId.trim();
    if (requestedId.isEmpty && _selectedCurrency.isEmpty) return;
    final selection = '$requestedId:$_selectedCurrency';
    if (_openedAccountSelection == selection) return;
    final equals = _equalsBudgetAccounts(resources);
    final budgets = equals.isEmpty ? resources : equals;
    final matching = budgets.where((budget) {
      final scopeId = _budgetTransactionScopeIds(budget).firstOrNull;
      if (scopeId == null) return false;
      if (requestedId.isNotEmpty && scopeId != requestedId) return false;
      return _selectedCurrency.isEmpty ||
          _budgetCurrencies(budget).contains(_selectedCurrency) ||
          _budgetBalanceRows(budget)
              .any((row) => row.currency == _selectedCurrency);
    }).toList();
    // A currency can belong to several actual accounts. Let the customer
    // choose from the filtered list instead of opening an arbitrary account.
    if (matching.length != 1) return;
    _openedAccountSelection = selection;
    final currency = _selectedCurrency;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _openedAccountSelection != selection) return;
      _showWalletBudgetDetails(
        context,
        budget: matching.single,
        budgets: budgets,
        balanceRows: _budgetBalanceRows(matching.single),
        disclosure: disclosure,
        selectedCurrency: currency,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(hoppaWalletAssetsProvider);
    final addresses = ref.watch(hoppaWalletAddressesProvider);
    final balances = ref.watch(hoppaWalletBalancesProvider);
    final budgets = ref.watch(budgetsProvider);
    final tenantConfig = ref.watch(mobileTenantConfigProvider);
    final bankingDashboard = ref.watch(dashboardProvider);
    final isBusinessAccount =
        bankingDashboard.valueOrNull?.profile.isBusinessAccount ?? false;
    final businessAccountReady =
        bankingDashboard.valueOrNull?.canUseBanking ?? false;
    final exchangeEnabled = isBusinessAccount
        ? businessAccountReady
        : tenantConfig.valueOrNull?.boomFiExchangeEnabled == true;
    final view = isBusinessAccount &&
            (_view == WalletView.assets || _view == WalletView.addresses)
        ? WalletView.balances
        : _view;
    final disclosure = resolveEqualsPaymentServicesDisclosure(
      localeCountryCode:
          WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '',
      defaultRegion:
          tenantConfig.valueOrNull?.equalsRegulatoryRegionDefault ?? 'EU',
      euDisclosure: tenantConfig.valueOrNull?.equalsRegulatoryDisclaimerEu,
      ukDisclosure: tenantConfig.valueOrNull?.equalsRegulatoryDisclaimerUk,
    );
    final isExample = context.isExampleTheme;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = isExample && width >= (kIsWeb ? 600 : 760);

    Future<void> refreshBalances() async {
      ref.invalidate(hoppaWalletAssetsProvider);
      ref.invalidate(hoppaWalletAddressesProvider);
      ref.invalidate(hoppaWalletBalancesProvider);
      ref.invalidate(userAssetsProvider);
      ref.invalidate(userWalletsProvider);
      ref.invalidate(budgetsProvider);
      ref.invalidate(portfolioEstimateProvider);
      ref.invalidate(exchangeOverviewProvider);
      ref.invalidate(exchangeTransfersProvider);
      await Future.wait([
        ref.read(hoppaWalletAssetsProvider.future),
        if (tenantConfig.valueOrNull?.equalsMoneyEnabled ?? true)
          ref.read(budgetsProvider.future),
      ]);
    }

    final body = RefreshIndicator(
      onRefresh: refreshBalances,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          widget.embedded ? 16 : 20,
          16,
          widget.embedded ? 16 : 20,
          widget.embedded ? 16 : 110,
        ),
        children: [
          if (!widget.embedded) ...[
            AccountsHubHeader(
              selected: switch (view) {
                WalletView.assets => AccountsHubSection.crypto,
                WalletView.addresses => AccountsHubSection.deposit,
                WalletView.exchange => AccountsHubSection.exchange,
                WalletView.balances => AccountsHubSection.money,
              },
              showMoney: tenantConfig.valueOrNull?.equalsMoneyEnabled ?? true,
              showCrypto: !isBusinessAccount,
              showExchange: exchangeEnabled,
            ),
            const SizedBox(height: 22),
          ],
          if (!widget.embedded && !isExample && view == WalletView.assets) ...[
            _WalletSectionHeader(
              title: context.tr('Crypto cards'),
              subtitle: context.tr('Crypto card balances and crypto actions.'),
            ),
            const SizedBox(height: 12),
          ] else if (!widget.embedded &&
              !isExample &&
              view == WalletView.exchange) ...[
            _WalletSectionHeader(
              title: context.tr('Exchange'),
              subtitle: context
                  .tr('Convert balances or move money between accounts.'),
            ),
            const SizedBox(height: 12),
          ] else if (!widget.embedded &&
              isExample &&
              view == WalletView.addresses) ...[
            // The route names itself once, here, above the async boundary.
            // It used to name itself twice: this Material heading was the
            // only branch of the four that was not gated on `!isExample`, so
            // Example painted an ungoverned `titleLarge` "Deposit addresses"
            // and then `_AddressList` painted a `ExampleSectionTitle` saying
            // exactly the same words underneath it — and on the balances
            // route the same heading said "Fiat account" over a section
            // called "Accounts & budgets", which is two different names for
            // one screen. Hoisting the Example header out of the data branch
            // also stops it blinking in and out: loading, error, empty and
            // data now all arrive under the same title instead of the page
            // growing a heading when the request lands.
            ExampleSectionTitle(title: context.tr('Deposit addresses')),
            const SizedBox(height: AppSpacing.xxs),
            PlatformLede(
              text: context.tr(
                  'One address per network. Send only the matching asset on the network shown, or the deposit will not arrive.'),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (!widget.embedded &&
              !isExample &&
              (view == WalletView.addresses ||
                  view == WalletView.balances)) ...[
            Text(
              view == WalletView.addresses
                  ? context.tr('Deposit addresses')
                  : context.tr('Fiat account'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
          ],
          if (view == WalletView.exchange)
            if (isBusinessAccount)
              budgets.when(
                data: (items) => _EqualsMoneyExchangeEntry(
                  budgets: items,
                ),
                error: (error, stackTrace) => PlatformErrorState(
                  error: error,
                  compact: false,
                  onRetry: () => ref.invalidate(budgetsProvider),
                ),
                loading: () => _WalletsLoading(
                  label: context.tr('Loading accounts'),
                  rows: 2,
                ),
              )
            else
              tenantConfig.when(
                data: (config) => assets.when(
                  data: (walletItems) => budgets.when(
                    data: (budgetItems) => ExchangePanel(
                      config: config,
                      budgets: budgetItems,
                      wallets: walletItems,
                      transferSection: _ExchangeTransfersContent(
                        outflowsEnabled: config.walletOutflowsEnabled,
                      ),
                    ),
                    error: (error, stackTrace) => PlatformErrorState(
                      error: error,
                      compact: false,
                      onRetry: () => ref.invalidate(budgetsProvider),
                    ),
                    loading: () => _WalletsLoading(
                      label: context.tr('Loading accounts'),
                      title: context.tr('Exchange balances'),
                      rows: 3,
                    ),
                  ),
                  error: (error, stackTrace) => PlatformErrorState(
                    error: error,
                    compact: false,
                    onRetry: () => ref.invalidate(hoppaWalletAssetsProvider),
                  ),
                  loading: () => _WalletsLoading(
                    label: context.tr('Loading wallets'),
                    title: context.tr('Exchange balances'),
                    rows: 3,
                  ),
                ),
                error: (error, stackTrace) => PlatformErrorState(
                  error: error,
                  compact: false,
                  onRetry: () => ref.invalidate(mobileTenantConfigProvider),
                ),
                loading: () => _WalletsLoading(
                  label: context.tr('Loading configuration'),
                  title: context.tr('Exchange balances'),
                  rows: 3,
                ),
              )
          else if (view == WalletView.assets)
            assets.when(
              data: (walletItems) => addresses.when(
                data: (addressItems) => _WalletHome(
                  wallets: walletItems,
                  addresses: addressItems,
                  withdrawalsEnabled:
                      tenantConfig.valueOrNull?.walletOutflowsEnabled == true,
                ),
                error: (error, stackTrace) => PlatformErrorState(
                  error: error,
                  compact: false,
                  onRetry: () => ref.invalidate(hoppaWalletAddressesProvider),
                ),
                loading: () => _WalletsLoading(
                  label: context.tr('Loading addresses'),
                  title: context.tr('Your assets'),
                ),
              ),
              error: (error, stackTrace) => PlatformErrorState(
                error: error,
                compact: false,
                onRetry: () => ref.invalidate(hoppaWalletAssetsProvider),
              ),
              loading: () => _WalletsLoading(
                label: context.tr('Loading wallets'),
                title: context.tr('Your assets'),
              ),
            )
          else if (view == WalletView.addresses)
            addresses.when(
              data: (items) => _AddressList(addresses: items),
              error: (error, stackTrace) => PlatformErrorState(
                error: error,
                compact: false,
                onRetry: () => ref.invalidate(hoppaWalletAddressesProvider),
              ),
              loading: () =>
                  _WalletsLoading(label: context.tr('Loading addresses')),
            )
          else ...[
            if (_selectedCurrency.isNotEmpty) ...[
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: InputChip(
                  label: Text(
                      context.tr('{p0} accounts', {'p0': _selectedCurrency})),
                  onDeleted: () => setState(() {
                    _selectedCurrency = '';
                    _openedAccountSelection =
                        '${widget.initialBudgetId.trim()}:';
                  }),
                  deleteButtonTooltipMessage: 'Show all account currencies',
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (!widget.embedded) ...[
              if (isExample) ...[
                ExampleSectionTitle(title: context.tr('Accounts & budgets')),
                const SizedBox(height: AppSpacing.xxs),
                PlatformLede(
                  text: context.tr(
                      'Every account you hold with us, and the budgets that draw on them.'),
                ),
                const SizedBox(height: AppSpacing.md),
              ] else ...[
                Text(
                  context.tr('Accounts & budgets'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
              ],
            ],
            budgets.when(
              data: (items) {
                if (items.isNotEmpty) {
                  _openInitialAccount(items, disclosure);
                  if (isExample && widget.embedded) {
                    return _ExampleBudgetList(
                      budgets: items,
                      disclosure: disclosure,
                      selectedCurrency: _selectedCurrency,
                    );
                  }
                  return _BudgetList(
                    budgets: items,
                    disclosure: disclosure,
                    showCreateButton: !widget.embedded,
                  );
                }
                return balances.when(
                  data: (balanceItems) => _BalanceList(balances: balanceItems),
                  error: (error, stackTrace) => PlatformErrorState(
                    error: error,
                    compact: false,
                    onRetry: () => ref.invalidate(hoppaWalletBalancesProvider),
                  ),
                  loading: () => _WalletsLoading(
                    label: context.tr('Loading balances'),
                    rows: 3,
                  ),
                );
              },
              error: (error, stackTrace) => PlatformErrorState(
                error: error,
                compact: false,
                onRetry: () => ref.invalidate(budgetsProvider),
              ),
              loading: () => _WalletsLoading(
                label: context.tr('Loading budgets'),
                rows: 3,
              ),
            ),
            if (!widget.embedded || !isExample)
              const SafeguardingStatementButton(),
          ],
        ],
      ),
    );

    return PlatformActionListener(
      child: widget.embedded
          ? body
          : Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: !isExample,
                title: Text(
                  isExample
                      ? context.tr('Accounts')
                      : switch (view) {
                          WalletView.assets => 'Crypto',
                          WalletView.addresses => 'Deposit',
                          WalletView.exchange => 'Exchange',
                          WalletView.balances => 'Accounts',
                        },
                ),
                actions: [
                  RefreshAction(onRefresh: refreshBalances),
                  if (!desktop) ...[
                    IconButton(
                      tooltip: context.tr('Settings'),
                      onPressed: () => context.go('/profile'),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                ],
              ),
              body: body,
            ),
    );
  }
}

class _EqualsMoneyExchangeEntry extends ConsumerWidget {
  const _EqualsMoneyExchangeEntry({required this.budgets});

  final List<PlatformResource> budgets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unavailable = _convertibleEqualsBudgets(budgets).isEmpty;
    final onConvert = unavailable
        ? null
        : () => showEqualsMoneyConversionDialog(context, ref, budgets);

    if (context.isExampleTheme) {
      // A business account's whole Exchange route is this one panel, so the
      // conversion CTA is the screen's single decisive action and the one
      // place the glass button belongs. The disabled reason sits under it in
      // secondary ink rather than in a tooltip nobody opens on a phone.
      return ExampleGlassPanel(
        radius: 20,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ExampleIconTile(
                  icon: Icons.currency_exchange_rounded,
                  color: ExamplePalette.of(context).accent,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.tr('Exchange account currencies'),
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                  'Review a live quotation before converting or sending funds in another currency.'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ExampleInk.secondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            ExampleGlassButton(
              label: context.tr('Convert funds'),
              icon: Icons.arrow_forward_rounded,
              expand: false,
              sheen: true,
              onPressed: onConvert,
            ),
            if (unavailable) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr(
                    'A funded budget with at least two supported currencies is required.'),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: ExampleInk.tertiary(context),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return NeoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.currency_exchange_rounded),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.tr('Exchange account currencies'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr(
                'Review a live quotation before converting or sending funds in another currency.'),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onConvert,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(context.tr('Convert funds')),
          ),
          if (unavailable) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                  'A funded budget with at least two supported currencies is required.'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> showEqualsMoneyAddMoneyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _EqualsMoneyAddMoneyDialog(),
  );
}

class _EqualsMoneyAddMoneyDialog extends ConsumerStatefulWidget {
  const _EqualsMoneyAddMoneyDialog();

  @override
  ConsumerState<_EqualsMoneyAddMoneyDialog> createState() =>
      _EqualsMoneyAddMoneyDialogState();
}

class _EqualsMoneyAddMoneyDialogState
    extends ConsumerState<_EqualsMoneyAddMoneyDialog> {
  String? _selectedBudgetId;
  String? _selectedCurrency;

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(budgetsProvider).when(
          loading: () => const AppProgressIndicator(),
          error: (error, _) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(budgetsProvider),
          ),
          data: (resources) {
            final budgets = _equalsBudgetAccounts(resources);
            if (budgets.isEmpty) {
              return Text(
                  context.tr('Your receiving account is not available yet.'));
            }
            final budget = budgets.firstWhere(
              (item) => _budgetId(item) == _selectedBudgetId,
              orElse: () => budgets.firstWhere(
                _isEqualsMainBudget,
                orElse: () => budgets.first,
              ),
            );
            final currencies = <String>{
              for (final row in _budgetBalanceRows(budget)) row.currency,
              ..._budgetCurrencies(budget),
            }.toList();
            final currency = currencies.contains(_selectedCurrency)
                ? _selectedCurrency!
                : currencies.firstOrNull ?? '';
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr(
                      'Send a bank transfer using the receiving details below.'),
                ),
                const SizedBox(height: AppSpacing.md),
                if (budgets.length == 1)
                  _ConversionAccountLabel(budget: budget)
                else
                  DropdownButtonFormField<String>(
                    initialValue: _budgetId(budget),
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('Account or budget'),
                    ),
                    items: [
                      for (final item in budgets)
                        DropdownMenuItem(
                          value: _budgetId(item),
                          child: Text(_budgetTitle(item)),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedBudgetId = value;
                      _selectedCurrency = null;
                    }),
                  ),
                if (currencies.length > 1) ...[
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    key: ValueKey('${_budgetId(budget)}:$currency'),
                    initialValue: currency,
                    decoration:
                        InputDecoration(labelText: context.tr('Currency')),
                    items: [
                      for (final item in currencies)
                        DropdownMenuItem(value: item, child: Text(item)),
                    ],
                    onChanged: (value) => setState(() {
                      _selectedCurrency = value;
                    }),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                _ReceivingAccountDetailsSection(
                  budget: budget,
                  budgets: budgets,
                  currency: currency,
                ),
                const SafeguardingStatementButton(),
              ],
            );
          },
        );
    if (MediaQuery.sizeOf(context).width < 600) {
      return Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Add money')),
            leading: IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: content,
            ),
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(context.tr('Add money')),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(child: content),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    );
  }
}

Future<void> showEqualsMoneyConversionDialog(
  BuildContext context,
  WidgetRef ref,
  List<PlatformResource> budgets, {
  String initialBudgetId = '',
  String initialSourceCurrency = '',
}) async {
  final convertible = _convertibleEqualsBudgets(budgets);
  if (convertible.isEmpty) return;

  await showDialog<void>(
    context: context,
    useSafeArea: false,
    barrierDismissible: false,
    builder: (_) => _EqualsMoneyConversionDialog(
      budgets: convertible,
      initialBudgetId: initialBudgetId,
      initialSourceCurrency: initialSourceCurrency,
    ),
  );
}

class _EqualsMoneyConversionDialog extends ConsumerStatefulWidget {
  const _EqualsMoneyConversionDialog({
    required this.budgets,
    this.initialBudgetId = '',
    this.initialSourceCurrency = '',
  });

  final List<PlatformResource> budgets;
  final String initialBudgetId;
  final String initialSourceCurrency;

  @override
  ConsumerState<_EqualsMoneyConversionDialog> createState() =>
      _EqualsMoneyConversionDialogState();
}

class _EqualsMoneyConversionDialogState
    extends ConsumerState<_EqualsMoneyConversionDialog> {
  List<PlatformResource> get convertible => widget.budgets;
  late PlatformResource budget = convertible
          .where((item) => _budgetId(item) == widget.initialBudgetId)
          .firstOrNull ??
      convertible.first;
  late String sourceCurrency = _fundedBudgetBalanceRows(budget)
          .where((row) =>
              row.currency == widget.initialSourceCurrency.toUpperCase())
          .firstOrNull
          ?.currency ??
      _fundedBudgetBalanceRows(budget).first.currency;
  late String targetCurrency = _conversionCurrencies(budget)
      .firstWhere((currency) => currency != sourceCurrency);
  final amountController = TextEditingController();
  Map<String, dynamic>? quote;
  bool loading = false;
  bool conversionCompleted = false;
  String? error;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !loading,
      child: Builder(
        builder: (dialogContext) {
          final setDialogState = setState;
          final fundedRows = _fundedBudgetBalanceRows(budget);
          final targetCurrencies = _conversionCurrencies(budget)
              .where((currency) => currency != sourceCurrency)
              .toList();
          final selectedBalance = fundedRows
              .where((row) => row.currency == sourceCurrency)
              .firstOrNull;
          final targetBalance = _budgetBalanceRows(budget)
              .where((row) => row.currency == targetCurrency)
              .firstOrNull;
          final VoidCallback? onMax = loading ||
                  quote != null ||
                  selectedBalance == null ||
                  !selectedBalance.amount.isFinite ||
                  selectedBalance.amount <= 0
              ? null
              : () => setDialogState(() {
                    final text = selectedBalance.amount.toString();
                    amountController.value = TextEditingValue(
                      text: text,
                      selection: TextSelection.collapsed(offset: text.length),
                    );
                    error = null;
                  });
          final quoteDetails = _mapValue(quote, const ['quote', 'Quote']);
          final quoteFrom = _mapValue(quoteDetails, const ['from', 'From']);
          final quoteTo = _mapValue(quoteDetails, const ['to', 'To']);
          final settlement =
              _mapValue(quote, const ['settlement', 'Settlement']);
          final charges = _mapValue(settlement, const ['charges', 'Charges']);
          final orderId =
              _textValue(quote ?? const {}, const ['orderId', 'OrderId']);
          final quoteRequestId = _textValue(
            quote ?? const {},
            const ['quoteRequestId', 'QuoteRequestId'],
          );

          Future<void> submit() async {
            final amount = double.tryParse(amountController.text.trim());
            if (amount == null ||
                amount <= 0 ||
                selectedBalance == null ||
                amount > selectedBalance.amount) {
              setDialogState(() {
                error = selectedBalance == null
                    ? 'Select a funded source currency.'
                    : 'Enter an amount up to ${_money(sourceCurrency, selectedBalance.amount)}.';
              });
              return;
            }

            setDialogState(() {
              loading = true;
              error = null;
            });
            final messenger = ScaffoldMessenger.of(context);
            try {
              if (quote == null) {
                final result = await ref
                    .read(mobilePlatformApiProvider)
                    .createEqualsMoneyConversionQuote(
                      accountId: _equalsParentAccountId(budget),
                      budgetId: _budgetId(budget),
                      sourceCurrency: sourceCurrency,
                      targetCurrency: targetCurrency,
                      amount: amount,
                    );
                if (!mounted) return;
                if (_textValue(result, const ['orderId', 'OrderId']) == null ||
                    _textValue(result,
                            const ['quoteRequestId', 'QuoteRequestId']) ==
                        null) {
                  setDialogState(() => error =
                      'We could not retrieve a valid conversion quote. Please try again.');
                  return;
                }
                setDialogState(() => quote = result);
              } else if (orderId != null && quoteRequestId != null) {
                await ref
                    .read(mobilePlatformApiProvider)
                    .executeEqualsMoneyConversion(
                      accountId: _equalsParentAccountId(budget),
                      orderId: orderId,
                      quoteRequestId: quoteRequestId,
                    );
                if (!mounted) return;
                conversionCompleted = true;
                ref.invalidate(budgetsProvider);
                ref.invalidate(hoppaWalletBalancesProvider);
                ref.invalidate(transactionsProvider);
                ref.invalidate(activityTransactionsProvider);
                ref.invalidate(activityAccountTransactionsProvider);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text(context.tr('Conversion completed'))),
                  );
                }
              }
            } catch (exception) {
              if (dialogContext.mounted) {
                setDialogState(() => error = friendlyErrorMessage(exception));
              }
            } finally {
              if (!conversionCompleted && dialogContext.mounted) {
                setDialogState(() => loading = false);
              }
            }
          }

          if (dialogContext.isExampleTheme) {
            return _ExampleEqualsConversionDialog(
              canClose: !loading,
              loading: loading,
              convertibleBudgets: convertible,
              budget: budget,
              fundedRows: fundedRows,
              targetCurrencies: targetCurrencies,
              sourceCurrency: sourceCurrency,
              targetCurrency: targetCurrency,
              amountController: amountController,
              onMax: onMax,
              availableText: selectedBalance == null
                  ? 'No funded balance'
                  : '${_money(sourceCurrency, selectedBalance.amount)} available',
              targetBalanceText: targetBalance == null
                  ? 'No current balance'
                  : '${_money(targetCurrency, targetBalance.amount)} balance',
              targetAmount: quote == null ? '—' : _quoteAmount(quoteTo),
              rate: _formatConversionRate(
                _textValue(quoteDetails, const ['rate', 'Rate']),
              ),
              fee: quote == null ? '—' : _quoteFee(charges, settlement),
              error: error,
              onBudgetChanged: quote != null || loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setDialogState(() {
                        budget = convertible.firstWhere(
                          (item) => _budgetId(item) == value,
                        );
                        sourceCurrency =
                            _fundedBudgetBalanceRows(budget).first.currency;
                        targetCurrency = _conversionCurrencies(budget)
                            .firstWhere(
                                (currency) => currency != sourceCurrency);
                        amountController.clear();
                        error = null;
                      });
                    },
              onSourceChanged: quote != null || loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setDialogState(() {
                        sourceCurrency = value;
                        targetCurrency = _conversionCurrencies(budget)
                            .firstWhere((currency) => currency != value);
                        error = null;
                      });
                    },
              onTargetChanged: quote != null || loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      setDialogState(() {
                        targetCurrency = value;
                        error = null;
                      });
                    },
              onSwap: quote != null || loading
                  ? null
                  : fundedRows.any((row) => row.currency == targetCurrency)
                      ? () {
                          setDialogState(() {
                            final previousSource = sourceCurrency;
                            sourceCurrency = targetCurrency;
                            targetCurrency = previousSource;
                            amountController.clear();
                            error = null;
                          });
                        }
                      : null,
              onAmountChanged: (_) => setDialogState(() {
                quote = null;
                error = null;
              }),
              onPrimary: loading ? null : submit,
              primaryLabel: loading
                  ? 'Processing…'
                  : quote == null
                      ? 'Review conversion'
                      : 'Confirm',
              hasQuote: quote != null,
              onCancelQuote: loading
                  ? null
                  : () => setDialogState(() {
                        quote = null;
                        error = null;
                      }),
            );
          }

          return Dialog.fullscreen(
            child: Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  onPressed:
                      loading ? null : () => Navigator.of(dialogContext).pop(),
                  icon: const Icon(Icons.close),
                ),
                title: Text(context.tr('Convert funds')),
              ),
              body: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                children: [
                  Text(
                    context.tr(
                        'Exchange currencies inside one fiat account or budget. Review the live rate and fee before confirming.'),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (convertible.length == 1)
                    _ConversionAccountLabel(budget: budget)
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _budgetId(budget),
                      decoration: InputDecoration(
                          labelText: context.tr('Account or budget')),
                      items: [
                        for (final item in convertible)
                          DropdownMenuItem(
                            value: _budgetId(item),
                            child: Text(_budgetTitle(item)),
                          ),
                      ],
                      onChanged: quote != null || loading
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() {
                                budget = convertible.firstWhere(
                                  (item) => _budgetId(item) == value,
                                );
                                sourceCurrency =
                                    _fundedBudgetBalanceRows(budget)
                                        .first
                                        .currency;
                                targetCurrency =
                                    _conversionCurrencies(budget).firstWhere(
                                  (currency) => currency != sourceCurrency,
                                );
                                amountController.clear();
                                error = null;
                              });
                            },
                    ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: sourceCurrency,
                    decoration: InputDecoration(labelText: context.tr('From')),
                    items: [
                      for (final row in fundedRows)
                        DropdownMenuItem(
                          value: row.currency,
                          child: Text(
                            context.tr('{p0} · {p1} available', {
                              'p0': row.currency,
                              'p1': _money(row.currency, row.amount)
                            }),
                          ),
                        ),
                    ],
                    onChanged: quote != null || loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setDialogState(() {
                              sourceCurrency = value;
                              targetCurrency = _conversionCurrencies(budget)
                                  .firstWhere((currency) => currency != value);
                              error = null;
                            });
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<String>(
                    initialValue: targetCurrency,
                    decoration: InputDecoration(labelText: context.tr('To')),
                    items: [
                      for (final currency in targetCurrencies)
                        DropdownMenuItem(
                          value: currency,
                          child: Text(currency),
                        ),
                    ],
                    onChanged: quote != null || loading
                        ? null
                        : (value) {
                            if (value != null) {
                              setDialogState(() {
                                targetCurrency = value;
                                error = null;
                              });
                            }
                          },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: amountController,
                    enabled: quote == null && !loading,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: context.tr('Amount'),
                      suffixIcon: TextButton(
                        onPressed: onMax,
                        child: Text(context.tr('Max')),
                      ),
                      helperText: selectedBalance == null
                          ? null
                          : context.tr('{p0} available', {
                              'p0':
                                  _money(sourceCurrency, selectedBalance.amount)
                            }),
                    ),
                  ),
                  const SafeguardingStatementButton(),
                  if (quote != null) ...[
                    const SizedBox(height: AppSpacing.lg),
                    NeoSurfaceCard(
                      child: Column(
                        children: [
                          _SheetRow(
                            label: context.tr('You send'),
                            value: _quoteAmount(quoteFrom),
                          ),
                          _SheetRow(
                            label: context.tr('Rate'),
                            value: _textValue(
                                  quoteDetails,
                                  const ['rate', 'Rate'],
                                ) ??
                                '—',
                          ),
                          _SheetRow(
                            label: context.tr('You receive'),
                            value: _quoteAmount(quoteTo),
                          ),
                          _SheetRow(
                            label: context.tr('Fee'),
                            value: _quoteFee(charges, settlement),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
              bottomNavigationBar: SafeArea(
                minimum: const EdgeInsets.all(20),
                child: FilledButton(
                  onPressed: loading ? null : submit,
                  child: Text(
                    loading
                        ? context.tr('Processing…')
                        : quote == null
                            ? context.tr('Get live quote')
                            : context.tr('Confirm conversion'),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ConversionAccountLabel extends StatelessWidget {
  const _ConversionAccountLabel({required this.budget});

  final PlatformResource budget;

  @override
  Widget build(BuildContext context) => InputDecorator(
        decoration: InputDecoration(labelText: context.tr('Account or budget')),
        child: Text(_budgetTitle(budget)),
      );
}

class _ExampleEqualsConversionDialog extends StatelessWidget {
  const _ExampleEqualsConversionDialog({
    required this.canClose,
    required this.loading,
    required this.convertibleBudgets,
    required this.budget,
    required this.fundedRows,
    required this.targetCurrencies,
    required this.sourceCurrency,
    required this.targetCurrency,
    required this.amountController,
    required this.onMax,
    required this.availableText,
    required this.targetBalanceText,
    required this.targetAmount,
    required this.rate,
    required this.fee,
    required this.error,
    required this.onBudgetChanged,
    required this.onSourceChanged,
    required this.onTargetChanged,
    required this.onSwap,
    required this.onAmountChanged,
    required this.onPrimary,
    required this.primaryLabel,
    this.hasQuote = false,
    this.onCancelQuote,
  });

  final bool canClose;
  final bool loading;
  final bool hasQuote;
  final VoidCallback? onCancelQuote;
  final List<PlatformResource> convertibleBudgets;
  final PlatformResource budget;
  final List<_BudgetBalanceRow> fundedRows;
  final List<String> targetCurrencies;
  final String sourceCurrency;
  final String targetCurrency;
  final TextEditingController amountController;
  final VoidCallback? onMax;
  final String availableText;
  final String targetBalanceText;
  final String targetAmount;
  final String rate;
  final String fee;
  final String? error;
  final ValueChanged<String?>? onBudgetChanged;
  final ValueChanged<String?>? onSourceChanged;
  final ValueChanged<String?>? onTargetChanged;
  final VoidCallback? onSwap;
  final ValueChanged<String> onAmountChanged;
  final VoidCallback? onPrimary;
  final String primaryLabel;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final useWebDialog = kIsWeb && size.width >= 600;
    if (useWebDialog || (!kIsWeb && size.width >= 900)) {
      return _buildDesktopDialog(context, size);
    }
    return Dialog.fullscreen(child: _buildMobileContent(context));
  }

  Widget _buildMobileContent(BuildContext context) {
    final scaffold = Scaffold(
      backgroundColor: ExamplePalette.of(context).paper,
      appBar: AppBar(
        centerTitle: true,
        leading: IconButton(
          tooltip: context.tr('Close'),
          onPressed: canClose ? () => Navigator.of(context).pop() : null,
          icon: const Icon(Icons.close_rounded),
        ),
        title: Text(context.tr('Convert funds')),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
          children: [
            Text(
              context.tr('Exchange currencies in your fiat account'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              context.tr('Review the live rate and fee before confirming.'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _fadedInk(context, .58),
                  ),
            ),
            const SizedBox(height: 18),
            if (convertibleBudgets.length == 1)
              _ConversionAccountLabel(budget: budget)
            else
              DropdownButtonFormField<String>(
                key: ValueKey(_budgetId(budget)),
                initialValue: _budgetId(budget),
                decoration:
                    InputDecoration(labelText: context.tr('Account or budget')),
                items: [
                  for (final item in convertibleBudgets)
                    DropdownMenuItem(
                      value: _budgetId(item),
                      child: Text(_budgetTitle(item)),
                    ),
                ],
                onChanged: onBudgetChanged,
              ),
            const SizedBox(height: 14),
            _ExampleConversionAmountCard(
              label: context.tr('From'),
              provider: 'Fiat account',
              currency: sourceCurrency,
              currencies: fundedRows.map((row) => row.currency).toList(),
              balanceText: availableText,
              amountController: amountController,
              enabled: !loading && onSourceChanged != null,
              onCurrencyChanged: onSourceChanged,
              onAmountChanged: onAmountChanged,
              onMax: onMax,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox.square(
                  dimension: 48,
                  child: IconButton.filledTonal(
                    tooltip: context.tr('Swap currencies'),
                    onPressed: onSwap,
                    icon: const Icon(Icons.swap_vert_rounded, size: 20),
                  ),
                ),
              ),
            ),
            _ExampleConversionAmountCard(
              label: context.tr('To'),
              provider: 'Fiat account',
              currency: targetCurrency,
              currencies: targetCurrencies,
              balanceText: targetBalanceText,
              displayAmount: targetAmount,
              enabled: !loading && onTargetChanged != null,
              onCurrencyChanged: onTargetChanged,
            ),
            const SizedBox(height: 12),
            _ExampleConversionFact(label: context.tr('Rate'), value: rate),
            const SizedBox(height: 7),
            _ExampleConversionFact(label: context.tr('Fee'), value: fee),
            const SafeguardingStatementButton(),
            if (error != null) ...[
              const SizedBox(height: 13),
              Semantics(
                liveRegion: true,
                child: Text(
                  error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: ExampleInk.accent(
                          context,
                          ExamplePalette.of(context).danger,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
          // No fixed 50 pt box any more: the glass button treats its height
          // as a floor, so at text scale 1.3 the bar grows instead of
          // clipping the label it exists to show.
          //
          // [IntrinsicHeight] is load-bearing, not decoration. A `Row` with
          // `CrossAxisAlignment.stretch` takes its cross-axis extent from the
          // incoming *maximum* height, and a `bottomNavigationBar` is measured
          // against the whole Scaffold — so the bar claimed all 600 px and the
          // conversion form above it laid out at exactly zero height. The
          // dialog opened with a title, a CTA and nothing in between; every
          // field, both dropdowns, the rate and the fee were absent from the
          // tree, not merely scrolled away. Bounding the row to its tallest
          // child restores the body and still lets the two buttons share one
          // height as text scales.
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (hasQuote) ...[
                  SizedBox(
                    width: 120,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        foregroundColor: ExampleInk.primary(context),
                        // A control's boundary, not a divider: the structural
                        // hairline is 1.18:1 on paper where 1.4.11 asks 3:1.
                        side: ExampleBorders.controlSideOf(context),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: onCancelQuote,
                      child: Text(context.tr('Cancel')),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  // The one decisive action of the whole conversion flow: get
                  // the quote, then confirm it. It carries the screen's single
                  // sheen while it is still an invitation, and drops it once a
                  // live quote is on screen and the button is a commitment.
                  child: ExampleGlassButton(
                    label: primaryLabel,
                    height: 50,
                    loading: loading,
                    sheen: !hasQuote,
                    onPressed: onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return PopScope(canPop: canClose, child: scaffold);
  }

  Widget _buildDesktopDialog(BuildContext context, Size size) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: canClose,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: EdgeInsets.symmetric(
          horizontal: size.width < 720 ? 16 : 32,
          vertical: 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 760,
            maxHeight: (size.height - 48).clamp(460, 620).toDouble(),
          ),
          child: Material(
            color: ExamplePalette.of(context).paper,
            elevation: 24,
            // A .45 black cast is right under a night dialog and a bruise
            // under a paper one; daylight lifts on the ambient token.
            shadowColor: ExampleTheme.isLight(context)
                ? ExamplePalette.of(context).shadowLift
                : context.brandDesign.color(
                    Theme.of(context).brightness, 'shadowLift',
                    fallback: Colors.black.withValues(alpha: .45)),
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('Convert funds'),
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              context.tr(
                                  'Exchange currencies in your fiat account at the live rate.'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _fadedInk(context, .56),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Close'),
                        visualDensity: VisualDensity.compact,
                        onPressed:
                            canClose ? () => Navigator.of(context).pop() : null,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (convertibleBudgets.length == 1)
                    _ConversionAccountLabel(budget: budget)
                  else
                    DropdownButtonFormField<String>(
                      key: ValueKey(_budgetId(budget)),
                      initialValue: _budgetId(budget),
                      isDense: true,
                      decoration: InputDecoration(
                        labelText: context.tr('Account or budget'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        for (final item in convertibleBudgets)
                          DropdownMenuItem(
                            value: _budgetId(item),
                            child: Text(_budgetTitle(item)),
                          ),
                      ],
                      onChanged: onBudgetChanged,
                    ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _ExampleConversionAmountCard(
                          label: context.tr('From'),
                          provider: 'Fiat account',
                          currency: sourceCurrency,
                          currencies:
                              fundedRows.map((row) => row.currency).toList(),
                          balanceText: availableText,
                          amountController: amountController,
                          enabled: !loading && onSourceChanged != null,
                          onCurrencyChanged: onSourceChanged,
                          onAmountChanged: onAmountChanged,
                          onMax: onMax,
                          compactDesktop: true,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: SizedBox.square(
                          dimension: 38,
                          child: IconButton.outlined(
                            tooltip: context.tr('Swap currencies'),
                            onPressed: onSwap,
                            icon:
                                const Icon(Icons.swap_horiz_rounded, size: 19),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _ExampleConversionAmountCard(
                          label: context.tr('To'),
                          provider: 'Fiat account',
                          currency: targetCurrency,
                          currencies: targetCurrencies,
                          balanceText: targetBalanceText,
                          displayAmount: targetAmount,
                          enabled: !loading && onTargetChanged != null,
                          onCurrencyChanged: onTargetChanged,
                          compactDesktop: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: ExampleSurface.navigationOf(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _hairline(context, .12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _ExampleConversionFact(
                            label: context.tr('Rate'),
                            value: rate,
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 20,
                          margin: const EdgeInsets.symmetric(horizontal: 18),
                          color: _hairline(context, .12),
                        ),
                        Expanded(
                          child: _ExampleConversionFact(
                            label: context.tr('Fee'),
                            value: fee,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SafeguardingStatementButton(),
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ExampleInk.accent(
                            context,
                            ExamplePalette.of(context).danger,
                          ),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 44),
                        ),
                        onPressed: hasQuote
                            ? onCancelQuote
                            : canClose
                                ? () => Navigator.of(context).pop()
                                : null,
                        child: Text(hasQuote
                            ? context.tr('Cancel')
                            : context.tr('Close')),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 184,
                        // 40 was under the 44 pt floor on the one control
                        // that moves money.
                        child: ExampleGlassButton(
                          label: primaryLabel,
                          height: 44,
                          loading: loading,
                          onPressed: onPrimary,
                        ),
                      ),
                    ],
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

class _ExampleConversionAmountCard extends StatelessWidget {
  const _ExampleConversionAmountCard({
    required this.label,
    required this.provider,
    required this.currency,
    required this.currencies,
    required this.balanceText,
    required this.enabled,
    required this.onCurrencyChanged,
    this.amountController,
    this.displayAmount,
    this.onAmountChanged,
    this.onMax,
    this.compactDesktop = false,
  });

  final String label;
  final String provider;
  final String currency;
  final List<String> currencies;
  final String balanceText;
  final bool enabled;
  final ValueChanged<String?>? onCurrencyChanged;
  final TextEditingController? amountController;
  final String? displayAmount;
  final ValueChanged<String>? onAmountChanged;
  final VoidCallback? onMax;
  final bool compactDesktop;

  @override
  Widget build(BuildContext context) => Container(
        padding: compactDesktop
            ? const EdgeInsets.fromLTRB(14, 10, 14, 10)
            : const EdgeInsets.fromLTRB(15, 12, 15, 12),
        decoration: BoxDecoration(
          color: ExampleSurface.navigationOf(context),
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: _hairline(context, .16),
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _fadedInk(context, .52),
                        ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    provider,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _fadedInk(context, .52),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 2, 5, 2),
                  decoration: BoxDecoration(
                    color: _wellFill(context, .58),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currency,
                      isDense: true,
                      borderRadius: BorderRadius.circular(14),
                      dropdownColor: ExampleSurface.navigationOf(context),
                      onChanged: enabled ? onCurrencyChanged : null,
                      items: [
                        for (final item in currencies)
                          DropdownMenuItem(
                            value: item,
                            child: Text(
                              item,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: amountController == null
                      ? Text(
                          displayAmount ?? '—',
                          textAlign: TextAlign.right,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        )
                      : TextField(
                          controller: amountController,
                          enabled: enabled,
                          textAlign: TextAlign.right,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '0.00',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: onAmountChanged,
                        ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: Text(
                    balanceText,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _fadedInk(context, .42),
                        ),
                  ),
                ),
                if (amountController != null)
                  TextButton(
                    onPressed: enabled ? onMax : null,
                    child: Text(context.tr('Max')),
                  ),
                if (amountController == null)
                  Text(
                    context.tr('Estimate'),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _fadedInk(context, .42),
                        ),
                  ),
              ],
            ),
          ],
        ),
      );
}

class _ExampleConversionFact extends StatelessWidget {
  const _ExampleConversionFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _fadedInk(context, .54),
                  ),
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
        ],
      );
}

bool canConvertEqualsMoneyBudgets(List<PlatformResource> budgets) =>
    _convertibleEqualsBudgets(budgets).isNotEmpty;

class _AddressList extends StatelessWidget {
  const _AddressList({required this.addresses});

  final List<HoppaWalletAsset> addresses;

  @override
  Widget build(BuildContext context) {
    if (addresses.isEmpty) {
      return PlatformEmptyState(
        compact: false,
        title: context.tr('No deposit addresses'),
        message: context.tr(
            'An address appears here only after the provider enables deposits for that network.'),
        icon: Icons.qr_code_2,
      );
    }

    if (context.isExampleTheme) {
      // One surface with hairlines instead of a card per address: the list
      // is navigation, and a stack of bordered cards makes six taps look
      // like six unrelated objects.
      //
      // The section title and its lede are *not* here. They belong to the
      // route, not to the data, so they are rendered once by the screen
      // above every async state; drawing them here as well was the screen's
      // one duplicated heading.
      return ExampleListGroup(
        children: [
          for (final address in addresses)
            ExampleRow(
              title: context.tr('{p0} deposit address', {'p0': address.symbol}),
              subtitle: address.hasNetwork
                  ? address.network
                  : context.tr('Tap to view'),
              leading: ExampleCurrencyAvatar(code: address.symbol, size: 32),
              trailing: ExampleRow.chevron,
              onTap: () => _showDepositAddressDialog(context, address),
              semanticsLabel: context
                  .tr('View the {p0} deposit address', {'p0': address.symbol}),
            ),
        ],
      );
    }

    return Column(
      children: [
        for (final address in addresses)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: NeoSurfaceCard(
              onTap: () => _showDepositAddressDialog(context, address),
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: CurrencyLogo(symbol: address.symbol),
                title: Text(
                    context.tr('{p0} deposit address', {'p0': address.symbol})),
                subtitle: Text(
                  address.hasNetwork
                      ? context.tr(
                          '{p0} · Tap to view address', {'p0': address.network})
                      : context.tr('Tap to view address'),
                ),
                trailing: const Icon(Icons.chevron_right),
              ),
            ),
          ),
      ],
    );
  }
}

class _BalanceList extends StatelessWidget {
  const _BalanceList({required this.balances});

  final List<HoppaWalletBalance> balances;

  @override
  Widget build(BuildContext context) {
    final funded = balances
        .where((balance) =>
            balance.available.abs() >= 0.00000001 ||
            balance.reserved.abs() >= 0.00000001)
        .toList();
    if (funded.isEmpty) return const SizedBox.shrink();

    if (context.isExampleTheme) {
      // The same ledger the crypto assets get: one surface, hairlines between
      // rows, figures right-aligned on a single tabular column, so a stack of
      // currencies reads down the page instead of being interrupted by a
      // border every 56 px.
      return ExampleListGroup(
        children: [
          for (final balance in funded)
            ExampleRow(
              title: balance.label,
              subtitle: balance.currency.toUpperCase(),
              leading: ExampleCurrencyAvatar(code: balance.currency, size: 32),
              trailing: _ExampleBalanceValue(balance: balance),
              semanticsLabel: '${balance.label}, '
                  '${_money(balance.currency, balance.available)} available',
            ),
        ],
      );
    }

    return Column(
      children: [
        for (final balance in funded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: NeoSurfaceCard(
              padding: EdgeInsets.zero,
              child: ListTile(
                leading: CurrencyLogo(
                  symbol: balance.currency,
                  fallbackIcon: Icons.account_balance_outlined,
                ),
                title: Text(balance.label),
                subtitle: Text(
                  balance.reserved > 0
                      ? context.tr('{p0} reserved',
                          {'p0': _money(balance.currency, balance.reserved)})
                      : context.tr('Available to spend or transfer'),
                ),
                trailing: Text(
                  _money(balance.currency, balance.available),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The figures column of a fiat balance row.
///
/// Available on the primary ink through [ExampleAmount] with tabular figures,
/// and beneath it — in tertiary ink on the same grid — what the provider is
/// holding back, so the two numbers stack instead of competing for one line.
/// Both themes resolve by role: Twilight keeps its tokens, paper reads the
/// daylight tertiary.
class _ExampleBalanceValue extends StatelessWidget {
  const _ExampleBalanceValue({required this.balance});

  final HoppaWalletBalance balance;

  @override
  Widget build(BuildContext context) {
    final reserved = balance.reserved;
    final held = reserved.abs() >= 0.00000001;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ExampleAmount(
          amount: balance.available,
          currency: balance.currency,
          size: ExampleAmountSize.inline,
          code: ExampleAmountCode.never,
          textAlign: TextAlign.end,
        ),
        const SizedBox(height: 1),
        Text(
          held
              ? context.tr(
                  '{p0} reserved', {'p0': _money(balance.currency, reserved)})
              : context.tr('Available'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 11.5,
            color: ExampleInk.tertiary(context),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _WalletHome extends ConsumerWidget {
  const _WalletHome({
    required this.wallets,
    required this.addresses,
    required this.withdrawalsEnabled,
  });

  final List<HoppaWalletAsset> wallets;
  final List<HoppaWalletAsset> addresses;
  final bool withdrawalsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletSymbols = wallets.map((wallet) => wallet.symbol).toSet();
    final displayWallets = [
      ...wallets,
      ...addresses.where((item) => !walletSymbols.contains(item.symbol)),
    ];
    final topUpSources = wallets
        .where((wallet) =>
            _topUpSourceSymbols.contains(wallet.symbol.toUpperCase()))
        .toList();

    if (displayWallets.isEmpty) {
      return PlatformEmptyState(
        compact: false,
        title: context.tr('No crypto assets yet'),
        message: context.tr('Crypto balances will appear after provider sync.'),
        icon: Icons.donut_large,
      );
    }

    if (context.isExampleTheme) {
      return _ExampleWalletHome(
        wallets: displayWallets,
        addresses: addresses,
        withdrawalsEnabled: withdrawalsEnabled,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final wallet in displayWallets)
          _WalletAssetCard(
            asset: wallet,
            depositAddresses: addresses
                .where((address) => address.symbol == wallet.symbol)
                .toList(),
            topUpSources: topUpSources,
            withdrawalsEnabled: withdrawalsEnabled,
          ),
      ],
    );
  }
}

/// Arms the screen's single arrival moment, once, and only once the route is
/// really on screen.
///
/// A freshly pushed route reports its animation as already completed on the
/// first build, so asking on frame one would arm the moment during the 420 ms
/// route transition, where nothing is allowed to run. The short delay lets
/// the real animation be installed, then the moment waits for it. Reduced
/// motion never schedules anything: the settled state is correct on frame one,
/// which is the final visual state rather than a faster version of it.
class _WalletsArrival extends StatefulWidget {
  const _WalletsArrival({required this.builder});

  final Widget Function(BuildContext context, bool settled) builder;

  @override
  State<_WalletsArrival> createState() => _WalletsArrivalState();
}

class _WalletsArrivalState extends State<_WalletsArrival> {
  /// How long after mount the moment is armed. Long enough that the route
  /// animation has been installed for real.
  static const Duration _settleDelay = Duration(milliseconds: 240);

  bool _settled = false;
  Timer? _settleTimer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    if (ExampleMotion.reduced(context)) {
      _settled = true;
      return;
    }
    _settleTimer ??= Timer(_settleDelay, _armFromRoute);
  }

  void _armFromRoute() {
    if (!mounted || _settled) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      setState(() => _settled = true);
      return;
    }
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _detachRoute();
    if (!mounted || _settled) return;
    setState(() => _settled = true);
  }

  void _detachRoute() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _detachRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _settled);
}

/// Example's Accounts home: one portfolio figure, four actions, then the
/// assets as a ledger.
///
/// The balances are a [ExampleListGroup] of [ExampleRow]s rather than a stack
/// of glass cards: one surface, one edge, hairlines between rows, so the
/// column of figures reads down the page instead of being interrupted by a
/// border every 56 px. Both themes come from named roles only — Twilight
/// keeps the tokens it always rendered, and on paper the group is a white
/// card under the daylight ambient rather than a dark panel inverted.
///
/// One moment, and it is the portfolio figure. Accounts is where the answer
/// to "what do I have" lives, so the total arrives in secondary ink and
/// settles into primary once the route transition has finished — ink only,
/// same glyphs, same box, same position. Everything else on the screen is
/// the 120 ms press on the actions and the 200 ms crossfade [ExampleAmount]
/// already runs when a balance actually changes.
class _ExampleWalletHome extends StatelessWidget {
  const _ExampleWalletHome({
    required this.wallets,
    required this.addresses,
    required this.withdrawalsEnabled,
  });

  final List<HoppaWalletAsset> wallets;
  final List<HoppaWalletAsset> addresses;
  final bool withdrawalsEnabled;

  /// Below this the four actions sit two to a row so their labels stay whole.
  static const double _twoRowActions = 560;

  /// Above this the hero and the ledger sit side by side.
  static const double _sideBySide = 900;

  @override
  Widget build(BuildContext context) {
    final priced = wallets.where((wallet) => wallet.hasFiatValue).toList();
    final stable = wallets
        .where((wallet) => !wallet.hasFiatValue && _isUsdPegged(wallet.symbol))
        .toList();
    final total =
        priced.fold<double>(0, (sum, wallet) => sum + wallet.fiatValue) +
            stable.fold<double>(0, (sum, wallet) => sum + wallet.amount);
    final allEstimated = priced.length + stable.length == wallets.length;
    final sendAsset = wallets.firstWhere(
      (wallet) =>
          withdrawalsEnabled &&
          wallet.amount > 0 &&
          const {'USDC', 'USDT'}.contains(wallet.symbol.toUpperCase()),
      orElse: () => wallets.first,
    );

    // One LayoutBuilder for the whole screen. The action grid used to nest a
    // second one inside the hero panel, which is a blank screen waiting for
    // any ancestor that measures an intrinsic dimension; the breakpoint it
    // needed is already known here.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final hero = _hero(
          context,
          total: total,
          allEstimated: allEstimated,
          sendAsset: sendAsset,
          twoRowActions: width >= _sideBySide || width < _twoRowActions,
        );
        final ledger = _ledger(context);
        final notice = _notice(context);

        if (width >= _sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 400,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [hero, const SizedBox(height: 12), notice],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(child: ledger),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            hero,
            const SizedBox(height: 16),
            ledger,
            const SizedBox(height: 12),
            notice,
          ],
        );
      },
    );
  }

  Widget _hero(
    BuildContext context, {
    required double total,
    required bool allEstimated,
    required HoppaWalletAsset sendAsset,
    required bool twoRowActions,
  }) {
    final palette = ExamplePalette.of(context);
    final actions = <({String label, bool primary, VoidCallback? onTap})>[
      (
        label: context.tr('Exchange to crypto'),
        primary: true,
        onTap: () => showCryptoExchangeSheet(context),
      ),
      (
        label: context.tr('Exchange to USD'),
        primary: false,
        onTap: () => showCryptoExchangeSheet(
              context,
              initialSide: CryptoTradeSide.sell,
            ),
      ),
      (
        label: context.tr('Receive'),
        primary: false,
        onTap: () => showStablecoinDepositDialog(context, addresses: addresses),
      ),
      (
        label: context.tr('Send'),
        primary: false,
        onTap: withdrawalsEnabled
            ? () => showCryptoWithdrawalDialog(context, asset: sendAsset)
            : null,
      ),
    ];

    return ExampleGlassPanel(
      radius: 20,
      borderAlpha: .26,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Portfolio value'),
            style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
          ),
          const SizedBox(height: 3),
          // The one moment: ink only. The figure keeps its glyphs, its box
          // and its position while it settles, so nothing on the screen
          // moves. Under reduced motion it is primary on frame one.
          _WalletsArrival(
            builder: (context, settled) => ExampleStateSwitch(
              alignment: Alignment.centerLeft,
              child: KeyedSubtree(
                key: ValueKey<bool>(settled),
                child: ExampleAmount(
                  amount: total,
                  currency: 'USD',
                  size: ExampleAmountSize.medium,
                  code: ExampleAmountCode.never,
                  color: settled
                      ? ExampleInk.primary(context)
                      : ExampleInk.secondary(context),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            allEstimated
                ? context.tr('Estimated across {p0} {p1}', {
                    'p0': wallets.length,
                    'p1': context.tr(wallets.length == 1 ? 'asset' : 'assets')
                  })
                : context.tr('Estimated · some assets unpriced'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: allEstimated ? palette.success : palette.warning,
            ),
          ),
          const SizedBox(height: 14),
          // Two tight columns on a phone, four across a tablet. Every child
          // is width-bound by the row, so a long label ellipsises inside its
          // button instead of overflowing the panel at text scale 1.3.
          for (var start = 0;
              start < actions.length;
              start += twoRowActions ? 2 : 4) ...[
            if (start > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var index = start;
                    index < start + (twoRowActions ? 2 : 4) &&
                        index < actions.length;
                    index++) ...[
                  if (index != start) const SizedBox(width: 8),
                  Expanded(
                    child: _ExampleCryptoAction(
                      label: actions[index].label,
                      primary: actions[index].primary,
                      onTap: actions[index].onTap,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _ledger(BuildContext context) {
    final count = '${wallets.length} '
        '${context.tr(wallets.length == 1 ? 'asset' : 'assets')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The count is a fact, not an action, so it stays in tertiary ink
        // rather than taking the accent ExampleSectionTitle gives an action.
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Your assets'),
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.primary(context),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: Text(
                count,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  color: ExampleInk.tertiary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ExampleListGroup(
          children: [
            for (final wallet in wallets) _ExampleAssetRow(wallet: wallet),
          ],
        ),
      ],
    );
  }

  Widget _notice(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return ExampleGlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.warning_amber_rounded,
              color: palette.warning,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Check the network before you send'),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  context.tr(
                      'Address and chain are validated before submission. Sending to the wrong chain is irreversible.'),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: palette.textSecondary,
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

bool _isUsdPegged(String symbol) =>
    const {'USD', 'USDC', 'USDT'}.contains(symbol.trim().toUpperCase());

/// One asset in the balance ledger.
///
/// Avatar, then the asset by name, then the figures right-aligned in a single
/// column: the holding on the primary ink in [ExampleAmount] with tabular
/// figures, and its fiat value under it in tertiary ink. Two numbers on one
/// baseline grid, so a column of assets can be compared by eye — which is the
/// whole job of a balance list.
class _ExampleAssetRow extends StatelessWidget {
  const _ExampleAssetRow({required this.wallet});

  final HoppaWalletAsset wallet;

  @override
  Widget build(BuildContext context) {
    final name = wallet.name.trim().isEmpty ? wallet.symbol : wallet.name;
    final subtitle = wallet.hasNetwork && wallet.network.trim().isNotEmpty
        ? '${wallet.symbol} · ${wallet.network}'
        : wallet.symbol;
    return ExampleRow(
      title: name,
      subtitle: subtitle,
      leading: ExampleCurrencyAvatar(code: wallet.symbol, size: 32),
      trailing: _ExampleAssetValue(wallet: wallet),
      semanticsLabel: '$name, ${_walletAmount(wallet.amount, wallet.symbol)} '
          '${wallet.symbol}',
    );
  }
}

/// The figures column of an asset row.
class _ExampleAssetValue extends StatelessWidget {
  const _ExampleAssetValue({required this.wallet});

  final HoppaWalletAsset wallet;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final fiat = wallet.hasFiatValue
        ? _money('USD', wallet.fiatValue)
        : _isUsdPegged(wallet.symbol)
            ? _money('USD', wallet.amount)
            : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ExampleAmount(
          amount: wallet.amount,
          currency: wallet.symbol,
          size: ExampleAmountSize.inline,
          code: ExampleAmountCode.never,
          textAlign: TextAlign.end,
        ),
        const SizedBox(height: 1),
        Text(
          fiat == null
              ? context.tr('Unpriced')
              : !wallet.hasFiatValue
                  ? context.tr('{p0} · Estimated', {'p0': fiat})
                  : fiat,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.end,
          style: TextStyle(
            fontSize: 11.5,
            color: palette.textTertiary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _ExampleCryptoAction extends StatelessWidget {
  const _ExampleCryptoAction({
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    if (primary) {
      // The house glass CTA, not a themed FilledButton: it is the one
      // decisive action in the portfolio panel, it resolves both themes
      // itself, it clamps to the 44 pt floor, and its sheen is the screen's
      // single alive surface — one host, on the one control that earns it.
      // 12 px rather than the pill so it reads as a sibling of the three
      // outlined actions beside it rather than a different species.
      return ExampleGlassButton(
        label: label,
        height: 44,
        radius: 12,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        sheen: true,
        onPressed: onTap,
      );
    }
    final enabled = onTap != null;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        backgroundColor: _panelFill(context, .6),
        // The ink and the disabled ink are named rather than inherited: this
        // button sits on a panel fill of its own, and the Material default
        // for a disabled outlined label is an onSurface alpha that has no
        // relationship to either Example theme.
        foregroundColor: ExampleInk.primary(context),
        disabledForegroundColor: ExampleInk.primary(context)
            .withValues(alpha: ExampleOpacity.disabled),
        // WCAG 1.4.11 asks 3:1 of the boundary of something the user
        // *operates*, and these three are the most-tapped controls on the
        // route. The structural hairline this used to draw is lavender .30 on
        // paper — 1.18:1 — which is a divider's contrast, not a control's.
        side: ExampleBorders.controlSideOf(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // The same label style the glass button resolves for itself, so the
        // four actions in the row read as one set of siblings instead of a
        // 14 pt primary next to three 13.5 pt strangers.
        textStyle: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
      onPressed: onTap,
      child: Text(
        label,
        maxLines: 1,
        // The label ellipsises inside the button rather than pushing the row
        // wider: "Exchange to crypto" at text scale 1.3 in a half-width slot
        // at 375 px has nowhere else to go.
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        semanticsLabel:
            enabled ? null : context.tr('{p0}, unavailable', {'p0': label}),
      ),
    );
  }
}

class _WalletSectionHeader extends StatelessWidget {
  const _WalletSectionHeader({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleLarge),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ExchangeTransfersContent extends ConsumerWidget {
  const _ExchangeTransfersContent({required this.outflowsEnabled});

  final bool outflowsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transfers = ref.watch(exchangeTransfersProvider);
    final isExample = context.isExampleTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isExample)
          ExampleSectionTitle(
            title: context.tr('Transfers in progress'),
            action: context.tr('All transactions'),
            onAction: () => context.push('/transactions'),
          )
        else
          SectionHeader(
            title: context.tr('Transfers in progress'),
            actionLabel: context.tr('View all transactions'),
            onAction: () => context.push('/transactions'),
          ),
        Text(
          context.tr(
              'Only transfers that still need processing or your attention are shown.'),
          style: isExample
              ? TextStyle(
                  fontSize: 12,
                  height: 1.4,
                  color: ExampleInk.tertiary(context),
                )
              : Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
        ),
        const SizedBox(height: AppSpacing.sm),
        transfers.when(
          data: (items) => _TransferProgressList(
            transfers: items,
            outflowsEnabled: outflowsEnabled,
          ),
          loading: () =>
              _WalletsLoading(label: context.tr('Loading transfers'), rows: 2),
          error: (error, stackTrace) => PlatformErrorState(
            error: error,
            onRetry: () => ref.invalidate(exchangeTransfersProvider),
          ),
        ),
      ],
    );
  }
}

// Retained as a reusable hub composition, but intentionally not used by the
// separated mobile Money and Crypto screens.
// ignore: unused_element
class _WalletActionPanel extends StatelessWidget {
  const _WalletActionPanel({
    required this.addresses,
    required this.exchangeEnabled,
  });

  final List<HoppaWalletAsset> addresses;
  final bool exchangeEnabled;

  @override
  Widget build(BuildContext context) {
    return NeoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('What do you want to do?'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            context.tr('Choose an action and we’ll guide you step by step.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => showStablecoinDepositDialog(
                context,
                addresses: addresses,
              ),
              icon: const Icon(Icons.south_rounded),
              label: Text(context.tr('Deposit crypto')),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _HubActionButton(
            icon: Icons.send_outlined,
            label: context.tr('Move money'),
            onPressed: () => context.push('/money/pay'),
          ),
          const SizedBox(height: AppSpacing.xs),
          _HubActionButton(
            icon: Icons.swap_horiz_rounded,
            label: context.tr('Exchange'),
            onPressed: exchangeEnabled
                ? () => context.push('/wallets/exchange')
                : null,
          ),
          const SizedBox(height: AppSpacing.xs),
          _HubActionButton(
            icon: Icons.add_rounded,
            label: context.tr('Add or withdraw'),
            onPressed: () => context.push('/payments'),
          ),
          const SizedBox(height: AppSpacing.xs),
          _HubActionButton(
            icon: Icons.credit_card_rounded,
            label: context.tr('Buy crypto with card'),
            onPressed: () => showBuyCryptoSheet(context),
          ),
        ],
      ),
    );
  }
}

class _HubActionButton extends StatelessWidget {
  const _HubActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
        ),
      );
}

// ignore: unused_element
class _MoneyServiceCard extends StatelessWidget {
  const _MoneyServiceCard({
    required this.wallets,
  });

  final List<HoppaWalletAsset> wallets;

  @override
  Widget build(BuildContext context) {
    final sorted = [...wallets]
      ..sort((left, right) => left.symbol.compareTo(right.symbol));
    return NeoSurfaceCard(
      padding: EdgeInsets.zero,
      borderColor: Theme.of(context).colorScheme.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: .12),
                  child: const Icon(Icons.account_balance_wallet_outlined),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('Crypto cards')),
                      Text(context.tr('Card balances and crypto wallets')),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (sorted.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Text(context.tr('No crypto balances are available yet.')),
            )
          else
            for (final wallet in sorted)
              ListTile(
                leading: CurrencyLogo(
                  symbol: wallet.symbol,
                  fallbackColor: wallet.tint,
                ),
                title: Text(context.tr('{p0} wallet', {'p0': wallet.symbol})),
                subtitle: Text(wallet.name),
                trailing: Text(
                  '${_walletAmount(wallet.amount)} ${wallet.symbol}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ExchangeServiceCard extends StatelessWidget {
  const _ExchangeServiceCard({required this.overview, required this.ready});

  final AsyncValue<BoomFiExchangeOverview> overview;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final data = overview.valueOrNull;
    return NeoSurfaceCard(
      onTap: () => context.push('/wallets/exchange'),
      child: Row(
        children: [
          CircleAvatar(
            child: Icon(
              Icons.currency_exchange_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(context.tr('Exchange')),
                    const SizedBox(width: AppSpacing.xs),
                    _WalletStatusPill(
                      label:
                          ready ? context.tr('Active') : context.tr('Optional'),
                      emphasized: ready,
                    ),
                  ],
                ),
                Text(
                  ready
                      ? context.tr(
                          '{p0} balances · Convert, deposit, and withdraw',
                          {'p0': data?.balances.length ?? 0})
                      : context.tr('Exchange account setup in progress'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _TransferProgressList extends StatelessWidget {
  const _TransferProgressList({
    required this.transfers,
    required this.outflowsEnabled,
  });

  final List<BoomFiTransfer> transfers;
  final bool outflowsEnabled;

  @override
  Widget build(BuildContext context) {
    final visible =
        transfers.where((transfer) => !_isFinished(transfer)).toList();
    if (visible.isEmpty) {
      if (context.isExampleTheme) {
        // Nothing to do is good news, so it reads as a settled fact in the
        // success ink rather than as an empty bucket with a call to action.
        return ExampleGlassPanel(
          radius: 16,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm + 2,
            vertical: AppSpacing.sm + 2,
          ),
          child: Row(
            children: [
              ExampleIconTile(
                icon: Icons.check_circle_outline_rounded,
                color: ExamplePalette.of(context).success,
                size: 32,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  context.tr(
                      'Every transfer has settled. Nothing needs your attention.'),
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return NeoSurfaceCard(
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline_rounded),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
                child:
                    Text(context.tr('No transfers currently need attention.'))),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          _TransferProgressCard(
            transfer: visible[index],
            outflowsEnabled: outflowsEnabled,
          ),
          if (index != visible.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }

  static bool _isFinished(BoomFiTransfer transfer) {
    final status = transfer.status.toLowerCase();
    return status == 'completed' ||
        status == 'settled' ||
        status == 'cancelled';
  }
}

class _TransferProgressCard extends ConsumerWidget {
  const _TransferProgressCard({
    required this.transfer,
    required this.outflowsEnabled,
  });

  final BoomFiTransfer transfer;
  final bool outflowsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stage = _transferStage(transfer.status);
    final needsAttention = transfer.needsFundsDecision ||
        transfer.needsQuoteDecision ||
        transfer.status.toLowerCase().contains('error') ||
        transfer.status.toLowerCase().contains('failed');
    final direction = _transferDirection(transfer.direction);
    final isExample = context.isExampleTheme;
    final parsedAmount = double.tryParse(transfer.cryptoAmount);
    return NeoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isExample)
                ExampleCurrencyAvatar(code: transfer.cryptoCurrency, size: 34)
              else
                CurrencyLogo(
                  symbol: transfer.cryptoCurrency,
                  size: 34,
                  fallbackIcon: Icons.currency_exchange_rounded,
                ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Tabular figures, so a column of transfers lines up its
                    // decimal points with the balances above it instead of
                    // drifting one glyph width per row.
                    if (isExample && parsedAmount != null)
                      ExampleAmount(
                        amount: parsedAmount,
                        currency: transfer.cryptoCurrency,
                        size: ExampleAmountSize.small,
                        code: ExampleAmountCode.never,
                      )
                    else
                      Text(
                        '${_compactTransferAmount(transfer.cryptoAmount)} ${transfer.cryptoCurrency}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    Text(
                      direction,
                      style: isExample
                          ? TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: ExampleInk.tertiary(context),
                            )
                          : Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _WalletStatusPill(
                label: needsAttention
                    ? context.tr('Action needed')
                    : friendlyStatus(transfer.status),
                emphasized: needsAttention,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _TransferTimeline(stage: stage, attention: needsAttention),
          if (transfer.completionMessage.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              transfer.completionMessage,
              style: isExample
                  ? TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: ExampleInk.secondary(context),
                    )
                  : Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (transfer.needsQuoteDecision && outflowsEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                FilledButton(
                  style: isExample ? _transferDecisionStyle(context) : null,
                  onPressed: () => _decideTransfer(
                    context,
                    ref,
                    transfer.id,
                    'approve',
                  ),
                  child: Text(context.tr('Approve quote')),
                ),
                OutlinedButton(
                  style: isExample ? _transferOutlineStyle(context) : null,
                  onPressed: () => _decideTransfer(
                    context,
                    ref,
                    transfer.id,
                    'decline',
                  ),
                  child: Text(context.tr('Decline')),
                ),
              ],
            ),
          ],
          if (transfer.needsFundsDecision && outflowsEnabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton(
                  style: isExample ? _transferOutlineStyle(context) : null,
                  onPressed: () => _decideTransfer(
                    context,
                    ref,
                    transfer.id,
                    'keep',
                  ),
                  child: Text(context.tr('Keep in Exchange')),
                ),
                FilledButton(
                  style: isExample ? _transferDecisionStyle(context) : null,
                  onPressed: () => _decideTransfer(
                    context,
                    ref,
                    transfer.id,
                    'return',
                  ),
                  child: Text(context.tr('Return funds')),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton(
              style: isExample ? _transferOutlineStyle(context) : null,
              onPressed: () => context.push('/transactions'),
              child: Text(context.tr('View details')),
            ),
          ),
        ],
      ),
    );
  }
}

/// The affirmative decision inside a transfer card.
///
/// Deliberately *not* [ExampleGlassButton]: the glass CTA earns its authority
/// by being rare, and a list of three pending transfers would put three of
/// them on one screen next to the Exchange panel's own. This is the same
/// silhouette as every other Example control — 44 pt floor, 12 px radius —
/// on the theme's own fill.
ButtonStyle _transferDecisionStyle(BuildContext context) =>
    FilledButton.styleFrom(
      minimumSize: const Size(0, 44),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

/// Its paired second choice: the same silhouette, unfilled. The edge is the
/// *control* side rather than the structural hairline — Decline, Keep in
/// Exchange and View details are all operated, and 1.4.11 asks 3:1 of a
/// boundary the user is meant to aim at.
ButtonStyle _transferOutlineStyle(BuildContext context) =>
    OutlinedButton.styleFrom(
      minimumSize: const Size(0, 44),
      foregroundColor: ExampleInk.primary(context),
      side: ExampleBorders.controlSideOf(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

Future<void> _decideTransfer(
  BuildContext context,
  WidgetRef ref,
  int id,
  String decision,
) async {
  try {
    final result = await ref
        .read(mobilePlatformApiProvider)
        .decideExchangeTransfer(id, decision);
    ref.invalidate(exchangeTransfersProvider);
    ref.invalidate(exchangeOverviewProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
    }
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error.toString())),
    );
  }
}

class _TransferTimeline extends StatelessWidget {
  const _TransferTimeline({required this.stage, required this.attention});

  final int stage;
  final bool attention;

  static const labels = [
    'Sent from\nCrypto cards',
    'Received by\nExchange',
    'Converting',
    'Sent to\nFiat account',
  ];

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final colors = Theme.of(context).colorScheme;
    final palette = ExamplePalette.of(context);
    // Example resolves every one of these by role, so the meter is legible on
    // paper as well as on night; the non-Example branch keeps the exact
    // colorScheme values it always painted.
    final done =
        isExample ? ExampleInk.accent(context, palette.accent) : colors.primary;
    final onDone = isExample ? palette.onFill : colors.onPrimary;
    final rest = isExample ? palette.borderSubtle : colors.outlineVariant;
    final wellFill = isExample ? ExampleSurface.of(context, 2) : colors.surface;
    final alert =
        isExample ? ExampleInk.accent(context, palette.warning) : colors.error;
    final quiet =
        isExample ? ExampleInk.secondary(context) : colors.onSurfaceVariant;
    return Semantics(
      label: 'Transfer step ${stage.clamp(1, labels.length)} of '
          '${labels.length}',
      excludeSemantics: true,
      child: Column(
        children: [
          Row(
            children: [
              for (var index = 0; index < labels.length; index++) ...[
                if (index > 0)
                  Expanded(
                    child: Container(
                      height: 2,
                      color: index <= stage ? done : rest,
                    ),
                  ),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: index < stage ? done : wellFill,
                    border: Border.all(
                      width: 2,
                      color: index <= stage
                          ? (attention && index == stage ? alert : done)
                          : rest,
                    ),
                  ),
                  child: index < stage
                      ? Icon(Icons.check_rounded, color: onDone, size: 17)
                      : Text(
                          '${index + 1}',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: index == stage
                                        ? (attention ? alert : done)
                                        : quiet,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 7),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final label in labels)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          // 9 px was unreadable at any contrast ratio. 10.5
                          // on the secondary ink clears the 4.5:1 floor in
                          // both themes and still fits four columns at 375.
                          fontSize: isExample ? 10.5 : 9,
                          height: isExample ? 1.25 : null,
                          color: quiet,
                        ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WalletStatusPill extends StatelessWidget {
  const _WalletStatusPill({required this.label, required this.emphasized});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      // The shared pill, so a transfer's status reads as the same object as
      // a card's or an account's. Warning rather than danger: a transfer that
      // needs a decision is waiting on the customer, not broken.
      final palette = ExamplePalette.of(context);
      return ExamplePill(
        label: label,
        color: emphasized ? palette.warning : palette.textTertiary,
        dot: emphasized,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final color = emphasized ? colors.primary : colors.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

int _transferStage(String status) {
  final normalized = status.toLowerCase();
  if (normalized.contains('complete') || normalized.contains('settled')) {
    return 4;
  }
  if (normalized.contains('convert') || normalized.contains('quote')) return 2;
  if (normalized.contains('deposit') ||
      normalized.contains('received') ||
      normalized.contains('fund')) {
    return 1;
  }
  return 1;
}

String _transferDirection(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('equals') && normalized.indexOf('equals') == 0) {
    return 'Fiat account to crypto cards';
  }
  return 'Crypto cards to fiat account';
}

String _compactTransferAmount(String value) {
  final parsed = double.tryParse(value);
  return parsed == null ? value : _walletAmount(parsed);
}

String _walletAmount(double value, [String symbol = 'BTC']) =>
    Money.formatAmount(symbol, value)
        .replaceFirst(' ${symbol.toUpperCase()}', '');

// ignore: unused_element
void _showWalletAccountsSheet(
  BuildContext context, {
  required List<HoppaWalletAsset> wallets,
  required List<HoppaWalletAsset> addresses,
  required bool withdrawalsEnabled,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      maxChildSize: .94,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Text(context.tr('Crypto card balances'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          _WalletOverview(
            wallets: wallets,
            addresses: addresses,
            withdrawalsEnabled: withdrawalsEnabled,
          ),
        ],
      ),
    ),
  );
}

class _WalletOverview extends StatelessWidget {
  const _WalletOverview({
    required this.wallets,
    required this.addresses,
    required this.withdrawalsEnabled,
  });

  final List<HoppaWalletAsset> wallets;
  final List<HoppaWalletAsset> addresses;
  final bool withdrawalsEnabled;

  @override
  Widget build(BuildContext context) {
    final walletSymbols = wallets.map((wallet) => wallet.symbol).toSet();
    final displayWallets = [
      ...wallets,
      ...addresses.where((address) => !walletSymbols.contains(address.symbol)),
    ];
    final topUpSources = wallets
        .where((wallet) =>
            _topUpSourceSymbols.contains(wallet.symbol.toUpperCase()))
        .toList();

    if (displayWallets.isEmpty) {
      return EmptyState(
        title: context.tr('No wallets yet'),
        message: context.tr('Wallet balances will appear after provider sync.'),
        icon: Icons.donut_large,
      );
    }

    return Column(
      children: [
        for (final wallet in displayWallets)
          _WalletAssetCard(
            asset: wallet,
            depositAddresses: addresses
                .where((address) => address.symbol == wallet.symbol)
                .toList(),
            topUpSources: topUpSources,
            withdrawalsEnabled: withdrawalsEnabled,
          ),
      ],
    );
  }
}

class _WalletAssetCard extends ConsumerWidget {
  const _WalletAssetCard({
    required this.asset,
    required this.depositAddresses,
    required this.topUpSources,
    required this.withdrawalsEnabled,
  });

  final HoppaWalletAsset asset;
  final List<HoppaWalletAsset> depositAddresses;
  final List<HoppaWalletAsset> topUpSources;
  final bool withdrawalsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);
    final canDeposit = depositAddresses.isNotEmpty;
    final canTopUp = asset.canTopUp && asset.walletId.isNotEmpty;
    final canConvert = asset.canConvert;
    final canWithdraw = withdrawalsEnabled &&
        asset.amount > 0 &&
        const {'USDC', 'USDT'}.contains(asset.symbol.toUpperCase());

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: NeoSurfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CurrencyLogo(
                  symbol: asset.symbol,
                  fallbackColor: asset.tint,
                  fallbackIcon: asset.symbol == 'USD'
                      ? Icons.account_balance_wallet_outlined
                      : Icons.token_outlined,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('{p0} Wallet', {'p0': asset.symbol}),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '${asset.amount.toStringAsFixed(2)} ${asset.symbol}',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              asset.symbol == 'USD'
                                  ? context.tr('Your USD wallet')
                                  : asset.hasNetwork
                                      ? context.tr('Crypto asset · {p0}',
                                          {'p0': asset.network})
                                      : context.tr('Crypto asset'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                          if (asset.hasFiatValue)
                            Text(
                              _money('EUR', asset.fiatValue),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
            if (canTopUp || canDeposit || canConvert || canWithdraw) ...[
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  if (canTopUp)
                    Expanded(
                      child: _WalletActionButton(
                        onPressed: action.isLoading
                            ? null
                            : () => _showTopUpDialog(
                                  context,
                                  ref,
                                  asset,
                                  topUpSources,
                                ),
                        icon: Icons.arrow_upward_rounded,
                        label: context.tr('Move to USD wallet'),
                      ),
                    ),
                  if (canDeposit)
                    Expanded(
                      child: _WalletActionButton(
                        onPressed: () => _showDepositAddressesSheet(
                          context,
                          asset,
                          depositAddresses,
                        ),
                        icon: Icons.qr_code_2_rounded,
                        label: context.tr('Deposit'),
                      ),
                    ),
                  if (canConvert)
                    Expanded(
                      child: _WalletActionButton(
                        onPressed: action.isLoading
                            ? null
                            : () => _showConvertDialog(
                                  context,
                                  ref,
                                  asset,
                                  _convertTargetSymbols,
                                ),
                        icon: Icons.swap_vert_rounded,
                        label: context.tr('Move to crypto wallet'),
                      ),
                    ),
                  if (canWithdraw)
                    Expanded(
                      child: _WalletActionButton(
                        onPressed: action.isLoading
                            ? null
                            : () => showCryptoWithdrawalDialog(
                                  context,
                                  asset: asset,
                                ),
                        icon: Icons.north_east_rounded,
                        label: context.tr('Withdraw'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WalletActionButton extends StatelessWidget {
  const _WalletActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          textStyle: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label, maxLines: 1),
        ),
      );
}

class _BudgetList extends ConsumerWidget {
  const _BudgetList({
    required this.budgets,
    required this.disclosure,
    this.showCreateButton = true,
  });

  final List<PlatformResource> budgets;
  final String disclosure;
  final bool showCreateButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equalsBudgets = _equalsBudgetAccounts(budgets);
    final displayBudgets = equalsBudgets.isEmpty ? budgets : equalsBudgets;
    final action = ref.watch(platformActionControllerProvider);

    if (displayBudgets.isEmpty) {
      return EmptyState(
        title: context.tr('No budgets yet'),
        message: context.tr('Create a fiat budget to organize card spending.'),
        icon: Icons.savings_outlined,
        action: showCreateButton
            ? FilledButton.icon(
                onPressed: action.isLoading
                    ? null
                    : () => showCreateEqualsBudgetDialog(context, ref),
                icon: const Icon(Icons.add),
                label: Text(context.tr('Create budget')),
              )
            : null,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showCreateButton) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: action.isLoading
                  ? null
                  : () => showCreateEqualsBudgetDialog(context, ref),
              icon: const Icon(Icons.add),
              label: Text(context.tr('Create budget')),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (var index = 0; index < displayBudgets.length; index++)
          _BudgetCard(
            budget: displayBudgets[index],
            equalsBudgets: equalsBudgets,
            action: action,
            disclosure: disclosure,
          ),
      ],
    );
  }
}

class _ExampleBudgetList extends ConsumerWidget {
  const _ExampleBudgetList({
    required this.budgets,
    required this.disclosure,
    this.selectedCurrency = '',
  });

  final List<PlatformResource> budgets;
  final String disclosure;
  final String selectedCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final equalsBudgets = _equalsBudgetAccounts(budgets);
    final displayBudgets = equalsBudgets.isEmpty ? budgets : equalsBudgets;
    final primaryBudget = displayBudgets.firstWhere(
      _isEqualsMainBudget,
      orElse: () => displayBudgets.first,
    );
    final valuationRates =
        ref.watch(portfolioEstimateProvider).valueOrNull?.valuationRates ??
            const <String, double>{};
    final accountRows =
        _budgetBalanceRows(primaryBudget, valuationRates: valuationRates);
    final receivingAccounts = receivingAccountsFromResources(
      ref.watch(equalsBankingInfoProvider).valueOrNull ?? const [],
    );
    String identity(PlatformResource budget, {String? currency}) =>
        receivingAccountForBudget(budget, receivingAccounts, currency: currency)
            ?.maskedIdentifier ??
        '';
    final otherBudgets = displayBudgets
        .where((budget) => _budgetId(budget) != _budgetId(primaryBudget))
        .where((budget) =>
            selectedCurrency.isEmpty ||
            _budgetCurrencies(budget).contains(selectedCurrency) ||
            _budgetBalanceRows(budget)
                .any((row) => row.currency == selectedCurrency))
        .toList();
    final action = ref.watch(platformActionControllerProvider);

    Widget accountCard(
      _BudgetBalanceRow? row,
      int index, {
      required bool compactDesktop,
    }) =>
        _ExampleAccountCard(
          currency: row?.currency ?? '',
          title: _accountTitle(
            row == null
                ? _budgetTitle(primaryBudget)
                : _accountDisplayName(row.currency),
            identity(primaryBudget, currency: row?.currency),
          ),
          subtitle: context
              .tr('Fiat account · {p0}', {'p0': _budgetTitle(primaryBudget)}),
          amount: row == null ? '—' : _money(row.currency, row.amount),
          amountValue: row?.amount,
          onDetails: () => _showWalletBudgetDetails(
            context,
            budget: primaryBudget,
            budgets: displayBudgets,
            balanceRows: accountRows,
            disclosure: disclosure,
            selectedCurrency: row?.currency ?? selectedCurrency,
          ),
          onPay: () => context.go(
            '/money/pay?budgetId=${Uri.encodeQueryComponent(_budgetId(primaryBudget))}',
          ),
          onPayees: () => context.go('/money/payees'),
          compactDesktop: compactDesktop,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 820;
        final rows = accountRows.isEmpty && selectedCurrency.isEmpty
            ? <_BudgetBalanceRow?>[null]
            : accountRows
                .where((row) =>
                    selectedCurrency.isEmpty ||
                    row.currency == selectedCurrency)
                .cast<_BudgetBalanceRow?>()
                .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (rows.isEmpty && otherBudgets.isEmpty)
              ExampleEmptyState(
                title:
                    context.tr('No accounts in {p0}', {'p0': selectedCurrency}),
                body: context.tr(
                    'Choose another currency or show all account currencies.'),
                compact: true,
              ),
            if (desktop)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (var index = 0; index < rows.length; index++)
                    SizedBox(
                      width: (constraints.maxWidth - 12) / 2,
                      child: accountCard(
                        rows[index],
                        index,
                        compactDesktop: true,
                      ),
                    ),
                ],
              )
            else
              for (var index = 0; index < rows.length; index++) ...[
                accountCard(
                  rows[index],
                  index,
                  compactDesktop: false,
                ),
                if (index != rows.length - 1) const SizedBox(height: 8),
              ],
            if (otherBudgets.isNotEmpty) ...[
              const SizedBox(height: 16),
              ExampleSectionTitle(
                title: context.tr('Budgets'),
                action: context.tr('Create budget'),
                onAction: action.isLoading
                    ? null
                    : () => showCreateEqualsBudgetDialog(context, ref),
              ),
              const SizedBox(height: 8),
              for (var index = 0; index < otherBudgets.length; index++) ...[
                _ExampleBudgetRow(
                  budget: otherBudgets[index],
                  maskedIdentifier:
                      identity(otherBudgets[index], currency: selectedCurrency),
                  selectedCurrency: selectedCurrency,
                  onTap: () => _showWalletBudgetDetails(
                    context,
                    budget: otherBudgets[index],
                    budgets: displayBudgets,
                    balanceRows: _budgetBalanceRows(otherBudgets[index]),
                    disclosure: disclosure,
                    selectedCurrency: selectedCurrency,
                  ),
                ),
                if (index != otherBudgets.length - 1) const SizedBox(height: 6),
              ],
            ],
          ],
        );
      },
    );
  }
}

/// One secondary budget in the accounts list.
///
/// Extracted from `_ExampleBudgetList` for three reasons, all of which were
/// defects in the inline version:
///
/// * The balance rows were recomputed five times per budget, once per read,
///   inside a loop that runs once per budget. They are parsed out of the
///   resource's metadata map, so that is five parses a row.
/// * The figure sat in a `Flexible` beside an `Expanded` title, which splits
///   the free space 1:1 whatever the two actually need — so a budget called
///   "Contractor payments Q3" ellipsised at half the row while a nine
///   character balance sat in a hundred points of its own dead space. The
///   figure now takes its natural width (capped, so a very large balance
///   still ellipsises rather than overflowing) and the title takes the rest.
/// * The money was a hand-styled `Text`. It is the only fiat figure on the
///   route that was not a [ExampleAmount], so it was the only one whose
///   symbol, grouping and Private Mode masking came from somewhere else.
class _ExampleBudgetRow extends StatelessWidget {
  const _ExampleBudgetRow({
    required this.budget,
    required this.onTap,
    this.maskedIdentifier = '',
    this.selectedCurrency = '',
  });

  final PlatformResource budget;
  final VoidCallback onTap;
  final String maskedIdentifier;
  final String selectedCurrency;

  /// A fiat balance wider than this is being truncated on purpose; below it
  /// the figure keeps its natural width and gives the rest to the title.
  static const double _figureMaxWidth = 132;

  @override
  Widget build(BuildContext context) {
    final rows = _budgetBalanceRows(budget)
        .where((row) =>
            selectedCurrency.isEmpty || row.currency == selectedCurrency)
        .toList();
    final first = rows.firstOrNull;
    return ExampleGlassPanel(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      onTap: onTap,
      child: Row(
        children: [
          ExampleIconTile(
            icon: Icons.account_balance_outlined,
            color: ExamplePalette.of(context).accent,
            size: 32,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _accountTitle(_budgetTitle(budget), maskedIdentifier),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                  ),
                ),
                Text(
                  rows.length > 1
                      ? context.tr('Fiat account · Multi-currency')
                      : context.tr('Fiat account · {p0}',
                          {'p0': first?.currency ?? 'Budget'}),
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
          const SizedBox(width: AppSpacing.xs),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _figureMaxWidth),
            child: ExampleAmount(
              amount: first?.amount,
              currency: first?.currency ?? '',
              size: ExampleAmountSize.inline,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

String _accountDisplayName(String currency) => switch (currency.toUpperCase()) {
      'EUR' => 'Euro Account',
      'GBP' => 'Sterling Account',
      final code => '$code Account',
    };

String _accountTitle(String title, String maskedIdentifier) =>
    maskedIdentifier.isEmpty ? title : '$title · $maskedIdentifier';

class _ExampleAccountCard extends StatelessWidget {
  const _ExampleAccountCard({
    required this.currency,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onDetails,
    required this.onPay,
    required this.onPayees,
    required this.compactDesktop,
    this.amountValue,
  });

  final String currency;
  final String title;
  final String subtitle;

  /// Pre-formatted fallback, used when there is no funded balance to show.
  final String amount;

  /// The figure itself. Non-null means the balance renders through
  /// [ExampleAmount] — tabular figures, a lighter currency code and a smaller
  /// fraction — so a column of accounts lines up on the decimal point.
  final double? amountValue;
  final VoidCallback onDetails;
  final VoidCallback onPay;
  final VoidCallback onPayees;
  final bool compactDesktop;

  @override
  Widget build(BuildContext context) {
    if (compactDesktop) {
      return ExampleGlassPanel(
        radius: 18,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onDetails,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                ExampleCurrencyAvatar(code: currency, size: 34),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: _fadedInk(context, .56),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (amountValue == null)
                      Text(
                        amount,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: ExampleInk.primary(context),
                            ),
                      )
                    else
                      ExampleAmount(
                        amount: amountValue,
                        currency: currency,
                        size: ExampleAmountSize.small,
                        code: ExampleAmountCode.never,
                        textAlign: TextAlign.end,
                      ),
                    Text(
                      context.tr('Active'),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: ExampleInk.accent(
                              context,
                              ExamplePalette.of(context).success,
                            ),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _ExampleDesktopAccountAction(
                  label: context.tr('Details'),
                  onTap: onDetails,
                ),
                _ExampleDesktopAccountAction(
                    label: context.tr('Pay'), onTap: onPay),
                _ExampleDesktopAccountAction(
                  label: context.tr('Payees'),
                  onTap: onPayees,
                ),
              ],
            ),
          ],
        ),
      );
    }
    return ExampleGlassPanel(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      onTap: onDetails,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ExampleCurrencyAvatar(code: currency, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                    Text(
                      subtitle,
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
              ExamplePill(
                  label: context.tr('Active'),
                  color: ExamplePalette.of(context).success),
            ],
          ),
          const SizedBox(height: 8),
          if (amountValue == null)
            Text(
              amount,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -.3,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            )
          else
            ExampleAmount(
              amount: amountValue,
              currency: currency,
              size: ExampleAmountSize.medium,
              code: ExampleAmountCode.never,
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _ExampleAccountAction(
                label: context.tr('Account details'),
                onTap: onDetails,
              ),
              _ExampleAccountAction(label: context.tr('Pay'), onTap: onPay),
              _ExampleAccountAction(
                  label: context.tr('Payees'), onTap: onPayees),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExampleDesktopAccountAction extends StatelessWidget {
  const _ExampleDesktopAccountAction({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
        style: TextButton.styleFrom(
          // 30 pt with a compact density landed at about 26 on the screen:
          // three of the account's four controls sat under the 44 pt floor.
          minimumSize: const Size(48, 44),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: ExampleInk.accent(
            context,
            ExamplePalette.of(context).accent,
          ),
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        onPressed: onTap,
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      );
}

class _ExampleAccountAction extends StatelessWidget {
  const _ExampleAccountAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ConstrainedBox(
            // Was an 11 px label in 10/5 of padding: a 21 pt target, half the
            // floor, on the three controls a fiat account actually uses. The
            // pill now *is* 44 tall rather than carrying an invisible hit box,
            // so the three of them read as one action bar under the balance.
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.budget,
    required this.equalsBudgets,
    required this.action,
    required this.disclosure,
  });

  final PlatformResource budget;
  final List<PlatformResource> equalsBudgets;
  final AsyncValue<ActionResult?> action;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    final balanceRows = _budgetBalanceRows(budget);
    final listedBalanceRows = balanceRows.take(3).toList();
    final colors = Theme.of(context).colorScheme;

    return Consumer(
      builder: (context, ref, child) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: NeoSurfaceCard(
            onTap: () => _showWalletBudgetDetails(
              context,
              budget: budget,
              budgets: equalsBudgets,
              balanceRows: balanceRows,
              disclosure: disclosure,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: colors.secondary.withValues(alpha: .16),
                      foregroundColor: colors.secondary,
                      child: const Icon(Icons.account_balance_rounded),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _budgetTitle(budget),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isEqualsMainBudget(budget)
                                ? context.tr('Account')
                                : context.tr('Budget'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (listedBalanceRows.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (final row in listedBalanceRows)
                            Text(
                              _money(row.currency, row.amount),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(width: AppSpacing.xs),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                const SizedBox(height: 12),
                _BudgetCardActions(
                  budget: budget,
                  budgets: equalsBudgets,
                  balanceRows: balanceRows,
                  disclosure: disclosure,
                  transferBusy: action.isLoading,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BudgetCardActions extends ConsumerStatefulWidget {
  const _BudgetCardActions({
    required this.budget,
    required this.budgets,
    required this.balanceRows,
    required this.disclosure,
    required this.transferBusy,
  });

  final PlatformResource budget;
  final List<PlatformResource> budgets;
  final List<_BudgetBalanceRow> balanceRows;
  final String disclosure;
  final bool transferBusy;

  @override
  ConsumerState<_BudgetCardActions> createState() => _BudgetCardActionsState();
}

class _BudgetCardActionsState extends ConsumerState<_BudgetCardActions> {
  bool _showLatest = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _BudgetActionButton(
                onPressed: () => _openBudgetTransactions(
                  context,
                  widget.budget,
                ),
                icon: Icons.receipt_long_outlined,
                label: context.tr('Transactions'),
              ),
            ),
            Expanded(
              child: _BudgetActionButton(
                onPressed: () => _showWalletBudgetDetails(
                  context,
                  budget: widget.budget,
                  budgets: widget.budgets,
                  balanceRows: widget.balanceRows,
                  disclosure: widget.disclosure,
                ),
                icon: Icons.info_outline_rounded,
                label: context.tr('Details'),
              ),
            ),
            Expanded(
              child: _BudgetActionButton(
                onPressed: () => setState(() => _showLatest = !_showLatest),
                icon: _showLatest
                    ? Icons.expand_less_rounded
                    : Icons.history_rounded,
                label: _showLatest ? context.tr('Hide') : context.tr('Latest'),
              ),
            ),
            if (!_isEqualsMainBudget(widget.budget))
              Expanded(
                child: _BudgetActionButton(
                  foregroundColor: colors.secondary,
                  onPressed: widget.transferBusy ||
                          !_hasBudgetTransferSource(
                            widget.budget,
                            widget.budgets,
                          )
                      ? null
                      : () => _showFundBudgetDialog(
                            context,
                            ref,
                            targetBudget: widget.budget,
                            budgets: widget.budgets,
                          ),
                  icon: Icons.account_balance_wallet,
                  label: context.tr('Fund'),
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
          ],
        ),
        if (_showLatest) ...[
          const SizedBox(height: AppSpacing.sm),
          _BudgetLatestTransactions(
            budget: widget.budget,
            onHide: () => setState(() => _showLatest = false),
          ),
        ],
      ],
    );
  }
}

class _BudgetActionButton extends StatelessWidget {
  const _BudgetActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.foregroundColor,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: foregroundColor,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: onPressed,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetLatestTransactions extends ConsumerWidget {
  const _BudgetLatestTransactions({
    required this.budget,
    required this.onHide,
    this.currency = '',
  });

  final PlatformResource budget;
  final VoidCallback onHide;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scopeIds = _budgetTransactionScopeIds(budget);
    final isExample = context.isExampleTheme;
    if (scopeIds.isEmpty) {
      return _LatestTransactionsFrame(
        onMore: null,
        onHide: onHide,
        // Not an error and not empty: the budget simply has no transaction
        // account behind it, and there is nothing the customer can retry. Say
        // that, and say who can change it.
        child: isExample
            ? ExampleEmptyState(
                icon: Icons.link_off_rounded,
                title: context.tr('No transaction account linked'),
                body: context.tr(
                    'This budget has no account to draw transactions from. Your administrator can link one.'),
                compact: true,
              )
            : Text(
                context.tr('No transaction account is linked to this budget.')),
      );
    }

    final transactions = ref.watch(activityTransactionsProvider);
    final normalizedCurrency = currency.trim().toUpperCase();
    // The same rows Activity draws: duplicate provider views folded and
    // each fee on the row it charges.
    final latest =
        groupCardFees(transactions.valueOrNull ?? const <LedgerTransaction>[])
            .where((item) => transactionMatchesScope(item, scopeIds))
            .where((item) =>
                normalizedCurrency.isEmpty ||
                item.displayAmount.currency.trim().toUpperCase() ==
                    normalizedCurrency)
            .toList()
          ..sort((left, right) {
            if (left.hasBookedAt != right.hasBookedAt) {
              return left.hasBookedAt ? -1 : 1;
            }
            return right.bookedAt.compareTo(left.bookedAt);
          });
    final visible = latest.take(5).toList();
    return _LatestTransactionsFrame(
      onMore: () =>
          _openBudgetTransactions(context, budget, currency: currency),
      onHide: onHide,
      exportAction: TransactionPdfExportButton(
        key: const ValueKey('budget-latest-transactions-export'),
        label: isExample ? context.tr('Print') : null,
        transactions:
            transactions.isLoading || transactions.hasError ? null : visible,
        filters: [
          'Account: ${normalizedCurrency.isEmpty ? _budgetTitle(budget) : _accountDisplayName(normalizedCurrency)}',
          if (normalizedCurrency.isNotEmpty) 'Currency: $normalizedCurrency',
          'Latest transactions shown',
        ],
        identityFor: (transaction) =>
            ref.read(transactionIdentityProvider(transaction)),
      ),
      child: transactions.when(
        // Two rows shaped like the two rows that are landing, so the panel
        // holds its height and the sheet below it does not jump. A spinner in
        // a 96 px frame tells the customer nothing except that something is
        // happening somewhere.
        loading: () => isExample
            ? const _BudgetTransactionsSkeleton()
            : const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(child: AppProgressIndicator()),
              ),
        error: (error, stackTrace) => isExample
            ? ExampleErrorState(
                title: context.tr('Transactions did not load'),
                error: error,
                compact: true,
                onRetry: () => ref.invalidate(activityTransactionsProvider),
              )
            : Text(friendlyErrorMessage(error)),
        data: (items) {
          if (visible.isEmpty) {
            return isExample
                ? ExampleEmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: context.tr('No transactions yet'),
                    body: context.tr(
                        'Card spend and transfers on this budget will appear here.'),
                    compact: true,
                  )
                : Text(context.tr('No transactions yet.'));
          }
          return Column(
            children: [
              for (final transaction in visible)
                InkWell(
                  onTap: () => _openBudgetHistoryRoute(
                    context,
                    '/transactions/${Uri.encodeComponent(transaction.id)}',
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ExampleIconTile(
                          icon: cardListAmount(transaction).decimalAmount >= 0
                              ? Icons.south_rounded
                              : Icons.north_east_rounded,
                          color: cardListAmount(transaction).decimalAmount >= 0
                              ? ExamplePalette.of(context).success
                              : ExamplePalette.of(context).accent,
                          size: 30,
                          radius: 9,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                transactionDisplayTitle(transaction.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: ExampleInk.primary(context),
                                ),
                              ),
                              Text(
                                '${transaction.displayType} · ${transactionDisplayStatus(transaction.status.isEmpty ? transaction.subtitle : transaction.status)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: ExampleInk.tertiary(context),
                                ),
                              ),
                              if (cardFeeCaption(transaction)
                                  case final caption?)
                                Text(
                                  caption,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: ExampleInk.tertiary(context),
                                  ),
                                ),
                              if (ref.watch(
                                      transactionIdentityProvider(transaction))
                                  case final String identity)
                                Text(
                                  identity,
                                  key: ValueKey(
                                      'budget-transaction-identity-${transaction.id}'),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: ExampleInk.secondary(context),
                                  ),
                                ),
                              Text(
                                _budgetTransactionTimestamp(
                                    context, transaction),
                                key: ValueKey(
                                    'budget-transaction-time-${transaction.id}'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: ExampleInk.tertiary(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${cardListAmount(transaction).isPositive ? '+' : ''}${cardListAmount(transaction).formatted}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color:
                                  cardListAmount(transaction).decimalAmount >= 0
                                      ? ExamplePalette.of(context).success
                                      : ExampleInk.primary(context),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
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

String _budgetTransactionTimestamp(
  BuildContext context,
  LedgerTransaction transaction,
) {
  if (!transaction.hasBookedAt) return 'Date and time unavailable';
  final localizations = MaterialLocalizations.of(context);
  final date = transaction.bookedAt.toLocal();
  return '${localizations.formatMediumDate(date)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(date), alwaysUse24HourFormat: true)}';
}

/// The two rows that are about to land, at their real height.
///
/// Shape-matched on purpose: 36 pt leading square, a short title line, a
/// shorter caption under it and an amount block on the right, at the same
/// 4 / 8 padding the real rows use. One sheen host for the pair — the alive
/// layer belongs to the block, never to each bar inside it.
class _BudgetTransactionsSkeleton extends StatelessWidget {
  const _BudgetTransactionsSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: context.tr('Loading transactions'),
        child: ExampleSheen.text(
          intensity: ExampleSheenIntensity.soft,
          child: Column(
            children: [
              for (var i = 0; i < 2; i++)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Row(
                    children: [
                      ExampleSkeleton.avatar(size: 36, sheen: false),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExampleSkeleton.line(width: 132, sheen: false),
                            SizedBox(height: 6),
                            ExampleSkeleton.line(
                              width: 76,
                              height: 10,
                              sheen: false,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: AppSpacing.sm),
                      ExampleSkeleton.line(width: 62, sheen: false),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}

class _LatestTransactionsFrame extends StatelessWidget {
  const _LatestTransactionsFrame({
    required this.child,
    required this.onMore,
    required this.onHide,
    this.exportAction,
  });

  final Widget child;
  final VoidCallback? onMore;
  final VoidCallback onHide;
  final Widget? exportAction;

  @override
  Widget build(BuildContext context) => Material(
        color: context.isExampleTheme
            ? _panelFill(context, .6)
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: context.isExampleTheme
                ? _hairline(context, .14)
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              child,
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (exportAction != null) ...[
                    exportAction!,
                    const Spacer(),
                  ],
                  if (onMore != null)
                    TextButton(
                      style: _frameActionStyle(context),
                      onPressed: onMore,
                      child: Text(context.tr('More')),
                    ),
                  if (context.isExampleTheme && onMore != null)
                    Container(
                        width: 1,
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: _hairline(context, .14)),
                  TextButton(
                    style: _frameActionStyle(context),
                    onPressed: onHide,
                    child: Text(context.tr('Hide')),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}

/// Material's text button floors at 40 pt tall. Two of them sit side by side
/// in the footer of a panel a customer taps with a thumb, so on Example they
/// take the 44 pt floor and the secondary ink that goes with a footer action.
ButtonStyle? _frameActionStyle(BuildContext context) => context.isExampleTheme
    ? TextButton.styleFrom(
        minimumSize: const Size(64, 44),
        foregroundColor: ExamplePalette.of(context).accent,
      )
    : null;

void _showWalletBudgetDetails(
  BuildContext context, {
  required PlatformResource budget,
  required List<PlatformResource> budgets,
  required List<_BudgetBalanceRow> balanceRows,
  required String disclosure,
  String selectedCurrency = '',
}) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => _BudgetDetailsDialog(
      budget: budget,
      budgets: budgets,
      balanceRows: balanceRows,
      disclosure: disclosure,
      selectedCurrency: selectedCurrency,
    ),
  );
}

class _BudgetDetailsDialog extends ConsumerStatefulWidget {
  const _BudgetDetailsDialog({
    required this.budget,
    required this.budgets,
    required this.balanceRows,
    required this.disclosure,
    this.selectedCurrency = '',
  });

  final PlatformResource budget;
  final List<PlatformResource> budgets;
  final List<_BudgetBalanceRow> balanceRows;
  final String disclosure;
  final String selectedCurrency;

  @override
  ConsumerState<_BudgetDetailsDialog> createState() =>
      _BudgetDetailsDialogState();
}

class _BudgetDetailsDialogState extends ConsumerState<_BudgetDetailsDialog> {
  bool _showLatest = true;

  @override
  Widget build(BuildContext context) {
    final currentBudgets = ref.watch(budgetsProvider).valueOrNull;
    final budgets = currentBudgets ?? widget.budgets;
    final budget = budgets
            .where((item) => _budgetId(item) == _budgetId(widget.budget))
            .firstOrNull ??
        widget.budget;
    final selectedCurrency = widget.selectedCurrency.trim().toUpperCase();
    final currencies = selectedCurrency.isEmpty
        ? _budgetCurrencies(budget)
        : [selectedCurrency];
    final balanceRows = (currentBudgets == null
            ? widget.balanceRows
            : _budgetBalanceRows(budget))
        .where((row) =>
            selectedCurrency.isEmpty || row.currency == selectedCurrency)
        .toList();
    final receiving = receivingAccountForBudget(
      budget,
      receivingAccountsFromResources(
        ref.watch(equalsBankingInfoProvider).valueOrNull ?? const [],
      ),
      currency: selectedCurrency,
    );
    final isExample = context.isExampleTheme;
    final size = MediaQuery.sizeOf(context);
    final wide = isExample && size.width >= 700;
    final title = _accountTitle(
      selectedCurrency.isEmpty
          ? _budgetTitle(budget)
          : _accountDisplayName(selectedCurrency),
      receiving?.maskedIdentifier ?? '',
    );
    final subtitle = _isEqualsMainBudget(budget)
        ? context.tr('Account')
        : context.tr('Budget');

    final balancePanel = isExample
        ? ExampleGlassPanel(
            radius: 20,
            borderAlpha: .26,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Available balance'),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (balanceRows.isEmpty)
                        Text(
                          context.tr('No funded balance'),
                          style: TextStyle(color: ExampleInk.primary(context)),
                        )
                      else
                        for (var i = 0; i < balanceRows.length; i++)
                          Text(
                            _money(
                              balanceRows[i].currency,
                              balanceRows[i].amount,
                            ),
                            style: TextStyle(
                              fontSize: i == 0 ? 26 : 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: i == 0 ? -.5 : 0,
                              color: i == 0
                                  ? ExampleInk.primary(context)
                                  : ExampleInk.secondary(context),
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                if (currencies.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final currency in currencies)
                        ExampleCurrencyAvatar(code: currency, size: 26),
                    ],
                  ),
              ],
            ),
          )
        : NeoSurfaceCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('Available balance')),
                      const SizedBox(height: 4),
                      if (balanceRows.isEmpty)
                        Text(context.tr('No funded balance'))
                      else
                        for (final row in balanceRows)
                          Text(
                            _money(row.currency, row.amount),
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                    ],
                  ),
                ),
                if (currencies.isNotEmpty)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(currencies.join(' · ')),
                  ),
              ],
            ),
          );

    void onMove() => _showBudgetMoveOptions(
          context,
          ref,
          budget: budget,
          budgets: budgets,
        );
    final canConvert = canConvertEqualsMoneyBudgets([budget]) &&
        (selectedCurrency.isEmpty ||
            _fundedBudgetBalanceRows(budget)
                .any((row) => row.currency == selectedCurrency));
    final actions = LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxWidth < 520;
      final style = OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 12),
        foregroundColor: isExample ? ExampleInk.primary(context) : null,
        side: isExample ? ExampleBorders.controlSideOf(context) : null,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontSize: compact ? 12 : null,
            ),
      );
      Widget action(String label, IconData icon, VoidCallback? onPressed) {
        final text = Text(context.tr(label), textAlign: TextAlign.center);
        return SizedBox(
          height: 48,
          child: compact
              ? OutlinedButton(style: style, onPressed: onPressed, child: text)
              : OutlinedButton.icon(
                  style: style,
                  onPressed: onPressed,
                  icon: Icon(icon, size: 18),
                  label: text,
                ),
        );
      }

      return Row(
        children: [
          Expanded(
            flex: compact ? 10 : 1,
            child: action('Move', Icons.swap_horiz_rounded, onMove),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: compact ? 12 : 1,
            child: action(
              'Convert',
              Icons.currency_exchange_rounded,
              canConvert
                  ? () => showEqualsMoneyConversionDialog(
                        context,
                        ref,
                        budgets,
                        initialBudgetId: _budgetId(budget),
                        initialSourceCurrency: selectedCurrency,
                      )
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: compact ? 19 : 1,
            child: action('New transaction', Icons.north_east_rounded, () {
              Navigator.of(context).pop();
              context.push(
                Uri(
                  path: '/money/pay',
                  queryParameters: {'budgetId': _budgetId(budget)},
                ).toString(),
              );
            }),
          ),
        ],
      );
    });

    Future<void> refreshHistory() async {
      ref.invalidate(budgetsProvider);
      ref.invalidate(equalsBankingInfoProvider);
      await Future.wait([
        ref.read(budgetsProvider.future),
        ref.read(refreshActivityProvider)(),
      ]);
    }

    final body = RefreshWhenVisible(
      onRefresh: refreshHistory,
      child: RefreshIndicator(
        onRefresh: refreshHistory,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(20, wide ? 8 : 12, 20, wide ? 24 : 100),
          children: [
            if (!wide) ...[
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: ExampleInk.secondary(context)),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            balancePanel,
            const SizedBox(height: AppSpacing.sm),
            actions,
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Latest transactions'),
                    style: isExample
                        ? TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: ExampleInk.primary(context),
                          )
                        : Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                RefreshAction(onRefresh: refreshHistory),
                if (!_showLatest)
                  TextButton(
                    // The last control on this dialog still on Material's 40 pt
                    // floor, and the one its own siblings — the "More" and "Hide"
                    // pair inside the frame it opens — were already lifted off.
                    // A lone "Show" is also nothing to a screen reader, so it
                    // says which list it opens.
                    style: _frameActionStyle(context),
                    onPressed: () => setState(() => _showLatest = true),
                    child: Text(
                      context.tr('Show'),
                      semanticsLabel:
                          context.tr('Show the latest transactions'),
                    ),
                  ),
              ],
            ),
            if (_showLatest) ...[
              const SizedBox(height: 8),
              _BudgetLatestTransactions(
                budget: budget,
                currency: selectedCurrency,
                onHide: () => setState(() => _showLatest = false),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _ReceivingAccountDetailsSection(
              budget: budget,
              budgets: budgets,
              currency: selectedCurrency,
            ),
            const SizedBox(height: 6),
            const SafeguardingStatementButton(
                alignment: Alignment.centerLeft, expanded: true),
          ],
        ),
      ),
    );

    if (wide) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Material(
          color: ExampleSurface.navigationOf(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(
              color: _hairline(context, .16),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            width: 720,
            height: (size.height - 48).clamp(480, 760).toDouble(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: ExampleInk.primary(context),
                              ),
                            ),
                            Text(
                              context
                                  .tr('{p0} · Fiat account', {'p0': subtitle}),
                              style: TextStyle(
                                fontSize: 12,
                                color: ExampleInk.tertiary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: context.tr('Close'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
    }

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          centerTitle: isExample,
          title: Text(context.tr('Budget details')),
          leading: IconButton(
            tooltip: context.tr('Back'),
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              isExample
                  ? Icons.arrow_back_ios_new_rounded
                  : Icons.arrow_back_rounded,
              size: isExample ? 19 : null,
            ),
          ),
        ),
        body: body,
      ),
    );
  }
}

Future<void> showCreateEqualsBudgetDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final nameController = TextEditingController(text: context.tr('Card Budget'));
  final selectedCurrencies = <String>{'GBP'};

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => _FullScreenActionDialog(
        title: Text(context.tr('Create budget')),
        primaryLabel: 'Create budget',
        onPrimary: selectedCurrencies.isEmpty
            ? null
            : () => Navigator.of(context).pop(true),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr(
                    'Set aside money for a card, team, or spending purpose.'),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: nameController,
                decoration:
                    InputDecoration(labelText: context.tr('Budget name')),
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
                  onChanged: (currency, selected) {
                    setDialogState(() {
                      if (selected) {
                        selectedCurrencies.add(currency);
                      } else {
                        selectedCurrencies.remove(currency);
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final name = nameController.text.trim();
  nameController.dispose();
  if (confirmed != true || name.isEmpty || !context.mounted) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.createBudget(
          name: name,
          currencies: _orderedSelectedCurrencies(selectedCurrencies),
        ),
      );
  ref.invalidate(budgetsProvider);
}

class _EqualsCurrencyChecklist extends StatelessWidget {
  const _EqualsCurrencyChecklist({
    required this.selectedCurrencies,
    required this.onChanged,
  });

  final Set<String> selectedCurrencies;
  final void Function(String currency, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListView.builder(
        itemCount: equalsSupportedCurrencyCodes.length,
        itemBuilder: (context, index) {
          final currency = equalsSupportedCurrencyCodes[index];

          return CheckboxListTile(
            dense: true,
            value: selectedCurrencies.contains(currency),
            onChanged: (value) => onChanged(currency, value == true),
            title: Text(currency),
            controlAffinity: ListTileControlAffinity.leading,
          );
        },
      ),
    );
  }
}

List<String> _orderedSelectedCurrencies(Set<String> selectedCurrencies) {
  return [
    for (final currency in equalsSupportedCurrencyCodes)
      if (selectedCurrencies.contains(currency)) currency,
  ];
}

Future<void> _showFundBudgetDialog(
  BuildContext context,
  WidgetRef ref, {
  required PlatformResource targetBudget,
  required List<PlatformResource> budgets,
}) async {
  final sourceBudgets = budgets
      .where(
        (budget) =>
            _budgetId(budget) != _budgetId(targetBudget) &&
            _sharedBudgetCurrencies(budget, targetBudget).isNotEmpty,
      )
      .toList();
  if (sourceBudgets.isEmpty) {
    return;
  }

  var sourceBudgetId = _budgetId(sourceBudgets.first);
  var amountText = '';
  var currency =
      _sharedBudgetCurrencies(sourceBudgets.first, targetBudget).firstOrNull ??
          _budgetCurrencies(targetBudget).firstOrNull ??
          'GBP';

  final submission = await showDialog<_BudgetTransferSubmission>(
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
        final available = _budgetBalanceForCurrency(selectedSource, currency);
        final exceedsBalance =
            available != null && amount.minorUnits > (available * 100).round();

        return _FullScreenActionDialog(
          title:
              Text(context.tr('Fund {p0}', {'p0': _budgetTitle(targetBudget)})),
          primaryLabel: 'Transfer money',
          onPrimary: amount.minorUnits <= 0 || exceedsBalance
              ? null
              : () => Navigator.of(context).pop(
                    _BudgetTransferSubmission(
                      sourceBudgetId: sourceBudgetId,
                      amount: amount,
                    ),
                  ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Move money between your fiat budgets.'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: sourceBudgetId,
                  decoration:
                      InputDecoration(labelText: context.tr('Source budget')),
                  items: [
                    for (final budget in sourceBudgets)
                      DropdownMenuItem(
                        value: _budgetId(budget),
                        child: Text(
                          '${_budgetTitle(budget)} · ${_budgetAvailableSummary(budget)}',
                          overflow: TextOverflow.ellipsis,
                        ),
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
                  decoration: InputDecoration(
                    labelText: context.tr('Amount'),
                    helperText: available == null
                        ? null
                        : context.tr('Available: {p0}',
                            {'p0': _money(currency, available)}),
                    errorText: exceedsBalance
                        ? context.tr('Amount exceeds available balance')
                        : null,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SafeguardingStatementButton(),
              ],
            ),
          ),
        );
      },
    ),
  );

  if (submission == null || !context.mounted) {
    return;
  }

  final sourceBudget = sourceBudgets.firstWhere(
    (budget) => _budgetId(budget) == submission.sourceBudgetId,
    orElse: () => sourceBudgets.first,
  );
  await _executeBudgetTransfer(
    context,
    ref,
    sourceBudget: sourceBudget,
    destinationBudget: targetBudget,
    amount: submission.amount,
  );
}

Future<void> _showBudgetMoveOptions(
  BuildContext context,
  WidgetRef ref, {
  required PlatformResource budget,
  required List<PlatformResource> budgets,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(context.tr('Move money')),
            subtitle:
                Text(context.tr('From {p0}', {'p0': _budgetTitle(budget)})),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_rounded),
            title: Text(context.tr('Between accounts')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(sheetContext).pop('accounts'),
          ),
          ListTile(
            leading: const Icon(Icons.currency_exchange_rounded),
            title: Text(context.tr('To exchange')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(sheetContext).pop('exchange'),
          ),
          ListTile(
            leading: const Icon(Icons.credit_card_rounded),
            title: Text(context.tr('To Crypto Cards Wallet balance')),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(sheetContext).pop('wallet'),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;

  if (choice == 'accounts') {
    await _showMoveBetweenBudgetsDialog(
      context,
      ref,
      sourceBudget: budget,
      budgets: budgets,
    );
    return;
  }

  final router = GoRouter.of(context);
  if (choice == 'exchange') {
    Navigator.of(context).pop();
    router.push(
      Uri(
        path: '/wallets/exchange',
        queryParameters: {'sourceBudgetId': _budgetId(budget)},
      ).toString(),
    );
    return;
  }

  final destination = await _chooseCryptoWalletDestination(context, ref);
  if (destination == null || !context.mounted) return;
  Navigator.of(context).pop();
  router.push(
    Uri(
      path: '/wallets/exchange',
      queryParameters: {
        'sourceBudgetId': _budgetId(budget),
        'destination': destination,
      },
    ).toString(),
  );
}

Future<String?> _chooseCryptoWalletDestination(
  BuildContext context,
  WidgetRef ref,
) async {
  var hasInterlace = false;
  var hasBPay = false;
  try {
    final wallets = await ref.read(hoppaWalletAssetsProvider.future);
    hasInterlace = wallets.any((wallet) => wallet.walletId.isNotEmpty);
  } catch (_) {}
  try {
    hasBPay = (await ref.read(exchangeOverviewProvider.future)).isReady;
  } catch (_) {}
  if (!context.mounted) return null;

  if (!hasInterlace && !hasBPay) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(context.tr('No Crypto Cards Wallet is available.'))),
    );
    return null;
  }

  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(context.tr('Choose wallet destination')),
            subtitle:
                Text(context.tr('Only available destinations are shown.')),
          ),
          if (hasInterlace)
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: Text(context.tr('Crypto card wallet')),
              subtitle: Text(context.tr('FIAT converted to USDC')),
              onTap: () => Navigator.of(sheetContext).pop('interlace'),
            ),
          if (hasBPay)
            ListTile(
              leading: const Icon(Icons.currency_exchange_rounded),
              title: Text(context.tr('BPay Exchange wallet')),
              subtitle: Text(context.tr('Available exchange balances')),
              onTap: () => Navigator.of(sheetContext).pop('bpay'),
            ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
    ),
  );
}

Future<void> _showMoveBetweenBudgetsDialog(
  BuildContext context,
  WidgetRef ref, {
  required PlatformResource sourceBudget,
  required List<PlatformResource> budgets,
}) async {
  final destinations = budgets
      .where((budget) =>
          _budgetId(budget) != _budgetId(sourceBudget) &&
          _sharedBudgetCurrencies(sourceBudget, budget).isNotEmpty)
      .toList();
  if (destinations.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('No compatible destination account.'))),
    );
    return;
  }

  var destinationId = _budgetId(destinations.first);
  var currency =
      _sharedBudgetCurrencies(sourceBudget, destinations.first).first;
  var amountText = '';
  final submission = await showDialog<_BudgetMoveSubmission>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setDialogState) {
        final destination = destinations.firstWhere(
          (item) => _budgetId(item) == destinationId,
          orElse: () => destinations.first,
        );
        final currencies = _sharedBudgetCurrencies(sourceBudget, destination);
        if (!currencies.contains(currency)) currency = currencies.first;
        final amount = _parseMoney(amountText, currency);
        final available = _budgetBalanceForCurrency(sourceBudget, currency);
        final exceeds =
            available != null && amount.minorUnits > (available * 100).round();

        return _FullScreenActionDialog(
          title: Text(
              context.tr('Move from {p0}', {'p0': _budgetTitle(sourceBudget)})),
          primaryLabel: 'Review transfer',
          onPrimary: amount.minorUnits <= 0 || exceeds
              ? null
              : () => Navigator.of(dialogContext).pop(
                    _BudgetMoveSubmission(
                      destinationBudgetId: destinationId,
                      amount: amount,
                    ),
                  ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: destinationId,
                  decoration: InputDecoration(
                      labelText: context.tr('Destination account')),
                  items: [
                    for (final item in destinations)
                      DropdownMenuItem(
                        value: _budgetId(item),
                        child: Text(_budgetTitle(item)),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => destinationId = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration:
                      InputDecoration(labelText: context.tr('Currency')),
                  items: [
                    for (final option in currencies)
                      DropdownMenuItem(value: option, child: Text(option)),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => currency = value);
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  onChanged: (value) =>
                      setDialogState(() => amountText = value),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: context.tr('Amount'),
                    helperText: available == null
                        ? null
                        : context.tr('Available: {p0}',
                            {'p0': _money(currency, available)}),
                    errorText: exceeds
                        ? context.tr('Amount exceeds available balance')
                        : null,
                  ),
                ),
                const SafeguardingStatementButton(),
              ],
            ),
          ),
        );
      },
    ),
  );
  if (submission == null || !context.mounted) return;
  final destination = destinations.firstWhere(
    (item) => _budgetId(item) == submission.destinationBudgetId,
  );
  await _executeBudgetTransfer(
    context,
    ref,
    sourceBudget: sourceBudget,
    destinationBudget: destination,
    amount: submission.amount,
  );
}

Future<void> _executeBudgetTransfer(
  BuildContext context,
  WidgetRef ref, {
  required PlatformResource sourceBudget,
  required PlatformResource destinationBudget,
  required Money amount,
}) async {
  final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => dialogContext.isExampleTheme
            ? _ExampleTransferConfirmDialog(
                amount: amount,
                from: _budgetTitle(sourceBudget),
                to: _budgetTitle(destinationBudget),
              )
            : AlertDialog(
                icon: const Icon(Icons.shield_outlined),
                title: Text(context.tr('Confirm transfer')),
                content: Text(
                  context.tr('Please confirm to move {p0} from {p1} to {p2}.', {
                    'p0': amount.formatted,
                    'p1': _budgetTitle(sourceBudget),
                    'p2': _budgetTitle(destinationBudget)
                  }),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: Text(context.tr('Back')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: Text(context.tr('Confirm and move')),
                  ),
                ],
              ),
      ) ??
      false;
  if (!confirmed || !context.mounted) return;

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.transferBudget(
          fromBudgetId: _budgetId(sourceBudget),
          toBudgetId: _budgetId(destinationBudget),
          amount: amount,
        ),
      );
  final result = ref.read(platformActionControllerProvider);
  if (result.hasError || !context.mounted) return;
  ref
    ..invalidate(budgetsProvider)
    ..invalidate(transactionsProvider)
    ..invalidate(activityTransactionsProvider)
    ..invalidate(activityAccountTransactionsProvider)
    ..invalidate(activityCardTransactionsProvider);
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _TransferSuccessDialog(),
  );
}

/// The last thing between a customer and a moved balance.
///
/// The Material original asked the question in one sentence — "Please confirm
/// to move EUR 1,250.00 from Marketing to Payroll." — which puts the single
/// fact that decides the answer, the amount, in the middle of a line of prose
/// where it is read at body weight next to two proper nouns. A confirmation
/// that has to be parsed is a confirmation people click through.
///
/// So the amount is the object here: [ExampleAmount] at hero size, tabular, on
/// its own; the two budgets drop to a labelled pair of [ExampleRow]s that
/// ellipsise instead of overflowing on a long budget name; and the decision is
/// a single [ExampleGlassButton] — this is exactly the "one decisive action"
/// the glass CTA exists for, and it is the only one on the dialog. "Back"
/// stays a quiet full-width text button beneath it rather than a competing
/// slab beside it, which also removes every truncation risk from the action
/// row at 375 and text scale 1.3.
///
/// Direction is carried by [Icon] widgets, never by an arrow character: the
/// bundled Geist subsets do not guarantee U+2191/U+2193, and a white-label
/// tenant's font guarantees less.
class _ExampleTransferConfirmDialog extends StatelessWidget {
  const _ExampleTransferConfirmDialog({
    required this.amount,
    required this.from,
    required this.to,
  });

  final Money amount;
  final String from;
  final String to;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        // A confirmation is a column, not a page: 380 holds the amount and the
        // two rows at a comfortable measure and stops the dialog stretching
        // into dead space on a 1440 desktop.
        constraints: const BoxConstraints(maxWidth: 380),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: palette.borderSubtle),
            boxShadow: ExampleShadows.sheetOf(context),
          ),
          child: SingleChildScrollView(
            // Text scale 1.3 on a 375 x 812 phone leaves this content taller
            // than the inset dialog; scrolling is the only correct answer,
            // because clipping a confirmation is worse than scrolling one.
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      ExampleIconTile(
                        icon: Icons.shield_outlined,
                        color: palette.accent,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          context.tr('Confirm transfer'),
                          style: TextStyle(
                            fontSize: 16.5,
                            height: 1.25,
                            fontWeight: FontWeight.w700,
                            color: ExampleInk.primary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ExampleAmount(
                    amount: amount.minorUnits / 100,
                    currency: amount.currency,
                    size: ExampleAmountSize.hero,
                    textAlign: TextAlign.center,
                    // It never changes while the dialog is open, so the
                    // crossfade would only ever fire on arrival.
                    animate: false,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ExampleListGroup(
                    children: [
                      ExampleRow(
                        title: context.tr('From'),
                        subtitle: from,
                        leading: ExampleIconTile(
                          icon: Icons.arrow_upward_rounded,
                          color: palette.textSecondary,
                        ),
                      ),
                      ExampleRow(
                        title: context.tr('To'),
                        subtitle: to,
                        leading: ExampleIconTile(
                          icon: Icons.arrow_downward_rounded,
                          color: palette.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  ExampleGlassButton(
                    label: context.tr('Confirm and move'),
                    semanticsLabel: context.tr(
                        'Confirm and move {p0} from {p1} to {p2}',
                        {'p0': amount.formatted, 'p1': from, 'p2': to}),
                    onPressed: () => Navigator.of(context).pop(true),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      foregroundColor: ExampleInk.secondary(context),
                    ),
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(context.tr('Back')),
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

class _TransferSuccessDialog extends StatefulWidget {
  const _TransferSuccessDialog();

  @override
  State<_TransferSuccessDialog> createState() => _TransferSuccessDialogState();
}

class _TransferSuccessDialogState extends State<_TransferSuccessDialog> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1100), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    if (!isExample) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .4, end: 1),
            duration: const Duration(milliseconds: 420),
            curve: Curves.elasticOut,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: child,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 72,
                  color: context.financeTheme.positive,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(context.tr('Transfer successful')),
              ],
            ),
          ),
        ),
      );
    }
    final palette = ExamplePalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: BorderRadius.circular(AppRadii.xl),
            border: Border.all(color: palette.borderSubtle),
            boxShadow: ExampleShadows.sheetOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: Semantics(
              container: true,
              liveRegion: true,
              label: context.tr('Transfer successful'),
              excludeSemantics: true,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: .94, end: 1),
                duration: ExampleMotion.of(
                  context,
                  const Duration(milliseconds: 420),
                ),
                curve: ExampleMotion.out,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: palette.tint(palette.success),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.sm + 2),
                        child: Icon(
                          Icons.check_rounded,
                          size: 32,
                          color: palette.success,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      context.tr('Transfer successful'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BudgetMoveSubmission {
  const _BudgetMoveSubmission({
    required this.destinationBudgetId,
    required this.amount,
  });

  final String destinationBudgetId;
  final Money amount;
}

Future<void> _showTopUpDialog(
  BuildContext context,
  WidgetRef ref,
  HoppaWalletAsset asset,
  List<HoppaWalletAsset> topUpSources,
) async {
  final sourceOptions = _sourceWalletOptions(topUpSources);
  if (sourceOptions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('No USDT or USDC wallet available'))),
    );
    return;
  }

  var amountText = '';
  var selectedSource = sourceOptions.first.symbol;

  final submission = await showDialog<_QuantumTopUpSubmission>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        final amount = _parseMoney(amountText, asset.symbol);
        final canSubmit = amount.minorUnits > 0;
        HoppaWalletAsset? selectedWallet;
        for (final source in sourceOptions) {
          if (source.symbol == selectedSource) {
            selectedWallet = source;
            break;
          }
        }

        return _FullScreenActionDialog(
          title: Text(context.tr('Move to {p0} wallet', {'p0': asset.symbol})),
          primaryLabel: 'Review transfer',
          onPrimary: canSubmit
              ? () => Navigator.of(context).pop(
                    _QuantumTopUpSubmission(
                      sourceCurrency: selectedSource,
                      amount: amount,
                    ),
                  )
              : null,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr(
                      'Move supported stablecoin value into your USD wallet.'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: selectedSource,
                  decoration: InputDecoration(
                    labelText: context.tr('Source crypto wallet'),
                  ),
                  items: [
                    for (final source in sourceOptions)
                      DropdownMenuItem(
                        value: source.symbol,
                        child: Text(
                          context.tr('{p0} · {p1} available', {
                            'p0': source.symbol,
                            'p1': source.amount.toStringAsFixed(6)
                          }),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    setDialogState(() => selectedSource = value);
                  },
                ),
                if (selectedWallet != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    context.tr('Available: {p0} {p1}', {
                      'p0': selectedWallet.amount.toStringAsFixed(6),
                      'p1': selectedWallet.symbol
                    }),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  onChanged: (value) {
                    setDialogState(() => amountText = value);
                  },
                  decoration: InputDecoration(
                    labelText: context.tr('Amount to receive (USD)'),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  if (submission == null || !context.mounted) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.transferCryptoToQuantumDashboard(
          sourceCurrency: submission.sourceCurrency,
          destinationCurrency: asset.symbol,
          amount: submission.amount,
        ),
      );
  ref.invalidate(hoppaWalletAssetsProvider);
  ref.invalidate(userAssetsProvider);
  ref.invalidate(userWalletsProvider);
}

Future<void> _showConvertDialog(
  BuildContext context,
  WidgetRef ref,
  HoppaWalletAsset asset,
  List<String> targetOptions,
) async {
  var amountText = '';
  var target = targetOptions.first;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _FullScreenActionDialog(
      title: Text(context.tr('Move to crypto wallet')),
      primaryLabel: 'Review conversion',
      onPrimary: () => Navigator.of(context).pop(true),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Choose how much of your USD wallet to convert.'),
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: amountText,
              onChanged: (value) => amountText = value,
              decoration:
                  InputDecoration(labelText: context.tr('Amount (USD)')),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: target,
              decoration:
                  InputDecoration(labelText: context.tr('Target asset')),
              items: [
                for (final option in targetOptions)
                  DropdownMenuItem(
                    value: option,
                    child: Text(option),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  target = value;
                }
              },
            ),
          ],
        ),
      ),
    ),
  );

  target = target.trim().toUpperCase();
  final amount = _parseMoney(amountText, 'USD');

  if (confirmed != true ||
      target.isEmpty ||
      amount.minorUnits <= 0 ||
      !context.mounted) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.exchangeQuantumUsdToCrypto(
          asset: target,
          amount: amount,
        ),
      );
  ref.invalidate(hoppaWalletAssetsProvider);
  ref.invalidate(userAssetsProvider);
  ref.invalidate(userWalletsProvider);
}

class _FullScreenActionDialog extends StatelessWidget {
  const _FullScreenActionDialog({
    required this.title,
    required this.child,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final Widget title;
  final Widget child;
  final String primaryLabel;
  final VoidCallback? onPrimary;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.tr('Close'),
            onPressed: () => Navigator.of(context).pop(),
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
    );
  }
}

void _showDepositAddressesSheet(
  BuildContext context,
  HoppaWalletAsset asset,
  List<HoppaWalletAsset> addresses,
) {
  if (addresses.length == 1) {
    _showDepositAddressDialog(context, addresses.single);
    return;
  }

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Deposit {p0}', {'p0': asset.symbol}),
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            for (final address in addresses)
              Card(
                child: ListTile(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _showDepositAddressDialog(context, address);
                  },
                  leading: const Icon(Icons.qr_code_2),
                  title: Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final chain in _walletChainLabels(address))
                        Chip(
                          label: Text(chain),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                    ],
                  ),
                  subtitle: Text(context
                      .tr('{p0} · Tap to view', {'p0': address.shortAddress})),
                  trailing: const Icon(Icons.chevron_right),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _showDepositAddressDialog(
  BuildContext context,
  HoppaWalletAsset address,
) {
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      child: _DepositAddressScreen(address: address),
    ),
  );
}

class _DepositAddressScreen extends StatelessWidget {
  const _DepositAddressScreen({required this.address});

  final HoppaWalletAsset address;

  @override
  Widget build(BuildContext context) {
    final chains = _walletChainLabels(address);
    final isExample = context.isExampleTheme;

    final scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('Close'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
        title: Text(context.tr('Deposit {p0}', {'p0': address.symbol})),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
        children: [
          Text(
            context.tr('Your deposit address'),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('Scan the QR code or copy the address below.'),
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (chains.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [for (final chain in chains) Chip(label: Text(chain))],
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Semantics(
              label: context.tr('Deposit address QR code'),
              image: true,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // The modules stay black on white in both themes: a
                  // scanner reads contrast, not brand.
                  color: isExample ? ExampleColors.lightSurface : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isExample
                      ? Border.all(
                          color: ExamplePalette.of(context).borderSubtle)
                      : null,
                  boxShadow: isExample ? ExampleShadows.ambientOf(context) : null,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: QrImageView(
                    data: address.address,
                    size: 260,
                    backgroundColor:
                        isExample ? ExampleColors.lightSurface : Colors.white,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (isExample)
            DecoratedBox(
              decoration: BoxDecoration(
                color: ExampleSurface.of(context, 1),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border:
                    Border.all(color: ExamplePalette.of(context).borderSubtle),
                boxShadow: ExampleShadows.ambientOf(context),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Center(
                  child: SelectableText(
                    address.address,
                    textAlign: TextAlign.center,
                    style: ExampleTextStyles.mono(context, size: 13)
                        .copyWith(color: ExampleInk.primary(context)),
                  ),
                ),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  address.address,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (isExample)
            DecoratedBox(
              decoration: BoxDecoration(
                color: ExampleSurface.of(context, 1),
                borderRadius: BorderRadius.circular(AppRadii.lg),
                border:
                    Border.all(color: ExamplePalette.of(context).borderSubtle),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm + 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: ExamplePalette.of(context).warning,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs + 2),
                    Expanded(
                      child: Text(
                        context.tr(
                            'Only send {p0} on the selected network. Using another asset or network may permanently lose funds.',
                            {'p0': address.symbol}),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr(
                            'Only send {p0} on the selected network. Using another asset or network may permanently lose funds.',
                            {'p0': address.symbol}),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: isExample
            ? ExampleGlassButton(
                label: context.tr('Copy address'),
                icon: Icons.copy,
                sheen: true,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: address.address));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('Address copied'))),
                    );
                  }
                },
              )
            : FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: address.address));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr('Address copied'))),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: Text(context.tr('Copy address')),
              ),
      ),
    );

    // This screen is a full-screen dialog on the root navigator, so the
    // shell's scope is not an ancestor: without one of its own the CTA's
    // sheen would render as a static highlight forever.
    return _MaybeSheenScope(child: scaffold);
  }
}

Money _parseMoney(String value, String currency) {
  final parsed = double.tryParse(value.replaceAll(',', '.')) ?? 0;
  return Money(currency: currency, minorUnits: (parsed * 100).round());
}

List<HoppaWalletAsset> _sourceWalletOptions(List<HoppaWalletAsset> wallets) {
  return wallets
      .where(
          (wallet) => _topUpSourceSymbols.contains(wallet.symbol.toUpperCase()))
      .toList()
    ..sort((left, right) => left.symbol.compareTo(right.symbol));
}

List<String> _walletChainLabels(HoppaWalletAsset wallet) {
  if (!wallet.hasNetwork || wallet.network.trim().isEmpty) {
    return const ['Network'];
  }

  final labels = <String>{};
  for (final part in wallet.network.split('/')) {
    final label = part.trim();
    if (label.isNotEmpty) {
      labels.add(label);
    }
  }

  return labels.isEmpty ? const ['Network'] : labels.toList();
}

class _QuantumTopUpSubmission {
  const _QuantumTopUpSubmission({
    required this.sourceCurrency,
    required this.amount,
  });

  final String sourceCurrency;
  final Money amount;
}

class _BudgetTransferSubmission {
  const _BudgetTransferSubmission({
    required this.sourceBudgetId,
    required this.amount,
  });

  final String sourceBudgetId;
  final Money amount;
}

class _SheetRow extends StatelessWidget {
  const _SheetRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

String _money(String currency, double amount) =>
    Money.formatAmount(currency, amount);

List<PlatformResource> _convertibleEqualsBudgets(
  List<PlatformResource> budgets,
) {
  return budgets
      .where(
        (budget) =>
            _isEqualsBudgetTransferSource(budget) &&
            _equalsParentAccountId(budget).isNotEmpty &&
            _conversionCurrencies(budget).length >= 2 &&
            _fundedBudgetBalanceRows(budget).isNotEmpty,
      )
      .toList();
}

String _equalsParentAccountId(PlatformResource budget) {
  return _textValue(budget.metadata, const [
        'parentAccountId',
        'ParentAccountId',
        'equalsAccountId',
        'EqualsAccountId',
        'accountId',
        'AccountId',
      ]) ??
      '';
}

Map<String, dynamic> _mapValue(
  Map<String, dynamic>? json,
  List<String> keys,
) {
  if (json == null) return const {};
  for (final key in keys) {
    final value = json[key];
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
  }
  return const {};
}

String _formatConversionRate(String? rate) {
  final value = double.tryParse(rate ?? '');
  if (value == null) return rate ?? '—';
  var text = value.toStringAsFixed(value >= 100 ? 2 : 6);
  if (text.contains('.')) {
    text =
        text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

String _quoteAmount(Map<String, dynamic> amount) {
  final currency = _textValue(amount, const ['currency', 'Currency']) ?? '';
  final value = _amountValue(amount);
  return value == null ? '—' : _money(currency, value);
}

String _quoteFee(
  Map<String, dynamic> charges,
  Map<String, dynamic> settlement,
) {
  final fee = _numberValue(charges['fee'] ?? charges['Fee']);
  final price = _mapValue(settlement, const ['price', 'Price']);
  final currency = _textValue(price, const ['currency', 'Currency']) ?? '';
  return fee == null ? '—' : _money(currency, fee);
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

String _budgetId(PlatformResource budget) {
  return _textValue(budget.metadata, const [
        'budgetId',
        'BudgetId',
        'id',
        'Id',
        'accountId',
        'AccountId',
      ]) ??
      budget.id;
}

String _budgetTransactionAccountId(PlatformResource budget) {
  return _textValue(budget.metadata, const [
        'accountId',
        'AccountId',
        'walletId',
        'WalletId',
        'balanceId',
        'BalanceId',
        'budgetId',
        'BudgetId',
      ]) ??
      '';
}

void _openBudgetTransactions(
  BuildContext context,
  PlatformResource budget, {
  String currency = '',
}) {
  final scopeIds = _budgetTransactionScopeIds(budget);
  if (scopeIds.isEmpty) return;
  _openBudgetHistoryRoute(
    context,
    Uri(
      path: '/transactions',
      queryParameters: {
        // This route filters the full ledger by the actual budget (or a
        // primary account ID when no budget exists), never its shared owner.
        'budgetId': scopeIds.single,
        'accountName': currency.isEmpty
            ? _budgetTitle(budget)
            : _accountDisplayName(currency),
        if (currency.isNotEmpty) 'currency': currency,
      },
    ).toString(),
  );
}

void _openBudgetHistoryRoute(BuildContext context, String location) {
  final router = GoRouter.of(context);
  // Account details is a root dialog above the app's shell navigator. Without
  // dismissing it, the history route opens underneath an unchanged dialog.
  if (ModalRoute.of(context) is PopupRoute) {
    Navigator.of(context).pop();
  }
  router.push(location);
}

double? _budgetBalanceForCurrency(
  PlatformResource budget,
  String currency,
) {
  final normalized = currency.trim().toUpperCase();
  for (final row in _budgetBalanceRows(budget)) {
    if (row.currency == normalized) return row.amount;
  }
  return null;
}

String _budgetAvailableSummary(PlatformResource budget) {
  final rows = _budgetBalanceRows(budget);
  if (rows.isEmpty) return 'No funded balance';
  return rows.map((row) => _money(row.currency, row.amount)).join(' · ');
}

List<PlatformResource> _equalsBudgetAccounts(List<PlatformResource> budgets) {
  // Preserve the provider order: the flat receiving-account response uses
  // the same positional order when no explicit budget ID is supplied.
  return budgets.where(_isEqualsBudgetTransferSource).toList();
}

bool _isEqualsBudgetTransferSource(PlatformResource budget) {
  final provider = _textValue(budget.metadata, const [
    'provider',
    'Provider',
    'bankProvider',
    'BankProvider',
  ])?.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
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
  ])?.toLowerCase().replaceAll(' ', '');
  final hasBudgetId = _textValue(budget.metadata, const [
        'budgetId',
        'BudgetId',
      ]) !=
      null;

  // `/mobile/banking/budgets` is already Equals-scoped and its rows do not
  // repeat the provider field. Accept its explicit budget ID and native types.
  final isEquals =
      provider == 'equalsmoney' || provider == '2' || providerType == '2';
  final isBudgetType = const {
    'budget',
    'accountbalance',
    'individual',
  }.contains(accountType);
  final hasExplicitOtherProvider =
      (provider != null || providerType != null) && !isEquals;
  if (hasExplicitOtherProvider) return false;

  // The Equals budgets endpoint also returns the main Account balance without
  // repeating provider/account type fields. Keep it available for conversion.
  final isNativeEqualsResource =
      hasBudgetId || isBudgetType || _isEqualsMainBudget(budget);
  return isEquals
      ? isBudgetType || accountType == null
      : isNativeEqualsResource;
}

bool _isEqualsMainBudget(PlatformResource budget) {
  return _budgetTitle(budget).toLowerCase().trim() == 'account balance';
}

bool _hasBudgetTransferSource(
  PlatformResource targetBudget,
  List<PlatformResource> budgets,
) {
  return budgets.any(
    (budget) =>
        _budgetId(budget) != _budgetId(targetBudget) &&
        _sharedBudgetCurrencies(budget, targetBudget).isNotEmpty,
  );
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

List<String> _conversionCurrencies(PlatformResource budget) {
  final configured = _budgetCurrencies(budget);
  if (!_isEqualsBudgetTransferSource(budget)) {
    return configured;
  }

  // Destination currencies include the full Equals catalogue, even before
  // the account holds a balance in that currency. From stays limited to the
  // funded rows in the conversion form.
  return <String>{
    ...configured,
    for (final row in _budgetBalanceRows(budget)) row.currency,
    ...equalsSupportedCurrencyCodes,
  }.toList();
}

class _BudgetBalanceRow {
  const _BudgetBalanceRow({
    required this.currency,
    required this.amount,
  });

  final String currency;
  final double amount;
}

typedef _WalletReceivingAccount = ReceivingAccountDetails;

Future<void> _copyReceivingDetail(
  BuildContext context,
  String label,
  String value,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.tr('{p0} copied', {'p0': label}))),
  );
}

class _ReceivingAccountDetailsSection extends ConsumerWidget {
  const _ReceivingAccountDetailsSection({
    required this.budget,
    required this.budgets,
    this.currency = '',
  });

  final PlatformResource budget;
  final List<PlatformResource> budgets;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bankingInfo = ref.watch(equalsBankingInfoProvider);
    final embeddedAccount =
        receivingAccountForBudget(budget, const [], currency: currency);

    final isExample = context.isExampleTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Receiving account details'),
          // The sibling heading in this dialog ("Latest transactions") is set
          // at 15.5/w700 on the primary ink; two headings at two sizes on one
          // sheet is the consistency failure a utility screen cannot afford.
          style: isExample
              ? TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.primary(context),
                )
              : Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (embeddedAccount != null)
          _ReceivingAccountCard(account: embeddedAccount)
        else
          bankingInfo.when(
            data: (infos) {
              final accounts = _walletReceivingAccounts(infos);
              final account = receivingAccountForBudget(budget, accounts,
                  currency: currency);

              if (account == null) {
                // A successful response without an exact match does not prove
                // that the customer has no receiving account.
                return isExample
                    ? ExampleEmptyState(
                        icon: Icons.account_balance_outlined,
                        title: context.tr('Receiving details unavailable'),
                        body: context.tr(
                            'Receiving details could not be matched to this account. Please contact support if this continues.'),
                        compact: true,
                      )
                    : NeoSurfaceCard(
                        child: Text(
                          context.tr(
                              'Receiving details are not linked to this budget yet.'),
                        ),
                      );
              }
              return _ReceivingAccountCard(account: account);
            },
            loading: () => isExample
                ? const _ReceivingAccountSkeleton()
                : NeoSurfaceCard(
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: AppProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        // The label is the only free child in this row; without
                        // a flex it overflows the dialog at text scale 1.3 on
                        // 375 px.
                        Expanded(
                            child:
                                Text(context.tr('Loading receiving details…'))),
                      ],
                    ),
                  ),
            error: (error, stackTrace) => isExample
                // The old row put a 40 pt "Retry" beside a bare sentence with
                // no cause and no live region. The house error state carries
                // all three.
                ? ExampleErrorState(
                    title: context.tr('Receiving details unavailable'),
                    error: error,
                    compact: true,
                    onRetry: () => ref.invalidate(equalsBankingInfoProvider),
                  )
                : NeoSurfaceCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr(
                                'Receiving details are temporarily unavailable.'),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              ref.invalidate(equalsBankingInfoProvider),
                          child: Text(context.tr('Retry')),
                        ),
                      ],
                    ),
                  ),
          ),
      ],
    );
  }
}

/// The receiving-account panel at its real size, before the bank details
/// arrive.
///
/// Same surface, radius, border and ambient shadow as
/// [_ExampleReceivingAccountPanel], with the header row and three detail lines
/// blocked out, so the sheet under it does not resize when the call returns.
class _ReceivingAccountSkeleton extends StatelessWidget {
  const _ReceivingAccountSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Semantics(
      container: true,
      label: context.tr('Loading receiving details'),
      child: ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: Border.all(color: palette.borderSubtle),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm + 2,
                  AppSpacing.md,
                  AppSpacing.sm + 2,
                ),
                child: Row(
                  children: [
                    ExampleSkeleton.avatar(size: 18, sheen: false),
                    SizedBox(width: AppSpacing.sm),
                    ExampleSkeleton.line(width: 148, sheen: false),
                  ],
                ),
              ),
              for (var i = 0; i < 3; i++) ...[
                Divider(height: 1, thickness: 1, color: palette.borderSubtle),
                const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      ExampleSkeleton.line(width: 84, height: 10, sheen: false),
                      Spacer(),
                      ExampleSkeleton.line(width: 132, sheen: false),
                    ],
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

class _ReceivingAccountCard extends StatelessWidget {
  const _ReceivingAccountCard({required this.account});

  final _WalletReceivingAccount account;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return _ExampleReceivingAccountPanel(account: account);
    }
    return NeoSurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_outlined),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  account.bankName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: context.tr('Show account QR'),
                onPressed: () => _showReceivingAccountQr(context, account),
                icon: const Icon(Icons.qr_code_2_rounded),
              ),
              TextButton.icon(
                onPressed: () => _copyReceivingDetail(
                    context, 'Account details', account.copyAll),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: Text(context.tr('Copy all')),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _AccountDetailRow(
            label: account.isIban ? 'IBAN' : context.tr('Account number'),
            value: account.accountNumber,
          ),
          if (account.swift.isNotEmpty)
            _AccountDetailRow(label: 'SWIFT/BIC', value: account.swift),
          if (account.holder.isNotEmpty)
            _AccountDetailRow(
              label: context.tr('Account holder'),
              value: account.holder,
            ),
        ],
      ),
    );
  }
}

/// Receiving details, set as a ledger of machine strings.
///
/// The bank sits above selectable values separated by hairlines. Labels
/// sit above long account numbers so they remain readable on phones.
///
/// Both themes come from named roles only: level-1 surface, subtle edge, and
/// the daylight ambient that gives a white panel its containment on paper.
class _ExampleReceivingAccountPanel extends StatelessWidget {
  const _ExampleReceivingAccountPanel({required this.account});

  final _WalletReceivingAccount account;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_balance_outlined,
                  size: 22,
                  color: palette.textSecondary,
                ),
                const Spacer(),
                IconButton(
                  tooltip: context.tr('Show account QR'),
                  onPressed: () => _showReceivingAccountQr(context, account),
                  icon: Icon(
                    Icons.qr_code_2_rounded,
                    size: 20,
                    color: palette.accent,
                  ),
                ),
                Container(
                    width: 1,
                    height: 28,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    color: palette.borderSubtle),
                TextButton.icon(
                  onPressed: () => _copyReceivingDetail(
                      context, 'Account details', account.copyAll),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(context.tr('Copy all')),
                ),
              ],
            ),
          ),
          _ExampleAccountDetailLine(
            label: account.isIban ? 'IBAN' : context.tr('Account number'),
            value: account.accountNumber,
          ),
          if (account.swift.isNotEmpty)
            _ExampleAccountDetailLine(label: 'SWIFT/BIC', value: account.swift),
          if (account.holder.isNotEmpty)
            _ExampleAccountDetailLine(
              label: context.tr('Account holder'),
              value: account.holder,
              mono: false,
            ),
        ],
      ),
    );
  }
}

/// One field of the receiving-account ledger: hairline, label, value.
class _ExampleAccountDetailLine extends StatelessWidget {
  const _ExampleAccountDetailLine({
    required this.label,
    required this.value,
    this.mono = true,
    this.first = false,
  });

  final String label;
  final String value;

  /// Machine strings use the mono style; all values remain selectable.
  final bool mono;

  /// The panel's own edge is the first line's rule, so it carries none.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: palette.borderSubtle)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: palette.textSecondary)),
                const SizedBox(height: 8),
                SelectableText(value,
                    style: mono
                        ? ExampleTextStyles.mono(context, size: 14)
                            .copyWith(color: palette.ink)
                        : TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.ink)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          IconButton.outlined(
            tooltip: context.tr('Copy {p0}', {'p0': label}),
            onPressed: () => _copyReceivingDetail(context, label, value),
            style: IconButton.styleFrom(
              minimumSize: const Size(44, 44),
              foregroundColor: palette.ink,
              side: BorderSide(color: palette.borderSubtle),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.copy_rounded, size: 20),
          ),
        ],
      ),
    );
  }
}

List<_WalletReceivingAccount> _walletReceivingAccounts(
  List<PlatformResource> infos,
) =>
    receivingAccountsFromResources(infos);

class _AccountDetailRow extends StatelessWidget {
  const _AccountDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 112,
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
            Expanded(child: SelectableText(value)),
            IconButton(
              tooltip: context.tr('Copy {p0}', {'p0': label}),
              onPressed: () => _copyReceivingDetail(context, label, value),
              icon: const Icon(Icons.copy_rounded, size: 18),
            ),
          ],
        ),
      );
}

void _showReceivingAccountQr(
  BuildContext context,
  _WalletReceivingAccount account,
) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      // A dialog on the root navigator sits above the shell, so the shell's
      // sheen scope is not an ancestor here: without one of its own the CTA's
      // band would never move. One scope, guarded, Example only.
      child: _MaybeSheenScope(
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.tr('Receiving account')),
            leading: Builder(
              builder: (pageContext) => IconButton(
                tooltip: context.tr('Close'),
                onPressed: () => Navigator.of(pageContext).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
            children: [
              Text(
                account.bankName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: Semantics(
                  label: context.tr('Account details QR code'),
                  image: true,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      // White modules in both themes; the frame is what
                      // changes, so the block is seated rather than pasted.
                      color: context.isExampleTheme
                          ? ExampleColors.lightSurface
                          : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: context.isExampleTheme
                          ? Border.all(
                              color: ExamplePalette.of(context).borderSubtle,
                            )
                          : null,
                      boxShadow: context.isExampleTheme
                          ? ExampleShadows.ambientOf(context)
                          : null,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: account.qrPayload,
                        size: 260,
                        backgroundColor: context.isExampleTheme
                            ? ExampleColors.lightSurface
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              if (context.isExampleTheme)
                _ExampleReceivingAccountLedger(account: account)
              else
                NeoSurfaceCard(
                  child: Column(
                    children: [
                      _AccountDetailRow(
                        label: account.isIban
                            ? 'IBAN'
                            : context.tr('Account number'),
                        value: account.accountNumber,
                      ),
                      if (account.swift.isNotEmpty)
                        _AccountDetailRow(
                          label: 'SWIFT/BIC',
                          value: account.swift,
                        ),
                      if (account.holder.isNotEmpty)
                        _AccountDetailRow(
                          label: context.tr('Account holder'),
                          value: account.holder,
                        ),
                    ],
                  ),
                ),
            ],
          ),
          bottomNavigationBar: SafeArea(
            minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: context.isExampleTheme
                ? ExampleGlassButton(
                    label: context.tr('Copy all account details'),
                    icon: Icons.copy_rounded,
                    sheen: true,
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: account.copyAll),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(context.tr('Account details copied'))),
                        );
                      }
                    },
                  )
                : FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: account.copyAll),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(context.tr('Account details copied'))),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                    label: Text(context.tr('Copy all account details')),
                  ),
          ),
        ),
      ),
    ),
  );
}

/// Adds a [ExampleSheenScope] only when Example is the brand and no scope is
/// already above: a screen pushed onto the root navigator does not inherit
/// the shell's, and the law allows exactly one per screen.
class _MaybeSheenScope extends StatelessWidget {
  const _MaybeSheenScope({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      // `ExampleAliveLayer`, not `maybeOf(context) == null`. `_effectiveEnabled` is
      // `widget.enabled && !_reducedMotion`, so under reduced motion EVERY scope
      // publishes `enabled: false` and `maybeOf` returns null -- and the old test
      // then mounted a second scope, a redundant controller and ticker State in
      // exactly the mode that exists to stop them. Against a scope disabled by its
      // own flag it is worse than redundant: the nested one defaults to
      // `enabled: true`, so it would run. Nothing constructs such a scope today;
      // the API invites one. `existsAbove` sees a scope on or off.
      ExampleAliveLayer(enabled: context.isExampleTheme, child: child);
}

/// The receiving-account fields as one panel of hairline-separated lines.
///
/// Shared by the budget dialog's summary and this QR screen so both read as
/// the same object; every machine value is a [ExampleMono] copy target.
class _ExampleReceivingAccountLedger extends StatelessWidget {
  const _ExampleReceivingAccountLedger({required this.account});

  final _WalletReceivingAccount account;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ExampleAccountDetailLine(
            label: account.isIban ? 'IBAN' : context.tr('Account number'),
            value: account.accountNumber,
            first: true,
          ),
          if (account.swift.isNotEmpty)
            _ExampleAccountDetailLine(label: 'SWIFT/BIC', value: account.swift),
          if (account.holder.isNotEmpty)
            _ExampleAccountDetailLine(
              label: context.tr('Account holder'),
              value: account.holder,
              mono: false,
            ),
        ],
      ),
    );
  }
}

/// Per-currency totals across every fiat budget, using the same deduped
/// balance rows the Accounts list renders so headers and lists agree.
List<Money> equalsBudgetBalances(List<PlatformResource> budgets,
    {Map<String, double> valuationRates = const {}}) {
  final byCurrency = <String, int>{};
  for (final budget in budgets) {
    for (final row in _budgetBalanceRows(budget)) {
      final minor = (row.amount * 100).round();
      byCurrency.update(row.currency, (value) => value + minor,
          ifAbsent: () => minor);
    }
  }
  final ordered = byCurrency.entries.toList()
    ..sort((a, b) => compareBalanceValues(
        a.key, a.value / 100, b.key, b.value / 100, valuationRates));
  return [
    for (final entry in ordered)
      Money(currency: entry.key, minorUnits: entry.value),
  ];
}

List<_BudgetBalanceRow> _budgetBalanceRows(PlatformResource budget,
    {Map<String, double> valuationRates = const {}}) {
  final rows = <_BudgetBalanceRow>[];
  final seen = <String>{};
  final supportedCurrencies = _budgetCurrencies(budget).toSet();

  void addRow(String? currency, double? amount) {
    final normalizedCurrency = currency?.trim().toUpperCase();
    if (normalizedCurrency == null ||
        normalizedCurrency.isEmpty ||
        amount == null ||
        amount == 0) {
      return;
    }
    if (supportedCurrencies.isNotEmpty &&
        !supportedCurrencies.contains(normalizedCurrency)) {
      return;
    }
    final key = '$normalizedCurrency-${amount.toStringAsFixed(2)}';
    if (!seen.add(key)) {
      return;
    }

    rows.add(_BudgetBalanceRow(currency: normalizedCurrency, amount: amount));
  }

  for (final key in const [
    'balances',
    'Balances',
    'currencyBalances',
    'CurrencyBalances',
    'supportedCurrencyBalances',
    'SupportedCurrencyBalances',
    'availableBalances',
    'AvailableBalances',
  ]) {
    final value = budget.metadata[key];
    if (value is List) {
      for (final item in value.whereType<Map>()) {
        final row = item.map((key, value) => MapEntry(key.toString(), value));
        addRow(
          _textValue(row, const [
            'currency',
            'Currency',
            'currencyCode',
            'CurrencyCode',
          ]),
          _amountValue(row),
        );
      }
    }
  }

  addRow(
    _textValue(budget.metadata, const [
      'currency',
      'Currency',
      'currencyCode',
      'CurrencyCode',
    ]),
    _amountValue(budget.metadata),
  );

  rows.sort((left, right) => compareBalanceValues(left.currency, left.amount,
      right.currency, right.amount, valuationRates));
  return rows;
}

List<_BudgetBalanceRow> _fundedBudgetBalanceRows(PlatformResource budget) =>
    _budgetBalanceRows(budget).where((row) => row.amount > 0).toList();

List<String> _budgetTransactionScopeIds(PlatformResource budget) {
  final explicitBudgetId = _textValue(budget.metadata, const [
    'budgetId',
    'BudgetId',
    'id',
    'Id',
  ]);
  if (explicitBudgetId != null) return [explicitBudgetId];
  // Only the primary account can use its own account ID without a budget ID.
  // Named budgets share an owner account, which must not widen their history.
  if (!_isEqualsMainBudget(budget)) return const [];
  final accountId = _budgetTransactionAccountId(budget);
  return accountId.isEmpty ? const [] : [accountId];
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

double? _amountValue(Map<String, dynamic> json) {
  for (final key in const [
    'available',
    'Available',
    'availableBalance',
    'AvailableBalance',
    'balance',
    'Balance',
    'amount',
    'Amount',
    'value',
    'Value',
  ]) {
    final value = json[key];
    if (value is Map) {
      final nested = value.map((key, value) => MapEntry(key.toString(), value));
      final nestedAmount = _amountValue(nested);
      if (nestedAmount != null) {
        return nestedAmount;
      }
    }
    final parsed = _numberValue(value);
    if (parsed != null) {
      return parsed;
    }
  }

  return null;
}

double? _numberValue(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }

  return null;
}
