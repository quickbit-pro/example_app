import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:mobile_flutter/brands/example/example.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/branding/app_design.dart';
import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../shared/shared.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/referral_copy.dart';
import '../domain/referral_share.dart';
import '../domain/rewards_models.dart';
import 'referral_actions.dart';
import 'referral_campaign_links.dart';
import 'referral_community_screen.dart';
import 'referral_offer_card.dart';
import 'referral_phone_summary.dart';
import 'referral_level_lifecycle.dart';
import 'referral_member_status.dart';
import 'referral_sections.dart';
import 'referral_workspace.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class RewardsScreen extends ConsumerStatefulWidget {
  const RewardsScreen({this.initialTab, super.key});

  /// The desktop workspace tab from the URL (`?tab=friends`), so a reload
  /// lands on the same section. Ignored on the phone. Null is Overview.
  final String? initialTab;

  @override
  ConsumerState<RewardsScreen> createState() => _RewardsScreenState();
}

class _RewardsScreenState extends ConsumerState<RewardsScreen> {
  final _voucherController = TextEditingController();
  bool _processing = false;
  bool _acceptingTerms = false;
  late ReferralWorkspaceTab _tab =
      ReferralWorkspaceTab.fromWire(widget.initialTab);

  @override
  void didUpdateWidget(covariant RewardsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The router rebuilds this screen with the new query when the tab
    // changes (and on a browser reload), so the URL is the source of truth.
    if (oldWidget.initialTab != widget.initialTab) {
      _tab = ReferralWorkspaceTab.fromWire(widget.initialTab);
    }
  }

  @override
  void dispose() {
    _voucherController.dispose();
    super.dispose();
  }

  /// Selects a workspace tab: into the URL when a router is present, so the
  /// address bar and history follow, and into local state either way.
  void _selectTab(ReferralWorkspaceTab tab) {
    setState(() => _tab = tab);
    GoRouter.maybeOf(context)?.go(
      tab == ReferralWorkspaceTab.overview
          ? AppRoutes.rewards
          : AppRoutes.rewardsTab(tab.wire),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(rewardsSnapshotProvider);
    final isExample = context.isExampleTheme;
    final desktop = isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    return Scaffold(
      appBar: AppBar(
        title: isExample && !desktop
            ? const ExampleLockup(height: 24)
            : Text(context.tr('Rewards')),
        actions: desktop
            ? null
            : [
                IconButton(
                  tooltip: context.tr('Settings'),
                  onPressed: () => context.go('/profile'),
                  icon: const Icon(Icons.settings_outlined),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
      ),
      body: ExampleAliveLayer(
        enabled: isExample,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(rewardsSnapshotProvider);
            await ref.read(rewardsSnapshotProvider.future);
          },
          child: snapshot.when(
            data: (data) {
              // Parsed once per build: the summary map is the wire shape,
              // the model is what every section below reads.
              final summary = data.summary;
              final programmeOn =
                  data.referralsEnabled && (summary?.enabled ?? false);
              final referrals = programmeOn
                  ? _ReferralOverview(
                      summary: summary!,
                      friends: data.referralFriends,
                      rewards: data.referralRewards,
                      acceptingTerms: _acceptingTerms,
                      onAcceptTerms: _acceptTerms,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Incoming attribution can be pending before this
                        // member is eligible to invite anyone themselves.
                        if (data.referralsEnabled)
                          const ReferralMemberStatusCard(),
                        _UnavailableCard(
                          icon: Icons.people_outline,
                          title: context.tr('Referrals are not enabled'),
                          message: context.tr(
                              'This section appears automatically when your company enables its referral programme.'),
                        ),
                      ],
                    );
              // The one big thing on the page, mounted above the columns
              // rather than inside one of them: at 1440 a hero that lived in
              // the left column would be a half-width panel with a half-width
              // panel beside it, which is a layout, not a lead. Example only —
              // a white-label tenant keeps the exact tree it renders today.
              final hero = isExample && programmeOn
                  ? _RewardsHero(summary: summary!)
                  : null;
              // Voucher entry and the assigned list belong to voucher
              // delivery. A wallet-credit programme pays the balance itself,
              // so there is nothing to claim and the column is not mounted;
              // the "not available" card only stands in when there is no
              // referral programme either, so the page is never empty.
              final vouchers = data.showsVoucherSections
                  ? Column(
                      key: const Key('rewards_voucher_sections'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _VoucherCodeCard(
                          controller: _voucherController,
                          processing: _processing,
                          onValidate: _validateVoucher,
                          onTerms: () => _openTerms(data.config.termsUrl),
                        ),
                        const SizedBox(height: 16),
                        _AssignedVouchers(
                          vouchers: data.assignedVouchers,
                          processing: _processing,
                          onRedeem: _redeemAssignment,
                          onRedeemAll: _redeemAll,
                        ),
                      ],
                    )
                  : !data.vouchersEnabled && !programmeOn
                      ? _UnavailableCard(
                          icon: Icons.confirmation_number_outlined,
                          title: context.tr('Vouchers are not available'),
                          message: context.tr(
                              'Voucher entry and assigned rewards remain hidden until the white-label company enables them.'),
                        )
                      : null;
              // The desktop shell gets the partner workspace (blueprint
              // p14, p17): the masthead, then a sub-navigation beside a
              // content column that holds everything the member API
              // exposes. The hero, the funnel and the voucher sections are
              // handed in so the workspace mounts the same objects the
              // phone does rather than second copies of them.
              if (desktop && programmeOn) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(40, 28, 40, 110),
                  children: [
                    const _RewardsMasthead(),
                    const SizedBox(height: AppSpacing.xl),
                    ReferralCommunityEntry(programId: summary!.programId),
                    ReferralWorkspace(
                      snapshot: data,
                      summary: summary,
                      tab: _tab,
                      onTabChanged: _selectTab,
                      hero: hero!,
                      funnel: _ReferralFunnel(referrals: summary.referrals),
                      vouchers: vouchers,
                      acceptingTerms: _acceptingTerms,
                      onAcceptTerms: _acceptTerms,
                    ),
                  ],
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final desktop =
                      context.isExampleTheme && constraints.maxWidth >= 820;
                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      desktop ? 40 : 20,
                      desktop ? 28 : AppSpacing.xs,
                      desktop ? 40 : 20,
                      110,
                    ),
                    children: [
                      if (context.isExampleTheme &&
                          MediaQuery.sizeOf(context).width <
                              ExampleBreakpoints.desktop) ...[
                        Text(context.tr('Rewards'), style: _pageTitle(context)),
                        const SizedBox(height: 12),
                      ],
                      // The masthead takes over at exactly the width where
                      // the 22 px title above stops rendering, so no width
                      // is left without a page voice — not only the widths
                      // wide enough for two columns.
                      if (context.isExampleTheme &&
                          MediaQuery.sizeOf(context).width >=
                              ExampleBreakpoints.desktop) ...[
                        const _RewardsMasthead(),
                        const SizedBox(height: AppSpacing.xl),
                      ],
                      if (hero != null) ...[
                        hero,
                        ReferralCommunityEntry(programId: summary!.programId),
                        SizedBox(height: desktop ? AppSpacing.lg : 18),
                      ],
                      if (desktop && vouchers != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: referrals),
                            const SizedBox(width: 22),
                            Expanded(child: vouchers),
                          ],
                        )
                      else ...[
                        referrals,
                        if (vouchers != null) ...[
                          const SizedBox(height: 16),
                          vouchers,
                        ],
                      ],
                    ],
                  );
                },
              );
            },
            error: (error, stackTrace) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (isExample)
                  ExampleErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(rewardsSnapshotProvider),
                  )
                else
                  ErrorState(
                    error: error,
                    onRetry: () => ref.invalidate(rewardsSnapshotProvider),
                  ),
              ],
            ),
            loading: () => isExample
                ? const _RewardsLoading()
                : ListView(
                    children: [
                      LoadingState(label: context.tr('Loading rewards'))
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Accepts the programme terms, then reloads: the summary only carries the
  /// code and link once the current version is on record.
  Future<void> _acceptTerms(int termsVersion) async {
    setState(() => _acceptingTerms = true);
    try {
      await ref.read(mobilePlatformApiProvider).acceptReferralTerms(
            termsVersion,
          );
      if (!mounted) return;
      _message(context.tr('Terms accepted. You can share your invite now.'));
      ref.invalidate(rewardsSnapshotProvider);
      await ref.read(rewardsSnapshotProvider.future);
    } catch (error) {
      if (mounted) _message(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _acceptingTerms = false);
    }
  }

  Future<void> _validateVoucher() async {
    final code = _voucherController.text.trim();
    if (code.isEmpty) {
      _message('Enter a voucher code first.');
      return;
    }

    setState(() => _processing = true);
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).validateVoucher(code);
      if (!mounted) return;
      final valid = _boolean(result.metadata, 'Valid', 'valid');
      if (!valid) {
        _message('This code is invalid or unavailable.');
        return;
      }
      final amount = _text(result.metadata, 'Amount', 'amount') ?? '—';
      final currency = _text(result.metadata, 'Currency', 'currency') ?? '';
      final shouldRedeem = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.tr('Voucher is valid')),
          content: Text(
            context.tr(
                '{p0} {p1} is available. Eligibility and company checks run again when you redeem.',
                {'p0': amount, 'p1': currency}),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr('Not now')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('Redeem')),
            ),
          ],
        ),
      );
      if (shouldRedeem == true) {
        await _redeemCode(code);
      }
    } catch (error) {
      if (mounted) _message(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _redeemCode(String code) async {
    final result =
        await ref.read(mobilePlatformApiProvider).redeemVoucher(code);
    if (!mounted) return;
    _voucherController.clear();
    _message(result.message);
    ref.invalidate(rewardsSnapshotProvider);
  }

  Future<void> _redeemAssignment(String assignmentId) async {
    setState(() => _processing = true);
    try {
      final result = await ref
          .read(mobilePlatformApiProvider)
          .redeemAssignedVoucher(assignmentId);
      if (mounted) _message(result.message);
      ref.invalidate(rewardsSnapshotProvider);
    } catch (error) {
      if (mounted) _message(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _redeemAll() async {
    setState(() => _processing = true);
    try {
      final result =
          await ref.read(mobilePlatformApiProvider).redeemAllAssignedVouchers();
      if (mounted) _message(result.message);
      ref.invalidate(rewardsSnapshotProvider);
    } catch (error) {
      if (mounted) _message(friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openTerms(String? url) async {
    final target = Uri.tryParse(url?.trim() ?? '');
    if (target == null || !target.hasScheme) {
      _message(
          'Reward terms are published by your company. Contact support for a copy.');
      return;
    }
    final opened =
        await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) _message('Could not open the terms document.');
  }
}

/// The page title, in the rhythm the rest of the app uses on a tab screen.
TextStyle _pageTitle(BuildContext context) => TextStyle(
      fontSize: 22 * context.brandDesign.typographyScale,
      fontWeight: FontWeight.w700,
      letterSpacing: -.3,
      color: ExampleInk.primary(context),
    );

/// The desktop masthead.
///
/// Below 600 this page states its name at 22 px and the shell's top bar
/// carries it from there — which left the 1440 layout with two columns of
/// panels and no page voice at all, the exact "no line that stops and
/// breathes" the competitive read scored us down on. The name is set from the
/// existing ramp in two steps: 44 px once there is room for two columns, 64 px
/// once there is a genuine desktop page around them, against a field that
/// heads its equivalents at 36 (RedotPay) to 80 and above (ether.fi Cash,
/// Revolut). The line under it is descriptive, not a claim, and stays quiet at
/// title size — one big thing per screen, and this is it. Not a sheen host:
/// the tier hairline already owns this screen's single sweep.
class _RewardsMasthead extends StatelessWidget {
  const _RewardsMasthead();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Rewards'),
          style: (width >= 1200
                  ? AppTypography.displayXl(theme.textTheme)
                  : theme.textTheme.displayLarge)
              ?.copyWith(color: ExampleInk.primary(context)),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.tr('Referrals and vouchers, in one place.'),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w400,
            height: 1.45,
            // Measured on the page ground it actually sits on: 7.98:1 over
            // Twilight paper, 7.49:1 over daylight paper. A secondary line
            // clears the 4.5:1 body floor with room in both themes.
            color: ExampleInk.secondary(context),
          ),
        ),
      ],
    );
  }
}

/// The recessed well an input or a machine string sits in, inside a panel.
/// Twilight sinks below the panel; daylight steps up from paper into the
/// lavender-tinted surface, because a light page has no darker floor.
Color _wellColor(BuildContext context) => ExampleTheme.isLight(context)
    ? ExamplePalette.of(context).surfaceSubtle
    : ExamplePalette.of(context).paper.withValues(alpha: .55);

/// Shape-matched placeholders for the two panels the screen resolves into.
/// The blocks carry the alive layer's soft sheen through the scope above.
class _RewardsLoading extends StatelessWidget {
  const _RewardsLoading();

  @override
  Widget build(BuildContext context) => Semantics(
        label: context.tr('Loading rewards'),
        child: ExcludeSemantics(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, 110),
            children: const [
              // A loading block is ONE sheen host, not three: the band
              // crosses the whole placeholder column, masked to the blocks so
              // it never lands in the gaps between them.
              ExampleSheen.text(
                intensity: ExampleSheenIntensity.soft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ExampleSkeleton.line(width: 108, height: 20, sheen: false),
                    SizedBox(height: AppSpacing.sm),
                    ExampleSkeleton.card(height: 244, sheen: false),
                    SizedBox(height: AppSpacing.md),
                    ExampleSkeleton.card(height: 176, sheen: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// The payoff, at the size a payoff is worth.
///
/// Rewards used to open on a 36 px figure wedged into the top-left corner of a
/// panel it shared with a 4 px progress bar, an invite code, a copy field and
/// a button — five jobs in one box, so the screen led with nothing. Home
/// answers "what do I have" with a 44 px number and an object under it; this
/// screen answers "what have I earned" and had never been given the same
/// courtesy.
///
/// So the hero is now one object with one subject: the unclaimed balance, the
/// level it was earned at, and the distance to the next one. Everything
/// operational — the code, the invitation, the vouchers — moved below it and
/// stepped down a weight.
///
/// It is the only element on this screen with a material of its own. Frosted
/// (the shell wraps every Example route in a `ExampleGlow`, so there is a real
/// atmosphere to blur), a violet seat under it, and the screen's single
/// [ExampleSweepBorder] as its edge — the same three-part treatment Home gives
/// its balance, which is the point: the two heroes should read as the same
/// kind of object. Nothing else on Rewards gets a sweep, a glow or a blur.
class _RewardsHero extends StatelessWidget {
  const _RewardsHero({required this.summary});

  final ReferralSummary summary;

  /// Corner of the hero and of its sweep, which must agree or the rim stops
  /// hugging the corners. [AppRadii.xl] rather than the `lg` every other panel
  /// on the page takes: radius is spent by role here, so the object that leads
  /// the screen is also the only one with that corner.
  static const double _radius = AppRadii.xl;

  /// Inner width at which the figure and the ladder stop stacking. Below it a
  /// 3:2 split leaves the rail too short to read as a journey; above it the
  /// stacked form leaves the panel half empty.
  static const double _wideAt = 640;

  @override
  Widget build(BuildContext context) {
    // A voucher programme has a balance waiting to be claimed; a
    // wallet-credit programme pays as it goes, so the figure is everything
    // the programme has produced that is not lost.
    final totals = summary.rewards;
    final figure = summary.usesVouchers ? totals.ready : totals.earned;
    final currency = totals.currency;
    // The ladder is only a journey when there is more than one visible
    // rung; a single-level programme shows the figure alone. With two
    // conditions on the next level the rail shows the one the customer is
    // furthest from; the line under it accounts for both.
    final focus = summary.showsLevels ? summary.progress.focusCondition : null;
    final levelName = summary.showsLevels ? summary.currentLevel?.name : null;
    final qualified = summary.referrals.qualified;

    final panel = ExampleGlassPanel(
      radius: _radius,
      material: ExampleGlassMaterial.frosted,
      // Twilight: `ExampleSweepBorder` insets its stroke by width / 2 in a
      // `Positioned.fill` over this panel, so it lands on the same outermost
      // 1 px ring the panel's own `Border.all` would. Zero here leaves one
      // stroke on that ring instead of two.
      //
      // Daylight ignores this knob: `ExampleGlassPanel` reads `borderAlpha`
      // on its dark branch only and resolves the paper edge through
      // `ExampleBorders.sideOf` instead, so the hairline stays — lavender at
      // .30, not an opaque rule — and the sweep darkens along it. That is
      // what `ExampleSweepBorder.floor` is written for: an arc brightening an
      // edge that is already there. Silencing the paper hairline too would
      // need an opt-out on `ExampleGlassPanel`, which is not this file.
      borderAlpha: 0,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final figureBlock = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _HeroFigure(amount: figure, currency: currency),
              const SizedBox(height: 6),
              Text(
                _heroCaption(context, qualified),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5 * context.brandDesign.typographyScale,
                  height: 1.35,
                  // Secondary, not tertiary: this line qualifies the number
                  // above it, so it is body copy and takes the body floor in
                  // both themes (7.98:1 Twilight, 7.49:1 daylight).
                  color: ExampleInk.secondary(context),
                ),
              ),
            ],
          );
          final ladder = focus == null
              ? null
              : _TierLadder(progress: summary.progress, condition: focus);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      summary.usesVouchers
                          ? context.tr('REWARDS AVAILABLE')
                          : context.tr('REWARDS EARNED'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ExampleTextStyles.label(context),
                    ),
                  ),
                  if (levelName != null) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: ExamplePill(
                        label: levelName,
                        color: ExampleColors.iris,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xxs),
              if (ladder == null)
                figureBlock
              // Wide, the two halves sit side by side and the ladder's rail
              // grows with the panel. Stacked, the hero at 1440 was a 1,360 px
              // plane with a 44 px number in one corner and 1,100 px of
              // nothing beside it — the desktop breakpoint has to be a
              // decision, not the phone layout with more air around it. The
              // rail getting longer as the page gets wider is also the right
              // reading: it is a distance.
              else if (constraints.maxWidth >= _wideAt)
                Row(
                  // Bottoms line up, so the caption under the figure and the
                  // "2 more to go" under the rail sit on one line across the
                  // panel instead of drifting apart.
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(flex: 3, child: figureBlock),
                    const SizedBox(width: AppSpacing.xl),
                    Expanded(flex: 2, child: ladder),
                  ],
                )
              else ...[
                figureBlock,
                const SizedBox(height: AppSpacing.md),
                const _PanelRule(),
                const SizedBox(height: AppSpacing.md),
                ladder,
              ],
            ],
          );
        },
      ),
    );
    return DecoratedBox(
      // The seat. On Twilight a violet bloom under the panel, so the figure
      // looks lit from within; in daylight `glowOf` returns the ambient plus
      // a 45 percent bloom, which is the difference between a panel resting
      // on paper and one printed on it.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: ExampleShadows.glowOf(
          context,
          ExampleColors.violet,
          alpha: .18,
          blur: 34,
          spread: -14,
          offset: const Offset(0, 12),
        ),
      ),
      child: ExampleSweepBorder(radius: _radius, child: panel),
    );
  }

  /// What the figure is made of, stated from the data rather than asserted.
  /// A programme with nothing earned yet says what to do instead of printing
  /// "0 referrals", which is a scolding, not a caption.
  static String _heroCaption(BuildContext context, int qualified) {
    if (qualified <= 0) return context.tr('Invite a friend to start earning.');
    return qualified == 1
        ? context.tr('Earned from 1 qualified referral.')
        : context
            .tr('Earned from {p0} qualified referrals.', {'p0': qualified});
  }
}

/// The reward figure at [ExampleAmountSize.hero] — the same 44 px volume as
/// Home's balance, because it is the same kind of statement.
///
/// [ExampleAmount] rather than a hand-set `Text`: it routes through
/// `Money.formatAmount`, so grouping, decimals, the symbol relief, the smaller
/// cents and Private Mode all stay decided in one place. The scale-down box is
/// Home's: a number steps down a size rather than truncating, because an
/// ellipsised balance is a wrong balance, and `scaleDown` only ever shrinks so
/// the common case renders at the full 44 px.
class _HeroFigure extends StatelessWidget {
  const _HeroFigure({required this.amount, required this.currency});

  final double? amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    const size = ExampleAmountSize.hero;
    return SizedBox(
      height: size.fontSize * size.height,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: AlignmentDirectional.centerStart,
        child: ExampleAmount(
          amount: amount,
          currency: currency,
          size: size,
          // The code is explicit above a figure a customer is about to claim:
          // "1.00" without "USD" is a number, not money.
          code: ExampleAmountCode.always,
        ),
      ),
    );
  }
}

/// A hairline that divides two subjects inside one panel — the hero's figure
/// from its tier ladder, the funnel's three stages from the rate derived off
/// them.
///
/// A rule rather than a second container in both places: those pairs belong to
/// the panel they are in, and boxing either half would make a card inside a
/// card. Depth is spent on one line, not on another surface.
class _PanelRule extends StatelessWidget {
  const _PanelRule();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 1,
        child: ColoredBox(color: ExampleBorders.hairlineSideOf(context).color),
      );
}

/// Tier progression as an object with a length.
///
/// The old control was a 4 px hairline with "3 of 5" set beside it in 12 px —
/// which states the fact and shows nothing. A programme whose whole promise is
/// "keep going" has to make the going visible, so the rail is now 10 px tall,
/// milestone-notched on the *unwalked* half (five referrals is five countable
/// steps, not 60 percent of an abstract quantity), ended where the customer
/// currently stands — the fill's own edge against the track, which is the
/// hardest edge the rail has — and closed by the only number that is actually
/// actionable: how many are left.
///
/// It is also this screen's one moment. The fill travels out from zero to its
/// value once, after the route transition finishes — a bar that is simply
/// *there* on arrival states a position; a bar that arrives at it states a
/// journey. Nothing moves layout: the rail's box is a fixed 10 px in a fixed
/// column, and only the paint inside it changes. Under reduced motion it is
/// at its final value on frame one.
class _TierLadder extends StatelessWidget {
  const _TierLadder({required this.progress, required this.condition});

  final ReferralProgress progress;

  /// The condition the rail measures: the one with the smaller completion
  /// fraction when the next level sets two.
  final ReferralLevelCondition condition;

  /// Tall enough to be an object rather than a rule, short enough to stay a
  /// measure rather than a container.
  static const double _height = 10;

  /// Above this, milestones stop being countable and the rail goes continuous
  /// — a points total of 2,500 is a distance, not a set of steps.
  static const int _maxSteps = 12;

  @override
  Widget build(BuildContext context) {
    final value = condition.fraction;
    // The focus is the condition furthest from met, so meeting it means the
    // whole level is.
    final complete = condition.met;
    final caption = context.tr('{p0} of {p1}', {
      'p0': _conditionFigure(condition, condition.current),
      'p1': _conditionFigure(condition, condition.target),
    });
    final light = ExampleTheme.isLight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('NEXT LEVEL'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ExampleTextStyles.label(context),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              caption,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w600,
                color: ExampleInk.primary(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Semantics(
          label: context.tr('Progress to the next level'),
          value: caption,
          child: ExcludeSemantics(
            child: _ArrivalFill(
              value: value,
              builder: (context, filled) => ExampleSheen(
                // A progress bar is a sanctioned sheen host, and it is the
                // only one on this screen: the invite CTA and the voucher
                // Redeem both opt out, so the page has one band, not three.
                borderRadius: const BorderRadius.all(
                  Radius.circular(_height / 2),
                ),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: const Size.fromHeight(_height),
                    painter: _TierRailPainter(
                      progress: filled,
                      // Money is a distance, not a set of steps.
                      steps: condition.isMoney ? 0 : _steps(condition.target),
                      track: light
                          ? ExamplePalette.of(context).surfaceHigh
                          : ExamplePalette.of(context)
                              .ink
                              .withValues(alpha: .10),
                      // The milestones ahead. Tertiary ink at a notch alpha:
                      // a mark on the road, not a label — but still a mark,
                      // so it owes the 3:1 a countable step owes as non-text
                      // UI, against the track it is cut into.
                      //
                      // The bare track is not the ground that sets these,
                      // though. This rail is the screen's one sheen host and
                      // the band paints over notch and track alike. It is not
                      // permanently there: with motion on it crosses for the
                      // 1.2 to 1.6 s of a sweep, once per the scope's 7 s
                      // cadence, and under reduced motion it rests on the
                      // rail for good at half the alpha. Either way the
                      // tightest moment is a live band's centre line — the
                      // one place it reaches its full peak — and that is the
                      // ground these are set against. .48 / .42
                      // cleared the bare track (3.25:1 on paper, 3.11:1 at
                      // worst across the four Twilight surface levels the
                      // hero's glass can rest over) and fell under the floor
                      // beneath that centre line — 2.73:1 on paper, 2.56:1 in
                      // Twilight. These clear it there: 3.33:1 on paper, and
                      // no worse than 3.23:1 on any of the four.
                      tick: ExampleInk.tertiary(context)
                          .withValues(alpha: light ? .56 : .54),
                      // "You are here" is this edge, and no cap is drawn
                      // over it. A cap at the tip would have the fill on one
                      // side and the track on the other, and no flat colour
                      // clears 3:1 against both. Twilight settles that on the
                      // bare rail: the fill (iris, relative luminance .336)
                      // is the brighter ground and the track (.013 at surface
                      // level 0 rising to .039 at level 3) the darker, so a
                      // cap would need luminance 1.11 to escape upward, or
                      // -0.02 to escape downward on the most forgiving of the
                      // four — both off the ends of the scale. The best any
                      // colour manages on its weaker side there is 2.08:1
                      // (level 3) to 2.47:1 (level 0).
                      //
                      // Daylight swaps the two roles, and that is the case
                      // the band decides rather than the geometry. Here the
                      // fill (lightIris, .118) is the darker ground and the
                      // track (lightSurfaceHigh, .784) the brighter, so there
                      // is room below the fill that Twilight does not have:
                      // on the bare rail black clears both, 3.37:1 on the
                      // fill and 16.67:1 on the track, while nothing above
                      // the track ever could (white is 1.26:1 on it). Under a
                      // live band's centre line that one escape closes —
                      // black falls to 2.99:1 on the lit fill, 0.01 under the
                      // floor, and nothing is darker than black.
                      //
                      // The cap that used to be here took neither escape. It
                      // cleared the fill (5.75:1 Twilight, 5.29:1 daylight)
                      // and vanished into the track — 1.06:1 to 1.33:1 across
                      // the four Twilight surfaces, 1.07:1 on paper — so what
                      // it actually drew was 2 px erased off the fill's tip.
                      // The edge alone clears the floor on every ground under
                      // a live band's centre line: 3.77:1 on paper, 3.33:1 on
                      // the worst Twilight surface.
                      fill: ExampleInk.accent(context, ExampleColors.iris),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          complete
              ? context.tr('Next level unlocked')
              : _remainingCaption(context, progress),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w600,
            color: ExampleInk.accent(
              context,
              complete ? ExampleColors.success : ExampleColors.iris,
            ),
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  /// Countable milestones, or zero for a continuous rail.
  static int _steps(double target) {
    if (target != target.roundToDouble()) return 0;
    final count = target.round();
    return count >= 2 && count <= _maxSteps ? count : 0;
  }
}

/// Holds a fill at zero until the screen has actually arrived, then runs it
/// out to [value] once.
///
/// The arming sequence is Home's, for the same reason: nothing may run during
/// the 420 ms route transition, and `ModalRoute.of` is not reliable in the
/// first frames, so a short timer arms a listener on the route animation and
/// the fill starts when that animation completes. Reduced motion never
/// schedules the timer at all — `ExampleMotion.of` collapses the duration to
/// zero and the bar is correct on frame one.
class _ArrivalFill extends StatefulWidget {
  const _ArrivalFill({required this.value, required this.builder});

  /// Final fill, 0..1.
  final double value;

  final Widget Function(BuildContext context, double filled) builder;

  @override
  State<_ArrivalFill> createState() => _ArrivalFillState();
}

class _ArrivalFillState extends State<_ArrivalFill> {
  /// Long enough after mount that the route animation exists to listen to.
  static const Duration _armDelay = Duration(milliseconds: 240);

  bool _armed = false;
  Timer? _armTimer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_armed) return;
    if (ExampleMotion.reduced(context)) {
      _armed = true;
      return;
    }
    _armTimer ??= Timer(_armDelay, _armFromRoute);
  }

  void _armFromRoute() {
    if (!mounted || _armed) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      setState(() => _armed = true);
      return;
    }
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _detachRoute();
    if (!mounted || _armed) return;
    setState(() => _armed = true);
  }

  void _detachRoute() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
  }

  @override
  void dispose() {
    _armTimer?.cancel();
    _detachRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: _armed ? widget.value : 0),
        // Composed from the motion tokens rather than invented: the length of
        // a route plus a state change. Long enough to read as travel across
        // a 300 px rail, short enough that it is over before the eye has
        // finished with the figure above it.
        duration: ExampleMotion.of(
          context,
          ExampleMotion.route + ExampleMotion.state,
        ),
        curve: ExampleMotion.arrive,
        builder: (context, filled, _) => widget.builder(context, filled),
      );
}

/// Track, milestones and fill, in one pass.
///
/// One [Paint] is allocated per paint and recoloured between draws; no Path is
/// built here at all. The painter only runs while the arrival fill is moving
/// and is stopped by [RepaintBoundary] from touching the panel around it.
class _TierRailPainter extends CustomPainter {
  const _TierRailPainter({
    required this.progress,
    required this.steps,
    required this.track,
    required this.tick,
    required this.fill,
  });

  /// 0..1.
  final double progress;

  /// Milestone count, or 0 for a continuous rail.
  final int steps;

  final Color track;
  final Color tick;
  final Color fill;

  /// Width of a milestone notch.
  static const double _mark = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    final rail = RRect.fromRectAndRadius(Offset.zero & size, radius);
    final paint = Paint()..color = track;
    canvas.drawRRect(rail, paint);

    canvas.save();
    canvas.clipRRect(rail);
    // Milestones first, so the walked part of the rail covers the ones
    // already passed: what is behind you is a distance, what is ahead of you
    // is a count.
    if (steps > 1) {
      paint.color = tick;
      for (var i = 1; i < steps; i++) {
        final x = size.width * i / steps;
        canvas.drawRect(
          Rect.fromLTWH(x - _mark / 2, 0, _mark, size.height),
          paint,
        );
      }
    }
    if (progress > 0) {
      // A started level always shows at least a round cap, so "1 of 20" is a
      // position rather than an empty bar.
      final travelled = size.width * progress;
      final width = travelled < size.height ? size.height : travelled;
      paint.color = fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, width, size.height),
          radius,
        ),
        paint,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TierRailPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.steps != steps ||
      oldDelegate.track != track ||
      oldDelegate.tick != tick ||
      oldDelegate.fill != fill;
}

/// Invited, Successful, In progress — drawn as the funnel they are.
///
/// These were three rows in a settings group, which is the shape the app uses
/// for "a label and a value you might change". They are not that: they are one
/// cohort narrowing twice, and the only interesting thing about them is the
/// *ratio*, which three right-aligned numerals hide completely. Each stage now
/// carries a magnitude bar scaled against the widest stage, so 8 → 3 → 2 is a
/// shape before it is a set of numbers, and the conversion rate — derived from
/// the same two figures, never a fourth number from nowhere — closes it.
///
/// Deliberately the lightest block on the page: a level-1 surface with no edge
/// in Twilight and no glow in either theme. The hero above it owns the depth;
/// this is a report.
class _ReferralFunnel extends StatelessWidget {
  const _ReferralFunnel({required this.referrals});

  final ReferralCounts referrals;

  @override
  Widget build(BuildContext context) {
    final invited = referrals.invited.toDouble();
    final successful = referrals.qualified.toDouble();
    final inProgress = referrals.inProgress.toDouble();
    // The widest stage sets the scale. Guarded at 1 so an empty programme
    // renders three empty tracks instead of dividing by zero.
    var top = invited;
    if (successful > top) top = successful;
    if (inProgress > top) top = inProgress;
    if (top <= 0) top = 1;
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final light = ExampleTheme.isLight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Referral funnel')),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            // Twilight separates this block by tone alone — it is the one
            // panel on the page without an edge, which is what makes the
            // bordered ones above and below it read as heavier.
            border: light ? ExampleBorders.subtleOf(context) : null,
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FunnelStage(
                  label: context.tr('Invited'),
                  value: '${referrals.invited}',
                  factor: invited / top,
                  // The cohort, washed back: the widest bar must not also be
                  // the loudest. But it is the scale the other two are drawn
                  // against, so it is also the one bar that may not fade out
                  // — at a third of the accent it measures 1.62:1 on the
                  // paper well and 1.79:1 on the night one, which is a
                  // rumour, not a datum. These are the quietest alphas that
                  // still clear the 3:1 a chart mark owes as non-text UI:
                  // 3.36:1 on the paper well, 3.38:1 on the night one. They
                  // differ because iris gains presence on a dark ground far
                  // faster than lightIris does on a pale one, and both stay
                  // plainly under the two stages beside them — Successful at
                  // 4.50 / 10.53 and In progress at 5.23 / 7.11.
                  color: accent.withValues(alpha: light ? .76 : .62),
                ),
                const SizedBox(height: 14),
                _FunnelStage(
                  label: context.tr('Qualified'),
                  value: '${referrals.qualified}',
                  factor: successful / top,
                  color: ExampleInk.accent(context, ExampleColors.success),
                ),
                const SizedBox(height: 14),
                _FunnelStage(
                  label: context.tr('In progress'),
                  value: '${referrals.inProgress}',
                  factor: inProgress / top,
                  color: accent,
                ),
                if (invited > 0) ...[
                  const SizedBox(height: AppSpacing.md),
                  const _PanelRule(),
                  const SizedBox(height: AppSpacing.sm),
                  MergeSemantics(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.tr('Converted'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize:
                                  13 * context.brandDesign.typographyScale,
                              color: ExampleInk.secondary(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          '${(successful / invited * 100).round()}%',
                          style: TextStyle(
                            fontSize: 17 * context.brandDesign.typographyScale,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.2,
                            color: ExampleInk.primary(context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// One stage of the funnel: the name, the figure at a size worth reading, and
/// the magnitude under both.
class _FunnelStage extends StatelessWidget {
  const _FunnelStage({
    required this.label,
    required this.value,
    required this.factor,
    required this.color,
  });

  final String label;
  final String value;

  /// Share of the widest stage, 0..1.
  final double factor;

  final Color color;

  /// Height of the magnitude bar.
  static const double _bar = 6;

  /// A non-zero stage never disappears: below this the bar would read as
  /// "none" when the number says otherwise.
  static const double _floor = .05;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(_bar / 2));
    final width = factor <= 0 ? 0.0 : factor.clamp(_floor, 1.0).toDouble();
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13 * context.brandDesign.typographyScale,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 20 * context.brandDesign.typographyScale,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                  letterSpacing: -.2,
                  color: ExampleInk.primary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: _bar,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _wellColor(context),
                borderRadius: radius,
              ),
              child: width <= 0
                  ? null
                  : FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: width,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: radius,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

String _compactNumber(num value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toString();

/// A figure on a level condition: a count, or money in the condition's
/// currency for the top-up amount.
String _conditionFigure(ReferralLevelCondition condition, double value) =>
    condition.isMoney
        ? formatReferralAmount(condition.currency, value)
        : _compactNumber(value);

/// What is left to the next level. One condition reads as it always has —
/// "2 more to go"; two read as one line with both distances, met ones
/// omitted — "3 more referrals · $600 more in top-ups".
String _remainingCaption(BuildContext context, ReferralProgress progress) {
  final conditions = progress.nextConditions;
  if (conditions.length == 1) {
    final only = conditions.single;
    return context.tr('{p0} more to go', {
      'p0': _conditionFigure(only, only.remaining),
    });
  }
  final parts = <String>[
    for (final condition in conditions)
      if (!condition.met)
        condition.isMoney
            ? context.tr('{p0} more in top-ups', {
                'p0': formatReferralAmount(
                    condition.currency, condition.remaining),
              })
            : condition.remaining == 1
                ? context.tr('1 more referral')
                : context.tr('{p0} more referrals', {
                    'p0': _compactNumber(condition.remaining),
                  }),
  ];
  return parts.join(' · ');
}

class _ReferralOverview extends ConsumerStatefulWidget {
  const _ReferralOverview({
    required this.summary,
    required this.friends,
    required this.rewards,
    required this.acceptingTerms,
    required this.onAcceptTerms,
  });

  final ReferralSummary summary;
  final List<ReferralFriend> friends;
  final List<ReferralReward> rewards;
  final bool acceptingTerms;
  final ValueChanged<int> onAcceptTerms;

  @override
  ConsumerState<_ReferralOverview> createState() => _ReferralOverviewState();
}

class _ReferralOverviewState extends ConsumerState<_ReferralOverview> {
  bool _sendingInvitation = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final summary = widget.summary;
    final code = summary.referralCode;
    // The platform's `referralPath` is only a link once the tenant has a
    // sign-up URL configured; otherwise it is the dashboard's relative route,
    // so the app points friends at its own sign-up screen instead.
    final link = code == null
        ? null
        : resolveReferralShareLink(
            referralCode: code,
            referralPath: summary.referralPath,
            currentWebUri: kIsWeb ? Uri.base : null,
            webAppUrl: ref.watch(appConfigProvider).branding.webAppUrl,
          );
    final progress = summary.progress;
    final focus = summary.showsLevels ? progress.focusCondition : null;
    final levelName = summary.showsLevels ? summary.currentLevel?.name : null;
    final gated = summary.mustAcceptTerms;
    // The common tail of both trees: what the programme pays (first, in
    // both), the terms gate where the invite would be, then the account of
    // who was invited and what it earned.
    final offer = ReferralOfferHeadline(summary: summary);
    final termsGate = gated && !summary.residenceRestricted
        ? ReferralTermsGate(
            terms: summary.terms!,
            busy: widget.acceptingTerms,
            onAccept: widget.onAcceptTerms,
          )
        : null;
    final residenceNotice = summary.residenceRestricted
        ? ExampleEmptyState(
            compact: true,
            icon: Icons.public_off_rounded,
            title: context.tr('Referral participation unavailable'),
            body: context.tr(summary.residenceRestrictionMessage),
          )
        : null;
    final levels = ReferralLevelsCard(summary: summary);
    final friends = ReferralFriendsList(friends: widget.friends);
    final ledger = ReferralRewardsLedger(
      summary: summary,
      rewards: widget.rewards,
    );

    if (isExample) {
      // Blueprint p18 and p20: one offer a customer could explain to a
      // friend, the four figures that answer "how is it going", the level
      // ladder when there is one, the three most recent friends and rewards
      // with a way into each full list, and the funnel last. The figure, the
      // level pill and the tier rail live in `_RewardsHero`, mounted above
      // this column, so nothing here repeats them.
      //
      // The card's foot is the share action — or the email fallback when the
      // summary carries no code — and the terms gate stands right under the
      // card, where that action would be, until the current version is
      // accepted.
      final funnel = _ReferralFunnel(referrals: summary.referrals);
      final paying = effectiveReferralOffer(summary);
      Widget? actions;
      if (termsGate != null || !summary.canInvite) {
        actions = null;
      } else if (code == null) {
        // The email invitation endpoint issues its own link; it does not need
        // a referral code in this summary. Keep inviting usable in this state.
        actions = ExampleGlassButton(
          label: context.tr('Invite friends'),
          icon: Icons.mail_outline_rounded,
          sheen: false,
          loading: _sendingInvitation,
          onPressed: _sendingInvitation
              ? null
              : () => _showEmailInvitationDialog(context),
        );
      } else {
        actions = _exampleShareActions(context, code: code, link: link);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (residenceNotice != null) ...[
            residenceNotice,
            const SizedBox(height: AppSpacing.md),
          ],
          ReferralOfferCard(summary: summary, actions: actions),
          if (termsGate != null) ...[
            const SizedBox(height: AppSpacing.md),
            termsGate,
          ],
          const SizedBox(height: AppSpacing.md),
          ReferralSummaryTiles(
            summary: summary,
            onFriends: () => _openFriends(context),
            onEarnings: (filter) => _openEarnings(context, filter),
          ),
          // The month's figures and an eight-week sparkline under the
          // tiles; mounts nothing when the backend serves no analytics.
          ReferralMonthLine(
            onTap: () => _openEarnings(context, ReferralEarningsFilter.all),
          ),
          if (summary.showsLevels) ...[
            const SizedBox(height: AppSpacing.md),
            levels,
          ],
          const SizedBox(height: AppSpacing.md),
          const ReferralMemberStatusCard(),
          const SizedBox(height: 12),
          ReferralLevelLifecycleCard(currency: summary.rewards.currency),
          const SizedBox(height: AppSpacing.md),
          ReferralFriendsPreview(
            friends: widget.friends,
            offer: paying,
            onSeeAll: () => _openFriends(context),
          ),
          const SizedBox(height: AppSpacing.md),
          ReferralRecentRewards(
            rewards: widget.rewards,
            summary: summary,
            onSeeAll: () => _openEarnings(context, ReferralEarningsFilter.all),
          ),
          const SizedBox(height: AppSpacing.md),
          funnel,
        ],
      );
    }

    final earned =
        summary.usesVouchers ? summary.rewards.ready : summary.rewards.earned;
    final inviteCard = NeoSurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      gradient: context.financeTheme.heroGradient,
      borderColor: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: theme.colorScheme.onPrimary),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.onPrimary.withValues(alpha: .24),
                  child: Icon(
                    Icons.card_giftcard_rounded,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    context.tr('Invite friends'),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: theme.colorScheme.onPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              levelName == null
                  ? context.tr(
                      'Share your invite and track every reward in one place.')
                  : context.tr('{p0} level', {'p0': levelName}),
              style: TextStyle(
                  color: theme.colorScheme.onPrimary.withValues(alpha: .70)),
            ),
            if (focus != null) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: focus.fraction),
              const SizedBox(height: 6),
              Text(
                context.tr('{p0} of {p1} toward the next level', {
                  'p0': _conditionFigure(focus, focus.current),
                  'p1': _conditionFigure(focus, focus.target),
                }),
                style: TextStyle(
                    color: theme.colorScheme.onPrimary.withValues(alpha: .70)),
              ),
              // Two conditions: the bar shows the further one; this line
              // accounts for both.
              if (progress.nextConditions.length > 1 && !focus.met) ...[
                const SizedBox(height: 4),
                Text(
                  _remainingCaption(context, progress),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
            if (code != null && summary.canInvite) ...[
              const SizedBox(height: 18),
              Text(
                context.tr('Your referral code'),
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: .70),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      code,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                  IconButton.filled(
                    tooltip: context.tr('Copy invite'),
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: link ?? code),
                      );
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(context.tr('Invite copied'))),
                        );
                      }
                    },
                    icon: const Icon(Icons.copy_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: context.tr('Share invite'),
                    onPressed: () => _shareReferral(
                      context,
                      code: code,
                      link: link,
                    ),
                    icon: const Icon(Icons.share_rounded),
                  ),
                ],
              ),
              if (link != null) ...[
                const SizedBox(height: 6),
                Text(
                  link,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 6),
              Text(
                context.tr(
                    'The invitation link prefills this code during signup.'),
                style: TextStyle(
                    color: theme.colorScheme.onPrimary.withValues(alpha: .70)),
              ),
            ],
            if (!gated && summary.canInvite) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _sendingInvitation
                    ? null
                    : () => _showEmailInvitationDialog(context),
                icon: _sendingInvitation
                    ? const SizedBox.square(
                        dimension: 18,
                        child: AppProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.mail_outline_rounded),
                label: Text(context.tr('Email invite')),
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.onPrimary,
                  foregroundColor: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) => GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth < 520 ? 2 : 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: constraints.maxWidth < 520 ? 2.15 : 1.45,
                children: [
                  _Metric(
                    label: context.tr('Invited'),
                    value: '${summary.referrals.invited}',
                  ),
                  _Metric(
                    label: context.tr('Qualified'),
                    value: '${summary.referrals.qualified}',
                  ),
                  _Metric(
                    label: context.tr('In progress'),
                    value: '${summary.referrals.inProgress}',
                  ),
                  _Metric(
                    label: summary.usesVouchers
                        ? context.tr('Available')
                        : context.tr('Earned'),
                    value: Money.formatAmount(summary.rewards.currency, earned),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        offer,
        if (summary.offer != null) const SizedBox(height: 16),
        if (residenceNotice != null) ...[
          residenceNotice,
          const SizedBox(height: 16),
        ],
        inviteCard,
        if (termsGate != null) ...[
          const SizedBox(height: 16),
          termsGate,
        ],
        if (summary.showsLevels) ...[
          const SizedBox(height: 16),
          levels,
        ],
        const SizedBox(height: 16),
        const ReferralMemberStatusCard(),
        const SizedBox(height: 12),
        ReferralLevelLifecycleCard(currency: summary.rewards.currency),
        const SizedBox(height: 16),
        friends,
        const SizedBox(height: 16),
        ledger,
      ],
    );
  }

  /// The share block at the foot of the offer card: the code and the link in
  /// a well (so the customer can see it is a real address, not a bare code),
  /// then Share and Copy link side by side and the email invitation under
  /// them. Matte glass throughout — this screen spends its single sweep on
  /// the tier rail, and a CTA that shimmers under a hero that does not is
  /// the wrong object leading the page.
  Widget _exampleShareActions(
    BuildContext context, {
    required String code,
    String? link,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(context.tr('INVITE CODE'), style: ExampleTextStyles.label(context)),
        const SizedBox(height: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: _wellColor(context),
            borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
            border: ExampleBorders.subtleOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 10,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  code,
                  maxLines: 1,
                  style: ExampleTextStyles.mono(
                    context,
                    size: 15,
                    weight: FontWeight.w500,
                  ),
                ),
                if (link != null) ...[
                  const SizedBox(height: 2),
                  // The address the copy and share actions hand out.
                  Text(
                    link,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ExampleTextStyles.mono(
                      context,
                      size: 12,
                      weight: FontWeight.w400,
                    ).copyWith(color: ExampleInk.secondary(context)),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          context.tr('The invitation link prefills this code at signup.'),
          style: TextStyle(
            fontSize: 12 * context.brandDesign.typographyScale,
            height: 1.4,
            color: ExampleInk.secondary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: ExampleGlassButton(
                key: const Key('referral_share'),
                label: context.tr('Share'),
                icon: Icons.ios_share_rounded,
                sheen: false,
                onPressed: () =>
                    _shareReferral(context, code: code, link: link),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: ExampleGlassButton(
                key: const Key('referral_copy_link'),
                label: context.tr('Copy link'),
                icon: Icons.copy_rounded,
                tone: ExampleGlassButtonTone.neutral,
                sheen: false,
                onPressed: () =>
                    copyReferralInvite(context, code: code, link: link),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // `loading` keeps the silhouette, width and position while the
        // platform emails the invitation, and the screen reader hears "in
        // progress" instead of a button that simply stopped responding.
        ExampleGlassButton(
          label: context.tr('Invite by email'),
          icon: Icons.mail_outline_rounded,
          tone: ExampleGlassButtonTone.neutral,
          sheen: false,
          loading: _sendingInvitation,
          loadingSemanticsLabel: 'Sending invitation',
          onPressed: _sendingInvitation
              ? null
              : () => _showEmailInvitationDialog(context),
        ),
        // The member's campaign links, as a secondary list, when any is
        // active; nothing otherwise, so the phone is unchanged without them.
        const ReferralCampaignLinksPhoneList(),
      ],
    );
  }

  void _openFriends(BuildContext context) =>
      GoRouter.maybeOf(context)?.go(AppRoutes.rewardsFriends);

  void _openEarnings(BuildContext context, ReferralEarningsFilter filter) =>
      GoRouter.maybeOf(context)
          ?.go(AppRoutes.rewardsEarningsFiltered(filter.wire));

  Future<void> _shareReferral(
    BuildContext context, {
    required String code,
    String? link,
  }) =>
      shareReferralInvite(
        context,
        appName: ref.read(appConfigProvider).branding.appName,
        summary: widget.summary,
        code: code,
        link: link,
        origin: shareOriginOf(context),
      );

  Future<void> _showEmailInvitationDialog(BuildContext context) async {
    final submission = await showReferralInvitationDialog(context);
    if (submission == null || !mounted) return;
    await _sendInvitation(submission);
  }

  Future<void> _sendInvitation(ReferralInvitationRequest request) async {
    setState(() => _sendingInvitation = true);
    try {
      await ref.read(mobilePlatformApiProvider).sendReferralInvitation(
            email: request.email,
            name: request.name,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.tr('Invitation sent to {p0}', {'p0': request.email}),
          ),
        ),
      );
      ref.invalidate(rewardsSnapshotProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _sendingInvitation = false);
    }
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: Theme.of(context).colorScheme.onPrimary),
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onPrimary
                      .withValues(alpha: .70)),
            ),
          ],
        ),
      );
}

class _VoucherCodeCard extends StatelessWidget {
  const _VoucherCodeCard({
    required this.controller,
    required this.processing,
    required this.onValidate,
    this.onTerms,
  });
  final TextEditingController controller;
  final bool processing;
  final VoidCallback onValidate;
  final VoidCallback? onTerms;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      final accent = ExampleInk.accent(context, ExampleColors.iris);
      return ExampleGlassPanel(
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('VOUCHER CODE'),
                style: ExampleTextStyles.label(context)),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 46),
                    child: TextField(
                      controller: controller,
                      textCapitalization: TextCapitalization.characters,
                      enabled: !processing,
                      style: ExampleTextStyles.mono(
                        context,
                        size: 14,
                        weight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: context.tr('Enter code'),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 13,
                        ),
                        fillColor: _wellColor(context),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AppRadii.sm),
                          ),
                          borderSide: ExampleBorders.subtleSideOf(context),
                        ),
                      ),
                      onSubmitted: (_) {
                        if (!processing) onValidate();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                // The claim: the one action on this screen that changes a
                // balance, so it is the one that gets the glass material.
                // It hugs its label rather than expanding — it shares a line
                // with the code field, and a Row gives its last child an
                // unbounded width. Radius and height are matched to that
                // field so the pair reads as one control, not as a button
                // parked beside an input.
                ExampleGlassButton(
                  label: context.tr('Redeem'),
                  expand: false,
                  height: 46,
                  radius: AppRadii.sm,
                  // Matte, like the invite CTA above it. This screen used to
                  // run two bands — this button and the tier bar — while the
                  // referral panel's own CTA ran none, so the same material
                  // shimmered in one panel and sat still in the next. The
                  // band now belongs to the tier rail alone, which is the
                  // object the screen is actually about; the controls are
                  // consistent with each other instead.
                  sheen: false,
                  loading: processing,
                  loadingSemanticsLabel: 'Redeeming voucher',
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 12,
                  ),
                  onPressed: processing ? null : onValidate,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ExamplePressable(
              onTap: onTerms,
              semanticsLabel: context.tr('Terms and conditions'),
              borderRadius:
                  const BorderRadius.all(Radius.circular(AppRadii.xs)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('Terms & conditions'),
                        style: TextStyle(
                          fontSize: 12.5 * context.brandDesign.typographyScale,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return NeoSurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Enter voucher code'),
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            context.tr(
                'We’ll validate the code and then use the redemption flow returned by the provider.'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            enabled: !processing,
            decoration: InputDecoration(
              labelText: context.tr('Voucher code'),
              prefixIcon: const Icon(Icons.confirmation_number_outlined),
            ),
            onSubmitted: (_) {
              if (!processing) onValidate();
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: processing ? null : onValidate,
              icon: processing
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.confirmation_number_outlined),
              label: Text(context.tr('Apply code')),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
              context.tr('Codes are not case-sensitive'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssignedVouchers extends StatelessWidget {
  const _AssignedVouchers({
    required this.vouchers,
    required this.processing,
    required this.onRedeem,
    required this.onRedeemAll,
  });
  final List<Map<String, dynamic>> vouchers;
  final bool processing;
  final ValueChanged<String> onRedeem;
  final VoidCallback onRedeemAll;

  @override
  Widget build(BuildContext context) {
    final redeemable = vouchers.where((voucher) {
      final status = _text(voucher, 'Status', 'status')?.toLowerCase();
      return status == 'assigned' || status == 'available';
    }).toList();
    if (context.isExampleTheme) {
      if (vouchers.isEmpty) {
        return ExampleEmptyState(
          compact: true,
          icon: Icons.local_activity_outlined,
          title: context.tr('No vouchers assigned yet'),
          body: context.tr(
              'Rewards your company assigns to you appear here, ready to redeem.'),
        );
      }
      return ExampleListGroup(
        title: context.tr('Assigned vouchers'),
        action: redeemable.isEmpty ? null : context.tr('Redeem all'),
        onAction: processing || redeemable.isEmpty ? null : onRedeemAll,
        children: [
          for (final voucher in vouchers)
            _ExampleVoucherRow(
              voucher: voucher,
              redeemable: redeemable.contains(voucher),
              processing: processing,
              onRedeem: onRedeem,
            ),
        ],
      );
    }
    return NeoSurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(context.tr('Assigned vouchers'),
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              if (redeemable.length > 1)
                TextButton(
                  onPressed: processing ? null : onRedeemAll,
                  child: Text(context.tr('Redeem all')),
                ),
            ],
          ),
          if (vouchers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(context.tr('No assigned vouchers yet.')),
            )
          else ...[
            const SizedBox(height: AppSpacing.xs),
            NeoGroupedCard(
              children: [
                for (final voucher in vouchers)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: .13),
                      child: Icon(
                        Icons.local_activity_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(_text(voucher, 'Name', 'name') ?? 'Voucher'),
                    subtitle: Text(
                      '${_field(voucher, 'Amount')} ${_field(voucher, 'Currency')} • ${_voucherTypeLabel(voucher)}',
                    ),
                    trailing: redeemable.contains(voucher)
                        ? FilledButton.tonal(
                            onPressed: processing
                                ? null
                                : () {
                                    final id = _text(
                                      voucher,
                                      'AssignmentId',
                                      'assignmentId',
                                    );
                                    if (id != null) onRedeem(id);
                                  },
                            child: Text(context.tr('Redeem')),
                          )
                        : StatusChip(
                            label: _field(voucher, 'Status'),
                            tone: FinanceStatusTone.neutral,
                          ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One assigned voucher as a row in the group: the reward on the left, the
/// amount and kind under it, and on the right either the redeem affordance
/// or the state it is already in. The whole row is the target, so the
/// action clears 44 pt without a button nested inside a list.
class _ExampleVoucherRow extends StatelessWidget {
  const _ExampleVoucherRow({
    required this.voucher,
    required this.redeemable,
    required this.processing,
    required this.onRedeem,
  });

  final Map<String, dynamic> voucher;
  final bool redeemable;
  final bool processing;
  final ValueChanged<String> onRedeem;

  @override
  Widget build(BuildContext context) {
    final name = _text(voucher, 'Name', 'name') ?? 'Voucher';
    final status = _field(voucher, 'Status');
    final id = _text(voucher, 'AssignmentId', 'assignmentId');
    final enabled = redeemable && !processing && id != null;
    return ExampleRow(
      title: name,
      subtitle: '${_field(voucher, 'Amount')} ${_field(voucher, 'Currency')}'
          ' · ${_voucherTypeLabel(voucher)}',
      enabled: !processing,
      leading: const ExampleIconTile(
        icon: Icons.local_activity_outlined,
        color: ExampleColors.iris,
      ),
      onTap: enabled ? () => onRedeem(id) : null,
      semanticsLabel:
          enabled ? context.tr('Redeem {p0}', {'p0': name}) : '$name, $status',
      trailing: redeemable
          ? Text(
              context.tr('Redeem'),
              style: TextStyle(
                fontSize: 12.5 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w700,
                color: ExampleInk.accent(context, ExampleColors.iris),
              ),
            )
          : ExamplePill(label: status, color: _statusColor(status)),
    );
  }
}

/// Brand token for a voucher state. Redeemed is the only outcome worth
/// colouring; everything else stays in the accent so a list of vouchers is
/// not a traffic light.
Color _statusColor(String status) {
  final value = status.toLowerCase();
  if (value.contains('redeem') || value.contains('used')) {
    return ExampleColors.success;
  }
  if (value.contains('expire') || value.contains('cancel')) {
    return ExampleColors.warning;
  }
  return ExampleColors.iris;
}

class _UnavailableCard extends StatelessWidget {
  const _UnavailableCard({
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleEmptyState(
        compact: true,
        icon: icon,
        title: title,
        body: message,
      );
    }
    return _material(context);
  }

  Widget _material(BuildContext context) => NeoSurfaceCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(message),
                ],
              ),
            ),
          ],
        ),
      );
}

String _voucherTypeLabel(Map<String, dynamic> voucher) {
  final raw = _text(voucher, 'RedemptionType', 'redemptionType') ??
      _text(voucher, 'Type', 'type') ??
      '';
  final normalized = raw.toLowerCase();
  if (normalized.contains('credit') || normalized.contains('account')) {
    return 'Account credit';
  }
  if (normalized.contains('code')) {
    return 'Redemption code';
  }
  return _field(voucher, 'Status');
}

String? _text(Map<String, dynamic> source, String first, String second) {
  final value = source[first] ?? source[second];
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _boolean(Map<String, dynamic> source, String first, String second) {
  final value = source[first] ?? source[second];
  return value == true || value?.toString().toLowerCase() == 'true';
}

String _field(Map<String, dynamic> source, String name) =>
    (source[name] ?? source[_lowerFirst(name)] ?? '0').toString();

String _lowerFirst(String value) =>
    value.isEmpty ? value : '${value[0].toLowerCase()}${value.substring(1)}';
