import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import '../../core/l10n/app_localizations.dart';
import '../../shared/widgets/brand_asset.dart';
import '../../shared/widgets/brand_loader.dart';
import 'example_colors.dart';

/// Displays the configured customer logo, or accessible initials if absent.
class ExampleMark extends StatelessWidget {
  const ExampleMark({this.size = 34, this.color, super.key});
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => BrandAsset(
        path: AppDesignTheme.logoOf(context),
        size: size,
        color: color,
      );
}

/// Uses the customer's app name and font instead of embedded logo paths.
class ExampleWordmark extends StatelessWidget {
  const ExampleWordmark({this.height = 14, this.color, super.key});
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      BrandWordmark(height: height, color: color);
}

/// Customer-configurable loading artwork with reduced-motion support.
class ExampleLoader extends StatelessWidget {
  const ExampleLoader({
    this.size = 36,
    this.color,
    this.semanticsLabel = 'Loading',
    this.spin = true,
    super.key,
  }) : showWordmark = false;

  const ExampleLoader.transition({this.size = 96, this.color, super.key})
      : semanticsLabel = 'Loading',
        showWordmark = false,
        spin = false;

  const ExampleLoader.boot({
    this.size = 132,
    this.showWordmark = true,
    bool intro = true,
    super.key,
  })  : color = null,
        semanticsLabel = 'Loading',
        spin = true;

  final double size;
  final Color? color;
  final String semanticsLabel;
  final bool spin;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) => BrandLoader(
        size: size,
        color: color ?? Theme.of(context).colorScheme.primary,
        semanticsLabel: showWordmark
            ? context.tr('Loading {p0}', {'p0': BrandAsset.nameOf(context)})
            : semanticsLabel,
        spin: spin,
        showWordmark: showWordmark,
      );
}

const exampleBootBackdrop = BoxDecoration(color: ExampleColors.appBackground);
