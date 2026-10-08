import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../app/routes.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../wallets/presentation/crypto_wallet_actions.dart';
import '../../banking/data/mobile_banking_api.dart';
import '../domain/dashboard_models.dart';

/// Both surfaces use the same remaining steps. A spent balance never resets
/// deposit progress, and an approved account can discover this after time away.
List<ActivationStep> activationSteps(
  HoppaDashboardSnapshot snapshot,
  bool funded,
) {
  if (snapshot.requiresKyc ||
      !snapshot.accountReady ||
      snapshot.isBusinessAccount) {
    return const [];
  }
  final cards =
      snapshot.cards.where((c) => c.status != CardStatus.cancelled).toList();
  if (cards.any(
    (c) => c.status == CardStatus.active || c.status == CardStatus.frozen,
  )) {
    return const [];
  }
  return [
    if (!funded)
      const ActivationStep(
        'Make your first deposit',
        Icons.add_circle_outline,
        'deposit',
      ),
    if (cards.isEmpty)
      const ActivationStep('Order your card', Icons.credit_card, 'order'),
    if (cards.isNotEmpty)
      ActivationStep(
        cards.first.virtual
            ? 'Your card is being prepared'
            : 'Activate after your card arrives',
        Icons.credit_card,
        'card',
        cardId: cards.first.id,
      ),
  ];
}

class ActivationStep {
  const ActivationStep(this.title, this.icon, this.action, {this.cardId});
  final String title;
  final IconData icon;
  final String action;
  final String? cardId;
}

class ExampleActivationPanel extends ConsumerStatefulWidget {
  const ExampleActivationPanel(
      {required this.snapshot, this.setupComplete = true, super.key});
  final HoppaDashboardSnapshot snapshot;
  final bool setupComplete;
  @override
  ConsumerState<ExampleActivationPanel> createState() =>
      _ExampleActivationPanelState();
}

class _ExampleActivationPanelState extends ConsumerState<ExampleActivationPanel> {
  bool? _funded;
  bool _busy = false;
  bool _recordedDeposit = false;
  bool get _observedDeposit => widget.snapshot.activities.any(
        (a) =>
            a.kind == HoppaActivityKind.deposit &&
            a.amount > 0 &&
            a.isCompleted &&
            !a.isInternalMovement,
      );
  bool get _eligible =>
      widget.setupComplete &&
      widget.snapshot.accountId.isNotEmpty &&
      !widget.snapshot.requiresKyc &&
      widget.snapshot.accountReady &&
      !widget.snapshot.isBusinessAccount;
  @override
  void initState() {
    super.initState();
    unawaited(_sync());
  }

  @override
  void didUpdateWidget(covariant ExampleActivationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_funded == null || (_observedDeposit && !_recordedDeposit)) {
      unawaited(_sync());
    }
  }

  Future<void> _sync() async {
    if (!_eligible || _busy || activationSteps(widget.snapshot, false).isEmpty) {
      return;
    }
    _busy = true;
    var observed = _observedDeposit;
    try {
      final dio = ref.read(dioProvider);
      final progress = await dio.post<Map<String, dynamic>>(
        '/api/v1/mobile/activation',
        data: {'hasCompletedDeposit': observed, 'claimIntroduction': false},
      );
      if (!mounted) return;
      observed = observed || progress.data?['hasCompletedDeposit'] == true;
      if (!observed) {
        observed = await MobileBankingApi(dio).hasCompletedDeposit();
      }
      if (!mounted || !_eligible) return;
      final response = await dio.post<Map<String, dynamic>>(
        '/api/v1/mobile/activation',
        data: {
          'hasCompletedDeposit': observed,
          'claimIntroduction':
              activationSteps(widget.snapshot, observed).isNotEmpty,
        },
      );
      if (!mounted) return;
      final data = response.data ?? const {};
      setState(() {
        _funded = data['hasCompletedDeposit'] == true;
        _recordedDeposit = observed;
      });
      if (data['showIntroduction'] == true && _eligible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _eligible && ModalRoute.of(context)?.isCurrent == true) {
            unawaited(_introduce());
          }
        });
      }
    } catch (_) {
      // A failed progress read must not repeat a modal or mislabel an existing
      // customer as unfunded. Dashboard refresh retries this nonessential panel.
    } finally {
      _busy = false;
    }
  }

  Future<void> _open(ActivationStep step) async {
    switch (step.action) {
      case 'deposit':
        await openCryptoDeposit(context, ref);
      case 'order':
        context.go(AppRoutes.orderCard);
      case 'card':
        context.go(AppRoutes.cardDetail(step.cardId!));
    }
  }

  Future<void> _introduce() async {
    final steps = activationSteps(widget.snapshot, _funded ?? true);
    if (steps.isEmpty) return;
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Your account is approved')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('You’re ready for your next step.')),
              const SizedBox(height: 16),
              for (final step in steps)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(dialogContext, step.action),
                    icon: Icon(step.icon),
                    label: Text(context.tr(step.title)),
                  ),
                ),
              if (widget.snapshot.referralsEnabled) ...[
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'invite'),
                  child: Text(context.tr('Invite friends')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, 'affiliate'),
                  child: Text(context.tr('Explore the affiliate program')),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(context.tr('Maybe later')),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'invite' || action == 'affiliate') {
      context.go(AppRoutes.rewardsTab(action == 'invite' ? 'share' : 'offer'));
    } else {
      final current = activationSteps(widget.snapshot, _funded ?? true);
      final step = current.where((s) => s.action == action).firstOrNull;
      if (step != null) await _open(step);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = _funded == null
        ? <ActivationStep>[]
        : activationSteps(widget.snapshot, _funded!);
    if (steps.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Finish setting up'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              for (final step in steps)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(step.icon),
                  title: Text(context.tr(step.title)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _open(step),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class ExampleReferralTeaser extends StatelessWidget {
  const ExampleReferralTeaser({required this.enabled, super.key});
  final bool enabled;
  @override
  Widget build(BuildContext context) => !enabled
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Expanded(
                    child: Text(context.tr('Invite a friend & earn'),
                        style: Theme.of(context).textTheme.titleSmall)),
                const SizedBox(width: 8),
                TextButton(
                    onPressed: () => context.go(AppRoutes.rewardsTab('share')),
                    child: Text(context.tr('Invite now'))),
              ]),
            ),
          ),
        );
}
