import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_build_info.dart';

/// Keeps support details visible outside the navigator, including in dialogs.
class AppVersionFrame extends ConsumerWidget {
  const AppVersionFrame({required this.child, super.key});

  final Widget child;
  static const headerKey = Key('app-version-header');

  /// Space used by the fixed desktop badge in a page's existing toolbar.
  static double reservedWidthOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_AppVersionHeaderSpace>()
          ?.width ??
      0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info =
        ref.watch(appBuildInfoProvider).valueOrNull ?? AppBuildInfo.compiled;
    final client = ref.watch(clientEnvironmentProvider);
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          height: 1.2,
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        ) ??
        const TextStyle(fontSize: 11);
    final painter = TextPainter(
      text: TextSpan(text: '${info.label}$client', style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final reservedWidth = (painter.width + 88).ceilToDouble();
    painter.dispose();

    return LayoutBuilder(builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 900 &&
          reservedWidth < constraints.maxWidth * .45;
      if (desktop) {
        final padding = theme.appBarTheme.actionsPadding
                ?.resolve(Directionality.of(context)) ??
            EdgeInsets.zero;
        return Stack(
          fit: StackFit.expand,
          children: [
            _AppVersionHeaderSpace(
              width: reservedWidth,
              child: Theme(
                data: theme.copyWith(
                    appBarTheme: theme.appBarTheme.copyWith(
                  actionsPadding: padding.copyWith(
                    right: padding.right + reservedWidth,
                  ),
                )),
                child: child,
              ),
            ),
            PositionedDirectional(
              top: 20,
              end: 24,
              child: SafeArea(
                bottom: false,
                left: false,
                child: IgnorePointer(
                  child: Container(
                    key: headerKey,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: .9),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: theme.colorScheme.outlineVariant
                              .withValues(alpha: .65)),
                    ),
                    child: DefaultTextStyle(
                      style: style,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(info.label),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: SizedBox(
                              height: 12,
                              child: VerticalDivider(
                                  width: 1,
                                  color: theme.colorScheme.outlineVariant)),
                        ),
                        Icon(Icons.language_rounded,
                            size: 13,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 5),
                        Text(client),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
      // Phones retain the compact line and their existing safe-area handling.
      return Column(
        children: [
          ColoredBox(
            color: theme.scaffoldBackgroundColor,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                child: SizedBox(
                  key: headerKey,
                  width: double.infinity,
                  child: DefaultTextStyle(
                    style: style.copyWith(fontSize: 10),
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 6,
                      children: [
                        Text(info.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text('· $client', maxLines: 1),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
              child: MediaQuery.removePadding(
                  context: context, removeTop: true, child: child)),
        ],
      );
    });
  }
}

class _AppVersionHeaderSpace extends InheritedWidget {
  const _AppVersionHeaderSpace({required this.width, required super.child});
  final double width;

  @override
  bool updateShouldNotify(_AppVersionHeaderSpace oldWidget) =>
      width != oldWidget.width;
}
