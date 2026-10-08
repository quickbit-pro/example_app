import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';

/// Four-point star with two satellite sparks that twinkle on a slow loop:
/// the "Ask AI" mark in the navigation. Selected renders brighter with a
/// soft glow; unselected stays muted but keeps a gentle shimmer.
class SparkleIcon extends StatefulWidget {
  const SparkleIcon({
    this.selected = false,
    this.size = 24,
    this.animate = true,
    super.key,
  });

  final bool selected;
  final double size;
  final bool animate;

  @override
  State<SparkleIcon> createState() => _SparkleIconState();
}

class _SparkleIconState extends State<SparkleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  void _syncAnimation() {
    final design = context.brandDesign;
    final animate = widget.animate &&
        design.motionEnabled &&
        !(MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    _controller.duration = Duration(
      milliseconds: (2600 * design.motionDurationScale).round(),
    );
    if (animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(SparkleIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _SparklePainter(
              progress: _controller.value,
              selected: widget.selected,
              primary: context.brandDesign.color(
                  Theme.of(context).brightness, 'accent',
                  fallback: widget.selected
                      ? ExampleColors.lavender
                      : ExampleColors.iris),
              secondary: context.brandDesign.color(
                  Theme.of(context).brightness, 'fill',
                  fallback: widget.selected
                      ? ExampleColors.violet
                      : ExampleColors.indigo),
              glow: context.brandDesign.color(
                  Theme.of(context).brightness, 'fill',
                  fallback: ExampleColors.violet),
            ),
          ),
        ),
      );
}

class _SparklePainter extends CustomPainter {
  const _SparklePainter(
      {required this.progress,
      required this.selected,
      required this.primary,
      required this.secondary,
      required this.glow});

  final double progress;
  final bool selected;
  final Color primary;
  final Color secondary;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * .46, size.height * .54);
    final radius = size.shortestSide * .40;
    final wave = (math.sin(progress * 2 * math.pi) + 1) / 2; // 0..1
    final mainScale = .92 + wave * .08;
    final alpha = selected ? 1.0 : .78;

    if (selected) {
      final glowPaint = Paint()
        ..color = glow.withValues(alpha: .28 + wave * .18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(center, radius * .9, glowPaint);
    }

    final gradient = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          primary.withValues(alpha: alpha),
          secondary.withValues(alpha: alpha),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawPath(_star(center, radius * mainScale, .36), gradient);

    // Satellite sparks twinkle on offset phases so the mark never sits still.
    final sparks = [
      (Offset(size.width * .80, size.height * .22), .30, 0.0),
      (Offset(size.width * .84, size.height * .70), .20, .45),
    ];
    for (final (position, scale, phase) in sparks) {
      final local = (math.sin((progress + phase) * 2 * math.pi) + 1) / 2;
      final sparkRadius = radius * scale * (.6 + local * .6);
      final paint = Paint()
        ..color = primary.withValues(alpha: (.35 + local * .65) * alpha);
      canvas.drawPath(_star(position, sparkRadius, .42), paint);
    }
  }

  /// Four-point star: outer points at [radius], inner points pulled in by
  /// [pinch] so the arms stay slender.
  Path _star(Offset center, double radius, double pinch) {
    final path = Path();
    for (var index = 0; index < 8; index++) {
      final angle = -math.pi / 2 + index * math.pi / 4;
      final length = index.isEven ? radius : radius * pinch;
      final point = Offset(
        center.dx + math.cos(angle) * length,
        center.dy + math.sin(angle) * length,
      );
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_SparklePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.selected != selected ||
      oldDelegate.primary != primary ||
      oldDelegate.secondary != secondary ||
      oldDelegate.glow != glow;
}
