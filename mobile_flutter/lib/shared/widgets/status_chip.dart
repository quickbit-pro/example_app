import 'package:flutter/material.dart';

import '../../core/branding/app_design.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';

class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    this.tone = FinanceStatusTone.neutral,
    this.icon,
    super.key,
  });

  final String label;
  final FinanceStatusTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final configured = context.brandDesign.isConfigured;
    final finance = context.financeTheme;
    final foreground = configured
        ? switch (tone) {
            FinanceStatusTone.success => finance.positive,
            FinanceStatusTone.warning => finance.pending,
            FinanceStatusTone.danger => finance.negative,
            FinanceStatusTone.info => finance.crypto,
            FinanceStatusTone.neutral =>
              Theme.of(context).colorScheme.onSurfaceVariant,
          }
        : HoppaColors.statusColor(tone);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = configured
        ? foreground.withValues(alpha: .16)
        : isDark
            ? HoppaColors.statusBackgroundDark(tone)
            : HoppaColors.statusBackground(tone);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(
          context.brandShape.radius(AppRadii.pill),
        ),
        border: Border.all(
          color: foreground.withValues(alpha: isDark ? .32 : .16),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: foreground),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
