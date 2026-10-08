import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';

/// Transaction status: four counts and the three jobs that act on them.
///
/// A utility screen — no arrival moment. The counts are rows with tabular
/// figures rather than a grid of little cards, so they line up digit for digit
/// and read as a ledger; the one semantic colour on the screen is the health
/// pill beside the lede.
class TransactionStatusScreen extends ConsumerWidget {
  const TransactionStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Transaction status'))),
        body: context.isExampleTheme ? const _ExampleBody() : const _LegacyBody(),
      ),
    );
  }
}

class _ExampleBody extends ConsumerWidget {
  const _ExampleBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(transactionStatsProvider);
    final summary = stats.valueOrNull;

    return ListView(
      padding: platformExamplePadding,
      children: [
        PlatformLede(
          text: context.tr(
              'How the ledger is settling, and the jobs that move it along.'),
          trailing: summary == null ? null : _healthPill(context, summary),
        ),
        platformSectionGap,
        ExampleStateSwitch(
          alignment: Alignment.topCenter,
          child: stats.when(
            data: (value) => _Counts(
              key: const ValueKey('status-data'),
              summary: value,
            ),
            error: (error, stackTrace) => PlatformErrorState(
              key: const ValueKey('status-error'),
              error: error,
              onRetry: () => ref.invalidate(transactionStatsProvider),
            ),
            loading: () => PlatformLoadingGroup(
              key: const ValueKey('status-loading'),
              title: context.tr('Ledger'),
              rows: 4,
              label: context.tr('Loading status'),
            ),
          ),
        ),
        if (stats.when(
          data: (_) => true,
          error: (_, __) => false,
          loading: () => false,
        )) ...[
          platformSectionGap,
          ExampleListGroup(
            title: context.tr('Jobs'),
            children: [
              PlatformActionRow(
                icon: Icons.file_download_outlined,
                label: context.tr('Export transactions'),
                description:
                    context.tr('Builds a statement file for the account'),
                onPressed: (context, ref) => ref
                    .read(platformActionControllerProvider.notifier)
                    .run((api) => api.exportTransactions()),
              ),
              PlatformActionRow(
                icon: Icons.sync_rounded,
                label: context.tr('Sync transactions'),
                description:
                    context.tr('Pulls the latest state from the providers'),
                onPressed: (context, ref) => ref
                    .read(platformActionControllerProvider.notifier)
                    .run((api) => api.syncTransactions()),
              ),
              PlatformActionRow(
                icon: Icons.search_rounded,
                label: context.tr('Load transaction detail'),
                description:
                    context.tr('Opens details for a single transaction'),
                onPressed: (context, ref) => ref
                    .read(platformActionControllerProvider.notifier)
                    .run((api) async {
                  final transaction = await api.getTransactionDetail('txn_1');

                  return ActionResult(
                    message: transaction.title,
                    reference: transaction.id,
                    metadata: transaction.metadata,
                  );
                }),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Counts extends StatelessWidget {
  const _Counts({required this.summary, super.key});

  final TransactionStatusSummary summary;

  @override
  Widget build(BuildContext context) => ExampleListGroup(
        title: context.tr('Ledger'),
        children: [
          // Conditional at the call site, not a shrunk child: the group draws
          // a hairline between every pair of children, and a zero-height
          // first child would leave a stray rule across the top of the list.
          if (summary.totalCount > 0) _SettlementBar(summary: summary),
          _CountRow(
            icon: Icons.receipt_long_outlined,
            label: context.tr('Total'),
            value: summary.totalCount,
          ),
          _CountRow(
            icon: Icons.check_circle_outline,
            label: context.tr('Completed'),
            value: summary.completedCount,
          ),
          _CountRow(
            icon: Icons.schedule_rounded,
            label: context.tr('Pending'),
            value: summary.pendingCount,
          ),
          _CountRow(
            icon: Icons.error_outline_rounded,
            label: context.tr('Failed'),
            value: summary.failedCount,
          ),
        ],
      );
}

/// The ledger as one proportion, above the four counts that name its parts.
///
/// Four numbers in a column say what happened; they do not say how much of it
/// happened. "6 failed" is a crisis at a total of 20 and a rounding error at
/// a total of 40,000, and the reader should not have to divide to find out.
/// The bar answers that in one glance and costs 8 logical pixels, which is
/// the whole argument for putting a chart on a utility screen at all.
///
/// Grounded, not decorative: it has a baseline (the track), a real scale
/// (the segments are exact fractions of the total, in the same order as the
/// rows beneath), and the caption states the split in words — so the colour
/// reinforces a reading that is already complete without it.
class _SettlementBar extends StatelessWidget {
  const _SettlementBar({required this.summary});

  final TransactionStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    // No total, no proportion: the caller drops this widget entirely rather
    // than shrinking it, because an empty ledger should get the rows and
    // nothing else — a bar of pure track implies a denominator that is not
    // there. This guard only keeps the arithmetic below honest.
    final total = summary.totalCount;
    if (total <= 0) return const SizedBox.shrink();

    final settled = summary.completedCount.clamp(0, total);
    final pending = summary.pendingCount.clamp(0, total);
    final failed = summary.failedCount.clamp(0, total);
    final parts = <String>[
      if (settled > 0) '$settled settled',
      if (pending > 0) '$pending pending',
      if (failed > 0) '$failed failed',
    ];
    final reading = parts.isEmpty ? '$total recorded' : parts.join('  ·  ');

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Semantics(
        label: context
            .tr('Of {p0} transactions, {p1}.', {'p0': total, 'p1': reading}),
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _SettlementPainter.thickness,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _SettlementPainter(
                    total: total,
                    settled: settled,
                    pending: pending,
                    failed: failed,
                    track: ExampleSurface.of(context, 2),
                    settledInk: ExampleInk.accent(context, ExampleColors.success),
                    pendingInk: ExampleInk.accent(context, ExampleColors.warning),
                    failedInk: ExampleInk.accent(context, ExampleColors.danger),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              reading,
              maxLines: 2,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                // Secondary ink, not the segment hues: three coloured words
                // on one line is a legend, and the bar already is one.
                color: ExampleInk.secondary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettlementPainter extends CustomPainter {
  const _SettlementPainter({
    required this.total,
    required this.settled,
    required this.pending,
    required this.failed,
    required this.track,
    required this.settledInk,
    required this.pendingInk,
    required this.failedInk,
  });

  final int total;
  final int settled;
  final int pending;
  final int failed;
  final Color track;
  final Color settledInk;
  final Color pendingInk;
  final Color failedInk;

  static const double thickness = 8;

  /// A count that exists is always drawn wide enough to see. One failure in
  /// forty thousand is a sub-pixel slice, and rounding it away would let the
  /// bar state something the numbers below it contradict.
  static const double _minVisible = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || total <= 0) return;
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );

    final widths = <double>[];
    for (final count in [settled, pending, failed]) {
      widths.add(count <= 0
          ? 0
          : (count / total * size.width).clamp(_minVisible, size.width));
    }
    final drawn = widths.fold<double>(0, (sum, width) => sum + width);
    // Minimum widths can push the run past the track; scale the whole run
    // back rather than letting the last segment fall off the end.
    final scale = drawn > size.width ? size.width / drawn : 1.0;

    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(Offset.zero & size, radius));
    final inks = [settledInk, pendingInk, failedInk];
    var x = 0.0;
    for (var index = 0; index < widths.length; index++) {
      final width = widths[index] * scale;
      if (width <= 0) continue;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, width, size.height),
        Paint()..color = inks[index],
      );
      x += width;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SettlementPainter oldDelegate) =>
      oldDelegate.total != total ||
      oldDelegate.settled != settled ||
      oldDelegate.pending != pending ||
      oldDelegate.failed != failed ||
      oldDelegate.track != track ||
      oldDelegate.settledInk != settledInk ||
      oldDelegate.pendingInk != pendingInk ||
      oldDelegate.failedInk != failedInk;
}

class _CountRow extends StatelessWidget {
  const _CountRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => ExampleRow(
        leading: ExampleIconTile(icon: icon, color: ExampleColors.iris),
        title: label,
        semanticsLabel: '$label $value',
        trailing: ExampleRowValue(value: '$value'),
      );
}

/// One pill, one hue: what the ledger needs from the operator right now.
Widget _healthPill(BuildContext context, TransactionStatusSummary summary) {
  if (summary.failedCount > 0) {
    return ExamplePill(
      label: context.tr('{p0} failed', {'p0': summary.failedCount}),
      color: ExampleColors.danger,
      dot: true,
    );
  }
  if (summary.pendingCount > 0) {
    return ExamplePill(
      label: context.tr('{p0} pending', {'p0': summary.pendingCount}),
      color: ExampleColors.warning,
      dot: true,
    );
  }
  return ExamplePill(
    label: context.tr('All settled'),
    color: ExampleColors.success,
    dot: true,
  );
}

/// The pre-Example screen, kept byte-identical for every white-label tenant.
class _LegacyBody extends ConsumerWidget {
  const _LegacyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(transactionStatsProvider);

    return stats.when(
      data: (summary) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatsGrid(summary: summary),
          const SizedBox(height: 16),
          ActionButton(
            icon: Icons.file_download_outlined,
            label: context.tr('Export transactions'),
            onPressed: (ref) => ref
                .read(platformActionControllerProvider.notifier)
                .run((api) => api.exportTransactions()),
          ),
          const SizedBox(height: 8),
          ActionButton(
            icon: Icons.sync,
            label: context.tr('Sync transactions'),
            onPressed: (ref) => ref
                .read(platformActionControllerProvider.notifier)
                .run((api) => api.syncTransactions()),
          ),
          const SizedBox(height: 8),
          ActionButton(
            icon: Icons.search,
            label: context.tr('Load transaction detail'),
            onPressed: (ref) => ref
                .read(platformActionControllerProvider.notifier)
                .run((api) async {
              final transaction = await api.getTransactionDetail('txn_1');

              return ActionResult(
                message: transaction.title,
                reference: transaction.id,
                metadata: transaction.metadata,
              );
            }),
          ),
        ],
      ),
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(transactionStatsProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading status')),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.summary});

  final TransactionStatusSummary summary;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _StatCard(label: context.tr('Total'), value: summary.totalCount),
        _StatCard(
            label: context.tr('Completed'), value: summary.completedCount),
        _StatCard(label: context.tr('Pending'), value: summary.pendingCount),
        _StatCard(label: context.tr('Failed'), value: summary.failedCount),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value.toString(),
                style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ],
        ),
      ),
    );
  }
}
