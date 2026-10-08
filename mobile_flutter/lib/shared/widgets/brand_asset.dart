import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';

/// A bundled tenant image with an accessible, brand-neutral fallback.
/// Raster assets are prepared and bundled by the brand configuration tool.
class BrandAsset extends StatelessWidget {
  const BrandAsset({
    required this.path,
    this.size = 42,
    this.width,
    this.appName,
    this.color,
    super.key,
  });

  final String path;
  final double size;
  final double? width;
  final String? appName;
  final Color? color;

  static String nameOf(BuildContext context, {String? fallback}) {
    final name = AppDesignTheme.nameOf(context).trim();
    if (name.isNotEmpty) return name;
    return fallback?.trim().isNotEmpty == true
        ? fallback!.trim()
        : 'Sample App';
  }

  @override
  Widget build(BuildContext context) {
    final name = nameOf(context, fallback: appName);
    final words = name.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
    final initials = words.take(2).map((word) => word.characters.first).join();
    final colors = Theme.of(context).colorScheme;
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(
          size * .22 * (context.brandDesign.radiusScale ?? 1),
        ),
      ),
      child: Center(
        child: Text(
          initials.toUpperCase(),
          style: TextStyle(
            color: color ?? colors.onPrimaryContainer,
            fontSize: size * .35,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      label: context.tr('{p0} logo', {'p0': name}),
      child: ExcludeSemantics(
        child: SizedBox(
          width: width ?? size,
          height: size,
          child: path.trim().isEmpty
              ? fallback
              : Image.asset(
                  path,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}

class BrandWordmark extends StatelessWidget {
  const BrandWordmark({required this.height, this.color, super.key});

  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        BrandAsset.nameOf(context),
        maxLines: 1,
        style: TextStyle(
          decoration: TextDecoration.none,
          fontSize: height,
          height: 1.15,
          color: color ?? Theme.of(context).colorScheme.onSurface,
          fontFamily: context.brandDesign.fontFamily.isEmpty
              ? null
              : context.brandDesign.fontFamily,
          fontWeight: FontWeight.w700,
        ),
      );
}
