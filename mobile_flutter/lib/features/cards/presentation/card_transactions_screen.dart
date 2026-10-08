import '../../../core/models/group_card_fees.dart';
import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../transactions/domain/transaction_identity.dart';
import '../../transactions/export/transaction_pdf_export_button.dart';
import '../domain/card_transaction_activity.dart';
import 'widgets/card_ledger.dart';

enum CardActivityFilter { all, purchases }

/// `/cards/:id/transactions` — the card's statement.
///
/// A card ledger is a money screen, so it is built like a statement rather
/// than like a feed: the money column is the card's own settlement currency
/// (never the foreign amount, which cannot be added up), every figure is
/// tabular so the decimals stack, and rows are grouped by day with the day's
/// net beside the date. Amount direction follows the existing domain model.
///
/// The screen spends its single arrival moment on that number: the period's
/// spend settles from the secondary ink into the primary ink over 200 ms once
/// the route transition has finished. Nothing else animates on arrival, and
/// under reduced motion the settled ink is correct on frame one.
class CardTransactionsScreen extends ConsumerStatefulWidget {
  const CardTransactionsScreen({required this.cardId, super.key});

  final String cardId;

  @override
  ConsumerState<CardTransactionsScreen> createState() =>
      _CardTransactionsScreenState();
}

class _CardTransactionsScreenState
    extends ConsumerState<CardTransactionsScreen> {
  CardActivityFilter _filter = CardActivityFilter.all;

  @override
  Widget build(BuildContext context) {
    final transactions = ref.watch(cardTransactionsProvider(widget.cardId));

    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    // Use the existing roster for the statement's card identity.
    final card = isExample
        ? ref
            .watch(cardsProvider)
            .valueOrNull
            ?.where((item) => item.id == widget.cardId)
            .firstOrNull
        : null;
    final exportEntries = transactions.isLoading || transactions.hasError
        ? null
        : _buildLedger(transactions.valueOrNull ?? const [],
                sortByDate: isExample)
            .where((entry) =>
                _filter == CardActivityFilter.all ||
                _matchesFilter(entry.activity.category, _filter))
            .toList();
    final cardIdentity = card == null
        ? null
        : transactionCardIdentityLabel(widget.cardId, [card]);

    return Scaffold(
      appBar: AppBar(
        centerTitle: isExample && !desktop,
        leading: isExample && !desktop
            ? IconButton(
                tooltip: context.tr('Back'),
                onPressed: () => context.canPop()
                    ? context.pop()
                    : context.go('/cards/${widget.cardId}'),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              )
            : null,
        title: Text(context.tr('Card activity')),
        actions: [
          RefreshAction(onRefresh: () async {
            ref.invalidate(cardTransactionsProvider(widget.cardId));
            await ref.read(cardTransactionsProvider(widget.cardId).future);
          }),
          TransactionPdfExportButton(
            transactions: exportEntries
                ?.map((entry) =>
                    _exportTransaction(entry, settlementPrimary: isExample))
                .toList(),
            filters: [
              if (cardIdentity != null) cardIdentity,
              'Type: ${_filterLabel(_filter)}',
            ],
            identityFor: (_) => cardIdentity,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.refresh(cardTransactionsProvider(widget.cardId).future),
        child: transactions.when(
          data: (items) {
            final all = _buildLedger(items, sortByDate: isExample);
            final visible = _filter == CardActivityFilter.all
                ? all
                : all
                    .where(
                      (entry) =>
                          _matchesFilter(entry.activity.category, _filter),
                    )
                    .toList();
            return _ActivityContent(
              cardId: widget.cardId,
              card: card,
              entries: visible,
              hasAnyActivity: all.isNotEmpty,
              selectedFilter: _filter,
              onFilterChanged: (value) => setState(() => _filter = value),
            );
          },
          error: (error, stackTrace) => isExample
              ? _ScrollableState(
                  child: ExampleErrorState(
                    title: context.tr('Card activity did not load'),
                    error: error,
                    onRetry: () =>
                        ref.invalidate(cardTransactionsProvider(widget.cardId)),
                    secondaryLabel: 'Back to card',
                    onSecondary: () => context.go('/cards/${widget.cardId}'),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    ErrorState(
                      error: error,
                      onRetry: () => ref
                          .invalidate(cardTransactionsProvider(widget.cardId)),
                    ),
                  ],
                ),
          loading: () => isExample
              ? const _LedgerSkeleton()
              : LoadingState(label: context.tr('Loading transactions')),
        ),
      ),
    );
  }
}

/// A scroll host for a state that has no list of its own, so pull-to-refresh
/// still reaches an empty or failed statement.
class _ScrollableState extends StatelessWidget {
  const _ScrollableState({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: child,
          ),
        ),
      );
}

class _ActivityContent extends StatelessWidget {
  const _ActivityContent({
    required this.cardId,
    required this.card,
    required this.entries,
    required this.hasAnyActivity,
    required this.selectedFilter,
    required this.onFilterChanged,
  });

  final String cardId;
  final PaymentCard? card;
  final List<_LedgerEntry> entries;
  final bool hasAnyActivity;
  final CardActivityFilter selectedFilter;
  final ValueChanged<CardActivityFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) {
      return _LegacyActivityList(
        cardId: cardId,
        activities: [for (final entry in entries) entry.activity],
        hasAnyActivity: hasAnyActivity,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // The header is only worth splitting into a rail once the ledger keeps
        // a full reading column beside it; under that it stays on top.
        final content = constraints.maxWidth >= 1000
            ? _wide(context)
            : _narrow(context, constraints.maxWidth);
        // One sheen clock for the screen: the skeleton and any host added
        // later share a schedule instead of starting their own tickers.
        if (ExampleSheenScope.existsAbove(context)) return content;
        return ExampleSheenScope(child: content);
      },
    );
  }

  Widget _summary(BuildContext context) => _LedgerSummary(
        card: card,
        entries: entries,
        scopeLabel: selectedFilter == CardActivityFilter.all
            ? 'all activity'
            : '${_filterLabel(selectedFilter).toLowerCase()} only',
      );

  Widget _filters(BuildContext context) =>
      ExampleSegmentedControl<CardActivityFilter>(
        // Keep both statement filters above the 44 pt tap floor.
        height: 44,
        selected: selectedFilter,
        onChanged: onFilterChanged,
        segments: [
          for (final filter in CardActivityFilter.values)
            (value: filter, label: _filterSegmentLabel(filter)),
        ],
      );

  Widget _ledger(BuildContext context) {
    if (entries.isEmpty) {
      return ExampleEmptyState(
        icon: Icons.receipt_long_outlined,
        title: hasAnyActivity
            ? context.tr('Nothing under this filter')
            : context.tr('No activity yet'),
        body: hasAnyActivity
            ? context.tr(
                'This card has activity, just none in this category. Switch back to All to see everything on it.')
            : context.tr(
                'Purchases, top-ups and refunds appear here as soon as they post.'),
        actionLabel:
            hasAnyActivity ? context.tr('Show all') : context.tr('Open card'),
        onAction: hasAnyActivity
            ? () => onFilterChanged(CardActivityFilter.all)
            : () => context.go('/cards/$cardId'),
      );
    }
    final days = _groupByDay(_groupFeeEntries(entries));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < days.length; index++) ...[
          _DayHeader(day: days[index], first: index == 0),
          ExampleListGroup(
            children: [
              for (final entry in days[index].entries)
                _ExampleActivityRow(
                  entry: entry,
                  identity: card == null
                      ? null
                      : transactionCardIdentityLabel(cardId, [card!]),
                  onTap: () => context.go(
                    '/transactions/${Uri.encodeComponent(entry.activity.reference)}'
                    '?cardId=${Uri.encodeComponent(cardId)}',
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _narrow(BuildContext context, double width) {
    final roomy = width >= ExampleBreakpoints.desktop;
    return ListView(
      padding: EdgeInsets.fromLTRB(
        roomy ? AppSpacing.lg : 20,
        roomy ? AppSpacing.lg : AppSpacing.sm,
        roomy ? AppSpacing.lg : 20,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            // A statement is a reading column; past this it stops being one.
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _summary(context),
                if (hasAnyActivity) ...[
                  const SizedBox(height: AppSpacing.md),
                  _filters(context),
                ],
                const SizedBox(height: AppSpacing.md),
                _ledger(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Desktop: the statement header becomes a rail, so the ledger keeps its
  /// reading column instead of stretching merchant names across 900 pt of
  /// empty page.
  Widget _wide(BuildContext context) {
    const railWidth = 340.0;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: railWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _summary(context),
                      if (hasAnyActivity) ...[
                        const SizedBox(height: AppSpacing.md),
                        _filters(context),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xl),
                Expanded(child: _ledger(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// The statement header.
// ---------------------------------------------------------------------------

/// What the period cost, which card it belongs to, and what else moved.
///
/// The old panel set SPENT and RECEIVED side by side at nearly the same
/// weight, which made a card statement read as a two-column table with no
/// answer in it. The spend is the answer, so it is the only large number;
/// received and net are facts under a rule; and the footer states exactly
/// which slice is being totalled, so a filtered view never reads as the
/// card's whole history.
class _LedgerSummary extends StatelessWidget {
  const _LedgerSummary({
    required this.card,
    required this.entries,
    required this.scopeLabel,
  });

  final PaymentCard? card;
  final List<_LedgerEntry> entries;
  final String scopeLabel;

  @override
  Widget build(BuildContext context) {
    var debits = 0;
    var credits = 0;
    for (final entry in entries) {
      final minorUnits = entry.activity.settlementAmount.minorUnits;
      if (entry.activity.isCredit) {
        credits += minorUnits.abs();
      } else {
        debits += minorUnits.abs();
      }
    }
    final currency = _ledgerCurrency(card, entries);
    final counted = _groupFeeEntries(entries).length;
    final range = _periodLabel(entries, context);
    final identity = card;

    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm + AppSpacing.xxs,
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
          if (identity != null) ...[
            Text(
              '${identity.displayLabel} · ${cardMetaLine(identity, context: context)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              semanticsLabel:
                  '${identity.displayLabel}, ${cardMetaSemantics(identity, context: context)}',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.3,
                color: ExampleInk.secondary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(context.tr('SPENT'), style: ExampleTextStyles.label(context)),
          const SizedBox(height: AppSpacing.xxs),
          _SettlingAmount(amount: debits / 100, currency: currency),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 1,
            child: ColoredBox(color: ExampleBorders.subtleSideOf(context).color),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _Fact(
                  label: context.tr('RECEIVED'),
                  amount: credits / 100,
                  currency: currency,
                  color: credits == 0
                      ? ExampleInk.tertiary(context)
                      : ExampleInk.accent(
                          context,
                          ExamplePalette.of(context).success,
                        ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _Fact(
                  label: context.tr('NET'),
                  amount: (credits - debits) / 100,
                  currency: currency,
                  align: TextAlign.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            [
              '$counted ${counted == 1 ? 'transaction' : 'transactions'}',
              scopeLabel,
              if (range != null) range,
            ].join(' · '),
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: ExampleInk.tertiary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.amount,
    required this.currency,
    this.color,
    this.align = TextAlign.start,
  });

  final String label;
  final double amount;
  final String currency;
  final Color? color;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: align == TextAlign.end
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(label, style: ExampleTextStyles.label(context)),
          const SizedBox(height: AppSpacing.xxs),
          ExampleAmount(
            amount: amount,
            currency: currency,
            size: ExampleAmountSize.small,
            code: ExampleAmountCode.never,
            animate: false,
            textAlign: align,
            color: color,
          ),
        ],
      );
}

/// The screen's one moment: the period's spend settles from the secondary ink
/// into the primary ink over 200 ms, once, after the route transition has
/// finished. It is a colour, so nothing moves and nothing reflows; under
/// reduced motion the settled ink is what paints on frame one.
class _SettlingAmount extends StatefulWidget {
  const _SettlingAmount({required this.amount, required this.currency});

  final double amount;
  final String currency;

  @override
  State<_SettlingAmount> createState() => _SettlingAmountState();
}

class _SettlingAmountState extends State<_SettlingAmount> {
  /// Far enough after mount that the route's own animation is installed for
  /// real; asked on frame one, a freshly pushed route reports "completed"
  /// while the 420 ms transition is still running.
  static const Duration _settleDelay = Duration(milliseconds: 240);

  bool _settled = false;
  bool _armed = false;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled || _armed) return;
    if (ExampleMotion.reduced(context)) {
      _settled = true;
      return;
    }
    _armed = true;
    Future<void>.delayed(_settleDelay, _armFromRoute);
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
    _detach();
    if (!mounted || _settled) return;
    setState(() => _settled = true);
  }

  void _detach() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resting = ExampleInk.secondary(context);
    final arrived = ExampleInk.primary(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _settled ? 1 : 0),
      duration: ExampleMotion.of(context, ExampleMotion.state),
      curve: ExampleMotion.arrive,
      builder: (context, progress, _) => ExampleAmount(
        amount: widget.amount,
        currency: widget.currency,
        size: ExampleAmountSize.large,
        code: ExampleAmountCode.never,
        animate: false,
        color: Color.lerp(resting, arrived, progress),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The dated ledger.
// ---------------------------------------------------------------------------

/// `Today   -$174.25`: the date in the section voice, the day's net beside it
/// in tabular figures so the column of day totals lines up with the amounts
/// underneath it.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.first});

  final _LedgerDay day;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final net = day.net;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : AppSpacing.lg,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
              child: ExampleSectionTitle(title: day.localizedLabel(context))),
          if (net != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              net,
              maxLines: 1,
              softWrap: false,
              semanticsLabel: context.tr('Net for {p0}, {p1}',
                  {'p0': day.localizedLabel(context), 'p1': net}),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ExampleInk.tertiary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One line of the statement.
///
/// The money column shows the settlement amount, with any original foreign
/// currency amount in the subtitle. Status and direction retain issuer data.
class _ExampleActivityRow extends StatelessWidget {
  const _ExampleActivityRow({
    required this.entry,
    required this.onTap,
    this.identity,
  });

  final _LedgerEntry entry;
  final VoidCallback onTap;
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final item = entry.activity;
    final moneyIn = cardActivityIsMoneyIn(item);
    final settlement = entry.ledger?.cardFees.isNotEmpty == true
        ? cardListAmount(entry.ledger!)
        : item.settlementAmount;
    final title = item.title.trim().isEmpty ? item.subtitle : item.title;

    // Keep attention states visible next to the transaction amount.
    final tone = _cardActivityStatusTone(item.status);
    final attention = switch (tone) {
      FinanceStatusTone.warning ||
      FinanceStatusTone.danger =>
        _statusLabel(item.status),
      _ => null,
    };

    final original = entry.originalAmount;
    final descriptor = <String>[
      entry.timeLabel ?? 'Time unavailable',
      if (original != null) original.formatted,
      if (entry.timeLabel == null && original == null) item.subtitle.trim(),
    ].where((part) => part.isNotEmpty).join(' · ');

    return ExampleRow(
      leading: ExampleIconTile(
        icon: moneyIn ? Icons.south_rounded : _iconFor(item.category),
        color: moneyIn ? palette.success : palette.accent,
      ),
      title: title,
      subtitle: [
        descriptor,
        if (identity != null) identity!,
        if (entry.ledger != null && cardFeeCaption(entry.ledger!) != null)
          cardFeeCaption(entry.ledger!)!,
      ].join('\n'),
      subtitleMaxLines: 3,
      trailing: ExampleRowValue(
        value: _signedValue(settlement, moneyIn),
        color: moneyIn ? palette.success : null,
        caption: attention,
        captionColor: attention == null
            ? null
            : (tone == FinanceStatusTone.danger
                ? palette.danger
                : palette.warning),
      ),
      semanticsLabel: [
        title,
        if (descriptor.isNotEmpty) descriptor,
        if (identity != null) identity!,
        '${moneyIn ? 'received' : 'spent'} '
            '${settlement.formatted.replaceFirst('-', '')}',
        if (attention != null) attention,
      ].join(', '),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Loading.
// ---------------------------------------------------------------------------

/// The statement in blocks, at exactly the size it will be, so nothing on the
/// page moves when the rows arrive. One sheen host and one semantics node for
/// the whole page, per the alive-layer laws.
class _LedgerSkeleton extends StatelessWidget {
  const _LedgerSkeleton();

  Widget _group(BuildContext context, int rows) => DecoratedBox(
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: ExampleBorders.subtleOf(context),
        ),
        child: Column(
          children: [for (var i = 0; i < rows; i++) const ExampleSkeleton.row()],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('Loading card activity'),
      excludeSemantics: true,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          20,
          AppSpacing.sm,
          20,
          AppSpacing.xxl,
        ),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ExampleSheen.text(
                intensity: ExampleSheenIntensity.soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm + AppSpacing.xxs,
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
                          ExampleSkeleton.line(
                            width: 168,
                            height: 11,
                            sheen: false,
                          ),
                          SizedBox(height: AppSpacing.sm),
                          ExampleSkeleton.line(
                            width: 46,
                            height: 9,
                            sheen: false,
                          ),
                          SizedBox(height: AppSpacing.xxs),
                          ExampleSkeleton.amount(width: 190, sheen: false),
                          SizedBox(height: AppSpacing.md),
                          ExampleSkeleton.line(
                            width: 210,
                            height: 10,
                            sheen: false,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const ExampleSkeleton(
                      height: 40,
                      radius: AppRadii.pill,
                      sheen: false,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const ExampleSkeleton.line(
                      width: 96,
                      height: 13,
                      sheen: false,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _group(context, 3),
                    const SizedBox(height: AppSpacing.lg),
                    const ExampleSkeleton.line(
                      width: 78,
                      height: 13,
                      sheen: false,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    _group(context, 2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// White-label: unchanged rendering.
// ---------------------------------------------------------------------------

class _LegacyActivityList extends StatelessWidget {
  const _LegacyActivityList({
    required this.cardId,
    required this.activities,
    required this.hasAnyActivity,
  });

  final String cardId;
  final List<CardTransactionActivity> activities;
  final bool hasAnyActivity;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        _ActivitySummary(activities: activities),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        if (activities.isEmpty)
          EmptyState(
            title: hasAnyActivity
                ? context.tr('No matching activity')
                : context.tr('No card activity'),
            message: hasAnyActivity
                ? context.tr('Try a different activity filter.')
                : context.tr(
                    'Transactions for this card will appear here once they post.'),
            icon: Icons.receipt_long_outlined,
          )
        else
          NeoGroupedCard(
            children: [
              for (final item in activities)
                _ActivityCard(
                  item: item,
                  onTap: () => context.go(
                    '/transactions/${Uri.encodeComponent(item.reference)}?cardId=${Uri.encodeComponent(cardId)}',
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.activities});

  final List<CardTransactionActivity> activities;

  @override
  Widget build(BuildContext context) {
    final debits = activities
        .where((item) => !item.isCredit)
        .fold(0, (sum, item) => sum + item.settlementAmount.minorUnits.abs());
    final credits = activities
        .where((item) => item.isCredit)
        .fold(0, (sum, item) => sum + item.settlementAmount.minorUnits.abs());
    final currency =
        activities.isEmpty ? 'USD' : activities.first.settlementAmount.currency;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Activity stream'),
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
                  label: context.tr('Debits'),
                  value:
                      Money(currency: currency, minorUnits: -debits).formatted,
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  label: context.tr('Credits'),
                  value:
                      Money(currency: currency, minorUnits: credits).formatted,
                ),
              ),
              Expanded(
                child: _SummaryMetric(
                  label: context.tr('Items'),
                  value: activities.length.toString(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.item, required this.onTap});

  final CardTransactionActivity item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final amount = item.displayAmount;
    return FinanceTransactionRow(
      onTap: onTap,
      logoUrl: item.merchantLogoUrl,
      currency: amount.currency,
      fallbackIcon: _iconFor(item.category),
      title: item.title,
      subtitle: item.subtitle,
      amount: amount.formatted,
      amountColor: item.isCredit
          ? context.brandDesign.color(Theme.of(context).brightness, 'success',
              fallback: Colors.green.shade700)
          : null,
      secondaryAmount: item.secondarySettlementAmount?.formatted,
      detailLabel: 'Crypto Card',
      status: item.status,
      statusTone: _cardActivityStatusTone(item.status),
    );
  }
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

// ---------------------------------------------------------------------------
// Ledger model.
//
// Presentation only: the rows arrive as PlatformResources and the domain
// object drops the timestamp, so the statement reads the booking time back off
// the resource here rather than inventing an order for a money screen.
// ---------------------------------------------------------------------------

class _LedgerEntry {
  const _LedgerEntry({
    required this.activity,
    required this.bookedAt,
    this.ledger,
  });

  final LedgerTransaction? ledger;
  final CardTransactionActivity activity;
  final DateTime? bookedAt;

  /// `15:24`, or null for a row the provider sent without a timestamp.
  String? get timeLabel {
    final at = bookedAt;
    if (at == null) return null;
    return '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
  }

  /// The amount as the merchant charged it, when that differs from what the
  /// card settled.
  Money? get originalAmount {
    final original = activity.transactionAmount;
    if (original == null) return null;
    final settlement = activity.settlementAmount;
    if (original.currency.trim().toUpperCase() ==
            settlement.currency.trim().toUpperCase() &&
        original.minorUnits == settlement.minorUnits) {
      return null;
    }
    return original;
  }
}

LedgerTransaction _exportTransaction(_LedgerEntry entry,
    {required bool settlementPrimary}) {
  final activity = entry.activity;
  Money signed(Money value) =>
      value.decimalAmount == 0 || value.isPositive == activity.isCredit
          ? value
          : value.negated;
  return LedgerTransaction(
    id: activity.reference,
    title: activity.title,
    subtitle: [
      activity.subtitle,
      if (settlementPrimary && entry.originalAmount != null)
        'Original amount: ${entry.originalAmount!.formatted}',
    ].join('\n'),
    amount: signed(activity.settlementAmount),
    // The statement's main column is settlement currency; putting the
    // merchant amount here would promote it to the PDF's main amount. The
    // merchant amount remains the same secondary descriptor shown on screen.
    // Receipts use their own ledger parser and keep original amount primary.
    transactionAmount: settlementPrimary || activity.transactionAmount == null
        ? null
        : signed(activity.transactionAmount!),
    bookedAt: entry.bookedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
    hasBookedAt: entry.bookedAt != null,
    type: TransactionType.card,
    rawType: activity.type,
    status: activity.status,
  );
}

class _LedgerDay {
  _LedgerDay(this.date, this.entries);

  /// Null for the group of rows the provider sent without a timestamp.
  final DateTime? date;
  final List<_LedgerEntry> entries;

  String get label => date == null ? 'Undated' : _dayLabel(date!);
  String localizedLabel(BuildContext context) =>
      date == null ? context.tr('Undated') : _dayLabel(date!, context: context);

  /// The day's net, formatted, when every row on it settled in one currency.
  /// A day that mixes currencies has no honest single total, so it shows none.
  String? get net {
    final currency =
        entries.first.activity.settlementAmount.currency.trim().toUpperCase();
    var minorUnits = 0;
    for (final entry in entries) {
      final amount = entry.activity.settlementAmount;
      if (amount.currency.trim().toUpperCase() != currency) return null;
      minorUnits += entry.activity.isCredit
          ? amount.minorUnits.abs()
          : -amount.minorUnits.abs();
      for (final fee in entry.ledger?.cardFees ?? <LedgerTransaction>[]) {
        final charged = feeChargedAmount(fee);
        if (charged.currency.trim().toUpperCase() != currency) return null;
        minorUnits += charged.minorUnits;
      }
    }
    return Money(currency: currency, minorUnits: minorUnits).formatted;
  }
}

/// Date groups are presentation only. Keep issuer order for other brands,
/// and never derive historical balances from a separately loaded card balance.
List<_LedgerEntry> _groupFeeEntries(List<_LedgerEntry> entries) {
  final rows = [
    for (final entry in entries)
      if (entry.ledger != null) entry.ledger!
  ];
  final byId = {for (final row in groupCardFees(rows)) row.id: row};
  return [
    for (final entry in entries)
      if (entry.ledger == null || byId.containsKey(entry.ledger!.id))
        _LedgerEntry(
            activity: entry.activity,
            bookedAt: entry.bookedAt,
            ledger: entry.ledger == null ? null : byId[entry.ledger!.id]),
  ];
}

List<_LedgerEntry> _buildLedger(
  List<PlatformResource> items, {
  required bool sortByDate,
}) {
  final entries = <_LedgerEntry>[
    for (final resource in items) _entry(resource),
  ];
  if (!sortByDate) return entries;
  // Dated rows newest first; undated rows keep the provider's order at the
  // end, where no date heading can claim them.
  final dated = entries.where((entry) => entry.bookedAt != null).toList()
    ..sort((a, b) => b.bookedAt!.compareTo(a.bookedAt!));
  final undated = entries.where((entry) => entry.bookedAt == null).toList();
  final ordered = [...dated, ...undated];

  return ordered;
}

List<_LedgerDay> _groupByDay(List<_LedgerEntry> entries) {
  final days = <_LedgerDay>[];
  for (final entry in entries) {
    final at = entry.bookedAt;
    final day = at == null ? null : DateUtils.dateOnly(at);
    if (days.isEmpty || days.last.date != day) {
      days.add(_LedgerDay(day, [entry]));
    } else {
      days.last.entries.add(entry);
    }
  }
  return days;
}

/// The booking time, read off the resource the provider returned.
///
/// [CardTransactionActivity] does not carry one, and a statement without dates
/// is a feed, so the timestamp is parsed here out of the same metadata bag the
/// domain object reads. ISO strings and epoch seconds or milliseconds are all
/// accepted, because the two card issuers behind this screen disagree.
_LedgerEntry _entry(PlatformResource resource) {
  final ledger =
      LedgerTransaction.fromJson({...resource.metadata, 'id': resource.id});
  return _LedgerEntry(
    activity: CardTransactionActivity.fromResource(resource),
    // The ledger parser knows every timestamp key the API has used; the
    // card preview on the card screen reads the same one, so a row never
    // says "Time unavailable" here while dated there.
    bookedAt:
        _bookedAt(resource) ?? (ledger.hasBookedAt ? ledger.bookedAt : null),
    ledger: ledger,
  );
}

DateTime? _bookedAt(PlatformResource resource) {
  const keys = [
    'createdAt',
    'CreatedAt',
    'bookedAt',
    'BookedAt',
    'transactionDate',
    'TransactionDate',
    'postedAt',
    'PostedAt',
    'date',
    'Date',
    'timestamp',
    'Timestamp',
  ];
  final sources = <Map<String, dynamic>>[resource.metadata];
  final nested = resource.metadata['metadata'] ?? resource.metadata['Metadata'];
  if (nested is Map) {
    sources.add(nested.map((key, value) => MapEntry(key.toString(), value)));
  }
  for (final source in sources) {
    for (final key in keys) {
      final value = source[key];
      if (value == null) continue;
      if (value is int) return _fromEpoch(value);
      final text = value.toString().trim();
      if (text.isEmpty) continue;
      final epoch = int.tryParse(text);
      if (epoch != null) return _fromEpoch(epoch);
      final parsed = DateTime.tryParse(text);
      if (parsed != null) return parsed.toLocal();
    }
  }
  return null;
}

DateTime? _fromEpoch(int value) {
  if (value <= 0) return null;
  // Ten digits is seconds, thirteen is milliseconds.
  final millis = value < 100000000000 ? value * 1000 : value;
  return DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
}

String _dayLabel(DateTime day, {BuildContext? context}) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (day == today) return context?.tr('Today') ?? 'Today';
  if (day == today.subtract(const Duration(days: 1))) {
    return context?.tr('Yesterday') ?? 'Yesterday';
  }
  return '${day.day} ${context?.tr(_months[day.month - 1]) ?? _months[day.month - 1]}';
}

/// `20 Aug - 1 Sep`, or a single date when the period is one day. Null while
/// nothing on screen is dated. The separator is an ASCII hyphen: an en dash is
/// not guaranteed in a white-label tenant's configured font.
String? _periodLabel(List<_LedgerEntry> entries, BuildContext context) {
  DateTime? newest;
  DateTime? oldest;
  for (final entry in entries) {
    final at = entry.bookedAt;
    if (at == null) continue;
    if (newest == null || at.isAfter(newest)) newest = at;
    if (oldest == null || at.isBefore(oldest)) oldest = at;
  }
  if (newest == null || oldest == null) return null;
  final from = _shortDate(oldest, context);
  final to = _shortDate(newest, context);
  return from == to ? from : '$from - $to';
}

String _shortDate(DateTime day, BuildContext context) =>
    '${day.day} ${context.tr(_months[day.month - 1].substring(0, 3))}';

const _months = [
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

/// The currency the statement totals in: the card's, when it is known, and
/// otherwise whatever the rows settled in.
String _ledgerCurrency(PaymentCard? card, List<_LedgerEntry> entries) {
  final fromCard = card?.balance.currency.trim() ?? '';
  if (fromCard.isNotEmpty) return fromCard;
  if (entries.isEmpty) return 'USD';
  return entries.first.activity.settlementAmount.currency;
}

/// Keep the existing issuer-aware domain direction across every presentation.
bool cardActivityIsMoneyIn(CardTransactionActivity item) => item.isCredit;

/// `-$174.25` / `+$500.00`, with the sign spelled in ASCII so no glyph is
/// asked of a tenant font that may not carry one. A zero movement (a freeze, a
/// PIN change) takes no sign at all.
String _signedValue(Money amount, bool moneyIn) {
  final magnitude = amount.formatted.replaceFirst('-', '');
  if (amount.minorUnits == 0) return magnitude;
  return moneyIn ? '+$magnitude' : '-$magnitude';
}

String _statusLabel(String value) {
  final status = value.trim();
  if (status.isEmpty) return 'Processing';
  return '${status[0].toUpperCase()}${status.substring(1)}';
}

/// The full word, for the statement line under the totals.
String _filterLabel(CardActivityFilter filter) => switch (filter) {
      CardActivityFilter.all => 'All',
      CardActivityFilter.purchases => 'Purchases',
    };

/// Keep the familiar compact label; the summary spells out "Purchases".
String _filterSegmentLabel(CardActivityFilter filter) => switch (filter) {
      CardActivityFilter.purchases => 'Spend',
      _ => _filterLabel(filter),
    };

bool _matchesFilter(
  CardTransactionCategory category,
  CardActivityFilter filter,
) {
  return switch (filter) {
    CardActivityFilter.all => true,
    CardActivityFilter.purchases =>
      category == CardTransactionCategory.purchase,
  };
}

FinanceStatusTone _cardActivityStatusTone(String value) {
  final status = value.toLowerCase().replaceAll('_', ' ').trim();
  if (const {'complete', 'completed', 'closed', 'settled', 'booked'}
      .contains(status)) {
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

IconData _iconFor(CardTransactionCategory category) {
  return switch (category) {
    CardTransactionCategory.purchase => Icons.shopping_bag_outlined,
    CardTransactionCategory.crypto => Icons.currency_bitcoin,
    CardTransactionCategory.control => Icons.tune,
  };
}
