import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../data/crypto_providers.dart';
import '../domain/crypto_models.dart';
import 'widgets/crypto_widgets.dart';

class CryptoMarketScreen extends ConsumerWidget {
  const CryptoMarketScreen({super.key});

  static const routePath = '/crypto/market';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!context.isExampleTheme) return const _LegacyMarket();
    final market = ref.watch(hoppaMarketAssetsProvider);
    final desktop =
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;
    return ExampleGlow(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar:
            AppBar(centerTitle: !desktop, title: Text(context.tr('Market'))),
        body: market.when(
          data: (items) => RefreshIndicator(
            color: ExampleInk.accent(context, ExampleColors.iris),
            backgroundColor: ExampleSurface.of(context, 2),
            onRefresh: () => ref.refresh(hoppaMarketAssetsProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: desktop ? 880 : 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded),
                            labelText: context.tr('Search assets'),
                          ),
                          readOnly: true,
                          onTap: () {},
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (items.isEmpty)
                          ExampleEmptyState(
                            title: context.tr('No market assets'),
                            body: context.tr(
                                'Market assets will appear after provider sync.'),
                            icon: Icons.query_stats_rounded,
                          )
                        else
                          _MarketTable(
                            assets: items,
                            title: context.tr('All assets'),
                            onOpen: () => context.push('/crypto/buy'),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(hoppaMarketAssetsProvider),
          ),
          loading: () => Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: ExampleListGroup(
              title: context.tr('Loading market'),
              children: const [
                ExampleSkeleton.row(),
                ExampleSkeleton.row(),
                ExampleSkeleton.row(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TableMetrics {
  const _TableMetrics({required this.value, required this.spark});

  final double value;

  final double spark;

  bool get hasSpark => spark > 0;
}

double _widest(Iterable<String> strings, TextStyle style, TextScaler scaler) {
  var widest = 0.0;
  final painter = TextPainter(
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
  );
  for (final string in strings) {
    painter
      ..text = TextSpan(text: string, style: style)
      ..layout();
    if (painter.width > widest) widest = painter.width;
  }
  painter.dispose();
  return widest;
}

_TableMetrics _metricsFor(
  BuildContext context,
  List<HoppaMarketAsset> assets,
  double rowWidth,
) {
  final theme = Theme.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  // The two styles CryptoRowValue and CryptoChange actually render in.
  final valueStyle = (theme.textTheme.titleSmall ??
          const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
      .copyWith(fontWeight: FontWeight.w600, height: 1.3);
  const changeStyle = TextStyle(
    fontSize: 12,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  final prices = assets.map(
    (asset) => asset.hasPrice
        ? Money.formatAmount('EUR', asset.price)
        : ExampleAmount.placeholder,
  );
  final changes = assets
      .where((asset) => asset.hasChangePercent)
      .map((asset) => '${asset.changePercent.abs().toStringAsFixed(2)}%')
      .toList();

  // The caret in front of a percentage is drawn three points larger than the
  // numerals, so a change cell is its glyph plus its digits.
  final widest = [
    _widest(prices, valueStyle, scaler),
    if (changes.isNotEmpty)
      _widest(changes, changeStyle, scaler) + scaler.scale(15),
  ].reduce((a, b) => a > b ? a : b);

  // The content box of a row: minus its padding, its leading square, and the
  // gap ExampleRow puts before whatever is trailing. What is left is the name
  // column plus the trailing columns.
  final content = rowWidth -
      AppSpacing.md * 2 -
      ExampleRow.leadingSize -
      ExampleRow.leadingGap -
      AppSpacing.sm;
  // The name column's floor: "Ethereum" over "ETH · Rank 2" at the reader's
  // own text size. The numbers get the width they measured, but never by
  // eating the label that says which asset they belong to.
  final nameFloor = scaler.scale(92);
  final value = widest.clamp(64.0, (content - nameFloor).clamp(64.0, 220.0));

  // The trend column is the first thing to go, and it goes by arithmetic
  // rather than by a breakpoint: it appears only at a width where it does not
  // push the name below its floor. It is the *supporting* reading — the caret
  // and the percentage already state the direction — so at a large text size
  // it stands down entirely and the numbers keep the room.
  final drawable = assets.any((asset) => asset.sparkline.length >= 2);
  double nameWidth(double spark) =>
      content - value - (spark > 0 ? spark + AppSpacing.sm : 0);
  final spark = !drawable || scaler.scale(14) > 16
      ? 0.0
      : nameWidth(56) >= nameFloor
          ? 56.0
          : nameWidth(44) >= nameFloor
              ? 44.0
              : 0.0;
  return _TableMetrics(value: value, spark: spark);
}

class _MarketTable extends StatelessWidget {
  const _MarketTable({
    required this.assets,
    required this.title,
    required this.onOpen,
  });

  final List<HoppaMarketAsset> assets;
  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final metrics = _metricsFor(context, assets, constraints.maxWidth);
          // Column labels earn their line only where there is room; on a
          // phone they are two more words above a list that already says what
          // it is.
          final header = constraints.maxWidth >= 560;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                container: true,
                liveRegion: true,
                label: title,
                excludeSemantics: true,
                child: ExampleSectionTitle(title: title),
              ),
              const SizedBox(height: AppSpacing.xs),
              if (header) ...[
                _ColumnHeader(metrics: metrics),
                const SizedBox(height: AppSpacing.xxs),
              ],
              ExampleListGroup(
                children: [
                  for (final asset in assets)
                    _MarketRow(
                      asset: asset,
                      metrics: metrics,
                      onTap: onOpen,
                    ),
                ],
              ),
            ],
          );
        },
      );
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({required this.metrics});

  final _TableMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 11,
      height: 1.3,
      fontWeight: FontWeight.w600,
      letterSpacing: .3,
      color: ExampleInk.tertiary(context),
    );
    return ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        child: Row(
          children: [
            const SizedBox(
              width: ExampleRow.leadingSize + ExampleRow.leadingGap,
            ),
            Expanded(child: Text(context.tr('Asset'), style: style)),
            const SizedBox(width: AppSpacing.sm),
            if (metrics.hasSpark) ...[
              SizedBox(
                width: metrics.spark,
                child: Text('24h', style: style, textAlign: TextAlign.center),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            SizedBox(
              width: metrics.value,
              child: Text(context.tr('Price'),
                  style: style, textAlign: TextAlign.end),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketRow extends StatelessWidget {
  const _MarketRow({
    required this.asset,
    required this.metrics,
    required this.onTap,
  });

  final HoppaMarketAsset asset;
  final _TableMetrics metrics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final change = asset.hasChangePercent ? asset.changePercent : null;
    final price = asset.hasPrice
        ? Money.formatAmount('EUR', asset.price)
        : ExampleAmount.placeholder;

    return ExampleRow(
      leading: AssetAvatar(asset: asset, size: 34),
      title: asset.name,
      subtitle: asset.hasMarketCapRank
          ? context.tr('{p0}  ·  Rank {p1}',
              {'p0': asset.symbol, 'p1': asset.marketCapRank})
          : asset.symbol,
      onTap: onTap,
      semanticsLabel: _spoken(price, change),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metrics.hasSpark) ...[
            _TrendSpark(
              values: asset.sparkline,
              trend: CryptoChange.trendOf(change),
              width: metrics.spark,
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          SizedBox(
            width: metrics.value,
            child: CryptoRowValue(
              value: price,
              caption: change == null ? null : CryptoChange(percent: change),
            ),
          ),
        ],
      ),
    );
  }

  String _spoken(String price, double? change) {
    final buffer = StringBuffer('${asset.name}, ${asset.symbol}');
    if (asset.hasMarketCapRank) buffer.write(', rank ${asset.marketCapRank}');
    buffer.write(asset.hasPrice ? ', $price' : ', price unavailable');
    if (change != null) {
      final direction = switch (CryptoChange.trendOf(change)) {
        CryptoTrend.up => 'up',
        CryptoTrend.down => 'down',
        CryptoTrend.flat => 'unchanged,',
      };
      buffer.write(
        ', $direction ${change.abs().toStringAsFixed(2)} percent '
        'over 24 hours',
      );
    }
    buffer.write('. Buy');
    return buffer.toString();
  }
}

class _TrendSpark extends StatelessWidget {
  const _TrendSpark({
    required this.values,
    required this.trend,
    required this.width,
  });

  final List<double> values;
  final CryptoTrend trend;
  final double width;

  static const double height = 26;

  @override
  Widget build(BuildContext context) {
    final ink = switch (trend) {
      CryptoTrend.up => ExampleInk.accent(context, ExampleColors.success),
      CryptoTrend.down => ExampleInk.accent(context, ExampleColors.danger),
      CryptoTrend.flat => ExampleInk.tertiary(context),
    };
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: values.length < 2
            ? null
            : RepaintBoundary(
                child: CustomPaint(
                  painter: _TrendSparkPainter(
                    values: values,
                    line: ink,
                    fill: ink.withValues(alpha: .18),
                    baseline: ExampleBorders.subtleSideOf(context).color,
                  ),
                ),
              ),
      ),
    );
  }
}

class _TrendSparkPainter extends CustomPainter {
  const _TrendSparkPainter({
    required this.values,
    required this.line,
    required this.fill,
    required this.baseline,
  });

  final List<double> values;
  final Color line;
  final Color fill;
  final Color baseline;

  static const double _inset = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || values.length < 2) return;

    var low = values.first;
    var high = values.first;
    for (final value in values) {
      if (value < low) low = value;
      if (value > high) high = value;
    }
    final span = high - low;
    const top = _inset;
    final bottom = size.height - _inset;
    if (bottom <= top) return;

    double y(double value) => span == 0
        ? (top + bottom) / 2
        : bottom - (value - low) / span * (bottom - top);

    final step = size.width / (values.length - 1);
    final path = Path()..moveTo(0, y(values.first));
    for (var index = 1; index < values.length; index++) {
      path.lineTo(index * step, y(values[index]));
    }

    // The level the window opened at: what the shape is being read against.
    final open = y(values.first);
    canvas.drawLine(
      Offset(0, open),
      Offset(size.width, open),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );

    final area = Path.from(path)
      ..lineTo(size.width, open)
      ..lineTo(0, open)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      Offset(size.width, y(values.last)),
      2,
      Paint()..color = line,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendSparkPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill ||
      oldDelegate.baseline != baseline;
}

// ---------------------------------------------------------------------------
// Loading
// ---------------------------------------------------------------------------

class _LegacyMarket extends ConsumerWidget {
  const _LegacyMarket();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final market = ref.watch(hoppaMarketAssetsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Market'))),
      body: market.when(
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(hoppaMarketAssetsProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: context.tr('Search assets'),
                ),
                readOnly: true,
                onTap: () {},
              ),
              const SizedBox(height: 16),
              if (items.isEmpty)
                EmptyState(
                  title: context.tr('No market assets'),
                  message: context
                      .tr('Market assets will appear after provider sync.'),
                  icon: Icons.query_stats,
                )
              else
                for (final asset in items)
                  MarketAssetTile(
                    asset: asset,
                    onTap: () => context.push('/crypto/buy'),
                  ),
            ],
          ),
        ),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(hoppaMarketAssetsProvider),
        ),
        loading: () => LoadingState(label: context.tr('Loading market')),
      ),
    );
  }
}
