import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import 'brand_asset.dart';

/// Configurable indeterminate loading artwork. Its semantics describe the
/// pending operation, never the decorative arc's painted fraction.
class BrandLoader extends StatefulWidget {
  const BrandLoader({
    this.size = 36,
    this.color,
    this.semanticsLabel = 'Loading',
    this.semanticsValue,
    this.spin = true,
    this.showWordmark = false,
    this.strokeWidth = 4,
    this.backgroundColor,
    super.key,
  });

  final double size;
  final Color? color;
  final String semanticsLabel;
  final String? semanticsValue;
  final bool spin;
  final bool showWordmark;
  final double strokeWidth;
  final Color? backgroundColor;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rotation = AnimationController(vsync: this);

  bool get _animate =>
      widget.spin &&
      context.brandDesign.motionEnabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);

  void _configureAnimation() {
    final design = context.brandDesign;
    final duration = Duration(
      milliseconds:
          (design.loaderDurationMs * design.motionDurationScale).round(),
    );
    final changed = _rotation.duration != duration;
    _rotation.duration = duration;
    if (_animate) {
      if (changed || !_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.stop();
      _rotation.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _configureAnimation();
  }

  @override
  void didUpdateWidget(covariant BrandLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _configureAnimation();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final design = context.brandDesign;
    final loaderAsset = design.asset('loader');
    final artwork = design.loaderStyle == 'logo'
        ? BrandAsset(
            path: loaderAsset.isNotEmpty
                ? loaderAsset
                : AppDesignTheme.logoOf(context),
            size: widget.size,
            color: widget.color,
          )
        : SizedBox.square(
            dimension: widget.size,
            child: CircularProgressIndicator(
              value: .72,
              strokeWidth: widget.strokeWidth,
              color: widget.color,
              backgroundColor: widget.backgroundColor,
            ),
          );
    final stage = RotationTransition(turns: _rotation, child: artwork);
    return Semantics(
      label: widget.semanticsLabel,
      value: widget.semanticsValue,
      child: ExcludeSemantics(
        child: widget.showWordmark
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  stage,
                  SizedBox(height: widget.size * .18),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: BrandWordmark(height: widget.size * .17),
                    ),
                  ),
                ],
              )
            : stage,
      ),
    );
  }
}
