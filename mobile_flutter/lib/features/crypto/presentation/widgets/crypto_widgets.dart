import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../../brands/example/example.dart';
import '../../../../core/branding/app_design.dart';
import '../../../../core/models/banking_models.dart';
import '../../../../shared/widgets/currency_logo.dart';
import '../../domain/crypto_models.dart';

enum CryptoTrend {
  up,
  down,

  flat,
}

class CryptoChange extends StatelessWidget {
  const CryptoChange({
    required this.percent,
    this.fontSize = 12,
    this.mainAxisAlignment = MainAxisAlignment.end,
    super.key,
  });

  final double? percent;

  final double fontSize;

  final MainAxisAlignment mainAxisAlignment;

  static CryptoTrend trendOf(double? percent) => percent == null || percent == 0
      ? CryptoTrend.flat
      : percent > 0
          ? CryptoTrend.up
          : CryptoTrend.down;

  @override
  Widget build(BuildContext context) {
    final value = percent;
    if (value == null) return const SizedBox.shrink();
    final trend = trendOf(value);
    final ink = switch (trend) {
      CryptoTrend.up => ExampleInk.accent(context, ExampleColors.success),
      CryptoTrend.down => ExampleInk.accent(context, ExampleColors.danger),
      CryptoTrend.flat => ExampleInk.secondary(context),
    };
    final glyph = switch (trend) {
      CryptoTrend.up => Icons.arrow_drop_up,
      CryptoTrend.down => Icons.arrow_drop_down,
      CryptoTrend.flat => Icons.remove_rounded,
    };
    final spoken = switch (trend) {
      CryptoTrend.up => 'Up',
      CryptoTrend.down => 'Down',
      CryptoTrend.flat => 'Unchanged,',
    };
    return Semantics(
      label: context.tr('{p0} {p1} percent',
          {'p0': spoken, 'p1': value.abs().toStringAsFixed(2)}),
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: mainAxisAlignment,
        children: [
          Icon(
            glyph,
            size: trend == CryptoTrend.flat ? fontSize : fontSize + 3,
            color: ink,
          ),
          Text(
            // The caret already carries the sign, so the string never repeats
            // it: "▾ -1.24%" is two signs saying the same thing twice.
            '${value.abs().toStringAsFixed(2)}%',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              fontSize: fontSize,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class CryptoRowValue extends StatelessWidget {
  const CryptoRowValue({
    required this.value,
    this.caption,
    this.captionText,
    super.key,
  });

  final String value;

  final Widget? caption;

  final String? captionText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mark = caption;
    final text = captionText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          maxLines: 1,
          softWrap: false,
          style: (theme.textTheme.titleSmall ??
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))
              .copyWith(
            fontWeight: FontWeight.w600,
            color: ExampleInk.primary(context),
            height: 1.3,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (mark != null)
          mark
        else if (text != null)
          Text(
            text,
            maxLines: 1,
            softWrap: false,
            style: (theme.textTheme.bodySmall ?? const TextStyle(fontSize: 12))
                .copyWith(
              color: ExampleInk.secondary(context),
              height: 1.35,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

class PortfolioPositionTile extends StatelessWidget {
  const PortfolioPositionTile({
    required this.position,
    super.key,
  });

  final HoppaPortfolioPosition position;

  bool get _priced => position.asset.hasPrice || position.valueOverride != null;

  double? get _change => !_priced ? null : position.profitLossPercent;

  @override
  Widget build(BuildContext context) =>
      context.isExampleTheme ? _example(context) : _legacy(context);

  Widget _example(BuildContext context) {
    final change = _change;
    final held = Money.formatAmount(position.asset.symbol, position.amount);
    return ExampleRow(
      leading: AssetAvatar(asset: position.asset, size: 34),
      title: position.asset.name,
      subtitle: held,
      semanticsLabel: _priced
          ? '${position.asset.name}, $held, worth '
              '${Money.formatAmount('EUR', position.value)}'
          : context.tr('{p0}, {p1}, value unavailable',
              {'p0': position.asset.name, 'p1': held}),
      trailing: _priced
          ? CryptoRowValue(
              value: Money.formatAmount('EUR', position.value),
              caption: change == null ? null : CryptoChange(percent: change),
            )
          : const ExampleRowValue(value: ExampleAmount.placeholder),
    );
  }

  Widget _legacy(BuildContext context) {
    final positive = position.profitLoss >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: AssetAvatar(asset: position.asset),
        title: Text('${position.asset.name} (${position.asset.symbol})'),
        subtitle: Text('${position.amount} ${position.asset.symbol}'),
        trailing: _priced
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money('EUR', position.value),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_priced)
                    Text(
                      '${positive ? '+' : ''}${position.profitLossPercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: positive
                            ? context.brandDesign.color(
                                Theme.of(context).brightness, 'success',
                                fallback: Colors.green.shade700)
                            : context.brandDesign.color(
                                Theme.of(context).brightness, 'danger',
                                fallback: Colors.red.shade700),
                      ),
                    ),
                ],
              )
            : null,
      ),
    );
  }
}

class MarketAssetTile extends StatelessWidget {
  const MarketAssetTile({required this.asset, this.onTap, super.key});

  final HoppaMarketAsset asset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) =>
      context.isExampleTheme ? _example(context) : _legacy(context);

  Widget _example(BuildContext context) {
    final change = asset.hasChangePercent ? asset.changePercent : null;
    return ExampleRow(
      leading: AssetAvatar(asset: asset, size: 34),
      title: asset.name,
      subtitle: asset.hasMarketCapRank
          ? context.tr('{p0}  ·  Rank {p1}',
              {'p0': asset.symbol, 'p1': asset.marketCapRank})
          : asset.symbol,
      onTap: onTap,
      semanticsLabel:
          onTap == null ? null : context.tr('{p0}, buy', {'p0': asset.name}),
      trailing: SizedBox(
        width: 150,
        child: Row(
          children: [
            Expanded(
              child: Sparkline(
                values: asset.sparkline,
                color: ExampleInk.accent(
                    context,
                    asset.changePercent >= 0
                        ? ExampleColors.success
                        : ExampleColors.danger),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            CryptoRowValue(
              value: asset.hasPrice
                  ? Money.formatAmount('EUR', asset.price)
                  : ExampleAmount.placeholder,
              caption: change == null ? null : CryptoChange(percent: change),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legacy(BuildContext context) {
    final positive = asset.changePercent >= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        leading: AssetAvatar(asset: asset),
        title: Text('${asset.name} (${asset.symbol})'),
        subtitle: Text(
          asset.hasMarketCapRank
              ? context.tr('Rank {p0}', {'p0': asset.marketCapRank})
              : context.tr('Rank unavailable'),
        ),
        trailing: SizedBox(
          width: 150,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Expanded(
                child: Sparkline(
                  values: asset.sparkline,
                  color: positive
                      ? context.brandDesign.color(
                          Theme.of(context).brightness, 'success',
                          fallback: Colors.green.shade600)
                      : context.brandDesign.color(
                          Theme.of(context).brightness, 'danger',
                          fallback: Colors.red.shade600),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    asset.hasPrice
                        ? money('EUR', asset.price)
                        : context.tr('Unavailable'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  if (asset.hasChangePercent)
                    Text(
                      '${positive ? '+' : ''}${asset.changePercent.toStringAsFixed(2)}%',
                      style: TextStyle(
                        color: positive
                            ? context.brandDesign.color(
                                Theme.of(context).brightness, 'success',
                                fallback: Colors.green.shade700)
                            : context.brandDesign.color(
                                Theme.of(context).brightness, 'danger',
                                fallback: Colors.red.shade700),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AssetAvatar extends StatelessWidget {
  const AssetAvatar({required this.asset, this.size = 40, super.key});

  final HoppaMarketAsset asset;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExampleCurrencyAvatar(code: asset.symbol, size: size);
    }
    return CurrencyLogo(
      symbol: asset.symbol,
      size: size,
      fallbackColor: asset.tint,
    );
  }
}

class Sparkline extends StatelessWidget {
  const Sparkline({required this.values, required this.color, super.key});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: CustomPaint(
        painter: _SparklinePainter(values: values, color: color),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  const _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.isEmpty) {
      return;
    }

    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final range = maxValue - minValue == 0 ? 1 : maxValue - minValue;
    final step = size.width / (values.length - 1);
    final path = Path();

    for (var index = 0; index < values.length; index++) {
      final x = index * step;
      final y =
          size.height - ((values[index] - minValue) / range * size.height);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.color != color;
  }
}

String money(String currency, double amount) {
  return '$currency ${amount.toStringAsFixed(amount.abs() >= 10 ? 2 : 4)}';
}
