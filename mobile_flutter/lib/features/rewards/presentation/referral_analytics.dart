import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../domain/rewards_models.dart';
import 'referral_phone_summary.dart' show referralFriendStageTone;
import 'referral_sections.dart' show ReferralStageChip;
import 'referral_widgets.dart';

// ---------------------------------------------------------------------------
// The operating overview's analytics (blueprint p6, p7, p17, p20, p33): a
// selected period, the conversion journey as six stage counts and a rate,
// weekly bars for friends and for earnings, and the friends who earned the
// most. Only the member's own earnings and pseudonymised stages — never a
// friend's balances, top-ups or identity. Example only; the workspace mounts
// these on Overview and hides them when the backend does not serve the
// resource.
// ---------------------------------------------------------------------------

/// The period as a control label: "7 days", "30 days", "90 days",
/// "This month".
String referralRangeLabel(BuildContext context, ReferralAnalyticsRange range) {
  switch (range) {
    case ReferralAnalyticsRange.sevenDays:
      return context.tr('7 days');
    case ReferralAnalyticsRange.thirtyDays:
      return context.tr('30 days');
    case ReferralAnalyticsRange.ninetyDays:
      return context.tr('90 days');
    case ReferralAnalyticsRange.month:
      return context.tr('This month');
  }
}

/// The period as a caption under a figure: "in the last 30 days",
/// "this month".
String referralRangeCaption(
    BuildContext context, ReferralAnalyticsRange range) {
  final days = range.days;
  if (days == null) return context.tr('this month');
  return context.tr('in the last {p0} days', {'p0': days});
}

/// The date a week starts, as "Sep 1". Week starts are UTC midnights; the
/// calendar day is read in UTC so a western time zone does not show the
/// Sunday before.
String referralWeekLabel(BuildContext context, DateTime weekStart) {
  final utc = weekStart.toUtc();
  return MaterialLocalizations.of(context)
      .formatShortMonthDay(DateTime(utc.year, utc.month, utc.day));
}

/// 7 days · 30 days · 90 days · This month, as the house pill control.
class ReferralPeriodSelector extends StatelessWidget {
  const ReferralPeriodSelector({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final ReferralAnalyticsRange selected;
  final ValueChanged<ReferralAnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: context.tr('Period'),
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ExampleSegmentedControl<ReferralAnalyticsRange>(
              key: const Key('referral_period_selector'),
              segments: [
                for (final range in ReferralAnalyticsRange.values)
                  (value: range, label: referralRangeLabel(context, range)),
              ],
              selected: selected,
              onChanged: onChanged,
            ),
          ),
        ),
      );
}

// ------------------------------------------------------------------ journey

/// Invited → Verified → Card issued → Qualified → Earning → Window ended:
/// the friends attributed in the period by the furthest stage they reached,
/// and the share of them that qualified. Six figures in a row on a wide
/// column, two rows of three below 640 px.
class ReferralJourneyStrip extends StatelessWidget {
  const ReferralJourneyStrip({required this.analytics, super.key});

  final ReferralMemberAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final stages = analytics.journey.stages;
    var top = 0;
    for (final stage in stages) {
      if (stage.count > top) top = stage.count;
    }
    final light = ExampleTheme.isLight(context);
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final success = ExampleInk.accent(context, ExampleColors.success);
    Color colorFor(String id) {
      switch (id) {
        case 'invited':
          return accent.withValues(alpha: light ? .76 : .62);
        case 'qualified':
        case 'earning':
          return success;
        case 'windowEnded':
          return ExampleInk.tertiary(context);
        default:
          return accent;
      }
    }

    final tiles = [
      for (final stage in stages)
        _JourneyStage(
          key: Key('referral_journey_${stage.id}'),
          label: context.tr(stage.label),
          count: stage.count,
          factor: top == 0 ? 0 : stage.count / top,
          color: colorFor(stage.id),
        ),
    ];
    final rate = '${(analytics.totals.conversionRate * 100).round()}%';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Conversion journey')),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: light
                ? ExampleBorders.subtleLightAll
                : ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              key: const Key('referral_journey_strip'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= 640) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < tiles.length; i++) ...[
                            if (i > 0) const _JourneyArrow(),
                            Expanded(child: tiles[i]),
                          ],
                        ],
                      );
                    }
                    Widget row(int first) => Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = first; i < first + 3; i++) ...[
                              if (i > first)
                                const SizedBox(width: AppSpacing.sm),
                              Expanded(child: tiles[i]),
                            ],
                          ],
                        );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        row(0),
                        const SizedBox(height: AppSpacing.md),
                        row(3),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 1,
                  child: ColoredBox(
                    color: ExampleBorders.hairlineSideOf(context).color,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                MergeSemantics(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.tr('Conversion rate'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        context.tr('{p0} of {p1} qualified', {
                          'p0': analytics.totals.qualified,
                          'p1': analytics.totals.attributed,
                        }),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: ExampleInk.secondary(context),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        rate,
                        key: const Key('referral_journey_rate'),
                        style: referralFigureStyle(context, size: 17),
                      ),
                    ],
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

/// One stage: the figure, the name, and a magnitude bar against the
/// widest stage so the narrowing reads as a shape before it is read as
/// numbers.
class _JourneyStage extends StatelessWidget {
  const _JourneyStage({
    required this.label,
    required this.count,
    required this.factor,
    required this.color,
    super.key,
  });

  final String label;
  final int count;

  /// Share of the widest stage, 0..1.
  final double factor;
  final Color color;

  static const double _bar = 4;
  static const double _floor = .06;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(_bar / 2));
    final width = factor <= 0 ? 0.0 : factor.clamp(_floor, 1.0).toDouble();
    return MergeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$count',
            maxLines: 1,
            style: referralFigureStyle(context, size: 22),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.3,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: _bar,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ExampleInk.tint(context, ExampleColors.lavender,
                    alpha: .18),
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

class _JourneyArrow extends StatelessWidget {
  const _JourneyArrow();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 0),
          child: Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: ExampleInk.tertiary(context),
          ),
        ),
      );
}

// -------------------------------------------------------------------- trend

/// Which weekly series the trend panel shows.
enum ReferralTrendSeries { friends, earnings }

/// Weekly bars with two tabs: attributed against qualified friends, and
/// accrued against paid rewards. Each series also reads as one sentence to
/// a screen reader, so the chart is never the only carrier of the figures.
class ReferralTrendPanel extends StatefulWidget {
  const ReferralTrendPanel({required this.analytics, super.key});

  final ReferralMemberAnalytics analytics;

  @override
  State<ReferralTrendPanel> createState() => _ReferralTrendPanelState();
}

class _ReferralTrendPanelState extends State<ReferralTrendPanel> {
  ReferralTrendSeries _series = ReferralTrendSeries.friends;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(title: context.tr('Trend')),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: BorderRadius.circular(AppRadii.lg),
            border: light
                ? ExampleBorders.subtleLightAll
                : ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              key: const Key('referral_trend_panel'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ReferralFilterChips<ReferralTrendSeries>(
                  key: const Key('referral_trend_tabs'),
                  options: [
                    (
                      value: ReferralTrendSeries.friends,
                      label: context.tr('Qualified friends'),
                    ),
                    (
                      value: ReferralTrendSeries.earnings,
                      label: context.tr('Earnings'),
                    ),
                  ],
                  selected: _series,
                  onChanged: (value) => setState(() => _series = value),
                ),
                const SizedBox(height: AppSpacing.md),
                ReferralWeeklyBars(
                  key: ValueKey('referral_trend_${_series.name}'),
                  analytics: widget.analytics,
                  series: _series,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The weekly bars for one series, with their legend and text summary.
class ReferralWeeklyBars extends StatelessWidget {
  const ReferralWeeklyBars({
    required this.analytics,
    required this.series,
    this.height = 220,
    super.key,
  });

  final ReferralMemberAnalytics analytics;
  final ReferralTrendSeries series;
  final double height;

  bool get _money => series == ReferralTrendSeries.earnings;

  double _primary(ReferralWeeklyBucket week) =>
      _money ? week.rewardsAccrued : week.attributed.toDouble();

  double _secondary(ReferralWeeklyBucket week) =>
      _money ? week.rewardsPaid : week.qualified.toDouble();

  String _format(double value) => _money
      ? formatReferralAmount(analytics.currency, value)
      : value.round().toString();

  @override
  Widget build(BuildContext context) {
    final weeks = analytics.weekly;
    final primaryLabel =
        _money ? context.tr('Accrued') : context.tr('Attributed');
    final secondaryLabel =
        _money ? context.tr('Paid') : context.tr('Qualified');
    final light = ExampleTheme.isLight(context);
    final accent = ExampleInk.accent(context, ExampleColors.iris);
    final primaryColor = accent.withValues(alpha: light ? .76 : .62);
    final secondaryColor = ExampleInk.accent(context, ExampleColors.success);
    final summary = StringBuffer(
      _money
          ? context.tr('Earnings per week')
          : context.tr('Qualified friends per week'),
    );
    if (weeks.isEmpty) {
      summary.write(': ${context.tr('No activity in this period')}');
    }
    for (final week in weeks) {
      final label = referralWeekLabel(context, week.weekStart);
      final figures = _money
          ? context.tr('{p0} accrued, {p1} paid', {
              'p0': _format(week.rewardsAccrued),
              'p1': _format(week.rewardsPaid),
            })
          : context.tr('{p0} attributed, {p1} qualified', {
              'p0': week.attributed,
              'p1': week.qualified,
            });
      summary.write('; ${context.tr('Week of {p0}', {'p0': label})}: $figures');
    }
    final legend = Row(
      children: [
        _LegendSwatch(color: primaryColor, label: primaryLabel),
        const SizedBox(width: AppSpacing.md),
        _LegendSwatch(color: secondaryColor, label: secondaryLabel),
      ],
    );
    return Semantics(
      label: summary.toString(),
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: height,
              child: weeks.isEmpty
                  ? Center(
                      child: Text(
                        context.tr('No activity in this period'),
                        style: referralBodyStyle(context),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => _chart(
                        context,
                        weeks,
                        width: constraints.maxWidth,
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        primaryLabel: primaryLabel,
                        secondaryLabel: secondaryLabel,
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.sm),
            legend,
          ],
        ),
      ),
    );
  }

  Widget _chart(
    BuildContext context,
    List<ReferralWeeklyBucket> weeks, {
    required double width,
    required Color primaryColor,
    required Color secondaryColor,
    required String primaryLabel,
    required String secondaryLabel,
  }) {
    var peak = 0.0;
    for (final week in weeks) {
      peak = math.max(peak, math.max(_primary(week), _secondary(week)));
    }
    final step = _money ? _niceStep(peak) : math.max(1.0, _niceStep(peak));
    final maxY = peak <= 0 ? step : step * (peak / step).ceil();
    const reservedLeft = 44.0;
    const groupsSpace = 10.0;
    final slot = (width - reservedLeft) / weeks.length;
    final barWidth = ((slot - groupsSpace) / 2 - 2).clamp(3.0, 16.0);
    final stride = weeks.length <= 8
        ? 1
        : weeks.length <= 16
            ? 2
            : 3;
    final hairline = ExampleBorders.hairlineSideOf(context).color;
    final axisStyle = TextStyle(
      fontSize: 11,
      color: ExampleInk.secondary(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final tooltipStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: ExampleInk.primary(context),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return BarChart(
      duration: Duration.zero,
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        minY: 0,
        maxY: maxY,
        groupsSpace: groupsSpace,
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: step,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: hairline, strokeWidth: 1),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: reservedLeft,
              interval: step,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                space: 6,
                child: Text(_format(value), style: axisStyle, maxLines: 1),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= weeks.length || index % stride != 0) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  child: Text(
                    referralWeekLabel(context, weeks[index].weekStart),
                    style: axisStyle,
                    maxLines: 1,
                  ),
                );
              },
            ),
          ),
        ),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => ExampleSurface.of(context, 3),
            tooltipBorder: BorderSide(color: hairline),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final week = weeks[group.x];
              final label = rodIndex == 0 ? primaryLabel : secondaryLabel;
              return BarTooltipItem(
                '${referralWeekLabel(context, week.weekStart)}\n'
                '$label ${_format(rod.toY)}',
                tooltipStyle,
              );
            },
          ),
        ),
        barGroups: [
          for (var i = 0; i < weeks.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 3,
              barRods: [
                BarChartRodData(
                  toY: _primary(weeks[i]),
                  color: primaryColor,
                  width: barWidth,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
                BarChartRodData(
                  toY: _secondary(weeks[i]),
                  color: secondaryColor,
                  width: barWidth,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A gridline step that divides [peak] into at most five even bands:
/// 1, 2 or 5 times a power of ten.
double _niceStep(double peak) {
  if (peak <= 0) return 1;
  final rough = peak / 4;
  final magnitude =
      math.pow(10, (math.log(rough) / math.ln10).floor()).toDouble();
  for (final factor in const [1, 2, 5]) {
    final step = magnitude * factor;
    if (peak / step <= 5) return step;
  }
  return magnitude * 10;
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      );
}

// -------------------------------------------------------------- top friends

/// The friends who earned the member the most in the period: pseudonym,
/// stage, earned. At most ten; the caller leaves the block out when the
/// list is empty.
class ReferralTopFriends extends StatelessWidget {
  const ReferralTopFriends({required this.analytics, super.key});

  final ReferralMemberAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final friends = analytics.topFriends.take(10).toList();
    final localizations = MaterialLocalizations.of(context);
    return ExampleListGroup(
      key: const Key('referral_top_friends'),
      title: context.tr('Top friends'),
      children: [
        for (final friend in friends)
          () {
            final stage = context.tr(friend.stage.label);
            final earned = formatReferralAmount(analytics.currency, friend.earned);
            final qualifiedAt = friend.qualifiedAt;
            final subtitle = qualifiedAt == null
                ? null
                : context.tr('Qualified on {p0}', {
                    'p0': localizations.formatShortDate(qualifiedAt.toLocal()),
                  });
            return ExampleRow(
              title: friend.alias,
              subtitle: subtitle,
              minHeight: 60,
              leading: const ExampleIconTile(
                icon: Icons.person_outline_rounded,
                color: ExampleColors.iris,
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(earned, style: referralFigureStyle(context)),
                  const SizedBox(height: 4),
                  ReferralStageChip(
                    label: stage,
                    tone: referralFriendStageTone(friend.stage),
                  ),
                ],
              ),
              semanticsLabel: '${friend.alias}, $stage, $earned',
            );
          }(),
      ],
    );
  }
}

// ------------------------------------------------------------------- states

/// Nothing happened in the period; the next action is to share the link.
class ReferralAnalyticsEmpty extends StatelessWidget {
  const ReferralAnalyticsEmpty({required this.onShare, super.key});

  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) => ExampleEmptyState(
        key: const Key('referral_analytics_empty'),
        compact: true,
        icon: Icons.insights_outlined,
        title: context.tr('No activity in this period'),
        body: context.tr(
            'Friends you invite and rewards you earn in this period will show here.'),
        actionLabel: context.tr('Share your link'),
        onAction: onShare,
      );
}

/// Placeholders for the journey strip and the trend panel while the
/// analytics load, under one sheen host.
class ReferralAnalyticsSkeleton extends StatelessWidget {
  const ReferralAnalyticsSkeleton({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
        key: const Key('referral_analytics_loading'),
        label: context.tr('Loading analytics'),
        child: const ExcludeSemantics(
          child: ExampleSheen.text(
            intensity: ExampleSheenIntensity.soft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExampleSkeleton.line(width: 160, height: 14, sheen: false),
                SizedBox(height: AppSpacing.sm),
                ExampleSkeleton.card(height: 132, sheen: false),
                SizedBox(height: AppSpacing.lg),
                ExampleSkeleton.line(width: 72, height: 14, sheen: false),
                SizedBox(height: AppSpacing.sm),
                ExampleSkeleton.card(height: 300, sheen: false),
              ],
            ),
          ),
        ),
      );
}
