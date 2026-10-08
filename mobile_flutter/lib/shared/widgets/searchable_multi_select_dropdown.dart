import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../brands/example/example_colors.dart';
import '../../brands/example/example_ui.dart';
import './app_progress_indicator.dart';

typedef OptionLabelBuilder = String Function(String value);

class SearchableSingleSelectDropdown extends StatelessWidget {
  const SearchableSingleSelectDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelBuilder = defaultOptionLabel,
    this.required = true,
    this.enabled = true,
    this.showLabel = true,
  });

  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final OptionLabelBuilder labelBuilder;
  final bool required;
  final bool enabled;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final selected = value?.trim() ?? '';
    return FormField<String>(
      key: ValueKey('$label:$selected:${options.length}'),
      initialValue: selected,
      validator: (_) {
        if (required && selected.isEmpty) {
          return context.tr('{p0} is required', {'p0': label});
        }
        if (selected.isNotEmpty && !options.contains(selected)) {
          return context.tr('Choose a valid {p0}', {'p0': label});
        }
        return null;
      },
      builder: (field) => context.isExampleTheme
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showLabel) ...[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: ExamplePalette.of(context).textSecondary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                ],
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: enabled && options.isNotEmpty
                      ? () => _openPicker(context, field)
                      : null,
                  child: InputDecorator(
                    isEmpty: selected.isEmpty,
                    decoration: InputDecoration(
                      errorText: field.errorText,
                      suffixIcon: enabled
                          ? const Icon(Icons.expand_more_rounded, size: 20)
                          : const SizedBox.square(
                              dimension: 20,
                              child: Padding(
                                padding: EdgeInsets.all(14),
                                child: AppProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? context
                              .tr('Select {p0}', {'p0': label.toLowerCase()})
                          : labelBuilder(selected),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: selected.isEmpty
                            ? Theme.of(context).hintColor
                            : ExamplePalette.of(context).ink,
                      ),
                    ),
                  ),
                ),
              ],
            )
          : InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: enabled && options.isNotEmpty
                  ? () => _openPicker(context, field)
                  : null,
              child: InputDecorator(
                isEmpty: selected.isEmpty,
                decoration: InputDecoration(
                  labelText: label,
                  errorText: field.errorText,
                  border: const OutlineInputBorder(),
                  suffixIcon: enabled
                      ? const Icon(Icons.arrow_drop_down)
                      : const SizedBox.square(
                          dimension: 20,
                          child: Padding(
                            padding: EdgeInsets.all(14),
                            child: AppProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                ),
                child: Text(
                  selected.isEmpty
                      ? context.tr('Select {p0}', {'p0': label})
                      : labelBuilder(selected),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: selected.isEmpty
                      ? TextStyle(color: Theme.of(context).hintColor)
                      : null,
                ),
              ),
            ),
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    FormFieldState<String> field,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _SearchableSingleSelectDialog(
        title: label,
        options: options,
        selected: value,
        labelBuilder: labelBuilder,
      ),
    );
    if (result == null || !field.mounted || !context.mounted) return;
    field.didChange(result);
    onChanged(result);
  }
}

class _SearchableSingleSelectDialog extends StatefulWidget {
  const _SearchableSingleSelectDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
  });

  final String title;
  final List<String> options;
  final String? selected;
  final OptionLabelBuilder labelBuilder;

  @override
  State<_SearchableSingleSelectDialog> createState() =>
      _SearchableSingleSelectDialogState();
}

class _SearchableSingleSelectDialogState
    extends State<_SearchableSingleSelectDialog> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = widget.options.where((option) {
      return query.isEmpty ||
          option.toLowerCase().contains(query) ||
          widget.labelBuilder(option).toLowerCase().contains(query);
    }).toList();

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.title),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context
                      .tr('Search {p0}', {'p0': widget.title.toLowerCase()}),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(child: Text(context.tr('No matching options')))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        final selected = option == widget.selected;
                        return ListTile(
                          leading: Icon(
                            selected
                                ? Icons.check_circle
                                : Icons.circle_outlined,
                          ),
                          title: Text(widget.labelBuilder(option)),
                          onTap: () => Navigator.of(context).pop(option),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchableMultiSelectDropdown extends StatelessWidget {
  const SearchableMultiSelectDropdown({
    super.key,
    required this.label,
    required this.values,
    required this.options,
    required this.onChanged,
    this.labelBuilder = defaultOptionLabel,
    this.required = true,
  });

  final String label;
  final List<String> values;
  final List<String> options;
  final ValueChanged<List<String>> onChanged;
  final OptionLabelBuilder labelBuilder;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return FormField<List<String>>(
      key: ValueKey('$label:${values.join('|')}'),
      initialValue: values,
      validator: (_) {
        if (required && values.isEmpty) {
          return context.tr('{p0} is required', {'p0': label});
        }

        return null;
      },
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => _openPicker(context, field),
          child: InputDecorator(
            isEmpty: values.isEmpty,
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              border: const OutlineInputBorder(),
              suffixIcon: const Icon(Icons.arrow_drop_down),
            ),
            child: Text(
              _summaryText(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: values.isEmpty
                  ? TextStyle(color: Theme.of(context).hintColor)
                  : null,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openPicker(
    BuildContext context,
    FormFieldState<List<String>> field,
  ) async {
    final selected = values.toSet();
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) => _SearchableMultiSelectDialog(
        title: label,
        options: options,
        selected: selected,
        labelBuilder: labelBuilder,
      ),
    );

    if (result == null) {
      return;
    }

    final ordered = options.where(result.toSet().contains).toList();
    field.didChange(ordered);
    onChanged(ordered);
  }

  String _summaryText() {
    if (values.isEmpty) {
      return 'Select options';
    }

    final labels = values.map(labelBuilder).toList();
    if (labels.length <= 3) {
      return labels.join(', ');
    }

    return '${labels.take(3).join(', ')} +${labels.length - 3} more';
  }
}

class _SearchableMultiSelectDialog extends StatefulWidget {
  const _SearchableMultiSelectDialog({
    required this.title,
    required this.options,
    required this.selected,
    required this.labelBuilder,
  });

  final String title;
  final List<String> options;
  final Set<String> selected;
  final OptionLabelBuilder labelBuilder;

  @override
  State<_SearchableMultiSelectDialog> createState() =>
      _SearchableMultiSelectDialogState();
}

class _SearchableMultiSelectDialogState
    extends State<_SearchableMultiSelectDialog> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filteredOptions = widget.options.where(_matchesQuery).toList();

    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
          title: Text(widget.title),
          actions: [
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: Text(context.tr('Clear')),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(_selected.toList()),
              child: Text(context.tr('Apply ({p0})', {'p0': _selected.length})),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  labelText: context
                      .tr('Search {p0}', {'p0': widget.title.toLowerCase()}),
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            Expanded(
              child: filteredOptions.isEmpty
                  ? Center(child: Text(context.tr('No matching options')))
                  : ListView.builder(
                      itemCount: filteredOptions.length,
                      itemBuilder: (context, index) {
                        final option = filteredOptions[index];
                        final isSelected = _selected.contains(option);
                        return CheckboxListTile(
                          value: isSelected,
                          title: Text(widget.labelBuilder(option)),
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: (value) {
                            setState(() {
                              if (value ?? false) {
                                _selected.add(option);
                              } else {
                                _selected.remove(option);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  bool _matchesQuery(String option) {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }

    return option.toLowerCase().contains(normalizedQuery) ||
        widget.labelBuilder(option).toLowerCase().contains(normalizedQuery);
  }
}

String defaultOptionLabel(String value) {
  return value
      .replaceAll('_', ' ')
      .toLowerCase()
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) {
    if (part.length <= 3) {
      return part.toUpperCase();
    }

    return '${part[0].toUpperCase()}${part.substring(1)}';
  }).join(' ');
}
