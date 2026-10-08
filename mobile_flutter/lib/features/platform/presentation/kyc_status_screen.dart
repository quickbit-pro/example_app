import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';
import '../../kyc/presentation/kyc_resubmission_panel.dart';

/// KYC status: three checks and the one thing to do next.
///
/// A utility screen — no arrival moment. The three states move through
/// `ExampleStateSwitch` at `ExampleMotion.state`, and the only semantic colour
/// on the page sits inside the status pills.
class KycStatusScreen extends ConsumerWidget {
  const KycStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('KYC status'))),
        body: context.isExampleTheme ? const _ExampleBody() : const _LegacyBody(),
      ),
    );
  }
}

class _ExampleBody extends ConsumerWidget {
  const _ExampleBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(kycDetailedStatusProvider);

    return ListView(
      padding: platformExamplePadding,
      children: [
        PlatformLede(
          text: context
              .tr('Where each verification stands, and what unlocks next.'),
          trailing: status.valueOrNull == null
              ? null
              : _overallPill(context, status.requireValue),
        ),
        platformSectionGap,
        ExampleStateSwitch(
          alignment: Alignment.topCenter,
          child: status.when(
            data: (value) => _Verification(
              key: const ValueKey('kyc-data'),
              status: value,
            ),
            error: (error, stackTrace) => PlatformErrorState(
              key: const ValueKey('kyc-error'),
              error: error,
              onRetry: () => ref.invalidate(kycDetailedStatusProvider),
            ),
            loading: () => PlatformLoadingGroup(
              key: const ValueKey('kyc-loading'),
              title: context.tr('Verification'),
              label: context.tr('Loading KYC status'),
            ),
          ),
        ),
      ],
    );
  }
}

/// The three checks, then the next action as a panel that wraps instead of a
/// row that truncates.
class _Verification extends StatelessWidget {
  const _Verification({required this.status, super.key});

  final KycDetailedStatus status;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleListGroup(
          title: context.tr('Verification'),
          children: [
            _StatusRow(
              icon: Icons.badge_outlined,
              label: context.tr('Identity'),
              status: status.hoppaStatus,
            ),
            _StatusRow(
              icon: Icons.account_balance_outlined,
              label: context.tr('Bank'),
              status: status.bankStatus,
            ),
            _StatusRow(
              icon: Icons.credit_card_outlined,
              label: context.tr('Card issuer'),
              status: status.cardIssuerStatus,
            ),
          ],
        ),
        platformSectionGap,
        ExampleSectionTitle(title: context.tr('Next action')),
        const SizedBox(height: AppSpacing.sm),
        if (status.hasInterlaceAction)
          KycResubmissionPanel(status: status)
        else
          _NextActionPanel(text: status.nextAction),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.label,
    required this.status,
  });

  final IconData icon;
  final String label;
  final String status;

  @override
  Widget build(BuildContext context) => ExampleRow(
        leading: ExampleIconTile(icon: icon, color: ExampleColors.iris),
        title: label,
        semanticsLabel: '$label ${friendlyStatus(status)}',
        trailing: PlatformStatusPill(status: status),
      );
}

class _NextActionPanel extends StatelessWidget {
  const _NextActionPanel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExampleIconTile(
              icon: Icons.flag_outlined,
              color: ExampleColors.iris,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  fallbackText(text, 'Nothing to do right now.'),
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.45,
                    color: ExampleInk.secondary(context),
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

Widget _overallPill(BuildContext context, KycDetailedStatus status) {
  final tones = [
    platformStatusColor(status.hoppaStatus),
    platformStatusColor(status.bankStatus),
    platformStatusColor(status.cardIssuerStatus),
  ];
  if (tones.contains(ExampleColors.danger)) {
    return ExamplePill(
      label: context.tr('Needs attention'),
      color: ExampleColors.danger,
      dot: true,
    );
  }
  if (tones.every((tone) => tone == ExampleColors.success)) {
    return ExamplePill(
      label: context.tr('Verified'),
      color: ExampleColors.success,
      dot: true,
    );
  }
  if (tones.contains(ExampleColors.warning)) {
    return ExamplePill(
      label: context.tr('In review'),
      color: ExampleColors.warning,
      dot: true,
    );
  }
  return ExamplePill(
    label: context.tr('Not started'),
    color: ExampleColors.iris,
    dot: true,
  );
}

/// The pre-Example screen, kept byte-identical for every white-label tenant.
class _LegacyBody extends ConsumerWidget {
  const _LegacyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(kycDetailedStatusProvider);

    return status.when(
      data: (value) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusTile(label: context.tr('Identity'), value: value.hoppaStatus),
          _StatusTile(label: context.tr('Bank'), value: value.bankStatus),
          _StatusTile(
              label: context.tr('Card issuer'), value: value.cardIssuerStatus),
          const SizedBox(height: 8),
          if (value.hasInterlaceAction)
            KycResubmissionPanel(status: value)
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.flag_outlined),
                title: Text(context.tr('Next action')),
                subtitle: Text(value.nextAction),
              ),
            ),
        ],
      ),
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(kycDetailedStatusProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading KYC status')),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_outlined),
        title: Text(label),
        trailing: Text(friendlyStatus(value)),
      ),
    );
  }
}
