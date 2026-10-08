import 'package:flutter/material.dart';

import '../../brands/example/example_motion.dart';
import '../../brands/example/example_colors.dart';
import '../../core/branding/app_design.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';

class FinanceCard extends StatelessWidget {
  const FinanceCard({
    required this.child,
    this.padding = AppSpacing.cardPadding,
    this.onTap,
    this.color,
    this.gradient,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final configured = context.brandDesign.isConfigured;
    final palette = ExamplePalette.of(context);
    final radius = context.brandShape.radius(AppRadii.sm);
    final decoration = BoxDecoration(
      color: gradient == null ? color ?? colors.surface : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            (configured ? colors.outlineVariant : HoppaColors.border),
      ),
      boxShadow: [
        BoxShadow(
          color: (configured ? palette.shadowAmbient : HoppaColors.ink)
              .withValues(alpha: 0.05),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );

    final content = AnimatedContainer(
      duration: ExampleMotion.of(context, const Duration(milliseconds: 160)),
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) {
      return content;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        child: content,
      ),
    );
  }
}

class BalanceCard extends StatelessWidget {
  const BalanceCard({
    required this.label,
    required this.amount,
    this.subtitle,
    this.action,
    super.key,
  });

  final String label;
  final String amount;
  final String? subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final configured = context.brandDesign.isConfigured;
    final onFill = configured ? ExamplePalette.of(context).onFill : Colors.white;
    final secondary =
        configured ? onFill.withValues(alpha: .7) : Colors.white70;

    return FinanceCard(
      gradient: configured
          ? context.financeTheme.heroGradient
          : const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HoppaColors.primaryDark,
                HoppaColors.primary,
              ],
            ),
      borderColor: Colors.transparent,
      child: DefaultTextStyle.merge(
        style: TextStyle(color: onFill),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: textTheme.labelLarge?.copyWith(color: secondary)),
            const SizedBox(height: AppSpacing.xs),
            Text(
              amount,
              style: textTheme.headlineMedium?.copyWith(color: onFill),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                subtitle!,
                style: textTheme.bodyMedium?.copyWith(color: secondary),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
