import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'display_snapshot.dart';

/// Keeps the page usable during refresh without presenting saved balances as
/// current. A failed refresh leaves the last successful data and a retry.
class SavedDataStatus extends StatelessWidget {
  const SavedDataStatus({
    required this.snapshot,
    required this.onRetry,
    required this.child,
    super.key,
  });

  final DisplaySnapshot<Object?> snapshot;
  final Future<void> Function() onRetry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      if (snapshot.isSaved)
        Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                const Icon(Icons.history, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  context.tr(snapshot.isRefreshing
                      ? 'Updating saved data…'
                      : 'Could not update. Showing saved data.'),
                  style: Theme.of(context).textTheme.bodySmall,
                )),
                if (!snapshot.isRefreshing)
                  TextButton(
                    onPressed: () async {
                      try {
                        await onRetry();
                      } catch (_) {
                        // The snapshot retains the refresh error.
                      }
                    },
                    child: Text(context.tr('Try again')),
                  ),
              ]),
            ),
          ),
        ),
      Expanded(child: child),
    ]);
  }
}
