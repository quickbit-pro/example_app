import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/group_activity_transactions.dart';

/// Keeps receipt navigation on each row and expansion on a separate control.
class ActivityTransactionGroupTile extends StatefulWidget {
  const ActivityTransactionGroupTile({
    required this.group,
    required this.rowBuilder,
    super.key,
  });

  final ActivityTransactionGroup group;
  final Widget Function(LedgerTransaction row) rowBuilder;

  @override
  State<ActivityTransactionGroupTile> createState() =>
      _ActivityTransactionGroupTileState();
}

class _ActivityTransactionGroupTileState
    extends State<ActivityTransactionGroupTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    if (group.entries.length < 2) return widget.rowBuilder(group.primary);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.rowBuilder(group.primary),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 12),
            child: Semantics(
              expanded: _expanded,
              child: TextButton.icon(
                key: ValueKey('activity-group-toggle-${group.primary.id}'),
                onPressed: () => setState(() => _expanded = !_expanded),
                icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                label: Text(context.tr(
                    _expanded ? 'Hide {p0} entries' : 'Show {p0} entries',
                    {'p0': group.entries.length})),
              ),
            ),
          ),
        ),
        if (_expanded)
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: .35),
            ),
            foregroundDecoration: BoxDecoration(
              border: BorderDirectional(
                start: BorderSide(
                    color: Theme.of(context).colorScheme.primary, width: 2),
              ),
            ),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final entry in group.entries) widget.rowBuilder(entry),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
