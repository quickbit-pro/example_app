import 'package:flutter/material.dart';

class ExchangeLimitsDialog extends StatefulWidget {
  const ExchangeLimitsDialog({super.key, this.allowBasic = true, this.currentTier});

  final bool allowBasic;
  final String? currentTier;

  @override
  State<ExchangeLimitsDialog> createState() => _ExchangeLimitsDialogState();
}

class _ExchangeLimitsDialogState extends State<ExchangeLimitsDialog> {
  late String? selectedTier = ['sdd', 'cdd'].contains(widget.currentTier)
      ? widget.currentTier
      : null;

  @override
  Widget build(BuildContext context) => AlertDialog(
        scrollable: true,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('Choose Exchange limits'),
        content: SizedBox(
          width: 400,
          child: RadioGroup<String>(
            groupValue: selectedTier,
            onChanged: (value) => setState(() => selectedTier = value),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                    'Select your limits, then continue to verification.'),
                const SizedBox(height: 20),
                if (widget.allowBasic) ...[
                  _LimitOption(
                    value: 'sdd',
                    title: 'Basic',
                    limit: '\$1,000 per 3 months',
                    selected: selectedTier == 'sdd',
                  ),
                  const SizedBox(height: 12),
                ],
                _LimitOption(
                  value: 'cdd',
                  title: 'Higher limits',
                  limit: '\$25,000 per year',
                  selected: selectedTier == 'cdd',
                ),
              ],
            ),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: selectedTier == null
                  ? null
                  : () => Navigator.pop(context, selectedTier),
              child: const Text('Continue'),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ),
        ],
      );
}

class _LimitOption extends StatelessWidget {
  const _LimitOption({
    required this.value,
    required this.title,
    required this.limit,
    required this.selected,
  });

  final String value;
  final String title;
  final String limit;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: selected ? colors.primaryContainer : colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? colors.primary : colors.outline,
          width: selected ? 2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: RadioListTile<String>(
        value: value,
        selected: selected,
        activeColor: colors.primary,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        title: Text(title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: selected ? colors.onPrimaryContainer : colors.onSurface,
            )),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(limit,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: selected
                    ? colors.onPrimaryContainer
                    : colors.onSurfaceVariant,
              )),
        ),
      ),
    );
  }
}
