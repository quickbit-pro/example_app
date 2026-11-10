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
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (snapshot.isSaved)
          Positioned.fill(
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: _buildBanner(context),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: OverflowBar(
          spacing: 8,
          overflowAlignment: OverflowBarAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      context.tr(snapshot.isRefreshing
                          ? 'Updating saved data…'
                          : 'Could not update. Showing saved data.'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}
