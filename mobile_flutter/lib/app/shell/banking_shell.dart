import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:ui' show ImageFilter, SemanticsRole;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../brands/example/example_sheen.dart';
import '../../brands/example/example_tokens.dart';
import '../../brands/example/example_tilt.dart';
import '../../brands/example/example_ui.dart';
import '../../core/api/dio_provider.dart';
import '../../core/branding/app_design.dart';
import '../../core/models/banking_models.dart';
import '../../features/assistant/presentation/sparkle_icon.dart';
import '../../features/banking/application/banking_providers.dart';
import '../../features/cards/presentation/widgets/card_face.dart';
import '../../features/platform/application/platform_providers.dart';
import '../routes.dart';

/// The chrome hairline that separates a bar, a rail or the aside from the
/// page. Twilight keeps the 10% lavender edge the shell has always drawn;
/// daylight uses the lavender .30 hairline, which is as quiet on paper as
/// .10 is on night.
Color _shellColor(BuildContext context, String key, Color fallback) =>
    context.brandDesign
        .color(Theme.of(context).brightness, key, fallback: fallback);

BorderSide _chromeEdge(BuildContext context) => BorderSide(
      color: _shellColor(
          context,
          'borderSubtle',
          ExampleTheme.isLight(context)
              ? ExampleColors.lightBorderSubtle
              : ExampleColors.lavender.withValues(alpha: .10)),
    );

typedef ShellDestination = ({NavigationDestination item, String route});

/// Layout breakpoints for the EXAMPLE Twilight shell.
abstract final class ExampleBreakpoints {
  /// Rail + top bar instead of the bottom navigation.
  static const double desktop = kIsWeb ? 600 : 760;

  /// Wide desktop: the Home screen gains the right-hand card rail.
  static const double aside = 1200;

  /// Compact rail (tablet exemplars in the design canvas).
  static const double compactRail = 1000;
}

class BankingShell extends ConsumerWidget {
  const BankingShell({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isExample = ref.watch(appConfigProvider).branding.isExample;
    final tenantConfig = ref.watch(mobileTenantConfigProvider).valueOrNull;
    final rewardsEnabled = tenantConfig != null &&
        (tenantConfig.referralsEnabled || tenantConfig.vouchersEnabled);
    final dashboard = ref.watch(dashboardProvider);
    final isBusinessAccount = dashboard.maybeWhen(
      data: (dashboard) => dashboard.profile.isBusinessAccount,
      orElse: () => false,
    );
    final accountsRoute = tenantConfig?.equalsMoneyEnabled == false
        ? AppRoutes.walletAssets
        : AppRoutes.money;
    final destinations = <ShellDestination>[
      (
        item: NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home_rounded),
          label: context.tr('Home'),
        ),
        route: AppRoutes.home,
      ),
      (
        item: NavigationDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet_rounded),
          label: context.tr('Accounts'),
        ),
        route: accountsRoute,
      ),
      if (!isBusinessAccount)
        (
          item: NavigationDestination(
            icon: const Icon(Icons.credit_card_outlined),
            selectedIcon: const Icon(Icons.credit_card_rounded),
            label: context.tr('Cards'),
          ),
          route: AppRoutes.cards,
        ),
      (
        item: NavigationDestination(
          icon: const Icon(Icons.receipt_long_outlined),
          selectedIcon: const Icon(Icons.receipt_long_rounded),
          label: context.tr('Activity'),
        ),
        route: AppRoutes.activity,
      ),
      if (rewardsEnabled || (isExample && !isBusinessAccount))
        (
          item: NavigationDestination(
            icon: const Icon(Icons.card_giftcard_outlined),
            selectedIcon: const Icon(Icons.card_giftcard_rounded),
            label: context.tr('Rewards'),
          ),
          route: AppRoutes.rewards,
        ),
      if (isExample)
        (
          item: NavigationDestination(
            icon: const SparkleIcon(size: 20),
            selectedIcon: const SparkleIcon(selected: true, size: 20),
            label: context.tr('Ask AI'),
          ),
          route: AppRoutes.askAi,
        ),
    ];
    final selected = _selectedIndex(
      context,
      destinations: destinations,
      accountsRoute: accountsRoute,
    );
    final location = GoRouterState.of(context).uri.path;
    final isCardDetail = RegExp(r'^/cards/[^/]+$').hasMatch(location);
    final isTransactionDetail =
        RegExp(r'^/transactions/(?!status$)[^/]+$').hasMatch(location);
    final hideNavigation = isCardDetail ||
        (isExample &&
            (location.startsWith(AppRoutes.profile) || isTransactionDetail));

    if (!isExample) {
      return Scaffold(
        body:
            Semantics(container: true, explicitChildNodes: true, child: child),
        bottomNavigationBar: hideNavigation
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.xl),
                    child: NavigationBar(
                      selectedIndex: selected < 0 ? 0 : selected,
                      onDestinationSelected: (index) {
                        HapticFeedback.selectionClick();
                        context.go(destinations[index].route);
                      },
                      destinations:
                          destinations.map((entry) => entry.item).toList(),
                    ),
                  ),
                ),
              ),
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    if (width >= ExampleBreakpoints.desktop) {
      final exchangeEnabled =
          !isBusinessAccount && tenantConfig?.boomFiExchangeEnabled == true;
      return _ExampleDesktopShell(
        destinations: destinations,
        selectedIndex: selected,
        location: location,
        showExchange: exchangeEnabled,
        settingsSelected: location.startsWith(AppRoutes.profile),
        peerSelected: location.startsWith(AppRoutes.peer),
        dashboard: dashboard,
        child: child,
      );
    }

    return ExampleGlow(
      child: Theme(
        data: theme.copyWith(scaffoldBackgroundColor: Colors.transparent),
        child: ExampleAliveLayer(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            body: Semantics(
                container: true, explicitChildNodes: true, child: child),
            bottomNavigationBar: hideNavigation
                ? null
                : _ExampleBottomBar(
                    destinations: destinations,
                    selectedIndex: selected < 0 ? 0 : selected,
                    onSelected: (index) {
                      HapticFeedback.selectionClick();
                      context.go(destinations[index].route);
                    },
                  ),
          ),
        ),
      ),
    );
  }

  int _selectedIndex(
    BuildContext context, {
    required List<ShellDestination> destinations,
    required String accountsRoute,
  }) {
    final location = GoRouterState.of(context).uri.path;
    if (location.startsWith(AppRoutes.accounts) ||
        location.startsWith(AppRoutes.money) ||
        location.startsWith(AppRoutes.payments) ||
        location.startsWith(AppRoutes.bankingServices) ||
        location.startsWith(AppRoutes.wallets) ||
        location.startsWith(AppRoutes.crypto)) {
      // By route, never by label: the label is translated, so in German it
      // is "Konten" and a comparison against "Accounts" left the rail with
      // nothing marked while the Accounts page was open.
      return destinations.indexWhere((entry) => entry.route == accountsRoute);
    }
    if (location.startsWith(AppRoutes.cards)) {
      final index =
          destinations.indexWhere((entry) => entry.route == AppRoutes.cards);
      return index < 0 ? 0 : index;
    }
    if (location.startsWith(AppRoutes.activity) ||
        location.startsWith(AppRoutes.transactions) ||
        location.startsWith(AppRoutes.transactionStatus)) {
      return destinations
          .indexWhere((entry) => entry.route == AppRoutes.activity);
    }
    if (location.startsWith(AppRoutes.rewards)) {
      final index =
          destinations.indexWhere((entry) => entry.route == AppRoutes.rewards);
      return index < 0 ? 0 : index;
    }
    if (location.startsWith(AppRoutes.askAi)) {
      return destinations.indexWhere((entry) => entry.route == AppRoutes.askAi);
    }
    if (location.startsWith(AppRoutes.home)) return 0;
    // Send & request is a rail item on desktop and lives under Home on phones.
    return -1;
  }
}

/// Desktop / tablet PWA layout from the Example App canvas: a 76pt icon rail,
/// a 76pt page header owned by each screen's [AppBar], and on Home a
/// 336pt aside with the card, spending and install panels.
class _ExampleDesktopShell extends StatelessWidget {
  const _ExampleDesktopShell({
    required this.child,
    required this.destinations,
    required this.selectedIndex,
    required this.location,
    required this.showExchange,
    required this.settingsSelected,
    required this.peerSelected,
    required this.dashboard,
  });

  final Widget child;
  final List<ShellDestination> destinations;
  final int selectedIndex;
  final String location;
  final bool showExchange;
  final bool settingsSelected;
  final bool peerSelected;
  final AsyncValue<DashboardSnapshot> dashboard;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < ExampleBreakpoints.compactRail;
    final headerHeight = compact ? 62.0 : 76.0;
    final showAside =
        location == AppRoutes.home && width >= ExampleBreakpoints.aside;
    final exchangeSelected = location.startsWith(AppRoutes.walletExchange);
    final shellTheme = theme.copyWith(
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: Colors.transparent,
        toolbarHeight: headerHeight,
        titleSpacing: compact ? 24 : 40,
        actionsPadding: EdgeInsets.only(right: compact ? 16 : 32),
        centerTitle: false,
        titleTextStyle: theme.textTheme.titleMedium?.copyWith(
          color: ExampleInk.primary(context),
          fontSize: 17 * context.brandDesign.typographyScale,
          fontWeight: FontWeight.w600,
        ),
        shape: Border(bottom: _chromeEdge(context)),
      ),
    );

    return ExampleGlow(
      desktop: true,
      child: ExampleAliveLayer(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ExampleRail(
                width: compact ? 70 : 76,
                destinations: destinations,
                selectedIndex: selectedIndex,
                showExchange: showExchange,
                exchangeSelected: exchangeSelected,
                settingsSelected: settingsSelected,
                peerSelected: peerSelected,
                userName: dashboard.valueOrNull?.profile.name ?? '',
              ),
              // Keep the nested route barrier from hiding its sibling rail.
              Expanded(
                child: Semantics(
                    container: true,
                    explicitChildNodes: true,
                    child: Theme(data: shellTheme, child: child)),
              ),
              if (showAside)
                _ExampleHomeAside(
                  headerHeight: headerHeight,
                  dashboard: dashboard,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExampleRail extends StatelessWidget {
  const _ExampleRail({
    required this.width,
    required this.destinations,
    required this.selectedIndex,
    required this.showExchange,
    required this.exchangeSelected,
    required this.settingsSelected,
    required this.peerSelected,
    required this.userName,
  });

  final double width;
  final List<ShellDestination> destinations;
  final int selectedIndex;
  final bool showExchange;
  final bool exchangeSelected;
  final bool settingsSelected;
  final bool peerSelected;
  final String userName;

  @override
  Widget build(BuildContext context) {
    final navSelected = !settingsSelected && !exchangeSelected && !peerSelected;
    final palette = ExamplePalette.of(context);
    // The .75 alpha on both rail surfaces was always meant to sit over a
    // blur; high contrast drops the blur and takes the opaque chrome ground
    // instead, exactly as ExampleGlassPanel does.
    final frosted = !(MediaQuery.maybeHighContrastOf(context) ?? false);
    final rail = Container(
      width: width,
      decoration: BoxDecoration(
        color: frosted ? palette.rail : palette.navigation,
        border: Border(
          right: BorderSide(
            color: _shellColor(
                context,
                'borderSubtle',
                palette.isDark
                    ? ExampleColors.iris.withValues(alpha: .16)
                    : ExampleColors.lightBorderSubtle),
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 22),
            const ExampleMark(size: 28),
            const SizedBox(height: 26),
            for (var index = 0; index < destinations.length; index++) ...[
              _RailItem(
                icon: destinations[index].item.icon,
                selectedIcon: destinations[index].item.selectedIcon,
                label: destinations[index].item.label,
                selected: navSelected && selectedIndex == index,
                onTap: () => context.go(destinations[index].route),
              ),
              const SizedBox(height: 10),
              if (destinations[index].route == AppRoutes.home) ...[
                _RailItem(
                  icon: const Icon(Icons.send_outlined),
                  selectedIcon: const Icon(Icons.send_rounded),
                  label: context.tr('Send'),
                  selected: peerSelected,
                  onTap: () => context.go(AppRoutes.peer),
                ),
                const SizedBox(height: 10),
              ],
              if (showExchange &&
                  destinations[index].route == AppRoutes.activity) ...[
                _RailItem(
                  icon: const Icon(Icons.swap_horiz_rounded),
                  selectedIcon: const Icon(Icons.swap_horiz_rounded),
                  label: context.tr('Exchange'),
                  selected: exchangeSelected,
                  onTap: () => context.go(AppRoutes.walletExchange),
                ),
                const SizedBox(height: 10),
              ],
            ],
            _RailItem(
              icon: const Icon(Icons.settings_outlined),
              selectedIcon: const Icon(Icons.settings_rounded),
              label: context.tr('Settings'),
              selected: settingsSelected,
              onTap: () => context.go(AppRoutes.profile),
            ),
            const Spacer(),
            Tooltip(
              message: userName.isEmpty ? context.tr('Profile') : userName,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => context.go(AppRoutes.profile),
                child: ExampleAvatar(name: userName),
              ),
            ),
            const SizedBox(height: 22),
          ],
        ),
      ),
    );
    if (!frosted) return _seated(context, rail);
    return _seated(
      context,
      RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: ExampleGlassPanel.frostSigma,
              sigmaY: ExampleGlassPanel.frostSigma,
            ),
            child: rail,
          ),
        ),
      ),
    );
  }

  /// Gives the rail a floor on paper. Frosted white over a near-white ground
  /// is a +4/255 plane with a 1.03:1 hairline, so daylight seats the chrome on
  /// the ambient sheet shadow. Twilight casts none, exactly as before, and the
  /// shadow sits outside the ClipRect so the blur never eats it.
  Widget _seated(BuildContext context, Widget child) => Semantics(
        container: true,
        explicitChildNodes: true,
        role: SemanticsRole.navigation,
        label: context.tr('Primary navigation'),
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: ExampleTheme.isLight(context)
                ? ExampleShadows.sheetOf(context)
                : ExampleShadows.none,
          ),
          child: child,
        ),
      );
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget icon;
  final Widget? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    final colors = ExamplePalette.of(context);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: ExampleMotion.of(context, ExampleMotion.state),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: selected
                  ? colors.fill.withValues(alpha: light ? .12 : .24)
                  : Colors.transparent,
              border: Border.all(
                color: selected
                    ? colors.accent.withValues(alpha: light ? .70 : .5)
                    : Colors.transparent,
              ),
              // A bloom under a chip reads as light on night and as a
              // smudge on paper, so daylight separates by fill and edge.
              boxShadow: selected && !light
                  ? ExampleShadows.glow(
                      colors.fill,
                      alpha: .55,
                      blur: 18,
                      spread: -4,
                    )
                  : null,
            ),
            child: IconTheme(
              data: IconThemeData(
                size: 22,
                color: selected
                    ? (light ? colors.accent : colors.ink)
                    : _shellColor(
                        context,
                        'textTertiary',
                        light
                            ? ExampleColors.lightTextTertiary
                            : ExampleColors.pearl.withValues(alpha: .55)),
              ),
              child: selected ? (selectedIcon ?? icon) : icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExampleHomeAside extends ConsumerWidget {
  const _ExampleHomeAside({
    required this.headerHeight,
    required this.dashboard,
  });

  final double headerHeight;
  final AsyncValue<DashboardSnapshot> dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = dashboard.valueOrNull;
    final cards = snapshot?.cards
            .where((card) => card.status != CardStatus.cancelled)
            .toList() ??
        const <PaymentCard>[];
    final card = cards.firstOrNull;
    final busy = ref.watch(bankingActionControllerProvider).isLoading;
    final showCards = snapshot?.profile.isBusinessAccount != true;

    return Container(
      width: 336,
      decoration: BoxDecoration(
        border: Border(left: _chromeEdge(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: headerHeight,
            decoration: BoxDecoration(
              border: Border(bottom: _chromeEdge(context)),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(28, 32, 28, 32),
              children: [
                if (showCards) ...[
                  _AsideTitle(context.tr('Your card')),
                  const SizedBox(height: 14),
                  if (card == null)
                    ExampleGlassPanel(
                      onTap: () => context.go(AppRoutes.cards),
                      child: Text(
                        context.tr('Order your {p0} card to see it here.', {
                          'p0': AppDesignTheme.nameOf(context).isEmpty
                              ? 'payment'
                              : AppDesignTheme.nameOf(context)
                        }),
                        style: TextStyle(color: ExampleInk.secondary(context)),
                      ),
                    )
                  else ...[
                    ExampleTiltCard(
                      maxAngle: .16,
                      child: CardFace(
                        card: card,
                        height: 176,
                        enableHoverTilt: false,
                        onTap: () =>
                            context.go(AppRoutes.cardsWithSelection(card.id)),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _AsideButton(
                            label: card.status == CardStatus.frozen
                                ? context.tr('Unfreeze')
                                : context.tr('Freeze'),
                            onTap: busy
                                ? null
                                : () => _toggleFreeze(context, ref, card),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _AsideButton(
                            label: context.tr('Details'),
                            onTap: () =>
                                context.go(AppRoutes.cardDetail(card.id)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (cards.isNotEmpty) ...[
                    _SpendingPanel(cards: cards),
                    const SizedBox(height: 24),
                  ],
                ],
                if (kIsWeb) const _InstallPanel(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleFreeze(
    BuildContext context,
    WidgetRef ref,
    PaymentCard card,
  ) async {
    final shouldFreeze = card.status != CardStatus.frozen;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(shouldFreeze
            ? context.tr('Freeze card?')
            : context.tr('Unfreeze card?')),
        content: Text(
          shouldFreeze
              ? context
                  .tr('Card payments will be blocked until you unfreeze it.')
              : context.tr('Card payments will be allowed again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
                shouldFreeze ? context.tr('Freeze') : context.tr('Unfreeze')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(bankingActionControllerProvider.notifier)
        .freezeCard(card.id, shouldFreeze);
    ref
      ..invalidate(cardsProvider)
      ..invalidate(dashboardProvider);
  }
}

class _AsideTitle extends StatelessWidget {
  const _AsideTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: ExampleInk.primary(context),
          fontSize: 14 * context.brandDesign.typographyScale,
          fontWeight: FontWeight.w600,
        ),
      );
}

class _AsideButton extends StatelessWidget {
  const _AsideButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          side: BorderSide(
              color: _shellColor(
                  context,
                  'borderSubtle',
                  ExampleTheme.isLight(context)
                      ? ExampleColors.lightBorderSubtle
                      : ExampleColors.lavender.withValues(alpha: .16))),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(11),
          ),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 12.5 * context.brandDesign.typographyScale,
                fontWeight: FontWeight.w600,
              ),
        ),
        onPressed: onTap,
        child: Text(label),
      );
}

class _SpendingPanel extends StatelessWidget {
  const _SpendingPanel({required this.cards});

  final List<PaymentCard> cards;

  @override
  Widget build(BuildContext context) {
    final currency = cards.first.balance.currency;
    final sameCurrency =
        cards.where((card) => card.balance.currency == currency).toList();
    final total = sameCurrency.fold<int>(
      0,
      (sum, card) => sum + card.balance.minorUnits.abs(),
    );
    // A four-swatch ramp that separates by hue *and* by lightness in both
    // themes. Twilight climbs from violet into pale lavender because it sits
    // on night; daylight has to walk the other way, so it starts on the
    // daylight fill and ends on indigo, and every swatch clears 3:1 on white.
    final palette = ExampleTheme.pick(
      context,
      dark: [
        ExamplePalette.of(context).fill,
        ExamplePalette.of(context).accent,
        _shellColor(context, 'textSecondary', ExampleColors.lavender),
        ExamplePalette.of(context).teal,
      ],
      light: [
        ExamplePalette.of(context).fill,
        _shellColor(context, 'accent', ExampleColors.violet),
        ExamplePalette.of(context).teal,
        _shellColor(context, 'ink', ExampleColors.indigo),
      ],
    );
    return ExampleGlassPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AsideTitle(context.tr('Card balances')),
          const SizedBox(height: 12),
          Text(
            Money(currency: currency, minorUnits: total).formatted,
            style: TextStyle(
              color: ExampleInk.primary(context),
              fontSize: 24 * context.brandDesign.typographyScale,
              fontWeight: FontWeight.w600,
              letterSpacing: -.6,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  for (var index = 0; index < sameCurrency.length; index++)
                    Expanded(
                      flex: total == 0
                          ? 0
                          : sameCurrency[index].balance.minorUnits.abs(),
                      child: ColoredBox(
                        color: palette[index % palette.length],
                      ),
                    ),
                  Expanded(
                    flex: total == 0 ? 1 : (total ~/ 4).clamp(1, total),
                    child: ColoredBox(
                      color: ExampleSurface.of(context, 2),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < sameCurrency.length; index++)
            Padding(
              padding: EdgeInsets.only(
                bottom: index == sameCurrency.length - 1 ? 0 : 9,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: palette[index % palette.length],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      sameCurrency[index].last4.isEmpty
                          ? sameCurrency[index].displayLabel
                          : '${sameCurrency[index].displayLabel} •• ${sameCurrency[index].last4}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ExampleInk.secondary(context),
                        fontSize: 12.5 * context.brandDesign.typographyScale,
                      ),
                    ),
                  ),
                  Text(
                    sameCurrency[index].balance.formatted,
                    style: TextStyle(
                      color: ExampleInk.primary(context),
                      fontSize: 12.5 * context.brandDesign.typographyScale,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InstallPanel extends StatelessWidget {
  const _InstallPanel();

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        emphasis: true,
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.download_rounded,
                  size: 18,
                  color: ExampleInk.accent(context, ExampleColors.iris),
                ),
                const SizedBox(width: 9),
                Expanded(
                    child: _AsideTitle(context.tr('Install {p0}', {
                  'p0': AppDesignTheme.nameOf(context).isEmpty
                      ? 'app'
                      : AppDesignTheme.nameOf(context)
                }))),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              context.tr(
                  'Add {p0} to this device and open it from your dock or start menu.',
                  {
                    'p0': AppDesignTheme.nameOf(context).isEmpty
                        ? 'the app'
                        : AppDesignTheme.nameOf(context)
                  }),
              style: TextStyle(
                color: ExampleInk.tertiary(context),
                fontSize: 12.5 * context.brandDesign.typographyScale,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontSize: 13 * context.brandDesign.typographyScale,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.tr(
                          "Use your browser's \"Install app\" option in the address bar to add {p0} to this device.",
                          {
                            'p0': AppDesignTheme.nameOf(context).isEmpty
                                ? 'the app'
                                : AppDesignTheme.nameOf(context)
                          }),
                    ),
                  ),
                ),
                child: Text(context.tr('Install app')),
              ),
            ),
          ],
        ),
      );
}

/// The Example bottom navigation: frosted over the atmosphere in both themes,
/// with a travelling light bar on the active tab.
///
/// The .85 alpha on [ExampleColors.navigationGlass] was always written for a
/// blur it never had; it has one now, and daylight mirrors it at white .60
/// into white .85 on the same hairline. The blur is the only one in the
/// shell chrome, bounded by its own [ClipRect] inside a [RepaintBoundary],
/// and it drops to the opaque chrome ground under high contrast.
class _ExampleBottomBar extends StatelessWidget {
  const _ExampleBottomBar({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<ShellDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final light = ExampleTheme.isLight(context);
    final frosted = !(MediaQuery.maybeHighContrastOf(context) ?? false);
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: frosted ? null : palette.navigation,
        gradient: frosted
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [palette.glassTop, palette.navigationGlass],
              )
            : null,
        border: Border(top: _chromeEdge(context)),
      ),
      child: SafeArea(
        top: false,
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelected,
          destinations: destinations.map((entry) => entry.item).toList(),
        ),
      ),
    );
    final plane = frosted
        ? RepaintBoundary(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: ExampleGlassPanel.frostSigma,
                  sigmaY: ExampleGlassPanel.frostSigma,
                ),
                child: surface,
              ),
            ),
          )
        : surface;
    // The indicator is a sheen host, and a sheen host inside a BackdropFilter
    // makes the blur re-run every frame of every sweep — 17 to 23 percent duty
    // cycle on the most expensive layer in the app, permanently, on every
    // shell screen. Painting it *above* the frosted plane is the same pixels
    // and a static blur. The enclosing RepaintBoundary cannot do this job: it
    // isolates the subtree from its parent, not the filter from its own child.
    //
    // On paper the plane also needs a floor: white .60 into white .85 over
    // F8F5FC is a +4/255 plane with a 1.03:1 hairline, so daylight seats the
    // bar on the upward ambient sheet shadow. Twilight casts none, exactly as
    // before.
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: light ? ExampleShadows.sheetOf(context) : ExampleShadows.none,
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          plane,
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: _ExampleNavIndicator.height,
            child: _ExampleNavIndicator(
              count: destinations.length,
              index: selectedIndex,
            ),
          ),
        ],
      ),
    );
  }
}

/// The active tab, marked by a lit segment of the bar's own top edge rather
/// than by a pill behind the icon: the tab labels already carry the accent,
/// and a 3 pt rail reads as precision instead of as another rounded chip.
///
/// It is one of the law's sheen hosts, so a soft band crosses it on arrival
/// and once a cadence after that. It travels between tabs in
/// [ExampleMotion.state] and instantly under reduced motion; nothing else on
/// the bar moves, and it is decorative, so it is out of the semantics tree.
class _ExampleNavIndicator extends StatelessWidget {
  const _ExampleNavIndicator({required this.count, required this.index});

  final int count;
  final int index;

  static const double height = 3;
  static const double width = 26;
  static const BorderRadius _radius =
      BorderRadius.vertical(bottom: Radius.circular(2));

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final light = ExampleTheme.isLight(context);
    final colors = ExamplePalette.of(context);
    final bar = ExampleSheen(
      borderRadius: _radius,
      intensity: ExampleSheenIntensity.onFill,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [colors.fill, colors.accent],
          ),
          borderRadius: _radius,
          boxShadow: light
              ? null
              : ExampleShadows.glow(
                  colors.fill,
                  alpha: .55,
                  blur: 14,
                  spread: -3,
                ),
        ),
        child: const SizedBox.expand(),
      ),
    );
    return ExcludeSemantics(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final slot = constraints.maxWidth / count;
            final target = slot * index + (slot - width) / 2;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  width: width,
                  height: height,
                  // Transform, not AnimatedPositioned: the law animates
                  // transform and opacity only, and a translated child costs
                  // no relayout of the bar on any frame of the travel.
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: target),
                    duration: ExampleMotion.of(context, ExampleMotion.state),
                    curve: ExampleMotion.out,
                    builder: (context, value, child) => Transform.translate(
                      offset: Offset(value, 0),
                      child: child,
                    ),
                    child: bar,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
