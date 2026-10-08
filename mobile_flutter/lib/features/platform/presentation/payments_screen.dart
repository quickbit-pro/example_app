import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

enum _PaymentView { activity, mandates, requests }

/// Payments: what you can create, and what has been created.
///
/// A utility screen — no arrival moment. The six creation actions are method
/// rows with their symbol in a `ExampleIconTile` rather than a grid of filled
/// buttons, the three ledgers sit behind one `ExampleSegmentedControl`, and the
/// switch between them is a `ExampleStateSwitch` at `ExampleMotion.state`: a
/// fade and two pixels, never a slide.
class PaymentsScreen extends ConsumerStatefulWidget {
  const PaymentsScreen({super.key});

  @override
  ConsumerState<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends ConsumerState<PaymentsScreen> {
  _PaymentView _view = _PaymentView.activity;

  @override
  Widget build(BuildContext context) {
    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Payments'))),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: context.isExampleTheme ? _exampleBody() : _legacyBody(),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(paymentsProvider);
    ref.invalidate(mandatesProvider);
    ref.invalidate(paymentRequestsProvider);
    await Future.wait<void>([
      ref.read(paymentsProvider.future).then<void>((_) {}).catchError((_) {}),
      ref.read(mandatesProvider.future).then<void>((_) {}).catchError((_) {}),
      ref
          .read(paymentRequestsProvider.future)
          .then<void>((_) {})
          .catchError((_) {}),
    ]);
  }

  // -- the six creation flows, shared by both brands ------------------------

  void _createPayment() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Create payment'),
        primaryLabel: 'Create payment',
        icon: Icons.payments_outlined,
        defaultReference: 'Merchant',
        currencies: const ['EUR', 'USD', 'USDC', 'USDT'],
        submit: (api, form) => api.createPayment(
          merchantName: form.reference,
          amount: form.money,
        ),
      );

  void _createMandate() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Create mandate'),
        primaryLabel: 'Create mandate',
        icon: Icons.fact_check_outlined,
        referenceLabel: 'Merchant',
        amountLabel: 'Maximum amount',
        defaultReference: 'Merchant',
        submit: (api, form) => api.createMandate(
          form.reference,
          amount: form.money,
        ),
      );

  void _requestPayment() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Request payment'),
        primaryLabel: 'Request payment',
        icon: Icons.request_quote,
        referenceLabel: 'Counterparty',
        defaultReference: 'Customer',
        currencies: const ['EUR', 'USD', 'USDC', 'USDT'],
        submit: (api, form) => api.createPaymentRequest(
          counterparty: form.reference,
          amount: form.money,
        ),
      );

  void _createPayout() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Create payout'),
        primaryLabel: 'Create payout',
        icon: Icons.outbox,
        referenceLabel: 'Destination address',
        defaultReference: '',
        currencies: const ['USDC', 'USDT', 'BTC', 'ETH', 'EUR'],
        submit: (api, form) => api.createPayout(
          destination: form.reference,
          amount: form.money,
        ),
      );

  void _withdraw() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Withdraw'),
        primaryLabel: 'Withdraw',
        icon: Icons.account_balance_wallet_outlined,
        referenceLabel: 'Destination address',
        defaultReference: '',
        currencies: const ['USDC', 'USDT', 'BTC', 'ETH'],
        submit: (api, form) => api.createWithdrawal(
          destination: form.reference,
          amount: form.money,
        ),
      );

  void _withdrawalFee() => _showPaymentForm(
        context,
        ref,
        title: context.tr('Withdrawal fee'),
        primaryLabel: 'Calculate fee',
        icon: Icons.money_off_csred_outlined,
        referenceLabel: 'Destination address',
        defaultReference: '',
        currencies: const ['USDC', 'USDT', 'BTC', 'ETH'],
        submit: (api, form) => api.calculateWithdrawalFee(
          destination: form.reference,
          amount: form.money,
        ),
      );

  // -- Example ---------------------------------------------------------------

  Widget _exampleBody() {
    final payments = ref.watch(paymentsProvider);
    final mandates = ref.watch(mandatesProvider);
    final requests = ref.watch(paymentRequestsProvider);
    final count = switch (_view) {
      _PaymentView.activity => payments.valueOrNull?.length,
      _PaymentView.mandates => mandates.valueOrNull?.length,
      _PaymentView.requests => requests.valueOrNull?.length,
    };
    final noun = switch (_view) {
      _PaymentView.activity => 'payments',
      _PaymentView.mandates => 'mandates',
      _PaymentView.requests => 'requests',
    };

    return ListView(
      padding: platformExamplePadding,
      children: [
        PlatformLede(
          text: context
              .tr('Move money, authorise a merchant, or ask to be paid.'),
          trailing: count == null
              ? null
              : ExamplePill(label: '$count $noun', color: ExampleColors.iris),
        ),
        platformSectionGap,
        ExampleListGroup(
          title: context.tr('Create'),
          children: [
            PlatformActionRow(
              icon: Icons.payments_outlined,
              label: context.tr('Create payment'),
              description: context.tr('Pay a merchant from an account'),
              onPressed: (context, ref) => _createPayment(),
            ),
            PlatformActionRow(
              icon: Icons.fact_check_outlined,
              label: context.tr('Create mandate'),
              description: context.tr('Let a merchant collect up to a limit'),
              onPressed: (context, ref) => _createMandate(),
            ),
            PlatformActionRow(
              icon: Icons.request_quote_outlined,
              label: context.tr('Request payment'),
              description: context.tr('Ask a counterparty to pay you'),
              onPressed: (context, ref) => _requestPayment(),
            ),
            PlatformActionRow(
              icon: Icons.outbox_outlined,
              label: context.tr('Create payout'),
              description: context.tr('Send funds to an external address'),
              onPressed: (context, ref) => _createPayout(),
            ),
            PlatformActionRow(
              icon: Icons.account_balance_wallet_outlined,
              label: context.tr('Withdraw'),
              description: context.tr('Move funds out of the account'),
              onPressed: (context, ref) => _withdraw(),
            ),
            PlatformActionRow(
              icon: Icons.calculate_outlined,
              label: context.tr('Withdrawal fee'),
              description: context.tr('Check the cost before you withdraw'),
              onPressed: (context, ref) => _withdrawalFee(),
            ),
          ],
        ),
        platformSectionGap,
        ExampleSegmentedControl<_PaymentView>(
          segments: [
            (value: _PaymentView.activity, label: context.tr('Activity')),
            (value: _PaymentView.mandates, label: context.tr('Mandates')),
            (value: _PaymentView.requests, label: context.tr('Requests')),
          ],
          selected: _view,
          onChanged: (value) => setState(() => _view = value),
        ),
        const SizedBox(height: AppSpacing.md),
        ExampleStateSwitch(
          alignment: Alignment.topCenter,
          child: KeyedSubtree(
            key: ValueKey(_view),
            child: switch (_view) {
              _PaymentView.activity => _exampleSection(
                  value: payments,
                  icon: Icons.payments_outlined,
                  emptyTitle: context.tr('Payments land here'),
                  emptyMessage: context.tr(
                      'Anything you create shows up in this list once the provider confirms it.'),
                  onRetry: () => ref.invalidate(paymentsProvider),
                ),
              _PaymentView.mandates => _exampleSection(
                  value: mandates,
                  icon: Icons.fact_check_outlined,
                  emptyTitle: context.tr('No merchant is authorised yet'),
                  emptyMessage: context.tr(
                      'Mandates you grant a merchant are listed here, and can be revoked from the row.'),
                  onRetry: () => ref.invalidate(mandatesProvider),
                  trailingBuilder: (resource) => _ResourceAction(
                    tooltip: context.tr('Revoke mandate'),
                    icon: Icons.block_outlined,
                    onPressed: () => _confirmResourceAction(
                      context,
                      ref,
                      title: context.tr('Revoke mandate'),
                      message: context.tr('Revoke {p0}?',
                          {'p0': _resourceDisplayTitle(resource)}),
                      action: (api) => api.revokeMandate(resource.id),
                    ),
                  ),
                ),
              _PaymentView.requests => _exampleSection(
                  value: requests,
                  icon: Icons.request_quote_outlined,
                  emptyTitle: context.tr('Nothing requested yet'),
                  emptyMessage: context.tr(
                      'Payment requests you send appear here until they are paid or cancelled.'),
                  onRetry: () => ref.invalidate(paymentRequestsProvider),
                  trailingBuilder: (resource) => _ResourceAction(
                    tooltip: context.tr('Cancel request'),
                    icon: Icons.cancel_schedule_send_outlined,
                    onPressed: () => _confirmResourceAction(
                      context,
                      ref,
                      title: context.tr('Cancel request'),
                      message: context.tr('Cancel {p0}?',
                          {'p0': _resourceDisplayTitle(resource)}),
                      action: (api) => api.cancelPaymentRequest(resource.id),
                    ),
                  ),
                ),
            },
          ),
        ),
      ],
    );
  }

  Widget _exampleSection({
    required AsyncValue<List<PlatformResource>> value,
    required IconData icon,
    required String emptyTitle,
    required String emptyMessage,
    required VoidCallback onRetry,
    Widget Function(PlatformResource resource)? trailingBuilder,
  }) {
    return value.when(
      data: (items) => items.isEmpty
          ? PlatformEmptyState(
              title: emptyTitle,
              message: emptyMessage,
              icon: icon,
            )
          : ExampleListGroup(
              children: [
                for (final resource in items)
                  ExampleRow(
                    leading: ExampleIconTile(
                      icon: icon,
                      color: ExampleColors.iris,
                    ),
                    title: _resourceDisplayTitle(resource),
                    subtitle: _rowCaption(resource),
                    semanticsLabel: trailingBuilder == null
                        ? context.tr('Open {p0}',
                            {'p0': _resourceDisplayTitle(resource)})
                        : null,
                    trailing: trailingBuilder == null
                        ? ExampleRow.chevronOf(context)
                        : trailingBuilder(resource),
                    onTap: () => _showDetails(context, resource),
                  ),
              ],
            ),
      error: (error, stackTrace) =>
          PlatformErrorState(error: error, onRetry: onRetry),
      loading: () => const PlatformLoadingGroup(),
    );
  }

  // -- every other brand: the pre-Example tree, unchanged --------------------

  Widget _legacyBody() {
    final payments = ref.watch(paymentsProvider);
    final mandates = ref.watch(mandatesProvider);
    final requests = ref.watch(paymentRequestsProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ActionGrid(
          onCreatePayment: _createPayment,
          onCreateMandate: _createMandate,
          onRequestPayment: _requestPayment,
          onCreatePayout: _createPayout,
          onWithdraw: _withdraw,
          onWithdrawalFee: _withdrawalFee,
        ),
        const SizedBox(height: 24),
        _Tabs(
          selected: _view,
          paymentsCount: payments.valueOrNull?.length ?? 0,
          mandatesCount: mandates.valueOrNull?.length ?? 0,
          requestsCount: requests.valueOrNull?.length ?? 0,
          onSelected: (value) => setState(() => _view = value),
        ),
        const SizedBox(height: 16),
        switch (_view) {
          _PaymentView.activity => _ResourceSection(
              title: context.tr('Payment activity'),
              value: payments,
              emptyTitle: context.tr('No payments yet'),
              emptyMessage: context
                  .tr('Created payments will appear here once available.'),
              icon: Icons.payments_outlined,
              onRetry: () => ref.invalidate(paymentsProvider),
            ),
          _PaymentView.mandates => _ResourceSection(
              title: context.tr('Mandates'),
              value: mandates,
              emptyTitle: context.tr('No mandates yet'),
              emptyMessage:
                  context.tr('Saved merchant mandates will appear here.'),
              icon: Icons.fact_check_outlined,
              onRetry: () => ref.invalidate(mandatesProvider),
              trailingBuilder: (resource) => _ResourceAction(
                tooltip: context.tr('Revoke mandate'),
                icon: Icons.block_outlined,
                onPressed: () => _confirmResourceAction(
                  context,
                  ref,
                  title: context.tr('Revoke mandate'),
                  message: context.tr(
                      'Revoke {p0}?', {'p0': _resourceDisplayTitle(resource)}),
                  action: (api) => api.revokeMandate(resource.id),
                ),
              ),
            ),
          _PaymentView.requests => _ResourceSection(
              title: context.tr('Payment requests'),
              value: requests,
              emptyTitle: context.tr('No payment requests'),
              emptyMessage: context.tr('Requested payments will appear here.'),
              icon: Icons.request_quote,
              onRetry: () => ref.invalidate(paymentRequestsProvider),
              trailingBuilder: (resource) => _ResourceAction(
                tooltip: context.tr('Cancel request'),
                icon: Icons.cancel_schedule_send_outlined,
                onPressed: () => _confirmResourceAction(
                  context,
                  ref,
                  title: context.tr('Cancel request'),
                  message: context.tr(
                      'Cancel {p0}?', {'p0': _resourceDisplayTitle(resource)}),
                  action: (api) => api.cancelPaymentRequest(resource.id),
                ),
              ),
            ),
        },
      ],
    );
  }
}

/// One line under a payment row: its own subtitle, then the first fact the
/// payload carries.
String? _rowCaption(PlatformResource resource) {
  final subtitle = _resourceSubtitle(resource);
  final facts = _resourceFacts(resource);
  if (subtitle == null) return facts.isEmpty ? null : facts.join(' · ');
  if (facts.isEmpty) return subtitle;
  return '$subtitle · ${facts.first}';
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onCreatePayment,
    required this.onCreateMandate,
    required this.onRequestPayment,
    required this.onCreatePayout,
    required this.onWithdraw,
    required this.onWithdrawalFee,
  });

  final VoidCallback onCreatePayment;
  final VoidCallback onCreateMandate;
  final VoidCallback onRequestPayment;
  final VoidCallback onCreatePayout;
  final VoidCallback onWithdraw;
  final VoidCallback onWithdrawalFee;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ActionTile(
          icon: Icons.payments_outlined,
          label: context.tr('Create payment'),
          onPressed: onCreatePayment,
        ),
        _ActionTile(
          icon: Icons.fact_check_outlined,
          label: context.tr('Create mandate'),
          onPressed: onCreateMandate,
        ),
        _ActionTile(
          icon: Icons.request_quote,
          label: context.tr('Request payment'),
          onPressed: onRequestPayment,
        ),
        _ActionTile(
          icon: Icons.outbox,
          label: context.tr('Create payout'),
          onPressed: onCreatePayout,
        ),
        _ActionTile(
          icon: Icons.account_balance_wallet_outlined,
          label: context.tr('Withdraw'),
          onPressed: onWithdraw,
        ),
        _ActionTile(
          icon: Icons.money_off_csred_outlined,
          label: context.tr('Withdrawal fee'),
          onPressed: onWithdrawalFee,
        ),
      ],
    );
  }
}

class _ActionTile extends ConsumerWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);
    return FilledButton.icon(
      onPressed: action.isLoading ? null : onPressed,
      icon: action.isLoading
          ? const SizedBox.square(
              dimension: 18,
              child: AppProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(label, overflow: TextOverflow.ellipsis),
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({
    required this.selected,
    required this.paymentsCount,
    required this.mandatesCount,
    required this.requestsCount,
    required this.onSelected,
  });

  final _PaymentView selected;
  final int paymentsCount;
  final int mandatesCount;
  final int requestsCount;
  final ValueChanged<_PaymentView> onSelected;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<_PaymentView>(
      segments: [
        ButtonSegment(
          value: _PaymentView.activity,
          icon: const Icon(Icons.receipt_long_outlined),
          label: Text(context.tr('Activity ({p0})', {'p0': paymentsCount})),
        ),
        ButtonSegment(
          value: _PaymentView.mandates,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(context.tr('Mandates ({p0})', {'p0': mandatesCount})),
        ),
        ButtonSegment(
          value: _PaymentView.requests,
          icon: const Icon(Icons.request_quote),
          label: Text(context.tr('Requests ({p0})', {'p0': requestsCount})),
        ),
      ],
      selected: {selected},
      onSelectionChanged: (values) => onSelected(values.single),
      showSelectedIcon: false,
    );
  }
}

class _ResourceSection extends StatelessWidget {
  const _ResourceSection({
    required this.title,
    required this.value,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.icon,
    required this.onRetry,
    this.trailingBuilder,
  });

  final String title;
  final AsyncValue<List<PlatformResource>> value;
  final String emptyTitle;
  final String emptyMessage;
  final IconData icon;
  final VoidCallback onRetry;
  final Widget Function(PlatformResource resource)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        value.when(
          data: (items) => _PaymentResourceList(
            resources: items,
            emptyTitle: emptyTitle,
            emptyMessage: emptyMessage,
            icon: icon,
            trailingBuilder: trailingBuilder,
          ),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: onRetry,
          ),
          loading: () => LoadingState(
              label: context.tr('Loading {p0}', {'p0': title.toLowerCase()})),
        ),
      ],
    );
  }
}

class _PaymentResourceList extends StatelessWidget {
  const _PaymentResourceList({
    required this.resources,
    required this.emptyTitle,
    required this.emptyMessage,
    required this.icon,
    this.trailingBuilder,
  });

  final List<PlatformResource> resources;
  final String emptyTitle;
  final String emptyMessage;
  final IconData icon;
  final Widget Function(PlatformResource resource)? trailingBuilder;

  @override
  Widget build(BuildContext context) {
    if (resources.isEmpty) {
      return EmptyState(
        title: emptyTitle,
        message: emptyMessage,
        icon: Icons.inbox_outlined,
      );
    }

    return Column(
      children: [
        for (final resource in resources)
          Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _showDetails(context, resource),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _resourceDisplayTitle(resource),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (_resourceSubtitle(resource) != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              _resourceSubtitle(resource)!,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ],
                          if (_resourceFacts(resource).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final fact in _resourceFacts(resource))
                                  Chip(
                                    label: Text(fact),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (trailingBuilder != null)
                      trailingBuilder!(resource)
                    else
                      const Icon(Icons.info_outline),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ResourceAction extends ConsumerWidget {
  const _ResourceAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);
    return IconButton(
      tooltip: tooltip,
      onPressed: action.isLoading ? null : onPressed,
      icon: Icon(icon),
    );
  }
}

class _PaymentFormResult {
  const _PaymentFormResult({
    required this.reference,
    required this.money,
  });

  final String reference;
  final Money money;
}

Future<void> _showPaymentForm(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String primaryLabel,
  required IconData icon,
  required String defaultReference,
  required Future<ActionResult> Function(
    dynamic api,
    _PaymentFormResult form,
  ) submit,
  String referenceLabel = 'Reference',
  String amountLabel = 'Amount',
  List<String> currencies = const ['EUR', 'USD'],
}) async {
  final referenceController = TextEditingController(text: defaultReference);
  final amountController = TextEditingController(text: '25.00');
  var currency = currencies.first;

  final result = await showModalBottomSheet<_PaymentFormResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setSheetState) {
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          final isExample = context.isExampleTheme;
          // Example keeps the sheet's action clear of the home indicator; every
          // other tenant keeps the padding it had.
          final safeBottom =
              isExample ? MediaQuery.viewPaddingOf(context).bottom : 0.0;
          void submitForm() {
            final reference = referenceController.text.trim();
            final amount = double.tryParse(
              amountController.text.trim().replaceAll(',', '.'),
            );
            if (reference.isEmpty || amount == null || amount <= 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    context.tr(
                        'Enter a reference and an amount greater than zero.'),
                  ),
                ),
              );
              return;
            }
            Navigator.of(context).pop(
              _PaymentFormResult(
                reference: reference,
                money: Money(
                  currency: currency,
                  minorUnits: (amount * 100).round(),
                ),
              ),
            );
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              bottomInset + 16 + safeBottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isExample)
                      ExampleIconTile(icon: icon, color: ExampleColors.iris)
                    else
                      Icon(icon),
                    SizedBox(width: isExample ? AppSpacing.sm : 8),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: referenceController,
                  decoration: InputDecoration(labelText: referenceLabel),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration:
                      InputDecoration(labelText: context.tr('Currency')),
                  items: [
                    for (final item in currencies)
                      DropdownMenuItem(value: item, child: Text(item)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setSheetState(() => currency = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(labelText: amountLabel),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  // This sheet genuinely has one decisive action, so it takes
                  // the glass material instead of a flat slab. `surface` is
                  // the right ground: a modal sheet paints its own opaque
                  // floor, and there is nothing behind it worth blurring.
                  // Validation, wording and the popped result are untouched —
                  // only the material the press lands on changed.
                  child: isExample
                      ? ExampleGlassButton(
                          label: primaryLabel,
                          icon: icon,
                          onPressed: submitForm,
                        )
                      : FilledButton(
                          onPressed: submitForm,
                          child: Text(primaryLabel),
                        ),
                ),
              ],
            ),
          );
        },
      );
    },
  );

  referenceController.dispose();
  amountController.dispose();

  if (result == null) {
    return;
  }

  await ref
      .read(platformActionControllerProvider.notifier)
      .run((api) => submit(api, result));
}

Future<void> _confirmResourceAction(
  BuildContext context,
  WidgetRef ref, {
  required String title,
  required String message,
  required Future<ActionResult> Function(dynamic api) action,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('Confirm')),
        ),
      ],
    ),
  );

  if (confirmed != true) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(action);
}

void _showDetails(BuildContext context, PlatformResource resource) {
  final example = context.isExampleTheme;
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: example,
    builder: (context) {
      if (example) return _ExamplePaymentDetails(resource: resource);
      final facts = _resourceFacts(resource);
      return ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Text(
            _resourceDisplayTitle(resource),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (_resourceSubtitle(resource) != null) ...[
            const SizedBox(height: 4),
            Text(_resourceSubtitle(resource)!),
          ],
          if (facts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final fact in facts) Chip(label: Text(fact)),
              ],
            ),
          ],
          const SizedBox(height: 16),
          for (final entry in resource.metadata.entries)
            if (entry.value != null && entry.value.toString().trim().isNotEmpty)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(friendlyStatus(entry.key)),
                subtitle: SelectableText(entry.value.toString()),
              ),
        ],
      );
    },
  );
}

/// The payment as Example reads it.
///
/// The pre-Example sheet printed `resource.metadata.entries` verbatim as
/// selectable body copy — which on this screen means a destination chain
/// address set in the reading typeface, elided at the end by the text engine
/// and with no way to copy it. Every value now goes through
/// [PlatformFactRow], so a machine string gets Geist Mono, gives way in the
/// middle (the tail is what people verify against an explorer) and becomes
/// its own 44 pt copy target with in-place confirmation, while a word stays a
/// row with the value in the tabular column.
///
/// Keep every populated metadata entry available in the scrollable sheet.
class _ExamplePaymentDetails extends StatelessWidget {
  const _ExamplePaymentDetails({required this.resource});

  final PlatformResource resource;

  @override
  Widget build(BuildContext context) {
    final subtitle = _resourceSubtitle(resource);
    final entries = [
      for (final entry in resource.metadata.entries)
        if (entry.value != null && entry.value.toString().trim().isNotEmpty)
          (
            label: friendlyStatus(entry.key),
            value: entry.value.toString().trim()
          ),
    ];
    final machineSubtitle =
        subtitle != null && platformLooksMachineString(subtitle);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _resourceDisplayTitle(resource),
              style: TextStyle(
                fontSize: 19,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: -.2,
                color: ExampleInk.primary(context),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              if (machineSubtitle)
                ExampleMono(
                  subtitle,
                  truncate: ExampleMonoTruncate.middle,
                  head: 10,
                  tail: 8,
                  size: 13.5,
                  copyable: true,
                  color: ExampleInk.secondary(context),
                )
              else
                SelectableText(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: ExampleInk.secondary(context),
                  ),
                ),
            ],
            if (entries.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              SelectionArea(
                child: ExampleListGroup(
                  children: [
                    for (final entry in entries)
                      PlatformFactRow(label: entry.label, value: entry.value),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _resourceDisplayTitle(PlatformResource resource) {
  final amount = _firstValue(resource.metadata, const [
    'amount',
    'Amount',
    'maxAmount',
    'MaxAmount',
    'value',
    'Value',
  ]);
  final currency = _firstValue(resource.metadata, const [
    'currency',
    'Currency',
    'asset',
    'Asset',
    'assetCode',
    'AssetCode',
  ]);
  if (amount != null && currency != null) {
    return '$currency $amount';
  }

  final title = resource.title.trim();
  if (title.isNotEmpty) {
    return friendlyStatus(title);
  }

  return 'Item';
}

String? _resourceSubtitle(PlatformResource resource) {
  final metadata = resource.metadata;
  final value = _firstValue(metadata, const [
        'description',
        'Description',
        'reference',
        'Reference',
        'merchantReferenceId',
        'MerchantReferenceId',
        'externalReferenceId',
        'ExternalReferenceId',
        'destinationAddress',
        'DestinationAddress',
        'status',
        'Status',
      ]) ??
      resource.subtitle;

  final text = value.trim();
  return text.isEmpty ? null : friendlyStatus(text);
}

List<String> _resourceFacts(PlatformResource resource) {
  final metadata = resource.metadata;
  final facts = [
    _fact('Status', metadata, const ['status', 'Status', 'state', 'State']),
    _fact('Currency', metadata, const [
      'currency',
      'Currency',
      'asset',
      'Asset',
      'assetCode',
      'AssetCode',
    ]),
    _fact('Created', metadata, const [
      'createdAt',
      'CreatedAt',
      'createdDate',
      'CreatedDate',
    ]),
    _fact('Expires', metadata, const ['expiresAt', 'ExpiresAt']),
  ].whereType<String>().toList();

  final seen = <String>{};
  return [
    for (final fact in facts)
      if (seen.add(fact.toLowerCase())) fact,
  ].take(4).toList();
}

String? _fact(
  String label,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  final value = _firstValue(metadata, keys);
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  return '$label ${friendlyStatus(value)}';
}

String? _firstValue(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key]?.toString().trim();
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}
