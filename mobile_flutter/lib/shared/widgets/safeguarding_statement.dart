import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../brands/example/example_colors.dart';
import '../../brands/example/example_ui.dart';
import '../../features/platform/application/platform_providers.dart';
import '../theme/app_theme_extensions.dart';
import 'legal_disclosure.dart';

/// Regulatory safeguarding text shown wherever fiat balances appear. Uses the
/// tenant-configured EU/UK wording when present, else the default statement.
final safeguardingStatementProvider = Provider<String>((ref) {
  final tenantConfig = ref.watch(mobileTenantConfigProvider).valueOrNull;
  return resolveEqualsPaymentServicesDisclosure(
    localeCountryCode:
        WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '',
    defaultRegion: tenantConfig?.equalsRegulatoryRegionDefault ?? 'EU',
    euDisclosure: tenantConfig?.equalsRegulatoryDisclaimerEu,
    ukDisclosure: tenantConfig?.equalsRegulatoryDisclaimerUk,
  );
});

Future<void> showSafeguardingStatement(
  BuildContext context, {
  required String statement,
}) {
  final isExample = context.isExampleTheme;
  // Per brightness: every dark branch below is the Twilight value this sheet
  // has always painted, so night output is unchanged.
  final palette = ExamplePalette.of(context);
  final onPaper = isExample && palette.brightness == Brightness.light;
  final wide = MediaQuery.sizeOf(context).width >= 700;
  final bodyStyle = TextStyle(
    fontSize: 14,
    height: 1.65,
    color: isExample
        ? palette.ink.withValues(alpha: .86)
        : Theme.of(context).colorScheme.onSurface,
  );
  if (wide) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: isExample
            ? palette.navigation
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(context.brandShape.radius(22)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 18, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.shield_outlined,
                      size: 20,
                      color: isExample
                          ? (onPaper
                              ? palette.accent
                              : palette.accentFor(ExampleColors.lavender))
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        context.tr('Safeguarding statement'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: isExample ? palette.ink : null,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: context.tr('Close'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(statement, style: bodyStyle),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  return showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (dialogContext) => Dialog.fullscreen(
      backgroundColor: isExample ? palette.navigation : null,
      child: Scaffold(
        backgroundColor: isExample ? palette.navigation : null,
        appBar: AppBar(
          centerTitle: isExample,
          title: Text(context.tr('Safeguarding statement')),
          leading: IconButton(
            tooltip: context.tr('Close'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 60),
          children: [
            Icon(
              Icons.shield_outlined,
              size: 36,
              color: isExample
                  ? (onPaper
                      ? palette.accent
                      : palette.accentFor(ExampleColors.lavender))
                  : null,
            ),
            const SizedBox(height: 16),
            Text(statement, style: bodyStyle),
          ],
        ),
      ),
    ),
  );
}

/// Quiet text link that opens the safeguarding statement. Place it beside
/// any list of fiat balances.
class SafeguardingStatementButton extends ConsumerWidget {
  const SafeguardingStatementButton(
      {this.alignment = Alignment.centerRight,
      this.expanded = false,
      super.key});

  final AlignmentGeometry alignment;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // No fiat banking on this installation means nothing is safeguarded.
    final fiatEnabled =
        ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled ??
            true;
    if (!fiatEnabled) return const SizedBox.shrink();
    final isExample = context.isExampleTheme;
    final color = isExample
        ? ExamplePalette.of(context).textTertiary
        : Theme.of(context).colorScheme.onSurfaceVariant;
    if (expanded) {
      return TextButton(
        onPressed: () => showSafeguardingStatement(context,
            statement: ref.read(safeguardingStatementProvider)),
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(double.infinity, 56),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        ),
        child: Row(children: [
          const Icon(Icons.shield_outlined, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child: Text(context.tr('Safeguarding statement'),
                  style: const TextStyle(fontSize: 14))),
          const SizedBox(width: 8),
          const Icon(Icons.chevron_right_rounded, size: 24),
        ]),
      );
    }
    return Align(
      alignment: alignment,
      child: TextButton.icon(
        style: TextButton.styleFrom(
          foregroundColor: color,
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        onPressed: () => showSafeguardingStatement(
          context,
          statement: ref.read(safeguardingStatementProvider),
        ),
        icon: const Icon(Icons.shield_outlined, size: 14),
        label: Text(
          context.tr('Safeguarding statement'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
