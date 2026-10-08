import '../../../core/cache/saved_data_status.dart';
import '../data/dashboard_display_provider.dart';
import '../../../shared/widgets/refresh_action.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/formatters/transaction_display.dart';
import '../../../brands/example/example.dart';
import '../../../app/shell/banking_shell.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../cards/presentation/widgets/neo_bank_card.dart';
import '../../platform/application/platform_providers.dart';
import '../../notifications/notifications.dart';
import '../../wallets/data/wallet_providers.dart';
import '../../wallets/presentation/deposit_address_dialog.dart';
import '../data/dashboard_providers.dart';
import '../domain/dashboard_models.dart';
import 'example_dashboard.dart';

Future<void> _retryDashboard(WidgetRef ref) async {
  try {
    // A composed-provider retry alone reuses failed source futures forever.
    await ref.read(refreshHoppaDashboardProvider)();
  } catch (_) {
    // The provider renders the new error; a button callback must not leak it.
  }
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  static const routePath = '/home';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(dashboardDisplayProvider);
    return SavedDataStatus(
      snapshot: snapshot,
      onRetry: () => ref.read(refreshHoppaDashboardProvider)(),
      child: _DashboardContent(dashboard: snapshot.value),
    );
  }
}

class _DashboardContent extends ConsumerWidget {
  const _DashboardContent({required this.dashboard});

  final AsyncValue<HoppaDashboardSnapshot> dashboard;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(appConfigProvider).branding;
    final unreadNotifications = ref.watch(unreadNotificationCountProvider);

    if (branding.isExample) {
      return dashboard.when(
        // Top-up refreshes wallet dependencies before opening its dialog.
        // Keep the existing Home mounted so that refresh cannot dispose the
        // button's context and silently cancel the pending action.
        skipLoadingOnReload: true,
        data: (snapshot) => ExampleDashboard(
          snapshot: snapshot,
          unreadNotifications: unreadNotifications.valueOrNull ?? 0,
          onRefresh: () => ref.read(refreshHoppaDashboardProvider)(),
        ),
        error: (error, stackTrace) => Scaffold(
          body: ErrorState(
            error: error,
            onRetry: () => _retryDashboard(ref),
          ),
        ),
        // Home is the first surface anyone sees, and it used to open on a
        // centred spinner: a grey disc on paper says nothing about what is
        // coming, and it is the one moment where every competitor in this
        // category shows the page assembling instead. The skeleton is
        // shape-matched, so the hero, the ledgers and the action row land in
        // the boxes they were already occupying and nothing jumps when the
        // data arrives.
        loading: () => const _ExampleHomeSkeleton(),
      );
    }

    return Scaffold(
      body: dashboard.when(
        data: (snapshot) => RefreshIndicator(
          onRefresh: () => ref.read(refreshHoppaDashboardProvider)(),
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 72,
                titleSpacing: AppSpacing.md,
                title: Row(
                  children: [
                    BrandMark(
                      appName: branding.appName,
                      logoAsset: branding.logoAsset,
                      size: 38,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        context.tr('{p0}, {p1}', {
                          'p0': context.tr(_greeting()),
                          'p1': _firstName(snapshot.customerName)
                        }),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                actions: [
                  RefreshAction(
                      onRefresh: () =>
                          ref.read(refreshHoppaDashboardProvider)()),
                  IconButton(
                    tooltip: context.tr('Notifications'),
                    onPressed: () => context.go(AppRoutes.notifications),
                    icon: Badge(
                      isLabelVisible:
                          (unreadNotifications.valueOrNull ?? 0) > 0,
                      label: Text(
                        '${unreadNotifications.valueOrNull ?? 0}',
                      ),
                      child: const Icon(Icons.notifications_none_rounded),
                    ),
                  ),
                  IconButton(
                    tooltip: context.tr('Settings'),
                    onPressed: () => context.go('/profile'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                  100,
                ),
                sliver: SliverList.list(
                  children: [
                    _PortfolioEstimateCard(
                      estimate: snapshot.portfolioEstimate,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _QuickActions(snapshot: snapshot),
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader(
                      title: context.tr('Your balances'),
                      actionLabel: context.tr('View all'),
                      onAction: () => context.go('/wallets/balances'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _ProviderBalances(snapshot: snapshot),
                    if (snapshot.fiatEnabled)
                      const SafeguardingStatementButton(),
                    if (snapshot.referralsEnabled ||
                        snapshot.vouchersEnabled) ...[
                      const SizedBox(height: AppSpacing.md),
                      _RewardsCard(snapshot: snapshot),
                    ],
                    if (!snapshot.isBusinessAccount) ...[
                      const SizedBox(height: AppSpacing.lg),
                      SectionHeader(
                        title: context.tr('Your cards'),
                        actionLabel: snapshot.cards.isEmpty
                            ? context.tr('Order')
                            : context.tr('Manage'),
                        onAction: () => context.go(
                          snapshot.cards.isEmpty ? '/cards/order' : '/cards',
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _CardsPreview(
                        cards: snapshot.cards,
                        onOpen: (card) => context.go('/cards/${card.id}'),
                        onOrder: () => context.go('/cards/order'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    SectionHeader(
                      title: context.tr('Recent activity'),
                      actionLabel: context.tr('View all'),
                      onAction: () => context.go('/activity'),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (snapshot.activities.isEmpty)
                      EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: context.tr('No activity yet'),
                        message: context.tr(
                            'Transactions will appear after provider sync.'),
                      )
                    else
                      NeoGroupedCard(
                        children: [
                          for (final activity in snapshot.activities.take(4))
                            _ActivityTile(
                              activity: activity,
                              onTap: () => context.go(
                                dashboardActivityRoute(activity.id),
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
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => _retryDashboard(ref),
        ),
        loading: () => LoadingState(label: context.tr('Loading dashboard')),
      ),
    );
  }
}

class _PortfolioEstimateCard extends StatelessWidget {
  const _PortfolioEstimateCard({required this.estimate});

  final PortfolioEstimate? estimate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = estimate;
    final warning = value == null
        ? 'Rate data is not available yet.'
        : value.isStale
            ? 'Rates may be out of date.'
            : value.isPartial
                ? 'Some balances are not included.'
                : 'Based on hourly market rates.';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Estimated total assets'),
                  style: theme.textTheme.labelLarge,
                ),
              ),
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            value == null
                ? '—'
                : '≈ ${_money(value.baseCurrency, value.total)}',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            warning,
            style: theme.textTheme.bodySmall?.copyWith(
              color:
                  theme.colorScheme.onPrimaryContainer.withValues(alpha: 0.72),
            ),
          ),
          if (value != null && value.missingCurrencies.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              context.tr(
                  'Missing: {p0}', {'p0': value.missingCurrencies.join(', ')}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.snapshot});

  final HoppaDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        NeoQuickAction(
          icon: Icons.north_east_rounded,
          label: context.tr('Send'),
          onTap:
              snapshot.outflowsEnabled ? () => context.go('/money/pay') : null,
        ),
        const SizedBox(width: AppSpacing.xs),
        NeoQuickAction(
          icon: Icons.swap_horiz_rounded,
          label: context.tr('Exchange'),
          onTap: snapshot.exchangeEnabled
              ? () => context.go('/wallets/exchange')
              : null,
        ),
        const SizedBox(width: AppSpacing.xs),
        if (!snapshot.isBusinessAccount) ...[
          NeoQuickAction(
            icon: Icons.add_rounded,
            label: context.tr('Buy'),
            onTap: () => context.go('/crypto/buy'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        NeoQuickAction(
          icon: Icons.south_rounded,
          label: context.tr('Deposit'),
          onTap: snapshot.isBusinessAccount
              ? () => context.go('/payments')
              : () => _openCryptoDeposit(context, ref),
        ),
      ],
    );
  }

  Future<void> _openCryptoDeposit(BuildContext context, WidgetRef ref) async {
    try {
      final addresses = await ref.read(hoppaWalletAddressesProvider.future);
      if (!context.mounted) return;
      await showStablecoinDepositDialog(
        context,
        addresses: addresses,
        initialAsset: 'USDT',
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    }
  }
}

class _ProviderBalances extends StatelessWidget {
  const _ProviderBalances({required this.snapshot});

  final HoppaDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final funded = snapshot.accounts
        .where((account) => account.balance.abs() >= 0.00000001)
        .toList();
    if (funded.isEmpty) {
      return EmptyState(
        icon: Icons.account_balance_wallet_outlined,
        title: context.tr('No balances yet'),
        message: context.tr('Funded balances will appear here automatically.'),
      );
    }

    final groups = <String, List<HoppaFiatAccount>>{};
    for (final account in funded) {
      groups.putIfAbsent(account.provider, () => []).add(account);
    }

    return Column(
      children: [
        for (var index = 0; index < groups.entries.length; index++) ...[
          _ProviderBalanceCard(
            provider: groups.entries.elementAt(index).key,
            balances: groups.entries.elementAt(index).value,
          ),
          if (index != groups.length - 1) const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _ProviderBalanceCard extends StatelessWidget {
  const _ProviderBalanceCard({
    required this.provider,
    required this.balances,
  });

  final String provider;
  final List<HoppaFiatAccount> balances;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NeoSurfaceCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      onTap: () => context.go(providerBalanceRouteFor(provider)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 48,
            decoration: BoxDecoration(
              color: _providerColor(provider),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        providerBalanceLabelFor(provider),
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    _StatusBadge(label: context.tr('Active'), positive: true),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: 2,
                  children: [
                    for (final balance in balances)
                      Text(
                        _money(balance.currency, balance.balance),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _RewardsCard extends ConsumerWidget {
  const _RewardsCard({required this.snapshot});

  final HoppaDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final rewards = ref.watch(rewardsSnapshotProvider).valueOrNull;
    final summary = rewards?.referralSummary;
    final progress = _dashboardMap(
      summary?['Progress'] ?? summary?['progress'],
    );
    final current = _dashboardNumber(
      progress['CurrentValue'] ?? progress['currentValue'],
    );
    final target = _dashboardNumber(
      progress['NextThreshold'] ?? progress['nextThreshold'],
    );
    final code = (summary?['ReferralCode'] ?? summary?['referralCode'])
        ?.toString()
        .trim();
    final features = <String>[
      if (snapshot.referralsEnabled) 'Referrals',
      if (snapshot.vouchersEnabled) 'vouchers',
    ];
    return NeoSurfaceCard(
      onTap: () => context.go('/rewards'),
      color: theme.colorScheme.primary.withValues(alpha: .12),
      borderColor: theme.colorScheme.primary.withValues(alpha: .28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: .18),
                child: Icon(
                  Icons.card_giftcard_rounded,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Rewards'),
                        style: theme.textTheme.titleMedium),
                    Text(
                      code == null || code.isEmpty
                          ? features.join(' & ')
                          : context.tr('Invite code {p0}', {'p0': code}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          if (snapshot.referralsEnabled && target != null && target > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: LinearProgressIndicator(
                minHeight: 7,
                value: ((current ?? 0) / target).clamp(0, 1),
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: .12),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              context.tr('{p0} of {p1} toward the next level', {
                'p0': _compactNumber(current ?? 0),
                'p1': _compactNumber(target)
              }),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardsPreview extends StatelessWidget {
  const _CardsPreview({
    required this.cards,
    required this.onOpen,
    required this.onOrder,
  });

  final List<PaymentCard> cards;
  final ValueChanged<PaymentCard> onOpen;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) {
    final visible =
        cards.where((card) => card.status != CardStatus.cancelled).toList();
    if (visible.isEmpty) {
      return NeoSurfaceCard(
        onTap: onOrder,
        child: Row(
          children: [
            CircleAvatar(
              child: Icon(Icons.add_card_rounded,
                  color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.tr('Order your first card')),
                  Text(context
                      .tr('Available card types depend on your account.')),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      );
    }
    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, index) => NeoBankCard.fromCard(
          visible[index],
          compact: true,
          onTap: () => onOpen(visible[index]),
        ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity, required this.onTap});

  final HoppaActivity activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final positive = activity.amount >= 0;
    return FinanceTransactionRow(
      onTap: onTap,
      logoUrl: activity.merchantLogoUrl,
      currency: activity.currency,
      fallbackColor: positive
          ? context.financeTheme.positive
          : Theme.of(context).colorScheme.primary,
      fallbackIcon: _activityIcon(activity.kind),
      title: transactionDisplayTitle(activity.title),
      subtitle: '${activity.subtitle} • ${activity.timeLabel}',
      amount:
          '${positive ? '+' : ''}${_money(activity.currency, activity.amount)}',
      amountColor: positive ? context.financeTheme.positive : null,
      secondaryAmount: activity.secondaryAmount == null
          ? null
          : _money(activity.secondaryCurrency, activity.secondaryAmount!),
      detailLabel: _activityProviderLabel(activity.kind),
      status: transactionDisplayStatus(activity.statusLabel),
      statusTone: _activityStatusTone(activity.statusLabel),
    );
  }
}

String _activityProviderLabel(HoppaActivityKind kind) {
  return switch (kind) {
    HoppaActivityKind.card => 'Crypto Card',
    HoppaActivityKind.crypto => 'Exchange',
    HoppaActivityKind.transfer ||
    HoppaActivityKind.deposit ||
    HoppaActivityKind.account =>
      'Fiat account',
  };
}

FinanceStatusTone _activityStatusTone(String value) {
  final status = value.toLowerCase().replaceAll('_', ' ').trim();
  if (const {'complete', 'completed', 'closed', 'settled'}.contains(status)) {
    return FinanceStatusTone.success;
  }
  if (const {'failed', 'declined', 'rejected', 'cancelled', 'canceled'}
      .contains(status)) {
    return FinanceStatusTone.danger;
  }
  if (const {'pending', 'processing', 'in progress'}.contains(status)) {
    return FinanceStatusTone.warning;
  }
  return FinanceStatusTone.neutral;
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label, required this.positive});

  final String label;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final color = positive
        ? context.financeTheme.positive
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      ),
    );
  }
}

String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning';
  if (hour < 18) return 'Good afternoon';
  return 'Good evening';
}

String _firstName(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? 'there' : trimmed.split(RegExp(r'\s+')).first;
}

String providerBalanceLabelFor(String provider) {
  final normalized = provider.toLowerCase();
  if (normalized.contains('interlace')) return 'Crypto cards';
  if (normalized.contains('boom')) return 'Exchange';
  if (normalized.contains('equals')) return 'Fiat account';
  return provider;
}

String providerBalanceRouteFor(String provider) {
  final normalized = provider.toLowerCase();
  if (normalized.contains('interlace')) return AppRoutes.walletAssets;
  if (normalized.contains('boom')) return AppRoutes.walletExchange;
  return AppRoutes.money;
}

String dashboardActivityRoute(String transactionId) =>
    '/transactions/${Uri.encodeComponent(transactionId)}';

Color _providerColor(String provider) {
  final normalized = provider.toLowerCase();
  if (normalized.contains('equals')) return HoppaColors.success;
  if (normalized.contains('boom')) return HoppaColors.blue;
  return HoppaColors.primary;
}

IconData _activityIcon(HoppaActivityKind kind) {
  return switch (kind) {
    HoppaActivityKind.card => Icons.credit_card_rounded,
    HoppaActivityKind.transfer => Icons.north_east_rounded,
    HoppaActivityKind.crypto => Icons.currency_bitcoin_rounded,
    HoppaActivityKind.deposit => Icons.south_rounded,
    HoppaActivityKind.account => Icons.account_balance_rounded,
  };
}

Map<String, dynamic> _dashboardMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

double? _dashboardNumber(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String _money(String currency, double amount) {
  final code = currency.trim().toUpperCase();
  final decimals = code == 'BTC' || code == 'ETH' ? 6 : 2;
  final value = amount.toStringAsFixed(decimals);
  return switch (code) {
    'EUR' => '€$value',
    'GBP' => '£$value',
    'USD' => '\$$value',
    _ => '$value $code',
  };
}

/// Home while it loads, in the shape Home will be.
///
/// Every block stands where its real element stands, at its real height, so
/// the arrival is data filling a page rather than a page replacing a spinner:
/// the hero panel keeps its 24 pt radius and its amount line box, the two
/// ledgers keep their 56 pt row rhythm and their hairlines, and the five
/// quick actions keep their circles. Nothing here is a guess about content —
/// no fake names, no fake amounts, no counts — only the geometry that is
/// already committed.
///
/// The whole page is ONE sheen host. A `ExampleSkeleton` sweeps itself by
/// default, and a dozen of them inside the shell's scope would register a
/// dozen hosts and a dozen `saveLayer`s a frame against a screen budget of
/// two or three; every block here is passed `sheen: false` and the single
/// soft sweep is taken once, at the top. Outside a `ExampleSheenScope` — a
/// widget test, a gallery card — it is inert, and under reduced motion the
/// sheen resolves to its static highlight.
class _ExampleHomeSkeleton extends StatelessWidget {
  const _ExampleHomeSkeleton();

  /// Matches the hero panel and the sweep it will carry.
  static const double _heroRadius = 24;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ExampleAtmosphere.home(
          child: ExampleBackdrop(
            child: Semantics(
              label: context.tr('Loading your accounts'),
              liveRegion: true,
              container: true,
              child: ExampleSheen.text(
                intensity: ExampleSheenIntensity.soft,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop =
                        constraints.maxWidth >= ExampleBreakpoints.desktop;
                    final pad = desktop
                        ? (constraints.maxWidth < 900 ? 24.0 : 40.0)
                        : 20.0;
                    return ListView(
                      // A skeleton has nothing to scroll to; letting it drag
                      // would let the customer pull an empty page around.
                      physics: const NeverScrollableScrollPhysics(),
                      padding:
                          EdgeInsets.fromLTRB(pad, desktop ? 32 : 8, pad, 24),
                      children: const [
                        _SkeletonHeader(),
                        SizedBox(height: 18),
                        ExampleSkeleton.line(
                          width: 168,
                          height: 15,
                          sheen: false,
                        ),
                        SizedBox(height: 8),
                        ExampleSkeleton.line(
                          width: 84,
                          height: 10,
                          sheen: false,
                        ),
                        SizedBox(height: 16),
                        _SkeletonHero(radius: _heroRadius),
                        SizedBox(height: 16),
                        _SkeletonGroup(rows: 4),
                        SizedBox(height: 22),
                        _SkeletonGroup(rows: 3),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
}

/// The lockup on the left and the two 44 pt controls on the right, at the
/// exact heights the real header uses, so the page does not shift when the
/// mark and the bell replace them.
class _SkeletonHeader extends StatelessWidget {
  const _SkeletonHeader();

  @override
  Widget build(BuildContext context) => const SafeArea(
        bottom: false,
        child: Row(
          children: [
            ExampleSkeleton(width: 104, height: 22, sheen: false),
            Spacer(),
            ExampleSkeleton.avatar(size: 28, sheen: false),
            SizedBox(width: AppSpacing.md),
            ExampleSkeleton.avatar(size: 28, sheen: false),
          ],
        ),
      );
}

/// The hero panel's silhouette: label, the balance at hero volume, the
/// caption, the chart band and the five actions. The panel is matte, not
/// frosted, and carries no sweep border — a rim of light around an empty box
/// is the material claiming to be finished.
class _SkeletonHero extends StatelessWidget {
  const _SkeletonHero({required this.radius});

  final double radius;

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        radius: radius,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ExampleSkeleton.line(width: 78, height: 10, sheen: false),
            const SizedBox(height: 14),
            const ExampleSkeleton.amount(
              size: ExampleAmountSize.hero,
              sheen: false,
            ),
            const SizedBox(height: 10),
            const ExampleSkeleton.line(width: 132, height: 10, sheen: false),
            const SizedBox(height: 16),
            // The trend band, at the plot height it will be drawn at.
            const ExampleSkeleton(height: 74, radius: 12, sheen: false),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < 5; i++)
                  const Column(
                    children: [
                      ExampleSkeleton.avatar(size: 42, sheen: false),
                      SizedBox(height: 8),
                      ExampleSkeleton.line(width: 34, height: 8, sheen: false),
                    ],
                  ),
              ],
            ),
          ],
        ),
      );
}

/// A ledger's silhouette: the section title above it, then rows on one
/// surface with the group's own hairlines, exactly as the accounts and
/// transaction groups are built.
class _SkeletonGroup extends StatelessWidget {
  const _SkeletonGroup({required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.sm),
            child: ExampleSkeleton.line(width: 96, height: 12, sheen: false),
          ),
          ExampleListGroup(
            children: [
              for (var i = 0; i < rows; i++)
                const ExampleSkeleton.row(height: 56, sheen: false),
            ],
          ),
        ],
      );
}
