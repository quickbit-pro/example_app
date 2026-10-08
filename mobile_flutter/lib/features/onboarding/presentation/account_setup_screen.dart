import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example_glass_button.dart';
import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/platform_widgets.dart';
import '../../platform/presentation/tiers_screen.dart';
import '../../platform/presentation/tier_details_sheet.dart';
import '../application/account_setup_providers.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

/// First-login checklist for personal accounts: verify identity, pick a
/// tier. Home opens it automatically until both are done or it is skipped.
class AccountSetupScreen extends ConsumerWidget {
  const AccountSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final currentTierState = ref.watch(currentTierProvider);
    final tiers = currentTierState.when<AsyncValue<List<PlatformResource>>>(
      data: (current) => tierIdOf(current) != null
          ? const AsyncData([])
          : ref.watch(tiersProvider),
      loading: () => const AsyncLoading(),
      error: (error, stack) => AsyncError(error, stack),
    );
    final currentTier = ref.watch(currentTierProvider);
    final action = ref.watch(platformActionControllerProvider);
    final kycStatus = dashboard.valueOrNull?.profile.kycStatus ?? '';
    final identity = identityStageFor(kycStatus);
    final selectedTierId = tierIdOf(currentTier.valueOrNull);
    final tierChosen = selectedTierId != null;
    final canContinue = identity != IdentityStage.required && tierChosen;
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    void finish({required bool dismissed}) {
      if (dismissed) {
        ref.read(accountSetupDismissedProvider.notifier).state = true;
      }
      context.go(AppRoutes.home);
    }

    void refresh() {
      ref
        ..invalidate(dashboardProvider)
        ..invalidate(kycDetailedStatusProvider)
        ..invalidate(currentTierProvider);
    }

    if (context.isExampleTheme) {
      return _ExampleAccountSetup(
        identity: identity,
        tiers: tiers,
        selectedTierId: selectedTierId,
        tierChosen: tierChosen,
        currentTier: currentTier.valueOrNull,
        canContinue: canContinue,
        busy: action.isLoading,
        refreshing: dashboard.isLoading,
        desktop: desktop,
        onRefresh: refresh,
        onRetryTiers: () {
          ref.invalidate(currentTierProvider);
          ref.invalidate(tiersProvider);
        },
        onSelectTier: (tier) {
          final id = tierIdOf(tier);
          if (id == null) return;
          ref.read(platformActionControllerProvider.notifier).selectTier(
                tierId: id,
                tierCycle: tierCycleOf(tier),
              );
        },
        onFinish: finish,
      );
    }

    final body = ListView(
      padding: EdgeInsets.fromLTRB(22, desktop ? 8 : 4, 22, 40),
      children: [
        Text(
          context.tr('Finish setting up your account'),
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -.4,
            color: context.brandDesign.color(
                Theme.of(context).brightness, 'ink',
                fallback: ExampleColors.pearl),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('Two quick steps unlock cards, payments and limits.'),
          style: TextStyle(
            fontSize: 14,
            color: context.brandDesign
                .color(Theme.of(context).brightness, 'ink',
                    fallback: ExampleColors.pearl)
                .withValues(alpha: .62),
          ),
        ),
        const SizedBox(height: 22),
        _SetupStepCard(
          number: 1,
          title: context.tr('Verify your identity'),
          subtitle: switch (identity) {
            IdentityStage.verified => 'Your identity is verified.',
            IdentityStage.inReview =>
              'We are reviewing your details. This usually takes a few minutes.',
            IdentityStage.required =>
              'Confirm who you are with a short form and an ID document.',
          },
          status: switch (identity) {
            IdentityStage.verified => _StepStatus.done,
            IdentityStage.inReview => _StepStatus.pending,
            IdentityStage.required => _StepStatus.todo,
          },
          statusLabel: switch (identity) {
            IdentityStage.verified => 'Verified',
            IdentityStage.inReview => 'In review',
            IdentityStage.required => 'Required',
          },
          action: identity == IdentityStage.verified
              ? null
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (identity == IdentityStage.required)
                      FilledButton.icon(
                        onPressed: () => context.push(AppRoutes.kyc),
                        icon:
                            const Icon(Icons.verified_user_outlined, size: 18),
                        label: Text(context.tr('Start verification')),
                      )
                    else
                      OutlinedButton(
                        onPressed: () => context.push(AppRoutes.kycStatus),
                        child: Text(context.tr('View status')),
                      ),
                    // The provider updates asynchronously after the KYC form;
                    // let the customer pull the latest decision without
                    // leaving this screen.
                    OutlinedButton.icon(
                      onPressed: dashboard.isLoading
                          ? null
                          : () {
                              ref
                                ..invalidate(dashboardProvider)
                                ..invalidate(kycDetailedStatusProvider)
                                ..invalidate(currentTierProvider);
                            },
                      icon: dashboard.isLoading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: AppProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(context.tr('Refresh status')),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _SetupStepCard(
          number: 2,
          title: context.tr('Choose your tier'),
          subtitle: tierChosen
              ? context.tr('You can change tiers later from Settings.')
              : context.tr(
                  'Tiers set your card limits and fees. Pick one to continue.'),
          status: tierChosen ? _StepStatus.done : _StepStatus.todo,
          statusLabel: tierChosen
              ? tierTitleOf(currentTier.valueOrNull!)
              : 'Not selected',
          child: tierChosen
              ? const SizedBox.shrink()
              : tiers.when(
                  data: (items) => items.isEmpty
                      ? Text(
                          context.tr(
                              'No tiers are available right now. You can pick one later from Settings.'),
                          style: TextStyle(
                            fontSize: 13,
                            color: context.brandDesign
                                .color(Theme.of(context).brightness, 'ink',
                                    fallback: ExampleColors.pearl)
                                .withValues(alpha: .62),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var index = 0;
                                index < items.length;
                                index++) ...[
                              _TierChoice(
                                tier: items[index],
                                selected:
                                    tierIdOf(items[index]) == selectedTierId,
                                busy: action.isLoading,
                                onSelect: () {
                                  final id = tierIdOf(items[index]);
                                  if (id == null) return;
                                  ref
                                      .read(platformActionControllerProvider
                                          .notifier)
                                      .selectTier(
                                        tierId: id,
                                        tierCycle: tierCycleOf(items[index]),
                                      );
                                },
                              ),
                              if (index != items.length - 1)
                                const SizedBox(height: 8),
                            ],
                          ],
                        ),
                  error: (error, stackTrace) => ErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(tiersProvider),
                  ),
                  loading: () => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: LoadingState(label: context.tr('Loading tiers')),
                  ),
                ),
        ),
        const SizedBox(height: 26),
        SizedBox(
          height: 50,
          child: FilledButton(
            onPressed: canContinue ? () => finish(dismissed: false) : null,
            child: Text(context.tr('Continue to Home')),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () => finish(dismissed: true),
            child: Text(context.tr("I'll do this later")),
          ),
        ),
      ],
    );

    return PlatformActionListener(
      child: ExampleGlow(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            centerTitle: !desktop,
            title: Text(context.tr('Account setup')),
            automaticallyImplyLeading: false,
            actions: [
              TextButton(
                onPressed: () => finish(dismissed: true),
                child: Text(context.tr('Skip')),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: desktop
                ? Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: body,
                    ),
                  )
                : body,
          ),
        ),
      ),
    );
  }

  static Widget _scope(bool example, Widget child) =>
      ExampleAliveLayer(enabled: example, child: child);
}

class _ExampleAccountSetup extends StatelessWidget {
  const _ExampleAccountSetup({
    required this.identity,
    required this.tiers,
    required this.selectedTierId,
    required this.tierChosen,
    required this.currentTier,
    required this.canContinue,
    required this.busy,
    required this.refreshing,
    required this.desktop,
    required this.onRefresh,
    required this.onRetryTiers,
    required this.onSelectTier,
    required this.onFinish,
  });

  final IdentityStage identity;
  final AsyncValue<List<PlatformResource>> tiers;
  final int? selectedTierId;
  final bool tierChosen;
  final PlatformResource? currentTier;
  final bool canContinue;
  final bool busy;
  final bool refreshing;
  final bool desktop;
  final VoidCallback onRefresh;
  final VoidCallback onRetryTiers;
  final ValueChanged<PlatformResource> onSelectTier;
  final void Function({required bool dismissed}) onFinish;

  /// Same form column the signup flow uses, so the two surfaces of one account
  /// setup measure the same at 1440.
  static const double maxWidth = 680;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final identityDone = identity != IdentityStage.required;
    final done = (identityDone ? 1 : 0) + (tierChosen ? 1 : 0);

    final body = ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        desktop ? AppSpacing.xs : AppSpacing.xxs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      children: [
        _SetupProgress(done: done, total: 2),
        const SizedBox(height: AppSpacing.lg),
        // The one headline of this screen, and the only text that shines.
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ExampleSheen.text(
            intensity: ExampleSheenIntensity.soft,
            child: Text(
              context.tr('Finish setting up your account'),
              style: theme.textTheme.headlineSmall,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.tr('Two quick steps unlock cards, payments and limits.'),
          // Secondary, not tertiary: this line is the promise the whole screen
          // rests on. Night .72 over lightSurface composites to (80,77,96) —
          // 7.77:1 on paper — and pearl .68 keeps its Twilight value.
          style: theme.textTheme.bodyMedium?.copyWith(
            color: ExampleInk.secondary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _SetupStation(
          number: 1,
          title: context.tr('Verify your identity'),
          subtitle: switch (identity) {
            IdentityStage.verified => 'Your identity is verified.',
            IdentityStage.inReview =>
              'We are reviewing your details. This usually takes a few minutes.',
            IdentityStage.required =>
              'Confirm who you are with a short form and an ID document.',
          },
          status: switch (identity) {
            IdentityStage.verified => _StepStatus.done,
            IdentityStage.inReview => _StepStatus.pending,
            IdentityStage.required => _StepStatus.todo,
          },
          statusLabel: switch (identity) {
            IdentityStage.verified => 'Verified',
            IdentityStage.inReview => 'In review',
            IdentityStage.required => 'Required',
          },
          action: identity == IdentityStage.verified
              ? null
              : Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    // Neutral, not filled: a station action must never be
                    // louder than the screen's one decisive CTA in the bar
                    // below it. Same object, same silhouette, unfilled.
                    ExampleGlassButton(
                      label: identity == IdentityStage.required
                          ? context.tr('Start verification')
                          : context.tr('View status'),
                      tone: ExampleGlassButtonTone.neutral,
                      icon: identity == IdentityStage.required
                          ? Icons.verified_user_outlined
                          : Icons.fact_check_outlined,
                      expand: false,
                      height: 46,
                      onPressed: () => context.push(
                        identity == IdentityStage.required
                            ? AppRoutes.kyc
                            : AppRoutes.kycStatus,
                      ),
                    ),
                    // The provider updates asynchronously after the KYC form;
                    // let the customer pull the latest decision without
                    // leaving this screen.
                    ExampleGlassButton(
                      label: context.tr('Refresh status'),
                      tone: ExampleGlassButtonTone.neutral,
                      icon: Icons.refresh_rounded,
                      expand: false,
                      height: 46,
                      loading: refreshing,
                      loadingSemanticsLabel: 'Refreshing your status',
                      onPressed: refreshing ? null : onRefresh,
                    ),
                  ],
                ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _SetupStation(
          number: 2,
          title: context.tr('Choose your tier'),
          subtitle: tierChosen
              ? context.tr('You can change tiers later from Settings.')
              : context.tr(
                  'Tiers set your card limits and fees. Pick one to continue.'),
          status: tierChosen ? _StepStatus.done : _StepStatus.todo,
          statusLabel: tierChosen ? tierTitleOf(currentTier!) : 'Not selected',
          isLast: true,
          child: tierChosen
              ? const SizedBox.shrink()
              : tiers.when(
                  data: (items) => items.isEmpty
                      ? Text(
                          context.tr(
                              'No tiers are available right now. You can pick one later from Settings.'),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ExampleInk.secondary(context),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var index = 0;
                                index < items.length;
                                index++) ...[
                              if (index != 0)
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: ExampleBorders.hairlineSideOf(context)
                                      .color,
                                ),
                              _TierRow(
                                tier: items[index],
                                selected:
                                    tierIdOf(items[index]) == selectedTierId,
                                busy: busy,
                                onSelect: () => onSelectTier(items[index]),
                              ),
                            ],
                          ],
                        ),
                  error: (error, stackTrace) => ErrorState(
                    error: error,
                    onRetry: onRetryTiers,
                  ),
                  loading: () => Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: LoadingState(label: context.tr('Loading tiers')),
                  ),
                ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // What used to be roughly 250 px of empty atmosphere under the CTA.
        // The subtitle already promises "cards, payments and limits"; this is
        // that sentence opened out into the three things it names, so the
        // space earns its keep instead of reading as a broken page.
        const _UnlockList(),
      ],
    );

    return PlatformActionListener(
      child: ExampleGlow(
        // One scope for the screen: the headline, the step rail and the CTA
        // are its only hosts and they share a single ticker.
        child: AccountSetupScreen._scope(
          true,
          Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              centerTitle: !desktop,
              title: Text(context.tr('Account setup')),
              automaticallyImplyLeading: false,
              actions: [
                TextButton(
                  onPressed: () => onFinish(dismissed: true),
                  child: Text(context.tr('Skip')),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
            body: SafeArea(
              top: false,
              child: desktop
                  ? Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: maxWidth),
                        child: body,
                      ),
                    )
                  : body,
            ),
            // Keep account completion and dismissal reachable below the
            // scrolling checklist.
            bottomNavigationBar: _SetupCtaBar(
              enabled: canContinue,
              hint: canContinue
                  ? null
                  : identity == IdentityStage.required
                      ? 'Verify your identity to continue.'
                      : 'Choose a tier to continue.',
              onContinue: () => onFinish(dismissed: false),
              onDismiss: () => onFinish(dismissed: true),
            ),
          ),
        ),
      ),
    );
  }
}

/// The corridor's header: a hairline rail with the finished stations filled.
///
/// Deliberately the same object the signup flow draws at the top of every
/// step, so account setup reads as the last room of one continuous space
/// rather than a screen from a different product.
class _SetupProgress extends StatelessWidget {
  const _SetupProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final light = ExampleTheme.isLight(context);
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    final fill = ExamplePalette.of(context).fill;
    // On paper no single tone clears 3:1 against both the page and the violet
    // fill, so daylight splits the two jobs exactly as the signup rail does:
    // the empty track is the surface step (lightViolet against
    // lightSurfaceHigh measures 4.26:1, the state boundary WCAG 1.4.11 asks
    // for) and the whole strip is enclosed in a night .58 pill — 4.66:1 on
    // paper — so its full extent stays visible. Twilight keeps borderSubtle
    // and no outline.
    final track = ExampleTheme.pick(
      context,
      dark: context.brandDesign.color(
          Theme.of(context).brightness, 'borderSubtle',
          fallback: ExampleColors.borderSubtle),
      light: context.brandDesign.color(
          Theme.of(context).brightness, 'surfaceHigh',
          fallback: ExampleColors.lightSurfaceHigh),
    );
    return Semantics(
      container: true,
      label: context.tr('Account setup progress'),
      value: '$done of $total steps done',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The rail is this screen's progress host: one band across the whole
          // strip, clipped to the pill it is drawn as.
          ExampleSheen(
            borderRadius:
                const BorderRadius.all(Radius.circular(AppRadii.pill)),
            child: Container(
              padding: light ? const EdgeInsets.all(1.5) : EdgeInsets.zero,
              decoration: light
                  ? BoxDecoration(
                      border: Border.all(
                          color: context.brandDesign.color(
                              Theme.of(context).brightness, 'textTertiary',
                              fallback: ExampleColors.lightTextTertiary)),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadii.pill),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  for (var index = 0; index < total; index++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: duration,
                        curve: ExampleMotion.arrive,
                        height: 3,
                        decoration: BoxDecoration(
                          color: index < done ? fill : track,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AppRadii.pill),
                          ),
                        ),
                      ),
                    ),
                    if (index != total - 1)
                      const SizedBox(width: AppSpacing.xxs),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            context.tr('{p0} of {p1} done', {'p0': done, 'p1': total}),
            // Secondary, not tertiary: this is the only place the screen says
            // how much is left, and it has to clear 4.5:1 to count.
            style: theme.textTheme.labelSmall?.copyWith(
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One station on the corridor rail.
///
/// The disc and the spine live in a 28 px gutter *outside* the panel, so the
/// two stations are visibly threaded together. The panel itself is spent by
/// role: a station that still owes work is a surface with an edge and an
/// ambient shadow; a finished one keeps only its disc, its title and its
/// status, and lies flat on the page. Two identical cards would say the two
/// jobs are equally live, which is exactly the flattened hierarchy the review
/// called out.
class _SetupStation extends StatelessWidget {
  const _SetupStation({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusLabel,
    this.action,
    this.child,
    this.isLast = false,
  });

  final int number;
  final String title;
  final String subtitle;
  final _StepStatus status;
  final String statusLabel;
  final Widget? action;
  final Widget? child;
  final bool isLast;

  /// Gutter width. A 28 px disc plus a 12 px gap leaves 295 px of panel at
  /// 375 px, which is wider than the 279 px the old nested layout offered.
  static const double _gutter = 28;
  static const double _gap = AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lifted = status != _StepStatus.done;
    final accent = switch (status) {
      _StepStatus.done => ExamplePalette.of(context).success,
      _StepStatus.pending => ExamplePalette.of(context).warning,
      // The "not started" hue. Lavender is a 1.7:1 whisper on paper, so the
      // resolver deepens it to lightIris (5B49D6, 4.95:1 against the surface
      // step) while Twilight keeps the lavender it renders today.
      _StepStatus.todo => ExampleTheme.pick(
          context,
          dark: context.brandDesign.color(
              Theme.of(context).brightness, 'accent',
              fallback: ExampleColors.lavender),
          light: context.brandDesign.color(
              Theme.of(context).brightness, 'accent',
              fallback: ExampleColors.lightIris),
        ),
    };

    // The station's title, explanation and status read as one sentence.
    // Only these: the actions and tier rows under them stay separate
    // controls, which a merge around the whole station would fold into one
    // node with a single tap.
    final head = MergeSemantics(
        child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: ExampleInk.primary(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  height: 1.4,
                  color: ExampleInk.secondary(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        ExamplePill(label: statusLabel, color: accent),
      ],
    ));

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        head,
        if (action != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Align(alignment: AlignmentDirectional.centerStart, child: action),
        ],
        if (child != null) ...[
          const SizedBox(height: AppSpacing.sm),
          child!,
        ],
      ],
    );

    final panel = lifted
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: ExampleSurface.of(context, 1),
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadii.lg)),
              border: status == _StepStatus.todo
                  ? ExampleBorders.emphasisOf(context)
                  : ExampleBorders.subtleOf(context),
              boxShadow: ExampleShadows.ambientOf(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: content,
            ),
          )
        // Finished: no border, no fill, no shadow. The work is done, so the
        // object goes away and only the record of it stays.
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: content,
          );

    return Stack(
      // A loose Stack would relax the tight width coming from the list and
      // let the row collapse to its intrinsic size; passthrough keeps the
      // station full-bleed.
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        // The spine, drawn behind the row and bridging the gap to the next
        // station so the rail is one unbroken line down the page.
        if (!isLast)
          Positioned(
            top: _gutter + AppSpacing.sm,
            // Runs past this station's own box and into the next disc, so
            // the rail is one line rather than two dashes with a 12 px break
            // sitting exactly where the eye is travelling.
            bottom: -(_gap + AppSpacing.sm),
            left: (_gutter - 1) / 2,
            width: 1,
            child: ColoredBox(
              color: ExampleBorders.hairlineSideOf(context).color,
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              // Lines the disc up with the title's cap height in both the
              // lifted and the flat station.
              padding: EdgeInsets.only(top: lifted ? AppSpacing.sm : 10),
              // The rail above already announces how many steps are done.
              child: ExcludeSemantics(
                child: _StationDisc(
                  number: number,
                  status: status,
                  accent: accent,
                  size: _gutter,
                ),
              ),
            ),
            const SizedBox(width: _gap),
            Expanded(child: panel),
          ],
        ),
      ],
    );
  }
}

class _StationDisc extends StatelessWidget {
  const _StationDisc({
    required this.number,
    required this.status,
    required this.accent,
    required this.size,
  });

  final int number;
  final _StepStatus status;
  final Color accent;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: ExampleMotion.of(context, ExampleMotion.state),
      curve: ExampleMotion.arrive,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ExampleInk.tint(context, accent),
        border: Border.all(color: accent.withValues(alpha: .5)),
      ),
      child: status == _StepStatus.done
          ? Icon(Icons.check_rounded, size: 15, color: accent)
          : Text(
              '$number',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
            ),
    );
  }
}

/// One tier, as a flat row on the station's own surface.
///
/// The old tile was a `ExampleGlassPanel` inside a `ExampleGlassPanel` — the
/// nested card the laws reject outright — and its facts were joined into a
/// sentence that wrapped mid-pair ("Price monthly 0 USD · Max cards 5,000 USD
/// / Month"). Here the panel is gone, the whole 56 pt row is the target
/// instead of a 32 pt "Select" link inside it, and the facts are real
/// label/value pairs that wrap as blocks, never mid-pair.
class _TierRow extends StatelessWidget {
  const _TierRow({
    required this.tier,
    required this.selected,
    required this.busy,
    required this.onSelect,
  });

  final PlatformResource tier;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;

  /// Radio column plus its gap, so the details control lines up with the
  /// tier's name rather than with the radio.
  static const double _textInset = 20 + AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = tierTitleOf(tier);
    final facts = _tierFacts(tier).take(3).toList();
    const radius = BorderRadius.all(Radius.circular(AppRadii.sm));
    final canSelect = !busy && !selected;
    return AnimatedContainer(
      duration: ExampleMotion.of(context, ExampleMotion.state),
      curve: ExampleMotion.arrive,
      decoration: BoxDecoration(
        // Chosen state is a tint plus the checked control, not a second
        // card: violet .13 over the station surface stays under the ink
        // and clear of the page, so the row still reads at 375 px.
        color: selected
            ? ExampleInk.tint(
                context,
                context.brandDesign.color(Theme.of(context).brightness, 'fill',
                    fallback: ExampleColors.violet))
            : Colors.transparent,
        borderRadius: radius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _selectable(context, theme, name, facts, radius, canSelect),
          // Outside the selectable row and its merged semantics: reading
          // what a plan includes must never pick it.
          Padding(
            // The button's own padding is the row's, so the inset alone
            // lands its label under the tier's name.
            padding: const EdgeInsetsDirectional.only(
              start: _textInset,
              bottom: AppSpacing.xxs,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TierDetailsButton(
                tierName: name,
                onPressed: () => showTierDetailsSheet(
                  context,
                  tier: tier,
                  isCurrent: selected,
                  onChoose: canSelect ? onSelect : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _selectable(
    BuildContext context,
    ThemeData theme,
    String name,
    List<_TierFact> facts,
    BorderRadius radius,
    bool canSelect,
  ) {
    return Semantics(
      button: true,
      selected: selected,
      label: selected
          ? context.tr('{p0}, selected', {'p0': name})
          : context.tr('Select {p0}', {'p0': name}),
      onTap: canSelect ? onSelect : null,
      excludeSemantics: true,
      child: ExamplePressable(
        onTap: canSelect ? onSelect : null,
        enabled: canSelect,
        borderRadius: radius,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.xs,
            0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color: selected
                      ? ExamplePalette.of(context).accent
                      : ExampleInk.tertiary(context),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: ExampleInk.primary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: AppSpacing.xs),
                          ExamplePill(
                            label: context.tr('Selected'),
                            color: context.brandDesign.color(
                                Theme.of(context).brightness, 'success',
                                fallback: ExampleColors.success),
                          ),
                        ],
                      ],
                    ),
                    if (facts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _TierFacts(facts: facts),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A tier fact as the pair it always was.
class _TierFact {
  const _TierFact(this.label, this.value);

  final String? label;
  final String value;
}

/// Every label the tier metadata formatter puts in front of a value. Matching
/// on these turns "Price monthly 0 USD" back into ("Price", "monthly 0 USD")
/// without touching the data contract that produced it; anything unmatched is
/// a standalone flag ("Popular", "Best value") and keeps no label. Longest
/// prefixes first so "Daily limit" never swallows "Daily free draws".
const _tierFactLabels = <String>[
  'Daily free draws',
  'Transaction limit',
  'Monthly limit',
  'Daily limit',
  'ATM limit',
  'Cards used',
  'Max cards',
  'Benefit',
  'Feature',
  'Price',
  'Cycle',
  'Level',
  'Card',
  'KYC',
];

List<_TierFact> _tierFacts(PlatformResource tier) {
  final facts = <_TierFact>[];
  for (final detail in tierDetailsOf(tier)) {
    final text = detail.trim();
    if (text.isEmpty) continue;
    final label = _tierFactLabels.firstWhere(
      (candidate) =>
          text.length > candidate.length + 1 && text.startsWith('$candidate '),
      orElse: () => '',
    );
    facts.add(
      label.isEmpty
          ? _TierFact(null, text)
          : _TierFact(label, text.substring(label.length + 1)),
    );
  }
  return facts;
}

/// The pairs, as blocks that wrap whole.
///
/// A `Wrap` of stacked label-over-value blocks is what stops a fact breaking
/// across a line: at 375 px the row has 231 px of text column, which holds two
/// short pairs or one long one, and the block — not the sentence — is the unit
/// that moves.
class _TierFacts extends StatelessWidget {
  const _TierFacts({required this.facts});

  final List<_TierFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      children: [
        for (final fact in facts)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (fact.label != null)
                Text(
                  fact.label!.toUpperCase(),
                  // Tertiary is allowed on a caption whose value sits directly
                  // under it: night .58 composites to (113,111,127) on
                  // lightSurface — 4.66:1, past the 3:1 floor for secondary
                  // text with room to spare.
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    letterSpacing: .8,
                    fontWeight: FontWeight.w700,
                    color: ExampleInk.tertiary(context),
                  ),
                ),
              Text(
                fact.value,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ExampleInk.primary(context),
                  fontWeight: FontWeight.w600,
                  // Counts and amounts line up under each other.
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// What the two steps actually buy, as three hairline rows.
///
/// This is the subtitle's "cards, payments and limits" opened out — the same
/// medicine the tier facts got, applied to the sentence that was the screen's
/// only justification for existing. It also gives the page enough body that
/// the pinned CTA sits at the end of something rather than above a void. A
/// vertical list, deliberately: a 3-up icon grid is an instant reject.
class _UnlockList extends StatelessWidget {
  const _UnlockList();

  static const _rows = <(IconData, String, String)>[
    (Icons.credit_card_outlined, 'Cards', 'Order and manage your cards'),
    (Icons.swap_horiz_rounded, 'Payments', 'Send and receive money'),
    (Icons.trending_up_rounded, 'Limits', 'Higher spending limits'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('WHAT THIS UNLOCKS'),
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 10.5,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: ExampleInk.tertiary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        for (var index = 0; index < _rows.length; index++)
          DecoratedBox(
            decoration: BoxDecoration(
              border: index == _rows.length - 1
                  ? null
                  : ExampleBorders.hairlineOf(context),
            ),
            child: SizedBox(
              height: 48,
              child: Row(
                children: [
                  Icon(
                    _rows[index].$1,
                    size: 18,
                    // Icons clear the 3:1 non-text floor in both themes:
                    // lightIris on lightPaper measures 5.83:1, iris on
                    // appBackground 8.4:1.
                    color: ExamplePalette.of(context).accent,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 78,
                    child: Text(
                      _rows[index].$2,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ExampleInk.primary(context),
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _rows[index].$3,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ExampleInk.secondary(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The pinned action bar.
///
/// A hairline over the atmosphere rather than a second frosted panel: the CTA
/// is itself the glass object, and stacking one inside another is how a bar
/// stops reading as one lit edge and starts reading as two stray rules.
class _SetupCtaBar extends StatelessWidget {
  const _SetupCtaBar({
    required this.enabled,
    required this.hint,
    required this.onContinue,
    required this.onDismiss,
  });

  final bool enabled;
  final String? hint;
  final VoidCallback onContinue;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = hint;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: ExampleBorders.hairlineOf(context, top: true, bottom: false),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: _ExampleAccountSetup.maxWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Why the button is inert, said once, where the thumb is. A
                  // disabled CTA with no explanation is the single most common
                  // dead end in a setup flow.
                  ExampleStateSwitch(
                    child: message == null
                        ? const SizedBox(
                            key: ValueKey('no-hint'),
                            width: double.infinity,
                          )
                        : Padding(
                            key: ValueKey(message),
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.xs),
                            child: Semantics(
                              liveRegion: true,
                              child: Text(
                                message,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: ExampleInk.secondary(context),
                                ),
                              ),
                            ),
                          ),
                  ),
                  // Center above loosens the width and the maxWidth cap leaves
                  // minWidth at 0, so an unbounded child would size to its
                  // label. Re-tighten: infinity resolves to the 680 cap on
                  // desktop and to the viewport on a phone.
                  SizedBox(
                    width: double.infinity,
                    child: ExampleGlassButton(
                      label: context.tr('Continue to Home'),
                      ground: ExampleGlassGround.atmosphere,
                      sheen: true,
                      onPressed: enabled ? onContinue : null,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Center(
                    child: TextButton(
                      onPressed: onDismiss,
                      child: Text(context.tr("I'll do this later")),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _StepStatus { todo, pending, done }

class _SetupStepCard extends StatelessWidget {
  const _SetupStepCard({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusLabel,
    this.action,
    this.child,
  });

  final int number;
  final String title;
  final String subtitle;
  final _StepStatus status;
  final String statusLabel;
  final Widget? action;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      _StepStatus.done => context.brandDesign.color(
          Theme.of(context).brightness, 'success',
          fallback: ExampleColors.success),
      _StepStatus.pending => context.brandDesign.color(
          Theme.of(context).brightness, 'warning',
          fallback: ExampleColors.warning),
      _StepStatus.todo => context.brandDesign.color(
          Theme.of(context).brightness, 'accent',
          fallback: ExampleColors.lavender),
    };
    return ExampleGlassPanel(
      radius: 20,
      borderAlpha: status == _StepStatus.todo ? .3 : .16,
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: .16),
                  border: Border.all(color: color.withValues(alpha: .5)),
                ),
                child: status == _StepStatus.done
                    ? Icon(Icons.check_rounded, size: 16, color: color)
                    : Text(
                        '$number',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.brandDesign.color(
                            Theme.of(context).brightness, 'ink',
                            fallback: ExampleColors.pearl),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.4,
                        color: context.brandDesign
                            .color(Theme.of(context).brightness, 'ink',
                                fallback: ExampleColors.pearl)
                            .withValues(alpha: .62),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              ExamplePill(label: statusLabel, color: color),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: action),
          ],
          if (child != null) ...[
            const SizedBox(height: 14),
            child!,
          ],
        ],
      ),
    );
  }
}

class _TierChoice extends StatelessWidget {
  const _TierChoice({
    required this.tier,
    required this.selected,
    required this.busy,
    required this.onSelect,
  });

  final PlatformResource tier;
  final bool selected;
  final bool busy;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final details = tierDetailsOf(tier);
    return ExampleGlassPanel(
      radius: 14,
      borderAlpha: selected ? .5 : .16,
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      onTap: busy || selected ? null : onSelect,
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked_rounded
                : Icons.radio_button_off_rounded,
            size: 20,
            color: selected
                ? context.brandDesign.color(
                    Theme.of(context).brightness, 'accent',
                    fallback: ExampleColors.iris)
                : context.brandDesign.color(
                    Theme.of(context).brightness, 'textTertiary',
                    fallback: ExampleColors.textTertiary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tierTitleOf(tier),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: context.brandDesign.color(
                        Theme.of(context).brightness, 'ink',
                        fallback: ExampleColors.pearl),
                  ),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    details.take(3).join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: context.brandDesign.color(
                          Theme.of(context).brightness, 'textTertiary',
                          fallback: ExampleColors.textTertiary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (selected)
            ExamplePill(
                label: context.tr('Selected'),
                color: context.brandDesign.color(
                    Theme.of(context).brightness, 'success',
                    fallback: ExampleColors.success))
          else
            TextButton(
              onPressed: busy ? null : onSelect,
              child: Text(context.tr('Select')),
            ),
        ],
      ),
    );
  }
}
