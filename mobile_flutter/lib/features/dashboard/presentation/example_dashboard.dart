import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';
import 'example_activation_panel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example_glass_button.dart';
import '../../../brands/example/example_tilt.dart';
import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_typography.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/group_card_fees.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/privacy/private_mode_provider.dart';
import '../../../shared/widgets/safeguarding_statement.dart';
import '../../auth/application/biometric_providers.dart';
import '../../auth/presentation/biometric_enable.dart';
import '../../cards/presentation/widgets/card_face.dart';
import '../../cards/presentation/card_detail_screen.dart' show showCardTopUp;
import '../../crypto/presentation/buy_crypto_screen.dart';
import '../../notifications/presentation/notifications_popover.dart';
import '../../onboarding/application/account_setup_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/tiers_screen.dart';
import '../../transactions/application/transaction_identity_provider.dart';
import '../../wallets/presentation/crypto_wallet_actions.dart';
import '../domain/dashboard_models.dart';
import '../domain/spending_insights.dart';
import '../data/display_currency_provider.dart';
import 'display_currency_selector.dart';
import 'widgets/example_balance_chart.dart';

/// Home's alive layer lives under the shell's [ExampleSheenScope]: the screen
/// mounted on its own — a widget test, a component gallery card — has no
/// scope, renders exactly the pixels it rendered before the sheen existed,
/// and gets no lit hairline either, because an edge that only catches light
/// has nothing to catch. Inside the shell, reduced motion still resolves to
/// the static highlight [ExampleSheen] paints for itself.
bool _aliveLayer(BuildContext context) =>
    ExampleSheenScope.maybeOf(context) != null;

/// The one headline on Home the alive layer touches. A soft band walks the
/// glyphs on arrival and once a cadence after that; the type does not move.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final headline = Text(text, style: style);
    if (!_aliveLayer(context)) return headline;
    return ExampleSheen.text(
      intensity: ExampleSheenIntensity.soft,
      child: headline,
    );
  }
}

/// Lets the dashboard's chart-animation option reach both responsive panels.
class _ChartAnimationScope extends InheritedWidget {
  const _ChartAnimationScope({required this.animate, required super.child});

  final bool animate;

  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_ChartAnimationScope>()
          ?.animate ??
      true;

  @override
  bool updateShouldNotify(_ChartAnimationScope oldWidget) =>
      oldWidget.animate != animate;
}

/// Example Home with the customer's Twilight and Pearl Daylight design.
class ExampleDashboard extends ConsumerWidget {
  const ExampleDashboard({
    required this.snapshot,
    required this.unreadNotifications,
    required this.onRefresh,
    this.greetingTime,
    this.animateChart = true,
    super.key,
  });

  final HoppaDashboardSnapshot snapshot;
  final int unreadNotifications;
  final Future<void> Function() onRefresh;
  final DateTime? greetingTime;

  /// Controls the balance chart animation; tests can render its settled state.
  final bool animateChart;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _ChartAnimationScope(
        animate: animateChart,
        child: LayoutBuilder(
          builder: (context, constraints) => _build(
            context,
            ref,
            desktop: constraints.maxWidth >= ExampleBreakpoints.desktop,
          ),
        ),
      );

  Widget _build(BuildContext context, WidgetRef ref, {required bool desktop}) {
    final firstName = _firstName(snapshot.customerName);
    final rows = _accountRows(context, snapshot);
    final openCards = snapshot.cards
        .where((card) => card.status != CardStatus.cancelled)
        .toList();
    final selectedCard = openCards.firstOrNull;
    final greeting = context.tr('{p0}, {p1}',
        {'p0': context.tr(_greeting(greetingTime)), 'p1': firstName});

    if (desktop) {
      return Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Home')),
          actions: [
            RefreshAction(onRefresh: onRefresh),
            if (snapshot.outflowsEnabled)
              _SendMoneyButton(onTap: () => _openSend(context, ref, snapshot)),
            const SizedBox(width: 12),
            _BellButton(
              unread: unreadNotifications,
              boxed: true,
              onTap: () => showNotificationsPopover(context),
            ),
          ],
        ),
        // The same sky at 1440. Desktop Home was the one Example surface with
        // no atmosphere behind it: a flat page with panels floating on
        // nothing, which is where daylight materiality actually loses. The
        // preset's light branch carries the ground from 1.09:1 to 1.20:1
        // between base and peak, so the wide page reads as a lit room, the
        // frosted hero has something real to blur, and the two breakpoints
        // stop being two different products.
        body: ExampleAtmosphere.home(
          child: ExampleBackdrop(
            child: RefreshIndicator(
              onRefresh: onRefresh,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 900;
                  final pad = compact ? 24.0 : 40.0;
                  return ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(pad, 32, pad, 40),
                    children: [
                      _Greeting(
                        text: greeting,
                        style: TextStyle(
                          color: ExampleInk.primary(context),
                          fontSize: 26 * context.brandDesign.typographyScale,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.4,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _longDate(context, greetingTime ?? DateTime.now()),
                        style: TextStyle(
                          color: ExampleInk.tertiary(context),
                          fontSize: 13.5 * context.brandDesign.typographyScale,
                        ),
                      ),
                      const SizedBox(height: 28),
                      _AccountSetupBanner(snapshot: snapshot),
                      ExampleActivationPanel(
                        key: ValueKey('activation-${snapshot.accountId}'),
                        setupComplete:
                            ref.watch(currentTierProvider).valueOrNull != null,
                        snapshot: snapshot,
                      ),
                      const _BiometricNudge(),
                      _DesktopBalancePanel(
                        snapshot: snapshot,
                        ref: ref,
                        compact: compact,
                        greetingTime: greetingTime,
                      ),
                      if (!snapshot.isBusinessAccount) ...[
                        const SizedBox(height: 28),
                        _HomeCardShelf(card: selectedCard),
                  const SizedBox(height: 16),
                  ExampleReferralTeaser(enabled: snapshot.referralsEnabled),
                      ],
                      const SizedBox(height: 28),
                      _DesktopSectionTitle(
                        title: context.tr('Accounts'),
                        action: context.tr('View all'),
                        onTap: () => context.go(
                          snapshot.fiatEnabled
                              ? AppRoutes.money
                              : AppRoutes.walletAssets,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _DesktopAccountGrid(rows: rows, compact: compact),
                      if (snapshot.fiatEnabled) ...[
                        const SizedBox(height: 6),
                        const SafeguardingStatementButton(),
                      ],
                      if (snapshot.activities.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        _DesktopSectionTitle(
                          title: context.tr('Recent activity'),
                          action: context.tr('All transactions'),
                          onTap: () => context.go(AppRoutes.activity),
                        ),
                        const SizedBox(height: 14),
                        _DesktopActivityPanel(
                          activities: snapshot.activities.take(5).toList(),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
    }

    // The home sky. `ExampleAtmosphere.home` paints the page ground plus the
    // indigo dawn off the top-left and the teal counter-glow low and right,
    // and it is what makes daylight Home read as a lit room rather than an
    // inverted dark theme: the preset's light branch runs at the .80 daylight
    // budget, so paper travels 1.09:1 -> 1.20:1 from ground to peak while
    // night ink stays at 14.9:1 on the brightest point. It replaces the
    // shell's generic top-centre glow inside the scroll only; the ground it
    // paints (appBackground on Twilight, lightPaper in daylight) is the
    // canonical page ground the navigation surface is specified to separate
    // upward from, so the bar above it reads as chrome, not as a seam.
    return Scaffold(
      body: ExampleAtmosphere.home(
        child: ExampleBackdrop(
          child: RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 10),
                    child: Row(
                      children: [
                        const ExampleLockup(height: 27),
                        const Spacer(),
                        RefreshAction(onRefresh: onRefresh),
                        _BellButton(
                          unread: unreadNotifications,
                          boxed: false,
                          onTap: () => context.go(AppRoutes.notifications),
                        ),
                        IconButton(
                          tooltip: context.tr('Settings'),
                          // 44 pt is the floor for every pressable; the
                          // default IconButton box is 48 but its constraints
                          // are only honoured when they are stated.
                          constraints: const BoxConstraints(
                            minWidth: 44,
                            minHeight: 44,
                          ),
                          onPressed: () => context.go(AppRoutes.profile),
                          icon: Icon(
                            Icons.settings_outlined,
                            size: 22,
                            color: ExampleInk.primary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _Greeting(
                  text: greeting,
                  style: TextStyle(
                    color: ExampleInk.primary(context),
                    fontSize: 21 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _membershipLabel(
                    context,
                    snapshot,
                    ref.watch(currentTierProvider).valueOrNull,
                  ),
                  style: TextStyle(
                    color: ExampleInk.accent(context, ExampleColors.iris),
                    fontSize: 12.5 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                _AccountSetupBanner(snapshot: snapshot),
                ExampleActivationPanel(
                  key: ValueKey('activation-${snapshot.accountId}'),
                  setupComplete:
                      ref.watch(currentTierProvider).valueOrNull != null,
                  snapshot: snapshot,
                ),
                const _BiometricNudge(),
                _HeroPanel(
                  snapshot: snapshot,
                  ref: ref,
                  greetingTime: greetingTime,
                ),
                if (!snapshot.isBusinessAccount) ...[
                  const SizedBox(height: 18),
                  // The card sits directly under the hero, not under five
                  // account rows. It was the last block before "Smart
                  // insights", roughly 1,050 px down a 844 px viewport, which
                  // put the one object on this product that nothing in the
                  // category matches a full screen and a half below the fold.
                  // Balance, then the card, then the ledger is also the order
                  // the page is actually read in: what I have, the thing I
                  // spend it with, where it sits.
                  //
                  // The shelf takes the same header as the two ledgers below
                  // it. Unframed, the artwork has to belong to the page's own
                  // structure rather than to a box of its own; with a header
                  // it reads as one labelled block in a sequence of labelled
                  // blocks instead of a banner dropped between them. No
                  // chevron on this one - the row already carries one, and
                  // the two point at different places (all cards vs this
                  // card).
                  _HomeCardShelf(card: selectedCard),
                  const SizedBox(height: 16),
                  ExampleReferralTeaser(enabled: snapshot.referralsEnabled),
                ],
                const SizedBox(height: 16),
                // One list group, not four floating cards. Four identical
                // panels stacked down the page is the "identical card grid"
                // tell; hairline-separated rows on one surface put the
                // amounts in a single right-aligned tabular column, which is
                // how a balance sheet is read.
                if (rows.isEmpty)
                  ExampleGlassPanel(
                    child: Text(
                      context
                          .tr('Balances will appear after your accounts sync.'),
                      style: TextStyle(color: ExampleInk.secondary(context)),
                    ),
                  )
                else
                  _AccountsGroup(rows: rows, snapshot: snapshot),
                if (snapshot.fiatEnabled) ...[
                  const SizedBox(height: 2),
                  const SafeguardingStatementButton(),
                ],
                const SizedBox(height: 14),
                _InsightPanel(activities: snapshot.activities),
                if (snapshot.activities.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  // The second ledger, built exactly like the first. Four
                  // separate rounded panels with 5 px of page showing between
                  // them is the stacked-identical-card tell, and on paper it
                  // is four flat white rectangles where one seated surface
                  // belongs — the single largest remaining daylight-
                  // materiality loss on this screen. One group, one set of
                  // hairlines, one right-aligned tabular amount column.
                  _ActivityGroup(
                    activities: snapshot.activities.take(4).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desktop Home's one decisive action, on the shared glass CTA.
///
/// It was a hand-rolled 40 pt pill on two literal violets that exist nowhere
/// in the palette — below the 44 pt target floor and outside the colour
/// system. The shared button is the same silhouette on named tones, resolves
/// both themes itself, and clamps its own height to the floor. Its ground is
/// `surface`: an app bar is opaque chrome with nothing behind it to blur, and
/// a bounded blur there would only cost a layer.
class _SendMoneyButton extends StatelessWidget {
  const _SendMoneyButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExampleGlassButton(
        label: context.tr('Send money'),
        icon: Icons.north_east_rounded,
        expand: false,
        height: 44,
        radius: AppRadii.md,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onPressed: onTap,
      );
}

class _BellButton extends StatelessWidget {
  const _BellButton({
    required this.unread,
    required this.boxed,
    required this.onTap,
  });

  final int unread;
  final bool boxed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: unread > 0
            ? context.tr('Notifications, {p0} unread', {'p0': unread})
            : context.tr('Notifications'),
        child: Tooltip(
          message: context.tr('Notifications'),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              // 44 in both forms. The boxed variant used to be 42, which put
              // the desktop notification target 2 pt under the floor for the
              // sake of matching a border that no one measures.
              width: 44,
              height: 44,
              decoration: boxed
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: ExampleBorders.subtleOf(context),
                    )
                  : null,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_none_rounded,
                    size: 22,
                    color: ExampleInk.primary(context),
                  ),
                  if (unread > 0)
                    Positioned(
                      top: boxed ? 9 : 6,
                      right: boxed ? 11 : 8,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: ExampleInk.accent(context, ExampleColors.violet),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Arms a screen's arrival moment once, and only once the route is really
/// on screen.
///
/// A freshly pushed route reports its animation as already completed on the
/// first build, so asking on frame one arms the moment during the 420 ms
/// transition — where nothing is allowed to run. The short delay lets the
/// real animation be installed, then the moment waits for it. Reduced motion
/// never schedules anything: the settled state is correct on frame one.
///
/// It is a separate object because Home has two layouts and one moment. The
/// phone hero and the desktop hero are different compositions of the same
/// balance, and a moment that only existed on the narrow one would make the
/// wide breakpoint a different product.
class _ArrivalSettle extends StatefulWidget {
  const _ArrivalSettle({required this.builder});

  final Widget Function(BuildContext context, bool settled) builder;

  @override
  State<_ArrivalSettle> createState() => _ArrivalSettleState();
}

class _ArrivalSettleState extends State<_ArrivalSettle> {
  /// How long after mount the arrival moment is armed. Long enough that the
  /// route animation has been installed for real.
  static const Duration _settleDelay = Duration(milliseconds: 240);

  bool _settled = false;
  Timer? _settleTimer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    // Reduced motion has no arrival: the value is correct on frame one.
    if (!_ChartAnimationScope.of(context) || ExampleMotion.reduced(context)) {
      _settled = true;
      return;
    }
    _settleTimer ??= Timer(_settleDelay, _armFromRoute);
  }

  void _armFromRoute() {
    if (!mounted || _settled) return;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      setState(() => _settled = true);
      return;
    }
    _routeAnimation = animation..addStatusListener(_onRouteStatus);
  }

  void _onRouteStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _detachRoute();
    if (!mounted || _settled) return;
    setState(() => _settled = true);
  }

  void _detachRoute() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _detachRoute();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _settled);
}

/// Home's hero: the balance is the sky.
///
/// The panel groups the balance, recent transaction history and five actions.
/// It is the only element on the screen that gets an arrival animation. The moment is the
/// amount settling from secondary to primary ink over 200 ms, once, after the
/// route transition has finished; nothing else on Home animates on arrival.
///
/// The panel is frosted rather than matte because it sits over a real
/// atmosphere, and daylight materiality is where this screen was weakest: a
/// blurred, white .60 plane with the violet dawn showing through it, seated on
/// an ambient shadow, is a material. A flat white card on paper is not.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.snapshot,
    required this.ref,
    this.greetingTime,
  });

  final HoppaDashboardSnapshot snapshot;
  final WidgetRef ref;
  final DateTime? greetingTime;

  /// Corner radius of the panel and of the sweep, which must agree or the
  /// rim stops hugging the corners.
  static const double _radius = 24;

  /// Horizontal margin of everything in the panel that is type. The action
  /// strip is deliberately outside it.
  static const EdgeInsets _typeInset = EdgeInsets.symmetric(horizontal: 18);

  @override
  Widget build(BuildContext context) => _ArrivalSettle(
        builder: (context, settled) => _panel(context, settled),
      );

  Widget _panel(BuildContext context, bool settled) {
    final portfolio = _displayPortfolio(snapshot, ref);
    final series = ExampleBalanceSeries.fromActivities(
      portfolio.total,
      snapshot.activities,
      currency: portfolio.currency,
      asOf: snapshot.portfolioEstimate?.valuedAt,
      valuationRates: portfolio.valuationRates,
    );
    final panel = ExampleGlassPanel(
      radius: _radius,
      material: ExampleGlassMaterial.frosted,
      // The sweep is the panel's edge. A border under it would be a second
      // rule at the same radius, and two 1 px lines on one object read as a
      // mistake rather than as light.
      borderAlpha: 0,
      // The panel's padding is vertical only so the five quick actions can
      // run its full inner width while the type block keeps an 18 px margin.
      // Under the old symmetric 18, each action had 51.8 px of label at 375
      // and the longest word on it — "Exchange" — measures 50.6 px in Geist
      // at 11 px. 1.2 px of headroom is not a layout, it is a coincidence
      // that any text scaling above 1.02 spends. Full-bleeding the strip
      // gives the same label 56.6 px. It also reads correctly: the actions
      // are a keyboard under the balance, not another line of the paragraph,
      // so they are allowed to sit a little wider than the prose.
      padding: const EdgeInsets.fromLTRB(0, 15, 0, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: _typeInset,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.tr('Total balance'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5 * context.brandDesign.typographyScale,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: Money.maskAmounts
                          ? context.tr('Show balances')
                          : context.tr('Hide balances'),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      // 44 pt floor. The old 28 pt box put the one control that
                      // hides a customer's money below the tap target minimum.
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      onPressed: () =>
                          ref.read(privateModeProvider.notifier).toggle(),
                      icon: Icon(
                        Money.maskAmounts
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 17,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                    const Spacer(),
                    DisplayCurrencySelector(currencies: [
                      for (final account in snapshot.accounts)
                        if (account.provider.toLowerCase().contains('equals'))
                          account.currency,
                    ]),
                  ],
                ),
                _HeroAmount(
                  currency: portfolio.currency,
                  amount: portfolio.total,
                  settled: settled,
                ),
                const SizedBox(height: 7),
                Text(
                  context.tr(portfolio.caption),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12 * context.brandDesign.typographyScale,
                    fontWeight: FontWeight.w600,
                    color: _captionInk(context, portfolio.captionTone),
                  ),
                ),
                if (!series.isEmpty && !Money.maskAmounts) ...[
                  const SizedBox(height: 14),
                  ExampleBalanceChart(
                    series: series,
                    currency: portfolio.currency,
                    // Home's one arrival, seen on a second surface: the line
                    // draws itself on the same flag the balance settles on.
                    arrived: settled,
                    animate: _ChartAnimationScope.of(context),
                  ),
                ] else if (!Money.maskAmounts &&
                    series.description != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    series.description!,
                    style: TextStyle(
                      fontSize: 12 * context.brandDesign.typographyScale,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            // 6 px, not 0: the discs still need to clear the panel's own
            // corner radius, and a control that touches a rounded edge looks
            // like it fell out of the panel.
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: _QuickActionsRow(snapshot: snapshot, ref: ref),
          ),
        ],
      ),
    );
    // The screen's single sweep, on the screen's single hero. Its default
    // angle lights the upper-right rim, which is the same corner the frosted
    // material's own top highlight runs along, so the two read as one object
    // catching one light rather than as two stray rules.
    //
    // Measured on the frosted ground, worst stop of each theme: the balance
    // 13.84:1 Twilight / 15.78:1 daylight, its cents 8.90 / 8.79, the symbol
    // 7.73 / 7.18, and the un-settled arrival ink 7.07 / 7.18 — the moment is
    // legible from its first frame, which it has to be, because it only
    // plays once.
    return DecoratedBox(
      // The hero's own seating. On Twilight this is a violet bloom under the
      // panel, so the balance looks lit from within rather than pasted on; in
      // daylight `glowOf` returns the ambient plus a 45 percent bloom, which
      // is the difference between a card that rests on paper and one that is
      // printed on it. Daylight materiality was this screen's worst score.
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
}

/// The Home balance. [ExampleAmountSize.medium] volume, Geist, tabular figures,
/// the currency symbol a step quieter and the cents a step smaller, so the
/// number reads as one object with three weights instead of one flat string.
///
/// It formats through [Money] rather than [ExampleAmount] because private mode
/// is a data contract: `Money.formatAmount` is the single path that returns
/// the masked form, and a hero that bypassed it would print a balance the
/// customer had just hidden.
class _HeroAmount extends StatelessWidget {
  const _HeroAmount({
    required this.currency,
    required this.amount,
    required this.settled,
  });

  final String currency;
  final double? amount;

  /// False until the route transition has finished; the amount arrives in
  /// secondary ink and settles into primary.
  final bool settled;

  /// Cents relative to the whole number, and the symbol's weight relief.
  static const double _fractionScale = .54;

  @override
  Widget build(BuildContext context) {
    final base = ExampleTextStyles.amount(
      context,
      size: ExampleAmountSize.medium,
    );
    final ink =
        settled ? ExampleInk.primary(context) : ExampleInk.secondary(context);
    final Widget number;
    if (amount == null) {
      number = Text('—', style: base.copyWith(color: ink));
    } else {
      final formatted = _money(currency, amount!);
      final dot = formatted.lastIndexOf('.');
      final whole = dot < 0 ? formatted : formatted.substring(0, dot);
      final fraction = dot < 0 ? '' : formatted.substring(dot);
      // The symbol is a label, not a digit: at full weight it competes with
      // the first numeral for the eye's entry point.
      final symbolEnd = _symbolEnd(whole);
      number = Text.rich(
        TextSpan(
          style: base.copyWith(color: ink),
          children: [
            if (symbolEnd > 0)
              TextSpan(
                text: whole.substring(0, symbolEnd),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: ink.withValues(alpha: .72),
                ),
              ),
            TextSpan(text: whole.substring(symbolEnd)),
            if (fraction.isNotEmpty)
              TextSpan(
                text: fraction,
                style: TextStyle(
                  fontSize: base.fontSize! * _fractionScale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0,
                  color: ink.withValues(alpha: .78),
                ),
              ),
          ],
        ),
        maxLines: 1,
        softWrap: false,
      );
    }
    // A balance steps down a size rather than truncating: an ellipsised
    // number is a wrong number. scaleDown only ever shrinks, so the common
    // case renders at the full 26 px.
    final sized = SizedBox(
      height: base.fontSize! * base.height!,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: number,
      ),
    );
    return Semantics(
      liveRegion: false,
      label: amount == null
          ? context.tr('Total balance unavailable')
          : context.tr('Total balance {p0}', {'p0': _money(currency, amount!)}),
      excludeSemantics: true,
      // The one moment: ink only. Same glyphs, same box, same position, so
      // nothing on the screen moves while it settles.
      child: ExampleStateSwitch(
        alignment: Alignment.centerLeft,
        child: KeyedSubtree(key: ValueKey(settled), child: sized),
      ),
    );
  }

  /// Length of the leading currency symbol, if the formatter put one there.
  /// Digits, a masked bullet run and a minus sign all end the symbol.
  static int _symbolEnd(String value) {
    var index = 0;
    while (index < value.length) {
      final code = value.codeUnitAt(index);
      final isDigit = code >= 0x30 && code <= 0x39;
      if (isDigit || code == 0x2022 || code == 0x2D) break;
      index++;
    }
    return index;
  }
}

/// Every account on one surface. [ExampleListGroup] draws the group's own
/// hairlines, so the rows carry none of their own and the amounts land in a
/// single right-aligned tabular column.
class _AccountsGroup extends StatelessWidget {
  const _AccountsGroup({required this.rows, required this.snapshot});

  final List<_AccountRowData> rows;
  final HoppaDashboardSnapshot snapshot;

  // The group seats itself on paper: `ExampleListGroup` already puts
  // `ambientLight` under its *surface* and nothing under its heading. The
  // outer shadow this widget used to add did the same job a second time,
  // over the wrong silhouette — the rounded rect covered the section title
  // too, so daylight printed a soft halo around the word "Accounts" and a
  // doubled edge under the rows. One shadow, on the object that casts it.
  @override
  Widget build(BuildContext context) => ExampleListGroup(
        title: context.tr('Accounts'),
        action: context.tr('View all'),
        onAction: () => context.go(
          snapshot.fiatEnabled ? AppRoutes.money : AppRoutes.walletAssets,
        ),
        children: [
          for (final row in rows) _AccountListRow(row: row),
        ],
      );
}

class _AccountListRow extends StatelessWidget {
  const _AccountListRow({required this.row});

  final _AccountRowData row;

  @override
  Widget build(BuildContext context) => ExampleRow(
        title: row.title,
        titleMaxLines: 2,
        subtitle: row.subtitle,
        leading: row.avatar,
        onTap: () => context.go(row.route),
        // The trailing caption is the row's qualifier — the 30-day
        // change, the currency, or the word "Estimated" — and it was
        // painted but never announced, so a screen reader heard an
        // estimate as an exact balance.
        semanticsLabel: row.trailing.isEmpty
            ? '${row.title}, ${row.amount}, ${row.subtitle}'
            : '${row.title}, ${row.amount}, ${row.subtitle}, '
                '${row.trailing}',
        trailing: ExampleRowValue(
          value: row.amount,
          caption: row.trailing.isEmpty ? null : row.trailing,
        ),
      );
}

/// Member transfers open the existing send/request hub. Business accounts
/// retain the payments flow.
Future<void> _openSend(
  BuildContext context,
  WidgetRef ref,
  HoppaDashboardSnapshot snapshot,
) async {
  if (snapshot.isBusinessAccount) {
    context.go(AppRoutes.pay);
    return;
  }
  context.go(AppRoutes.peer);
}

Future<void> _openDeposit(
  BuildContext context,
  WidgetRef ref,
  HoppaDashboardSnapshot snapshot,
) async {
  if (snapshot.isBusinessAccount) {
    context.go(AppRoutes.payments);
    return;
  }
  await openCryptoDeposit(context, ref);
}

/// Send / Request / Exchange / Buy / Deposit, shared by phone and desktop
/// balance panels.
class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({required this.snapshot, required this.ref});

  final HoppaDashboardSnapshot snapshot;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          _HomeAction(
            icon: Icons.north_east_rounded,
            label: context.tr('Send'),
            enabled: snapshot.outflowsEnabled || snapshot.fiatEnabled,
            onTap: () => _openSend(context, ref, snapshot),
          ),
          _HomeAction(
            icon: Icons.south_west_rounded,
            label: context.tr('Request'),
            enabled: snapshot.outflowsEnabled && !snapshot.isBusinessAccount,
            onTap: () => context.go(AppRoutes.peerRequest),
          ),
          _HomeAction(
            icon: Icons.swap_horiz_rounded,
            label: context.tr('Exchange'),
            enabled: snapshot.exchangeEnabled,
            onTap: () => context.go(AppRoutes.walletExchange),
          ),
          _HomeAction(
            icon: Icons.add_rounded,
            label: context.tr('Buy'),
            enabled: !snapshot.isBusinessAccount,
            onTap: () => showBuyCryptoSheet(context),
          ),
          _HomeAction(
            icon: Icons.download_rounded,
            label: context.tr('Deposit'),
            enabled: true,
            onTap: () => _openDeposit(context, ref, snapshot),
          ),
        ],
      );
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Center(
          child: ExampleCircleAction(
            icon: icon,
            label: label,
            onTap: enabled ? onTap : null,
          ),
        ),
      );
}

/// Home's card shelf.
///
/// The teaser used to be a bordered night-gradient banner with the artwork
/// tucked inside it — a card drawn inside a card, which is the one
/// composition this system rejects outright. [ExamplePaymentCard] already
/// carries its own rim, its own violet bloom and its own wordmark: it is a
/// finished object, and a shelf's job is to stand it up, not to frame it a
/// second time. Two rounded rectangles at two radii, one inside the other,
/// also put a third edge on a screen that spends its edge budget on the hero.
///
/// Dropping the frame is the largest daylight-materiality win left here.
/// Framed, the artwork was a dark rectangle inside a dark rectangle and paper
/// never saw an object at all; standing on the page it is the only dark thing
/// on pearl, so its bloom and its 1 px rim finally read as a real card
/// resting on a real ground — the exact contrast daylight was scored down
/// for. The label comes off the artwork at the same time and takes page ink
/// instead of being pinned to pearl because it had been floating on night:
/// on the page ground that is 16.99:1 daylight / 17.14:1 Twilight for the
/// title and 7.49:1 / 7.98:1 for the meta line, where the framed version had
/// one fixed pair of values that were only ever correct on night.
class _HomeCardShelf extends ConsumerStatefulWidget {
  const _HomeCardShelf({required this.card});

  final PaymentCard? card;

  @override
  ConsumerState<_HomeCardShelf> createState() => _HomeCardShelfState();
}

class _HomeCardShelfState extends ConsumerState<_HomeCardShelf> {
  bool _opening = false;

  Future<void> _topUp() async {
    final card = widget.card;
    if (_opening || card == null || card.status != CardStatus.active) return;
    setState(() => _opening = true);
    try {
      await showCardTopUp(context, ref, card);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSectionTitle(
          title: context.tr('Your card'),
          action: context.tr('All cards'),
          onAction: () => context.go(AppRoutes.cards),
        ),
        const SizedBox(height: 4),
        _CardTeaser(
          card: card,
          onTap: () => context.go(card == null
              ? AppRoutes.cards
              : AppRoutes.cardsWithSelection(card.id)),
        ),
        if (card != null) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ExampleGlassButton(
              label: context.tr('Top up card'),
              icon: Icons.add_rounded,
              height: 44,
              expand: false,
              loading: _opening,
              onPressed:
                  card.status == CardStatus.active && !_opening ? _topUp : null,
              semanticsLabel: card.status == CardStatus.active
                  ? context.tr('Top up {p0}, ending {p1}',
                      {'p0': card.displayLabel, 'p1': card.last4})
                  : context.tr(
                      'Top up card, unavailable while this card is {p0}',
                      {'p0': card.status.name}),
            ),
          ),
        ],
      ],
    );
  }
}

class _CardTeaser extends StatelessWidget {
  const _CardTeaser({required this.card, required this.onTap});

  final PaymentCard? card;
  final VoidCallback onTap;

  /// 1.576, within a hair of the 1.586 ISO card ratio, at the smallest size
  /// where the wordmark printed on the artwork is still a wordmark. The old
  /// 90 x 57 slot read as a swatch of the card rather than as the card.
  static const double _artworkWidth = 104;
  static const double _artworkHeight = 66;

  @override
  Widget build(BuildContext context) {
    final title = card == null
        ? context.tr('{p0} Card', {
            'p0': AppDesignTheme.nameOf(context).isEmpty
                ? 'Payment'
                : AppDesignTheme.nameOf(context)
          })
        : card!.displayLabel;
    final meta = card == null
        ? context.tr('Explore available cards')
        : [
            context.tr(card!.virtual ? 'Virtual' : 'Physical'),
            if (card!.network.isNotEmpty) card!.network,
            // "ending 1234", not "•• 1234". The mask was two U+2022 in
            // whatever family `branding.fontFamily` resolves to — the same
            // glyph exposure the accounts row's arrows had — and a screen
            // reader read it out as "bullet bullet 1234". The word is
            // shorter to say, impossible to render as a missing-glyph box,
            // and the only remaining non-ASCII character on this line is the
            // Latin-1 middot separator.
            if (card!.last4.isNotEmpty)
              context.tr('ending {p0}', {'p0': card!.last4}),
          ].join(' · ');
    final palette = ExamplePalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        // Both washes resolve from the palette rather than from the Material
        // defaults, so the pointer and keyboard states are violet on night
        // and deepened violet on paper instead of the framework's own accent.
        hoverColor: palette.fill.withValues(alpha: .08),
        focusColor: palette.fill.withValues(alpha: .16),
        splashColor: palette.fill.withValues(alpha: .12),
        child: Semantics(
          button: true,
          // One announcement for the whole shelf. Without this the artwork's
          // own image semantics land in the middle of the row and a screen
          // reader says "EXAMPLE Card, Card design, Virtual, Visa".
          label: '$title, $meta',
          excludeSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
            child: Row(
              children: [
                SizedBox(
                  width: _artworkWidth,
                  // The same seam every /cards face goes through, so Home's
                  // thumbnail is the real object in miniature rather than a
                  // second, flatter drawing of it. The outer phone-motion
                  // wrapper owns tilt and the whole row owns the tap, so the
                  // artwork's internal hover transform stays disabled.
                  child: card == null
                      ? Container(
                          height: _artworkHeight,
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.credit_card_outlined,
                            color: ExampleInk.secondary(context),
                          ),
                        )
                      : ExampleTiltCard(
                          maxAngle: .07,
                          child: CardFace(
                            card: card,
                            compact: true,
                            height: _artworkHeight,
                            interactive: false,
                            sweepOnArrival: false,
                          ),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15 * context.brandDesign.typographyScale,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -.1,
                          color: ExampleInk.primary(context),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        meta,
                        // Two lines, because this line is assembled from
                        // known short tokens and growing is the honest
                        // response to text scaling. At 375 and scale 1.0 it
                        // occupies one line with room to spare; at 1.3 the
                        // longest real form — "Virtual · Mastercard · ending
                        // 1234" — used to run past the chevron and lose its
                        // last digits, and a card you identify by its last
                        // four is the one string on this row that must not be
                        // truncated.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12 * context.brandDesign.typographyScale,
                          color: ExampleInk.secondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Secondary rather than tertiary ink: 7.49:1 daylight and
                // 7.98:1 Twilight against the 3:1 floor for a non-text
                // affordance, and it is the only thing marking the row as
                // pressable now that the frame is gone.
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: ExampleInk.secondary(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Smart insights: facts about this calendar month, as ledger rows.
///
/// It used to total every activity the snapshot happened to hold under a
/// "This month" label, which was neither this month nor an insight. Now the
/// month is the month, last month is the comparison when the window reaches
/// it, and the rest is what a customer would actually ask: what came in,
/// where most of it went, the biggest single payment, and what looks like a
/// subscription. Same group, hairlines and amount column as the ledgers.
class _InsightPanel extends StatelessWidget {
  const _InsightPanel({required this.activities});

  final List<HoppaActivity> activities;

  @override
  Widget build(BuildContext context) {
    final insights = SpendingInsights.compute(activities, now: DateTime.now());
    final currency = insights.currency;
    final rows = <Widget>[];
    if (!insights.hasHistory) {
      rows.add(_InsightRow(
        icon: Icons.auto_awesome_outlined,
        title: context.tr('Insights unlock as you transact'),
        subtitle: context.tr('Spending patterns appear here'),
      ));
    } else if (insights.payments == 0) {
      final last = insights.lastMonthSpent;
      rows.add(_InsightRow(
        icon: Icons.payments_outlined,
        title: context.tr('Nothing spent yet this month'),
        subtitle: last != null && last > 0
            ? context
                .tr('Last month you spent {p0}', {'p0': _money(currency, last)})
            : context.tr('Spending patterns appear here'),
      ));
    } else {
      rows.add(_InsightRow(
        icon: Icons.payments_outlined,
        title: context.tr('Spent this month'),
        subtitle: _comparison(context, insights),
        value: _money(currency, insights.spent),
      ));
      if (insights.received > 0) {
        final net = insights.net;
        rows.add(_InsightRow(
          icon: Icons.south_west_rounded,
          title: context.tr('Received this month'),
          subtitle: context.tr('Net {p0}', {
            'p0':
                net >= 0 ? '+${_money(currency, net)}' : _money(currency, net),
          }),
          value: '+${_money(currency, insights.received)}',
          color: ExampleColors.success,
        ));
      }
      final top = insights.topMerchant;
      final largest = insights.largest;
      if (top != null) {
        rows.add(_InsightRow(
          icon: Icons.storefront_outlined,
          title: top.title,
          subtitle:
              context.tr('Top merchant · {p0} payments', {'p0': top.count}),
          value: _money(currency, top.total),
        ));
      }
      final recurring = insights.recurring;
      if (recurring.isNotEmpty) {
        rows.add(_InsightRow(
          icon: Icons.autorenew_rounded,
          title: recurring.first.title,
          subtitle: context.tr('Looks like a monthly payment'),
          value: _money(currency, recurring.first.amount),
        ));
      }
      // The single largest payment, unless it is the only payment (then it
      // is the total) or the top merchant already names it.
      if (largest != null &&
          insights.payments >= 2 &&
          rows.length < 4 &&
          (top == null ||
              top.title.toLowerCase() != largest.title.toLowerCase())) {
        rows.add(_InsightRow(
          icon: Icons.trending_up_rounded,
          title: largest.title,
          subtitle: context.tr('Largest payment'),
          value: _money(currency, largest.amount),
          onTap: () => context.go(AppRoutes.transactionDetail(largest.id)),
        ));
      }
    }
    return ExampleListGroup(
      title: context.tr('Smart insights'),
      action: context.tr('This month'),
      onAction: () => context.go(AppRoutes.activity),
      children: rows,
    );
  }

  /// "12% less than last month", or the payment count when there is no last
  /// month to compare against.
  String _comparison(BuildContext context, SpendingInsights insights) {
    final change = insights.changeFromLastMonth;
    if (change == null) {
      return context.tr(
        insights.payments == 1 ? 'across {p0} payment' : 'across {p0} payments',
        {'p0': insights.payments},
      );
    }
    final percent = change.abs().round();
    if (percent < 1) return context.tr('Same as last month');
    return context.tr(
      change > 0 ? '{p0} more than last month' : '{p0} less than last month',
      {'p0': '$percent%'},
    );
  }
}

/// One insight as a ledger row: a fact on the left, its amount on the right.
class _InsightRow extends StatelessWidget {
  const _InsightRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.value,
    this.color,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? value;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ExampleRow(
        title: title,
        subtitle: subtitle,
        leading: ExampleIconTile(icon: icon, color: color ?? ExampleColors.iris),
        trailing:
            value == null ? null : ExampleRowValue(value: value!, color: color),
        onTap: onTap,
        semanticsLabel:
            value == null ? '$title, $subtitle' : '$title, $value, $subtitle',
      );
}

/// Recent transactions as one ledger.
///
/// The rows used to be four separate glass panels with page showing between
/// them: four identical rounded rectangles stacked down the screen, which is
/// the tell the accounts block was already restructured to avoid, and which
/// on paper is four flat white cards floating on near-white paper. As one
/// hairline-separated group the amounts land in a single right-aligned
/// tabular column, the leading marks share one 40 pt rhythm with the accounts
/// above, and daylight has one seated material instead of four.
class _ActivityGroup extends StatelessWidget {
  const _ActivityGroup({required this.activities});

  final List<HoppaActivity> activities;

  @override
  Widget build(BuildContext context) => ExampleListGroup(
        title: context.tr('Recent transactions'),
        action: context.tr('View all'),
        onAction: () => context.go(AppRoutes.activity),
        children: [
          for (final activity in activities) _ActivityRow(activity: activity),
        ],
      );
}

/// One transaction as a ledger row.
///
/// Credits take the success ink and debits stay on the primary ink, because
/// a column that is entirely green or entirely red carries no information:
/// money arriving is the exception worth marking. Measured on the group
/// surface (darkSurface / lightSurface), alpha-composited first: the title
/// 15.61:1 Twilight and 18.36:1 daylight, the timestamp 7.63:1 / 7.79:1, the
/// debit amount 15.61:1 / 18.36:1 and the credit ink 9.95:1 / 5.11:1. Every
/// one clears the 4.5:1 body floor in both themes.
class _ActivityRow extends ConsumerWidget {
  const _ActivityRow({required this.activity});

  final HoppaActivity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positive = activity.amount > 0;
    final amount =
        '${positive ? '+' : ''}${_money(activity.currency, activity.amount)}';
    final transaction = activity.transaction;
    final identity = transaction == null
        ? null
        : ref.watch(transactionIdentityProvider(transaction));
    final descriptor = [
      activity.timeLabel,
      if (identity != null) identity,
      if (transaction != null)
        if (cardFeeCaption(transaction) case final caption?) caption,
    ];
    return ExampleRow(
      title: activity.title,
      subtitle: descriptor.join('\n'),
      subtitleMaxLines: null,
      leading: ExampleIconTile(
        icon: _activityIcon(activity.kind),
        color: positive ? ExampleColors.success : ExampleColors.iris,
      ),
      onTap: () => context.go(AppRoutes.transactionDetail(activity.id)),
      semanticsLabel: '${activity.title}, $amount, ${descriptor.join(', ')}',
      trailing: ExampleRowValue(
        value: amount,
        color: positive ? ExampleColors.success : null,
      ),
    );
  }
}

// ── Desktop composition ──────────────────────────────────────────────────

class _DesktopSectionTitle extends StatelessWidget {
  const _DesktopSectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: ExampleInk.primary(context),
                fontSize: 17 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text(
                action,
                style: TextStyle(
                  color: ExampleInk.accent(context, ExampleColors.iris),
                  fontSize: 13 * context.brandDesign.typographyScale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      );
}

class _DesktopBalancePanel extends StatelessWidget {
  const _DesktopBalancePanel({
    required this.snapshot,
    required this.ref,
    required this.compact,
    this.greetingTime,
  });

  final HoppaDashboardSnapshot snapshot;
  final WidgetRef ref;
  final bool compact;
  final DateTime? greetingTime;

  /// Corner radius of the panel and of its sweep, which must agree.
  static const double _radius = 24;

  @override
  Widget build(BuildContext context) => _ArrivalSettle(
        builder: (context, settled) => _panel(context, settled),
      );

  Widget _panel(BuildContext context, bool settled) {
    final portfolio = _displayPortfolio(snapshot, ref);
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              context.tr('Total balance'),
              style: TextStyle(
                fontSize: 13 * context.brandDesign.typographyScale,
                color: ExampleInk.secondary(context),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: Money.maskAmounts
                  ? context.tr('Show balances')
                  : context.tr('Hide balances'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              // 44 pt floor, the same as the phone hero's. The wide
              // breakpoint had kept a 28 pt box on the one control that hides
              // a customer's money; a pointer is not a reason to drop below
              // the target minimum, and this screen is also driven by touch
              // on a tablet at this width.
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () => ref.read(privateModeProvider.notifier).toggle(),
              icon: Icon(
                Money.maskAmounts
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 16,
                color: ExampleInk.secondary(context),
              ),
            ),
            const Spacer(),
            DisplayCurrencySelector(currencies: [
              for (final account in snapshot.accounts)
                if (account.provider.toLowerCase().contains('equals'))
                  account.currency,
            ]),
          ],
        ),
        const SizedBox(height: 10),
        // The wide breakpoint gets the same hero object as the phone, not a
        // second amount widget with the same digits: one number at one
        // volume, with the symbol a step quieter, the cents a step smaller,
        // and the same 200 ms settle from secondary to primary ink after the
        // route lands. Home's one moment now belongs to Home, not to a
        // layout branch of it.
        _HeroAmount(
          currency: portfolio.currency,
          amount: portfolio.total,
          settled: settled,
        ),
        const SizedBox(height: 12),
        Text(
          context.tr(portfolio.caption),
          style: TextStyle(
            fontSize: 13 * context.brandDesign.typographyScale,
            fontWeight: FontWeight.w600,
            color: _captionInk(context, portfolio.captionTone),
          ),
        ),
        const SizedBox(height: 22),
        _QuickActionsRow(snapshot: snapshot, ref: ref),
      ],
    );
    final series = ExampleBalanceSeries.fromActivities(
      portfolio.total,
      snapshot.activities,
      currency: portfolio.currency,
      asOf: snapshot.portfolioEstimate?.valuedAt,
      valuationRates: portfolio.valuationRates,
    );
    // Desktop and phone share the rolling monthly history,
    // displayed with the customer's updated chart styling.
    final chart = series.isEmpty || Money.maskAmounts
        ? Align(
            alignment: Alignment.centerLeft,
            child: Text(
              Money.maskAmounts
                  ? context
                      .tr('Balance history hidden while balances are hidden.')
                  : series.description ??
                      'The balance trend appears after your first transactions.',
              style: TextStyle(
                fontSize: 12.5 * context.brandDesign.typographyScale,
                color: ExampleInk.tertiary(context),
              ),
            ),
          )
        : ExampleBalanceChart(
            series: series,
            currency: portfolio.currency,
            arrived: settled,
            animate: _ChartAnimationScope.of(context),
            height: compact ? 132 : 160,
          );
    final panel = ExampleGlassPanel(
      radius: _radius,
      // Frosted, now that `ExampleAtmosphere.home` runs behind the desktop
      // scroll too: a blurred plane with the indigo dawn showing through it
      // is a material at any width. The border drops to zero because the
      // sweep below is the panel's edge, and two 1 px rules at one radius
      // read as a mistake rather than as light.
      material: ExampleGlassMaterial.frosted,
      borderAlpha: 0,
      padding: EdgeInsets.all(compact ? 22 : 28),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [summary, const SizedBox(height: 18), chart],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(width: 360, child: summary),
                const SizedBox(width: 40),
                Expanded(child: chart),
              ],
            ),
    );
    return DecoratedBox(
      // Desktop's hero seating, matching the phone's: a violet bloom under
      // the panel on Twilight, ambient plus a 45 percent bloom on paper. A
      // 1200 px panel with no shadow under it is the flattest object a wide
      // page can hold.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(_radius),
        boxShadow: ExampleShadows.glowOf(
          context,
          ExampleColors.violet,
          alpha: .16,
          blur: 38,
          spread: -16,
          offset: const Offset(0, 14),
        ),
      ),
      child: ExampleSweepBorder(radius: _radius, child: panel),
    );
  }
}

class _DesktopAccountGrid extends StatelessWidget {
  const _DesktopAccountGrid({required this.rows, required this.compact});

  final List<_AccountRowData> rows;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return ExampleGlassPanel(
        child: Text(
          context.tr('Balances will appear after your accounts sync.'),
          style: TextStyle(color: ExampleInk.secondary(context)),
        ),
      );
    }
    final accounts = rows.where((row) => !row.isCryptoCard).toList();
    final crypto = rows.where((row) => row.isCryptoCard).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        // A 3-up grid only works where the item count is a multiple of three
        // or genuinely open-ended. With four accounts it leaves one lone card
        // beside two thirds of a row of dead paper, directly under the page's
        // densest block; two clean rows read as composition instead of as a
        // rendering fault. Counts that divide by three keep the 3-up.
        final columns = compact
            ? 2
            : (accounts.length % 3 == 0 || accounts.length > 6)
                ? 3
                : 2;
        final width = (constraints.maxWidth - 16 * (columns - 1)) / columns;
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final row in accounts)
              SizedBox(
                width: width,
                // One announcement per card, in the order the card is read
                // rather than the order it is built. Without it a screen
                // reader walked the tile bottom-up — qualifier, amount,
                // account name — which is three facts in no relation.
                child: Semantics(
                  button: true,
                  label: row.trailing.isEmpty
                      ? '${row.title}, ${row.amount}, ${row.subtitle}'
                      : '${row.title}, ${row.amount}, ${row.subtitle}, '
                          '${row.trailing}',
                  excludeSemantics: true,
                  child: ExampleGlassPanel(
                    radius: 20,
                    padding: const EdgeInsets.all(20),
                    onTap: () => context.go(row.route),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            row.avatar,
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                row.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5 *
                                      context.brandDesign.typographyScale,
                                  color: ExampleInk.secondary(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          row.amount,
                          style: TextStyle(
                            fontSize: 22 * context.brandDesign.typographyScale,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.6,
                            color: ExampleInk.primary(context),
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5 *
                                      context.brandDesign.typographyScale,
                                  color: ExampleInk.tertiary(context),
                                ),
                              ),
                            ),
                            // The phone shows every row's qualifier under the
                            // amount; the wide grid was dropping it, so at 1440
                            // an estimate and an exact balance printed
                            // identically and the 30-day change disappeared
                            // altogether. Same fact, same tone, same tabular
                            // column — a breakpoint may re-compose the screen,
                            // it may not tell the customer less.
                            if (row.trailing.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Text(
                                row.trailing,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 12.5 *
                                      context.brandDesign.typographyScale,
                                  fontWeight: FontWeight.w600,
                                  color: ExampleInk.secondary(context),
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (crypto.isNotEmpty)
              SizedBox(
                width: constraints.maxWidth,
                child: ExampleListGroup(
                  children: [
                    for (final row in crypto) _AccountListRow(row: row),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DesktopActivityPanel extends StatelessWidget {
  const _DesktopActivityPanel({required this.activities});

  final List<HoppaActivity> activities;

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        radius: 20,
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            for (var index = 0; index < activities.length; index++)
              _DesktopActivityRow(
                activity: activities[index],
                last: index == activities.length - 1,
              ),
          ],
        ),
      );
}

class _DesktopActivityRow extends ConsumerWidget {
  const _DesktopActivityRow({required this.activity, required this.last});

  final HoppaActivity activity;
  final bool last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positive = activity.amount > 0;
    final transaction = activity.transaction;
    final identity = transaction == null
        ? null
        : ref.watch(transactionIdentityProvider(transaction));
    return InkWell(
      onTap: () => context.go(AppRoutes.transactionDetail(activity.id)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: ExampleTheme.isLight(context)
                      ? ExampleBorders.subtleSideOf(context)
                      : BorderSide(
                          color: ExamplePalette.of(context)
                              .borderSubtle
                              .withValues(alpha: .07),
                        ),
                ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: positive
                    ? ExampleInk.tint(context, ExampleColors.success, alpha: .14)
                    : ExampleSurface.of(context, 2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                positive ? Icons.south_rounded : _activityIcon(activity.kind),
                size: 18,
                color: ExampleInk.accent(
                  context,
                  positive ? ExampleColors.success : ExampleColors.lavender,
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    activity.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [activity.subtitle, if (identity != null) identity]
                        .join('\n'),
                    maxLines: null,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5 * context.brandDesign.typographyScale,
                      color: ExampleInk.tertiary(context),
                    ),
                  ),
                ],
              ),
            ),
            // Fixed-width, right-aligned columns so the timestamp and amount
            // line up down the list regardless of amount length.
            SizedBox(
              width: 120,
              child: Text(
                activity.timeLabel,
                maxLines: 2,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5 * context.brandDesign.typographyScale,
                  color: ExampleInk.tertiary(context),
                ),
              ),
            ),
            const SizedBox(width: 24),
            SizedBox(
              width: 156,
              child: Text(
                '${positive ? '+' : ''}${_money(activity.currency, activity.amount)}',
                maxLines: 1,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5 * context.brandDesign.typographyScale,
                  fontWeight: FontWeight.w600,
                  color: positive
                      ? ExampleInk.accent(context, ExampleColors.success)
                      : ExampleInk.primary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Data helpers ─────────────────────────────────────────────────────────

class _PortfolioView {
  const _PortfolioView({
    required this.currency,
    required this.total,
    required this.caption,
    required this.captionTone,
    this.valuationRates = const {},
  });

  final Map<String, double> valuationRates;
  final String currency;
  final double? total;
  final String caption;
  final _CaptionTone captionTone;
}

/// What the balance caption is saying, so the ink can be resolved against
/// whichever ground the caption lands on.
enum _CaptionTone { quiet, neutral, primary }

Color _captionInk(BuildContext context, _CaptionTone tone) => switch (tone) {
      _CaptionTone.quiet => ExampleInk.tertiary(context),
      // Lavender is a caption on night; on paper the same neutral note is the
      // secondary ink, because a pale lavender there reads as a stain.
      _CaptionTone.neutral => ExampleTheme.isLight(context)
          ? ExampleInk.secondary(context)
          : context.brandDesign.color(
              Theme.of(context).brightness,
              'textSecondary',
              fallback: ExampleColors.lavender,
            ),
      _CaptionTone.primary => ExampleInk.primary(context),
    };

/// Balances held on the cards themselves. Hoppa's portfolio estimate only
/// values wallet assets, so these must be added on top of it.
double _cardBalancesIn(HoppaDashboardSnapshot snapshot, String currency) {
  final code = currency.trim().toUpperCase();
  var total = 0.0;
  for (final card in snapshot.cards) {
    if (card.status == CardStatus.cancelled) continue;
    if (card.balance.currency.trim().toUpperCase() != code) continue;
    total += card.balance.minorUnits / 100;
  }
  return total;
}

_PortfolioView _portfolio(HoppaDashboardSnapshot snapshot) {
  if (!snapshot.cardBalancesAvailable) {
    return _PortfolioView(
      currency: snapshot.portfolioEstimate?.baseCurrency ?? 'USD',
      total: null,
      caption: 'Card balances unavailable · pull to refresh',
      captionTone: _CaptionTone.neutral,
    );
  }
  final estimate = snapshot.portfolioEstimate;
  final currencies = snapshot.accounts
      .map((account) => account.currency.trim().toUpperCase())
      .where((currency) => currency.isNotEmpty)
      .toSet();
  final canUseAccountFallback = estimate == null && currencies.length == 1;
  final currency = estimate?.baseCurrency ??
      (canUseAccountFallback ? currencies.single : '');
  final baseTotal = estimate?.total ??
      (canUseAccountFallback
          ? snapshot.accounts.fold<double>(
              0,
              (sum, account) => sum + account.balance,
            )
          : null);
  final total = baseTotal == null || currency.isEmpty
      ? baseTotal
      : baseTotal + _cardBalancesIn(snapshot, currency);
  final unavailable = estimate == null && !canUseAccountFallback;
  final empty = snapshot.accounts.isEmpty &&
      snapshot.holdings.isEmpty &&
      snapshot.cards.isEmpty;
  if (empty) {
    return const _PortfolioView(
      currency: 'USD',
      total: 0,
      caption: 'No balances yet',
      captionTone: _CaptionTone.quiet,
    );
  }
  return _PortfolioView(
    currency: currency,
    total: total,
    valuationRates: {
      ...?estimate?.valuationRates,
      if (currency.isNotEmpty) currency: 1
    },
    caption: unavailable
        ? 'Estimated total unavailable'
        : 'Estimated · accounts and cards',
    captionTone: unavailable ? _CaptionTone.neutral : _CaptionTone.primary,
  );
}

_PortfolioView _displayPortfolio(
    HoppaDashboardSnapshot snapshot, WidgetRef ref) {
  final base = _portfolio(snapshot);
  final currency = ref.watch(homeDisplayCurrencyProvider);
  final quote = ref.watch(homeDisplayRateProvider);
  if (currency == base.currency) return base;
  final rate = base.currency == 'USD' && quote.valueOrNull?.currency == currency
      ? quote.valueOrNull?.rate
      : null;
  return _PortfolioView(
    currency: currency,
    total: rate == null || base.total == null ? null : base.total! * rate,
    caption: rate == null
        ? quote.isLoading
            ? 'Updating balance…'
            : 'Currency estimate unavailable'
        : base.caption,
    captionTone: rate == null ? _CaptionTone.neutral : base.captionTone,
    valuationRates: rate == null
        ? const {}
        : {
            for (final entry in base.valuationRates.entries)
              entry.key: entry.value * rate,
            currency: 1,
          },
  );
}

class _AccountRowData {
  const _AccountRowData({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.trailing,
    required this.avatar,
    required this.route,
    this.isCryptoCard = false,
  });

  final String title;
  final String subtitle;
  final String amount;
  final String trailing;
  final Widget avatar;
  final String route;

  final bool isCryptoCard;
}

List<_AccountRowData> _accountRows(
    BuildContext context, HoppaDashboardSnapshot snapshot) {
  final rows = <_AccountRowData>[];
  final providerTotals = snapshot.portfolioEstimate?.providerTotals ?? const [];
  PortfolioProviderTotal? providerTotal(String alias) {
    for (final total in providerTotals) {
      if (total.provider.toLowerCase().contains(alias) && total.isAvailable) {
        return total;
      }
    }
    return null;
  }

  final fiat = snapshot.accounts.where((account) {
    final provider = account.provider.toLowerCase();
    return provider.contains('equals') ||
        (!provider.contains('interlace') &&
            !provider.contains('crypto card') &&
            !provider.contains('boom') &&
            !provider.contains('exchange'));
  });
  for (final account in fiat) {
    final isEquals = account.provider.toLowerCase().contains('equals');
    final rawName = account.name.trim();
    final name = rawName.isEmpty ||
            const {'main', 'main account'}.contains(rawName.toLowerCase())
        ? '${account.currency.toUpperCase()} account'
        : rawName;
    final identifier = account.maskedIdentifier;
    rows.add(
      _AccountRowData(
        title: isEquals || identifier.isEmpty ? name : '$name · $identifier',
        subtitle: isEquals
            ? context.tr('Fiat account{p0}',
                {'p0': identifier.isEmpty ? '' : ' $identifier'})
            : account.provider.trim().isEmpty
                ? context.tr('Account')
                : account.provider,
        amount: _money(account.currency, account.balance),
        trailing: account.currency.toUpperCase(),
        avatar: _currencyAvatar(account.currency),
        route: Uri(
          path: AppRoutes.money,
          queryParameters: {
            'currency': account.currency.trim().toUpperCase(),
            if (account.budgetId.trim().isNotEmpty)
              'budgetId': account.budgetId.trim(),
          },
        ).toString(),
      ),
    );
  }

  final cryptoCard = snapshot.accounts.where((account) {
    final provider = account.provider.toLowerCase();
    return provider.contains('interlace') || provider.contains('crypto card');
  }).toList();
  if (cryptoCard.isNotEmpty) {
    final byCurrency = <String, double>{};
    for (final account in cryptoCard) {
      byCurrency.update(
        account.currency.toUpperCase(),
        (value) => value + account.balance,
        ifAbsent: () => account.balance,
      );
    }
    for (final currency in const ['USD', 'USDT', 'USDC']) {
      final amount = byCurrency[currency];
      if (amount == null) continue;
      rows.add(
        _AccountRowData(
          title: currency,
          subtitle: context.tr('Crypto card'),
          amount: Money.formatAmount(currency, amount)
              .replaceFirst(' $currency', ''),
          trailing: '${_money('USD', amount)} · ${context.tr('Estimated')}',
          avatar: ExampleCurrencyAvatar(code: currency, size: 32),
          route: AppRoutes.walletBalances,
          isCryptoCard: true,
        ),
      );
    }
  }

  for (final card in snapshot.cards.where(
    (card) => card.status != CardStatus.cancelled,
  )) {
    final digits = card.last4.replaceAll(RegExp(r'\D'), '');
    final last4 = digits.length >= 4 ? digits.substring(digits.length - 4) : '';
    rows.add(
      _AccountRowData(
        title: last4.isEmpty
            ? card.displayLabel
            : '${context.tr('Card')} •••• $last4',
        subtitle: context.tr(card.virtual ? 'Virtual card' : 'Physical card'),
        amount: card.hasReportedBalance
            ? card.balance.formatted
            : context.tr('Balance unavailable'),
        trailing: card.balance.currency.toUpperCase(),
        avatar: SizedBox(
          width: 32,
          height: 32,
          child: Icon(Icons.credit_card_rounded,
              color: ExampleInk.secondary(context), size: 26),
        ),
        route: '${AppRoutes.cards}/${Uri.encodeComponent(card.id)}',
        isCryptoCard: true,
      ),
    );
  }

  final exchange = snapshot.accounts.where((account) {
    final provider = account.provider.toLowerCase();
    return provider.contains('boom') || provider.contains('exchange');
  }).toList();
  final exchangeTotal = providerTotal('boomfi');
  if (exchange.isNotEmpty || exchangeTotal != null) {
    final byCurrency = <String, double>{};
    for (final account in exchange) {
      byCurrency.update(
        account.currency.toUpperCase(),
        (value) => value + account.balance,
        ifAbsent: () => account.balance,
      );
    }
    final primary = byCurrency.entries.isEmpty
        ? null
        : byCurrency.entries.firstWhere(
            (entry) => entry.key == 'USD',
            orElse: () => byCurrency.entries.first,
          );
    rows.add(
      _AccountRowData(
        title: context.tr('Exchange'),
        subtitle: byCurrency.isEmpty
            ? context.tr('Spot balances')
            : '${byCurrency.length} ${byCurrency.length == 1 ? 'balance' : 'balances'}',
        amount: exchangeTotal != null
            ? _money(exchangeTotal.currency, exchangeTotal.total)
            : primary == null
                ? '—'
                : _money(primary.key, primary.value),
        trailing: exchangeTotal != null
            ? context.tr('Estimated')
            : primary == null
                ? ''
                : byCurrency.length == 1
                    ? primary.key
                    : '+${byCurrency.length - 1} more',
        avatar: const _ExchangeAvatar(),
        route: AppRoutes.walletExchange,
      ),
    );
  }
  return rows;
}

String _membershipLabel(BuildContext context, HoppaDashboardSnapshot snapshot,
        PlatformResource? tier) =>
    snapshot.isBusinessAccount
        ? context.tr('Business account')
        : tier == null
            ? context.tr('Member')
            : context.tr('{p0} tier', {'p0': tierTitleOf(tier)});

String _longDate(BuildContext context, DateTime date) {
  const days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${context.tr(days[date.weekday - 1])}, ${date.day} ${context.tr(months[date.month - 1])}';
}

/// Currency marks for the account rows, with one code intercepted.
///
/// `ExampleCurrencyAvatar`'s BTC branch draws the Bitcoin sign U+20BF as text
/// in no named family. That codepoint is in neither bundled Geist subset, so
/// on web it resolves to whatever the engine happens to hold and renders as a
/// notdef box. Until the shared painter draws the mark as a path, Home spells
/// the ticker instead — every glyph in "BTC" is in the subset, and a monogram
/// on the coin's own hue still reads as Bitcoin. Measured: 5.70:1 on the
/// Twilight disc, 4.92:1 on the daylight one — the ticker is body-grade in
/// both, where a notdef box carried no information at any ratio.
Widget _currencyAvatar(String code) => code.trim().toUpperCase() == 'BTC'
    ? const _TickerAvatar(code: 'BTC', hue: ExampleColors.bitcoin)
    : ExampleCurrencyAvatar(code: code);

/// A ticker on its own hue, for assets with no drawn mark.
class _TickerAvatar extends StatelessWidget {
  const _TickerAvatar({required this.code, required this.hue});

  final String code;
  final Color hue;

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: code,
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: ExampleInk.tint(context, hue, alpha: .20),
          ),
          child: Text(
            code,
            style: TextStyle(
              // `accent` returns the hue untouched on Twilight and deepens it
              // for paper, so the ticker carries text on both grounds.
              color: ExampleInk.accent(context, hue),
              fontSize: 9 * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w700,
              height: 1,
              letterSpacing: .2,
            ),
          ),
        ),
      );
}

/// The one account row with no currency of its own. It resolves its own ink,
/// because the rows are built outside the widget tree.
class _ExchangeAvatar extends StatelessWidget {
  const _ExchangeAvatar();

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ExampleInk.tint(context, ExampleColors.teal, alpha: .16),
        ),
        child: Icon(
          Icons.swap_horiz_rounded,
          size: 16,
          color: ExampleInk.accent(context, ExampleColors.teal),
        ),
      );
}

IconData _activityIcon(HoppaActivityKind kind) => switch (kind) {
      HoppaActivityKind.card => Icons.credit_card_rounded,
      HoppaActivityKind.transfer => Icons.north_east_rounded,
      HoppaActivityKind.crypto => Icons.swap_horiz_rounded,
      HoppaActivityKind.deposit => Icons.south_rounded,
      HoppaActivityKind.account => Icons.account_balance_rounded,
    };

String _greeting([DateTime? time]) {
  final hour = (time ?? DateTime.now()).hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String _firstName(String name) {
  final value = name.trim();
  return value.isEmpty ? 'there' : value.split(RegExp(r'\s+')).first;
}

/// Every amount on Home goes through [Money], never through a local
/// formatter: it is the one path that returns the masked form while private
/// mode is on, and a screen that formatted its own digits would print a
/// balance the customer had just hidden.
String _money(String currency, double amount) =>
    Money.formatAmount(currency, amount);

/// Personal accounts that still need identity verification or a tier see a
/// setup banner; the first time per session Home opens the setup screen.
class _AccountSetupBanner extends ConsumerWidget {
  const _AccountSetupBanner({required this.snapshot});

  final HoppaDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (snapshot.isBusinessAccount) return const SizedBox.shrink();
    final tier = ref.watch(currentTierProvider);
    final tierKnown = tier.hasValue || tier.hasError;
    // Only an answered lookup with no tier counts; a failed request must not
    // push a fully set-up customer back into account setup.
    final needsTier = tier.hasValue && tier.valueOrNull == null;
    final needsSetup = snapshot.requiresKyc || needsTier;
    if (!needsSetup) return const SizedBox.shrink();

    final prompted = ref.watch(accountSetupPromptedProvider);
    final dismissed = ref.watch(accountSetupDismissedProvider);
    if (!prompted && !dismissed && tierKnown && needsTier) {
      ref.read(accountSetupPromptedProvider.notifier).state = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted && GoRouter.maybeOf(context) != null) {
          context.go(AppRoutes.accountSetup);
        }
      });
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ExampleGlassPanel(
        radius: 18,
        borderAlpha: .34,
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        onTap: () => context.go(AppRoutes.accountSetup),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExampleInk.tint(context, ExampleColors.violet, alpha: .22),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.verified_user_outlined,
                size: 19,
                color: ExampleInk.accent(context, ExampleColors.lavender),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Finish setting up your account'),
                    style: TextStyle(
                      fontSize: 14 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snapshot.requiresKyc && needsTier
                        ? context.tr(
                            'Verify your identity and choose a tier to unlock cards.')
                        : snapshot.requiresKyc
                            ? context.tr(
                                'Verify your identity to unlock cards and payments.')
                            : context.tr(
                                'Choose a tier to set your limits and unlock cards.'),
                    style: TextStyle(
                      fontSize: 12.5 * context.brandDesign.typographyScale,
                      color: ExampleInk.secondary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: ExampleInk.tertiary(context),
            ),
          ],
        ),
      ),
    );
  }
}

/// One-time prompt after sign-in: biometrics are available on this device but
/// not turned on yet. "Enable" runs the same flow as Settings.
class _BiometricNudge extends ConsumerWidget {
  const _BiometricNudge();

  static bool _dismissedThisSession = false;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (_dismissedThisSession) {
      return const SizedBox.shrink();
    }
    final capability = ref.watch(biometricCapabilityProvider).valueOrNull;
    final enrollment = ref.watch(biometricEnrollmentProvider).valueOrNull;
    if (capability == null || enrollment == null) {
      return const SizedBox.shrink();
    }
    if (!capability.available || enrollment.canUnlock) {
      return const SizedBox.shrink();
    }
    final label = kIsWeb ? 'Passkey' : capability.describe();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: ExampleGlassPanel(
        radius: 18,
        borderAlpha: .34,
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ExampleInk.tint(context, ExampleColors.iris, alpha: .22),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                kIsWeb ? Icons.key_rounded : Icons.fingerprint_rounded,
                size: 20,
                color: ExampleInk.accent(context, ExampleColors.pearl),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('Turn on {p0} sign-in', {'p0': label}),
                    style: TextStyle(
                      color: ExampleInk.primary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5 * context.brandDesign.typographyScale,
                    ),
                  ),
                  Text(
                    context.tr(
                        'Unlock the app and confirm payments without typing your password.'),
                    style: TextStyle(
                      color: ExampleTheme.isLight(context)
                          ? ExampleInk.secondary(context)
                          : ExamplePalette.of(context)
                              .ink
                              .withValues(alpha: .66),
                      fontSize: 12 * context.brandDesign.typographyScale,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            // The nudge's decisive action, on the shared glass button. The
            // hand-rolled FilledButton was pinned to a 36 pt minimum, 8 pt
            // under the target floor, and inked itself from the Material
            // scheme rather than from the palette, so daylight got the
            // framework's accent instead of the deepened violet. `ground` is
            // left at `surface`: the button sits on a glass panel that has
            // already blurred what is behind it, and a second bounded blur
            // there would only cost a layer.
            ExampleGlassButton(
              label: context.tr('Enable'),
              expand: false,
              // 15 px of label plus 14 either side is 77.6 px wide at 375,
              // which leaves the description column 141 px to wrap into —
              // it wraps, it never truncates.
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              onPressed: () async {
                final enabled = await enableBiometricSignIn(
                  context,
                  ref,
                  label: label,
                );
                if (enabled) {
                  _dismissedThisSession = true;
                }
                ref.invalidate(biometricEnrollmentProvider);
              },
            ),
            IconButton(
              tooltip: context.tr('Not now'),
              visualDensity: VisualDensity.compact,
              // Compact density shrinks the default 48 pt box to 40; stating
              // the constraints puts the dismiss control back on the floor.
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              onPressed: () {
                _dismissedThisSession = true;
                ref.invalidate(biometricEnrollmentProvider);
              },
              icon: Icon(
                Icons.close,
                size: 18,
                color: ExampleTheme.isLight(context)
                    ? ExampleInk.tertiary(context)
                    : ExamplePalette.of(context).ink.withValues(alpha: .6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
