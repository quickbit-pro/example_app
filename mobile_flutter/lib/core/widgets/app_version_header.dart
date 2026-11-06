import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../diagnostics/app_build_info.dart';

/// A small shared header on every routed page, including sign-in and details.
/// Reserve space instead of covering AppBar actions, content, or system insets.
class AppVersionFrame extends ConsumerWidget {
  const AppVersionFrame({required this.child, super.key});

  final Widget child;
  static const headerKey = Key('app-version-header');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info =
        ref.watch(appBuildInfoProvider).valueOrNull ?? AppBuildInfo.compiled;
    final client = ref.watch(clientEnvironmentProvider);
    final theme = Theme.of(context);
    return Column(
      children: [
        ColoredBox(
          color: theme.scaffoldBackgroundColor,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: SizedBox(
                key: headerKey,
                width: double.infinity,
                child: DefaultTextStyle(
                  style: TextStyle(
                      fontSize: 10,
                      height: 1.2,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: theme.textTheme.bodySmall?.fontFamily,
                      fontFeatures: const [FontFeature.tabularFigures()]),
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
  }
}
