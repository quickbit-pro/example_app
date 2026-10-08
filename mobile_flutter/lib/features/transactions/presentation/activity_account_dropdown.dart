import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import '../application/activity_account_options_provider.dart';
import '../domain/activity_account_option.dart';

/// Account scope remains available independently of operation type/history.
class ActivityAccountDropdown extends ConsumerWidget {
  const ActivityAccountDropdown({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final ActivityAccountOption? selected;
  final ValueChanged<ActivityAccountOption?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(activityAccountOptionsProvider);
    final options = {for (final option in state.options) option.key: option};
    final selected = this.selected;
    final viewport = MediaQuery.of(context);
    final availableHeight = math.max(
        0.0,
        viewport.size.height -
            viewport.padding.vertical -
            viewport.viewInsets.vertical);
    // A refresh, source failure, or account with empty history never clears the
    // chosen scope. All accounts is always available to remove it explicitly.
    if (selected != null) options.putIfAbsent(selected.key, () => selected);
    final example = context.isExampleTheme;
    final color = example
        ? ExampleInk.primary(context)
        : Theme.of(context).colorScheme.onSurface;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: example
          ? ExampleBorders.controlSideOf(context)
          : BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: context.tr('Filter activity by account'),
          child: InputDecorator(
            decoration: InputDecoration(
              isDense: true,
              constraints: const BoxConstraints(minHeight: 48),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              prefixIcon: Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: color),
              prefixIconConstraints: const BoxConstraints(minWidth: 38),
              filled: true,
              fillColor: example ? ExampleSurface.of(context, 2) : null,
              border: border,
              enabledBorder: border,
              focusedBorder: border,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('activity-account-dropdown'),
                value: selected?.key ?? '',
                isExpanded: true,
                isDense: true,
                // Menu size follows the viewport, not the narrow toolbar
                // button, so currency and account identity remain readable.
                menuWidth: math.min(520, viewport.size.width - 32),
                menuMaxHeight: math.min(440, availableHeight * .65),
                itemHeight: null,
                dropdownColor: example ? ExampleSurface.of(context, 2) : null,
                borderRadius: BorderRadius.circular(16),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                selectedItemBuilder: (context) => [
                  for (final label in [
                    context.tr('All accounts'),
                    ...options.values.map((option) => option.label)
                  ])
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Tooltip(
                          message: label,
                          child: Text(label,
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ),
                ],
                items: [
                  DropdownMenuItem(
                      value: '', child: Text(context.tr('All accounts'))),
                  for (final option in options.values)
                    DropdownMenuItem(
                        value: option.key,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Text(option.label, softWrap: true),
                        )),
                ],
                onChanged: (key) =>
                    onChanged(key == null || key.isEmpty ? null : options[key]),
              ),
            ),
          ),
        ),
        if (state.isLoading || state.errors.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Row(children: [
              Expanded(
                  child: Text(
                state.errors.isNotEmpty
                    ? context.tr(
                        '{p0} could not load', {'p0': state.errors.join(', ')})
                    : context.tr('Loading accounts…'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: example ? ExampleInk.secondary(context) : null),
              )),
              if (state.errors.isNotEmpty)
                IconButton(
                    tooltip: context.tr('Retry account filters'),
                    onPressed: state.retry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    visualDensity: VisualDensity.compact),
            ]),
          ),
      ],
    );
  }
}
