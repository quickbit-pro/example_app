import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/branding/app_design.dart';
import '../../../shared/shared.dart';
import '../../auth/presentation/example_otp_field.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/onboarding_banking_screen.dart';
import '../../wallets/domain/wallet_models.dart';
import '../../wallets/presentation/wallets_screen.dart';
import '../domain/payment_balance_options.dart';
import 'accounts_hub_header.dart';
import '../domain/balance_value_order.dart';

enum MoneyTab { accounts, pay, payees }

class MoneyScreen extends ConsumerStatefulWidget {
  const MoneyScreen({
    this.initialTab = MoneyTab.accounts,
    this.initialBudgetId = '',
    this.initialCurrency = '',
    super.key,
  });

  final MoneyTab initialTab;
  final String initialBudgetId;
  final String initialCurrency;

  @override
  ConsumerState<MoneyScreen> createState() => _MoneyScreenState();
}

class _MoneyScreenState extends ConsumerState<MoneyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      initialIndex: widget.initialTab.index,
      vsync: this,
    )..addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_handleTabChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = ref.watch(dashboardProvider);
    final budgets = ref.watch(budgetsProvider);
    final kycStatus = ref.watch(kycDetailedStatusProvider);
    final tenantConfig = ref.watch(mobileTenantConfigProvider);
    final platformAction = ref.watch(platformActionControllerProvider);
    final valuationRates =
        ref.watch(portfolioEstimateProvider).valueOrNull?.valuationRates ??
            const <String, double>{};
    // Crypto-only installations have no fiat accounts: the Accounts tab is
    // the wallet view, so any deep link here goes there instead of the bank
    // onboarding gate.
    if (tenantConfig.valueOrNull?.equalsMoneyEnabled == false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.walletAssets);
      });
      return const Scaffold(body: SizedBox.shrink());
    }
    final disclosure = resolveEqualsPaymentServicesDisclosure(
      localeCountryCode:
          WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '',
      defaultRegion:
          tenantConfig.valueOrNull?.equalsRegulatoryRegionDefault ?? 'EU',
      euDisclosure: tenantConfig.valueOrNull?.equalsRegulatoryDisclaimerEu,
      ukDisclosure: tenantConfig.valueOrNull?.equalsRegulatoryDisclaimerUk,
    );

    ref.listen(bankingActionControllerProvider, (previous, next) {
      // Ignore the notifier's initial build; only react to real actions.
      if (previous?.isLoading != true || previous?.hasValue != true) {
        return;
      }
      next.whenOrNull(
        data: (_) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Request submitted'))),
        ),
        error: (error, stackTrace) =>
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        ),
      );
    });

    final screen = Scaffold(
      body: kycStatus.when(
        data: (detailedStatus) {
          final personal =
              dashboard.valueOrNull?.profile.isBusinessAccount != true;
          // Money needs Equals Money onboarding, but the crypto side does not:
          // keep the Money / Crypto switch on top so Interlace customers can
          // still reach their wallets.
          final gateHeader = AccountsHubHeader(
            selected: AccountsHubSection.money,
            showMoney: tenantConfig.valueOrNull?.equalsMoneyEnabled ?? true,
            showCrypto: personal,
            showExchange: personal &&
                tenantConfig.valueOrNull?.boomFiExchangeEnabled == true,
          );
          if (detailedStatus.requiresEqualsMoneyAction) {
            return _EqualsMoneyActionRequired(
              status: detailedStatus,
              header: gateHeader,
            );
          }

          return dashboard.when(
            data: (snapshot) {
              if (!snapshot.canUseBanking) {
                return _BankingRequired(
                  onContinue: () => context.go('/onboarding/banking'),
                  header: gateHeader,
                );
              }

              final isBusinessAccount = snapshot.profile.isBusinessAccount;
              final exchangeEnabled = isBusinessAccount
                  ? snapshot.canUseBanking
                  : tenantConfig.valueOrNull?.boomFiExchangeEnabled == true;
              final isExample = context.isExampleTheme;
              final width = MediaQuery.sizeOf(context).width;
              final desktop = isExample && width >= (kIsWeb ? 600 : 760);
              return Scaffold(
                appBar: AppBar(
                  title: Text(context.tr('Accounts')),
                  actions: [
                    RefreshAction(onRefresh: () async {
                      ref.invalidate(budgetsProvider);
                      ref.invalidate(accountsProvider);
                      ref.invalidate(equalsBankingInfoProvider);
                      ref.invalidate(payeesProvider);
                      await Future.wait([
                        ref.read(budgetsProvider.future),
                        ref.read(accountsProvider.future),
                        ref.read(payeesProvider.future),
                      ]);
                    }),
                    if (!desktop) ...[
                      IconButton(
                        tooltip: context.tr('Settings'),
                        onPressed: () => context.go('/profile'),
                        icon: const Icon(Icons.settings_outlined),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
                body: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: AccountsHubHeader(
                        selected: AccountsHubSection.money,
                        showMoney:
                            tenantConfig.valueOrNull?.equalsMoneyEnabled ??
                                true,
                        showCrypto: !isBusinessAccount,
                        showExchange: exchangeEnabled,
                      ),
                    ),
                    SizedBox(height: isExample ? 14 : 18),
                    if (isExample && widget.initialTab == MoneyTab.accounts) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _ExampleMoneyOverview(
                          totalBalance: snapshot.totalBalance,
                          balances: _equalsOverviewBalances(
                            snapshot,
                            budgets.valueOrNull ?? const [],
                            valuationRates,
                          ),
                          canConvert: canConvertEqualsMoneyBudgets(
                            budgets.valueOrNull ?? const [],
                          ),
                          onAddMoney: () =>
                              showEqualsMoneyAddMoneyDialog(context),
                          onConvert: () => showEqualsMoneyConversionDialog(
                            context,
                            ref,
                            budgets.valueOrNull ?? const [],
                          ),
                          onCreateBudget: platformAction.isLoading
                              ? null
                              : () => showCreateEqualsBudgetDialog(
                                    context,
                                    ref,
                                  ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // The safeguarding note shares the heading's line: it
                      // is a footnote to the balances above, not a section.
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        // Weighted so the note keeps its natural width at
                        // 375 and only starts to ellipsise past a 1.3 text
                        // scale, while the heading can never be pushed off
                        // the line.
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _MoneySectionHeadline(
                                  title: context.tr('My accounts')),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            const Flexible(
                              flex: 3,
                              child: SafeguardingStatementButton(),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _EqualsMoneyHeader(
                          disclosure: disclosure,
                          isCreating: platformAction.isLoading,
                          canConvert: canConvertEqualsMoneyBudgets(
                            budgets.valueOrNull ?? const [],
                          ),
                          onConvert: () => showEqualsMoneyConversionDialog(
                            context,
                            ref,
                            budgets.valueOrNull ?? const [],
                          ),
                          onCreateBudget: () =>
                              showCreateEqualsBudgetDialog(context, ref),
                        ),
                      ),
                      EqualsMoneyTabBar(controller: _tabController),
                    ],
                    Expanded(
                      child: isExample && widget.initialTab == MoneyTab.accounts
                          ? WalletsScreen(
                              initialView: WalletView.balances,
                              embedded: true,
                              initialBudgetId: widget.initialBudgetId,
                              initialCurrency: widget.initialCurrency,
                            )
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                WalletsScreen(
                                  initialView: WalletView.balances,
                                  embedded: true,
                                  initialBudgetId:
                                      widget.initialTab == MoneyTab.accounts
                                          ? widget.initialBudgetId
                                          : '',
                                  initialCurrency:
                                      widget.initialTab == MoneyTab.accounts
                                          ? widget.initialCurrency
                                          : '',
                                ),
                                _PaymentForm(
                                  initialAccountId: widget.initialBudgetId,
                                ),
                                const _PayeesView(),
                              ],
                            ),
                    ),
                  ],
                ),
              );
            },
            error: (error, stackTrace) => _MoneyErrorState(
              error: error,
              onRetry: () => ref.invalidate(dashboardProvider),
            ),
            loading: () => LoadingState(label: context.tr('Loading accounts')),
          );
        },
        error: (error, stackTrace) => _MoneyErrorState(
          error: error,
          onRetry: () => ref.invalidate(kycDetailedStatusProvider),
        ),
        loading: () =>
            LoadingState(label: context.tr('Checking onboarding status')),
      ),
    );
    // The alive layer is one scope per screen. The banking shell provides it
    // on the tabbed routes; on the routes that mount this screen on its own
    // there is none, and the two allowed hosts here — the hero panel's top
    // hairline and the section headline — would fall back to their static
    // highlight. ExampleAliveLayer asks `existsAbove`, which is the only
    // correct question: `maybeOf` reports null for a scope that is switched
    // *off*, so asking it here would nest a fresh enabled scope under a
    // deliberately disabled one and defeat the kill switch.
    return ExampleAliveLayer(enabled: context.isExampleTheme, child: screen);
  }
}

/// Funded balances shown in the Accounts overview: the dashboard accounts
/// when they carry money, otherwise the Fiat account budget balances.
List<Money> _equalsOverviewBalances(
  DashboardSnapshot snapshot,
  List<PlatformResource> budgets,
  Map<String, double> valuationRates,
) {
  // Budgets are the source of truth the Accounts list renders; their rows
  // are deduped because the API repeats a balance under several keys.
  final fromBudgets =
      equalsBudgetBalances(budgets, valuationRates: valuationRates);
  if (fromBudgets.isNotEmpty) return fromBudgets;

  final byCurrency = <String, int>{};
  void add(Money money) {
    final code = money.currency.trim().toUpperCase();
    if (code.isEmpty || money.minorUnits == 0) return;
    byCurrency.update(code, (value) => value + money.minorUnits,
        ifAbsent: () => money.minorUnits);
  }

  for (final account in snapshot.accounts) {
    if (account.provider != 'EqualsMoney') continue;
    if (account.currencyBalances.isEmpty) {
      add(account.balance);
    } else {
      final seen = <String>{};
      for (final money in account.currencyBalances) {
        if (seen.add('${money.currency}:${money.minorUnits}')) add(money);
      }
    }
  }
  if (byCurrency.isEmpty) {
    for (final budget in budgets) {
      for (final key in const ['balances', 'Balances', 'currencyBalances']) {
        final rows = budget.metadata[key];
        if (rows is! List) continue;
        for (final row in rows.whereType<Map>()) {
          final currency = (row['currency'] ?? row['Currency'])?.toString();
          final amount = row['available'] ??
              row['Available'] ??
              row['amount'] ??
              row['Amount'] ??
              row['balance'] ??
              row['Balance'];
          if (currency == null || amount == null) continue;
          add(Money.fromJson({'currency': currency, 'amount': amount}));
        }
      }
    }
  }
  final ordered = byCurrency.entries.toList()
    ..sort((a, b) => compareBalanceValues(
        a.key, a.value / 100, b.key, b.value / 100, valuationRates));
  return [
    for (final entry in ordered)
      Money(currency: entry.key, minorUnits: entry.value),
  ];
}

/// Centres a Example state composition and lets it scroll rather than overflow.
///
/// A pane at 375 x 812 holds a glyph, a headline, a body and a button at a 1.0
/// text scale and not at 1.3, so the composition scrolls inside the centre: it
/// stays optically centred while it fits and stays reachable when it does not.
/// No padding of its own — the composition already carries 24 / 32 and caps its
/// measure at 320.
Widget _centredState(Widget child) => Center(
      child: SingleChildScrollView(child: child),
    );

/// Nothing-here state for this screen.
///
/// The shared [EmptyState] paints a Twilight card under *any* Example theme —
/// `darkSurface`, an iris wash and an iris glyph, all named as dark literals —
/// so on paper it lands as a near-black slab with a 2.7:1 glyph. Until that
/// shared widget resolves per brightness, Example goes through the vocabulary's
/// own [ExampleEmptyState], whose ink is re-earned for daylight. Every other
/// brand gets the shared composition unchanged.
class _MoneyEmptyState extends StatelessWidget {
  const _MoneyEmptyState({
    required this.title,
    required this.message,
    required this.icon,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) => context.isExampleTheme
      ? _centredState(
          ExampleEmptyState(icon: icon, title: title, body: message),
        )
      : EmptyState(title: title, message: message, icon: icon);
}

/// Failure state for this screen, for the same reason as [_MoneyEmptyState]:
/// the shared [ErrorState] renders through [EmptyState] and inherits its
/// Twilight card. [ExampleErrorState] announces itself in a live region and
/// takes the danger ink of the active theme.
///
/// The gateway warm-up case is kept verbatim: 502/503/504 right after
/// registration means the account is still being provisioned, not that
/// anything is broken, and the customer is told to wait rather than to retry
/// into the same wall.
class _MoneyErrorState extends StatelessWidget {
  const _MoneyErrorState({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  bool get _providerWarmingUp =>
      error is DioException &&
      const {502, 503, 504}
          .contains((error as DioException).response?.statusCode);

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) {
      return ErrorState(error: error, onRetry: onRetry);
    }
    if (_providerWarmingUp) {
      // Provisioning is a wait, not a failure: the empty composition tints its
      // glyph with the accent, where the error composition would put a danger
      // red on a screen where nothing has gone wrong.
      return _centredState(
        ExampleEmptyState(
          icon: Icons.hourglass_top_rounded,
          title: context.tr('Your account is being set up'),
          body: context.tr(
              'This usually takes a minute right after registration. Please wait a moment and try again.'),
          actionLabel: onRetry == null ? null : context.tr('Try again'),
          onAction: onRetry,
        ),
      );
    }
    return _centredState(
      ExampleErrorState(error: error, onRetry: onRetry),
    );
  }
}

/// The Money hub hero: the one balance the screen is about, on a panel that
/// carries its own light.
///
/// Composition, all vocabulary. A bounded [ExampleAtmosphere] gives the panel a
/// ground that is lit rather than filled — `ExampleSurface.of(context, 1)`
/// (darkSurface at night, white on paper) under a violet dawn and a teal
/// counter-glow stated per brightness — and the screen's single
/// [ExampleSweepBorder] rims it. The balance is a [ExampleAmount], so the
/// numerals are tabular, the cents are set at 60 percent and the ISO code is
/// smaller and in the secondary ink.
///
/// Example-only by construction: the accounts branch of [MoneyScreen] is the
/// only thing that builds it, and that branch is already behind `isExample`.
/// A brightness or brand gate inside here would be dead code.
///
/// It reads top to bottom as four registers, and each one is a different
/// weight on purpose — the panel's own complaint used to be that everything on
/// it was the same weight except the number:
///
/// 1. the masthead — the currency's flag artwork and an eyebrow label;
/// 2. the balance, at [ExampleAmountSize.hero] or the largest volume that fits;
/// 3. a hairline, then the [_MoneyLedger] — the other currencies as pockets
///    at [ExampleAmountSize.small] instead of as one 12 px caption;
/// 4. the actions, spent by role: one filled [ExampleGlassButton] and two matte
///    chips, where there used to be three identical grey discs.
///
/// This is still the screen's one moment: on arrival the numerals settle from
/// the secondary ink to full ink over [ExampleMotion.state] through
/// [ExampleStateSwitch], and only after the 420 ms route transition has
/// finished. Nothing else animates, nothing moves, and under reduced motion
/// the amount is simply at full ink on the first frame. The CTA below it is
/// built with its endless sheen switched off for the same reason: one panel,
/// one moving thing.
///
/// The atmosphere is given an explicit [ExampleAtmosphere.base] and an explicit
/// glow list per brightness rather than a preset: presets resolve daylight
/// from `theme.scaffoldBackgroundColor`, which the banking shell overrides to
/// transparent, so a preset inside the shell would paint Twilight on paper.
class _ExampleMoneyOverview extends StatefulWidget {
  const _ExampleMoneyOverview({
    required this.totalBalance,
    required this.canConvert,
    this.balances = const [],
    required this.onAddMoney,
    required this.onConvert,
    required this.onCreateBudget,
  });

  final Money totalBalance;
  final List<Money> balances;
  final bool canConvert;
  final VoidCallback onAddMoney;
  final VoidCallback onConvert;
  final VoidCallback? onCreateBudget;

  @override
  State<_ExampleMoneyOverview> createState() => _ExampleMoneyOverviewState();
}

class _ExampleMoneyOverviewState extends State<_ExampleMoneyOverview> {
  /// Corner radius of the panel, the clip and the sweep, which must agree.
  static const double _radius = 22;

  /// Inner gutter of the panel.
  static const EdgeInsets _panelPadding = EdgeInsets.fromLTRB(18, 16, 18, 16);

  /// How long after mount the arrival moment is armed. Long enough that the
  /// route animation has been installed for real: a freshly pushed route
  /// reports its animation as completed on the first build.
  static const Duration _settleDelay = Duration(milliseconds: 240);

  /// Advance of one tabular numeral as a fraction of the font size, plus the
  /// two scales [ExampleAmount] sets the cents and the ISO code at. Together
  /// they estimate the rendered width of a balance so the panel can pick the
  /// largest volume it can actually hold: the amount steps down a size rather
  /// than fading out, because a faded balance is a truncated balance.
  static const double _glyphAdvance = .58;
  static const double _fractionScale = .6;
  static const double _codeScale = .42;

  bool _settled = false;
  Timer? _settleTimer;
  Animation<double>? _routeAnimation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled) return;
    // Reduced motion has no arrival: the balance is correct on frame one.
    if (ExampleMotion.reduced(context)) {
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

  /// The panel's own lights at night: a violet dawn off the top-left corner
  /// with iris in the falloff, and the teal counter-glow low and right, so the
  /// hero has temperature contrast instead of one flat purple wash.
  static const List<ExampleAtmosphereGlow> _twilightGlows = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(-.45, -1),
      radius: 1.15,
      alpha: .22,
      mid: ExampleColors.iris,
      midAlpha: .09,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.05, 1.1),
      radius: .85,
      alpha: .07,
      midStop: .45,
    ),
  ];

  /// The same two lights on paper, at the daylight strength the presets use
  /// (about .4 of Twilight), stated outright because an explicit base turns
  /// the painter's own light branch off.
  static const List<ExampleAtmosphereGlow> _daylightGlows = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(-.45, -1),
      radius: 1.15,
      alpha: .085,
      mid: ExampleColors.iris,
      midAlpha: .045,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.05, 1.1),
      radius: .85,
      alpha: .05,
      midStop: .45,
    ),
  ];

  /// Estimated rendered width of [money] set at [size], run by run: the whole
  /// digits at full volume, the cents at 60 percent and the ISO code at the
  /// small size [ExampleAmount] gives it.
  static double _amountWidth(
    Money money,
    ExampleAmountSize size,
    double textScale,
  ) {
    final iso = money.currency.trim().toUpperCase();
    var number = money.formatted;
    // `Money.formatAmount` appends " CODE" when it has no symbol for the
    // currency and `ExampleAmount` peels it off to set it small; measure the
    // same two runs rather than counting the code twice.
    if (iso.isNotEmpty && number.endsWith(' $iso')) {
      number = number.substring(0, number.length - iso.length - 1);
    }
    final split =
        size == ExampleAmountSize.hero || size == ExampleAmountSize.large;
    final dot = number.lastIndexOf('.');
    final whole = split && dot > 0 ? number.substring(0, dot) : number;
    final fraction = split && dot > 0 ? number.substring(dot) : '';
    final em = size.fontSize * textScale * _glyphAdvance;
    return whole.length * em +
        fraction.length * em * _fractionScale +
        (iso.isEmpty ? 0 : (iso.length + 1) * em * _codeScale);
  }

  /// Largest amount volume whose rendered string still fits [available].
  static ExampleAmountSize _amountSize(
    Money money,
    double available,
    double textScale,
  ) {
    for (final size in const [
      ExampleAmountSize.hero,
      ExampleAmountSize.large,
    ]) {
      if (_amountWidth(money, size, textScale) <= available) return size;
    }
    return ExampleAmountSize.medium;
  }

  /// Width the wide layout hands to the action column at a 1.0 text scale.
  /// The amount measures against what is left *after* this and its gutter, so
  /// the hero never steps down for space the actions were never going to use.
  static const double _actionsColumn = 220;

  /// Most of the panel the action column is allowed to take. Uncapped, the
  /// narrowest panel that takes the two-column layout — 500 px on web — would
  /// hand a 1.6 text scale a 352 px column and leave the balance beside it
  /// `500 - 36 - 352 - 16` = 96 px. Past this share the two columns have
  /// stopped being two columns, which is why it reads as the affordability
  /// test in [_isWide] rather than as a clamp on the column.
  static const double _actionsColumnMaxShare = .45;

  /// The column at [textScale].
  ///
  /// The chip row splits this width between two chips — the [Row] in
  /// [_actions] is `Expanded`, `SizedBox(width: xs)`, `Expanded` — and each
  /// chip spends an 18 px icon and its 8 px gutter before the label, so a
  /// label's room is `(column - 8) / 2 - 26`, which at `220 * textScale` is
  /// `110 * textScale - 30`. "New budget" set at 13 px w600 is about 72 px at
  /// a 1.0 scale and grows with it, so the room grows by 110 per unit of
  /// scale against the label's 72 and the label fits at every accessibility
  /// scale — but only while the column really is `220 * textScale`. Held at
  /// a flat 220 the two grow at 0 against 72 and the longer label ellipsises
  /// from a little over 1.1 up, which is the clipping the narrow layout was
  /// restructured into two rows to avoid, reappearing on desktop.
  static double _actionsColumnFor(double textScale) =>
      _actionsColumn * textScale;

  /// Whether a panel [available] px wide sets the summary and the actions
  /// side by side at [textScale].
  ///
  /// Two conditions, and the second is why a scale can change the layout: the
  /// panel has to be wide enough for two columns at all, and it has to be
  /// able to hand the actions their whole [_actionsColumnFor] width inside
  /// [_actionsColumnMaxShare]. Clamping the column to the share instead was
  /// the shape this replaces, and it put the ellipsis back in a band: on web
  /// a 500 px panel at a 1.3 scale clamped 286 to 225, which is 82 px of
  /// label room against the 94 the label wants. The label clipped up to a
  /// 549 px panel and the clamp bit at all up to 636. Stacking hands
  /// `_actions()` the whole panel instead — at 500 px that is 464, so each
  /// chip is 228 and each label 202 — and the balance above it keeps the
  /// whole gutter rather than losing the column and its 16 px.
  static bool _isWide(double available, double textScale) =>
      available >= (kIsWeb ? 500 : 760) &&
      _actionsColumnFor(textScale) <= available * _actionsColumnMaxShare;

  @override
  Widget build(BuildContext context) {
    final balances = widget.balances;
    final primary = balances.isEmpty ? widget.totalBalance : balances.first;
    final rest = balances.length > 1 ? balances.sublist(1) : const <Money>[];
    final textScale = MediaQuery.textScalerOf(context).scale(1) *
        context.brandDesign.typographyScale;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = _isWide(constraints.maxWidth, textScale);
        final actionsColumn = _actionsColumnFor(textScale);
        // The amount never shares its line, so the whole panel gutter is its
        // measure; on the wide layout the actions column takes a slice first.
        final measure = constraints.maxWidth -
            _panelPadding.horizontal -
            (wide ? actionsColumn + AppSpacing.md : 0.0);
        final size = _amountSize(primary, measure, textScale);
        final summary = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Masthead. The currency's own artwork comes first, so the hero
            // says *which* money this is before it says how much, and it says
            // it with the same disc the balances underneath use rather than
            // with a word. The label is set in the eyebrow voice instead of as
            // one more 12.5 px line, which is what gave the panel a type
            // ladder of 44 / 12.5 / 12 — three volumes that read as two.
            //
            // Silent to a screen reader, because it is a picture of what the
            // amount node below already says in full: "Money balance 7,294.75
            // EUR". Announced, the masthead's own disc and eyebrow made that
            // three consecutive nodes — "EUR", "Money balance", "Money
            // balance 7,294.75 EUR" — the phrase twice over. One object, one
            // node; the pockets underneath fold their disc in the same way.
            //
            // "Add money" sits at the masthead's far end rather than as a
            // full-width bar under the balance: it is the reason the screen
            // exists, so it belongs beside the title, and hugging its label
            // it stops shouting over the figure it serves. It is outside the
            // [ExcludeSemantics] so it keeps its own node. On the wide layout
            // the masthead spans only the summary column, so the button moves
            // to the top of the action column instead — still the panel's
            // top-right corner, which is the one place it is meant to be.
            Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        ExampleCurrencyAvatar(code: primary.currency, size: 18),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(
                            context.tr('MONEY BALANCE'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: ExampleTextStyles.label(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (!wide) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _addMoney(),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            _SettlingAmount(
              money: primary,
              size: size,
              settled: _settled,
            ),
            if (rest.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              // A rule, not a second card. The ledger is the same object one
              // register down; a panel nested inside the hero would flatten
              // the hierarchy this exists to build, and the vocabulary's own
              // answer to "separate without nesting" is a hairline.
              SizedBox(
                width: double.infinity,
                height: 1,
                child: ColoredBox(
                  color: ExampleBorders.hairlineSideOf(context).color,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _MoneyLedger(balances: rest),
            ],
          ],
        );

        return _panel(
          context,
          wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: summary),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: actionsColumn,
                      child: _actions(wide: true),
                    ),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    const SizedBox(height: AppSpacing.md),
                    _actions(wide: false),
                  ],
                ),
        );
      },
    );
  }

  /// The three things a customer can do here, spent by role instead of
  /// stamped three times.
  ///
  /// This used to be three identical [ExampleCircleAction] discs in a row, and
  /// the row could not answer either of the two questions a customer asks of
  /// it. *Which of these is the point?* — none of them, they were the same
  /// object at the same weight. *Which of these can I actually use?* — also
  /// none, because a disc at [ExampleOpacity.disabled] beside two discs that
  /// were already quiet grey circles reads as three shades of the same
  /// unavailable.
  ///
  /// So: "Add money" is the reason this screen exists and becomes the one
  /// lifted object on the panel — a filled [ExampleGlassButton], the house
  /// CTA, which no reader mistakes for disabled. It hugs its label now (see
  /// [_addMoney]) and sits at the panel's top-right: on the masthead beside
  /// the title when the panel stacks, at the head of this column when it
  /// does not. "Convert" and "New budget"
  /// are the same matte chip the Pay header uses, one surface step up from
  /// the panel ground so they read as controls resting on it. A disabled chip
  /// beside a filled pill is unmistakably disabled; a disabled disc beside two
  /// discs was not.
  ///
  /// Two chips on their own row rather than three labels on one: at 375 the
  /// three cannot share a line without ellipsising "New budget", and a CTA
  /// that has to be guessed at is not a CTA.
  ///
  /// `ground: atmosphere` is the literal truth — the button sits inside this
  /// panel's [ExampleAtmosphere], so its body samples the panel's own light
  /// instead of inventing a haze. `sheen: false` is deliberate: the panel
  /// already carries the screen's lit hairline, which is exactly the case
  /// [ExampleGlassButton.sheen] documents for turning it off.
  Widget _addMoney() => ExampleGlassButton(
        label: context.tr('Add money'),
        icon: Icons.add_rounded,
        ground: ExampleGlassGround.atmosphere,
        expand: false,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        sheen: false,
        onPressed: widget.onAddMoney,
      );

  Widget _actions({required bool wide}) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // On the wide layout the CTA heads the column; stacked, it is
          // already on the masthead above.
          if (wide) ...[
            _addMoney(),
            const SizedBox(height: AppSpacing.xs),
          ],
          Row(
            children: [
              Expanded(
                child: _ExampleHeaderAction(
                  icon: Icons.swap_horiz_rounded,
                  label: context.tr('Convert'),
                  surfaceLevel: 2,
                  onTap: widget.canConvert ? widget.onConvert : null,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: _ExampleHeaderAction(
                  icon: Icons.savings_outlined,
                  label: context.tr('New budget'),
                  surfaceLevel: 2,
                  onTap: widget.onCreateBudget,
                ),
              ),
            ],
          ),
        ],
      );

  /// The lit ground, the rim and — when the shell's alive layer is present —
  /// the one lit hairline along the panel's top edge.
  Widget _panel(BuildContext context, Widget child) {
    const borderRadius = BorderRadius.all(Radius.circular(_radius));
    final light = ExampleTheme.isLight(context);
    final hero = ExampleSweepBorder(
      radius: _radius,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          // Empty in Twilight, where the surface step is the separation.
          boxShadow: ExampleShadows.ambientOf(context),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: ExampleAtmosphere(
            base: ExampleSurface.of(context, 1),
            glows: light ? _daylightGlows : _twilightGlows,
            child: Padding(padding: _panelPadding, child: child),
          ),
        ),
      ),
    );
    // The sheen lives on the shell's single scope; mounted on its own the
    // panel renders exactly the same pixels without one.
    if (ExampleSheenScope.maybeOf(context) == null) return hero;
    final peak = _decorationColor(
      context,
      'sheenPeak',
      light ? ExampleColors.lightIris : ExampleColors.lavender,
    );
    return Stack(
      children: [
        hero,
        Positioned(
          top: 0,
          left: _radius,
          right: _radius,
          height: 1,
          child: IgnorePointer(
            child: ExampleSheen(
              intensity: ExampleSheenIntensity.soft,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      peak.withValues(alpha: 0),
                      peak.withValues(alpha: light ? .40 : .32),
                      peak.withValues(alpha: 0),
                    ],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The hero balance and its one moment.
///
/// [ExampleAmount] does its own crossfade when the value changes, but the
/// arrival is a change of ink at a constant value, so the switch is owned here
/// and the amount is handed `animate: false` — one [ExampleStateSwitch], not
/// two nested ones. The key carries both the settle flag and the value, so a
/// balance that refreshes later still crossfades.
class _SettlingAmount extends StatelessWidget {
  const _SettlingAmount({
    required this.money,
    required this.size,
    required this.settled,
  });

  final Money money;
  final ExampleAmountSize size;
  final bool settled;

  @override
  Widget build(BuildContext context) => ExampleStateSwitch(
        alignment: Alignment.centerLeft,
        child: KeyedSubtree(
          key: ValueKey<String>(
            '$settled|${money.currency}|${money.minorUnits}',
          ),
          child: ExampleAmount(
            amount: money.minorUnits / 100,
            currency: money.currency,
            size: size,
            code: ExampleAmountCode.always,
            animate: false,
            color: settled
                ? ExampleInk.primary(context)
                : ExampleInk.secondary(context),
            semanticsLabel:
                context.tr('Money balance {p0}', {'p0': money.formatted}),
          ),
        ),
      );
}

/// The currencies the hero does not promote, as objects rather than as a
/// caption.
///
/// This line was `4,562.35 USD   1,860.00 GBP` in 12 px secondary ink — the
/// quietest thing on the panel, and the second most important. It is the
/// answer to "how is my money split", which is the question a multi-currency
/// account exists to raise, and it was set at the volume the design system
/// reserves for a timestamp.
///
/// So each currency becomes a *pocket*: its real flag artwork, then its
/// balance at [ExampleAmountSize.small]. That is a 44 / 18 / 11 type ladder
/// instead of 44 / 12.5 / 12, and it is identity encoded in form — a US flag
/// and a UK flag are told apart at a glance and at any text scale, where two
/// currency symbols in a run-on string are not.
///
/// What it deliberately does **not** do is draw a share-of-total bar. Without
/// an FX rate, `EUR 7,294` and `AED 10,000` cannot be compared, and a bar
/// implying they can would be invented data. Magnitude is carried by the one
/// honest ordering the data already has — the promoted balance at 44 px, the
/// rest at 18 px in descending order — and by nothing else.
class _MoneyLedger extends StatelessWidget {
  const _MoneyLedger({required this.balances});

  final List<Money> balances;

  /// Past this the strip stops being a glance and starts being a list, so the
  /// remainder is counted rather than drawn. A [Wrap] means the drawn ones
  /// still flow to a second line at a large text scale instead of overflowing.
  static const int _maxPockets = 3;

  @override
  Widget build(BuildContext context) {
    final shown = balances.take(_maxPockets).toList();
    final extra = balances.length - shown.length;
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final money in shown) _CurrencyPocket(money: money),
        if (extra > 0)
          Text(
            context.tr('+{p0} MORE', {'p0': extra}),
            maxLines: 1,
            // Spelled out for a screen reader: the caps are typography, not
            // an acronym, and "MORE" is short enough that some engines spell
            // it letter by letter.
            semanticsLabel: context.tr('{p0} more {p1}',
                {'p0': extra, 'p1': extra == 1 ? 'currency' : 'currencies'}),
            // The counter is a marker, not a balance, so it takes the eyebrow
            // voice the masthead adopted rather than a fourth volume. Set as
            // a raw 12.5 px `TextStyle` it put back the exact off-ladder
            // volume this panel was rebuilt to remove, and it carried no
            // `fontFamily`, so a tenant's APP_FONT_FAMILY silently skipped it.
            style: ExampleTextStyles.label(context)
                .copyWith(color: ExampleInk.tertiary(context)),
          ),
      ],
    );
  }
}

/// One currency in the ledger: its flag, then its balance.
///
/// [ExampleAmountCode.always], the same as the hero one register up — a choice
/// between two working options, not the only one that names a pocket.
/// `Money.formatAmount` carries a symbol for exactly USD, EUR and GBP
/// (`Money._fiatSymbols`), those three sit inside the ten codes
/// [ExampleCurrencyAvatar] paints artwork for, and `auto` prints the ISO code
/// wherever the formatter produced no symbol. So on an unmasked balance `auto`
/// drops a code only where a flag has already replaced it, and a JPY or PLN
/// pocket keeps its code either way.
///
/// Where the two part company is Private Mode. `Money.formatAmount` returns
/// dots, so `auto` finds no trailing code to peel and renders `••••` alone
/// while `always` still reads `•••• JPY` — and on a masked strip the disc is
/// the only other name a pocket carries on screen, which for a currency with
/// no artwork is a 6 px glyph. What `always` costs is a repeated "USD" beside
/// a US flag, and pockets wide enough that at 375 with balances this long the
/// [Wrap] gives each of the three a line of its own.
///
/// The figure is [Flexible] rather than capped at a constant. `ExampleAmount`
/// fades what outgrows its box, so a fixed 148 px cap faded a seven-figure
/// balance at an accessibility text scale while the panel around it still had
/// room to give — the truncation the hero's own step-down one register up
/// exists to refuse, on the same panel. Flexible inside a min-size [Row] lets
/// a pocket keep its intrinsic width and shrink only against the [Wrap]'s
/// real limit, which is the whole panel.
class _CurrencyPocket extends StatelessWidget {
  const _CurrencyPocket({required this.money});

  final Money money;

  @override
  Widget build(BuildContext context) => Semantics(
        label: context.tr(
            '{p0} balance {p1}', {'p0': money.currency, 'p1': money.formatted}),
        excludeSemantics: true,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExampleCurrencyAvatar(code: money.currency, size: 20),
            const SizedBox(width: AppSpacing.xs),
            Flexible(
              child: ExampleAmount(
                amount: money.minorUnits / 100,
                currency: money.currency,
                size: ExampleAmountSize.small,
                code: ExampleAmountCode.always,
                animate: false,
              ),
            ),
          ],
        ),
      );
}

/// The screen's one headline. Under the shell's alive layer a soft band walks
/// the glyphs on arrival and once a cadence after; the type never moves, and
/// without a scope this is a plain [ExampleSectionTitle].
class _MoneySectionHeadline extends StatelessWidget {
  const _MoneySectionHeadline({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final headline = ExampleSectionTitle(title: title);
    if (ExampleSheenScope.maybeOf(context) == null) return headline;
    return ExampleSheen.text(
      intensity: ExampleSheenIntensity.soft,
      child: headline,
    );
  }
}

/// Header of the Pay and Payees tabs: which account is in play, the
/// safeguarding note, and the two account-level actions.
///
/// Example reads it in its own register — the account name in the section
/// voice, the safeguarding note as a 44 pt icon target with a real semantics
/// label, and the two actions as a pair of equal-width matte chips on their
/// own line, so neither label can ever be clipped by the other at a 1.3 text
/// scale. Utility chrome: nothing here animates beyond the 120 ms press.
/// Every other brand keeps the Material composition byte for byte.
class _EqualsMoneyHeader extends StatelessWidget {
  const _EqualsMoneyHeader({
    required this.disclosure,
    required this.isCreating,
    required this.canConvert,
    required this.onConvert,
    required this.onCreateBudget,
  });

  final String disclosure;
  final bool isCreating;
  final bool canConvert;
  final VoidCallback onConvert;
  final VoidCallback onCreateBudget;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) return _example(context);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                context.tr('Fiat account'),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: context.tr('Safeguarding statement'),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(
                width: 34,
                height: 34,
              ),
              onPressed: () => showPaymentServicesDisclosure(
                context,
                disclosure: disclosure,
              ),
              icon: const Icon(Icons.info_outline_rounded, size: 20),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Accounts & budgets'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: canConvert ? onConvert : null,
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
              label: Text(context.tr('Convert')),
            ),
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.secondary,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
              ),
              onPressed: isCreating ? null : onCreateBudget,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(context.tr('Create budget')),
            ),
          ],
        ),
      ],
    );
  }

  /// The same information in the Example register.
  Widget _example(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('Fiat account'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19 * context.brandDesign.typographyScale,
                  fontWeight: FontWeight.w700,
                  color: ExampleInk.primary(context),
                ),
              ),
            ),
            _ExampleHeaderIcon(
              icon: Icons.info_outline_rounded,
              label: context.tr('Safeguarding statement'),
              onTap: () => showPaymentServicesDisclosure(
                context,
                disclosure: disclosure,
              ),
            ),
          ],
        ),
        Text(
          context.tr('Accounts & budgets'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5 * context.brandDesign.typographyScale,
            color: ExampleInk.secondary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // Equal shares rather than natural widths: 'Create budget' is the
        // longest label on the row and would push 'Convert' off the line at a
        // 1.3 text scale if either child sized itself.
        Row(
          children: [
            Expanded(
              child: _ExampleHeaderAction(
                icon: Icons.swap_horiz_rounded,
                label: context.tr('Convert'),
                onTap: canConvert ? onConvert : null,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _ExampleHeaderAction(
                icon: Icons.add_rounded,
                label: context.tr('Create budget'),
                onTap: isCreating ? null : onCreateBudget,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Icon-only 44 pt target in the Example header: no chrome, a real name for
/// screen readers, and the 120 ms press every Example control shares.
class _ExampleHeaderIcon extends StatelessWidget {
  const _ExampleHeaderIcon({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: ExamplePressable(
          onTap: onTap,
          semanticsLabel: label,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(
              icon,
              size: 20,
              color: ExampleInk.secondary(context),
            ),
          ),
        ),
      );
}

/// Secondary action in the Example header and in the accounts hero: a 44 pt
/// matte chip, edged with the hairline of the active theme and — on paper,
/// where a white chip on paper has almost no tonal contrast left — seated on
/// the night ambient. The label ellipsizes rather than overflowing, and the
/// whole chip dims to [ExampleOpacity.disabled] when there is nothing to do.
class _ExampleHeaderAction extends StatelessWidget {
  const _ExampleHeaderAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.surfaceLevel = 1,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// Which step of the surface ladder the chip is drawn on.
  ///
  /// One is right for a chip resting on the page, which is where the Pay
  /// header puts it, and is the default so that call site is unchanged. A
  /// chip *inside* a level-1 panel takes two: at level 1 it would be the exact
  /// colour of the thing it is sitting on in Twilight, and only its hairline
  /// would prove it existed.
  final int surfaceLevel;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AppRadii.md));
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : ExampleOpacity.disabled,
      child: ExamplePressable(
        onTap: onTap,
        enabled: enabled,
        semanticsLabel: label,
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, surfaceLevel),
            borderRadius: radius,
            border: Border.fromBorderSide(ExampleBorders.sideOf(context)),
            // Empty in Twilight, where the surface step is the separation.
            boxShadow: ExampleShadows.ambientOf(context),
          ),
          child: SizedBox(
            height: 44,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: ExampleInk.accent(context, ExampleColors.iris),
                ),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13 * context.brandDesign.typographyScale,
                      fontWeight: FontWeight.w600,
                      color: ExampleInk.primary(context),
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
}

/// Accounts / Pay / Payees.
///
/// Example gets the pill vocabulary the accounts hub above it already uses, so
/// the two control bars on the Pay and Payees tabs read as one system instead
/// of a Example pill over a Material tab strip. Every other brand keeps the
/// Material [TabBar] byte for byte, including its indicator and label colours.
class EqualsMoneyTabBar extends StatelessWidget {
  const EqualsMoneyTabBar({this.controller, super.key});

  final TabController? controller;

  @override
  Widget build(BuildContext context) {
    final resolved = controller ?? DefaultTabController.maybeOf(context);
    if (context.isExampleTheme && resolved != null) {
      return Padding(
        // 20 to sit on the same gutter as the accounts hub above it.
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: _ExampleMoneyTabs(controller: resolved),
      );
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            color: colorScheme.secondary,
            borderRadius: BorderRadius.circular(16),
          ),
          labelColor: colorScheme.onSecondary,
          unselectedLabelColor: colorScheme.onSurfaceVariant,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700),
          tabs: [
            _CompactMoneyTab(
              icon: Icons.account_balance_outlined,
              label: context.tr('Accounts'),
            ),
            _CompactMoneyTab(
                icon: Icons.receipt_long_outlined, label: context.tr('Pay')),
            _CompactMoneyTab(
                icon: Icons.people_outline, label: context.tr('Payees')),
          ],
        ),
      ),
    );
  }
}

/// The Money tabs in the Example register.
///
/// One [ExampleSegmentedControl] driven by the screen's own [TabController], so
/// a tap on a segment and a swipe of the [TabBarView] stay in step. The
/// selection follows `index`, which the controller publishes the instant a tap
/// lands, rather than the animation value — the segment moves on its own
/// 200 ms state token instead of tracking a drag frame by frame. Utility
/// chrome: there is no arrival moment here, and the one state move collapses
/// to instant under reduced motion inside the control.
class _ExampleMoneyTabs extends StatelessWidget {
  const _ExampleMoneyTabs({required this.controller});

  final TabController controller;

  static const List<({int value, String label})> _segments = [
    (value: 0, label: 'Accounts'),
    (value: 1, label: 'Pay'),
    (value: 2, label: 'Payees'),
  ];

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) => ExampleSegmentedControl<int>(
          height: 44,
          segments: [
            for (final segment in _segments)
              (value: segment.value, label: context.tr(segment.label))
          ],
          selected: controller.index,
          onChanged: (index) {
            if (index != controller.index) controller.animateTo(index);
          },
        ),
      );
}

class _CompactMoneyTab extends StatelessWidget {
  const _CompactMoneyTab({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Tab(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
              ),
            ),
          ],
        ),
      );
}

class _EqualsMoneyActionRequired extends StatelessWidget {
  const _EqualsMoneyActionRequired({required this.status, this.header});

  final KycDetailedStatus status;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Accounts'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (header != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
              child: header,
            ),
          ],
          EqualsMoneyRequiredActionCard(status: status),
        ],
      ),
    );
  }
}

class _BankingRequired extends StatelessWidget {
  const _BankingRequired({required this.onContinue, this.header});

  final VoidCallback onContinue;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Accounts'))),
      body: Column(
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: header,
            ),
          Expanded(child: _bankingPrompt(context)),
        ],
      ),
    );
  }

  Widget _bankingPrompt(BuildContext context) {
    if (context.isExampleTheme) {
      return _centredState(
        ExampleEmptyState(
          icon: Icons.account_balance_outlined,
          title: context.tr('Finish bank onboarding'),
          body: context.tr(
              'Accounts and payments open as soon as your bank onboarding is complete.'),
          actionLabel: context.tr('Continue onboarding'),
          onAction: onContinue,
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.account_balance, size: 48),
            const SizedBox(height: 12),
            Text(
              context.tr(
                  'Complete bank onboarding before viewing accounts and moving money.'),
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.account_balance),
              label: Text(context.tr('Continue onboarding')),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentForm extends ConsumerStatefulWidget {
  const _PaymentForm({this.initialAccountId = ''});

  final String initialAccountId;

  @override
  ConsumerState<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends ConsumerState<_PaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _referenceController = TextEditingController();
  final _otpController = TextEditingController();
  String? _accountKey;
  String? _payeeKey;
  String? _currency;
  PayoutQuote? _quote;
  PayoutCheck? _check;
  String _verificationToken = '';
  String _errorMessage = '';
  bool _loading = false;
  bool _otpSent = false;
  Timer? _quoteRefreshTimer;

  @override
  void dispose() {
    _quoteRefreshTimer?.cancel();
    _amountController.dispose();
    _referenceController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// The commit label for the step the flow is on. One button, three states:
  /// the target never moves under the thumb between quoting and confirming.
  String get _ctaLabel => _otpSent
      ? 'Confirm payment'
      : _quote == null
          ? 'Show fee'
          : 'Send OTP code';

  /// The commit action for the step the flow is on. Null while a request is
  /// in flight, or while the amount and reference cannot yet buy a quote —
  /// the button then renders as an inert surface step rather than a live
  /// affordance the user can hammer.
  VoidCallback? _ctaAction(
    Payee payee,
    AccountBalance account, {
    required bool canRequestQuote,
  }) {
    if (_loading) return null;
    if (_otpSent) return _confirmPayout;
    if (_quote == null) {
      return canRequestQuote ? () => _requestQuote(payee, account) : null;
    }
    return () => _sendOtp(payee, account);
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final payees = ref.watch(payeesProvider);
    final budgets = ref.watch(budgetsProvider).valueOrNull ?? const [];

    return accounts.when(
      data: (accountItems) => payees.when(
        data: (payeeItems) {
          final sendablePayees =
              payeeItems.where((payee) => !payee.requiresConfirmation).toList();
          final fundedAccounts = paymentAccountsWithBudgets(
            accountItems,
            budgets,
          ).where(hasFundedBalance).toList();
          if (fundedAccounts.isEmpty) {
            return _MoneyEmptyState(
              title: context.tr('No funded balance'),
              message: context
                  .tr('Add funds to an account before making a payment.'),
              icon: Icons.account_balance_wallet_outlined,
            );
          }
          if (sendablePayees.isEmpty) {
            return _MoneyEmptyState(
              title: context.tr('No confirmed payees'),
              message: context
                  .tr('Add or confirm a payee before sending a payment.'),
              icon: Icons.people_outline,
            );
          }

          final payeeOptions = _payeeOptions(sendablePayees);
          _payeeKey ??= payeeOptions.firstOrNull?.key;
          final selectedPayeeEntry = _selectedPayeeEntry(payeeOptions);
          final selectedPayee = selectedPayeeEntry.payee;
          final accountOptions = _accountOptions(fundedAccounts);
          if (_accountKey == null && widget.initialAccountId.isNotEmpty) {
            _accountKey = accountOptions
                .where((option) => option.account.id == widget.initialAccountId)
                .firstOrNull
                ?.key;
          }
          if (!accountOptions.any((option) => option.key == _accountKey)) {
            _accountKey = accountOptions.first.key;
          }
          final selectedAccountEntry = _selectedAccountEntry(accountOptions);
          final selectedAccount = selectedAccountEntry.account;
          final currencyOptions = fundedCurrencyOptions(
            selectedAccount,
            preferredCurrency: selectedPayee.currency,
          );
          if (_currency == null || !currencyOptions.contains(_currency)) {
            _currency = currencyOptions.first;
          }
          final targetCurrency =
              fallbackText(selectedPayee.currency, _currency!);
          final canRequestQuote =
              _amountValue() > 0 && _referenceController.text.trim().isNotEmpty;

          final theme = Theme.of(context);
          final isExample = context.isExampleTheme;
          return LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              // Two desktop tiers, both from the existing ramp. This screen is
              // where a person commits money, so it is the one line on the
              // money surface that earns display type: it stops and breathes
              // before the form asks for a number. 44 at tablet width, 64 once
              // there is a real desktop page around it — measured against the
              // field, whose send flows head at 36 (RedotPay) to 80+ (ether.fi
              // Cash, Revolut). Below 834 nothing changes: mobile keeps the
              // 22 px headline and no line reflows at 375 or 393.
              final headline = !isExample || width < 834
                  ? theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)
                  : width >= 1200
                      ? AppTypography.displayXl(theme.textTheme)
                      : theme.textTheme.displayLarge;
              // A payment form stretched across 1440 px reads as a spreadsheet
              // and drags the eye across a 1300 px line per field. The laws cap
              // a form column at 520; the page keeps the rest as air.
              final gutter = isExample && width >= 834
                  ? ((width - 520) / 2).clamp(16.0, double.infinity)
                  : 16.0;
              return Form(
                key: _formKey,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(gutter, 16, gutter, 16),
                  children: [
                    Text(
                      context.tr('Send money'),
                      style: headline,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.tr(
                          'Choose the account and recipient, then review the fee before confirming.'),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: selectedAccountEntry.key,
                      decoration: InputDecoration(
                          labelText: context.tr('From account')),
                      items: [
                        for (final option in accountOptions)
                          DropdownMenuItem(
                            value: option.key,
                            child: Text(
                              paymentAccountOptionLabel(option.account),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: _required,
                      onChanged: (value) {
                        setState(() {
                          _accountKey = value;
                          _currency = null;
                          _resetPayoutState();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedPayeeEntry.key,
                      decoration:
                          InputDecoration(labelText: context.tr('Payee')),
                      items: [
                        for (final option in payeeOptions)
                          DropdownMenuItem(
                            value: option.key,
                            child: Text(_payeeLabel(option.payee)),
                          ),
                      ],
                      validator: _required,
                      onChanged: (value) {
                        setState(() {
                          _payeeKey = value;
                          _currency = null;
                          _resetPayoutState();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: InputDecoration(
                          labelText: context.tr('Pay from currency')),
                      items: [
                        for (final currency in currencyOptions)
                          DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                      ],
                      validator: _required,
                      onChanged: (value) {
                        setState(() {
                          _currency = value;
                          _resetPayoutState();
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _AvailableBalanceHint(
                      account: selectedAccount,
                      currency: _currency!,
                    ),
                    const SafeguardingStatementButton(),
                    const SizedBox(height: 12),
                    _AmountField(
                      controller: _amountController,
                      currency: _currency!,
                      onChanged: (_) => setState(() => _resetPayoutState()),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _referenceController,
                      decoration:
                          InputDecoration(labelText: context.tr('Reference')),
                      validator: _required,
                      onChanged: (_) => setState(_resetPayoutState),
                    ),
                    if (targetCurrency != _currency) ...[
                      const SizedBox(height: 8),
                      Text(
                        context.tr(
                            'Recipient currency: {p0}', {'p0': targetCurrency}),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (_errorMessage.isNotEmpty)
                      Card(
                        color: Theme.of(context).colorScheme.errorContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            _errorMessage,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                    if (_quote != null) ...[
                      _PayoutQuoteCard(
                        quote: _quote!,
                        check: _check,
                        otpSent: _otpSent,
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (_otpSent) ...[
                      Text(
                        context.tr('Enter the 8-digit code sent to you.'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 8),
                      ExampleOtpField(
                        controller: _otpController,
                        length: 8,
                        enabled: !_loading,
                        label: context.tr('OTP code'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _loading ? null : _resendOtp,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.tr('Resend code')),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (isExample)
                      // The decisive action of the money surface, and the only
                      // glass button on it. Its label walks the flow — Show fee,
                      // Send OTP code, Confirm payment — but the silhouette,
                      // width and position never move, so the commit target sits
                      // in the same place from the first tap to the last. No
                      // sheen: this screen already spends its sweep on the
                      // balance panel's hairline and the section title, and a
                      // third host would turn a rhythm into a shimmer.
                      ExampleGlassButton(
                        label: _ctaLabel,
                        icon: _otpSent ? Icons.verified_user : Icons.send,
                        loading: _loading,
                        loadingSemanticsLabel: '$_ctaLabel, in progress',
                        onPressed: _ctaAction(
                          selectedPayee,
                          selectedAccount,
                          canRequestQuote: canRequestQuote,
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _ctaAction(
                          selectedPayee,
                          selectedAccount,
                          canRequestQuote: canRequestQuote,
                        ),
                        icon: Icon(_otpSent ? Icons.verified_user : Icons.send),
                        label: Text(
                            _loading ? context.tr('Processing...') : _ctaLabel),
                      ),
                  ],
                ),
              );
            },
          );
        },
        error: (error, stackTrace) => _MoneyErrorState(
          error: error,
          onRetry: () => ref.invalidate(payeesProvider),
        ),
        loading: () => LoadingState(label: context.tr('Loading payees')),
      ),
      error: (error, stackTrace) => _MoneyErrorState(
        error: error,
        onRetry: () => ref.invalidate(accountsProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading accounts')),
    );
  }

  Future<void> _requestQuote(
    Payee selectedPayee,
    AccountBalance selectedAccount,
  ) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
      await _refreshQuote(selectedPayee, selectedAccount, showErrors: true);
      _startQuoteRefresh(selectedPayee, selectedAccount);
    } catch (error) {
      setState(() => _errorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _sendOtp(
    Payee selectedPayee,
    AccountBalance selectedAccount,
  ) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });

      final quote = _quote ??
          await _refreshQuote(
            selectedPayee,
            selectedAccount,
            showErrors: true,
          );
      final api = ref.read(mobileBankingApiProvider);
      final amount = _amountValue();
      final check = await api.checkPayout(
        payeeId: selectedPayee.id,
        quotationId: quote.id,
        amount: amount,
        currency: _currency!,
        memo: _referenceController.text.trim(),
      );
      if (!check.pass) {
        setState(() {
          _check = check;
          _errorMessage = check.message.isEmpty
              ? 'The payout check did not pass.'
              : check.message;
        });
        return;
      }

      final otp = await api.initiatePayoutOtp(
        checkId: check.id,
        quoteRequestId: quote.quoteRequestId,
        payeeId: selectedPayee.id,
        amount: amount,
        currency: _currency!,
      );

      if (!otp.success || otp.verificationToken.isEmpty) {
        throw StateError(
          otp.message.isEmpty ? 'OTP could not be sent.' : otp.message,
        );
      }

      setState(() {
        _check = check;
        _verificationToken = otp.verificationToken;
        _otpSent = true;
        _otpController.clear();
      });
      _startQuoteRefresh(selectedPayee, selectedAccount);
    } catch (error) {
      setState(() => _errorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _confirmPayout() async {
    final otpCode = _otpController.text.trim();
    if (otpCode.length != 8) {
      setState(() => _errorMessage = 'Enter the full 8-digit OTP code.');
      return;
    }
    if (_verificationToken.isEmpty ||
        _payeeKey == null ||
        _accountKey == null) {
      setState(
          () => _errorMessage = 'Request a new OTP code before confirming.');
      return;
    }

    final accounts = ref.read(accountsProvider).valueOrNull ?? const [];
    final payees = ref.read(payeesProvider).valueOrNull ?? const [];
    if (accounts.isEmpty || payees.isEmpty) {
      setState(
          () => _errorMessage = 'Accounts or payees are no longer available.');
      return;
    }
    final selectedAccount =
        _selectedAccountEntry(_accountOptions(accounts)).account;
    final selectedPayee = _selectedPayeeEntry(_payeeOptions(payees)).payee;

    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });

      final api = ref.read(mobileBankingApiProvider);
      final latestQuote = await _refreshQuote(
        selectedPayee,
        selectedAccount,
        showErrors: true,
      );
      final verification = await api.verifyPayoutOtp(
        verificationToken: _verificationToken,
        otpCode: otpCode,
      );
      if (!verification.success) {
        throw StateError(
          verification.message.isEmpty
              ? 'The OTP code was not accepted.'
              : verification.message,
        );
      }

      final verifiedToken = verification.verificationToken.isEmpty
          ? _verificationToken
          : verification.verificationToken;
      await api.confirmPayout(
        checkId: _check?.id ?? '',
        quoteRequestId: latestQuote.quoteRequestId,
        verificationToken: verifiedToken,
        payeeId: selectedPayee.id,
        amount: _amountValue(),
        currency: _currency!,
      );

      _quoteRefreshTimer?.cancel();
      ref.invalidate(transactionsProvider);
      ref.invalidate(activityTransactionsProvider);
      ref.invalidate(activityAccountTransactionsProvider);
      ref.invalidate(activityCardTransactionsProvider);
      ref.invalidate(accountsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Payment submitted'))),
        );
        setState(() => _resetPayoutState());
      }
    } catch (error) {
      setState(() => _errorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resendOtp() async {
    if (_verificationToken.isEmpty) {
      return;
    }

    try {
      setState(() {
        _loading = true;
        _errorMessage = '';
      });
      final otp = await ref
          .read(mobileBankingApiProvider)
          .resendPayoutOtp(verificationToken: _verificationToken);
      if (!otp.success) {
        throw StateError(
            otp.message.isEmpty ? 'OTP resend failed.' : otp.message);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(otp.message.isEmpty
              ? context.tr('OTP code resent')
              : otp.message),
        ),
      );
    } catch (error) {
      setState(() => _errorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<PayoutQuote> _refreshQuote(
    Payee selectedPayee,
    AccountBalance selectedAccount, {
    required bool showErrors,
  }) async {
    final quote = await ref.read(mobileBankingApiProvider).createPayoutQuote(
          payeeId: selectedPayee.id,
          amount: _amountValue(),
          sourceCurrency: _currency!,
          targetCurrency: fallbackText(selectedPayee.currency, _currency!),
          lastQuoteId: _quote?.id,
        );

    if (mounted) {
      setState(() {
        _quote = quote;
        if (showErrors) {
          _errorMessage = '';
        }
      });
    }

    return quote;
  }

  void _startQuoteRefresh(
    Payee selectedPayee,
    AccountBalance selectedAccount,
  ) {
    _quoteRefreshTimer?.cancel();
    _quoteRefreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _quote == null) {
        return;
      }
      _refreshQuoteSilently(selectedPayee, selectedAccount);
    });
  }

  Future<void> _refreshQuoteSilently(
    Payee selectedPayee,
    AccountBalance selectedAccount,
  ) async {
    try {
      await _refreshQuote(
        selectedPayee,
        selectedAccount,
        showErrors: false,
      );
    } catch (_) {}
  }

  void _resetPayoutState() {
    _quoteRefreshTimer?.cancel();
    _quote = null;
    _check = null;
    _verificationToken = '';
    _errorMessage = '';
    _otpSent = false;
    _otpController.clear();
  }

  double _amountValue() {
    return double.tryParse(
            _amountController.text.trim().replaceAll(',', '.')) ??
        0;
  }

  _PaymentAccountOption _selectedAccountEntry(
    List<_PaymentAccountOption> accounts,
  ) {
    final selectedKey = _accountKey;
    if (selectedKey != null) {
      for (final option in accounts) {
        if (option.key == selectedKey) {
          return option;
        }
      }
    }

    return accounts.first;
  }

  _PaymentPayeeOption _selectedPayeeEntry(List<_PaymentPayeeOption> payees) {
    final selectedKey = _payeeKey;
    if (selectedKey != null) {
      for (final option in payees) {
        if (option.key == selectedKey) {
          return option;
        }
      }
    }

    return payees.first;
  }
}

class _PayeesView extends ConsumerStatefulWidget {
  const _PayeesView();

  @override
  ConsumerState<_PayeesView> createState() => _PayeesViewState();
}

class _PaymentAccountOption {
  const _PaymentAccountOption({
    required this.key,
    required this.account,
  });

  final String key;
  final AccountBalance account;
}

class _AvailableBalanceHint extends StatelessWidget {
  const _AvailableBalanceHint({
    required this.account,
    required this.currency,
  });

  final AccountBalance account;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final matches = account.currencyBalances
        .where((balance) => balance.currency.toUpperCase() == currency)
        .firstOrNull;
    final available = matches ??
        (account.available.currency.toUpperCase() == currency
            ? account.available
            : null);

    return Row(
      children: [
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        // A natural-width label in a Row overflows before it wraps; the hint
        // is the longest string on the Pay form at a 1.3 text scale.
        Expanded(
          child: Text(
            available == null
                ? context.tr(
                    '{p0} balance available after fee check', {'p0': currency})
                : context.tr('{p0} available', {'p0': available.formatted}),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _PaymentPayeeOption {
  const _PaymentPayeeOption({
    required this.key,
    required this.payee,
  });

  final String key;
  final Payee payee;
}

List<_PaymentAccountOption> _accountOptions(List<AccountBalance> accounts) {
  return [
    for (var index = 0; index < accounts.length; index++)
      _PaymentAccountOption(
        key: '${accounts[index].id}#$index',
        account: accounts[index],
      ),
  ];
}

List<_PaymentPayeeOption> _payeeOptions(List<Payee> payees) {
  return [
    for (var index = 0; index < payees.length; index++)
      _PaymentPayeeOption(
        key: '${payees[index].id}#$index',
        payee: payees[index],
      ),
  ];
}

class _PayeesViewState extends ConsumerState<_PayeesView> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _accountHolderController = TextEditingController();
  final _accountController = TextEditingController();
  final _bankNameController = TextEditingController();
  final _routingCodeController = TextEditingController();
  final _bankAddressController = TextEditingController();
  final _bankAddress2Controller = TextEditingController();
  final _bankCityController = TextEditingController();
  final _bankStateController = TextEditingController();
  final _bankPostalCodeController = TextEditingController();
  final _payeeAddressController = TextEditingController();
  final _payeeAddress2Controller = TextEditingController();
  final _payeeCityController = TextEditingController();
  final _payeeStateController = TextEditingController();
  final _payeePostalCodeController = TextEditingController();
  final _commentsController = TextEditingController();
  final _payeeOtpController = TextEditingController();
  String _paymentType = 'INDIVIDUAL';
  String _paymentMethod = 'SEPA.CREDITTRANSFER';
  String _currency = 'EUR';
  String _countryCode = 'SI';
  String _bankCountryCode = 'SI';
  String _payeeCountryCode = 'SI';
  String _routingCodeType = 'BIC';
  String _payeeVerificationToken = '';
  String _payeeErrorMessage = '';
  String _payeeStatusMessage = '';
  bool _payeeOtpSent = false;
  bool _payeeLoading = false;
  bool _clearingPayeeForm = false;
  bool _showPayeeForm = false;

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _displayNameController,
      _firstNameController,
      _lastNameController,
      _accountHolderController,
      _accountController,
      _bankNameController,
      _routingCodeController,
      _bankAddressController,
      _bankAddress2Controller,
      _bankCityController,
      _bankStateController,
      _bankPostalCodeController,
      _payeeAddressController,
      _payeeAddress2Controller,
      _payeeCityController,
      _payeeStateController,
      _payeePostalCodeController,
      _commentsController,
    ]) {
      controller.addListener(_resetPayeeVerificationIfStarted);
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _accountHolderController.dispose();
    _accountController.dispose();
    _bankNameController.dispose();
    _routingCodeController.dispose();
    _bankAddressController.dispose();
    _bankAddress2Controller.dispose();
    _bankCityController.dispose();
    _bankStateController.dispose();
    _bankPostalCodeController.dispose();
    _payeeAddressController.dispose();
    _payeeAddress2Controller.dispose();
    _payeeCityController.dispose();
    _payeeStateController.dispose();
    _payeePostalCodeController.dispose();
    _commentsController.dispose();
    _payeeOtpController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final payees = ref.watch(payeesProvider);

    return payees.when(
      data: (items) => Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(context.tr('Saved payees'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            if (context.isExampleTheme)
              _ExamplePayeeList(payees: items)
            else if (items.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.people_outline),
                  title: Text(context.tr('No payees saved')),
                  subtitle:
                      Text(context.tr('Add a recipient below before paying.')),
                ),
              )
            else
              for (final payee in items)
                Card(
                  child: ListTile(
                    leading: Icon(
                      payee.requiresConfirmation
                          ? Icons.pending_actions
                          : Icons.person_outline,
                    ),
                    title: Text(_payeeLabel(payee)),
                    subtitle: Text(_payeeSubtitle(payee)),
                  ),
                ),
            const Divider(height: 32),
            if (!_showPayeeForm)
              Row(
                children: [
                  Expanded(
                    // The payees tab's opening move, and its only decisive
                    // one while the form is closed — so on Example it is the
                    // same glass object the tab's commit uses further down,
                    // instead of a Material slab that made this one tab
                    // answer "what do I press" with two different materials.
                    // The two never co-render: this branch is `!_showPayeeForm`
                    // and the glass commit lives in the `else`.
                    //
                    // `surface` ground: this is a plain scrolling ListView on
                    // the scaffold, with nothing painted behind it to sample.
                    // Height stays at the widget's 54 default, which is the
                    // theme's own filled/outlined minimum, so the Scan QR
                    // button beside it keeps its exact alignment.
                    child: context.isExampleTheme
                        ? ExampleGlassButton(
                            label: context.tr('Add payee'),
                            icon: Icons.person_add_alt,
                            onPressed: () =>
                                setState(() => _showPayeeForm = true),
                          )
                        : FilledButton.icon(
                            onPressed: () =>
                                setState(() => _showPayeeForm = true),
                            icon: const Icon(Icons.person_add_alt),
                            label: Text(context.tr('Add payee')),
                          ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _payeeLoading ? null : _scanPayeeQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(context.tr('Scan QR')),
                  ),
                ],
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      context.tr('Add payee'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _payeeLoading ? null : _scanPayeeQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(context.tr('Scan QR')),
                  ),
                  IconButton(
                    tooltip: context.tr('Close form'),
                    onPressed: _payeeLoading
                        ? null
                        : () => setState(() => _showPayeeForm = false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _displayNameController,
                decoration:
                    InputDecoration(labelText: context.tr('Display name')),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration:
                          InputDecoration(labelText: context.tr('First name')),
                      validator: _required,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration:
                          InputDecoration(labelText: context.tr('Last name')),
                      validator: _required,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountHolderController,
                decoration: InputDecoration(
                    labelText: context.tr('Account holder name')),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SelectField(
                      label: context.tr('Currency'),
                      value: _currency,
                      options: const ['EUR', 'GBP', 'USD'],
                      onChanged: (value) => setState(() {
                        _currency = value;
                        _resetPayeeVerification();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SelectField(
                      label: context.tr('Country'),
                      value: _countryCode,
                      options: const [
                        'SI',
                        'GB',
                        'DE',
                        'FR',
                        'NL',
                        'ES',
                        'IT',
                        'US'
                      ],
                      onChanged: (value) => setState(() {
                        _countryCode = value;
                        _bankCountryCode = value;
                        _payeeCountryCode = value;
                        _resetPayeeVerification();
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SelectField(
                label: context.tr('Payment type'),
                value: _paymentType,
                options: const ['INDIVIDUAL', 'COMPANY'],
                onChanged: (value) => setState(() {
                  _paymentType = value;
                  _resetPayeeVerification();
                }),
              ),
              const SizedBox(height: 12),
              _SelectField(
                label: context.tr('Payment method'),
                value: _paymentMethod,
                options: const [
                  'SEPA.CREDITTRANSFER',
                  'SEPA.INSTANT',
                  'SWIFT',
                  'CHAPS',
                  'UKFPS',
                  'ACH',
                  'WIRETRANSFER',
                  'OFF_PLATFORM',
                ],
                onChanged: (value) => setState(() {
                  _paymentMethod = value;
                  _resetPayeeVerification();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountController,
                decoration: InputDecoration(
                    labelText: context.tr('IBAN or account number')),
                validator: _required,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SelectField(
                      label: context.tr('Routing type'),
                      value: _routingCodeType,
                      options: const ['BIC', 'SWIFT', 'SORT_CODE', 'ABA'],
                      onChanged: (value) => setState(() {
                        _routingCodeType = value;
                        _resetPayeeVerification();
                      }),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _routingCodeController,
                      decoration: InputDecoration(
                          labelText: context.tr('Routing code')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankNameController,
                decoration: InputDecoration(labelText: context.tr('Bank name')),
              ),
              const SizedBox(height: 12),
              Text(context.tr('Bank address'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _SelectField(
                label: context.tr('Bank country'),
                value: _bankCountryCode,
                options: const ['SI', 'GB', 'DE', 'FR', 'NL', 'ES', 'IT', 'US'],
                onChanged: (value) => setState(() {
                  _bankCountryCode = value;
                  _resetPayeeVerification();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankAddressController,
                decoration: InputDecoration(
                    labelText: context.tr('Bank address line 1')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankAddress2Controller,
                decoration: InputDecoration(
                    labelText: context.tr('Bank address line 2')),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _bankCityController,
                      decoration:
                          InputDecoration(labelText: context.tr('Bank city')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _bankStateController,
                      decoration:
                          InputDecoration(labelText: context.tr('Bank state')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bankPostalCodeController,
                decoration:
                    InputDecoration(labelText: context.tr('Bank postal code')),
              ),
              const SizedBox(height: 16),
              Text(context.tr('Payee address'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _SelectField(
                label: context.tr('Payee country'),
                value: _payeeCountryCode,
                options: const ['SI', 'GB', 'DE', 'FR', 'NL', 'ES', 'IT', 'US'],
                onChanged: (value) => setState(() {
                  _payeeCountryCode = value;
                  _resetPayeeVerification();
                }),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _payeeAddressController,
                decoration: InputDecoration(
                    labelText: context.tr('Payee address line 1')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _payeeAddress2Controller,
                decoration: InputDecoration(
                    labelText: context.tr('Payee address line 2')),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _payeeCityController,
                      decoration:
                          InputDecoration(labelText: context.tr('Payee city')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _payeeStateController,
                      decoration:
                          InputDecoration(labelText: context.tr('Payee state')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _payeePostalCodeController,
                decoration:
                    InputDecoration(labelText: context.tr('Payee postal code')),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _commentsController,
                decoration: InputDecoration(labelText: context.tr('Comments')),
                maxLines: 2,
              ),
              if (_payeeErrorMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      _payeeErrorMessage,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ),
              ],
              if (_payeeStatusMessage.isNotEmpty) ...[
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.mark_email_read_outlined),
                    title: Text(context.tr('Verification code sent')),
                    subtitle: Text(_payeeStatusMessage),
                  ),
                ),
              ],
              if (_payeeOtpSent) ...[
                const SizedBox(height: 12),
                Text(
                  context.tr('Enter the 8-digit code sent to you.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ExampleOtpField(
                  controller: _payeeOtpController,
                  length: 8,
                  enabled: !_payeeLoading,
                  label: context.tr('OTP code'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _payeeLoading ? null : _resendPayeeOtp,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.tr('Resend code')),
                ),
              ],
              const SizedBox(height: 16),
              if (context.isExampleTheme)
                // The payee tab's commit, in the same material and the same
                // place as the pay tab's — the two tabs of one screen should
                // not answer "what do I press to finish" with two different
                // objects. Label walks Send OTP code -> Confirm payee while
                // the silhouette holds.
                ExampleGlassButton(
                  label: _payeeOtpSent
                      ? context.tr('Confirm payee')
                      : context.tr('Send OTP code'),
                  icon: _payeeOtpSent
                      ? Icons.verified_user
                      : Icons.person_add_alt,
                  loading: _payeeLoading,
                  onPressed: _payeeLoading
                      ? null
                      : (_payeeOtpSent ? _confirmPayee : _startPayeeOtp),
                )
              else
                FilledButton.icon(
                  onPressed: _payeeLoading
                      ? null
                      : (_payeeOtpSent ? _confirmPayee : _startPayeeOtp),
                  icon: Icon(_payeeOtpSent
                      ? Icons.verified_user
                      : Icons.person_add_alt),
                  label: Text(
                    _payeeLoading
                        ? context.tr('Processing...')
                        : _payeeOtpSent
                            ? context.tr('Confirm payee')
                            : context.tr('Send OTP code'),
                  ),
                ),
            ],
          ],
        ),
      ),
      error: (error, stackTrace) => _MoneyErrorState(
        error: error,
        onRetry: () => ref.invalidate(payeesProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading payees')),
    );
  }

  Future<void> _startPayeeOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    try {
      setState(() {
        _payeeLoading = true;
        _payeeErrorMessage = '';
        _payeeStatusMessage = '';
      });
      final result =
          await ref.read(mobileBankingApiProvider).initiatePayeeCreation(
                paymentType: _paymentType,
                currency: _currency,
                paymentMethod: _paymentMethod,
                countryCode: _countryCode,
                firstName: _firstNameController.text.trim(),
                lastName: _lastNameController.text.trim(),
                accountNumber: _accountController.text.trim(),
                userName: _accountHolderController.text.trim(),
                displayName: _displayNameController.text.trim(),
                bankName: _bankNameController.text.trim(),
                routingCodeType: _routingCodeType,
                routingCodeValue: _routingCodeController.text.trim(),
                bankCountry: _bankCountryCode,
                bankAddressLine1: _bankAddressController.text.trim(),
                bankAddressLine2: _bankAddress2Controller.text.trim(),
                bankCity: _bankCityController.text.trim(),
                bankState: _bankStateController.text.trim(),
                bankPostalCode: _bankPostalCodeController.text.trim(),
                payeeCountry: _payeeCountryCode,
                payeeAddressLine1: _payeeAddressController.text.trim(),
                payeeAddressLine2: _payeeAddress2Controller.text.trim(),
                payeeCity: _payeeCityController.text.trim(),
                payeeState: _payeeStateController.text.trim(),
                payeePostalCode: _payeePostalCodeController.text.trim(),
                comments: _commentsController.text.trim(),
              );
      if (!result.success || result.verificationToken.isEmpty) {
        throw StateError(
          result.message.isEmpty ? 'OTP could not be sent.' : result.message,
        );
      }
      setState(() {
        _payeeVerificationToken = result.verificationToken;
        _payeeStatusMessage = result.message.isEmpty
            ? 'Enter the OTP code to save this payee.'
            : result.message;
        _payeeOtpSent = true;
        _payeeOtpController.clear();
      });
    } catch (error) {
      setState(() => _payeeErrorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _payeeLoading = false);
      }
    }
  }

  Future<void> _scanPayeeQr() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _PayeeQrScannerScreen()),
    );
    if (payload == null || payload.trim().isEmpty) {
      return;
    }

    final details = _parsePayeeQrPayload(payload);
    if (!details.hasBankDetails) {
      setState(() {
        _payeeErrorMessage =
            'This QR code does not include bank account details we can prefill.';
        _payeeStatusMessage = payload.trim();
      });
      return;
    }

    setState(() {
      _showPayeeForm = true;
      _applyScannedPayee(details);
      _payeeStatusMessage = 'Payee details filled from QR code.';
      _payeeErrorMessage = '';
    });
  }

  void _applyScannedPayee(_ScannedPayeeDetails details) {
    _clearingPayeeForm = true;
    if (details.displayName != null) {
      _displayNameController.text = details.displayName!;
    }
    if (details.firstName != null) {
      _firstNameController.text = details.firstName!;
    }
    if (details.lastName != null) {
      _lastNameController.text = details.lastName!;
    }
    if (details.accountHolder != null) {
      _accountHolderController.text = details.accountHolder!;
    }
    if (details.accountNumber != null) {
      _accountController.text = details.accountNumber!;
    }
    if (details.bankName != null) {
      _bankNameController.text = details.bankName!;
    }
    if (details.routingCodeValue != null) {
      _routingCodeController.text = details.routingCodeValue!;
    }
    if (details.addressLine1 != null) {
      _payeeAddressController.text = details.addressLine1!;
    }
    if (details.city != null) {
      _payeeCityController.text = details.city!;
    }
    if (details.comments != null) {
      _commentsController.text = details.comments!;
    }
    if (details.countryCode != null) {
      _countryCode = details.countryCode!;
      _payeeCountryCode = details.countryCode!;
      _bankCountryCode = details.countryCode!;
    }
    if (details.currency != null) {
      _currency = details.currency!;
    }
    if (details.paymentMethod != null) {
      _paymentMethod = details.paymentMethod!;
    }
    if (details.routingCodeType != null) {
      _routingCodeType = details.routingCodeType!;
    }
    _clearingPayeeForm = false;
    _resetPayeeVerification();
  }

  Future<void> _confirmPayee() async {
    final otpCode = _payeeOtpController.text.trim();
    if (otpCode.length != 8) {
      setState(() => _payeeErrorMessage = 'Enter the full 8-digit OTP code.');
      return;
    }
    if (_payeeVerificationToken.isEmpty) {
      setState(() =>
          _payeeErrorMessage = 'Request a new OTP code before confirming.');
      return;
    }

    try {
      setState(() {
        _payeeLoading = true;
        _payeeErrorMessage = '';
      });
      final verification =
          await ref.read(mobileBankingApiProvider).verifyPayoutOtp(
                verificationToken: _payeeVerificationToken,
                otpCode: otpCode,
              );
      if (!verification.success) {
        throw StateError(
          verification.message.isEmpty
              ? 'The OTP code was not accepted.'
              : verification.message,
        );
      }
      await ref.read(mobileBankingApiProvider).confirmPayeeCreation(
            verificationToken: verification.verificationToken.isEmpty
                ? _payeeVerificationToken
                : verification.verificationToken,
          );
      ref.invalidate(payeesProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Payee saved'))),
        );
        setState(_clearPayeeForm);
      }
    } catch (error) {
      setState(() => _payeeErrorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _payeeLoading = false);
      }
    }
  }

  Future<void> _resendPayeeOtp() async {
    if (_payeeVerificationToken.isEmpty) {
      return;
    }

    try {
      setState(() {
        _payeeLoading = true;
        _payeeErrorMessage = '';
      });
      final result = await ref
          .read(mobileBankingApiProvider)
          .resendPayoutOtp(verificationToken: _payeeVerificationToken);
      if (!result.success) {
        throw StateError(
          result.message.isEmpty ? 'OTP resend failed.' : result.message,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _payeeStatusMessage =
            result.message.isEmpty ? 'OTP code resent.' : result.message;
      });
    } catch (error) {
      setState(() => _payeeErrorMessage = friendlyErrorMessage(error));
    } finally {
      if (mounted) {
        setState(() => _payeeLoading = false);
      }
    }
  }

  void _resetPayeeVerificationIfStarted() {
    if (_clearingPayeeForm) {
      return;
    }
    if (_payeeOtpSent || _payeeVerificationToken.isNotEmpty) {
      setState(_resetPayeeVerification);
    }
  }

  void _resetPayeeVerification() {
    _payeeVerificationToken = '';
    _payeeErrorMessage = '';
    _payeeStatusMessage = '';
    _payeeOtpSent = false;
    _payeeOtpController.clear();
  }

  void _clearPayeeForm() {
    _clearingPayeeForm = true;
    _displayNameController.clear();
    _firstNameController.clear();
    _lastNameController.clear();
    _accountHolderController.clear();
    _accountController.clear();
    _bankNameController.clear();
    _routingCodeController.clear();
    _bankAddressController.clear();
    _bankAddress2Controller.clear();
    _bankCityController.clear();
    _bankStateController.clear();
    _bankPostalCodeController.clear();
    _payeeAddressController.clear();
    _payeeAddress2Controller.clear();
    _payeeCityController.clear();
    _payeeStateController.clear();
    _payeePostalCodeController.clear();
    _commentsController.clear();
    _bankCountryCode = _countryCode;
    _payeeCountryCode = _countryCode;
    _clearingPayeeForm = false;
    _resetPayeeVerification();
  }
}

/// Saved payees in the Example register: one [ExampleListGroup] of 56 pt
/// [ExampleRow]s instead of a stack of Material cards, so the payee list has
/// the same rhythm, hairlines and inks as every other Example list — in both
/// themes, since the group, the rows, the tile and the pill all resolve their
/// surfaces and inks per brightness.
///
/// A utility list: no arrival moment, no stagger, and the rows carry no
/// gesture because there is nothing yet to open.
class _ExamplePayeeList extends StatelessWidget {
  const _ExamplePayeeList({required this.payees});

  final List<Payee> payees;

  @override
  Widget build(BuildContext context) {
    if (payees.isEmpty) {
      return ExampleListGroup(
        children: [
          ExampleRow(
            title: context.tr('No payees saved'),
            subtitle: context.tr('Add a recipient below before paying.'),
            leading: const ExampleIconTile(
              icon: Icons.people_outline,
              color: ExampleColors.iris,
            ),
          ),
        ],
      );
    }
    return ExampleListGroup(
      children: [
        for (final payee in payees)
          ExampleRow(
            title: _payeeLabel(payee),
            subtitle: _payeeSubtitle(payee),
            leading: ExampleIconTile(
              icon: payee.requiresConfirmation
                  ? Icons.pending_actions_outlined
                  : Icons.person_outline,
              color: payee.requiresConfirmation
                  ? ExampleColors.warning
                  : ExampleColors.iris,
            ),
            trailing: payee.requiresConfirmation
                ? ExamplePill(
                    label: context.tr('Pending'),
                    color: ExampleColors.warning,
                    dot: true,
                  )
                : null,
          ),
      ],
    );
  }
}

class _PayeeQrScannerScreen extends StatefulWidget {
  const _PayeeQrScannerScreen();

  @override
  State<_PayeeQrScannerScreen> createState() => _PayeeQrScannerScreenState();
}

class _PayeeQrScannerScreenState extends State<_PayeeQrScannerScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Scan account QR'))),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_handled) {
                return;
              }
              final rawValue = capture.barcodes
                  .map((barcode) => barcode.rawValue)
                  .whereType<String>()
                  .firstOrNull;
              if (rawValue == null || rawValue.trim().isEmpty) {
                return;
              }
              _handled = true;
              Navigator.of(context).pop(rawValue);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: double.infinity,
              color: Colors.black54,
              padding: const EdgeInsets.all(16),
              child: Text(
                context.tr('Point the camera at a bank account QR code.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannedPayeeDetails {
  const _ScannedPayeeDetails({
    this.displayName,
    this.firstName,
    this.lastName,
    this.accountHolder,
    this.accountNumber,
    this.bankName,
    this.routingCodeType,
    this.routingCodeValue,
    this.addressLine1,
    this.city,
    this.countryCode,
    this.currency,
    this.paymentMethod,
    this.comments,
  });

  final String? displayName;
  final String? firstName;
  final String? lastName;
  final String? accountHolder;
  final String? accountNumber;
  final String? bankName;
  final String? routingCodeType;
  final String? routingCodeValue;
  final String? addressLine1;
  final String? city;
  final String? countryCode;
  final String? currency;
  final String? paymentMethod;
  final String? comments;

  bool get hasBankDetails {
    return (accountNumber?.trim().isNotEmpty ?? false) ||
        (routingCodeValue?.trim().isNotEmpty ?? false);
  }
}

_ScannedPayeeDetails _parsePayeeQrPayload(String rawPayload) {
  final payload = rawPayload.trim();
  final epc = _parseEpcQrPayload(payload);
  if (epc != null) {
    return epc;
  }
  final upn = _parseUpnQrPayload(payload);
  if (upn != null) {
    return upn;
  }

  final values = _labelledQrValues(payload);
  final accountNumber = _firstValue(values, const [
    'account number',
    'iban',
    'st racuna',
    'st. racuna',
    'št racuna',
    'št. racuna',
    'št. računa',
  ]);
  final accountHolder = _firstValue(values, const [
    'account holder',
    'naziv',
    'name',
    'user name',
    'recipient',
  ]);
  final bankName = _firstValue(values, const ['bank', 'bank name']);
  final swift = _firstValue(values, const [
    'swift/bic',
    'swift',
    'bic',
    'swift code',
  ]);
  final sortCode = _firstValue(values, const ['sort code', 'sort_code']);
  final address = _firstValue(values, const ['address', 'naslov']);
  final city = _firstValue(values, const ['city', 'kraj']);
  final currencies = _firstValue(values, const [
    'available currencies',
    'currency',
  ]);
  final preferredCurrency = _firstCurrency(currencies);
  final country = _countryFromAccount(accountNumber);

  return _ScannedPayeeDetails(
    displayName: accountHolder,
    firstName: _firstNameFromFullName(accountHolder),
    lastName: _lastNameFromFullName(accountHolder),
    accountHolder: accountHolder,
    accountNumber: accountNumber?.replaceAll(' ', ''),
    bankName: bankName,
    routingCodeType: sortCode != null
        ? 'SORT_CODE'
        : swift == null
            ? null
            : 'BIC',
    routingCodeValue: sortCode ?? swift,
    addressLine1: address,
    city: city,
    countryCode: country,
    currency: preferredCurrency ?? _currencyFromCountry(country),
    paymentMethod: _paymentMethodForScannedAccount(
      accountNumber: accountNumber,
      countryCode: country,
      currency: preferredCurrency,
      hasSortCode: sortCode != null,
    ),
  );
}

_ScannedPayeeDetails? _parseUpnQrPayload(String payload) {
  final lines = payload
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  if (lines.isEmpty || !lines.first.toUpperCase().startsWith('UPNQR')) {
    return null;
  }

  final accountIndex = lines.indexWhere(_looksLikeIban);
  if (accountIndex >= 0) {
    final accountNumber = _cleanAccountNumber(lines[accountIndex]);
    final accountHolder = _lineAfter(lines, accountIndex);
    final addressLine1 = _lineAfter(lines, accountIndex + 1);
    final city = _lineAfter(lines, accountIndex + 2);
    final comments = _lineAfter(lines, accountIndex + 3);
    return _upnDetails(
      accountNumber: accountNumber,
      accountHolder: accountHolder,
      addressLine1: addressLine1,
      city: city,
      comments: comments,
    );
  }

  final compact = payload.replaceAll(RegExp(r'\s+'), ' ').trim();
  final ibanMatch = RegExp(r'\bSI\d{2}\s?\d{4}\s?\d{4}\s?\d{4}\s?\d{3}\b')
      .firstMatch(compact.toUpperCase());
  if (ibanMatch == null) {
    return null;
  }

  final accountNumber = _cleanAccountNumber(ibanMatch.group(0));
  final remainder = compact.substring(ibanMatch.end).trim();
  final parts = _splitCompactUpnRemainder(remainder);
  return _upnDetails(
    accountNumber: accountNumber,
    accountHolder: parts.accountHolder,
    addressLine1: parts.addressLine1,
    city: parts.city,
    comments: parts.comments,
  );
}

_ScannedPayeeDetails? _parseEpcQrPayload(String payload) {
  final lines =
      payload.split(RegExp(r'\r?\n')).map((line) => line.trim()).toList();
  if (lines.length < 7 || lines.first != 'BCD') {
    return null;
  }

  final swift = lines.length > 4 ? lines[4] : '';
  final name = lines.length > 5 ? lines[5] : '';
  final iban = lines.length > 6 ? lines[6] : '';
  final amountLine = lines.length > 7 ? lines[7] : '';
  final currency = amountLine.length >= 3 ? amountLine.substring(0, 3) : null;
  final country = _countryFromAccount(iban);

  return _ScannedPayeeDetails(
    displayName: name,
    firstName: _firstNameFromFullName(name),
    lastName: _lastNameFromFullName(name),
    accountHolder: name,
    accountNumber: iban,
    routingCodeType: swift.isEmpty ? null : 'BIC',
    routingCodeValue: swift.isEmpty ? null : swift,
    countryCode: country,
    currency: currency,
    paymentMethod: 'SEPA.CREDITTRANSFER',
  );
}

_ScannedPayeeDetails _upnDetails({
  required String accountNumber,
  String? accountHolder,
  String? addressLine1,
  String? city,
  String? comments,
}) {
  final country = _countryFromAccount(accountNumber);
  return _ScannedPayeeDetails(
    displayName: accountHolder,
    firstName: _firstNameFromFullName(accountHolder),
    lastName: _lastNameFromFullName(accountHolder),
    accountHolder: accountHolder,
    accountNumber: accountNumber,
    addressLine1: addressLine1,
    city: city,
    countryCode: country,
    currency: _currencyFromCountry(country),
    paymentMethod: 'SEPA.CREDITTRANSFER',
    comments: comments,
  );
}

bool _looksLikeIban(String value) {
  return RegExp(r'^[A-Z]{2}\d{2}(?:\s?[A-Z0-9]){8,30}$')
      .hasMatch(value.toUpperCase());
}

String _cleanAccountNumber(String? value) {
  return (value ?? '').replaceAll(RegExp(r'\s+'), '').toUpperCase();
}

String? _lineAfter(List<String> lines, int index) {
  final valueIndex = index + 1;
  if (valueIndex >= lines.length) {
    return null;
  }
  final value = lines[valueIndex].trim();
  return value.isEmpty ? null : value;
}

({String? accountHolder, String? addressLine1, String? city, String? comments})
    _splitCompactUpnRemainder(String remainder) {
  final tokens = remainder
      .split(RegExp(r'\s+'))
      .where((token) => token.trim().isNotEmpty)
      .toList();
  if (tokens.isEmpty) {
    return (
      accountHolder: null,
      addressLine1: null,
      city: null,
      comments: null,
    );
  }

  String? comments;
  if (tokens.length > 1 && RegExp(r'^\d{1,4}$').hasMatch(tokens.last)) {
    comments = tokens.removeLast();
  }

  final streetIndex = _compactStreetIndex(tokens);
  if (streetIndex > 0) {
    final addressStart = streetIndex - 1;
    var addressEnd = tokens.length;
    for (var index = streetIndex + 1; index < tokens.length; index++) {
      if (RegExp(r'\d').hasMatch(tokens[index])) {
        addressEnd = index + 1;
        break;
      }
    }
    final accountHolder = tokens.take(addressStart).join(' ').trim();
    final addressLine1 =
        tokens.skip(addressStart).take(addressEnd - addressStart).join(' ');
    final city = tokens.skip(addressEnd).join(' ').trim();
    return (
      accountHolder: accountHolder.isEmpty ? null : accountHolder,
      addressLine1: addressLine1.isEmpty ? null : addressLine1,
      city: city.isEmpty ? null : city,
      comments: comments,
    );
  }

  if (tokens.length >= 4) {
    final accountHolder = tokens.take(2).join(' ');
    final city = tokens.length > 3 ? tokens.last : null;
    final addressLine1 =
        tokens.skip(2).take(tokens.length - (city == null ? 2 : 3)).join(' ');
    return (
      accountHolder: accountHolder,
      addressLine1: addressLine1.isEmpty ? null : addressLine1,
      city: city,
      comments: comments,
    );
  }

  return (
    accountHolder: tokens.join(' '),
    addressLine1: null,
    city: null,
    comments: comments,
  );
}

int _compactStreetIndex(List<String> tokens) {
  const streetWords = {
    'CESTA',
    'ULICA',
    'POT',
    'TRG',
    'NASELJE',
    'KOLONIJA',
    'BREG',
    'OBALA',
    'GASA',
    'GAJ',
    'POLJE',
  };
  return tokens.indexWhere((token) {
    final normalized = _normalizeQrLabel(token).toUpperCase();
    return streetWords.contains(normalized);
  });
}

Map<String, String> _labelledQrValues(String payload) {
  final values = <String, String>{};
  for (final line in payload.split(RegExp(r'\r?\n'))) {
    final separatorIndex = line.indexOf(':');
    if (separatorIndex <= 0) {
      continue;
    }
    final key = _normalizeQrLabel(line.substring(0, separatorIndex));
    final value = line.substring(separatorIndex + 1).trim();
    if (key.isNotEmpty && value.isNotEmpty) {
      values[key] = value;
    }
  }
  return values;
}

String _normalizeQrLabel(String label) {
  return label
      .toLowerCase()
      .replaceAll('č', 'c')
      .replaceAll('š', 's')
      .replaceAll('ž', 'z')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _firstValue(Map<String, String> values, List<String> keys) {
  for (final key in keys) {
    final value = values[_normalizeQrLabel(key)];
    if (value != null && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return null;
}

String? _firstCurrency(String? value) {
  if (value == null) {
    return null;
  }
  final match = RegExp(r'\b[A-Z]{3}\b').firstMatch(value.toUpperCase());
  return match?.group(0);
}

String? _countryFromAccount(String? accountNumber) {
  final trimmed = accountNumber?.replaceAll(' ', '').toUpperCase() ?? '';
  if (trimmed.length >= 2 && RegExp(r'^[A-Z]{2}').hasMatch(trimmed)) {
    return trimmed.substring(0, 2);
  }
  return null;
}

String _currencyFromCountry(String? countryCode) {
  return switch (countryCode) {
    'GB' => 'GBP',
    _ => 'EUR',
  };
}

String _paymentMethodForScannedAccount({
  required String? accountNumber,
  required String? countryCode,
  required String? currency,
  required bool hasSortCode,
}) {
  if (hasSortCode || countryCode == 'GB' || currency == 'GBP') {
    return 'UKFPS';
  }
  if ((accountNumber ?? '')
          .replaceAll(' ', '')
          .toUpperCase()
          .startsWith('SI') ||
      currency == 'EUR') {
    return 'SEPA.CREDITTRANSFER';
  }
  return 'SWIFT';
}

String? _firstNameFromFullName(String? value) {
  final parts = _nameParts(value);
  if (parts.length <= 1) {
    return parts.firstOrNull;
  }
  return parts.take(parts.length - 1).join(' ');
}

String? _lastNameFromFullName(String? value) {
  final parts = _nameParts(value);
  return parts.isEmpty ? null : parts.last;
}

List<String> _nameParts(String? value) {
  return (value ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
}

class _PayoutQuoteCard extends StatelessWidget {
  const _PayoutQuoteCard({
    required this.quote,
    required this.check,
    required this.otpSent,
  });

  final PayoutQuote quote;
  final PayoutCheck? check;
  final bool otpSent;

  @override
  Widget build(BuildContext context) {
    final expiresAt = quote.expiresAt;
    final isExample = context.isExampleTheme;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          otpSent
              ? context.tr('Live quote for confirmation')
              : context.tr('Fee and quote'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _QuoteRow(
          label: context.tr('Sending'),
          value:
              '${quote.sourceCurrency} ${quote.sourceAmount.toStringAsFixed(2)}',
        ),
        _QuoteRow(
          label: context.tr('Recipient gets'),
          value:
              '${quote.targetCurrency} ${quote.targetAmount.toStringAsFixed(2)}',
        ),
        _QuoteRow(label: context.tr('Fee'), value: quote.feeLabel),
        _QuoteRow(label: context.tr('Rate'), value: quote.rateLabel),
        if (expiresAt != null)
          _QuoteRow(
            label: context.tr('Expires'),
            value: TimeOfDay.fromDateTime(expiresAt.toLocal()).format(context),
          ),
        if (check != null)
          _QuoteRow(
            label: context.tr('Validation'),
            value: check!.pass
                ? 'Passed'
                : fallbackText(check!.message, 'Blocked'),
          ),
      ],
    );
    // Example reads the quote off a matte panel with the daylight and Twilight
    // surfaces the rest of the app uses; every other brand keeps its Material
    // card, byte for byte.
    if (isExample) {
      return ExampleGlassPanel(
        radius: AppRadii.lg,
        padding: const EdgeInsets.all(16),
        child: body,
      );
    }
    return Card(
      child: Padding(padding: const EdgeInsets.all(16), child: body),
    );
  }
}

class _QuoteRow extends StatelessWidget {
  const _QuoteRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    // Example flexes the label column instead of pinning it to 108 px, so a
    // 1.3 text scale widens it instead of wrapping it, and sets the value in
    // tabular figures so the quote's numbers line up. Other brands keep the
    // fixed column they render today.
    final labelText = Text(
      label,
      style: isExample
          ? theme.textTheme.bodySmall?.copyWith(
              color: ExampleInk.secondary(context),
            )
          : theme.textTheme.bodySmall,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isExample) ...[
            Flexible(flex: 4, child: labelText),
            const SizedBox(width: AppSpacing.sm),
          ] else
            SizedBox(width: 108, child: labelText),
          Expanded(
            flex: isExample ? 6 : 1,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: isExample
                  ? theme.textTheme.bodyMedium?.copyWith(
                      color: ExampleInk.primary(context),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({
    required this.controller,
    this.currency = 'EUR',
    this.onChanged,
  });

  final TextEditingController controller;
  final String currency;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: context.tr('Amount'),
        prefixText: '$currency ',
      ),
      validator: (value) {
        final parsed = double.tryParse((value ?? '').replaceAll(',', '.'));
        if (parsed == null || parsed <= 0) {
          return context.tr('Enter an amount');
        }

        return null;
      },
    );
  }
}

class _SelectField extends StatelessWidget {
  const _SelectField({
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
      validator: _required,
      onChanged: (value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}

String? _required(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Required';
  }

  return null;
}

String _payeeLabel(Payee payee) {
  return fallbackText(payee.name, 'Payee');
}

String _payeeSubtitle(Payee payee) {
  final parts = [
    if (payee.accountReference.trim().isNotEmpty) payee.accountReference.trim(),
    if (payee.currency.trim().isNotEmpty) payee.currency.trim(),
    if (payee.paymentMethod.trim().isNotEmpty) payee.paymentMethod.trim(),
    if (payee.provider.trim().isNotEmpty) payee.provider.trim(),
    if (payee.requiresConfirmation) 'confirmation required',
  ];

  return fallbackText(parts.join(' • '), 'Account unavailable');
}

/// Resolve decorative hues without changing the inherited theme's defaults.
Color _decorationColor(BuildContext context, String key, Color fallback) =>
    context.brandDesign
        .color(Theme.of(context).brightness, key, fallback: fallback);
