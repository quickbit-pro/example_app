import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../brands/example/example_ui.dart';
import '../../core/branding/app_design.dart';
import 'brand_asset.dart';
import '../../brands/example/example_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_theme_extensions.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({
    required this.appName,
    this.logoAsset = '',
    this.size = 42,
    super.key,
  });

  final String appName;
  final String logoAsset;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (context.brandDesign.isConfigured) {
      final configured = AppDesignTheme.logoOf(context);
      return BrandAsset(
        path: configured.isNotEmpty ? configured : logoAsset,
        appName: appName,
        size: size,
      );
    }
    final colors = Theme.of(context).colorScheme;
    final radius = context.brandShape.radius(AppRadii.sm);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: SizedBox.square(
        dimension: size,
        child: Icon(
          Icons.account_balance_wallet_rounded,
          color: colors.onPrimary,
          size: size * 0.5,
        ),
      ),
    );

    if (appName.trim().toLowerCase() == 'example' && logoAsset.trim().isEmpty) {
      return ExampleMark(size: size);
    }

    if (logoAsset.trim().isEmpty) {
      return Semantics(
          label: context.tr('{p0} logo', {'p0': appName}), child: fallback);
    }

    return Semantics(
      label: context.tr('{p0} logo', {'p0': appName}),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          logoAsset,
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

class NeoSurfaceCard extends StatelessWidget {
  const NeoSurfaceCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.onTap,
    this.borderColor,
    this.color,
    this.gradient,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? borderColor;
  final Color? color;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isExample = context.isExampleTheme;
    // Example resolves per brightness: the dark branch is the exact Twilight
    // value this card has always painted, so night output is unchanged, while
    // paper gets a white surface, a lavender hairline and an ambient shadow
    // instead of a #101425 panel under night ink (measured at 1.06:1).
    final palette = ExamplePalette.of(context);
    final light = isExample && palette.brightness == Brightness.light;
    final radius = isExample ? 18.0 : context.brandShape.radius(AppRadii.lg);
    final decoration = BoxDecoration(
      color: gradient == null
          ? color ?? (isExample ? palette.surface : colors.surface)
          : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ??
            (isExample
                ? (light
                    ? palette.borderSubtle
                    : ExampleColors.lavender.withValues(alpha: .12))
                : colors.outlineVariant),
      ),
      boxShadow: isExample
          ? [
              BoxShadow(
                color: light
                    ? palette.shadowAmbient
                    : Colors.black.withValues(alpha: .14),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    );
    final content = Ink(
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

class NeoQuickAction extends StatelessWidget {
  const NeoQuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final enabled = onTap != null;
    return Expanded(
      child: InkWell(
        borderRadius:
            BorderRadius.circular(context.brandShape.radius(AppRadii.md)),
        onTap: onTap,
        child: Ink(
          height: isExample ? 68 : 80,
          decoration: BoxDecoration(
            color: isExample
                ? ExamplePalette.of(context).surfaceHigh
                : theme.colorScheme.surfaceContainer,
            borderRadius:
                BorderRadius.circular(context.brandShape.radius(AppRadii.md)),
            border: Border.all(
              color: isExample
                  ? (ExamplePalette.of(context).brightness == Brightness.light
                      ? ExamplePalette.of(context).borderSubtle
                      : ExampleColors.lavender.withValues(alpha: .11))
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 25,
                color: enabled
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant.withValues(alpha: .5),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: enabled
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NeoGroupedCard extends StatelessWidget {
  const NeoGroupedCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return NeoSurfaceCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Divider(),
              ),
          ],
        ],
      ),
    );
  }
}

class NeoSettingsRow extends StatelessWidget {
  const NeoSettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.destructive = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isExample = context.isExampleTheme;
    final foreground = destructive ? colors.error : colors.onSurface;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isExample ? 6 : 4,
      ),
      horizontalTitleGap: 12,
      minLeadingWidth: 32,
      titleAlignment: ListTileTitleAlignment.center,
      leading: isExample
          ? Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: foreground.withValues(alpha: .12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: foreground, size: 20),
            )
          : Icon(icon, color: foreground, size: 22),
      title: Text(title, style: TextStyle(color: foreground)),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ??
          (onTap == null
              ? null
              : Icon(Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant)),
      onTap: onTap,
    );
  }
}

class NeoFullScreenDialog extends StatelessWidget {
  const NeoFullScreenDialog({
    required this.title,
    required this.body,
    this.primaryLabel,
    this.onPrimary,
    this.primaryIcon,
    this.canClose = true,
    this.wideWidth = 560,
    this.wideMaxHeight = 680,
    super.key,
  });

  final String title;
  final Widget body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final IconData? primaryIcon;
  final bool canClose;

  /// Size of the centred sheet on wide web. A review that has to show its
  /// whole contract at once (card, costs and every agreement) asks for more
  /// room than the default form sheet.
  final double wideWidth;
  final double wideMaxHeight;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final isExample = context.isExampleTheme;
    if (isExample && size.width >= 700) {
      // Desktop / wide web: a centred sheet instead of a full-screen route.
      return PopScope(
        canPop: canClose,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Material(
            color: ExamplePalette.of(context).navigation,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color: ExamplePalette.of(context).brightness == Brightness.light
                    ? ExamplePalette.of(context).borderSubtle
                    : ExampleColors.lavender.withValues(alpha: .16),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: wideWidth.clamp(0, size.width - 64).toDouble(),
              height: (size.height - 48).clamp(420, wideMaxHeight).toDouble(),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('Close'),
                          visualDensity: VisualDensity.compact,
                          onPressed: canClose
                              ? () => Navigator.of(context).pop()
                              : null,
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(child: body),
                  if (primaryLabel != null) ...[
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: canClose
                                ? () => Navigator.of(context).pop()
                                : null,
                            child: Text(context.tr('Cancel')),
                          ),
                          const SizedBox(width: 10),
                          SizedBox(
                            height: 40,
                            child: FilledButton.icon(
                              onPressed: onPrimary,
                              icon: Icon(
                                primaryIcon ?? Icons.arrow_forward_rounded,
                                size: 18,
                              ),
                              label: Text(primaryLabel!),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return PopScope(
      canPop: canClose,
      child: Dialog.fullscreen(
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: context.tr('Close'),
              onPressed: canClose ? () => Navigator.of(context).pop() : null,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(title),
          ),
          body: SafeArea(child: body),
          bottomNavigationBar: primaryLabel == null
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.md,
                    ),
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: onPrimary,
                        icon: Icon(primaryIcon ?? Icons.arrow_forward_rounded),
                        label: Text(primaryLabel!),
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
