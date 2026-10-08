import 'package:flutter/material.dart';

import '../../brands/example/example_ui.dart';
import '../../core/branding/app_design.dart';
import 'brand_loader.dart';

/// Drop-in replacement for [CircularProgressIndicator]: under the EXAMPLE
/// theme an indeterminate spinner becomes the animated brand mark
/// ([ExampleLoader]); everywhere else, and for determinate progress, it is the
/// Material indicator with the same arguments.
class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({
    this.value,
    this.strokeWidth = 4,
    this.color,
    this.backgroundColor,
    this.valueColor,
    this.semanticsLabel,
    this.semanticsValue,
    super.key,
  });

  final double? value;
  final double strokeWidth;
  final Color? color;
  final Color? backgroundColor;
  final Animation<Color?>? valueColor;
  final String? semanticsLabel;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    final design = context.brandDesign;
    if (value != null || (!design.isConfigured && !context.isExampleTheme)) {
      return CircularProgressIndicator(
        value: value,
        strokeWidth: strokeWidth,
        color: color,
        backgroundColor: backgroundColor,
        valueColor: valueColor,
        semanticsLabel: semanticsLabel,
        semanticsValue: semanticsValue,
      );
    }
    // Inside buttons the ambient icon colour is the button's foreground; the
    // brand colour sweep would vanish on a violet surface, so the loader goes
    // monochrome in that colour there and keeps the gradient elsewhere.
    final ambient = IconTheme.of(context).color;
    final themed = Theme.of(context).iconTheme.color;
    Widget indicator(Color? animatedColor) {
      final mono = animatedColor ??
          color ??
          (ambient != null && ambient != themed ? ambient : null);
      if (design.isConfigured && design.loaderStyle != 'example') {
        return BrandLoader(
          color: mono,
          strokeWidth: strokeWidth,
          backgroundColor: backgroundColor,
          semanticsLabel: semanticsLabel ?? 'Loading',
          semanticsValue: semanticsValue,
        );
      }
      return Semantics(
        value: semanticsValue,
        child: ExampleLoader(
          color: mono,
          semanticsLabel: semanticsLabel ?? 'Loading',
        ),
      );
    }

    if (valueColor == null) return indicator(null);
    return AnimatedBuilder(
      animation: valueColor!,
      builder: (_, __) => indicator(valueColor!.value),
    );
  }
}
