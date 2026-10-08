import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';
import 'tier_details_sheet.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

/// Tiers: what you are on, what the next plan costs, and what it buys.
///
/// This is the most persuasive surface in the product, so it is the one
/// platform screen composed as an argument rather than as a list. Each tier is
/// a panel that answers three questions in the order a buyer asks them —
/// *what is it called*, *what does it cost*, *what do I get* — and the money
/// is set once, big, in [ExampleAmount]'s tabular figures, instead of being
/// buried mid-sentence in a benefits line the way the service returns it.
/// Below the price the numbers stack as a spec table (label left, value right,
/// tabular) so two plans can be read down a column; below that the inclusions
/// are hairline rows, so a tier reads as a contract rather than as tags.
///
/// **Weight is spent once.** Exactly one panel is the focus: the flagged
/// recommendation if the service marks one and it is not already yours,
/// otherwise the plan you are on. That panel — and only it — takes
/// `ExampleBorders.emphasis`, the level-3 surface, the lit inner hairline, and
/// the filled [ExampleGlassButton]. Every other selectable tier gets the same
/// object unfilled ([ExampleGlassButtonTone.neutral]), which is a real second
/// choice rather than a second shout. The plan you are already on has no
/// button at all: it holds the CTA's slot with a line of quiet ink, so the
/// buttons still line up across a row at desktop width.
///
/// **One moment.** The focus panel's inner top hairline takes a single sheen
/// pass once the route has settled, then keeps the scope's cadence. When no
/// tier is current and none is flagged there is nothing to point at, so the
/// moment moves to the headline instead — never to both. Nothing else on the
/// screen animates beyond the 120 ms press.
class TiersScreen extends ConsumerWidget {
  const TiersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Tiers'))),
        body: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(currentTierProvider);
            ref.invalidate(tiersProvider);
            await ref.read(tiersProvider.future);
          },
          child:
              context.isExampleTheme ? const _ExampleBody() : const _LegacyBody(),
        ),
      ),
    );
  }
}

/// Widest the plan ladder ever runs. Past this the columns stop growing and
/// the block centres, so 1440 gets a composition rather than three panels
/// stretched across a monitor.
const double _tiersMaxContentWidth = 1160;

/// Column gutter at the wide breakpoints, per the layout law.
const double _tiersGutter = AppSpacing.xl;

class _ExampleBody extends ConsumerWidget {
  const _ExampleBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiers = ref.watch(tiersProvider);
    final currentTier = ref.watch(currentTierProvider);
    final current = currentTier.valueOrNull;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        // A tier panel wants about 320 to hold "Transaction limit" beside its
        // value without the label wrapping to three lines; two columns are
        // only offered once both of them clear that with air to spare.
        final columns = width >= 1080 ? 3 : (width >= 760 ? 2 : 1);
        final padding = columns == 1
            ? platformExamplePadding
            : const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.xxl,
              );

        return ListView(
          padding: padding,
          // A short plan list must still accept the overscroll that drives
          // RefreshIndicator; without this, pull-to-refresh was dead on any
          // account whose provider returned one or two tiers.
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _tiersMaxContentWidth),
                child: tiers.when(
                  data: (items) => _plans(
                    context,
                    ref,
                    items: items,
                    current: current,
                    currentIsLoading: currentTier.isLoading,
                    columns: columns,
                  ),
                  error: (error, stackTrace) => _frame(
                    headline: _TierHeadline(
                      tier: current,
                      loading: currentTier.isLoading,
                      // The list failed, so the headline is the only thing
                      // left to greet with.
                      sheen: true,
                    ),
                    body: PlatformErrorState(
                      key: const ValueKey('tiers-error'),
                      error: error,
                      onRetry: () => ref.invalidate(tiersProvider),
                    ),
                  ),
                  loading: () => _frame(
                    headline: const _TierHeadlineSkeleton(),
                    body: _TiersSkeleton(columns: columns),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Headline, section title, then whatever occupies the plan slot. One
  /// composition for every state, so the page does not re-lay-out under the
  /// reader when the data lands.
  Widget _frame({required Widget headline, required Widget body}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          platformSectionGap,
          const ExampleSectionTitle(title: 'Available tiers'),
          const SizedBox(height: AppSpacing.sm),
          body,
        ],
      );

  Widget _plans(
    BuildContext context,
    WidgetRef ref, {
    required List<PlatformResource> items,
    required PlatformResource? current,
    required bool currentIsLoading,
    required int columns,
  }) {
    final currentId = tierIdOf(current);
    final focus = _focusIndex(items, currentId);
    return _frame(
      headline: _TierHeadline(
        tier: current,
        loading: currentIsLoading,
        // The screen spends one moment. It belongs on the focus panel when
        // there is one to point at, and on the headline only when there is
        // not.
        sheen: focus == null,
      ),
      body: items.isEmpty
          ? ExampleEmptyState(
              key: const ValueKey('tiers-empty'),
              compact: true,
              icon: Icons.workspace_premium_outlined,
              title: context.tr('No plans to compare yet'),
              body: context.tr(
                  'Your account is still being provisioned, so the tiers have not been published. Check again in a moment.'),
              actionLabel: context.tr('Check again'),
              onAction: () => ref.invalidate(tiersProvider),
            )
          : _TierGrid(
              key: const ValueKey('tiers-data'),
              items: items,
              currentId: currentId,
              focusIndex: focus,
              columns: columns,
            ),
    );
  }

  /// The one panel that carries extra weight: the flagged recommendation when
  /// it is not already yours, otherwise the plan you are on. Null means the
  /// service gave us nothing to point at, and no panel is dressed as a hero.
  static int? _focusIndex(List<PlatformResource> items, int? currentId) {
    for (var i = 0; i < items.length; i++) {
      final isCurrent = currentId != null && tierIdOf(items[i]) == currentId;
      if (!isCurrent && _tierHighlightLabel(items[i]) != null) return i;
    }
    if (currentId == null) return null;
    for (var i = 0; i < items.length; i++) {
      if (tierIdOf(items[i]) == currentId) return i;
    }
    return null;
  }
}

/// The plan ladder. One column on a phone; two or three at the wide
/// breakpoints, where an `IntrinsicHeight` row keeps every panel in a run the
/// same height so the prices sit on one line and the buttons on another —
/// which is the whole reason a comparison table is readable.
class _TierGrid extends StatelessWidget {
  const _TierGrid({
    required this.items,
    required this.currentId,
    required this.focusIndex,
    required this.columns,
    super.key,
  });

  final List<PlatformResource> items;
  final int? currentId;
  final int? focusIndex;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final lanes = columns > items.length ? items.length : columns;
    if (lanes <= 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.sm),
            _panel(i, fillHeight: false),
          ],
        ],
      );
    }

    final runs = <Widget>[];
    for (var start = 0; start < items.length; start += lanes) {
      final end = start + lanes > items.length ? items.length : start + lanes;
      runs.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var lane = 0; lane < lanes; lane++) ...[
                if (lane > 0) const SizedBox(width: _tiersGutter),
                Expanded(
                  child: start + lane < end
                      ? _panel(start + lane, fillHeight: true)
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < runs.length; i++) ...[
          if (i > 0) const SizedBox(height: _tiersGutter),
          runs[i],
        ],
      ],
    );
  }

  Widget _panel(int index, {required bool fillHeight}) {
    final tier = items[index];
    return _TierPanel(
      tier: tier,
      isCurrent: currentId != null && tierIdOf(tier) == currentId,
      isFocus: index == focusIndex,
      fillHeight: fillHeight,
    );
  }
}

/// The plan, said once: an eyebrow, the tier name at headline size, and a
/// single pill. No card — the statement is the header, so nothing below it is
/// nested inside anything.
class _TierHeadline extends StatelessWidget {
  const _TierHeadline({
    required this.tier,
    this.loading = false,
    this.sheen = false,
  });

  final PlatformResource? tier;

  /// The current-tier call has not answered yet. The name holds its line with
  /// a placeholder rather than the page re-flowing when it lands.
  final bool loading;

  /// This headline is carrying the screen's one moment.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    if (loading) return const _TierHeadlineSkeleton();
    final resource = tier;
    final selected = resource != null && tierIdOf(resource) != null;
    final name = selected ? tierTitleOf(resource) : 'No tier selected';
    // The lede orients; it never repeats the plan's own description, which
    // the panel for that plan is already carrying a few hundred pixels below.
    final lede = selected
        ? 'Your plan is active. Compare it with the tiers below.'
        : 'Choose a tier to unlock card ordering and higher limits.';

    final Widget title = Text(
      name,
      style: TextStyle(
        fontSize: 24,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: ExampleInk.primary(context),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('CURRENT TIER'),
                      style: ExampleTextStyles.label(context)),
                  const SizedBox(height: AppSpacing.xxs),
                  if (sheen)
                    ExampleSheen.text(
                      intensity: ExampleSheenIntensity.soft,
                      child: title,
                    )
                  else
                    title,
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xxs),
              child: selected
                  ? ExamplePill(
                      label: context.tr('Active'),
                      color: ExampleColors.success,
                      dot: true,
                    )
                  : ExamplePill(
                      label: context.tr('Not selected'),
                      color: ExampleColors.iris,
                    ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          lede,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: ExampleInk.secondary(context),
          ),
        ),
      ],
    );
  }
}

class _TierHeadlineSkeleton extends StatelessWidget {
  const _TierHeadlineSkeleton();

  @override
  Widget build(BuildContext context) => ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExampleSkeleton.line(
              width: 84,
              height: 10,
              sheen: false,
              semanticsLabel: context.tr('Loading current tier'),
            ),
            const SizedBox(height: AppSpacing.xs),
            const ExampleSkeleton.line(
              width: 168,
              height: 22,
              sheen: false,
              semanticsLabel: '',
            ),
            const SizedBox(height: AppSpacing.sm),
            const ExampleSkeleton.line(
              widthFactor: .72,
              sheen: false,
              semanticsLabel: '',
            ),
          ],
        ),
      );
}

/// Shape-matched wait for the ladder: panels, at the panel's own width, in
/// the breakpoint's own column count. One sheen host for the whole block.
class _TiersSkeleton extends StatelessWidget {
  const _TiersSkeleton({required this.columns});

  final int columns;

  @override
  Widget build(BuildContext context) {
    final block = ExampleSkeleton.card(
      height: 264,
      sheen: false,
      semanticsLabel: context.tr('Loading tiers'),
    );
    return ExampleSheen.text(
      key: const ValueKey('tiers-loading'),
      intensity: ExampleSheenIntensity.soft,
      child: columns <= 1
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                block,
                const SizedBox(height: AppSpacing.sm),
                block,
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var lane = 0; lane < columns; lane++) ...[
                  if (lane > 0) const SizedBox(width: _tiersGutter),
                  Expanded(child: block),
                ],
              ],
            ),
    );
  }
}

/// One tier as a panel: name, price, spec table, inclusions, one action.
///
/// The focus panel takes the emphasis edge and the level-3 surface; every
/// other tier rests on matte level-1 depth. Never a card inside a card — the
/// spec rows and the inclusions are hairline-separated rows on the panel's
/// own surface.
class _TierPanel extends ConsumerStatefulWidget {
  const _TierPanel({
    required this.tier,
    required this.isCurrent,
    required this.isFocus,
    required this.fillHeight,
  });

  final PlatformResource tier;
  final bool isCurrent;

  /// This panel carries the screen's weight and its one moment.
  final bool isFocus;

  /// Stretch to the tallest panel in the run, so the prices and the buttons
  /// line up across a desktop row.
  final bool fillHeight;

  @override
  ConsumerState<_TierPanel> createState() => _TierPanelState();
}

class _TierPanelState extends ConsumerState<_TierPanel> {
  /// True between this panel's own tap and the shared controller going idle.
  /// Without it the spinner landed on every tier at once, which told the user
  /// nothing about which plan they had just chosen.
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(platformActionControllerProvider, (previous, next) {
      if (!next.isLoading && _pending && mounted) {
        setState(() => _pending = false);
      }
    });
    final busy = ref.watch(platformActionControllerProvider).isLoading;
    final tier = widget.tier;
    final name = tierTitleOf(tier);
    final subtitle = _tierProse(tier.subtitle);
    final breakdown = _tierBreakdown(tier);
    final price = _tierPriceOf(tier);
    final highlight = widget.isCurrent ? null : _tierHighlightLabel(tier);

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          _header(context, name: name, subtitle: subtitle, badge: highlight),
          if (!price.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            _TierPriceBlock(price: price),
          ],
          if (breakdown.specs.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            const _TierRule(),
            _TierSpecTable(rows: breakdown.specs),
          ],
          if (breakdown.inclusions.isNotEmpty) ...[
            const _TierRule(),
            _TierInclusions(items: breakdown.inclusions),
          ],
          if (price.isEmpty &&
              breakdown.specs.isEmpty &&
              breakdown.inclusions.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                  'This plan did not publish its price or its benefits. Pull to refresh, or ask support what it includes.'),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: ExampleInk.secondary(context),
              ),
            ),
          ],
          // The full contract (cards, their allowances and fees) opens on
          // request, so the ladder stays a comparison.
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TierDetailsButton(
              tierName: name,
              onPressed: () => showTierDetailsSheet(
                context,
                tier: tier,
                isCurrent: widget.isCurrent,
                onChoose: busy ? null : _select,
              ),
            ),
          ),
          if (widget.fillHeight) const Spacer(),
          const SizedBox(height: AppSpacing.md),
          _action(context, name: name, busy: busy),
        ],
      ),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, widget.isFocus ? 3 : 1),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: widget.isFocus
            ? ExampleBorders.emphasisOf(context)
            : ExampleBorders.subtleOf(context),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: widget.fillHeight ? MainAxisSize.max : MainAxisSize.min,
        children: [
          // The screen's one moment: the lit inner edge of the focus panel
          // takes a single sheen pass after the route settles.
          if (widget.isFocus) const _TierEdge(),
          if (widget.fillHeight) Expanded(child: content) else content,
        ],
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required String name,
    required String subtitle,
    required String? badge,
  }) {
    final pill = widget.isCurrent
        ? ExamplePill(
            label: context.tr('Current'),
            color: ExampleColors.success,
            dot: true,
          )
        : badge == null
            ? null
            : ExamplePill(label: badge, color: ExampleColors.iris);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: TextStyle(
                  fontSize: 17,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.primary(context),
                ),
              ),
              if (subtitle.isNotEmpty &&
                  subtitle.toLowerCase() != name.toLowerCase()) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (pill != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Padding(padding: const EdgeInsets.only(top: 2), child: pill),
        ],
      ],
    );
  }

  /// One control per panel, and only one of them is filled.
  ///
  /// The plan you are on holds the slot with a line of ink instead of a
  /// button: there is nothing to press, and an empty gap would knock the
  /// other panels' buttons off the shared baseline at desktop width.
  Widget _action(
    BuildContext context, {
    required String name,
    required bool busy,
  }) {
    if (widget.isCurrent) {
      return SizedBox(
        key: currentPlanSlotKey,
        height: ExampleGlassButton.minTouchTarget,
        child: Center(
          child: Text(
            context.tr('You are on this plan'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.3,
              color: ExampleInk.secondary(context),
            ),
          ),
        ),
      );
    }

    return ExampleGlassButton(
      // The label is fixed, not "Choose <name>": a tier name is service data
      // and a CTA label is one line that must never ellipsize. The specific
      // plan reaches assistive technology through the semantics label.
      label: context.tr('Choose this plan'),
      semanticsLabel: context.tr('Choose the {p0} plan', {'p0': name}),
      // The focus panel is the only filled slab on the page; the rest are the
      // same object unfilled, which reads as a real alternative rather than
      // as a row of competing CTAs.
      tone: widget.isFocus
          ? ExampleGlassButtonTone.primary
          : ExampleGlassButtonTone.neutral,
      // A painted panel, not an atmosphere: nothing behind is worth sampling,
      // so the material goes opaque and keeps its silhouette.
      ground: ExampleGlassGround.surface,
      // The panel's lit hairline is already this screen's sheen host. A
      // second one on the button would be two moments.
      sheen: false,
      loading: _pending && busy,
      loadingSemanticsLabel: 'Selecting the $name plan',
      onPressed: busy ? null : _select,
    );
  }

  void _select() {
    setState(() => _pending = true);
    _selectTier(context, ref, widget.tier);
  }
}

/// The slot the plan you are on holds instead of a button, so a desktop row's
/// actions still share a baseline. Named so a layout test can measure it.
@visibleForTesting
const Key currentPlanSlotKey = ValueKey('tier-current-plan-slot');

/// The lit inner edge of the focus panel, and the only sheen host on the
/// screen. Under reduced motion, or with no scope above it, it is a fixed
/// soft highlight and starts no ticker.
class _TierEdge extends StatelessWidget {
  const _TierEdge();

  @override
  Widget build(BuildContext context) => ExampleSheen(
        intensity: ExampleSheenIntensity.soft,
        child: SizedBox(
          height: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ExamplePalette.of(context).fill.withValues(alpha: .55),
            ),
          ),
        ),
      );
}

/// A hairline between two blocks inside a panel, with the panel's own
/// vertical rhythm around it. A `Divider` would bring its own theme height.
class _TierRule extends StatelessWidget {
  const _TierRule();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: SizedBox(
          height: 1,
          child: ColoredBox(
            color: ExampleBorders.hairlineSideOf(context).color,
          ),
        ),
      );
}

/// The price, set once and set large.
///
/// The service ships the price inside a sentence ("Price monthly 9.99 EUR");
/// a buyer compares numerals, not sentences. So the headline figure goes
/// through [ExampleAmount] at `medium` — the same tabular numerals as every
/// other amount in the app, which is what makes two panels comparable down a
/// column — and the period is a caption under it rather than a word glued to
/// the number.
class _TierPriceBlock extends StatelessWidget {
  const _TierPriceBlock({required this.price});

  final _TierPrice price;

  @override
  Widget build(BuildContext context) {
    final caption = price.period;
    final amount = price.amount;

    final Widget figure;
    if (amount == null) {
      figure = Text(
        price.fallback ?? '',
        style: TextStyle(
          fontSize: 15,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: ExampleInk.primary(context),
        ),
      );
    } else if (amount == 0) {
      // A published zero is "free", not "0.00". Saying it in a word is both
      // more honest and the stronger sales line.
      figure = Text(
        context.tr('Free'),
        style: TextStyle(
          fontSize: 26,
          height: 1.12,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: ExampleInk.primary(context),
        ),
      );
    } else {
      figure = ExampleAmount(
        amount: amount,
        currency: price.currency,
        size: ExampleAmountSize.medium,
        animate: false,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        figure,
        if (caption != null && caption.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            caption,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.35,
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      ],
    );
  }
}

/// The plan's numbers as a two-column table: label in secondary ink on the
/// left, value in tabular figures on the right. Aligned digits are the entire
/// point — a limit that has to be hunted for inside a sentence is a limit
/// nobody compares.
class _TierSpecTable extends StatelessWidget {
  const _TierSpecTable({required this.rows});

  final List<({String label, String value})> rows;

  @override
  Widget build(BuildContext context) {
    final valueStyle = ExampleTextStyles.amount(
      context,
      size: ExampleAmountSize.inline,
    ).copyWith(color: ExampleInk.primary(context));
    final labelStyle = TextStyle(
      fontSize: 12.5,
      height: 1.4,
      color: ExampleInk.secondary(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                // The label yields first, so a long one wraps rather than
                // pushing the numeral off its column.
                Expanded(child: Text(rows[i].label, style: labelStyle)),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  rows[i].value,
                  textAlign: TextAlign.end,
                  style: valueStyle,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// What the tier includes, one line each, wrapping rather than truncating.
class _TierInclusions extends StatelessWidget {
  const _TierInclusions({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final ink = ExampleInk.accent(context, ExampleColors.iris);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  // A real icon, never a check glyph: U+2713 is not in the
                  // bundled Geist subset and lands as a tofu box on web.
                  child: Icon(Icons.check_rounded, size: 14, color: ink),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    items[i],
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Deriving a plan panel from a service payload.
//
// `tierDetailsOf` is the shared contract — the account-setup flow and the
// legacy screen both render its lines verbatim — so nothing below changes it.
// These helpers re-read the same output and sort it into the three jobs the
// Example panel has: a headline price, a spec table and an inclusion list.
// ---------------------------------------------------------------------------

/// The price of a tier, parsed into numerals the app can set in its own
/// tabular voice instead of the sentence the service returns.
class _TierPrice {
  const _TierPrice({
    this.amount,
    this.currency = '',
    this.period,
    this.fallback,
  });

  /// Major units, or null when the payload's price could not be read as a
  /// number — in which case [fallback] holds the service's own line and is
  /// rendered verbatim rather than dropped.
  final double? amount;
  final String currency;

  /// "per month", "per year", or null when the payload does not say.
  final String? period;
  final String? fallback;

  bool get isEmpty => amount == null && (fallback == null || fallback!.isEmpty);
}

const List<String> _tierCurrencyKeys = [
  'currency',
  'Currency',
  'priceCurrency',
  'PriceCurrency',
  'currencyCode',
  'CurrencyCode',
];

const List<String> _tierMonthlyKeys = [
  'monthlyFee',
  'MonthlyFee',
  'monthlySubscriptionFee',
  'MonthlySubscriptionFee',
  'monthlyPrice',
  'MonthlyPrice',
];

const List<String> _tierYearlyKeys = [
  'yearlyFee',
  'YearlyFee',
  'yearlySubscriptionFee',
  'YearlySubscriptionFee',
  'yearlyPrice',
  'YearlyPrice',
];

const List<String> _tierFlatPriceKeys = [
  'price',
  'Price',
  'subscriptionFee',
  'SubscriptionFee',
  'fee',
  'Fee',
];

_TierPrice _tierPriceOf(PlatformResource tier) {
  final metadata = tier.metadata;
  final currency = _textValue(metadata, _tierCurrencyKeys) ?? '';
  final monthlyHidden =
      _boolValue(metadata, const ['hideMonthlyFee', 'HideMonthlyFee']) == true;
  final yearlyHidden =
      _boolValue(metadata, const ['hideYearlyFee', 'HideYearlyFee']) == true;
  final monthly = monthlyHidden ? null : _textValue(metadata, _tierMonthlyKeys);
  final yearly = yearlyHidden ? null : _textValue(metadata, _tierYearlyKeys);
  final flat = _textValue(metadata, _tierFlatPriceKeys);
  final fallback = _priceLabel(metadata);

  final headline = monthly ?? flat ?? yearly;
  if (headline == null) return const _TierPrice();

  final period = monthly != null
      ? 'per month'
      : (flat != null ? _periodFromCycle(tierCycleOf(tier)) : 'per year');
  final parsed = _parseAmount(headline);
  if (parsed == null) {
    return _TierPrice(currency: currency, fallback: fallback);
  }

  return _TierPrice(
    amount: parsed,
    currency: currency,
    period: period,
    fallback: fallback,
  );
}

String? _periodFromCycle(String? cycle) {
  final value = cycle?.toLowerCase() ?? '';
  if (value.contains('month')) return 'per month';
  if (value.contains('year') || value.contains('annual')) return 'per year';
  if (value.contains('week')) return 'per week';
  if (value.contains('day') || value.contains('daily')) return 'per day';
  return null;
}

double? _parseAmount(String raw) {
  final cleaned = raw.trim().replaceAll(',', '');
  if (cleaned.isEmpty) return null;
  return double.tryParse(cleaned);
}

/// A tier's own description, left as prose.
///
/// `friendlyStatus` exists to turn `pending_review` into "Pending Review", and
/// the screen ran every subtitle through it — which title-cased whole
/// sentences into "Higher Limits And Priority Support". A description is only
/// put through it when the string actually looks like a machine token.
String _tierProse(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final machineToken = !trimmed.contains(' ') ||
      trimmed.contains('_') ||
      trimmed == trimmed.toUpperCase();
  if (machineToken) return friendlyStatus(trimmed);
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}

/// The badge a tier wears when the service marks it out. State beats
/// marketing: the panel only asks for this when the tier is not the one the
/// user is already on.
String? _tierHighlightLabel(PlatformResource tier) {
  final metadata = tier.metadata;
  if (_boolValue(metadata, const ['isBestValue', 'IsBestValue']) == true) {
    return 'Best value';
  }
  if (_boolValue(metadata, const ['isRecommended', 'IsRecommended']) == true) {
    return 'Recommended';
  }
  if (_boolValue(metadata, const ['isPopular', 'IsPopular']) == true) {
    return 'Most popular';
  }
  return null;
}

/// Detail lines the panel has already said somewhere louder: the price is the
/// headline, the cycle is its caption, and the three marketing flags are the
/// pill.
const Set<String> _tierPromotedLines = {
  'Popular',
  'Best value',
};

/// Labels `tierDetailsOf` puts in front of a quantity. Everything matching
/// one of these becomes a spec row; everything else is an inclusion.
const List<String> _tierSpecLabels = [
  'Monthly limit',
  'Daily limit',
  'Transaction limit',
  'ATM limit',
  'Daily free draws',
  'Max cards',
  'Cards used',
  'Level',
  'KYC',
];

/// Labels worth restating in the panel's own words.
const Map<String, String> _tierSpecDisplayNames = {
  'KYC': 'KYC level',
  'Max cards': 'Cards included',
  'Level': 'Tier level',
};

/// Prefixes that add nothing next to a check mark.
const List<String> _tierInclusionPrefixes = ['Benefit ', 'Feature '];

({List<({String label, String value})> specs, List<String> inclusions})
    _tierBreakdown(PlatformResource tier) {
  final specs = <({String label, String value})>[];
  final inclusions = <String>[];

  final price = _tierPriceOf(tier);
  for (final line in tierDetailsOf(tier)) {
    if (line.startsWith('Price ')) {
      // The headline selects one billing price. Keep all published options
      // available when the service provides both monthly and annual fees.
      if (line.contains(' • ') || price.isEmpty) {
        inclusions.add(line.replaceAll(' • ', ' · '));
      }
      continue;
    }
    if (line.startsWith('Cycle ')) {
      // Unknown billing cycles are still service data; do not hide them just
      // because the headline cannot turn them into a standard price caption.
      if (price.period == null) inclusions.add(line);
      continue;
    }
    if (_tierPromotedLines.contains(line)) continue;

    final label =
        _tierSpecLabels.where((key) => line.startsWith('$key ')).fold<String?>(
              null,
              // Longest match wins, so "Daily limit" is never read as "Daily".
              (best, key) =>
                  best == null || key.length > best.length ? key : best,
            );
    if (label != null) {
      specs.add((
        label: _tierSpecDisplayNames[label] ?? label,
        value: _groupedNumber(line.substring(label.length + 1)),
      ));
      continue;
    }

    var text = line;
    for (final prefix in _tierInclusionPrefixes) {
      if (text.startsWith(prefix)) {
        text = text.substring(prefix.length);
        break;
      }
    }
    // The shared line joins its parts with U+2022. Every other Example screen
    // separates facts with the Latin-1 middle dot, which is also the safer
    // glyph in a white-label tenant's configured font, so the display copy is
    // normalised here rather than in the string every other caller reads.
    text = text.replaceAll(' \u2022 ', ' \u00B7 ');
    if (text.trim().isNotEmpty) inclusions.add(text);
  }

  return (specs: specs, inclusions: inclusions);
}

/// Groups the thousands in a bare integer so a limit reads at a glance.
/// Anything that is not a plain four-digit-or-longer integer is returned
/// untouched: the service's own string is never reinterpreted, and no
/// currency is invented for a number that did not carry one.
String _groupedNumber(String value) {
  final digits = value.trim();
  if (!RegExp(r'^\d{4,}$').hasMatch(digits)) return value;
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// The pre-Example screen, kept byte-identical for every white-label tenant.
class _LegacyBody extends ConsumerWidget {
  const _LegacyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiers = ref.watch(tiersProvider);
    final currentTier = ref.watch(currentTierProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        currentTier.when(
          data: (tier) => _CurrentTierPanel(tier: tier),
          error: (error, stackTrace) => const _CurrentTierPanel(tier: null),
          loading: () => Card(
            child: ListTile(
              leading: const AppProgressIndicator(),
              title: Text(context.tr('Loading current tier')),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('Available tiers'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        tiers.when(
          data: (items) => items.isEmpty
              ? EmptyState(
                  title: context.tr('No tiers available'),
                  message: context
                      .tr('Available user and card tiers will appear here.'),
                  icon: Icons.workspace_premium_outlined,
                )
              : Column(
                  children: [
                    for (final tier in items)
                      _TierCard(
                        tier: tier,
                        isCurrent:
                            tierIdOf(currentTier.valueOrNull) == tierIdOf(tier),
                      ),
                  ],
                ),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(tiersProvider),
          ),
          loading: () => LoadingState(label: context.tr('Loading tiers')),
        ),
      ],
    );
  }
}

class _CurrentTierPanel extends StatelessWidget {
  const _CurrentTierPanel({required this.tier});

  final PlatformResource? tier;

  @override
  Widget build(BuildContext context) {
    if (tier == null || tierIdOf(tier) == null) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.workspace_premium_outlined),
          title: Text(context.tr('No tier selected')),
          subtitle: Text(
              context.tr('Select a tier to unlock card ordering and limits.')),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.workspace_premium_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Current tier'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      Text(
                        tierTitleOf(tier!),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _TierDetailsWrap(tier: tier!),
          ],
        ),
      ),
    );
  }
}

class _TierCard extends ConsumerWidget {
  const _TierCard({
    required this.tier,
    required this.isCurrent,
  });

  final PlatformResource tier;
  final bool isCurrent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final action = ref.watch(platformActionControllerProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.workspace_premium_outlined),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tierTitleOf(tier),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (tier.subtitle.trim().isNotEmpty)
                        Text(friendlyStatus(tier.subtitle)),
                    ],
                  ),
                ),
                if (isCurrent)
                  Chip(label: Text(context.tr('Current')))
                else
                  FilledButton(
                    onPressed: action.isLoading
                        ? null
                        : () => _selectTier(context, ref, tier),
                    child: Text(context.tr('Select')),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _TierDetailsWrap(tier: tier),
          ],
        ),
      ),
    );
  }
}

class _TierDetailsWrap extends StatelessWidget {
  const _TierDetailsWrap({required this.tier});

  final PlatformResource tier;

  @override
  Widget build(BuildContext context) {
    final details = tierDetailsOf(tier);
    if (details.isEmpty) {
      return Text(context.tr('Tier details were not returned by the service.'));
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final detail in details)
          Chip(label: Text(detail), visualDensity: VisualDensity.compact),
      ],
    );
  }
}

void _selectTier(BuildContext context, WidgetRef ref, PlatformResource tier) {
  final tierId = tierIdOf(tier);
  if (tierId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context
            .tr('This tier is missing the identifier needed to select it.')),
      ),
    );
    return;
  }

  ref.read(platformActionControllerProvider.notifier).selectTier(
        tierId: tierId,
        tierCycle: tierCycleOf(tier),
      );
}

String tierTitleOf(PlatformResource tier) {
  final title = _textValue(tier.metadata, const [
    'tierName',
    'TierName',
    'displayName',
    'DisplayName',
    'name',
    'Name',
    'label',
    'Label',
  ]);
  if (title != null && !_looksTechnicalId(title)) {
    return friendlyStatus(title);
  }

  final fallback = tier.title.trim();
  if (fallback.isNotEmpty && !_looksTechnicalId(fallback)) {
    return friendlyStatus(fallback);
  }

  return 'Tier ${tierIdOf(tier) ?? ''}'.trim();
}

int? tierIdOf(PlatformResource? tier) {
  if (tier == null) {
    return null;
  }

  final value = _textValue(tier.metadata, const [
        'tierId',
        'TierId',
        'selectedTierId',
        'SelectedTierId',
        'id',
        'Id',
      ]) ??
      (tier.id.trim().isEmpty || tier.id == 'item' ? null : tier.id);

  return value == null ? null : int.tryParse(value);
}

List<String> tierDetailsOf(PlatformResource tier) {
  final metadata = tier.metadata;
  final price = _priceLabel(metadata);
  final cycle = tierCycleOf(tier);
  final level = _labeledValue('Level', metadata, const [
    'tierLevel',
    'TierLevel',
    'level',
    'Level',
  ]);
  final kyc = _labeledValue('KYC', metadata, const [
    'kycLevel',
    'KycLevel',
    'requiredKycLevel',
    'RequiredKycLevel',
    'kycTier',
    'KycTier',
  ]);
  final maxCards = _labeledValue('Max cards', metadata, const [
    'maxCards',
    'MaxCards',
    'cardLimit',
    'CardLimit',
    'numberOfCards',
    'NumberOfCards',
  ]);
  final cardsUsed = _labeledValue('Cards used', metadata, const [
    'currentCardCount',
    'CurrentCardCount',
    'usedCards',
    'UsedCards',
    'cardsUsed',
    'CardsUsed',
  ]);
  final dailyFreeDraws = _labeledValue('Daily free draws', metadata, const [
    'dailyFreeDraws',
    'DailyFreeDraws',
  ]);
  final details = <String>[
    if (price != null) price,
    if (cycle != null) 'Cycle ${friendlyStatus(cycle)}',
    if (level != null) level,
    if (kyc != null) kyc,
    if (_boolValue(metadata, const ['isDefault', 'IsDefault']) == true)
      'Default tier',
    if (_boolValue(metadata, const ['isPopular', 'IsPopular']) == true)
      'Popular',
    if (_boolValue(metadata, const ['isBestValue', 'IsBestValue']) == true)
      'Best value',
    if (_boolValue(
          metadata,
          const ['dailyRewardsEnabled', 'DailyRewardsEnabled'],
        ) ==
        true)
      'Daily rewards enabled',
    if (dailyFreeDraws != null) dailyFreeDraws,
    if (maxCards != null) maxCards,
    if (cardsUsed != null) cardsUsed,
    ..._limitDetails(metadata),
    ..._listDetails('Benefit', metadata, const [
      'benefits',
      'Benefits',
      'tierBenefits',
      'TierBenefits',
    ]),
    ..._listDetails('Feature', metadata, const [
      'features',
      'Features',
      'includedFeatures',
      'IncludedFeatures',
    ]),
    ..._listDetails('Card', metadata, const [
      'cardBenefits',
      'CardBenefits',
      'cardFeatures',
      'CardFeatures',
    ]),
    ..._cardTierDetails(metadata),
  ];

  final seen = <String>{};
  return [
    for (final detail in details)
      if (detail.trim().isNotEmpty && seen.add(detail.toLowerCase())) detail,
  ];
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}

String? tierCycleOf(PlatformResource tier) {
  return _textValue(tier.metadata, const [
    'tierCycle',
    'TierCycle',
    'billingCycle',
    'BillingCycle',
    'tierBillingCycle',
    'TierBillingCycle',
    'cycle',
    'Cycle',
  ]);
}

String? _priceLabel(Map<String, dynamic> metadata) {
  final currency = _textValue(metadata, const [
    'currency',
    'Currency',
    'priceCurrency',
    'PriceCurrency',
    'currencyCode',
    'CurrencyCode',
  ]);
  final monthlyPrice = _boolValue(
            metadata,
            const ['hideMonthlyFee', 'HideMonthlyFee'],
          ) ==
          true
      ? null
      : _textValue(metadata, const [
          'monthlyFee',
          'MonthlyFee',
          'monthlySubscriptionFee',
          'MonthlySubscriptionFee',
          'monthlyPrice',
          'MonthlyPrice',
        ]);
  final yearlyPrice = _boolValue(
            metadata,
            const ['hideYearlyFee', 'HideYearlyFee'],
          ) ==
          true
      ? null
      : _textValue(metadata, const [
          'yearlyFee',
          'YearlyFee',
          'yearlySubscriptionFee',
          'YearlySubscriptionFee',
          'yearlyPrice',
          'YearlyPrice',
        ]);
  final price = _textValue(metadata, const [
    'price',
    'Price',
    'subscriptionFee',
    'SubscriptionFee',
    'fee',
    'Fee',
  ]);
  final parts = [
    if (monthlyPrice != null) 'monthly ${_moneyText(monthlyPrice, currency)}',
    if (yearlyPrice != null) 'yearly ${_moneyText(yearlyPrice, currency)}',
  ];
  if (parts.isNotEmpty) {
    return 'Price ${parts.join(' • ')}';
  }

  return price == null ? null : 'Price ${_moneyText(price, currency)}';
}

List<String> _limitDetails(Map<String, dynamic> metadata) {
  final limits = <String>[
    ..._limitDetailsFromMap(metadata),
  ];
  final nestedLimits = metadata['limits'] ?? metadata['Limits'];
  if (nestedLimits is Map) {
    limits.addAll(_limitDetailsFromMap(_stringMap(nestedLimits)));
  }

  return limits;
}

List<String> _limitDetailsFromMap(Map<String, dynamic> metadata) {
  return [
    _labeledValue('Monthly limit', metadata, const [
      'monthlyLimit',
      'MonthlyLimit',
      'monthlySpendLimit',
      'MonthlySpendLimit',
      'monthlyTransactionLimit',
      'MonthlyTransactionLimit',
    ]),
    _labeledValue('Daily limit', metadata, const [
      'dailyLimit',
      'DailyLimit',
      'dailySpendLimit',
      'DailySpendLimit',
      'dailyTransactionLimit',
      'DailyTransactionLimit',
    ]),
    _labeledValue('Transaction limit', metadata, const [
      'transactionLimit',
      'TransactionLimit',
      'singleTransactionLimit',
      'SingleTransactionLimit',
    ]),
    _labeledValue('ATM limit', metadata, const [
      'atmLimit',
      'AtmLimit',
      'atmWithdrawalLimit',
      'AtmWithdrawalLimit',
    ]),
  ].whereType<String>().toList();
}

String? _labeledValue(
  String label,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  final value = _textValue(metadata, keys);
  if (value == null) {
    return null;
  }

  return '$label ${friendlyStatus(value)}';
}

List<String> _listDetails(
  String label,
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  final values = <String>[];
  for (final key in keys) {
    final value = metadata[key];
    _appendDisplayValues(values, value);
  }

  return [
    for (final value in values)
      if (value.trim().isNotEmpty) '$label ${friendlyStatus(value)}',
  ];
}

List<String> _cardTierDetails(Map<String, dynamic> metadata) {
  final rows = _listFromMetadata(metadata, const [
    'availableCardTypes',
    'AvailableCardTypes',
    'cardTypes',
    'CardTypes',
    'cardBenefits',
    'CardBenefits',
    'cardTiers',
    'CardTiers',
    'cards',
    'Cards',
  ]);

  return [
    for (final row in rows)
      if (_cardTierLabel(row) != null) _cardTierLabel(row)!,
  ];
}

String? _cardTierLabel(Map<String, dynamic> card) {
  final name = _textValue(card, const [
        'name',
        'Name',
        'displayName',
        'DisplayName',
        'cardTypeName',
        'CardTypeName',
        'cardType',
        'CardType',
        'productCode',
        'ProductCode',
      ]) ??
      'Card';
  final currency = _textValue(card, const [
    'currency',
    'Currency',
    'currencyCode',
    'CurrencyCode',
  ]);
  final freeCards = _labeledValue('free cards', card, const [
    'freeCardsIncluded',
    'FreeCardsIncluded',
  ]);
  final issueFee =
      _textValue(card, const ['issueFee', 'IssueFee', 'issuanceFee']);
  final replacementFee =
      _textValue(card, const ['replacementFee', 'ReplacementFee']);
  final monthlyFee =
      _textValue(card, const ['monthlyFee', 'MonthlyFee', 'fee', 'Fee']);
  final yearlyFee = _textValue(card, const [
    'yearlyFee',
    'YearlyFee',
    'yearlySubscriptionFee',
    'YearlySubscriptionFee',
  ]);
  final parts = [
    friendlyStatus(name),
    if (freeCards != null) freeCards,
    if (issueFee != null) 'issue ${_moneyText(issueFee, currency)}',
    if (replacementFee != null)
      'replacement ${_moneyText(replacementFee, currency)}',
    if (monthlyFee != null) 'monthly ${_moneyText(monthlyFee, currency)}',
    if (yearlyFee != null) 'yearly ${_moneyText(yearlyFee, currency)}',
    if (_textValue(card, const ['maxCards', 'MaxCards', 'limit', 'Limit']) !=
        null)
      'count ${_textValue(card, const [
            'maxCards',
            'MaxCards',
            'limit',
            'Limit'
          ])}',
    ..._listDetails('feature', card, const [
      'cardFeatures',
      'CardFeatures',
      'features',
      'Features',
    ]).map((value) => value.replaceFirst('feature ', '')),
  ];

  return 'Card ${parts.join(' • ')}';
}

String _moneyText(String amount, String? currency) {
  if (currency == null || currency.trim().isEmpty) {
    return amount;
  }

  return '$amount $currency';
}

bool? _boolValue(Map<String, dynamic> json, List<String> keys) {
  final value = _textValue(json, keys)?.toLowerCase();
  if (value == 'true') {
    return true;
  }
  if (value == 'false') {
    return false;
  }

  return null;
}

void _appendDisplayValues(List<String> values, Object? value) {
  if (value == null) {
    return;
  }
  if (value is List) {
    for (final item in value) {
      _appendDisplayValues(values, item);
    }
    return;
  }
  if (value is Map) {
    final json = value.map((key, item) => MapEntry(key.toString(), item));
    final text = _textValue(json, const [
      'name',
      'Name',
      'title',
      'Title',
      'label',
      'Label',
      'description',
      'Description',
      'benefit',
      'Benefit',
      'feature',
      'Feature',
    ]);
    if (text != null) {
      values.add(text);
    }
    return;
  }

  values.add(value.toString());
}

List<Map<String, dynamic>> _listFromMetadata(
  Map<String, dynamic> metadata,
  List<String> keys,
) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is List) {
      return value.whereType<Map>().map(_stringMap).toList();
    }
  }

  final nestedTier = metadata['tier'] ?? metadata['Tier'];
  if (nestedTier is Map) {
    return _listFromMetadata(_stringMap(nestedTier), keys);
  }

  return const [];
}

Map<String, dynamic> _stringMap(Map value) {
  return value.map((key, item) => MapEntry(key.toString(), item));
}

bool _looksTechnicalId(String value) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    return false;
  }

  return RegExp(r'^[a-z]+_[a-z0-9_]+$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^[0-9a-f]{8}-[0-9a-f-]{27,}$', caseSensitive: false)
          .hasMatch(normalized) ||
      RegExp(r'^\d+$').hasMatch(normalized);
}
