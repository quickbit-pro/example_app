import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../application/business_providers.dart';

class BusinessGate extends ConsumerStatefulWidget {
  const BusinessGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends ConsumerState<BusinessGate>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _refresh();
  }

  void _refresh() => ref.invalidate(businessWorkflowProvider);

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(String paymentId) async {
    final api = ref.read(mobileBankingApiProvider);
    var result =
        await api.startBusinessCheckout(paymentId, termsAccepted: false);
    if (!mounted) return;
    if (result['error'] == 'PAYMENT_TERMS_REQUIRED') {
      final terms = result['terms'];
      if (terms is! Map<String, dynamic>) {
        throw StateError('Payment terms are unavailable.');
      }
      final accepted = await showDialog<bool>(
        context: context,
        builder: (_) => _PaymentTerms(terms: terms),
      );
      if (accepted != true || !mounted) return;
      result = await api.startBusinessCheckout(paymentId, termsAccepted: true);
    }
    if (const {'PAID', 'WAIVED'}.contains(result['status']) || !mounted) return;
    final url = Uri.tryParse(result['url']?.toString() ?? '');
    if (url == null ||
        url.scheme != 'https' ||
        url.host != 'checkout.stripe.com' ||
        url.userInfo.isNotEmpty ||
        url.port != 443) {
      throw StateError('A secure Stripe payment link is unavailable.');
    }
    final opened = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
      webOnlyWindowName: '_self',
    );
    if (!opened) throw StateError('Could not open Stripe.');
  }

  @override
  Widget build(BuildContext context) {
    return ref.watch(businessWorkflowProvider).when(
          loading: () =>
              _page(const Center(child: CircularProgressIndicator())),
          error: (error, _) => _page(Text(friendlyErrorMessage(error))),
          data: (workflow) {
            final state = workflow['state'];
            if (const {'DRAFT', 'INFORMATION_REQUIRED', 'SUBMITTED'}
                .contains(state)) {
              return widget.child;
            }
            if (state == 'SELECT_TIER') return _page(_plans(workflow));
            final purpose = switch (state) {
              'PAYMENT_REQUIRED' => 'INITIAL',
              'DIFFERENCE_REQUIRED' => 'DIFFERENCE',
              _ => null,
            };
            final message = _statusMessages[state] ??
                'Business onboarding status is unavailable.';
            return _page(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.tr(message),
                    style: Theme.of(context).textTheme.titleLarge),
                if (purpose != null) ...[
                  for (final payment in _records(workflow['payments'])
                      .where((payment) => payment['purpose'] == purpose))
                    _payment(payment),
                  Text(context.tr(
                      'After paying in your browser, return here and refresh your status.')),
                ],
              ],
            ));
          },
        );
  }

  Widget _page(Widget content) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Business onboarding'))),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    content,
                    if (_error != null)
                      Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    if (_busy) const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: _busy ? null : _refresh,
                      child: Text(context.tr('Refresh status')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

  Widget _plans(Map<String, dynamic> workflow) {
    final tiers =
        _records(workflow['tiers']).where((tier) => tier['id'] is int).toList();
    final gates = _records(workflow['gates']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('Select your business plan'),
            style: Theme.of(context).textTheme.titleLarge),
        if (tiers.isEmpty)
          Text(context.tr('No business plans are available. Contact support.')),
        for (final tier in tiers)
          Builder(builder: (context) {
            final id = tier['id'] as int;
            final fee = gates
                .where(
                    (gate) => gate['tier_id'] == id && gate['enabled'] == true)
                .firstOrNull;
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tier['name'].toString(),
                        style: Theme.of(context).textTheme.titleMedium),
                    if (tier['description'] is String)
                      Text(tier['description'] as String),
                    if (fee != null)
                      Text(context.tr('Opening fee: {p0} {p1}', {
                        'p0': fee['amount'],
                        'p1': fee['currency'],
                      })),
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() => ref
                              .read(mobileBankingApiProvider)
                              .selectBusinessTier(id)),
                      child:
                          Text(context.tr('Select {p0}', {'p0': tier['name']})),
                    ),
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _payment(Map<String, dynamic> payment) {
    final id = payment['id']?.toString() ?? '';
    final status = payment['status'];
    final paidByBank = payment['bank_amount'];
    final partialBankTransfer = paidByBank is num && paidByBank > 0;
    Map<String, dynamic>? invoice;
    if (payment['invoice_details_json'] case final String rawInvoice) {
      try {
        final details = jsonDecode(rawInvoice);
        if (details is Map<String, dynamic>) invoice = details;
      } on FormatException {
        // Checkout does not depend on the optional invoice preview.
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${payment['amount']} ${payment['currency']} · $status'),
            if (invoice != null && invoice['bankInstructions'] is String)
              SelectableText([
                if (payment['invoice_number'] != null)
                  context.tr('Invoice {p0}', {'p0': payment['invoice_number']}),
                invoice['bankInstructions'] as String,
              ].join('\n')),
            if (partialBankTransfer)
              Text(context.tr(
                  'A partial bank transfer was recorded. Contact support to confirm the remaining balance.')),
            if (id.isNotEmpty &&
                !partialBankTransfer &&
                !const {'PAID', 'WAIVED', 'REFUNDED', 'DISPUTED'}
                    .contains(status))
              FilledButton(
                onPressed: _busy ? null : () => _run(() => _pay(id)),
                child: Text(context.tr('Pay securely with Stripe')),
              ),
          ],
        ),
      ),
    );
  }
}

Iterable<Map<String, dynamic>> _records(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>() : const [];

class _PaymentTerms extends StatefulWidget {
  const _PaymentTerms({required this.terms});

  final Map<String, dynamic> terms;

  @override
  State<_PaymentTerms> createState() => _PaymentTermsState();
}

class _PaymentTermsState extends State<_PaymentTerms> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.terms['title']?.toString() ?? 'Payment terms'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.terms['intro'] case final String intro) Text(intro),
              if (widget.terms['secondaryIntro'] case final String intro)
                Text(intro),
              if (widget.terms['items'] case final List items)
                for (final item in items) Text('• $item'),
              CheckboxListTile(
                value: _accepted,
                onChanged: (value) => setState(() => _accepted = value == true),
                title: Text(widget.terms['checkboxLabel']?.toString() ??
                    'I accept these payment terms'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: _accepted ? () => Navigator.pop(context, true) : null,
            child: Text(context.tr('Continue to Stripe')),
          ),
        ],
      );
}

const _statusMessages = {
  'PAYMENT_REQUIRED': 'Complete the opening payment to continue.',
  'ASSESSMENT_PENDING': 'Your risk assessment is pending.',
  'MANUAL_REVIEW': 'Your business application is under review.',
  'DIFFERENCE_REQUIRED': 'The remaining opening fee is due.',
  'READY': 'Your application is ready to send to Equals Money.',
  'SUBMITTING': 'Your application is being sent to Equals Money.',
  'SUBMISSION_UNCERTAIN': 'We are confirming submission with Equals Money.',
  'PAYMENT_REVIEW': 'Your payment is under review.',
  'REJECTED': 'Your business application was declined.',
  'BLOCKED': 'Your business application is on hold. Contact support.',
};
