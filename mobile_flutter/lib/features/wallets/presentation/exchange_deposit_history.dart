import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../domain/exchange_models.dart';
import '../../platform/application/platform_providers.dart';
import 'exchange_support.dart';

class ExchangeDepositHistory extends StatelessWidget {
  const ExchangeDepositHistory({super.key, required this.deposits});
  final List<BoomFiDeposit> deposits;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deposit history',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (deposits.isEmpty)
            const Text(
                'Incoming Exchange deposits will appear here when the provider reports them.'),
          for (final deposit in deposits.take(5))
            ExchangeDepositCard(deposit: deposit),
          if (deposits.length > 5)
            TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: const Text('Deposit history'),
                            content: SizedBox(
                                width: 560,
                                child: ListView(shrinkWrap: true, children: [
                                  for (final deposit in deposits)
                                    ExchangeDepositCard(deposit: deposit)
                                ])),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Done'))
                            ])),
                child: const Text('Show all deposits')),
        ],
      );
}

class ExchangeDepositCard extends StatefulWidget {
  const ExchangeDepositCard({super.key, required this.deposit});
  final BoomFiDeposit deposit;

  @override
  State<ExchangeDepositCard> createState() => _ExchangeDepositCardState();
}

class _ExchangeDepositCardState extends State<ExchangeDepositCard> {
  bool _expanded = false;

  Future<void> _verify() async {
    try {
      await openExchangeUrl(widget.deposit.verificationUrl!);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open verification. Please try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final deposit = widget.deposit;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final date = deposit.createdAt?.toLocal();
    final timestamp = date == null
        ? ''
        : '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} · '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final network = deposit.chainId > 0
        ? exchangeNetworkName(deposit.chainId)
        : deposit.currency;
    final statusColor = deposit.requiresAction || deposit.status == 'failed'
        ? colors.error
        : colors.onSurfaceVariant;
    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            deposit.requiresAction
                ? Icons.shield_outlined
                : deposit.status == 'completed'
                    ? Icons.check_circle_outline
                    : deposit.status == 'failed'
                        ? Icons.error_outline
                        : Icons.schedule,
            size: 14,
            color: statusColor),
        const SizedBox(width: 6),
        Flexible(
            child: Text(deposit.statusLabel,
                style: theme.textTheme.labelMedium?.copyWith(
                    color: statusColor, fontWeight: FontWeight.w600))),
      ]),
    );
    return Container(
      key: ValueKey('deposit-${deposit.paymentId}'),
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .6)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, constraints) {
            final identity =
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(12)),
                child: Icon(
                    deposit.isDeposit ? Icons.south_west : Icons.north_east,
                    color: colors.primary,
                    size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('${deposit.amount} ${deposit.currency}',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('${deposit.paymentMethod} · $network',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    if (timestamp.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(timestamp,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant)),
                    ],
                  ])),
            ]);
            if (constraints.maxWidth < 520) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    identity,
                    const SizedBox(height: 12),
                    badge,
                  ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: identity),
              const SizedBox(width: 16),
              badge,
            ]);
          }),
          if (deposit.requiresAction) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: colors.primary.withValues(alpha: .14)),
              ),
              child: LayoutBuilder(builder: (context, constraints) {
                final explanation = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verify the source of funds',
                          style: theme.textTheme.labelLarge
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(
                          deposit.isDeposit
                              ? 'Complete the Travel Rule check to release this deposit.'
                              : 'Complete the Travel Rule check to continue this payment.',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant, height: 1.45)),
                    ]);
                final action = deposit.verificationUrl == null
                    ? Text('Refresh Exchange to get a verification link.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant))
                    : FilledButton.icon(
                        key: ValueKey('verify-deposit-${deposit.paymentId}'),
                        onPressed: _verify,
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 42),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(deposit.isDeposit
                            ? 'Verify deposit'
                            : 'Verify payment'));
                if (constraints.maxWidth < 620) {
                  return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        explanation,
                        const SizedBox(height: 12),
                        action,
                      ]);
                }
                return Row(children: [
                  Expanded(child: explanation),
                  const SizedBox(width: 24),
                  action
                ]);
              }),
            ),
          ] else if (deposit.status == 'pending' && deposit.isDeposit) ...[
            const SizedBox(height: 12),
            Text('The provider is still processing this payment. Check Exchange balances for your available funds.',
                style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.45)),
          ] else if (deposit.status == 'failed') ...[
            const SizedBox(height: 12),
            Text(
                'The provider reported this payment as failed. Contact support with the payment ID.',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: colors.error)),
          ],
          const SizedBox(height: 10),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('deposit-details-${deposit.paymentId}'),
                onPressed: () => setState(() => _expanded = !_expanded),
                style: TextButton.styleFrom(
                    foregroundColor: colors.onSurfaceVariant,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                    minimumSize: const Size(0, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18),
                label: Text(_expanded ? 'Hide details' : 'Transaction details'),
              )),
          if (_expanded) ...[
            const SizedBox(height: 4),
            Divider(
                height: 1, color: colors.outlineVariant.withValues(alpha: .5)),
            const SizedBox(height: 8),
            Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(children: [
                    _DepositDetailValue(
                        label: 'Payment ID', value: deposit.paymentId),
                    if (deposit.transactionHash.isNotEmpty)
                      _DepositDetailValue(
                          label: 'Blockchain transaction',
                          value: deposit.transactionHash),
                    if (deposit.settlementTransactionHash.isNotEmpty)
                      _DepositDetailValue(
                          label: 'Settlement transaction',
                          value: deposit.settlementTransactionHash),
                  ]),
                )),
          ],
        ]),
      ),
    );
  }
}

class _DepositDetailValue extends StatelessWidget {
  const _DepositDetailValue({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final short = value.length > 30
        ? '${value.substring(0, 14)}…${value.substring(value.length - 10)}'
        : value;
    final identifier = Row(children: [
      Expanded(
          child: Tooltip(
              message: value,
              child: Text(short,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(fontFamily: 'monospace')))),
      IconButton(
        tooltip: 'Copy $label',
        icon: const Icon(Icons.copy_outlined, size: 16),
        onPressed: () async {
          try {
            await Clipboard.setData(ClipboardData(text: value));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('$label copied'),
                  duration: const Duration(seconds: 2)));
            }
          } catch (_) {
            if (context.mounted) {
              showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                          title: Text(label),
                          content: SelectableText(value),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Done'))
                          ]));
            }
          }
        },
      ),
    ]);
    return LayoutBuilder(
        builder: (context, constraints) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: constraints.maxWidth < 520
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                          identifier,
                        ])
                  : Row(children: [
                      SizedBox(
                          width: 170,
                          child: Text(label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant))),
                      Expanded(child: identifier),
                    ]),
            ));
  }
}

/// Activity receipts use the same payment state as Exchange. Fetch the current
/// action link instead of embedding bearer URLs in general transaction exports.
class ExchangeDepositReceipt extends ConsumerWidget {
  const ExchangeDepositReceipt({super.key, required this.deposit});
  final BoomFiDeposit deposit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(exchangeOverviewProvider);
    final current = [
          ...?overview.valueOrNull?.payments,
          ...?overview.valueOrNull?.deposits
        ].where((item) => item.paymentId == deposit.paymentId).firstOrNull ??
        deposit;
    return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          if (overview.isLoading) const LinearProgressIndicator(),
          ExchangeDepositCard(deposit: current),
          TextButton(
              onPressed: () => context.go('/wallets/exchange'),
              child: const Text('Open Exchange')),
          TextButton(
              onPressed: () => ref.invalidate(exchangeOverviewProvider),
              child: const Text('Refresh status')),
        ]));
  }
}
