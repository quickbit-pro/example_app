import '../../../core/cache/saved_data_status.dart';
import '../application/activity_display_provider.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/group_activity_transactions.dart';
import 'activity_transaction_group_tile.dart';
import 'monthly_statements.dart';
import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_typography.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/formatters/transaction_display.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../shared/shared.dart';
import '../../../shared/widgets/refresh_when_visible.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/transaction_scope.dart';
import '../domain/transaction_activity_type.dart';
import '../domain/transaction_flow.dart';
import '../domain/activity_net_flow.dart';
import '../application/activity_valuation_provider.dart';
import '../../dashboard/data/display_currency_provider.dart';
import '../../dashboard/presentation/display_currency_selector.dart';
import 'activity_scope_dropdown.dart';
import '../application/transaction_identity_provider.dart';
import '../application/activity_account_options_provider.dart';
import '../export/transaction_pdf_export_button.dart';
import '../domain/activity_account_option.dart';
import 'activity_account_dropdown.dart';
import 'activity_transaction_icon.dart';
import '../domain/transaction_identity.dart';

enum TransactionActivityFilter { all, incoming, outgoing }

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({
    this.accountId = '',
    this.accountName = '',
    this.budgetId = '',
    this.currency = '',
    super.key,
  });

  final String accountId;
  final String accountName;
  final String budgetId;
  final String currency;

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _filterBarKey = GlobalKey();
  TransactionActivityFilter _filter = TransactionActivityFilter.all;
  TransactionAssetFilter _assetFilter = TransactionAssetFilter.all;
  String _searchQuery = '';
  DateTimeRange? _dateRange;
  TransactionActivityType? _typeFilter;
  String _scopeId = '';
  ActivityAccountOption? _accountScope;

  ActivityAccountOption? get _selectedAccount {
    final selected = _accountScope;
    if (selected == null) return null;
    return ref
            .read(activityAccountOptionsProvider)
            .options
            .where((option) => option.key == selected.key)
            .firstOrNull ??
        selected;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _filtered =>
      _filter != TransactionActivityFilter.all ||
      _assetFilter != TransactionAssetFilter.all ||
      _searchQuery.trim().isNotEmpty ||
      _dateRange != null ||
      _typeFilter != null ||
      _scopeId.isNotEmpty ||
      _accountScope != null;

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _filter = TransactionActivityFilter.all;
      _assetFilter = TransactionAssetFilter.all;
      _searchQuery = '';
      _dateRange = null;
      _typeFilter = null;
      _scopeId = '';
      _accountScope = null;
    });
  }

  void _setTypeFilter(TransactionActivityType? value) {
    setState(() {
      _typeFilter = value;
    });
  }

  void _openTransaction(LedgerTransaction transaction) {
    // A card request can discover a newer row than the cached all-activity
    // feed used by receipts. Refresh that history before opening the receipt.
    if (_cardApiScoped &&
        !(ref.read(activityTransactionsProvider).valueOrNull?.any(
                  (item) => item.id == transaction.id,
                ) ??
            false)) {
      ref.invalidate(activityTransactionsProvider);
    }
    context.go('/transactions/${transaction.id}');
  }

  bool get _cardApiScoped =>
      widget.accountId.trim().isEmpty &&
      widget.budgetId.trim().isEmpty &&
      _scopeId.isNotEmpty;

  Widget? _scopeSelector(List<LedgerTransaction> transactions) {
    final type = _typeFilter;
    if (type != TransactionActivityType.card && _scopeId.isEmpty) {
      return null;
    }
    return ActivityScopeDropdown(
      type: TransactionActivityType.card,
      transactions: transactions,
      selectedId: _scopeId,
      onChanged: (value) => setState(() => _scopeId = value),
    );
  }

  Widget _accountSelector() => ActivityAccountDropdown(
        selected: _accountScope,
        onChanged: (value) => setState(() {
          _accountScope = value;
          _clearIncompatibleType();
        }),
      );

  /// Route scoping is independent of the user's optional header filters.
  List<LedgerTransaction> _scoped(List<LedgerTransaction> items,
      {bool globalFeed = false}) {
    final budget = widget.budgetId.trim();
    final account = widget.accountId.trim();
    final currency = widget.currency.trim().toUpperCase();
    return items.where((item) {
      if (budget.isNotEmpty && !transactionMatchesScope(item, [budget])) {
        return false;
      }
      if (globalFeed &&
          budget.isEmpty &&
          account.isNotEmpty &&
          !transactionMatchesScope(item, [account])) {
        return false;
      }
      return currency.isEmpty ||
          item.displayAmount.currency.trim().toUpperCase() == currency;
    }).toList();
  }

  bool _matchesBaseFilters(LedgerTransaction item) {
    if (!_assetFilter.matches(item)) return false;
    if (_filter != TransactionActivityFilter.all &&
        !_matchesFilter(item, _filter)) {
      return false;
    }
    if (_dateRange case final range?) {
      if (!item.hasBookedAt) return false;
      final booked = DateUtils.dateOnly(item.bookedAt);
      if (booked.isBefore(DateUtils.dateOnly(range.start)) ||
          booked.isAfter(DateUtils.dateOnly(range.end))) {
        return false;
      }
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return [
      item.title,
      item.subtitle,
      item.status,
      item.displayType,
      item.amount.currency,
      item.displayAmount.currency
    ].join(' ').toLowerCase().contains(query);
  }

  List<LedgerTransaction>? _globalFilterRows() {
    final global = _cardApiScoped
        ? ref.read(activityCardTransactionsProvider(_scopeId))
        : ref.read(activityTransactionsProvider);
    // An in-flight refresh or failed request cannot establish incompatibility.
    if (global.isLoading || global.hasError || global.valueOrNull == null) {
      return null;
    }
    return _scoped(global.requireValue, globalFeed: !_cardApiScoped)
        .where((row) => _accountScope?.matches(row) ?? true)
        .where((row) =>
            _scopeId.isEmpty || _cardApiScoped || row.cardId == _scopeId)
        .where(_matchesBaseFilters)
        .toList();
  }

  List<TransactionActivityType> _availableTypes() {
    final rows = _globalFilterRows();
    if (rows == null) return [if (_typeFilter != null) _typeFilter!];
    return TransactionActivityType.values
        .where((type) =>
            type != TransactionActivityType.crypto && rows.any(type.matches))
        .toList();
  }

  void _clearIncompatibleType() {
    final type = _typeFilter;
    if (type == null) return;
    final rows = _globalFilterRows();
    if (rows != null && !rows.any(type.matches)) {
      _typeFilter = null;
    }
  }

  void _setDirection(TransactionActivityFilter value) => setState(() {
        _filter = value;
        _clearIncompatibleType();
      });

  void _setAsset(TransactionAssetFilter value) => setState(() {
        _assetFilter = value;
        _clearIncompatibleType();
      });

  Widget? _activeFilterChips() {
    if (!_filtered) return null;
    final selections = <({String key, String label, VoidCallback clear})>[
      if (_filter != TransactionActivityFilter.all)
        (
          key: 'direction',
          label: context.tr('Direction: {p0}', {
            'p0': _filter == TransactionActivityFilter.incoming ? 'In' : 'Out'
          }),
          clear: () => _setDirection(TransactionActivityFilter.all)
        ),
      if (_assetFilter != TransactionAssetFilter.all)
        (
          key: 'asset',
          label: context.tr('Assets: {p0}', {'p0': _assetFilter.label}),
          clear: () => _setAsset(TransactionAssetFilter.all)
        ),
      if (_dateRange case final range?)
        (
          key: 'date',
          label: context.tr('Date: {p0}–{p1}',
              {'p0': _shortDate(range.start), 'p1': _shortDate(range.end)}),
          clear: () => setState(() => _dateRange = null)
        ),
      if (_typeFilter case final type?)
        (
          key: 'type',
          label: context.tr('Type: {p0}', {'p0': type.label}),
          clear: () => _setTypeFilter(null)
        ),
      if (_searchQuery.trim().isNotEmpty)
        (
          key: 'search',
          label: context.tr('Search: {p0}', {'p0': _searchQuery.trim()}),
          clear: () {
            _searchController.clear();
            setState(() => _searchQuery = '');
          }
        ),
    ];
    if (_scopeId.isNotEmpty) {
      String label = context.tr('Selected card');
      {
        final card = ref
            .watch(cardsProvider)
            .valueOrNull
            ?.where((card) => card.id == _scopeId)
            .firstOrNull;
        if (card != null) {
          label = card.last4.trim().isEmpty
              ? card.displayLabel
              : 'Card •••• ${card.last4}';
        }
      }
      selections.add((
        key: 'scope',
        label: label,
        clear: () => setState(() => _scopeId = '')
      ));
    }
    if (_selectedAccount case final account?) {
      selections.add((
        key: 'account',
        label: account.label,
        clear: () => setState(() => _accountScope = null),
      ));
    }
    return Wrap(
      key: const ValueKey('activity-active-filters'),
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(context.tr('Active filters:'),
            style:
                TextStyle(fontSize: 11.5, color: ExampleInk.secondary(context))),
        for (final selection in selections)
          InputChip(
            key: ValueKey('activity-active-${selection.key}'),
            visualDensity: VisualDensity.compact,
            label: ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth:
                      math.min(220.0, MediaQuery.sizeOf(context).width - 116)),
              child: Tooltip(
                  message: selection.label,
                  child: Text(selection.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5))),
            ),
            onDeleted: selection.clear,
            deleteButtonTooltipMessage: 'Remove ${selection.label} filter',
          ),
        TextButton(
          key: const ValueKey('activity-clear-filters'),
          onPressed: _clearFilters,
          child: Text(context.tr('Clear all')),
        ),
      ],
    );
  }

  List<LedgerTransaction> _visible(List<LedgerTransaction> scoped) {
    return scoped.where((item) {
      if (!_matchesBaseFilters(item)) return false;
      if (!(_accountScope?.matches(item) ?? true)) return false;
      if (_scopeId.isNotEmpty && !_cardApiScoped && item.cardId != _scopeId) {
        return false;
      }
      final type = _typeFilter;
      if (type != null &&
          !(type == TransactionActivityType.card && _cardApiScoped) &&
          !type.matches(item)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<String> _exportFilters() => [
        'Direction: ${switch (_filter) {
          TransactionActivityFilter.all => 'All',
          TransactionActivityFilter.incoming => 'In',
          TransactionActivityFilter.outgoing => 'Out',
        }}',
        'Asset type: ${_assetFilter.label}',
        if (widget.accountName.trim().isNotEmpty)
          'Account: ${widget.accountName.trim()}',
        if (widget.currency.trim().isNotEmpty)
          'Currency: ${widget.currency.trim().toUpperCase()}',
        if (_typeFilter case final type?) 'Type: ${type.label}',
        if (_scopeId.isNotEmpty)
          transactionCardIdentityLabel(
                  _scopeId, ref.read(cardsProvider).valueOrNull ?? const []) ??
              'Selected card',
        if (_selectedAccount case final account?) 'Account: ${account.label}',
        if (_dateRange case final range?)
          'Date: ${range.start.toIso8601String().split('T').first} to ${range.end.toIso8601String().split('T').first}',
        if (_searchQuery.trim().isNotEmpty) 'Search: ${_searchQuery.trim()}',
      ];

  @override
  Widget build(BuildContext context) {
    ref.watch(activityTransactionsProvider);
    ref.watch(activityAccountOptionsProvider);
    final budgetScoped = widget.budgetId.trim().isNotEmpty;
    final apiScoped = widget.accountId.trim().isNotEmpty && !budgetScoped;
    final feed = _cardApiScoped
        ? activityCardTransactionsProvider(_scopeId)
        : apiScoped
            ? activityAccountTransactionsProvider(widget.accountId)
            : activityTransactionsProvider;
    final liveTransactions = ref.watch(feed);
    final snapshot = ref.watch(activityDisplayProvider((
      accountId: apiScoped && !_cardApiScoped ? widget.accountId : '',
      cardId: _cardApiScoped ? _scopeId : '',
    )));
    final transactions = snapshot.value;
    final exportRows = liveTransactions.isLoading || liveTransactions.hasError
        ? null
        : _visible(_scoped(liveTransactions.valueOrNull ?? const []));

    Future<void> refresh() async {
      if (_typeFilter == TransactionActivityType.card) {
        ref.invalidate(cardsProvider);
      }
      if (_typeFilter == TransactionActivityType.account) {
        ref.invalidate(accountsProvider);
      }
      await ref.read(refreshActivityProvider)();
      await ref.read(feed.future);
    }

    void retry() => ref.invalidate(feed);

    final showMoney =
        ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled ??
            true;
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    return RefreshWhenVisible(
      onRefresh: refresh,
      child: SavedDataStatus(
        snapshot: snapshot,
        onRetry: refresh,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.accountName.trim().isEmpty
                ? context.tr('Transactions')
                : context.tr('{p0} transactions', {'p0': widget.accountName})),
            actions: [
              RefreshAction(onRefresh: refresh),
              const MonthlyStatementButton(),
              TransactionPdfExportButton(
                transactions: exportRows,
                filters: _exportFilters(),
                identityFor: (transaction) =>
                    ref.read(transactionIdentityProvider(transaction)),
              ),
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
          body: isExample
              ? _exampleBody(
                  transactions: transactions,
                  refresh: refresh,
                  retry: retry,
                )
              : RefreshIndicator(
                  onRefresh: refresh,
                  child: transactions.when(
                    data: (items) {
                      final scoped = _scoped(items);
                      return _TransactionsContent(
                        showMoney: showMoney,
                        transactions: _visible(scoped),
                        hasAnyTransactions: scoped.isNotEmpty,
                        selectedFilter: _filter,
                        assetFilter: _assetFilter,
                        onAssetFilterChanged: _setAsset,
                        onFilterChanged: _setDirection,
                        searchQuery: _searchQuery,
                        searchController: _searchController,
                        onSearchChanged: (value) =>
                            setState(() => _searchQuery = value),
                        dateRange: _dateRange,
                        onDateRangeChanged: (value) =>
                            setState(() => _dateRange = value),
                        typeFilter: _typeFilter,
                        availableTypes: _availableTypes(),
                        onTypeFilterChanged: _setTypeFilter,
                        scopeSelector: Column(children: [
                          _accountSelector(),
                          if (_scopeSelector(scoped) case final cardSelector?)
                            cardSelector,
                        ]),
                        onTransactionTap: _openTransaction,
                      );
                    },
                    error: (error, stackTrace) =>
                        ErrorState(error: error, onRetry: retry),
                    loading: () =>
                        LoadingState(label: context.tr('Loading transactions')),
                  ),
                ),
        ),
      ),
    );
  }

  /// Filters remain above the ledger in loading, empty and populated states.
  Widget _exampleBody({
    required AsyncValue<List<LedgerTransaction>> transactions,
    required Future<void> Function() refresh,
    required VoidCallback retry,
  }) {
    final filterBar = _ExampleActivityBar(
      key: _filterBarKey,
      controller: _searchController,
      query: _searchQuery,
      onQueryChanged: (value) => setState(() => _searchQuery = value),
      direction: _filter,
      onDirectionChanged: _setDirection,
      asset: _assetFilter,
      onAssetChanged: _setAsset,
      filters: _ActivityFilters(
        dateRange: _dateRange,
        onDateRangeChanged: (value) => setState(() => _dateRange = value),
        typeFilter: _typeFilter,
        availableTypes: _availableTypes(),
        onTypeFilterChanged: _setTypeFilter,
        accountSelector: _accountSelector(),
        scopeSelector: _scopeSelector(transactions.valueOrNull ?? const []),
        onMore: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(context.tr('Filter by card'),
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                ActivityScopeDropdown(
                  type: TransactionActivityType.card,
                  transactions: transactions.valueOrNull ?? const [],
                  selectedId: _scopeId,
                  onChanged: (value) {
                    setState(() => _scopeId = value);
                    Navigator.of(sheetContext).pop();
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
      activeFilters: _activeFilterChips(),
    );
    final body = LayoutBuilder(builder: (context, constraints) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep the keyed search field focused when keyboard insets change
          // the header from fixed to scrollable.
          if (constraints.maxHeight < 600 ||
              (_filtered && constraints.maxHeight < 760))
            ConstrainedBox(
              constraints:
                  BoxConstraints(maxHeight: constraints.maxHeight * .6),
              child: SingleChildScrollView(
                key: const ValueKey('activity-compact-filters'),
                child: filterBar,
              ),
            )
          else
            filterBar,
          Expanded(
            child: RefreshIndicator(
              onRefresh: refresh,
              child: transactions.when(
                data: (items) {
                  final scoped = _scoped(items);
                  return _ExampleTransactionsContent(
                    includeRelated: widget.accountId.trim().isNotEmpty ||
                        widget.budgetId.trim().isNotEmpty ||
                        _scopeId.isNotEmpty,
                    transactions: _visible(scoped),
                    hasAnyTransactions: scoped.isNotEmpty,
                    filtered: _filtered,
                    onClearFilters: _clearFilters,
                    onTransactionTap: _openTransaction,
                  );
                },
                error: (error, stackTrace) => _ExampleScrollHost(
                  child: Column(
                    children: [
                      ErrorState(error: error, onRetry: retry),
                      if (_filtered)
                        TextButton(
                            onPressed: _clearFilters,
                            child: Text(context.tr('Clear filters'))),
                    ],
                  ),
                ),
                loading: () => const _ExampleTransactionsLoading(),
              ),
            ),
          ),
        ],
      );
    });

    // One sheen clock per screen. `/transactions` is a `ShellRoute` child and
    // `BankingShell` already wraps the routed child in a `ExampleAliveLayer`,
    // so wrapping again would mount a second scope and a second ticker under
    // the first — two unrelated rhythms on one screen. Ask whether a scope is
    // above before adding one; this branch is for the case where nothing is,
    // which is a test or a direct link to the screen on its own.
    //
    // This asks the same question `ExampleAliveLayer` does, and inherits its
    // one blind spot: an alive layer built with `enabled: false` returns its
    // child bare rather than publishing a switched-off binding, so
    // `existsAbove` reports no scope and this branch still mounts one. Nothing
    // in the app builds a disabled layer above this route today — both of
    // `BankingShell`'s take the default — but this guard is not what would
    // stop it if one did.
    if (ExampleSheenScope.existsAbove(context)) return body;
    return ExampleSheenScope(child: body);
  }
}

// ---------------------------------------------------------------------------
// Example
// ---------------------------------------------------------------------------

/// Search, direction, currency and scope filters stay above the ledger.
/// Short viewports let the filter area scroll so the keyboard cannot hide it.
///
/// Frosted is earned here: the mobile and desktop Example shells both paint a
/// `ExampleGlow` atmosphere behind the page, so there is something real to
/// blur. Both themes are explicit — night glass at .85 on Twilight, white at
/// .85 on paper — and the bar is closed by the daylight or Twilight hairline.
class _ExampleActivityBar extends StatelessWidget {
  const _ExampleActivityBar({
    required this.controller,
    required this.query,
    required this.onQueryChanged,
    required this.direction,
    required this.onDirectionChanged,
    required this.asset,
    required this.onAssetChanged,
    required this.filters,
    required this.activeFilters,
    super.key,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final TransactionActivityFilter direction;
  final ValueChanged<TransactionActivityFilter> onDirectionChanged;
  final TransactionAssetFilter asset;
  final ValueChanged<TransactionAssetFilter> onAssetChanged;
  final Widget filters;
  final Widget? activeFilters;

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= _ExampleLayout.wideBreakpoint;
    return RepaintBoundary(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: ExampleGlassPanel.frostSigma,
            sigmaY: ExampleGlassPanel.frostSigma,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              // Resolved rather than branched: the dark arm of this ternary
              // *was* `navigationGlass`, so the output is byte-identical in
              // Twilight and the daylight value can never drift out of step.
              color: ExamplePalette.of(context).navigationGlass,
              border: Border(bottom: ExampleBorders.hairlineSideOf(context)),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? _ExampleLayout.widePadding : _ExampleLayout.padding,
                AppSpacing.sm,
                wide ? _ExampleLayout.widePadding : _ExampleLayout.padding,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ExampleSearchField(
                    controller: controller,
                    query: query,
                    onChanged: onQueryChanged,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _FilterGroupRow(
                    label: context.tr('Direction'),
                    help: context.tr(
                        'In shows money received. Out shows money sent or spent.'),
                    child: ExampleSegmentedControl<TransactionActivityFilter>(
                      key: const ValueKey('activity-direction-filter'),
                      segmentIcons: const {
                        TransactionActivityFilter.all: Icons.tune_rounded,
                        TransactionActivityFilter.incoming:
                            Icons.arrow_downward_rounded,
                        TransactionActivityFilter.outgoing:
                            Icons.arrow_upward_rounded,
                      },
                      segmentIconColors: {
                        TransactionActivityFilter.incoming:
                            ExamplePalette.of(context).success,
                        TransactionActivityFilter.outgoing:
                            ExampleInk.accent(context, ExampleColors.danger),
                      },
                      segments: [
                        (
                          value: TransactionActivityFilter.all,
                          label: context.tr('All')
                        ),
                        (
                          value: TransactionActivityFilter.incoming,
                          label: context.tr('In')
                        ),
                        (
                          value: TransactionActivityFilter.outgoing,
                          label: context.tr('Out')
                        ),
                      ],
                      selected: direction,
                      onChanged: onDirectionChanged,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _FilterGroupRow(
                    label: context.tr('Asset type'),
                    help: context.tr(
                        'Filter by the transaction currency: fiat money or crypto assets.'),
                    child: ExampleSegmentedControl<TransactionAssetFilter>(
                      key: const ValueKey('activity-asset-filter'),
                      segmentIcons: const {
                        TransactionAssetFilter.all: Icons.grid_view_rounded,
                        TransactionAssetFilter.fiat: Icons.euro_rounded,
                        TransactionAssetFilter.crypto:
                            Icons.currency_bitcoin_rounded,
                      },
                      selectedColor: Theme.of(context).colorScheme.secondary,
                      onSelectedColor:
                          Theme.of(context).colorScheme.onSecondary,
                      segments: [
                        for (final value in TransactionAssetFilter.values)
                          (value: value, label: value.label),
                      ],
                      selected: asset,
                      onChanged: onAssetChanged,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 640),
                      child: filters,
                    ),
                  ),
                  if (activeFilters != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    activeFilters!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FilterGroupRow extends StatelessWidget {
  const _FilterGroupRow(
      {required this.label, required this.help, required this.child});

  final String label;
  final String help;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final labelWidget = Tooltip(
      message: help,
      triggerMode: TooltipTriggerMode.tap,
      child: Row(children: [
        Flexible(
            child: Text(label,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.secondary(context)))),
        const SizedBox(width: 4),
        Icon(Icons.info_outline_rounded,
            size: 13, color: ExampleInk.secondary(context)),
      ]),
    );
    return LayoutBuilder(builder: (context, constraints) {
      // Keep icon and label together when a narrow viewport or larger system
      // text needs the full width for the three choices.
      final choice = TextPainter(
        text: TextSpan(
            text: context.tr('Crypto'),
            style: DefaultTextStyle.of(context).style.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                )),
        textScaler: MediaQuery.textScalerOf(context),
        textDirection: Directionality.of(context),
      )..layout();
      final inlineWidth = 91 + 3 * (choice.width + 16 + 4 + 8) + 8;
      choice.dispose();
      if (constraints.maxWidth < inlineWidth) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              labelWidget,
              const SizedBox(height: 4),
              child,
            ]);
      }
      return Row(children: [
        SizedBox(width: 91, child: labelWidget),
        Expanded(child: child),
      ]);
    });
  }
}

class _ExampleSearchField extends StatelessWidget {
  const _ExampleSearchField({
    required this.controller,
    required this.query,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: AppSpacing.sm),
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: ExampleBorders.subtleOf(context),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            size: 18,
            color: ExampleInk.secondary(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              cursorColor: ExampleInk.accent(context, ExampleColors.iris),
              style: TextStyle(
                fontSize: 14,
                color: ExampleInk.primary(context),
              ),
              decoration: InputDecoration(
                isCollapsed: true,
                // The surrounding container owns the search outline. Override
                // themed state borders so the field cannot draw a second one.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
                hintText: context.tr('Search transactions'),
                hintStyle: TextStyle(
                  fontSize: 14,
                  color: ExampleInk.secondary(context),
                ),
              ),
            ),
          ),
          if (query.isNotEmpty)
            SizedBox.square(
              dimension: 44,
              child: ExamplePressable(
                onTap: () {
                  controller.clear();
                  onChanged('');
                },
                semanticsLabel: context.tr('Clear search'),
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 18,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ),
            )
          else
            const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );
  }
}

/// Layout constants for the Example ledger, in one place so the sticky bar and
/// the scroll view can never disagree about their gutter.
abstract final class _ExampleLayout {
  static const double padding = 20;
  static const double widePadding = 32;

  /// Wider screens use the desktop gutter while retaining a full-width ledger.
  static const double wideBreakpoint = 1080;
}

class _ActivityNetFlowSummary extends ConsumerWidget {
  const _ActivityNetFlowSummary(
      {required this.transactions, required this.includeRelated});
  final List<LedgerTransaction> transactions;
  final bool includeRelated;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currency = ref.watch(homeDisplayCurrencyProvider);
    final rates = ref.watch(activityValuationProvider);
    final totals = activityFlowTotals(transactions,
        currency: currency, rates: rates, includeRelated: includeRelated);
    final net = totals.net;
    final palette = ExamplePalette.of(context);
    final incomingColor = palette.success;
    final outgoingColor = palette.accent;
    final totalMovement = (totals.incoming ?? 0) + (totals.outgoing ?? 0);
    final incomingShare = totalMovement > 0
        ? (totals.incoming! / totalMovement).clamp(0.0, 1.0)
        : 0.0;
    String signed(double amount) =>
        '${amount > 0 ? '+' : ''}${Money.formatAmount(currency, amount)}';

    Widget legend(String label, double? amount, Color color) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(
                child: Text(
              '$label  ${amount == null ? '—' : signed(amount)}',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            )),
          ],
        );

    return ExampleGlassPanel(
      key: const ValueKey('activity-net-flow'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Masthead: the title, the display unit the figures below are
          // valued in — the same dropdown Home's total balance carries, on the
          // same provider, so the two screens never disagree — and the count.
          // A Wrap, so at large text scales the count drops to its own line
          // instead of being clipped.
          SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 20,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(context.tr('NET FLOW IN'),
                          style: TextStyle(
                              color: ExampleInk.primary(context),
                              fontWeight: FontWeight.w700)),
                      const SizedBox(width: 4),
                      DisplayCurrencySelector(
                        key: const ValueKey('activity-net-flow-currency'),
                        currencies: [
                          for (final item in transactions) item.amount.currency,
                        ],
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                    ],
                  ),
                  Text(
                      context.tr(
                          totals.eventCount == 1 ? '{p0} event' : '{p0} events',
                          {'p0': totals.eventCount}).toUpperCase(),
                      key: const ValueKey('activity-net-flow-events'),
                      style: TextStyle(
                          color: ExampleInk.secondary(context),
                          fontWeight: FontWeight.w700)),
                ],
              )),
          const SizedBox(height: 6),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            spacing: 6,
            children: [
              Text(
                  net == null
                      ? context.tr('Exchange rate unavailable')
                      : signed(net),
                  key: const ValueKey('activity-net-flow-value'),
                  style: TextStyle(
                      color: net == null || net == 0
                          ? ExampleInk.primary(context)
                          : net > 0
                              ? incomingColor
                              : outgoingColor,
                      fontSize: net == null ? 16 : 36,
                      fontWeight: FontWeight.w800)),
              if (net != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(currency,
                        style: TextStyle(
                            color: ExampleInk.primary(context),
                            fontWeight: FontWeight.w700))),
            ],
          ),
          const SizedBox(height: 4),
          Text(context.tr('All amounts in {p0}', {'p0': currency}),
              style:
                  TextStyle(color: ExampleInk.secondary(context), fontSize: 12)),
          const SizedBox(height: 14),
          Semantics(
            label: context.tr('Incoming and outgoing proportions'),
            child: LayoutBuilder(
                builder: (context, constraints) => Row(
                      key: const ValueKey('activity-net-flow-bar'),
                      children: [
                        if (totalMovement == 0)
                          Expanded(
                              child: Container(
                                  height: 8,
                                  decoration: BoxDecoration(
                                      color: palette.borderSubtle,
                                      borderRadius: BorderRadius.circular(4))))
                        else ...[
                          if (incomingShare > 0)
                            Container(
                                width: (constraints.maxWidth -
                                        (incomingShare < 1 ? 3 : 0)) *
                                    incomingShare,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: incomingColor,
                                    borderRadius: BorderRadius.circular(4))),
                          if (incomingShare > 0 && incomingShare < 1)
                            const SizedBox(width: 3),
                          if (incomingShare < 1)
                            Expanded(
                                child: Container(
                                    height: 8,
                                    decoration: BoxDecoration(
                                        color: outgoingColor,
                                        borderRadius:
                                            BorderRadius.circular(4)))),
                        ],
                      ],
                    )),
          ),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 8,
                children: [
                  legend(context.tr('IN'), totals.incoming, incomingColor),
                  legend(
                      context.tr('OUT'),
                      totals.outgoing == null ? null : -totals.outgoing!,
                      outgoingColor),
                ],
              )),
        ],
      ),
    );
  }
}

class _ExampleTransactionsContent extends StatelessWidget {
  const _ExampleTransactionsContent({
    required this.transactions,
    required this.includeRelated,
    required this.hasAnyTransactions,
    required this.filtered,
    required this.onClearFilters,
    required this.onTransactionTap,
  });

  final List<LedgerTransaction> transactions;
  final bool includeRelated;
  final bool hasAnyTransactions;
  final bool filtered;
  final VoidCallback onClearFilters;
  final ValueChanged<LedgerTransaction> onTransactionTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _ExampleLayout.wideBreakpoint;
        final inset = wide ? _ExampleLayout.widePadding : _ExampleLayout.padding;
        final ledgerWidth = constraints.maxWidth - inset * 2;

        if (transactions.isEmpty) {
          return _ExampleScrollHost(
            padding: EdgeInsets.fromLTRB(
              inset,
              AppSpacing.md,
              inset,
              AppSpacing.xl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ActivityNetFlowSummary(
                    transactions: transactions, includeRelated: includeRelated),
                const SizedBox(height: AppSpacing.md),
                ExampleEmptyState(
                  title: hasAnyTransactions
                      ? context.tr('Nothing matches those filters')
                      : context.tr('No transactions yet'),
                  body: hasAnyTransactions
                      ? context.tr(
                          'Widen the date range or clear a filter to see more of the ledger.')
                      : context.tr(
                          'Card payments, transfers and account activity appear here the moment they post.'),
                  icon: Icons.receipt_long_outlined,
                  actionLabel: filtered ? context.tr('Clear filters') : null,
                  onAction: filtered ? onClearFilters : null,
                ),
              ],
            ),
          );
        }

        // Pending money is not settled money, so it does not belong in a day.
        // Hoisting it into one block above the dated ledger is the cue a
        // reader gets without reading anything at all: POSITION carries the
        // "not final yet", which survives colour blindness, a greyscale
        // screenshot and direct sunlight. The amber pill on each row and the
        // status word inside it are the redundant encodings, never the only
        // ones. Revolut web and ether.fi Cash both leave pending rows mixed
        // into the day they arrived in, where the only difference is a tint.
        final groups = groupActivityTransactions(transactions);
        final groupsByPrimary = {
          for (final group in groups) group.primary: group
        };
        final undated = <LedgerTransaction>[];
        final pending = <LedgerTransaction>[];
        final booked = <LedgerTransaction>[];
        for (final transaction in groups.map((group) => group.primary)) {
          if (!transaction.hasBookedAt) {
            undated.add(transaction);
            continue;
          }
          (_isPending(transaction) ? pending : booked).add(transaction);
        }
        final days = _groupByDay(booked);

        // Every currency has its own signed total. Row magnitude bands use
        // one currency only, so unrelated units are never compared visually.
        final totals = _FlowTotals.byCurrency(
          transactions,
          includeRelated: includeRelated,
        );
        final scale = _MagnitudeScale.of(
          transactions,
          totals.isEmpty ? '' : totals.first.currency,
        );
        // Each heading scrolls together with its rows.
        final ledger = <Widget>[
          if (undated.isNotEmpty) ...[
            _dayHeaderSliver(
                label: context.tr('Date unavailable'),
                count: undated.length,
                inset: inset),
            _rowsSliver(context,
                inset: inset,
                ledgerWidth: ledgerWidth,
                groups: groupsByPrimary,
                transactions: undated,
                scale: scale),
          ],
          if (pending.isNotEmpty) ...[
            _dayHeaderSliver(
              label: context.tr('Pending'),
              count: pending.length,
              inset: inset,
              // The one heading on the screen that is not a date, so it is
              // the one heading that carries a hue. Amber names the state on
              // the band, on the block's edge and on each row's pill: three
              // redundant encodings on top of the position, none of them
              // load-bearing alone.
              tone: ExampleColors.warning,
            ),
            _rowsSliver(
              context,
              inset: inset,
              ledgerWidth: ledgerWidth,
              groups: groupsByPrimary,
              transactions: pending,
              scale: scale,
              held: true,
            ),
          ],
          for (final day in days) ...[
            _dayHeaderSliver(
              label: _dayLabel(context, day.date),
              count: day.transactions.length,
              inset: inset,
            ),
            _rowsSliver(
              context,
              inset: inset,
              ledgerWidth: ledgerWidth,
              groups: groupsByPrimary,
              transactions: day.transactions,
              scale: scale,
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        ];

        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: Padding(
              padding: EdgeInsets.fromLTRB(
                  inset, AppSpacing.sm, inset, AppSpacing.sm),
              child: _ActivityNetFlowSummary(
                  transactions: transactions, includeRelated: includeRelated),
            )),
            ...ledger,
          ],
        );
      },
    );
  }

  /// One block of the ledger.
  ///
  /// [held] draws the money that has not settled: the surface steps up a
  /// level and the block is closed by an amber edge instead of the lavender
  /// hairline every other block wears. Depth and colour are spent here
  /// because this is the one block on the screen whose contents can still
  /// change — every other block is history, and history all looks the same.
  Widget _rowsSliver(
    BuildContext context, {
    required double inset,
    required double ledgerWidth,
    required List<LedgerTransaction> transactions,
    required Map<LedgerTransaction, ActivityTransactionGroup> groups,
    required _MagnitudeScale scale,
    bool held = false,
  }) {
    final level = held ? 2 : 1;
    Widget group = ExampleListGroup(
      level: level,
      bordered: !held,
      children: [
        for (final transaction in transactions)
          ActivityTransactionGroupTile(
            key: ValueKey('activity-group-${transaction.id}'),
            group: groups[transaction]!,
            rowBuilder: (row) =>
                _exampleRow(context, row, scale, level, ledgerWidth),
          ),
      ],
    );
    if (held) {
      group = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(
            color: ExampleInk.tint(context, ExampleColors.warning, alpha: .32),
          ),
        ),
        child: group,
      );
    }
    return SliverPadding(
      padding: EdgeInsets.fromLTRB(inset, 0, inset, AppSpacing.sm),
      sliver: SliverToBoxAdapter(child: group),
    );
  }

  Widget _exampleRow(
    BuildContext context,
    LedgerTransaction transaction,
    _MagnitudeScale scale,
    int level,
    double ledgerWidth,
  ) {
    final tone = _transactionStatusTone(transaction);
    final attention =
        tone == FinanceStatusTone.warning || tone == FinanceStatusTone.danger;
    final amount = cardListAmount(transaction);
    // A row carrying a status pill always drops the kind: the pill sits on
    // the same line, and the kind is the token worth losing there — the pill
    // is why the reader stopped on this row, and the time is what tells them
    // which charge it is. At 375 it has to go anyway; measured on the ledger
    // fixture in Geist, the pill leaves the descriptor 111.0 pt and
    // `13:24 · Card Payment` wants 118.1. By 393 it would fit — 129.0 pt of
    // room — and the row drops it there too. That much is a design rule rather
    // than a measurement, and the pill's own width is why it is not modelled.
    //
    // Every other row asks [_descriptorFits], which measures both sides.
    final compact = attention ||
        !_descriptorFits(context, transaction, amount, ledgerWidth);
    return Consumer(builder: (context, ref, child) {
      final identity = ref.watch(transactionIdentityProvider(transaction));
      final identityLine = [
        if (!transaction.hasBookedAt) 'Time unavailable',
        if (identity != null && identity.isNotEmpty) identity,
        if (cardFeeCaption(transaction) case final caption?) caption,
      ].join(' · ');
      return _LedgerRow(
        key: ValueKey<String>(transaction.id),
        share: scale.shareOf(amount),
        incoming: amount.decimalAmount > 0,
        level: level,
        child: ExampleTransactionRow(
          title: transactionDisplayTitle(transaction.title),
          amount: amount.decimalAmount,
          currency: amount.currency,
          descriptor: transaction.hasBookedAt
              ? _rowDescriptor(transaction, compact: compact)
              : '',
          identityLabel: identityLine.isEmpty ? null : identityLine,
          tint: ExampleTransactionRow.tintFor(_categoryOf(transaction)),
          logoUrl: transaction.merchantLogoUrl,
          fallbackIcon: activityTransactionIcon(transaction),
          statusLabel: attention
              ? transactionDisplayStatus(
                  transaction.status.isEmpty
                      ? transaction.subtitle
                      : transaction.status,
                )
              : null,
          statusColor: tone == FinanceStatusTone.danger
              ? ExampleColors.danger
              : ExampleColors.warning,
          secondaryLabel: transaction.secondarySettlementAmount?.formatted,
          onTap: () => onTransactionTap(transaction),
        ),
      );
    });
  }
}

/// Additional filters are visible without scrolling past transaction history.
class _ActivityFilters extends StatelessWidget {
  const _ActivityFilters({
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.typeFilter,
    required this.availableTypes,
    required this.onTypeFilterChanged,
    required this.accountSelector,
    required this.onMore,
    this.scopeSelector,
  });

  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final TransactionActivityType? typeFilter;
  final List<TransactionActivityType> availableTypes;
  final ValueChanged<TransactionActivityType?> onTypeFilterChanged;
  final Widget accountSelector;
  final VoidCallback onMore;
  final Widget? scopeSelector;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
            builder: (context, constraints) => Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _ExampleFilterChip(
                      icon: Icons.calendar_month_outlined,
                      label: dateRange == null
                          ? context.tr('Date')
                          : '${_shortDate(dateRange!.start)}–${_shortDate(dateRange!.end)}',
                      active: dateRange != null,
                      onTap: () async {
                        final selected = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 1)),
                          initialDateRange: dateRange,
                        );
                        if (selected != null) onDateRangeChanged(selected);
                      },
                      onClear: dateRange == null
                          ? null
                          : () => onDateRangeChanged(null),
                    ),
                    // Null is dismissal for PopupMenuButton, so use our clearing sentinel.
                    PopupMenuButton<Object>(
                      initialValue: typeFilter ?? _allTypes,
                      onSelected: (value) => onTypeFilterChanged(
                        value is TransactionActivityType ? value : null,
                      ),
                      tooltip: context.tr('Filter by type'),
                      itemBuilder: (context) => [
                        PopupMenuItem(
                            value: _allTypes,
                            child: Text(context.tr('All types'))),
                        for (final type in availableTypes)
                          PopupMenuItem(
                            value: type,
                            child: Text(context.tr(type.label)),
                          ),
                      ],
                      child: _ExampleFilterChip(
                        icon: Icons.tune_rounded,
                        label: typeFilter == null
                            ? context.tr('Type')
                            : typeFilter!.label,
                        active: typeFilter != null,
                        onTap: null,
                        onClear: typeFilter == null
                            ? null
                            : () => onTypeFilterChanged(null),
                      ),
                    ),
                    SizedBox(
                      width: constraints.maxWidth < 340 ||
                              dateRange != null ||
                              typeFilter != null
                          ? constraints.maxWidth
                          : constraints.maxWidth - 184,
                      child: accountSelector,
                    ),
                  ],
                )),
        if (scopeSelector != null) ...[
          const SizedBox(height: AppSpacing.xs),
          scopeSelector!,
        ],
        Row(children: [
          TextButton.icon(
            key: const ValueKey('activity-more-filters'),
            onPressed: onMore,
            icon: const Icon(Icons.more_horiz_rounded, size: 16),
            label: Text(context.tr('More')),
          ),
          const Spacer(),
          Icon(Icons.sort_rounded,
              size: 14, color: ExampleInk.secondary(context)),
          const SizedBox(width: 4),
          Text(context.tr('Newest first'),
              style:
                  TextStyle(fontSize: 11, color: ExampleInk.secondary(context))),
        ]),
      ],
    );
  }
}

/// A ledger line with its size and its direction drawn behind it.
///
/// The number already says how much and the sign already says which way, but
/// both have to be *read*: a column of tabular figures is a spreadsheet, and
/// the reader has to compare digit counts to find the movement that matters.
/// So the row also carries a band — width proportional to the amount, anchored
/// to the leading edge when money came **in** and to the trailing edge when it
/// went **out**.
///
/// Two encodings, one element, no extra height:
///
/// * **size** is length, so the salary is visibly the biggest thing on the day
///   and the coffee is visibly not;
/// * **direction** is *which side the weight sits on*, which survives
///   greyscale, colour blindness and a glance — where a green tint and a plus
///   sign survive none of the three.
///
/// Deliberately not a stripe down the row's edge and not a bar under the
/// amount: the first is a side-stripe accent border, the second collides with
/// the settlement caption an FX row already puts there. A band behind the row
/// costs no layout, so the 56 pt rhythm and the group's dividers are untouched.
///
/// The wash is quiet by measurement rather than by taste. It is the one
/// thing on this screen that puts a new ground under type that was signed
/// off against the surface ladder, so its peak alpha is set by the smallest
/// ink standing on it: the 11.5 px settlement caption an FX row writes in
/// `ExampleInk.tertiary`, which lives in the trailing amount column — which is
/// exactly where an outgoing row anchors the band at full strength.
///
/// The ground that caption gets is not the block's surface. This painter
/// sits in a `Positioned.fill` *under* the row, and `ExampleTransactionRow`
/// paints `ExampleInk.hover` — the ink at .04 — inside it; every row here is
/// given an `onTap`, so on a pointer device the composite the caption stands
/// on is surface -> band -> hover. That is the order the alphas below are
/// picked against, because it is the worst ground a row can present.
///
/// Composited in that order, then WCAG 2.1, at the peak, on both levels a
/// block can rest on and in both materials:
///
/// | ground                     | in   | out  | hover only | no wash |
/// | -------------------------- | ---- | ---- | ---------- | ------- |
/// | Twilight level 1           | 4.67 | 4.72 | 4.94       | 5.10    |
/// | Twilight level 2 (pending) | —    | —    | 4.59       | 4.84    |
/// | Pearl level 1              | 4.83 | 4.78 | 4.95       | 5.09    |
/// | Pearl level 2 (pending)    | 4.63 | 4.59 | 4.74       | 4.88    |
///
/// Which is why the alpha differs by material *and* by level. The wash
/// lightens the ground in both materials, but Twilight's ink is the light
/// one, so there the lift comes straight out of the ink. The largest
/// hundredth each ground carries with the caption still at 4.5:1 is .09 on
/// Twilight level 1, .33 on Pearl level 1 and .20 on Pearl level 2, so Pearl
/// keeps the vocabulary's .13 on both of its levels and Twilight takes .06 on
/// level 1. The two level-1 bands travel the same distance off their own
/// surfaces even so — 1.100 and 1.084 of luminance on Twilight, 1.082 and
/// 1.106 on Pearl, against the 1.09 the app's own hover wash spends — so the
/// band reads at one weight in both materials.
///
/// Twilight level 2 is the ground that cannot be paid for, and it is not
/// painted. The pending block steps the surface up to `darkSurfaceSubtle`,
/// which starts the caption at 4.84:1 and leaves 4.59:1 once the hover wash
/// has taken its share; the largest alpha that still clears the floor on top
/// of that is .01, which is a rounding error rather than a quantity. So
/// Twilight's pending rows carry no band — the amber edge, the pill and the
/// block's position above the dated ledger are what that block encodes there.
/// Pearl's pending block keeps its band: its ink is the dark one, and its
/// level-2 ground still has 0.24 of a ratio to spend after the hover wash.
///
/// Example-only: nothing on the white-label path builds this.
class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.share,
    required this.incoming,
    required this.level,
    required this.child,
    super.key,
  });

  /// 0..1, already perceptually scaled by [_magnitudeShare].
  final double share;

  /// Money arriving. Anchors the band to the leading edge.
  final bool incoming;

  /// Surface level of the block this row sits in — 1 for a settled day, 2 for
  /// the pending block. The band lands on it, so it is what decides how much
  /// the band is allowed to cost.
  final int level;

  final Widget child;

  /// Widest the band ever gets, as a fraction of the row. Short of the whole
  /// row on purpose: a band that reaches the far edge stops reading as a
  /// measurement and starts reading as a selected row.
  static const double _reach = .62;

  /// Below this the band is a smudge rather than a quantity, so nothing is
  /// painted. Rows this small are the ones the reader is scrolling past.
  static const double _floor = .08;

  /// Peak alpha of the wash at the anchored edge, on a level-1 block. One per
  /// material, because the same alpha does not cost the two inks the same.
  static const double _alphaNight = .06;
  static const double _alphaDay = .13;

  /// Peak alpha for a block resting on [level], or null when that ground
  /// cannot carry a band without taking the settlement caption under the body
  /// floor. Null on Twilight from level 2 up, and the pending block is the
  /// only block that reaches it; the class doc holds the composited ratios
  /// every entry here was picked from.
  static double? _peakAlpha({required bool dark, required int level}) {
    if (!dark) return _alphaDay;
    return level >= 2 ? null : _alphaNight;
  }

  @override
  Widget build(BuildContext context) {
    if (share < _floor) return child;
    final alpha = _peakAlpha(
      dark: ExamplePalette.of(context).isDark,
      level: level,
    );
    if (alpha == null) return child;
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _MagnitudeWashPainter(
                  extent: share * _reach,
                  fromStart: incoming == ltr,
                  // `tint` keeps the Twilight hue on paper and only loses a
                  // little alpha, which is what a wash behind a glyph is
                  // supposed to do — the same call `ExamplePill` makes. The
                  // alpha itself comes from the material and the level; see
                  // the class doc for the ratios it was picked from.
                  color: ExampleInk.tint(
                    context,
                    incoming ? ExampleColors.success : ExampleColors.iris,
                    alpha: alpha,
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// The band itself: solid at the anchored edge, gone at the other, so it
/// fades into the row instead of ending on a hard vertical rule.
class _MagnitudeWashPainter extends CustomPainter {
  const _MagnitudeWashPainter({
    required this.extent,
    required this.fromStart,
    required this.color,
  });

  /// Width as a fraction of the row.
  final double extent;

  /// Anchored to the left edge in the current reading direction.
  final bool fromStart;

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width * extent;
    if (width <= 0 || size.height <= 0) return;
    final rect = fromStart
        ? Rect.fromLTWH(0, 0, width, size.height)
        : Rect.fromLTWH(size.width - width, 0, width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: fromStart ? Alignment.centerLeft : Alignment.centerRight,
          end: fromStart ? Alignment.centerRight : Alignment.centerLeft,
          colors: [color, color.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_MagnitudeWashPainter oldDelegate) =>
      oldDelegate.extent != extent ||
      oldDelegate.fromStart != fromStart ||
      oldDelegate.color != color;
}

/// How long a row's band should be, 0..1.
///
/// Square root, not linear. A ledger's dynamic range is brutal — a 5,400
/// salary sits three orders of magnitude above a 7.40 fare — and on a linear
/// scale every row but the largest collapses to nothing, which is a chart
/// that only ever draws one bar. The square root keeps the big movement
/// clearly biggest while leaving the middle of the day readable, which is the
/// range the reader is actually scanning.
double _magnitudeShare(double magnitude, double peak) {
  if (peak <= 0 || magnitude <= 0) return 0;
  return math.sqrt((magnitude / peak).clamp(0.0, 1.0));
}

/// Row magnitude bands compare amounts within the most frequent settlement
/// currency. Other currencies still have complete totals in the summary,
/// but their row widths are not compared with a different unit of money.
class _MagnitudeScale {
  const _MagnitudeScale({required this.currency, required this.peak});

  /// The largest movement in [currency] anywhere in [transactions].
  factory _MagnitudeScale.of(
    List<LedgerTransaction> transactions,
    String currency,
  ) {
    var peak = 0.0;
    for (final transaction in transactions) {
      final money = transaction.displayAmount;
      if (_currencyCode(money) != currency) continue;
      final magnitude = money.decimalAmount.abs();
      if (magnitude > peak) peak = magnitude;
    }
    return _MagnitudeScale(currency: currency, peak: peak);
  }

  /// The currency the bands are drawn in. Money in any other gets none.
  final String currency;

  /// Amount of the largest movement in [currency]: the band's full reach.
  final double peak;

  /// How much of the row [money] has earned, 0..1 — and zero, meaning no band
  /// at all, for money this scale cannot speak for.
  double shareOf(Money money) => _currencyCode(money) == currency
      ? _magnitudeShare(money.decimalAmount.abs(), peak)
      : 0;
}

/// The comparison form of a currency code. A provider is free to send `usd`,
/// ` USD ` or `USD` for the same money, and a band that missed the match
/// would silently disappear rather than fail.
String _currencyCode(Money money) => money.currency.trim().toUpperCase();

/// A date label in the ledger flow. It scrolls away with its rows instead
/// of accumulating pinned headers over later transactions.
Widget _dayHeaderSliver({
  required String label,
  required int count,
  required double inset,
  Color? tone,
}) {
  return SliverToBoxAdapter(
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: inset, vertical: 10),
        child: _ExampleDayHeaderLine(
          label: label,
          count: count,
          tone: tone,
        ),
      ),
    ),
  );
}

/// Date and event count for a block. Net flow is summarized once above.
class _ExampleDayHeaderLine extends StatelessWidget {
  const _ExampleDayHeaderLine({
    required this.label,
    required this.count,
    this.tone,
  });

  final String label;
  final int count;

  /// Hue of a state heading; null leaves the heading in the primary ink.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final accent = tone == null ? null : ExampleInk.accent(context, tone!);
    return Semantics(
      header: true,
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  if (accent != null) ...[
                    // A 6 pt disc, not a dot on an "i": the state is already
                    // named in the word beside it and repeated on every pill
                    // below, so this only has to survive being glanced at.
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: accent ?? ExampleInk.primary(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    count == 1
                        ? context.tr('1 event')
                        : context.tr('{p0} events', {'p0': count}),
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: ExampleInk.tertiary(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// External flow grouped by actual currency. Conversions and related ledger
/// rows remain in Activity but do not become new deposits. A specific account
/// or card has its own boundary, so its funding movements remain included.
class _FlowTotals {
  const _FlowTotals({
    required this.currency,
    required this.incoming,
    required this.outgoing,
    required this.net,
    required this.events,
  });

  static List<_FlowTotals> byCurrency(
    List<LedgerTransaction> transactions, {
    bool includeRelated = false,
  }) {
    final groups = <String, List<LedgerTransaction>>{};
    // The same rows the ledger draws: duplicate views of one movement folded
    // and each fee on the row it charges, so a declined purchase whose fees
    // were still taken counts what it cost and a fee is never summed twice.
    for (final item in activityAccountingRows(transactions)) {
      if (transactionHasFailed(item) && !item.cardFees.any(cardFeeWasCharged)) {
        continue;
      }
      if (!includeRelated &&
          (!item.isPrimary || transactionIsInternalMovement(item))) {
        continue;
      }
      final code = _currencyCode(cardListAmount(item));
      groups.putIfAbsent(code, () => []).add(item);
    }
    final totals = <_FlowTotals>[];
    for (final entry in groups.entries) {
      var incoming = BigInt.zero;
      var outgoing = BigInt.zero;
      for (final item in entry.value) {
        // Sum at the eight decimal places supported by the amount display,
        // avoiding floating-point residues such as 0.1 + 0.2 - 0.3.
        final amount = BigInt.parse(cardListAmount(item)
            .decimalAmount
            .toStringAsFixed(8)
            .replaceAll('.', ''));
        if (amount > BigInt.zero) {
          incoming += amount;
        } else {
          outgoing -= amount;
        }
      }
      totals.add(_FlowTotals(
        currency: entry.key,
        incoming: incoming.toDouble() / 100000000,
        outgoing: outgoing.toDouble() / 100000000,
        net: (incoming - outgoing).toDouble() / 100000000,
        events: entry.value.length,
      ));
    }
    totals.sort((a, b) {
      final countOrder = b.events.compareTo(a.events);
      return countOrder == 0 ? a.currency.compareTo(b.currency) : countOrder;
    });
    return totals;
  }

  final String currency;
  final double incoming;
  final double outgoing;
  final int events;

  final double net;
  double get volume => incoming + outgoing;
  double get incomingShare => volume == 0 ? 0 : incoming / volume;
  bool get isEmpty => volume == 0;
}

/// A 44 pt filter chip. Same anatomy in both themes: a level-2 surface, the
/// resting hairline, and the emphasis edge plus the accent ink when it is
/// carrying a filter.
class _ExampleFilterChip extends StatelessWidget {
  const _ExampleFilterChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final chip = Container(
      height: 44,
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        right: onClear == null ? AppSpacing.sm : 0,
      ),
      decoration: BoxDecoration(
        color: active
            ? ExampleInk.tint(context, ExampleColors.violet, alpha: .16)
            : ExampleSurface.of(context, 2),
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: active
            ? ExampleBorders.emphasisOf(context)
            : ExampleBorders.subtleOf(context),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: active ? accent : ExampleInk.secondary(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: active
                  ? ExampleInk.primary(context)
                  : ExampleInk.secondary(context),
            ),
          ),
          if (onClear != null)
            SizedBox.square(
              dimension: 44,
              child: ExamplePressable(
                onTap: onClear,
                semanticsLabel: context.tr('Clear {p0} filter', {'p0': label}),
                child: Center(
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    if (onTap == null) return chip;
    return ExamplePressable(
      onTap: onTap,
      pressedScale: ExampleTransactionRow.pressedScale,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: chip,
    );
  }
}

/// The filter controls stay live while only the ledger displays placeholders.
class _ExampleTransactionsLoading extends StatelessWidget {
  const _ExampleTransactionsLoading();

  @override
  Widget build(BuildContext context) {
    final wide =
        MediaQuery.sizeOf(context).width >= _ExampleLayout.wideBreakpoint;
    final inset = wide ? _ExampleLayout.widePadding : _ExampleLayout.padding;
    return ListView(
      padding: EdgeInsets.fromLTRB(inset, AppSpacing.md, inset, AppSpacing.xl),
      children: [
        Semantics(
          label: context.tr('Loading transactions'),
          child: ExcludeSemantics(
            child: ExampleSheen(
              intensity: ExampleSheenIntensity.soft,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ExampleSkeleton.line(
                      width: 120, height: 14, sheen: false),
                  const SizedBox(height: AppSpacing.sm),
                  ExampleListGroup(
                    children: [
                      for (var index = 0; index < 5; index++)
                        const ExampleSkeleton.row(
                          height: 56,
                          avatarSize: ExampleRow.leadingSize,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Centres an empty or error state in the viewport while keeping the pull to
/// refresh alive — a state that cannot be pulled down is a dead end.
class _ExampleScrollHost extends StatelessWidget {
  const _ExampleScrollHost({
    required this.child,
    this.padding = const EdgeInsets.symmetric(
      horizontal: _ExampleLayout.padding,
      vertical: AppSpacing.xl,
    ),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight.isFinite
            ? (constraints.maxHeight - padding.vertical).clamp(0.0, 4000.0)
            : 0.0;
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Center(child: child),
          ),
        );
      },
    );
  }
}

/// One day of the ledger.
class _TransactionDay {
  _TransactionDay(this.date, this.transactions);

  final DateTime date;
  final List<LedgerTransaction> transactions;
}

/// Authorised but not settled. Declined and failed rows are deliberately not
/// pending: they happened, on a day, and belong in that day's block.
bool _isPending(LedgerTransaction transaction) =>
    _transactionStatusTone(transaction) == FinanceStatusTone.warning;

/// Newest day first, newest row first inside it. The ledger is sorted here,
/// in presentation, because a provider is free to return rows in any order
/// and a day header may only appear once.
List<_TransactionDay> _groupByDay(List<LedgerTransaction> transactions) {
  final sorted = [...transactions]
    ..sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
  final days = <_TransactionDay>[];
  for (final transaction in sorted) {
    final day = DateUtils.dateOnly(transaction.bookedAt);
    if (days.isEmpty || days.last.date != day) {
      days.add(_TransactionDay(day, [transaction]));
    } else {
      days.last.transactions.add(transaction);
    }
  }
  return days;
}

/// `Today`, `Yesterday`, then `Thu 28 August`.
///
/// The weekday is not decoration: people remember spending by the shape of
/// their week — the Saturday, the Friday night — far better than by the
/// number of the month, and it is the one word that turns a date into a
/// memory. The two nearest days keep their names, because nobody thinks of
/// today as a weekday.
String _dayLabel(BuildContext context, DateTime day) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (day == today) return context.tr('Today');
  if (day == today.subtract(const Duration(days: 1))) {
    return context.tr('Yesterday');
  }
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${context.tr(weekdays[day.weekday - 1])} ${day.day} ${context.tr(months[day.month - 1])}';
}

/// Whether `time · kind` still fits the second line of a row, in a ledger
/// whose blocks are [ledgerWidth] wide.
///
/// `ExampleTransactionRow` lays its text column and its amount column side by
/// side in one `Row`, and only the text column is flexible: the amount column
/// takes its intrinsic width first and the descriptor is given what is left.
/// So the room the descriptor has is arithmetic rather than a guess —
///
///     ledgerWidth
///       − `ExampleRow.textInset`  (start padding, avatar, gap)
///       − `AppSpacing.md`        (end padding)
///       − `AppSpacing.sm`        (gap before the amount column)
///       − the amount column
///
/// — and both sides of the comparison are laid out here in the row's own
/// styles at the reader's own text scale. Checked against the rendered rows
/// in `example_transactions_layout_test.dart`, which fails the moment a row
/// compacts with room to spare or keeps the kind without it.
///
/// Measuring is what keeps the trade local. A scale that costs a 375 phone
/// its kind label costs an 834 tablet nothing, because a tablet's rows are
/// 459 pt wider; a single seven-figure amount costs its own row the kind and
/// leaves the rest of the ledger alone. A rule written as one scale ceiling
/// cannot tell those apart and spends every row for the worst one.
///
/// Rows carrying a status pill never reach this — they compact for the pill,
/// whose width is not modelled here.
bool _descriptorFits(
  BuildContext context,
  LedgerTransaction transaction,
  Money amount,
  double ledgerWidth,
) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final room = ledgerWidth -
      ExampleRow.textInset -
      AppSpacing.md -
      AppSpacing.sm -
      _amountColumnWidth(context, transaction, amount, scaler);
  if (room <= 0) return false;
  // The descriptor's own style, as `ExampleTransactionRow` writes it. Its
  // colour and line height are set there too and neither changes a width;
  // tabular figures do, so they are set here.
  final style = (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
      .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
  final painter = TextPainter(
    text: TextSpan(text: _rowDescriptor(transaction), style: style),
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  )..layout();
  final needed = painter.width;
  painter.dispose();
  return needed <= room;
}

/// Intrinsic width of a row's trailing column: the amount, or the secondary
/// settlement caption under it when that caption is the wider of the two.
///
/// The amount is rebuilt here the way `ExampleAmount` builds it at
/// [ExampleAmountSize.small] with `ExampleAmountCode.auto` and
/// `ExampleAmountTone.signed`, because that is the string whose width decides
/// how much of the row is left: `Money.formatAmount` appends the ISO code for
/// a currency with no symbol, the widget peels that code off and sets it at
/// 11 pt beside 18 pt numerals, and a credit is prefixed "+". Measuring the
/// raw `formatAmount` string at the numerals' size instead reads
/// `-12,345.67 AED` as 132.0 pt where it is drawn 118.8 — 13.2 pt of column
/// that is not there, enough to take the kind off a line that had room.
double _amountColumnWidth(
  BuildContext context,
  LedgerTransaction transaction,
  Money amount,
  TextScaler scaler,
) {
  final value = amount.decimalAmount;
  final iso = amount.currency.trim().toUpperCase();
  var number = Money.formatAmount(amount.currency, value);
  String? code;
  if (iso.isNotEmpty && number.endsWith(' $iso')) {
    number = number.substring(0, number.length - iso.length - 1);
    code = iso;
  }
  if (value > 0) number = '+$number';

  final style = ExampleTextStyles.amount(
    context,
    size: ExampleAmountSize.small,
  );
  final codeSize = (ExampleAmountSize.small.fontSize * _amountCodeScale)
      .clamp(11.0, 16.0)
      .roundToDouble();
  final painter = TextPainter(
    textDirection: Directionality.of(context),
    textScaler: scaler,
    maxLines: 1,
  );
  painter
    ..text = TextSpan(
      style: style,
      children: [
        TextSpan(text: number),
        if (code != null)
          TextSpan(
            text: ' $code',
            style: style.copyWith(
              fontSize: codeSize,
              fontWeight: FontWeight.w600,
              letterSpacing: codeSize * .04,
            ),
          ),
      ],
    )
    ..layout();
  var width = painter.width;

  // The settlement caption shares the column and is laid out under the
  // amount, so the column is as wide as the wider of the two.
  if (transaction.secondarySettlementAmount?.formatted case final caption?) {
    painter
      ..text = TextSpan(
        text: caption,
        style: (Theme.of(context).textTheme.bodySmall ??
                const TextStyle(fontSize: 12))
            .copyWith(
          fontSize: _settlementCaptionSize,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      )
      ..layout();
    if (painter.width > width) width = painter.width;
  }
  painter.dispose();
  return width;
}

/// `ExampleAmount._codeScale`, and the point size `ExampleTransactionRow` sets
/// its settlement caption at. Neither is reachable from here — one is private
/// and the other is a literal in the row's own build — so both are restated,
/// and the layout test measures the result against the rows those widgets
/// actually render: 'a code-suffixed amount is measured the way it is set'
/// covers the first and 'an FX row measures the caption under its amount'
/// the second.
const double _amountCodeScale = .38;
const double _settlementCaptionSize = 11.5;

/// `15:24 · Card payment`. The date lives in the day header, so the row only
/// carries the time and what kind of movement it was; [compact] drops the
/// kind, for a row sharing its second line with a status pill or for one
/// whose amount column has left the descriptor too little room.
String _rowDescriptor(LedgerTransaction transaction, {bool compact = false}) {
  if (!transaction.hasBookedAt) return 'Time unavailable';
  final date = transaction.bookedAt;
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  final time = '$hour:$minute';
  return compact ? time : '$time · ${_kindLabel(transaction)}';
}

/// The provider's own label when it says something, the transaction type
/// otherwise — `displayType` falls back to the word "Transaction", which
/// tells the reader nothing they cannot already see.
String _kindLabel(LedgerTransaction transaction) {
  final display = transaction.displayType.trim();
  if (display.isEmpty || display.toLowerCase() == 'transaction') {
    return _transactionTypeLabel(transaction.type);
  }
  return display;
}

/// Everything that might name a category, joined for [ExampleTransactionRow.tintFor].
String _categoryOf(LedgerTransaction transaction) {
  final metadata = transaction.metadata['merchantCategory'] ??
      transaction.metadata['MerchantCategory'];
  return [
    transaction.merchantCategory,
    metadata?.toString() ?? '',
    transaction.rawType,
    transaction.displayType,
    transaction.title,
  ].where((value) => value.trim().isNotEmpty).join(' ');
}

// Existing alternate-brand presentation and transaction classification.

class _TransactionsContent extends StatelessWidget {
  const _TransactionsContent({
    required this.transactions,
    required this.hasAnyTransactions,
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.assetFilter,
    required this.onAssetFilterChanged,
    required this.searchQuery,
    required this.searchController,
    required this.onSearchChanged,
    required this.dateRange,
    required this.onDateRangeChanged,
    required this.typeFilter,
    required this.availableTypes,
    required this.onTypeFilterChanged,
    this.scopeSelector,
    required this.onTransactionTap,
    this.showMoney = true,
  });

  final List<LedgerTransaction> transactions;
  final bool hasAnyTransactions;
  final TransactionActivityFilter selectedFilter;
  final ValueChanged<TransactionActivityFilter> onFilterChanged;
  final TransactionAssetFilter assetFilter;
  final ValueChanged<TransactionAssetFilter> onAssetFilterChanged;
  final String searchQuery;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final DateTimeRange? dateRange;
  final ValueChanged<DateTimeRange?> onDateRangeChanged;
  final TransactionActivityType? typeFilter;
  final List<TransactionActivityType> availableTypes;
  final ValueChanged<TransactionActivityType?> onTypeFilterChanged;
  final Widget? scopeSelector;
  final ValueChanged<LedgerTransaction> onTransactionTap;

  /// Fiat filters are pointless on installations without fiat banking.
  final bool showMoney;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final search = SearchBar(
      controller: searchController,
      constraints: isExample ? const BoxConstraints.tightFor(height: 46) : null,
      hintText: context.tr('Search transactions'),
      leading: const Icon(Icons.search_rounded),
      onChanged: onSearchChanged,
      trailing: [
        if (searchQuery.isNotEmpty)
          IconButton(
            tooltip: context.tr('Clear search'),
            onPressed: () {
              searchController.clear();
              onSearchChanged('');
            },
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
    final categories = isExample
        ? ExampleSegmentedControl<TransactionActivityFilter>(
            segmentIcons: const {
              TransactionActivityFilter.all: Icons.tune_rounded,
              TransactionActivityFilter.incoming: Icons.arrow_downward_rounded,
              TransactionActivityFilter.outgoing: Icons.arrow_upward_rounded,
            },
            segments: [
              (value: TransactionActivityFilter.all, label: context.tr('All')),
              (
                value: TransactionActivityFilter.incoming,
                label: context.tr('In')
              ),
              (
                value: TransactionActivityFilter.outgoing,
                label: context.tr('Out')
              ),
            ],
            selected: selectedFilter,
            onChanged: onFilterChanged,
          )
        : SegmentedButton<TransactionActivityFilter>(
            expandedInsets: EdgeInsets.zero,
            segments: [
              ButtonSegment(
                value: TransactionActivityFilter.all,
                label: Text(context.tr('All')),
                icon: isExample ? null : const Icon(Icons.all_inbox_outlined),
              ),
              ButtonSegment(
                value: TransactionActivityFilter.incoming,
                label: Text(context.tr('In')),
                icon: isExample ? null : const Icon(Icons.south_west_rounded),
              ),
              ButtonSegment(
                value: TransactionActivityFilter.outgoing,
                label: Text(context.tr('Out')),
                icon: isExample ? null : const Icon(Icons.north_east_rounded),
              ),
            ],
            selected: {selectedFilter},
            onSelectionChanged: (value) => onFilterChanged(value.first),
          );
    final assets = SegmentedButton<TransactionAssetFilter>(
      key: const ValueKey('activity-asset-filter'),
      expandedInsets: EdgeInsets.zero,
      segments: [
        for (final value in TransactionAssetFilter.values)
          ButtonSegment(
              value: value,
              label: Text(context.tr(value.label)),
              icon: Icon(switch (value) {
                TransactionAssetFilter.all => Icons.grid_view_rounded,
                TransactionAssetFilter.fiat => Icons.euro_rounded,
                TransactionAssetFilter.crypto => Icons.currency_bitcoin_rounded,
              })),
      ],
      selected: {assetFilter},
      onSelectionChanged: (value) => onAssetFilterChanged(value.first),
    );
    final filterRow = Row(
      children: [
        Expanded(
          child: _TransactionFilterButton(
            icon: Icons.calendar_month_outlined,
            label: dateRange == null
                ? context.tr('Date')
                : '${_shortDate(dateRange!.start)}–${_shortDate(dateRange!.end)}',
            active: dateRange != null,
            onTap: () async {
              final selected = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 1)),
                initialDateRange: dateRange,
              );
              if (selected != null) onDateRangeChanged(selected);
            },
            onClear: dateRange == null ? null : () => onDateRangeChanged(null),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          // A null menu value counts as "dismissed" for PopupMenuButton, so
          // "All types" uses a sentinel to clear the filter.
          child: PopupMenuButton<Object>(
            initialValue: typeFilter ?? _allTypes,
            onSelected: (value) => onTypeFilterChanged(
              value is TransactionActivityType ? value : null,
            ),
            itemBuilder: (context) => [
              PopupMenuItem(
                  value: _allTypes, child: Text(context.tr('All types'))),
              for (final type in availableTypes)
                PopupMenuItem(
                  value: type,
                  child: Text(context.tr(type.label)),
                ),
            ],
            child: _TransactionFilterButton(
              icon: Icons.tune_rounded,
              label:
                  typeFilter == null ? context.tr('Type') : typeFilter!.label,
              active: typeFilter != null,
              onTap: null,
              onClear:
                  typeFilter == null ? null : () => onTypeFilterChanged(null),
            ),
          ),
        ),
      ],
    );
    final filters = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        filterRow,
        if (scopeSelector != null) ...[
          const SizedBox(height: 10),
          scopeSelector!,
        ],
      ],
    );
    final activity = transactions.isEmpty
        ? EmptyState(
            title: hasAnyTransactions
                ? context.tr('No matching transactions')
                : context.tr('No transactions yet'),
            message: hasAnyTransactions
                ? context.tr('Change filters to review more activity.')
                : context.tr(
                    'Transfers, card payments, and account activity will appear here once they post.'),
            icon: Icons.receipt_long_outlined,
          )
        : isExample
            ? _ExampleTransactionList(
                transactions: transactions,
                grouped: MediaQuery.sizeOf(context).width >=
                    ExampleBreakpoints.desktop,
                onTransactionTap: onTransactionTap,
              )
            : NeoGroupedCard(
                children: [
                  for (final group in groupActivityTransactions(transactions))
                    ActivityTransactionGroupTile(
                      key: ValueKey('activity-group-${group.primary.id}'),
                      group: group,
                      rowBuilder: (row) => _TransactionRow(
                        transaction: row,
                        onTap: () => onTransactionTap(row),
                      ),
                    ),
                ],
              );

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = isExample && constraints.maxWidth >= 820;
        return ListView(
          padding: EdgeInsets.fromLTRB(
            desktop ? 40 : 20,
            desktop ? 28 : 12,
            desktop ? 40 : 20,
            110,
          ),
          children: [
            if (desktop)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 310,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TransactionSummary(transactions: transactions),
                        const SizedBox(height: 16),
                        search,
                        const SizedBox(height: 12),
                        categories,
                        const SizedBox(height: 10),
                        assets,
                        const SizedBox(height: 10),
                        filters,
                      ],
                    ),
                  ),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        activity,
                      ],
                    ),
                  ),
                ],
              )
            else ...[
              _TransactionSummary(transactions: transactions),
              const SizedBox(height: 16),
              search,
              const SizedBox(height: 12),
              categories,
              const SizedBox(height: 10),
              assets,
              const SizedBox(height: 10),
              filters,
              const SizedBox(height: 16),
              activity,
            ],
          ],
        );
      },
    );
  }
}

class _TransactionSummary extends StatelessWidget {
  const _TransactionSummary({required this.transactions});

  final List<LedgerTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final item in transactions) {
      final code = item.amount.currency.trim().toUpperCase();
      if (code.isEmpty) continue;
      counts.update(code, (value) => value + 1, ifAbsent: () => 1);
    }
    final currencies = counts.keys.toSet();
    final singleCurrency = currencies.length <= 1;
    // Summarise the currency that appears most often; the others are noted.
    final currency = counts.entries.isEmpty
        ? 'USD'
        : (counts.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
            .first
            .key;
    final inCurrency = transactions
        .where((item) => item.amount.currency.trim().toUpperCase() == currency);
    final incoming = inCurrency
        .where((item) => item.amount.minorUnits > 0)
        .fold(0, (sum, item) => sum + item.amount.minorUnits);
    final outgoing = inCurrency
        .where((item) => item.amount.minorUnits < 0)
        .fold(0, (sum, item) => sum + item.amount.minorUnits.abs());
    final colorScheme = Theme.of(context).colorScheme;

    final isExample = context.isExampleTheme;
    if (isExample) {
      return ExampleGlassPanel(
        radius: 18,
        borderAlpha: .26,
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Asset activity'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: ExamplePalette.of(context).ink,
                    ),
                  ),
                ),
                if (!singleCurrency)
                  Text(
                    context.tr('{p0} · +{p1} more',
                        {'p0': currency, 'p1': currencies.length - 1}),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ExamplePalette.of(context).textTertiary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ExampleMetric(
                    label: context.tr('Incoming'),
                    value:
                        '${incoming > 0 ? '+' : ''}${Money(currency: currency, minorUnits: incoming).formatted}',
                    color: ExamplePalette.of(context).success,
                  ),
                ),
                Expanded(
                  child: _ExampleMetric(
                    label: context.tr('Outgoing'),
                    value: Money(currency: currency, minorUnits: -outgoing)
                        .formatted,
                  ),
                ),
                SizedBox(
                  width: 70,
                  child: _ExampleMetric(
                    label: context.tr('Events'),
                    value: transactions.length.toString(),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }
    return Container(
      padding: EdgeInsets.all(isExample ? 14 : 18),
      decoration: BoxDecoration(
        color: isExample
            ? ExamplePalette.of(context).surface
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(isExample ? 16 : 18),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Asset activity'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  label: context.tr('Incoming'),
                  value: singleCurrency
                      ? Money(currency: currency, minorUnits: incoming)
                          .formatted
                      : 'Mixed',
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  label: context.tr('Outgoing'),
                  value: singleCurrency
                      ? Money(currency: currency, minorUnits: -outgoing)
                          .formatted
                      : 'Mixed',
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  label: context.tr('Events'),
                  value: transactions.length.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TransactionFilterButton extends StatelessWidget {
  const _TransactionFilterButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (context.isExampleTheme) {
      return Material(
        color: active
            ? ExamplePalette.of(context).fill.withValues(alpha: .16)
            : ExamplePalette.of(context).surface.withValues(alpha: .7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            height: 44,
            padding: const EdgeInsets.only(left: 14, right: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: active
                    ? ExamplePalette.of(context).accent.withValues(alpha: .6)
                    : ExamplePalette.of(context).borderSubtle,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: active
                      ? ExamplePalette.of(context).accent
                      : ExamplePalette.of(context).textSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: active
                          ? ExamplePalette.of(context).ink
                          : ExamplePalette.of(context).textSecondary,
                    ),
                  ),
                ),
                if (onClear != null)
                  IconButton(
                    tooltip: context.tr('Clear'),
                    onPressed: onClear,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 15),
                  )
                else
                  const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      );
    }
    return Material(
      color: active
          ? colors.primary.withValues(alpha: .14)
          : colors.surfaceContainer,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? colors.primary : colors.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: active ? colors.primary : null),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: context.tr('Clear'),
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _shortDate(DateTime value) => '${value.day}.${value.month}';

String _transactionTypeLabel(TransactionType type) => switch (type) {
      TransactionType.card => 'Card',
      TransactionType.transfer => 'Transfer',
      TransactionType.topUp => 'Top up',
      TransactionType.payment => 'Payment',
      TransactionType.fee => 'Fee',
    };

const _allTypes = Object();

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.transaction, required this.onTap});

  final LedgerTransaction transaction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayAmount = cardListAmount(transaction);
    final positive = transaction.amount.decimalAmount > 0;
    final provider = _transactionProvider(transaction);
    if (context.isExampleTheme) {
      final status = transactionDisplayStatus(
        transaction.status.isEmpty ? transaction.subtitle : transaction.status,
      );
      final tone = _transactionStatusTone(transaction);
      final statusColor = _exampleToneColor(context, tone);
      final tileColor = tone == FinanceStatusTone.danger
          ? ExampleColors.danger
          : tone == FinanceStatusTone.warning
              ? ExampleColors.warning
              : positive
                  ? ExampleColors.success
                  : transaction.type == TransactionType.transfer
                      ? ExampleColors.teal
                      : ExampleColors.iris;
      return ExampleGlassPanel(
        radius: 16,
        padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
        onTap: onTap,
        child: Row(
          children: [
            ExampleIconTile(
              icon: tone == FinanceStatusTone.danger
                  ? Icons.block_rounded
                  : tone == FinanceStatusTone.warning
                      ? Icons.schedule_rounded
                      : _iconFor(transaction),
              color: tileColor,
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    transactionDisplayTitle(transaction.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: ExamplePalette.of(context).ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_transactionSubtitle(transaction)} · ${provider.label}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: ExamplePalette.of(context).textTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${positive ? '+' : ''}${displayAmount.formatted}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: positive
                        ? ExamplePalette.of(context).success
                        : ExamplePalette.of(context).ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: statusColor,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return FinanceTransactionRow(
      onTap: onTap,
      logoUrl: transaction.merchantLogoUrl,
      currency: displayAmount.currency,
      fallbackIcon: _iconFor(transaction),
      title: transactionDisplayTitle(transaction.title),
      subtitle: [
        _transactionSubtitle(transaction),
        if (cardFeeCaption(transaction) case final fee?) fee
      ].join(' · '),
      amount: displayAmount.formatted,
      amountColor: positive
          ? ExamplePalette.of(context).design.color(
                Theme.of(context).brightness,
                'success',
                fallback: Colors.green.shade700,
              )
          : null,
      secondaryAmount: transaction.secondarySettlementAmount?.formatted,
      detailLabel: provider.label,
      onDetailTap: () => _showProviderDisclosure(context, provider),
      status: transactionDisplayStatus(
        transaction.status.isEmpty ? transaction.subtitle : transaction.status,
      ),
      statusTone: _transactionStatusTone(transaction),
    );
  }
}

class _ExampleTransactionList extends StatelessWidget {
  const _ExampleTransactionList({
    required this.transactions,
    required this.grouped,
    required this.onTransactionTap,
  });

  final List<LedgerTransaction> transactions;
  final bool grouped;
  final ValueChanged<LedgerTransaction> onTransactionTap;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    DateTime? currentDay;
    for (final transaction in transactions) {
      final day = DateUtils.dateOnly(transaction.bookedAt);
      if (grouped && day != currentDay) {
        currentDay = day;
        children.add(
          Padding(
            padding: EdgeInsets.only(
              top: children.isEmpty ? 0 : 14,
              bottom: 8,
            ),
            child: Text(
              _legacyDayLabel(context, day).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: ExamplePalette.of(context).textTertiary,
              ),
            ),
          ),
        );
      } else if (children.isNotEmpty) {
        children.add(const SizedBox(height: 6));
      }
      children.add(
        _TransactionRow(
          transaction: transaction,
          onTap: () => onTransactionTap(transaction),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

String _legacyDayLabel(BuildContext context, DateTime day) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (day == today) return context.tr('Today');
  if (day == today.subtract(const Duration(days: 1))) {
    return context.tr('Yesterday');
  }
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${day.day} ${context.tr(months[day.month - 1])}';
}

Color _exampleToneColor(BuildContext context, FinanceStatusTone tone) =>
    switch (tone) {
      FinanceStatusTone.success => ExamplePalette.of(context).success,
      FinanceStatusTone.warning => ExamplePalette.of(context).warning,
      FinanceStatusTone.danger => ExamplePalette.of(context).danger,
      _ => ExamplePalette.of(context).textSecondary,
    };

class _ExampleMetric extends StatelessWidget {
  const _ExampleMetric({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ExamplePalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color == null
                  ? ExamplePalette.of(context).ink
                  : ExampleInk.accent(context, color!),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
      ],
    );
  }
}

bool _matchesFilter(
  LedgerTransaction transaction,
  TransactionActivityFilter filter,
) {
  return switch (filter) {
    TransactionActivityFilter.all => true,
    TransactionActivityFilter.incoming => transaction.amount.decimalAmount > 0,
    TransactionActivityFilter.outgoing => transaction.amount.decimalAmount < 0,
  };
}

bool _isCryptoTransaction(LedgerTransaction transaction) =>
    TransactionActivityType.crypto.matches(transaction);

enum _TransactionProvider { bank, cryptoCard, exchange }

extension on _TransactionProvider {
  String get label => switch (this) {
        _TransactionProvider.bank => 'Bank',
        _TransactionProvider.cryptoCard => 'Crypto Card',
        _TransactionProvider.exchange => 'Exchange',
      };

  String get institution => switch (this) {
        _TransactionProvider.bank => 'Fiat account',
        _TransactionProvider.cryptoCard => 'Crypto card',
        _TransactionProvider.exchange => 'BoomFi Exchange / ZBX',
      };

  String get description => switch (this) {
        _TransactionProvider.bank =>
          'Banking and payment services for this transaction are provided by our regulated payment partner. See the safeguarding statement for details.',
        _TransactionProvider.cryptoCard =>
          'This transaction belongs to the Crypto card service.',
        _TransactionProvider.exchange =>
          'This transaction belongs to the BoomFi Exchange service powered through ZBX.',
      };
}

_TransactionProvider _transactionProvider(LedgerTransaction transaction) {
  final searchable =
      '${transaction.title} ${transaction.subtitle}'.toLowerCase();
  if (searchable.contains('exchange') ||
      searchable.contains('boomfi') ||
      searchable.contains('zbx')) {
    return _TransactionProvider.exchange;
  }
  if (transaction.walletId.isNotEmpty ||
      _isCryptoTransaction(transaction) ||
      transaction.type == TransactionType.card) {
    return _TransactionProvider.cryptoCard;
  }
  return _TransactionProvider.bank;
}

Future<void> _showProviderDisclosure(
  BuildContext context,
  _TransactionProvider provider,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      icon: const Icon(Icons.info_outline_rounded),
      title: Text(provider.institution),
      content: Text(provider.description),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.tr('Close')),
        ),
      ],
    ),
  );
}

String _transactionSubtitle(LedgerTransaction transaction) {
  final date = transaction.bookedAt;
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '${transaction.displayType} · $day.$month.${date.year}';
}

IconData _iconFor(LedgerTransaction transaction) {
  final raw = '${transaction.rawType} ${transaction.displayType}'.toLowerCase();
  if (raw.contains('exchange') || raw.contains('convert')) {
    return Icons.swap_horiz_rounded;
  }
  if (raw.contains('deposit') || raw.contains('top') && raw.contains('up')) {
    return Icons.south_rounded;
  }
  if (raw.contains('withdraw') ||
      raw.contains('unload') ||
      raw.contains('payout')) {
    return Icons.north_east_rounded;
  }
  if (raw.contains('fee')) return Icons.percent_rounded;
  if (_isCryptoTransaction(transaction)) {
    return Icons.currency_bitcoin;
  }

  return switch (transaction.type) {
    TransactionType.card => Icons.credit_card,
    TransactionType.transfer => Icons.swap_horiz,
    TransactionType.topUp => Icons.add_card,
    TransactionType.payment => Icons.receipt_long,
    TransactionType.fee => Icons.percent,
  };
}

FinanceStatusTone _transactionStatusTone(LedgerTransaction transaction) {
  final status =
      (transaction.status.isEmpty ? transaction.subtitle : transaction.status)
          .toLowerCase()
          .replaceAll('_', ' ')
          .trim();
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
