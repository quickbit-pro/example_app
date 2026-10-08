import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../data/crypto_providers.dart';
import '../domain/crypto_models.dart';
import 'widgets/crypto_widgets.dart';

class CryptoPortfolioScreen extends ConsumerWidget {
  const CryptoPortfolioScreen({super.key});

  static const routePath = '/crypto';

  @override
  Widget build(BuildContext context, WidgetRef ref) => context.isExampleTheme
      ? const _ExamplePortfolio()
      : const _LegacyPortfolio();
}

class _ExamplePortfolio extends ConsumerWidget {
  const _ExamplePortfolio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(hoppaPortfolioProvider);
    final market = ref.watch(hoppaMarketAssetsProvider);
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    return ExampleGlow(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: !desktop,
          title: Text(context.tr('Crypto')),
          actions: [
            IconButton(
              tooltip: context.tr('Market'),
              onPressed: () => context.push('/crypto/market'),
              icon: const Icon(Icons.query_stats_rounded),
            ),
            const SizedBox(width: AppSpacing.xxs),
          ],
        ),
        body: SafeArea(
          top: false,
          child: RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(hoppaPortfolioProvider);
              ref.invalidate(hoppaMarketAssetsProvider);
              await ref.read(hoppaPortfolioProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        portfolio.when(
                          data: (items) => _PortfolioPanel(positions: items),
                          error: (error, stackTrace) => ErrorState(
                            error: error,
                          ),
                          loading: () => const _PanelSkeleton(),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        const _PortfolioActions(),
                        const SizedBox(height: AppSpacing.lg),
                        portfolio.when(
                          data: (items) => _holdings(context, items),
                          error: (error, stackTrace) => ErrorState(
                            error: error,
                          ),
                          loading: () => ExampleListGroup(
                            title: context.tr('Your assets'),
                            children: const [
                              ExampleSkeleton.row(),
                              ExampleSkeleton.row(),
                              ExampleSkeleton.row(),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        market.when(
                          data: (items) => _movers(context, items),
                          error: (error, stackTrace) => ErrorState(
                            error: error,
                          ),
                          loading: () => ExampleListGroup(
                            title: context.tr('Market movers'),
                            children: const [
                              ExampleSkeleton.row(),
                              ExampleSkeleton.row(),
                              ExampleSkeleton.row(),
                            ],
                          ),
                        ),
                      ],
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

  Widget _holdings(BuildContext context, List<HoppaPortfolioPosition> items) {
    if (items.isEmpty) {
      return ExampleEmptyState(
        title: context.tr('No crypto assets yet'),
        body: context.tr('Portfolio assets will appear after provider sync.'),
        icon: Icons.currency_bitcoin,
        compact: true,
      );
    }
    return ExampleListGroup(
      title: context.tr('Your assets'),
      children: [
        for (final position in items)
          PortfolioPositionTile(
            position: position,
          ),
      ],
    );
  }

  Widget _movers(BuildContext context, List<HoppaMarketAsset> items) {
    if (items.isEmpty) {
      return ExampleEmptyState(
        title: context.tr('No prices yet'),
        body: context
            .tr('Market data appears as soon as the provider has synced.'),
        icon: Icons.query_stats_rounded,
        compact: true,
      );
    }
    return ExampleListGroup(
      title: context.tr('Market movers'),
      action: context.tr('View all'),
      onAction: () => context.push('/crypto/market'),
      children: [
        for (final asset in items.take(3)) MarketAssetTile(asset: asset),
      ],
    );
  }
}

class _PortfolioPanel extends StatelessWidget {
  const _PortfolioPanel({required this.positions});

  final List<HoppaPortfolioPosition> positions;

  @override
  Widget build(BuildContext context) {
    final total = positions.fold<double>(
      0,
      (sum, position) => sum + position.value,
    );
    final profit = positions.fold<double>(
      0,
      (sum, position) => sum + position.profitLoss,
    );
    final profitPercent = total == 0 ? 0 : profit / (total - profit) * 100;

    return ExampleGlassPanel(
      radius: AppRadii.lg,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Portfolio value'),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: .2,
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          ExampleAmount(
            amount: total,
            currency: 'EUR',
            size: ExampleAmountSize.large,
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ExampleAmount(
                amount: profit,
                currency: 'EUR',
                size: ExampleAmountSize.inline,
                tone: ExampleAmountTone.delta,
              ),
              // Direction as a shape before it is a colour, and the same
              // mark the holdings and market rows below use, so one glance
              // down the page reads as one language rather than three.
              CryptoChange(percent: profitPercent.toDouble(), fontSize: 13),
              Text(
                context.tr('since cost'),
                style: TextStyle(
                  fontSize: 11.5,
                  color: ExampleInk.tertiary(context),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PanelSkeleton extends StatelessWidget {
  const _PanelSkeleton();

  @override
  Widget build(BuildContext context) => ExampleGlassPanel(
        radius: AppRadii.lg,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        // One host for the panel. Three defaulted skeletons registered three,
        // which with the Buy CTA below put this screen at four — over the two
        // or three a screen is allowed.
        child: ExampleSheen.text(
          intensity: ExampleSheenIntensity.soft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ExampleSkeleton.line(width: 96, height: 11, sheen: false),
              const SizedBox(height: AppSpacing.xs),
              ExampleSkeleton.amount(
                sheen: false,
                semanticsLabel: context.tr('Loading portfolio value'),
              ),
              const SizedBox(height: AppSpacing.sm),
              const ExampleSkeleton.line(width: 140, height: 16, sheen: false),
            ],
          ),
        ),
      );
}

class _PortfolioActions extends StatelessWidget {
  const _PortfolioActions();

  @override
  Widget build(BuildContext context) {
    // One material, two volumes. Buy and Sell were a filled button beside an
    // outlined one — two different objects that happen to sit together;
    // as one glass material at two tones they read as a pair, and the
    // secondary is never as loud as the primary nor as quiet as a text link.
    //
    // `atmosphere` because both sit straight on the ExampleGlow with nothing
    // opaque in between. The shell already provides this screen's
    // ExampleSheenScope; without one `sheen` renders as a fixed soft
    // highlight and starts no ticker.
    return const Row(
      children: [
        Expanded(child: _PortfolioAction.buy()),
        SizedBox(width: AppSpacing.sm),
        Expanded(child: _PortfolioAction.sell()),
      ],
    );
  }
}

class _PortfolioAction extends StatelessWidget {
  const _PortfolioAction.buy()
      : _label = 'Buy',
        _icon = Icons.add_rounded,
        _route = '/crypto/buy',
        _primary = true;

  const _PortfolioAction.sell()
      : _label = 'Sell',
        _icon = Icons.swap_vert_rounded,
        _route = '/crypto/sell',
        _primary = false;

  final String _label;
  final IconData _icon;
  final String _route;
  final bool _primary;

  @override
  Widget build(BuildContext context) => ExampleGlassButton(
        label: _label,
        icon: _icon,
        tone: _primary
            ? ExampleGlassButtonTone.primary
            : ExampleGlassButtonTone.neutral,
        ground: ExampleGlassGround.atmosphere,
        sheen: _primary,
        onPressed: () => context.push(_route),
      );
}

class _LegacyPortfolio extends ConsumerWidget {
  const _LegacyPortfolio();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final portfolio = ref.watch(hoppaPortfolioProvider);
    final market = ref.watch(hoppaMarketAssetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Crypto')),
        actions: [
          IconButton(
            tooltip: context.tr('Market'),
            onPressed: () => context.push('/crypto/market'),
            icon: const Icon(Icons.query_stats),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(hoppaPortfolioProvider);
          ref.invalidate(hoppaMarketAssetsProvider);
          await ref.read(hoppaPortfolioProvider.future);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            portfolio.when(
              data: (items) => _LegacyHero(positions: items),
              error: (error, stackTrace) => ErrorState(error: error),
              loading: () =>
                  LoadingState(label: context.tr('Loading portfolio')),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => context.push('/crypto/buy'),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('Buy')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push('/crypto/sell'),
                    icon: const Icon(Icons.swap_vert),
                    label: Text(context.tr('Sell')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(context.tr('Your assets'),
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            portfolio.when(
              data: (items) => Column(
                children: [
                  if (items.isEmpty)
                    EmptyState(
                      title: context.tr('No crypto assets yet'),
                      message: context.tr(
                          'Portfolio assets will appear after provider sync.'),
                      icon: Icons.currency_bitcoin,
                    )
                  else
                    for (final position in items)
                      PortfolioPositionTile(position: position),
                ],
              ),
              error: (error, stackTrace) => ErrorState(error: error),
              loading: () => LoadingState(label: context.tr('Loading assets')),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('Market movers'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/crypto/market'),
                  child: Text(context.tr('View all')),
                ),
              ],
            ),
            market.when(
              data: (items) => Column(
                children: [
                  if (items.isEmpty)
                    EmptyState(
                      title: context.tr('No market assets'),
                      message: context
                          .tr('Market assets will appear after provider sync.'),
                      icon: Icons.query_stats,
                    )
                  else
                    for (final asset in items.take(3))
                      MarketAssetTile(asset: asset),
                ],
              ),
              error: (error, stackTrace) => ErrorState(error: error),
              loading: () => LoadingState(label: context.tr('Loading market')),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegacyHero extends StatelessWidget {
  const _LegacyHero({required this.positions});

  final List<HoppaPortfolioPosition> positions;

  @override
  Widget build(BuildContext context) {
    final value = positions.fold<double>(
      0,
      (total, position) => total + position.value,
    );
    final profit = positions.fold<double>(
      0,
      (total, position) => total + position.profitLoss,
    );
    final profitPercent = value == 0 ? 0 : profit / (value - profit) * 100;
    final positive = profit >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('Portfolio value'),
            style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onPrimary
                  .withValues(alpha: 0.76),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            money('EUR', value),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          Chip(
            avatar: Icon(
              positive ? Icons.trending_up : Icons.trending_down,
              size: 18,
            ),
            label: Text(
              '${positive ? '+' : ''}${money('EUR', profit)} · '
              '${positive ? '+' : ''}${profitPercent.toStringAsFixed(2)}%',
            ),
          ),
        ],
      ),
    );
  }
}
