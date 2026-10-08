import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import '../../../core/models/upload_document.dart';
import '../../../shared/widgets/safeguarding_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/routes.dart';
import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/equals_money.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/widgets/additional_information_dialog.dart';
import '../../../shared/widgets/searchable_multi_select_dropdown.dart';
import '../../banking/application/banking_providers.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';
import 'tiers_screen.dart' show tierIdOf;
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader, ExampleSheetNote, ExampleSheetCta;
import '../../../shared/widgets/app_progress_indicator.dart';

/// Providers and budgets: the EqualsMoney onboarding flow.
///
/// The flow is unchanged — same guards, same actions, same dialogs. What is
/// new is the frame: a setup panel whose step bar is the screen's one moment
/// (a single sheen pass along the 2 pt hairline once the route settles), the
/// actions as rows in a `ExampleListGroup`, and the single next step lifted out
/// of the list into a frosted bar pinned above the safe area, so the thing to
/// do next is always on screen.
class OnboardingBankingScreen extends ConsumerWidget {
  const OnboardingBankingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenantConfig = ref.watch(mobileTenantConfigProvider);
    if (tenantConfig.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Providers and budgets'))),
        body: LoadingState(label: context.tr('Loading banking configuration')),
      );
    }
    final config = tenantConfig.valueOrNull;
    if (config == null || !config.equalsMoneyEnabled) {
      return Scaffold(
        appBar: AppBar(title: Text(context.tr('Providers and budgets'))),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: EmptyState(
            title: context.tr('Banking provider unavailable'),
            message: context.tr(
                'EqualsMoney onboarding is not enabled for this white-label installation.'),
            icon: Icons.account_balance_outlined,
          ),
        ),
      );
    }

    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Providers and budgets'))),
        body: context.isExampleTheme ? const _ExampleBody() : const _LegacyBody(),
      ),
    );
  }
}

class _ExampleBody extends ConsumerWidget {
  const _ExampleBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kycStatus = ref.watch(kycDetailedStatusProvider);
    final dashboard = ref.watch(dashboardProvider);
    final isBusinessAccount =
        dashboard.valueOrNull?.profile.isBusinessAccount ?? false;
    final status = kycStatus.valueOrNull;
    final onboarded = status?.canUseEqualsMoneyBanking ?? false;
    final needsInput = status?.requiresEqualsMoneyAction ?? false;
    final inReview = status?.hasEqualsMoneyReviewState ?? false;
    final accountId = status?.equalsMoneyAccountId;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: platformExamplePadding,
            children: [
              _SetupPanel(status: kycStatus),
              platformSectionGap,
              if (needsInput && status != null) ...[
                ExampleSectionTitle(title: context.tr('Required now')),
                const SizedBox(height: AppSpacing.sm),
                _RequiredActionPanel(status: status),
                platformSectionGap,
              ],
              ExampleListGroup(
                title: needsInput
                    ? context.tr('Also here')
                    : context.tr('Next actions'),
                children: [
                  ExampleRow(
                    leading: ExampleIconTile(
                      icon: _providerIcon(
                        onboarded: onboarded,
                        needsInput: needsInput,
                        inReview: inReview,
                      ),
                      color: ExampleColors.iris,
                    ),
                    title: context.tr('EqualsMoney'),
                    subtitle: !isBusinessAccount &&
                            status?.isHoppaApproved != true &&
                            !onboarded &&
                            !needsInput &&
                            !inReview
                        ? context.tr(
                            'Complete identity verification before banking setup')
                        : _providerCaption(
                            onboarded: onboarded,
                            needsInput: needsInput,
                            inReview: inReview,
                            isBusinessAccount: isBusinessAccount,
                            accountId: accountId,
                          ),
                    trailing: _providerPill(
                      context,
                      onboarded: onboarded,
                      needsInput: needsInput,
                      inReview: inReview,
                    ),
                  ),
                  if (!needsInput) ...[
                    PlatformActionRow(
                      icon: Icons.info_outline,
                      label: context.tr('Banking info'),
                      description: onboarded
                          ? context.tr('View EqualsMoney account details')
                          : context.tr('Available after EqualsMoney approval'),
                      enabled: onboarded,
                      onPressed: onboarded
                          ? (context, ref) => ref
                                  .read(
                                      platformActionControllerProvider.notifier)
                                  .run(
                                (api) async {
                                  final info = await api.getEqualsBankingInfo();

                                  return ActionResult(
                                    message: info.title,
                                    reference: info.id,
                                    metadata: info.metadata,
                                  );
                                },
                              )
                          : null,
                    ),
                    PlatformActionRow(
                      icon: Icons.savings_outlined,
                      label: context.tr('Create EUR budget'),
                      description: onboarded
                          ? context.tr('Set a monthly spending pool')
                          : context.tr('Available after EqualsMoney approval'),
                      enabled: onboarded,
                      onPressed: onboarded
                          ? (context, ref) => ref
                              .read(platformActionControllerProvider.notifier)
                              .run((api) => api.createBudget(
                                    name: 'New budget',
                                    currency: 'EUR',
                                  ))
                          : null,
                    ),
                    PlatformActionRow(
                      icon: Icons.edit_outlined,
                      label: context.tr('Update budget'),
                      description: onboarded
                          ? context.tr('Adjust budget settings')
                          : context.tr('Available after EqualsMoney approval'),
                      enabled: onboarded,
                      onPressed: onboarded
                          ? (context, ref) => ref
                              .read(platformActionControllerProvider.notifier)
                              .run(
                                (api) => api.updateBudget(
                                  budgetId: 'budget_ops',
                                  name: 'Operations',
                                  currency: 'EUR',
                                ),
                              )
                          : null,
                    ),
                    PlatformActionRow(
                      icon: Icons.compare_arrows,
                      label: context.tr('Move budget funds'),
                      description: onboarded
                          ? context.tr('Transfer between budgets')
                          : context.tr('Available after EqualsMoney approval'),
                      enabled: onboarded,
                      onPressed: onboarded
                          ? (context, ref) => ref
                              .read(platformActionControllerProvider.notifier)
                              .run(
                                (api) => api.transferBudget(
                                  fromBudgetId: 'budget_ops',
                                  toBudgetId: 'budget_cards',
                                  amount: const Money(
                                    currency: 'EUR',
                                    minorUnits: 2500,
                                  ),
                                ),
                              )
                          : null,
                    ),
                  ],
                ],
              ),
              if (!needsInput) ...[
                platformSectionGap,
                ExampleSectionTitle(title: context.tr('Providers')),
                const SizedBox(height: AppSpacing.sm),
                ExampleStateSwitch(
                  alignment: Alignment.topCenter,
                  child: ref.watch(providersProvider).when(
                        data: (items) => ResourceList(
                          key: const ValueKey('providers-data'),
                          resources: onboarded ? items : const [],
                          emptyTitle: onboarded
                              ? context.tr('No providers connected')
                              : context.tr('Provider details locked'),
                          emptyMessage: onboarded
                              ? context.tr(
                                  'Provider details appear here after the first sync.')
                              : context.tr(
                                  'Complete EqualsMoney approval before account details are shown.'),
                          icon: Icons.account_balance,
                        ),
                        error: (error, stackTrace) => PlatformErrorState(
                          key: const ValueKey('providers-error'),
                          error: error,
                          onRetry: () => ref.invalidate(providersProvider),
                        ),
                        loading: () => PlatformLoadingGroup(
                          key: const ValueKey('providers-loading'),
                          rows: 2,
                          label: context.tr('Loading providers'),
                        ),
                      ),
                ),
                platformSectionGap,
                ExampleSectionTitle(title: context.tr('Budgets')),
                const SizedBox(height: AppSpacing.sm),
                ExampleStateSwitch(
                  alignment: Alignment.topCenter,
                  child: ref.watch(budgetsProvider).when(
                        data: (items) => ResourceList(
                          key: const ValueKey('budgets-data'),
                          showSafeguarding: true,
                          resources: onboarded ? items : const [],
                          emptyTitle: onboarded
                              ? context.tr('No budgets yet')
                              : context.tr('Budgets locked'),
                          emptyMessage: onboarded
                              ? context
                                  .tr('Create a budget to organise spending.')
                              : context.tr(
                                  'Budgets unlock after EqualsMoney approval.'),
                          icon: Icons.savings_outlined,
                        ),
                        error: (error, stackTrace) => PlatformErrorState(
                          key: const ValueKey('budgets-error'),
                          error: error,
                          onRetry: () => ref.invalidate(budgetsProvider),
                        ),
                        loading: () => PlatformLoadingGroup(
                          key: const ValueKey('budgets-loading'),
                          rows: 2,
                          label: context.tr('Loading budgets'),
                        ),
                      ),
                ),
                const SafeguardingStatementButton(),
              ],
            ],
          ),
        ),
        _StickyNextStep(
          status: status,
          isBusinessAccount: isBusinessAccount,
          onboarded: onboarded,
          needsInput: needsInput,
          inReview: inReview,
        ),
      ],
    );
  }
}

IconData _providerIcon({
  required bool onboarded,
  required bool needsInput,
  required bool inReview,
}) {
  if (onboarded) return Icons.check_circle_outline;
  if (needsInput || inReview) return Icons.hourglass_top;
  return Icons.account_balance;
}

String _providerCaption({
  required bool onboarded,
  required bool needsInput,
  required bool inReview,
  required bool isBusinessAccount,
  required String? accountId,
}) {
  if (onboarded) return 'Account ${accountId ?? 'connected'} is ready';
  if (needsInput) {
    return 'Upload documents or finish the secure provider check';
  }
  if (inReview) return 'We update this screen when the provider approves it';
  return isBusinessAccount
      ? 'Open an EU/UK business account'
      : 'Open your banking setup';
}

Widget _providerPill(
  BuildContext context, {
  required bool onboarded,
  required bool needsInput,
  required bool inReview,
}) {
  if (onboarded) {
    return ExamplePill(
      label: context.tr('Active'),
      color: ExampleColors.success,
      dot: true,
    );
  }
  if (needsInput) {
    return ExamplePill(
      label: context.tr('Action needed'),
      color: ExampleColors.warning,
      dot: true,
    );
  }
  if (inReview) {
    return ExamplePill(
      label: context.tr('In review'),
      color: ExampleColors.warning,
      dot: true,
    );
  }
  return ExamplePill(label: context.tr('Not started'), color: ExampleColors.iris);
}

/// Setup progress: the count, the step bar, and the three checks as hairline
/// rows on one surface. The step bar is the screen's only sheen host.
class _SetupPanel extends StatelessWidget {
  const _SetupPanel({required this.status});

  final AsyncValue<KycDetailedStatus> status;

  @override
  Widget build(BuildContext context) {
    final detailed = status.valueOrNull;
    final total = detailed?.setupStepCount ?? 3;
    final completed = detailed?.completedSetupStepCount;
    final steps = <({String label, bool? done})>[
      (
        label: context.tr('Identity verification'),
        done: detailed?.isHoppaApproved
      ),
      (label: context.tr('Bank KYC'), done: detailed?.isBankApproved),
      (label: context.tr('Card issuer'), done: detailed?.isCardIssuerApproved),
    ];
    final side = ExampleBorders.hairlineSideOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Banking setup'),
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  completed == null
                      ? '—'
                      : context
                          .tr('{p0} of {p1}', {'p0': completed, 'p1': total}),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.secondary(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _StepBar(total: total, completed: completed ?? 0),
            const SizedBox(height: AppSpacing.xs),
            for (var i = 0; i < steps.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: side)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    children: [
                      Icon(
                        steps[i].done == true
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: steps[i].done == true
                            ? ExampleInk.accent(context, ExampleColors.success)
                            : ExampleInk.tertiary(context),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          context.tr(steps[i].label),
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (detailed?.hasEqualsMoneyAccount ?? false)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: side)),
                child: Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: ExampleMono(
                    'Account ${detailed!.equalsMoneyAccountId}',
                    size: 11.5,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The step hairline: one 2 pt segment per setup step, filled as each one
/// lands, and the single sheen host on this screen.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.total, required this.completed});

  final int total;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    return Semantics(
      label: context.tr('Setup progress, {p0} of {p1} steps complete',
          {'p0': completed, 'p1': total}),
      child: ExampleSheen(
        borderRadius: const BorderRadius.all(Radius.circular(1)),
        intensity: ExampleSheenIntensity.soft,
        child: Row(
          children: [
            for (var i = 0; i < total; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: i < completed ? palette.fill : palette.borderSubtle,
                    borderRadius: const BorderRadius.all(Radius.circular(1)),
                  ),
                  child: const SizedBox(height: 2),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// What EqualsMoney is waiting for, on one surface: the message, then each
/// requested document as a hairline row with its own action. The link that
/// continues the provider check lives in the sticky bar, not here, so the
/// screen never offers the same button twice.
class _RequiredActionPanel extends ConsumerWidget {
  const _RequiredActionPanel({required this.status});

  final KycDetailedStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = status.equalsMoneyAdditionalDocumentsRequested;
    final side = ExampleBorders.hairlineSideOf(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ExampleIconTile(
                  icon: Icons.assignment_late_outlined,
                  color: ExampleColors.warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('EqualsMoney needs your input'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                          color: ExampleInk.primary(context),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        context.tr(_equalsMoneyActionMessage(
                          hasDocuments: documents.isNotEmpty,
                          hasActionUrl: status.hasEqualsMoneyActionUrl,
                          requiredAction: status.equalsMoneyRequiredAction,
                        )),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            for (final document in documents)
              DecoratedBox(
                decoration: BoxDecoration(border: Border(top: side)),
                child: Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: _ExampleDocumentRow(document: document),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExampleDocumentRow extends ConsumerWidget {
  const _ExampleDocumentRow({required this.document});

  final EqualsMoneyAdditionalDocumentRequest document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);
    final details = document.expectsFiles
        ? [
            document.type,
            if (document.associatedPersonName != null)
              document.associatedPersonName!,
            if (document.associatedPersonEmail != null)
              document.associatedPersonEmail!,
            if (document.additionalInformation != null)
              document.additionalInformation!,
          ].join(' · ')
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ExampleIconTile(
            icon: Icons.description_outlined,
            color: ExampleColors.iris,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _equalsMoneyRequestLabel(document.type, document.text),
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                    color: ExampleInk.primary(context),
                  ),
                ),
                if (details != null && details.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          action.isLoading
              ? const Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: AppSpacing.sm,
                  ),
                  child: SizedBox.square(
                    dimension: 18,
                    child: AppProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  onPressed: () => document.expectsFiles
                      ? _chooseAndUploadEqualsMoneyDocument(
                          context,
                          ref,
                          document,
                        )
                      : _answerEqualsMoneyInformation(context, ref, document),
                  icon: Icon(
                    document.expectsFiles
                        ? Icons.upload_file
                        : Icons.edit_note_outlined,
                    size: 18,
                  ),
                  label: Text(document.expectsFiles
                      ? context.tr('Upload')
                      : context.tr('Answer')),
                ),
        ],
      ),
    );
  }
}

/// The one next step, pinned above the safe area in a frosted bar. Renders
/// nothing at all when the account is approved or the provider is reviewing:
/// an empty bar is worse than no bar.
class _StickyNextStep extends ConsumerWidget {
  const _StickyNextStep({
    required this.status,
    required this.isBusinessAccount,
    required this.onboarded,
    required this.needsInput,
    required this.inReview,
  });

  final KycDetailedStatus? status;
  final bool isBusinessAccount;
  final bool onboarded;
  final bool needsInput;
  final bool inReview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);
    final busy = action.isLoading;
    final current = status;

    String label;
    IconData icon;
    VoidCallback? onPressed;
    if (needsInput && current != null && current.hasEqualsMoneyActionUrl) {
      label = _equalsMoneyActionLabel(current.equalsMoneyRequiredAction);
      icon = Icons.open_in_new;
      onPressed = busy
          ? null
          : () => _openEqualsMoneyActionUrl(
                context,
                ref,
                fallbackUrl: current.equalsMoneyActionUrl!,
              );
    } else if (!onboarded && !needsInput && !inReview) {
      label = isBusinessAccount
          ? 'Start business onboarding'
          : current == null
              ? 'Identity status unavailable'
              : !current.isHoppaApproved
                  ? 'Continue identity verification'
                  : 'Start EqualsMoney';
      icon = Icons.arrow_forward_rounded;
      onPressed = busy || (!isBusinessAccount && current == null)
          ? null
          : isBusinessAccount
              ? () => context.go(AppRoutes.business)
              : current?.isHoppaApproved != true
                  ? () => context.go(AppRoutes.kyc)
                  : () => _showEqualsMoneyDialog(context, ref);
    } else {
      return const SizedBox.shrink();
    }

    // The one decisive action of the onboarding flow, in the bar that is
    // pinned to it. Ground is `surface`, not `atmosphere`: PlatformStickyBar
    // already runs the screen's one BackdropFilter and paints a gradient over
    // it, so from this button's point of view the ground is opaque. A second,
    // nested blur would sample the first one's own output — an expensive way
    // to make the bar look muddier.
    return PlatformStickyBar(
      child: ExampleGlassButton(
        label: label,
        icon: icon,
        loading: busy,
        onPressed: onPressed,
      ),
    );
  }
}

/// The pre-Example screen, kept byte-identical for every white-label tenant.
class _LegacyBody extends ConsumerWidget {
  const _LegacyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kycStatus = ref.watch(kycDetailedStatusProvider);
    final dashboard = ref.watch(dashboardProvider);
    final isBusinessAccount =
        dashboard.valueOrNull?.profile.isBusinessAccount ?? false;
    final equalsMoneyOnboarded = kycStatus.maybeWhen(
      data: (status) => status.canUseEqualsMoneyBanking,
      orElse: () => false,
    );
    final equalsMoneyNeedsInput =
        kycStatus.valueOrNull?.requiresEqualsMoneyAction ?? false;
    final equalsMoneyInReview =
        kycStatus.valueOrNull?.hasEqualsMoneyReviewState ?? false;
    final equalsMoneyAccountId = kycStatus.valueOrNull?.equalsMoneyAccountId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _OnboardingProgressCard(status: kycStatus),
        if (equalsMoneyNeedsInput) ...[
          const SizedBox(height: 16),
          EqualsMoneyRequiredActionCard(status: kycStatus.valueOrNull!),
        ],
        const SizedBox(height: 16),
        Text(
          equalsMoneyNeedsInput
              ? context.tr('Required now')
              : context.tr('Next actions'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        _ActionTile(
          enabled: !equalsMoneyOnboarded &&
              !equalsMoneyNeedsInput &&
              !equalsMoneyInReview &&
              (isBusinessAccount || kycStatus.hasValue),
          icon: equalsMoneyOnboarded
              ? Icons.check_circle_outline
              : equalsMoneyNeedsInput || equalsMoneyInReview
                  ? Icons.hourglass_top
                  : Icons.account_balance,
          title: equalsMoneyOnboarded
              ? context.tr('EqualsMoney active')
              : equalsMoneyNeedsInput
                  ? context.tr('EqualsMoney waiting for you')
                  : equalsMoneyInReview
                      ? context.tr('EqualsMoney in review')
                      : isBusinessAccount
                          ? context.tr('Start EqualsMoney business')
                          : kycStatus.valueOrNull?.isHoppaApproved == true
                              ? context.tr('Start EqualsMoney')
                              : context.tr('Continue identity verification'),
          subtitle: equalsMoneyOnboarded
              ? context.tr('Account {p0} is ready',
                  {'p0': equalsMoneyAccountId ?? 'connected'})
              : equalsMoneyNeedsInput
                  ? context.tr(
                      'Upload documents or complete the secure provider check')
                  : equalsMoneyInReview
                      ? context.tr(
                          'We will update this screen when the provider approves it')
                      : isBusinessAccount
                          ? context.tr('Open EU/UK business account')
                          : kycStatus.valueOrNull?.isHoppaApproved == true
                              ? context.tr('Open banking setup')
                              : context.tr(
                                  'Identity verification must be approved first'),
          onTap: equalsMoneyOnboarded ||
                  equalsMoneyNeedsInput ||
                  equalsMoneyInReview
              ? null
              : isBusinessAccount
                  ? (context, ref) => context.go(AppRoutes.business)
                  : kycStatus.valueOrNull?.isHoppaApproved == true
                      ? (context, ref) => _showEqualsMoneyDialog(context, ref)
                      : (context, ref) => context.go(AppRoutes.kyc),
        ),
        if (!equalsMoneyNeedsInput) ...[
          _ActionTile(
            enabled: equalsMoneyOnboarded,
            icon: Icons.info_outline,
            title: context.tr('Banking info'),
            subtitle: equalsMoneyOnboarded
                ? context.tr('View EqualsMoney account details')
                : context.tr('Available after EqualsMoney approval'),
            onTap: equalsMoneyOnboarded
                ? (context, ref) =>
                    ref.read(platformActionControllerProvider.notifier).run(
                      (api) async {
                        final info = await api.getEqualsBankingInfo();

                        return ActionResult(
                          message: info.title,
                          reference: info.id,
                          metadata: info.metadata,
                        );
                      },
                    )
                : null,
          ),
          _ActionTile(
            enabled: equalsMoneyOnboarded,
            icon: Icons.savings_outlined,
            title: context.tr('Create EUR budget'),
            subtitle: equalsMoneyOnboarded
                ? context.tr('Set a monthly spending pool')
                : context.tr('Available after EqualsMoney approval'),
            onTap: equalsMoneyOnboarded
                ? (context, ref) => ref
                    .read(platformActionControllerProvider.notifier)
                    .run((api) => api.createBudget(
                          name: 'New budget',
                          currency: 'EUR',
                        ))
                : null,
          ),
          _ActionTile(
            enabled: equalsMoneyOnboarded,
            icon: Icons.edit_outlined,
            title: context.tr('Update budget'),
            subtitle: equalsMoneyOnboarded
                ? context.tr('Adjust budget settings')
                : context.tr('Available after EqualsMoney approval'),
            onTap: equalsMoneyOnboarded
                ? (context, ref) =>
                    ref.read(platformActionControllerProvider.notifier).run(
                          (api) => api.updateBudget(
                            budgetId: 'budget_ops',
                            name: 'Operations',
                            currency: 'EUR',
                          ),
                        )
                : null,
          ),
          _ActionTile(
            enabled: equalsMoneyOnboarded,
            icon: Icons.compare_arrows,
            title: context.tr('Move budget funds'),
            subtitle: equalsMoneyOnboarded
                ? context.tr('Transfer between budgets')
                : context.tr('Available after EqualsMoney approval'),
            onTap: equalsMoneyOnboarded
                ? (context, ref) =>
                    ref.read(platformActionControllerProvider.notifier).run(
                          (api) => api.transferBudget(
                            fromBudgetId: 'budget_ops',
                            toBudgetId: 'budget_cards',
                            amount: const Money(
                              currency: 'EUR',
                              minorUnits: 2500,
                            ),
                          ),
                        )
                : null,
          ),
          const SizedBox(height: 24),
          Text(context.tr('Providers'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ref.watch(providersProvider).when(
                data: (items) => ResourceList(
                  resources: equalsMoneyOnboarded ? items : const [],
                  emptyTitle: equalsMoneyOnboarded
                      ? context.tr('No providers connected')
                      : context.tr('Provider details locked'),
                  emptyMessage: equalsMoneyOnboarded
                      ? context.tr('Provider details will appear after sync.')
                      : context.tr(
                          'Complete EqualsMoney approval before account details are shown.'),
                  icon: Icons.account_balance,
                ),
                error: (error, stackTrace) => ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(providersProvider),
                ),
                loading: () =>
                    LoadingState(label: context.tr('Loading providers')),
              ),
          const SizedBox(height: 24),
          Text(context.tr('Budgets'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ref.watch(budgetsProvider).when(
                data: (items) => ResourceList(
                  resources: equalsMoneyOnboarded ? items : const [],
                  emptyTitle: equalsMoneyOnboarded
                      ? context.tr('No budgets yet')
                      : context.tr('Budgets locked'),
                  emptyMessage: equalsMoneyOnboarded
                      ? context.tr('Create a budget to organize spending.')
                      : context
                          .tr('Budgets unlock after EqualsMoney approval.'),
                  icon: Icons.savings_outlined,
                ),
                error: (error, stackTrace) => ErrorState(
                  error: error,
                  onRetry: () => ref.invalidate(budgetsProvider),
                ),
                loading: () =>
                    LoadingState(label: context.tr('Loading budgets')),
              ),
        ],
      ],
    );
  }
}

class _OnboardingProgressCard extends StatelessWidget {
  const _OnboardingProgressCard({required this.status});

  final AsyncValue<KycDetailedStatus> status;

  @override
  Widget build(BuildContext context) {
    final detailedStatus = status.valueOrNull;
    final completed = detailedStatus?.completedSetupStepCount;
    final total = detailedStatus?.setupStepCount ?? 3;
    final progress = completed == null ? null : completed / total;
    final stepLabel = completed == null ? '...' : '$completed/$total';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle_outline),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('Banking setup'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(
                  stepLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _SetupChip(
                  label: context.tr('Identity verification'),
                  isComplete: detailedStatus?.isHoppaApproved,
                ),
                _SetupChip(
                  label: context.tr('Bank KYC'),
                  isComplete: detailedStatus?.isBankApproved,
                ),
                _SetupChip(
                  label: context.tr('Card issuer'),
                  isComplete: detailedStatus?.isCardIssuerApproved,
                ),
              ],
            ),
            if (detailedStatus?.hasEqualsMoneyAccount ?? false) ...[
              const SizedBox(height: 8),
              Text(
                context.tr('EqualsMoney account {p0}',
                    {'p0': detailedStatus!.equalsMoneyAccountId}),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EqualsMoneyRequiredActionCard extends ConsumerWidget {
  const EqualsMoneyRequiredActionCard({required this.status, super.key});

  final KycDetailedStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final action = ref.watch(platformActionControllerProvider);
    final documents = status.equalsMoneyAdditionalDocumentsRequested;
    final hasActionUrl = status.hasEqualsMoneyActionUrl;
    final requiredAction = status.equalsMoneyRequiredAction;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.assignment_late_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('EqualsMoney needs your input'),
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(_equalsMoneyActionMessage(
                          hasDocuments: documents.isNotEmpty,
                          hasActionUrl: hasActionUrl,
                          requiredAction: requiredAction,
                        )),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (documents.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final document in documents) ...[
                _EqualsMoneyDocumentTile(document: document),
                const SizedBox(height: 8),
              ],
            ],
            if (!hasActionUrl &&
                _isIdentityVerificationAction(requiredAction)) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => ref.invalidate(kycDetailedStatusProvider),
                icon: const Icon(Icons.refresh),
                label: Text(context.tr('Refresh status')),
              ),
            ],
            if (hasActionUrl) ...[
              const SizedBox(height: 8),
              // This card is NOT onboarding-only: `AccountsContent` and the
              // money surface both render it as the entire body when the
              // provider is blocking, so on Example this button was the whole
              // screen's decisive action still wearing the Material slab.
              // Gated on the theme, because the same card is the white-label
              // onboarding body too and that tree must not move.
              //
              // `surface` ground — a Material Card paints an opaque floor and
              // there is nothing behind it worth blurring. `loading` carries
              // the action controller's busy state in place, so the label
              // does not vanish mid-redirect.
              if (context.isExampleTheme)
                ExampleGlassButton(
                  label: context.tr(_equalsMoneyActionLabel(requiredAction)),
                  icon: Icons.open_in_new,
                  loading: action.isLoading,
                  onPressed: action.isLoading
                      ? null
                      : () => _openEqualsMoneyActionUrl(
                            context,
                            ref,
                            fallbackUrl: status.equalsMoneyActionUrl!,
                          ),
                )
              else
                FilledButton.icon(
                  onPressed: action.isLoading
                      ? null
                      : () => _openEqualsMoneyActionUrl(
                            context,
                            ref,
                            fallbackUrl: status.equalsMoneyActionUrl!,
                          ),
                  icon: const Icon(Icons.open_in_new),
                  label: Text(
                    context.tr(_equalsMoneyActionLabel(requiredAction)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EqualsMoneyDocumentTile extends ConsumerWidget {
  const _EqualsMoneyDocumentTile({required this.document});

  final EqualsMoneyAdditionalDocumentRequest document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: const Icon(Icons.description_outlined),
        title: Text(_equalsMoneyRequestLabel(document.type, document.text)),
        subtitle: document.expectsFiles
            ? Text(
                [
                  document.type,
                  if (document.associatedPersonName != null)
                    document.associatedPersonName!,
                  if (document.associatedPersonEmail != null)
                    document.associatedPersonEmail!,
                  if (document.additionalInformation != null)
                    document.additionalInformation!,
                ].join('\n'),
              )
            : null,
        trailing: action.isLoading
            ? const SizedBox.square(
                dimension: 18,
                child: AppProgressIndicator(strokeWidth: 2),
              )
            : TextButton.icon(
                onPressed: () => document.expectsFiles
                    ? _chooseAndUploadEqualsMoneyDocument(
                        context,
                        ref,
                        document,
                      )
                    : _answerEqualsMoneyInformation(context, ref, document),
                icon: Icon(
                  document.expectsFiles
                      ? Icons.upload_file
                      : Icons.edit_note_outlined,
                ),
                label: Text(document.expectsFiles
                    ? context.tr('Upload')
                    : context.tr('Answer')),
              ),
      ),
    );
  }
}

class _SetupChip extends StatelessWidget {
  const _SetupChip({
    required this.label,
    required this.isComplete,
  });

  final String label;
  final bool? isComplete;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        isComplete == true ? Icons.check_circle : Icons.radio_button_unchecked,
        size: 18,
      ),
      label: Text(label),
    );
  }
}

class _ActionTile extends ConsumerWidget {
  const _ActionTile({
    this.enabled = true,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool enabled;
  final IconData icon;
  final String title;
  final String subtitle;
  final void Function(BuildContext context, WidgetRef ref)? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);

    return Card(
      child: ListTile(
        enabled: enabled && !action.isLoading,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: action.isLoading
            ? const SizedBox.square(
                dimension: 18,
                child: AppProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right),
        onTap: enabled && !action.isLoading && onTap != null
            ? () => onTap!(context, ref)
            : null,
      ),
    );
  }
}

/// Whether the customer is on a tier. Null when the lookup failed: an unknown
/// answer is not "no tier", so the application is not blocked on it.
Future<bool?> _hasSelectedTier(WidgetRef ref) async {
  try {
    final current = await ref.read(mobilePlatformApiProvider).getCurrentTier();
    return tierIdOf(current) != null;
  } catch (_) {
    return null;
  }
}

/// Opening an account needs a tier: say so, and lead straight to the tiers.
Future<void> _showTierRequiredNotice(BuildContext context) {
  return showExampleSheet<void>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(title: sheetContext.tr('Choose a tier first')),
        const SizedBox(height: AppSpacing.xs),
        const ExampleSheetNote(
            'Your account can only be opened on a tier. Choose one, then come back here to open your account.'),
        const SizedBox(height: AppSpacing.md),
        ExampleSheetCta(
          label: sheetContext.tr('Choose a tier'),
          onPressed: () {
            Navigator.of(sheetContext).pop();
            context.push(AppRoutes.tiers);
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        ExampleGlassButton(
          label: sheetContext.tr('Not now'),
          tone: ExampleGlassButtonTone.neutral,
          ground: ExampleGlassGround.surface,
          sheen: false,
          onPressed: () => Navigator.of(sheetContext).pop(),
        ),
      ],
    ),
  );
}

Future<void> _showEqualsMoneyDialog(BuildContext context, WidgetRef ref) async {
  // Refresh at the entry point as the visible status may be stale.
  try {
    final status =
        await ref.read(mobilePlatformApiProvider).getDetailedKycStatus();
    if (!context.mounted) return;
    ref.invalidate(kycDetailedStatusProvider);
    if (!status.isHoppaApproved) {
      context.go(AppRoutes.kyc);
      return;
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          context.tr('Unable to verify identity status. Please try again.')),
    ));
    return;
  }
  // The provider refuses an account application without a tier, and says so
  // only after the whole form has been filled in. Account setup lets the
  // tier step be skipped, so ask for it here, before the form.
  if (await _hasSelectedTier(ref) == false) {
    if (context.mounted) await _showTierRequiredNotice(context);
    return;
  }
  if (!context.mounted) return;
  final formKey = GlobalKey<FormState>();
  var includeCards = true;
  var mainPurposes = ['PURCHASE_OF_GOODS_OR_SERVICES'];
  var sourceOfFunds = ['RECEIVING_FUNDS_FROM_OWN_ACCOUNTS'];
  var destinationCountries = ['GB'];
  var currencies = ['GBP'];
  var annualVolume = '10001-50000';
  var numberOfPayments = '5-10';
  var cardPurposes = ['PURCHASE_OF_GOODS_OR_SERVICES'];
  var cardAnnualSpend = '0-10000';
  var numberOfCardsRequired = '0-10';
  var atmWithdrawalsRequired = false;
  UploadDocument? proofOfAddress;
  String? uploadError;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(context.tr('EqualsMoney onboarding')),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SearchableMultiSelectDropdown(
                  label: context.tr('Main purposes'),
                  values: mainPurposes,
                  options: equalsPersonalPurposeOptions,
                  onChanged: (value) => setState(() => mainPurposes = value),
                ),
                const SizedBox(height: 12),
                SearchableMultiSelectDropdown(
                  label: context.tr('Sources of funds'),
                  values: sourceOfFunds,
                  options: equalsPersonalSourceOfFundsOptions,
                  onChanged: (value) => setState(() => sourceOfFunds = value),
                ),
                const SizedBox(height: 12),
                SearchableMultiSelectDropdown(
                  label: context.tr('Destination countries'),
                  values: destinationCountries,
                  options: equalsCountryCodes,
                  onChanged: (value) =>
                      setState(() => destinationCountries = value),
                ),
                const SizedBox(height: 12),
                SearchableMultiSelectDropdown(
                  label: context.tr('Required currencies'),
                  values: currencies,
                  options: equalsSupportedCurrencyCodes,
                  onChanged: (value) => setState(() => currencies = value),
                ),
                const SizedBox(height: 12),
                _RequiredDropdown(
                  label: context.tr('Annual volume'),
                  value: annualVolume,
                  options: equalsAnnualVolumeOptions,
                  onChanged: (value) => setState(() => annualVolume = value),
                ),
                const SizedBox(height: 12),
                _RequiredDropdown(
                  label: context.tr('Number of payments'),
                  value: numberOfPayments,
                  options: equalsPersonalPaymentCountOptions,
                  onChanged: (value) =>
                      setState(() => numberOfPayments = value),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Request cards')),
                  value: includeCards,
                  onChanged: (value) => setState(() => includeCards = value),
                ),
                if (includeCards) ...[
                  SearchableMultiSelectDropdown(
                    label: context.tr('Card purposes'),
                    values: cardPurposes,
                    options: equalsPersonalPurposeOptions,
                    onChanged: (value) => setState(() => cardPurposes = value),
                  ),
                  const SizedBox(height: 12),
                  _RequiredDropdown(
                    label: context.tr('Annual card spend'),
                    value: cardAnnualSpend,
                    options: equalsAnnualVolumeOptions,
                    onChanged: (value) =>
                        setState(() => cardAnnualSpend = value),
                  ),
                  const SizedBox(height: 12),
                  _RequiredDropdown(
                    label: context.tr('Number of cards required'),
                    value: numberOfCardsRequired,
                    options: equalsCardCountOptions,
                    onChanged: (value) =>
                        setState(() => numberOfCardsRequired = value),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(context.tr('ATM withdrawals required')),
                    value: atmWithdrawalsRequired,
                    onChanged: (value) =>
                        setState(() => atmWithdrawalsRequired = value),
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.upload_file),
                  title: Text(
                    proofOfAddress?.name ?? 'Proof of address',
                  ),
                  subtitle: Text(
                      context.tr('PDF, JPG, JPEG, or PNG. Maximum 10 MB.')),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        final result = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
                          withData: true,
                        );
                        if (result == null || !context.mounted) return;
                        final document = UploadDocument.fromPlatformFile(
                            result.files.single);
                        setState(() {
                          proofOfAddress = document;
                          uploadError = null;
                        });
                      } catch (error) {
                        if (!context.mounted) return;
                        setState(() => uploadError = error is FormatException
                            ? error.message
                            : 'The file could not be opened. Please choose it again.');
                      }
                    },
                    child: Text(context.tr('Choose')),
                  ),
                ),
                if (proofOfAddress == null || uploadError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      uploadError ?? 'Proof of address is required.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () {
              final hasSelections = mainPurposes.isNotEmpty &&
                  sourceOfFunds.isNotEmpty &&
                  destinationCountries.isNotEmpty &&
                  currencies.isNotEmpty &&
                  (!includeCards || cardPurposes.isNotEmpty);
              if (!(formKey.currentState?.validate() ?? false) ||
                  !hasSelections ||
                  proofOfAddress == null) {
                return;
              }
              Navigator.of(context).pop(true);
            },
            child: Text(context.tr('Submit')),
          ),
        ],
      ),
    ),
  );

  if (!context.mounted || confirmed != true || proofOfAddress == null) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.startEqualsMoneyOnboarding(
          requestedFeatures:
              includeCards ? ['PAYMENTS', 'CARDS'] : ['PAYMENTS'],
          mainPurpose: mainPurposes,
          sourceOfFunds: sourceOfFunds,
          destinationOfFunds: destinationCountries,
          currenciesRequired: currencies,
          annualVolume: annualVolume,
          numberOfPayments: numberOfPayments,
          cardPurposes: includeCards ? cardPurposes : const [],
          cardAnnualSpend: includeCards ? cardAnnualSpend : null,
          numberOfCardsRequired: includeCards ? numberOfCardsRequired : null,
          atmWithdrawalsRequired: atmWithdrawalsRequired,
          proofOfAddress: proofOfAddress,
        ),
      );
}

Future<void> _chooseAndUploadEqualsMoneyDocument(
  BuildContext context,
  WidgetRef ref,
  EqualsMoneyAdditionalDocumentRequest document,
) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || !context.mounted) return;
    if (result.files.length > 10) {
      throw const FormatException('Choose at most 10 documents at a time.');
    }
    final documents =
        result.files.map(UploadDocument.fromPlatformFile).toList();
    if (documents.isEmpty) return;
    await ref.read(platformActionControllerProvider.notifier).run(
          (api) => api.uploadEqualsMoneyDocument(
            type: document.type,
            documents: documents,
            applicationId: document.applicationId,
            associatedPersonId: document.associatedPersonId,
          ),
        );
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error is FormatException
          ? error.message
          : context
              .tr('The files could not be opened. Please choose them again.')),
    ));
  }
}

Future<void> _answerEqualsMoneyInformation(
  BuildContext context,
  WidgetRef ref,
  EqualsMoneyAdditionalDocumentRequest request,
) async {
  final answer = await showAdditionalInformationDialog(
    context,
    title: _equalsMoneyRequestLabel(request.type, request.text),
  );
  if (answer == null || !context.mounted) {
    return;
  }

  await ref.read(platformActionControllerProvider.notifier).run(
        (api) => api.submitEqualsMoneyInformation(
          type: request.type,
          response: answer,
          associatedPersonId: request.associatedPersonId,
        ),
      );
}

String _equalsMoneyRequestLabel(String type, String fallback) {
  return type.trim().toUpperCase() == 'RESIDENTIAL_ADDRESS'
      ? 'Enter your residential address'
      : fallback;
}

Future<void> _openEqualsMoneyActionUrl(
  BuildContext context,
  WidgetRef ref, {
  required String fallbackUrl,
}) async {
  var url = fallbackUrl;
  try {
    final freshStatus =
        await ref.read(mobilePlatformApiProvider).getDetailedKycStatus();
    final freshUrl = freshStatus.equalsMoneyActionUrl;
    if (freshUrl != null && freshUrl.trim().isNotEmpty) {
      url = freshUrl.trim();
    }
    ref.invalidate(kycDetailedStatusProvider);
  } catch (_) {
    // Keep the currently displayed URL as a fallback if refresh is unavailable.
  }

  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('EqualsMoney check link is invalid.'))),
      );
    }
    return;
  }

  final opened = await launchUrl(
    uri,
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('Could not open EqualsMoney check.'))),
    );
  }
}

String _equalsMoneyActionMessage({
  required bool hasDocuments,
  required bool hasActionUrl,
  required String? requiredAction,
}) {
  if (hasDocuments && hasActionUrl) {
    return 'Upload the requested documents here, then continue the secure EqualsMoney check.';
  }
  if (hasDocuments) {
    return 'Upload each requested document so EqualsMoney can continue the review.';
  }
  if (!hasActionUrl && _isIdentityVerificationAction(requiredAction)) {
    return 'EqualsMoney requires identity verification, but the verification link is currently unavailable. Refresh the status or contact support.';
  }
  if (requiredAction?.trim().toLowerCase() == 'identityverificationcheck') {
    return 'Complete the secure EqualsMoney identity verification before the account can be approved.';
  }
  if (_isLivenessAction(requiredAction)) {
    return 'EqualsMoney needs a liveness check before the account can be approved.';
  }

  return 'EqualsMoney needs an additional check before the account can be approved.';
}

String _equalsMoneyActionLabel(String? action) {
  if (action?.trim().toLowerCase() == 'identityverificationcheck') {
    return 'Complete identity verification';
  }
  return _isLivenessAction(action)
      ? 'Continue liveness check'
      : 'Continue EqualsMoney check';
}

bool _isIdentityVerificationAction(String? action) =>
    action?.trim().toLowerCase() == 'identityverificationcheck' ||
    _isLivenessAction(action);

bool _isLivenessAction(String? action) {
  final normalized = action?.toLowerCase().trim() ?? '';
  return normalized.contains('liveness') || normalized.contains('liveless');
}

class _RequiredDropdown extends StatelessWidget {
  const _RequiredDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              option.replaceAll('_', ' '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      validator: (value) => value == null ? '$label is required' : null,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}
