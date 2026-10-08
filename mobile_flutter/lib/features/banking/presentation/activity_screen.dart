import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../brands/example/example.dart';
import '../../../core/formatters/transaction_display.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../application/banking_providers.dart';
import 'widgets/banking_tiles.dart';

/// The activity ledger: every movement, newest first, cut into days.
///
/// A utility screen, written as one — no arrival moment, no stagger, no sheen.
/// What it gets instead is rhythm: one [ExampleSectionTitle] per day carrying
/// that day's net on the right in the tertiary ink, and under it a single
/// [ExampleListGroup] of [ExampleRow]s, so the eye runs down one column of
/// tabular figures instead of hopping between cards. Credits take the success
/// token and debits the danger token, both re-resolved for the active
/// brightness inside [ExampleRowValue], so the sign reads on paper as well as
/// on the night ground.
///
/// Outside the Example theme the screen renders the `NeoGroupedCard` of
/// `TransactionTile`s it always did.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final transactions = ref.watch(transactionsProvider);
    final isExample = context.isExampleTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Transactions')),
        actions: [
          IconButton(
            tooltip: context.tr('Settings'),
            onPressed: () => context.go('/profile'),
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: transactions.when(
        data: (items) => items.isEmpty
            ? EmptyState(
                title: context.tr('No activity yet'),
                message:
                    context.tr('Transfers and card payments will appear here.'),
                icon: Icons.receipt_long_outlined,
              )
            : RefreshIndicator(
                onRefresh: () => ref.refresh(transactionsProvider.future),
                child: isExample
                    ? _ExampleActivityList(transactions: items)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.xs,
                          AppSpacing.md,
                          110,
                        ),
                        children: [
                          NeoGroupedCard(
                            children: [
                              for (final transaction in items)
                                TransactionTile(transaction: transaction),
                            ],
                          ),
                        ],
                      ),
              ),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(transactionsProvider),
        ),
        loading: () => LoadingState(
          label: context.tr('Loading activity'),
        ),
      ),
    );
  }
}

/// One day header, one group of rows, repeated. Nothing here animates beyond
/// the row's own press: a ledger is read hundreds of times a day, and the
/// law's frequency gate puts anything at that cadence below the 120 ms press.
class _ExampleActivityList extends StatelessWidget {
  const _ExampleActivityList({required this.transactions});

  final List<LedgerTransaction> transactions;

  @override
  Widget build(BuildContext context) {
    final days = _groupByDay(transactions);
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        110,
      ),
      children: [
        for (var index = 0; index < days.length; index++) ...[
          _ExampleDayHeader(day: days[index], first: index == 0),
          ExampleListGroup(
            children: [
              for (final transaction in days[index].transactions)
                _ExampleActivityRow(transaction: transaction),
            ],
          ),
        ],
      ],
    );
  }
}

/// `Today   −$174.25`: the date on the left in the section voice, the day's
/// net on the right in the tertiary ink, tabular so the column of day totals
/// lines up with the amounts underneath it.
class _ExampleDayHeader extends StatelessWidget {
  const _ExampleDayHeader({required this.day, required this.first});

  final _ActivityDay day;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final total = day.net;
    return Padding(
      padding: EdgeInsets.only(
        top: first ? 0 : AppSpacing.lg,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(child: ExampleSectionTitle(title: _dayLabel(day.date))),
          if (total != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              total,
              maxLines: 1,
              softWrap: false,
              semanticsLabel: context.tr('Net for the day {p0}', {'p0': total}),
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

/// `Card payment / 15:24 · Card   −$12.00`. The date lives in the header, so
/// the row carries the time and the kind of movement instead.
class _ExampleActivityRow extends StatelessWidget {
  const _ExampleActivityRow({required this.transaction});

  final LedgerTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final amount = transaction.displayAmount;
    final title = transactionDisplayTitle(transaction.title);
    final status = transactionDisplayStatus(transaction.subtitle);
    final credit = amount.minorUnits >= 0;
    return ExampleRow(
      title: title,
      subtitle: _rowDescriptor(transaction),
      leading: ExampleIconTile(
        icon: _iconForType(transaction.type),
        color: _tintForType(transaction.type),
      ),
      trailing: ExampleRowValue(
        value: amount.formatted,
        color: credit ? ExampleColors.success : ExampleColors.danger,
        caption: status,
      ),
      semanticsLabel: '$title, ${amount.formatted}, $status',
    );
  }
}

/// One day of the ledger.
class _ActivityDay {
  _ActivityDay(this.date, this.transactions);

  final DateTime date;
  final List<LedgerTransaction> transactions;

  /// The day's net, formatted, when every row on it shares one currency. A
  /// day that mixes currencies has no honest single total, so it shows none.
  String? get net {
    final currency =
        transactions.first.displayAmount.currency.trim().toUpperCase();
    var minorUnits = 0;
    for (final transaction in transactions) {
      final amount = transaction.displayAmount;
      if (amount.currency.trim().toUpperCase() != currency) return null;
      minorUnits += amount.minorUnits;
    }
    return Money(currency: currency, minorUnits: minorUnits).formatted;
  }
}

/// Newest day first, newest row first inside it. Sorted here, in presentation,
/// because a provider is free to return rows in any order and a day header may
/// only appear once.
List<_ActivityDay> _groupByDay(List<LedgerTransaction> transactions) {
  final sorted = [...transactions]
    ..sort((a, b) => b.bookedAt.compareTo(a.bookedAt));
  final days = <_ActivityDay>[];
  for (final transaction in sorted) {
    final day = DateUtils.dateOnly(transaction.bookedAt);
    if (days.isEmpty || days.last.date != day) {
      days.add(_ActivityDay(day, [transaction]));
    } else {
      days.last.transactions.add(transaction);
    }
  }
  return days;
}

String _dayLabel(DateTime day) {
  final today = DateUtils.dateOnly(DateTime.now());
  if (day == today) return 'Today';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
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
  return '${day.day} ${months[day.month - 1]}';
}

String _rowDescriptor(LedgerTransaction transaction) {
  final date = transaction.bookedAt;
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute · ${_typeLabel(transaction.type)}';
}

String _typeLabel(TransactionType type) => switch (type) {
      TransactionType.card => 'Card',
      TransactionType.transfer => 'Transfer',
      TransactionType.topUp => 'Top-up',
      TransactionType.payment => 'Payment',
      TransactionType.fee => 'Fee',
    };

IconData _iconForType(TransactionType type) => switch (type) {
      TransactionType.card => Icons.credit_card_rounded,
      TransactionType.transfer => Icons.swap_horiz_rounded,
      TransactionType.topUp => Icons.add_card_outlined,
      TransactionType.payment => Icons.receipt_long_rounded,
      TransactionType.fee => Icons.percent_rounded,
    };

/// The category tint. Brand tokens only: `ExampleIconTile` washes its tile in
/// the hue and deepens the glyph for whichever theme is active, so none of
/// these ever reaches a `TextStyle` or a fill directly.
Color _tintForType(TransactionType type) => switch (type) {
      TransactionType.card => ExampleColors.violet,
      TransactionType.transfer => ExampleColors.iris,
      TransactionType.topUp => ExampleColors.success,
      TransactionType.payment => ExampleColors.teal,
      TransactionType.fee => ExampleColors.warning,
    };
