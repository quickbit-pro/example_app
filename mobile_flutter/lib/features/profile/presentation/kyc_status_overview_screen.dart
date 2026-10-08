import 'dart:async';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import 'security_sheets.dart';
import '../../kyc/presentation/kyc_resubmission_panel.dart';

class HoppaKycStatusScreen extends ConsumerStatefulWidget {
  const HoppaKycStatusScreen({super.key});

  static const routePath = '/kyc/status';

  @override
  ConsumerState<HoppaKycStatusScreen> createState() =>
      _HoppaKycStatusScreenState();
}

class _HoppaKycStatusScreenState extends ConsumerState<HoppaKycStatusScreen>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(kycDetailedStatusProvider);
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused) {
        ref.invalidate(kycDetailedStatusProvider);
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    ref.invalidate(dashboardProvider);
    ref.invalidate(onboardingProvider);
    final _ = await ref.refresh(kycDetailedStatusProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(kycDetailedStatusProvider);
    final isBusinessAccount = ref.watch(dashboardProvider).maybeWhen(
          data: (dashboard) => dashboard.profile.isBusinessAccount,
          orElse: () => false,
        );
    final equalsMoneyEnabled =
        ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled ??
            true;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('KYC status')),
        actions: [
          IconButton(
            tooltip: context.tr('Refresh status'),
            onPressed: _refreshStatus,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ExampleBackdrop(
        child: status.when(
          data: (value) => RefreshIndicator(
            onRefresh: _refreshStatus,
            child: _KycStatusContent(
              status: value,
              isBusinessAccount: isBusinessAccount,
              equalsMoneyEnabled: equalsMoneyEnabled,
            ),
          ),
          // Verification has a fixed shape, so Example loads into that shape
          // and fails into a designed, announced error. Other brands keep the
          // shared states they render today.
          error: (error, stackTrace) => context.isExampleTheme
              ? Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ExampleErrorState(
                      title: context.tr('Verification status is unavailable'),
                      error: error,
                      onRetry: () => ref.invalidate(kycDetailedStatusProvider),
                    ),
                  ),
                )
              : ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(kycDetailedStatusProvider),
                ),
          loading: () => context.isExampleTheme
              ? const _ExampleKycSkeleton()
              : LoadingState(label: context.tr('Loading KYC status')),
        ),
      ),
    );
  }
}

/// Same content as the KYC status page, presented like the other Settings
/// details: a sheet over the current screen instead of a navigation. It
/// rides the shared Example sheet shell, so it arrives on
/// `ExampleMotion.sheet` with the sheet curve and leaves at 75 percent of it,
/// and it is instant under reduced motion.
Future<void> showKycStatusSheet(BuildContext context, WidgetRef ref) {
  ref.invalidate(kycDetailedStatusProvider);
  return showExampleSheet<void>(
    context,
    scrollable: false,
    maxWidth: 640,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .82,
      child: Consumer(
        builder: (context, ref, _) {
          final status = ref.watch(kycDetailedStatusProvider);
          final isBusinessAccount = ref.watch(dashboardProvider).maybeWhen(
                data: (dashboard) => dashboard.profile.isBusinessAccount,
                orElse: () => false,
              );
          final equalsMoneyEnabled = ref
                  .watch(mobileTenantConfigProvider)
                  .valueOrNull
                  ?.equalsMoneyEnabled ??
              true;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExampleSheetHeader(
                title: context.tr('Identity verification'),
                actions: [
                  IconButton(
                    tooltip: context.tr('Refresh status'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ref.invalidate(dashboardProvider);
                      ref.invalidate(onboardingProvider);
                      ref.invalidate(kycDetailedStatusProvider);
                    },
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 20,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Close'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    icon: Icon(
                      Icons.close_rounded,
                      size: 20,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ExampleStateSwitch(
                  child: status.when(
                    data: (value) => _KycStatusContent(
                      key: const ValueKey('kyc-data'),
                      status: value,
                      isBusinessAccount: isBusinessAccount,
                      equalsMoneyEnabled: equalsMoneyEnabled,
                    ),
                    error: (error, stackTrace) => Center(
                      key: const ValueKey('kyc-error'),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: ExampleErrorState(
                          title:
                              context.tr('Verification status is unavailable'),
                          error: error,
                          onRetry: () =>
                              ref.invalidate(kycDetailedStatusProvider),
                        ),
                      ),
                    ),
                    loading: () => const _ExampleKycSkeleton(
                      key: ValueKey('kyc-loading'),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _KycStatusContent extends StatelessWidget {
  const _KycStatusContent({
    required this.status,
    required this.isBusinessAccount,
    required this.equalsMoneyEnabled,
    super.key,
  });

  final KycDetailedStatus status;
  final bool isBusinessAccount;

  /// False on installations without EqualsMoney: the banking provider check
  /// and bank onboarding actions are hidden entirely.
  final bool equalsMoneyEnabled;

  @override
  Widget build(BuildContext context) {
    final checks = [
      if (!isBusinessAccount)
        _KycCheck(
          title: context.tr('Crypto card KYC'),
          subtitle: context
              .tr('Identity and compliance review for crypto card access.'),
          caption: context.tr('Crypto card access'),
          value: status.hoppaStatus,
          isComplete: status.isHoppaApproved,
          icon: Icons.badge_outlined,
        ),
      if (equalsMoneyEnabled)
        _KycCheck(
          title: context.tr('Banking provider'),
          subtitle: context.tr('Fiat account onboarding and eligibility.'),
          caption: context.tr('Fiat accounts'),
          value: status.bankStatus,
          isComplete: status.canUseEqualsMoneyBanking,
          icon: Icons.account_balance,
        ),
      if (!isBusinessAccount)
        _KycCheck(
          title: context.tr('Card issuer'),
          subtitle: context.tr('Issuer review for virtual and physical cards.'),
          caption: context.tr('Virtual & physical'),
          value: status.cardIssuerStatus,
          isComplete: status.isCardIssuerApproved,
          icon: Icons.credit_card,
        ),
    ];
    final complete = checks.where((check) => check.isComplete).length;

    // Example gets its own tree; every other brand keeps the Material one
    // below, byte for byte.
    if (context.isExampleTheme) {
      return _ExampleKycBody(
        checks: checks,
        complete: complete,
        status: status,
        isBusinessAccount: isBusinessAccount,
        equalsMoneyEnabled: equalsMoneyEnabled,
      );
    }

    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: theme.colorScheme.onPrimary,
                size: 34,
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('Verification progress'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isBusinessAccount
                    ? context.tr(
                        '{p0} of {p1} checks are ready. Complete the compliance review to unlock business accounts, transfers, and exchange.',
                        {
                            'p0': complete,
                            'p1': checks.length
                          })
                    : context.tr(
                        '{p0} of {p1} checks are ready. Keep all checks approved to unlock cards, payouts, and crypto wallet operations.',
                        {'p0': complete, 'p1': checks.length}),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 18),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: complete / checks.length,
                  backgroundColor:
                      theme.colorScheme.onPrimary.withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (final check in checks) _KycCheckTile(check: check),
        const SizedBox(height: 8),
        if (status.hasInterlaceAction)
          KycResubmissionPanel(status: status)
        else
          _NextActionCard(
            status: status,
            isBusinessAccount: isBusinessAccount,
            equalsMoneyEnabled: equalsMoneyEnabled,
          ),
      ],
    );
  }
}

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({
    required this.status,
    required this.isBusinessAccount,
    required this.equalsMoneyEnabled,
  });

  final KycDetailedStatus status;
  final bool isBusinessAccount;
  final bool equalsMoneyEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identityReady = isBusinessAccount || status.isHoppaApproved;
    final bankingReady = !equalsMoneyEnabled || status.canUseEqualsMoneyBanking;
    final allReady = identityReady &&
        bankingReady &&
        (isBusinessAccount || status.isCardIssuerApproved);
    final message = allReady
        ? context.tr('All verification checks are complete.')
        : equalsMoneyEnabled && status.requiresEqualsMoneyAction
            ? context.tr(
                'EqualsMoney needs your input before accounts, budgets, payouts, and cards can be used.')
            : !identityReady
                ? status.nextAction
                : equalsMoneyEnabled
                    ? context.tr(
                        'Continue bank onboarding to activate accounts and payments.')
                    : context.tr(
                        'Card issuer review is in progress. Cards unlock once it is approved.');

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.flag_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    allReady ? context.tr('Ready') : context.tr('Next action'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(message),
            if (!allReady) ...[
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (!identityReady)
                    FilledButton.icon(
                      onPressed: () => context.go('/kyc'),
                      icon: const Icon(Icons.play_arrow),
                      label: Text(context.tr('Continue KYC')),
                    ),
                  if (equalsMoneyEnabled)
                    OutlinedButton.icon(
                      onPressed: () => context.go(
                        isBusinessAccount ? '/business' : '/onboarding/banking',
                      ),
                      icon: Icon(
                        status.requiresEqualsMoneyAction
                            ? Icons.assignment_late_outlined
                            : Icons.account_balance,
                      ),
                      label: Text(
                        status.requiresEqualsMoneyAction
                            ? context.tr('Resolve EqualsMoney')
                            : context.tr('Bank onboarding'),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KycCheckTile extends StatelessWidget {
  const _KycCheckTile({required this.check});

  final _KycCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = check.isComplete;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: complete
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.tertiaryContainer,
          child: Icon(
            complete ? Icons.check : check.icon,
            color: complete
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onTertiaryContainer,
          ),
        ),
        title: Text(check.title),
        subtitle: Text(check.subtitle),
        trailing: Text(
          friendlyStatus(check.value),
          style: theme.textTheme.labelLarge?.copyWith(
            color: complete
                ? theme.colorScheme.primary
                : theme.colorScheme.tertiary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _KycCheck {
  const _KycCheck({
    required this.title,
    required this.subtitle,
    required this.caption,
    required this.value,
    required this.isComplete,
    required this.icon,
  });

  final String title;
  final String subtitle;

  /// The Example caption. [subtitle] is a full sentence written for the
  /// Material tile; on a 375 pt row it shares its line with a status pill,
  /// so this is the same fact in at most 18 characters and never truncates.
  final String caption;
  final String value;
  final bool isComplete;
  final IconData icon;
}

/// Example's verification screen: one progress panel, one list of checks, one
/// next step. Utility register — no arrival moment, nothing animates on
/// mount. The only motion is the pill swapping through [ExampleStateSwitch]
/// when a check clears, and the sheen travelling along the progress bar,
/// which is one of the allowed hosts.
class _ExampleKycBody extends StatelessWidget {
  const _ExampleKycBody({
    required this.checks,
    required this.complete,
    required this.status,
    required this.isBusinessAccount,
    required this.equalsMoneyEnabled,
  });

  final List<_KycCheck> checks;
  final int complete;
  final KycDetailedStatus status;
  final bool isBusinessAccount;
  final bool equalsMoneyEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = checks.length;
    final allReady = total > 0 && complete == total;
    final fraction = total == 0 ? 0.0 : complete / total;

    Widget bar = DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleInk.accent(context, ExampleColors.iris),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: const SizedBox.expand(),
    );
    // A progress bar is on the sheen allow-list. It only registers when the
    // shell's scope is above us; nothing here starts a second ticker, so
    // reduced motion and the hidden-route pause are handled once, upstream.
    if (ExampleSheenScope.maybeOf(context) != null) {
      bar = ExampleSheen(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: bar,
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('Verification'),
                        style: (theme.textTheme.titleMedium ??
                                const TextStyle(fontSize: 16))
                            .copyWith(
                          fontWeight: FontWeight.w700,
                          color: ExampleInk.primary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    ExampleStateSwitch(
                      child: ExamplePill(
                        key: ValueKey(allReady),
                        label: allReady
                            ? context.tr('Verified')
                            : context.tr(
                                '{p0} of {p1}', {'p0': complete, 'p1': total}),
                        color:
                            allReady ? ExampleColors.success : ExampleColors.iris,
                        dot: allReady,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Semantics(
                  label: context.tr('Verification progress'),
                  value: '$complete of $total checks approved',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    child: SizedBox(
                      height: 6,
                      child: ColoredBox(
                        color: ExampleInk.tint(
                          context,
                          ExampleColors.iris,
                          alpha: .18,
                        ),
                        child: FractionallySizedBox(
                          alignment: AlignmentDirectional.centerStart,
                          widthFactor: fraction.clamp(0.0, 1.0),
                          child: bar,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  isBusinessAccount
                      ? context.tr(
                          'Complete the compliance review to unlock business accounts, transfers and exchange.')
                      : context.tr(
                          'Keep every check approved to unlock cards, payouts and crypto wallet operations.'),
                  style: (theme.textTheme.bodySmall ??
                          const TextStyle(fontSize: 12))
                      .copyWith(
                    color: ExampleInk.secondary(context),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ExampleListGroup(
          title: context.tr('Checks'),
          children: [
            for (final check in checks) _ExampleKycCheckRow(check: check),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (status.hasInterlaceAction)
          KycResubmissionPanel(status: status)
        else
          _ExampleNextAction(
            status: status,
            isBusinessAccount: isBusinessAccount,
            equalsMoneyEnabled: equalsMoneyEnabled,
          ),
      ],
    );
  }
}

/// One verification check.
///
/// [ExampleRow] puts its trailing slot on the same line as the title, and a
/// status pill plus a 16-character title do not both fit in 375 pt at text
/// scale 1.3. So this mirrors the row's geometry exactly — 56 pt floor,
/// `ExampleRow.defaultPadding`, the 40 pt leading square, the 12 pt gap — and
/// moves the pill onto the caption line, where it has room to say
/// "Action needed" without shortening the check's name.
class _ExampleKycCheckRow extends StatelessWidget {
  const _ExampleKycCheckRow({required this.check});

  final _KycCheck check;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = check.isComplete;
    final label = _kycPillLabel(check);
    final tone = complete
        ? ExampleColors.success
        : label == 'Action needed' || label == 'Declined'
            ? ExampleColors.warning
            : ExampleColors.iris;

    return Semantics(
      container: true,
      label: '${check.title}, $label, ${check.caption}',
      child: ExcludeSemantics(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: ExampleRow.defaultPadding,
            child: Row(
              children: [
                SizedBox.square(
                  dimension: ExampleRow.leadingSize,
                  child: Center(
                    child: ExampleIconTile(
                      icon: complete ? Icons.check_rounded : check.icon,
                      color: tone,
                    ),
                  ),
                ),
                const SizedBox(width: ExampleRow.leadingGap),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        check.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (theme.textTheme.titleSmall ??
                                const TextStyle(fontSize: 14))
                            .copyWith(
                          fontWeight: FontWeight.w600,
                          color: ExampleInk.primary(context),
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          ExampleStateSwitch(
                            child: ExamplePill(
                              key: ValueKey(label),
                              label: label,
                              color: tone,
                              dot: complete,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Expanded(
                            child: Text(
                              check.caption,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: (theme.textTheme.bodySmall ??
                                      const TextStyle(fontSize: 12))
                                  .copyWith(
                                color: ExampleInk.secondary(context),
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The pill never echoes raw provider text: a backend string of unknown
/// length would blow the caption line open. It is derived from the check's
/// own completeness plus a few keywords, so the vocabulary is fixed at four
/// labels and the widest, "Action needed", is measured to fit at 375 pt and
/// text scale 1.3.
String _kycPillLabel(_KycCheck check) {
  if (check.isComplete) return 'Approved';
  final value = check.value.trim().toLowerCase();
  if (value.isEmpty || value.contains('not ') || value.contains('none')) {
    return 'Not started';
  }
  if (value.contains('reject') ||
      value.contains('declin') ||
      value.contains('fail')) {
    return 'Declined';
  }
  if (value.contains('action') ||
      value.contains('require') ||
      value.contains('resubmit') ||
      value.contains('document')) {
    return 'Action needed';
  }
  return 'In review';
}

/// The single next step, as a panel rather than a card inside the list: one
/// primary action stacked over one secondary, never side by side, so 375 pt
/// at text scale 1.3 never has to wrap a button label.
class _ExampleNextAction extends StatelessWidget {
  const _ExampleNextAction({
    required this.status,
    required this.isBusinessAccount,
    required this.equalsMoneyEnabled,
  });

  final KycDetailedStatus status;
  final bool isBusinessAccount;
  final bool equalsMoneyEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identityReady = isBusinessAccount || status.isHoppaApproved;
    final bankingReady = !equalsMoneyEnabled || status.canUseEqualsMoneyBanking;
    final allReady = identityReady &&
        bankingReady &&
        (isBusinessAccount || status.isCardIssuerApproved);
    final message = allReady
        ? context.tr('All verification checks are complete.')
        : equalsMoneyEnabled && status.requiresEqualsMoneyAction
            ? context.tr(
                'EqualsMoney needs your input before accounts, budgets, payouts and cards can be used.')
            : !identityReady
                ? status.nextAction
                : equalsMoneyEnabled
                    ? context.tr(
                        'Continue bank onboarding to activate accounts and payments.')
                    : context.tr(
                        'Card issuer review is in progress. Cards unlock once it is approved.');

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ExampleIconTile(
                  icon: allReady ? Icons.task_alt_rounded : Icons.flag_outlined,
                  color: allReady ? ExampleColors.success : ExampleColors.iris,
                ),
                const SizedBox(width: ExampleRow.leadingGap),
                Expanded(
                  child: Text(
                    allReady ? context.tr('Ready') : context.tr('Next step'),
                    style: (theme.textTheme.titleSmall ??
                            const TextStyle(fontSize: 14))
                        .copyWith(
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style:
                  (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
                      .copyWith(
                color: ExampleInk.secondary(context),
                height: 1.45,
              ),
            ),
            if (!allReady) ...[
              if (!identityReady) ...[
                const SizedBox(height: AppSpacing.md),
                _ExampleKycAction(
                  label: context.tr('Continue verification'),
                  primary: true,
                  onPressed: () => context.go('/kyc'),
                ),
              ],
              if (equalsMoneyEnabled) ...[
                const SizedBox(height: AppSpacing.xs),
                _ExampleKycAction(
                  label: status.requiresEqualsMoneyAction
                      ? context.tr('Resolve EqualsMoney')
                      : context.tr('Bank onboarding'),
                  primary: identityReady,
                  onPressed: () => context.go(
                    isBusinessAccount ? '/business' : '/onboarding/banking',
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// One 52 pt action on the product's CTA material.
///
/// Verification is the one thing on this screen the customer can actually do
/// next, so it gets the real button rather than a hand-rolled slab: primary
/// is [ExampleGlassButtonTone.primary], the stacked second action is
/// [ExampleGlassButtonTone.neutral], and both keep the same 52 pt footprint so
/// they never disagree about height. `ExampleGlassGround.surface` because the
/// panel under them is painted, not atmosphere — the material goes opaque and
/// keeps its silhouette instead of dissolving into the card.
class _ExampleKycAction extends StatelessWidget {
  const _ExampleKycAction({
    required this.label,
    required this.primary,
    required this.onPressed,
  });

  final String label;
  final bool primary;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ExampleGlassButton(
        label: label,
        tone: primary
            ? ExampleGlassButtonTone.primary
            : ExampleGlassButtonTone.neutral,
        height: 52,
        onPressed: onPressed,
      );
}

/// Verification while the status is still in flight.
///
/// The same argument as the Settings skeleton: this page has one shape, so it
/// loads into that shape — the progress panel at its real height, the checks
/// on the same 56 pt rhythm as the rows that replace them, the next-step card
/// under them. Nothing moves position when the status lands.
///
/// One sheen host for the whole page, never one per block: the law's ceiling
/// is two or three, and a column of shimmering panels is the loading cliché
/// this system is built against. With no scope above, or under reduced
/// motion, the band is a static highlight and no ticker starts.
class _ExampleKycSkeleton extends StatelessWidget {
  const _ExampleKycSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget panel(Widget child) => DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: child,
        );

    return Semantics(
      label: context.tr('Loading verification status'),
      child: ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              panel(
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ExampleSkeleton.line(
                              widthFactor: .42,
                              height: 15,
                              sheen: false,
                            ),
                          ),
                          SizedBox(width: AppSpacing.sm),
                          ExampleSkeleton(
                            width: 62,
                            height: 20,
                            radius: AppRadii.pill,
                            sheen: false,
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.md),
                      ExampleSkeleton(
                        height: 6,
                        radius: AppRadii.pill,
                        sheen: false,
                      ),
                      SizedBox(height: AppSpacing.md),
                      ExampleSkeleton.line(height: 10, sheen: false),
                      SizedBox(height: AppSpacing.xs),
                      ExampleSkeleton.line(
                        widthFactor: .74,
                        height: 10,
                        sheen: false,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ExampleListGroup(
                children: [
                  for (var i = 0; i < 3; i++)
                    const ExampleSkeleton.row(
                      height: 56,
                      avatarSize: 34,
                      trailing: false,
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              panel(
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          ExampleSkeleton(
                            width: 34,
                            height: 34,
                            radius: 10,
                            sheen: false,
                          ),
                          SizedBox(width: ExampleRow.leadingGap),
                          Expanded(
                            child: ExampleSkeleton.line(
                              widthFactor: .34,
                              height: 13,
                              sheen: false,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppSpacing.sm),
                      ExampleSkeleton.line(height: 10, sheen: false),
                      SizedBox(height: AppSpacing.xs),
                      ExampleSkeleton.line(
                        widthFactor: .58,
                        height: 10,
                        sheen: false,
                      ),
                      SizedBox(height: AppSpacing.md),
                      ExampleSkeleton(
                        height: 52,
                        radius: AppRadii.pill,
                        sheen: false,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
