import '../../../core/models/group_card_fees.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';

import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_typography.dart' show ExampleTextStyles;
import '../../../brands/example/example_ui.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../shared/shared.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../application/transaction_identity_provider.dart';
import '../domain/transaction_identity.dart';
import '../domain/transaction_network.dart';
import '../export/transaction_pdf_export_button.dart';
import 'activity_transaction_icon.dart';
import 'transaction_invoices.dart';

class TransactionDetailScreen extends ConsumerWidget {
  const TransactionDetailScreen({
    required this.transactionId,
    this.cardId,
    super.key,
  });

  final String transactionId;

  /// When opened from a card's activity list the transaction lives in the
  /// card ledger rather than the account ledger, so we look it up there.
  final String? cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardId = this.cardId;
    final fromCard = cardId != null && cardId.isNotEmpty;
    final transactions = fromCard
        ? ref.watch(cardTransactionsProvider(cardId)).whenData(
              (items) => items
                  .map(_ledgerTransactionFromCardResource)
                  .toList(growable: false),
            )
        : ref.watch(activityTransactionsProvider);
    final backRoute =
        fromCard ? '/cards/$cardId/transactions' : AppRoutes.activity;
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    final exportTransaction = transactions.isLoading || transactions.hasError
        ? null
        : _findTransaction(transactions.valueOrNull ?? const [], transactionId);
    final exportIdentity = exportTransaction == null
        ? null
        : (fromCard ? ref.watch(cardIdentityProvider(cardId)) : null) ??
            ref.watch(transactionIdentityProvider(exportTransaction));

    void retry() => fromCard
        ? ref.invalidate(cardTransactionsProvider(cardId))
        : ref.invalidate(activityTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        centerTitle: isExample && !desktop,
        leading: isExample && !desktop
            ? IconButton(
                tooltip: context.tr('Back'),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(backRoute),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              )
            : null,
        title: Text(desktop
            ? context.tr('Transaction details')
            : context.tr('Transaction')),
        actions: [
          TransactionPdfExportButton(
            transactions:
                exportTransaction == null ? null : [exportTransaction],
            receipt: true,
            identityFor: (_) => exportIdentity,
          ),
        ],
      ),
      body: transactions.when(
        data: (items) {
          final transaction = _findTransaction(items, transactionId);
          if (transaction == null) {
            return isExample
                ? _ExampleDetailHost(
                    child: ExampleEmptyState(
                      title: context.tr('Transaction not found'),
                      body:
                          context.tr('This transaction may still be syncing.'),
                      icon: Icons.receipt_long_outlined,
                    ),
                  )
                : EmptyState(
                    title: context.tr('Transaction not found'),
                    message:
                        context.tr('This transaction may still be syncing.'),
                    icon: Icons.receipt_long_outlined,
                  );
          }

          final identity =
              (fromCard ? ref.watch(cardIdentityProvider(cardId)) : null) ??
                  ref.watch(transactionIdentityProvider(transaction));
          return _TransactionDetail(
            transaction: transaction,
            identity: identity,
          );
        },
        error: (error, stackTrace) => ErrorState(error: error, onRetry: retry),
        loading: () => isExample
            ? const _ExampleDetailLoading()
            : LoadingState(label: context.tr('Loading transaction')),
      ),
    );
  }
}

bool _hasChargedFees(LedgerTransaction transaction) {
  final charged = transaction.cardFees.where(cardFeeWasCharged);
  return charged.isNotEmpty &&
      charged.every((fee) =>
          feeChargedAmount(fee).currency.toUpperCase() ==
          transaction.amount.currency.toUpperCase());
}

Money? _secondaryReceiptAmount(LedgerTransaction transaction) =>
    _hasChargedFees(transaction)
        ? transaction.displayAmount
        : transaction.secondarySettlementAmount;

String _secondaryReceiptLabel(LedgerTransaction transaction) =>
    _hasChargedFees(transaction) ? 'Purchase amount: {p0}' : '{p0} settled';

class _CardFeeDetails extends StatelessWidget {
  const _CardFeeDetails({required this.transaction});
  final LedgerTransaction transaction;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Card fees'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          NeoGroupedCard(children: [
            _DetailRow(
                label: context.tr('Purchase amount'),
                value: transaction.displayAmount.formatted),
            for (final fee in transaction.cardFees)
              _DetailRow(
                  label: context.tr(cardFeeLabel(fee)),
                  value:
                      '${feeChargedAmount(fee).currency} ${feeChargedAmount(fee).decimalAmount.abs().toStringAsFixed(2)} · ${cardFeeWasCharged(fee) ? 'Charged' : fee.status}'),
            if (transaction.cardFees.any(cardFeeWasCharged) &&
                transaction.cardFees.where(cardFeeWasCharged).every((fee) =>
                    feeChargedAmount(fee).currency.toUpperCase() ==
                    transaction.amount.currency.toUpperCase()))
              _DetailRow(
                  label: context.tr('Total including fees'),
                  value: cardListAmount(transaction).formatted),
          ]),
        ],
      );
}

class _TransactionDetail extends StatelessWidget {
  const _TransactionDetail({required this.transaction, this.identity});

  final LedgerTransaction transaction;
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final displayAmount = cardListAmount(transaction);
    final positive = displayAmount.isPositive;
    final metadataRows = _metadataRows(transaction.metadata);
    final isExample = context.isExampleTheme;

    if (isExample) {
      return _ExampleTransactionDetail(
        transaction: transaction,
        metadataRows: metadataRows,
        identity: identity,
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        isExample ? 20 : 16,
        12,
        isExample ? 20 : 16,
        isExample ? 110 : 28,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isExample ? null : colorScheme.surfaceContainerHighest,
              gradient: isExample
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        ExamplePalette.of(context).surface,
                        ExamplePalette.of(context).surfaceHigh,
                      ],
                    )
                  : null,
              borderRadius: BorderRadius.circular(isExample ? 22 : 8),
              border: Border.all(
                color: isExample
                    ? ExamplePalette.of(context).borderSubtle
                    : colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CurrencyLogo(
                  symbol: displayAmount.currency,
                  size: 52,
                  fallbackIcon: activityTransactionIcon(transaction),
                ),
                const SizedBox(height: 16),
                Text(
                  displayAmount.formatted,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: positive
                            ? ExamplePalette.of(context).design.color(
                                  Theme.of(context).brightness,
                                  'success',
                                  fallback: Colors.green.shade700,
                                )
                            : null,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (_secondaryReceiptAmount(transaction)
                    case final amount?) ...[
                  const SizedBox(height: 4),
                  Text(
                    context.tr(_secondaryReceiptLabel(transaction),
                        {'p0': amount.formatted}),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 6),
                Text(
                  transaction.title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  fallbackText(transaction.subtitle, 'No additional details'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          NeoGroupedCard(
            children: [
              _DetailRow(
                  label: context.tr('Status'), value: _statusFor(transaction)),
              _DetailRow(
                  label: context.tr('Type'), value: transaction.displayType),
              if (identity != null)
                _DetailRow(
                    label: context.tr('Account / card'), value: identity!),
              _DetailRow(label: context.tr('Reference'), value: transaction.id),
              _DetailRow(
                label: context.tr('Booked'),
                value: transaction.hasBookedAt
                    ? _dateLabel(transaction.bookedAt)
                    : 'Unavailable',
              ),
              if (transactionNetworkLabel(transaction) case final network?)
                _DetailRow(label: context.tr('Network'), value: network),
            ],
          ),
          if (transaction.cardFees.isNotEmpty) ...[
            const SizedBox(height: 24),
            _CardFeeDetails(transaction: transaction),
          ],
          const SizedBox(height: 24),
          TransactionInvoices(
              key: ValueKey(transaction.id), transactionId: transaction.id),
          if (metadataRows.isNotEmpty) ...[
            const SizedBox(height: 24),
            ExpansionTile(
              title: Text(context.tr('Advanced details')),
              children: [
                NeoGroupedCard(children: [
                  for (final row in metadataRows)
                    _DetailRow(label: row.label, value: row.value),
                ]),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ExampleTransactionDetail extends StatelessWidget {
  const _ExampleTransactionDetail({
    required this.transaction,
    required this.metadataRows,
    this.identity,
  });

  final LedgerTransaction transaction;
  final List<({String label, String value})> metadataRows;
  final String? identity;

  @override
  Widget build(BuildContext context) {
    final status = _statusFor(transaction);
    final statusColor = _statusColor(status);
    // Only 'Pending' and 'Complete' are points on the way to settlement.
    // 'Booked' is the ledger saying it does not know, and 'Declined' is a
    // transaction that will never reach the second node — a track drawn over
    // either would be an invented fact, so both keep the pill.
    final tracked = status == 'Pending' || status == 'Complete';

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _ExampleDetailLayout.twoColumn;
        final inset = wide
            ? _ExampleDetailLayout.widePadding
            : _ExampleDetailLayout.padding;

        final summary = _ExampleDetailSummary(
          transaction: transaction,
          status: status,
          statusColor: statusColor,
          tracked: tracked,
          alignment:
              wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        );

        final facts = ExampleListGroup(
          dividerInset: AppSpacing.md,
          children: [
            // The state moves up into the settlement track when there is
            // one. Saying it twice on one receipt makes the reader check
            // whether the two copies disagree. The booking timestamp stays
            // here: the track answers "is this final", the record answers
            // "when", and neither repeats the other.
            if (!tracked)
              _ExampleDetailRow(
                label: context.tr('Status'),
                value: status,
                valueColor: statusColor,
              ),
            _ExampleDetailRow(
                label: context.tr('Type'), value: transaction.displayType),
            if (identity != null)
              _ExampleDetailRow(
                label: context.tr('Account / card'),
                value: identity!,
                mono: true,
              ),
            _ExampleDetailRow(
              label: context.tr('Booked'),
              value: transaction.hasBookedAt
                  ? _dateLabel(transaction.bookedAt)
                  : 'Unavailable',
            ),
            if (transactionNetworkLabel(transaction) case final network?)
              _ExampleDetailRow(label: context.tr('Network'), value: network),
            _ExampleDetailRow(
              label: context.tr('Reference'),
              value: transaction.id,
              mono: true,
            ),
          ],
        );

        final details = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            facts,
            if (transaction.cardFees.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _CardFeeDetails(transaction: transaction),
            ],
            const SizedBox(height: AppSpacing.lg),
            TransactionInvoices(
                key: ValueKey(transaction.id), transactionId: transaction.id),
            if (metadataRows.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              ExpansionTile(
                title: Text(context.tr('Advanced details')),
                children: [
                  ExampleListGroup(
                    dividerInset: AppSpacing.md,
                    children: [
                      for (final row in metadataRows)
                        _ExampleDetailRow(
                          label: row.label,
                          value: row.value,
                          mono: _looksLikeReference(row.value),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        );

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            inset,
            wide ? AppSpacing.lg : AppSpacing.xs,
            inset,
            AppSpacing.xxl,
          ),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: _ExampleDetailLayout.panelWidth,
                      child: ExampleGlassPanel(
                        material: ExampleGlassMaterial.frosted,
                        radius: AppRadii.lg,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: summary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(child: details),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    summary,
                    const SizedBox(height: AppSpacing.lg),
                    details,
                  ],
                ),
        );
      },
    );
  }
}

abstract final class _ExampleDetailLayout {
  static const double padding = 20;
  static const double widePadding = 32;

  /// Above this the summary becomes a glass side panel; below it the page is
  /// one centred column.
  static const double twoColumn = 900;
  static const double panelWidth = 340;
  static const double avatarSize = 56;
}

/// Merchant, amount, status. The amount is the only hero on the page, and it
/// scales down rather than truncating so a fourteen-character crypto figure
/// still fits a 375 pt screen.
class _ExampleDetailSummary extends StatelessWidget {
  const _ExampleDetailSummary({
    required this.transaction,
    required this.status,
    required this.statusColor,
    required this.tracked,
    required this.alignment,
  });

  final LedgerTransaction transaction;
  final String status;
  final Color statusColor;

  /// The ledger knows whether this settled, so the state is drawn as a track
  /// rather than named in a pill.
  final bool tracked;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    final centred = alignment == CrossAxisAlignment.center;
    final textAlign = centred ? TextAlign.center : TextAlign.start;
    final title = transaction.title;
    final amount = cardListAmount(transaction);
    final positive = amount.isPositive;
    final settled = _secondaryReceiptAmount(transaction);
    final place = _placeOf(transaction);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        ExampleTransactionAvatar(
          name: title,
          tint: ExampleTransactionRow.tintFor(_categoryOf(transaction)),
          logoUrl: transaction.merchantLogoUrl,
          fallbackIcon: activityTransactionIcon(transaction),
          size: _ExampleDetailLayout.avatarSize,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          title,
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            height: 1.3,
            color: ExampleInk.primary(context),
          ),
        ),
        if (place != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            place,
            textAlign: textAlign,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: centred ? Alignment.center : Alignment.centerLeft,
            child: Text(
              '${positive ? '+' : ''}${amount.formatted}',
              textAlign: textAlign,
              style: ExampleTextStyles.amount(
                context,
                size: ExampleAmountSize.hero,
              ).copyWith(
                color: positive
                    ? ExamplePalette.of(context).success
                    : ExampleInk.primary(context),
              ),
            ),
          ),
        ),
        if (settled != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.tr(
                _secondaryReceiptLabel(transaction), {'p0': settled.formatted}),
            textAlign: textAlign,
            style: TextStyle(
              fontSize: 12.5,
              color: ExampleInk.tertiary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.sm),
        Align(
          alignment: centred ? Alignment.center : Alignment.centerLeft,
          child: tracked
              ? _ExampleSettlementTrack(
                  bookedAt:
                      transaction.hasBookedAt ? transaction.bookedAt : null,
                  settled: status == 'Complete',
                )
              : ExamplePill(
                  label: status,
                  color: statusColor,
                  dot: true,
                  fontSize: 11,
                ),
        ),
      ],
    );
  }
}

/// Booked, then settled: the receipt's real question drawn as two nodes.
///
/// What a reader wants from a transaction page is not the colour of a status
/// word, it is whether the money is final. A solid node on a solid rule says
/// settled; an open ring on a thin one says not yet, and both survive a
/// greyscale screenshot, a colour-blind reader and a phone in sunlight,
/// because the difference is fill and weight rather than hue. The amber and
/// green are the second, redundant reading, and both clear the 3:1 non-text
/// floor everywhere the track renders.
///
/// Composited on the two scaffold colours this screen paints on —
/// [ExampleColors.appBackground] and [ExampleColors.lightPaper] — success is
/// 10.9:1 and warning 11.3:1 in Twilight, and 4.7:1 and 4.9:1 in daylight,
/// where the palette swaps in [ExampleColors.lightSuccess] and
/// [ExampleColors.lightWarning]. The desktop layout moves the summary into a
/// frosted [ExampleGlassPanel], and that fill is a gradient, so there the two
/// become ranges rather than points: 10.1:1 to 10.5:1 and 10.4:1 to 10.8:1 in
/// Twilight, 5.0:1 down to 4.5:1 and 5.1:1 down to 4.7:1 in daylight,
/// measured at the gradient's two stops. The tightest point on either theme
/// is therefore the daylight panel's lower edge at 4.5:1, half again the
/// floor a non-text element has to clear.
///
/// No timestamp is printed on it. The data contract carries no settlement
/// time, so a dated first node beside an undated second one would read as
/// missing data; instead both nodes name a state, the booking timestamp stays
/// in the record below, and two short words cannot truncate at any width or
/// text scale.
class _ExampleSettlementTrack extends StatelessWidget {
  const _ExampleSettlementTrack({
    required this.bookedAt,
    required this.settled,
  });

  final DateTime? bookedAt;
  final bool settled;

  /// Big enough to read as a node rather than a bullet, small enough that the
  /// pair does not compete with the hero amount above them.
  static const double _node = 12;

  /// The track is a caption, not a layout: uncapped it would stretch the
  /// whole one-column content width, which runs to just under 860 pt at the
  /// top of that layout ([_ExampleDetailLayout.twoColumn] less two
  /// [_ExampleDetailLayout.padding] insets), and two nodes that far apart stop
  /// reading as one track. It also has to fit inside the desktop summary
  /// panel — [_ExampleDetailLayout.panelWidth] less its two `AppSpacing.lg`
  /// insets, so 292 pt — which is the narrowest place it renders.
  static const double _maxWidth = 220;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final open = palette.warning;
    final done = palette.success;
    final booked = bookedAt == null
        ? 'Booking time unavailable'
        : 'Booked ${_dateLabel(bookedAt!)}';

    return Semantics(
      container: true,
      label: settled
          ? context.tr('{p0}, settled', {'p0': booked})
          : context.tr('{p0}, settlement pending', {'p0': booked}),
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _maxWidth),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: _node,
                child: Row(
                  children: [
                    const _ExampleTrackNode(filled: true, color: null),
                    Expanded(
                      child: Center(
                        child: Container(
                          height: settled ? 2 : 1,
                          margin: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                          ),
                          decoration: BoxDecoration(
                            // Weight, not only hue: a settled rail is twice
                            // as thick as an unsettled one. The waiting rail
                            // takes tertiary ink rather than a hairline —
                            // 5.15:1 on the Twilight scaffold and 4.96:1 on
                            // the daylight one, and 5.15:1 to 5.11:1 and
                            // 5.04:1 to 4.89:1 across the frosted desktop
                            // panel — because a rule nobody can see turns the
                            // track into two dots floating apart.
                            color: settled
                                ? done
                                : ExamplePalette.of(context).textTertiary,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                    _ExampleTrackNode(
                      filled: settled,
                      color: settled ? null : open,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxs + 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: _ExampleTrackLabel(
                      title: context.tr('Booked'),
                      textAlign: TextAlign.start,
                      strong: !settled,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: _ExampleTrackLabel(
                      title: settled
                          ? context.tr('Settled')
                          : context.tr('Pending'),
                      textAlign: TextAlign.end,
                      strong: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One node on the settlement track: filled when the step has happened, an
/// open ring when it has not.
class _ExampleTrackNode extends StatelessWidget {
  const _ExampleTrackNode({required this.filled, required this.color});

  final bool filled;

  /// Null takes the success ink; the pending node passes warning.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? ExamplePalette.of(context).success;
    return SizedBox.square(
      dimension: _ExampleSettlementTrack._node,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? ink : Colors.transparent,
          border: filled ? null : Border.all(color: ink, width: 2),
        ),
      ),
    );
  }
}

class _ExampleTrackLabel extends StatelessWidget {
  const _ExampleTrackLabel({
    required this.title,
    required this.textAlign,
    required this.strong,
  });

  final String title;
  final TextAlign textAlign;

  /// The step the reader is actually waiting on carries the primary ink; the
  /// one already behind them steps back to secondary.
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      textAlign: textAlign,
      maxLines: 1,
      style: TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color:
            strong ? ExampleInk.primary(context) : ExampleInk.secondary(context),
      ),
    );
  }
}

/// One fact. Label left in the secondary ink, value right in the primary. The
/// two columns are proportional rather than intrinsic, so a long reference
/// wraps inside its own half instead of pushing the label off the screen.
class _ExampleDetailRow extends StatelessWidget {
  const _ExampleDetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
  });

  final String label;
  final String value;
  final Color? valueColor;

  /// References, hashes and addresses retain every character in Geist Mono.
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final color = valueColor;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: ExampleRow.defaultPadding,
        child: Row(
          children: [
            Expanded(
              flex: 4,
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
            Expanded(
              flex: 6,
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: mono
                      ? ExampleTextStyles.mono(
                          context,
                          size: 12.5,
                          weight: FontWeight.w500,
                        )
                      : TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: color == null
                              ? ExampleInk.primary(context)
                              : ExampleInk.accent(context, color),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Centres a Example empty or error state in the page.
class _ExampleDetailHost extends StatelessWidget {
  const _ExampleDetailHost({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: _ExampleDetailLayout.padding,
          vertical: AppSpacing.xl,
        ),
        child: child,
      ),
    );
  }
}

/// Shape-matched placeholders for the receipt, under the one soft sheen a
/// skeleton is allowed to carry.
class _ExampleDetailLoading extends StatelessWidget {
  const _ExampleDetailLoading();

  @override
  Widget build(BuildContext context) {
    final body = Semantics(
      label: context.tr('Loading transaction'),
      child: ExcludeSemantics(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            _ExampleDetailLayout.padding,
            AppSpacing.xs,
            _ExampleDetailLayout.padding,
            AppSpacing.xxl,
          ),
          child: ExampleSheen(
            intensity: ExampleSheenIntensity.soft,
            borderRadius: BorderRadius.circular(AppRadii.lg),
            child: Column(
              children: [
                // The wrapping ExampleSheen above is this block's single
                // host; every skeleton inside it opts out, or the group
                // becomes four nested hosts and four saveLayers a frame.
                const ExampleSkeleton.avatar(
                  size: _ExampleDetailLayout.avatarSize,
                  sheen: false,
                ),
                const SizedBox(height: AppSpacing.sm),
                const ExampleSkeleton.line(width: 140, sheen: false),
                const SizedBox(height: AppSpacing.sm),
                const ExampleSkeleton.amount(
                  size: ExampleAmountSize.hero,
                  sheen: false,
                ),
                const SizedBox(height: AppSpacing.sm),
                // Stands in for the settlement track, so the facts below
                // it move by the difference rather than by the track's whole
                // height when the receipt lands. Measured at 375 in the
                // default text scale the real track lays out 34 pt tall
                // against the 44 reserved here, so 10 pt of settle is left
                // and the facts rise into it rather than being pushed down.
                const ExampleSkeleton.card(
                  width: 220,
                  height: 44,
                  radius: AppRadii.sm,
                  sheen: false,
                ),
                const SizedBox(height: AppSpacing.lg),
                ExampleListGroup(
                  dividerInset: AppSpacing.md,
                  children: [
                    for (var index = 0; index < 5; index++)
                      const ExampleSkeleton.row(height: 56, avatar: false),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    // The receipt is a `ShellRoute` child, and `BankingShell` already wraps
    // the routed child in a `ExampleAliveLayer`. Adding a scope here without
    // asking would put a second one — and a second ticker, on its own
    // schedule — under the shell's. The skeleton still needs a clock when it
    // is hosted on its own, so it asks rather than assuming either way.
    //
    // Same blind spot as the ledger's: `ExampleAliveLayer(enabled: false)`
    // publishes no binding at all, so `existsAbove` cannot tell a switched-off
    // layer from no layer and this branch would still mount a scope under one.
    if (ExampleSheenScope.existsAbove(context)) return body;
    return ExampleSheenScope(child: body);
  }
}

// Semantic tokens are resolved by ExamplePill and ExampleInk at the point of use.
Color _statusColor(String status) => switch (status) {
      'Pending' => ExampleColors.warning,
      'Complete' => ExampleColors.success,
      'Declined' => ExampleColors.danger,
      _ => ExampleColors.lavender,
    };

/// Everything that might name a category, joined for the avatar tint.
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

/// `Dubai · AE` when the ledger carries a place, null when it does not. No
/// map: there are no coordinates in the data contract, and a decorative map
/// of a guessed city is fake data.
String? _placeOf(LedgerTransaction transaction) {
  String read(List<String> keys) {
    for (final key in keys) {
      final value = transaction.metadata[key];
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
    }
    return '';
  }

  final city = read(const ['merchantCity', 'MerchantCity', 'city', 'City']);
  final country = read(const [
    'merchantCountry',
    'MerchantCountry',
    'country',
    'Country',
    'countryCode',
    'CountryCode',
  ]);
  final parts = [city, country].where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return null;
  return parts.join(' · ');
}

/// A single unspaced token long enough to be a reference, hash or address.
bool _looksLikeReference(String value) =>
    value.length >= 16 && !value.contains(' ');

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------

List<({String label, String value})> _metadataRows(
  Map<String, dynamic> metadata,
) {
  final values = <String, String>{};

  void add(Object? value, String path, String key) {
    if (value == null) return;
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString().trim();
        if (key.isEmpty || _isSensitiveMetadataKey(key)) continue;
        add(entry.value, path.isEmpty ? key : '$path · $key', key);
      }
      return;
    }
    if (value is Iterable) {
      final items = value.where((item) => item != null).toList();
      if (items.isEmpty) return;
      // Flatten nested objects so identity masking and sensitive-key removal
      // also apply inside arrays; raw JSON would bypass both safeguards.
      if (items.any((item) => item is Map || item is Iterable)) {
        for (var index = 0; index < items.length; index++) {
          add(items[index], '$path · ${index + 1}', key);
        }
      } else {
        final display = items
            .map((item) => transactionMetadataDisplayValue(key, item!))
            .whereType<String>()
            .join(', ');
        if (display.isNotEmpty) values[path] = display;
      }
      return;
    }

    final display = transactionMetadataDisplayValue(key, value);
    if (display != null) values[path] = display;
  }

  add(metadata, '', '');
  final rows = values.entries
      .map((entry) => (label: _metadataLabel(entry.key), value: entry.value))
      .toList()
    ..sort((left, right) => left.label.compareTo(right.label));
  return rows;
}

bool _isSensitiveMetadataKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  return normalized.contains('password') ||
      normalized.contains('secret') ||
      normalized.contains('accesstoken') ||
      normalized.contains('refreshtoken') ||
      normalized.contains('cashback');
}

String _metadataLabel(String value) {
  final spaced = value
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAllMapped(
        RegExp(r'([a-z0-9])([A-Z])'),
        (match) => '${match.group(1)} ${match.group(2)}',
      )
      .replaceAll('·', ' · ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (spaced.isEmpty) return 'Metadata';
  return '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

LedgerTransaction? _findTransaction(
  List<LedgerTransaction> items,
  String transactionId,
) {
  for (final item in [...groupCardFees(items), ...items]) {
    if (item.id == transactionId) {
      return item;
    }
  }
  // Card ledgers key rows by their provider reference; fall back to it.
  for (final item in [...groupCardFees(items), ...items]) {
    final reference = item.metadata['reference'] ?? item.metadata['Reference'];
    if (reference?.toString() == transactionId) {
      return item;
    }
  }

  return null;
}

/// Card transactions arrive as raw platform resources; reuse the ledger
/// parser so the detail view renders them like any other transaction.
LedgerTransaction _ledgerTransactionFromCardResource(PlatformResource item) {
  final json = <String, dynamic>{...item.metadata};
  if ((json['id'] ?? json['Id'])?.toString().trim().isEmpty ?? true) {
    json['id'] = item.id;
  }
  if ((json['title'] ?? json['Title'])?.toString().trim().isEmpty ?? true) {
    json['title'] = item.title;
  }
  return LedgerTransaction.fromJson(json);
}

String _dateLabel(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$day.$month.${date.year} $hour:$minute';
}

String _statusFor(LedgerTransaction transaction) {
  final subtitle =
      (transaction.status.isEmpty ? transaction.subtitle : transaction.status)
          .toLowerCase();
  // Hoppa's card ledger says "fail" for a declined purchase.
  if (const {'failed', 'fail', 'declined', 'rejected'}.contains(subtitle)) {
    return 'Declined';
  }
  if (subtitle == 'closed' || subtitle == 'success') return 'Complete';
  if (subtitle.contains('pending')) {
    return 'Pending';
  }
  if (subtitle.contains('settled') || subtitle.contains('complete')) {
    return 'Complete';
  }

  return 'Booked';
}
