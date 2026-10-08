import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/app_localizations.dart';

class AssistantTripBudget {
  const AssistantTripBudget(this.amount, this.currency, this.basis);
  final int amount;
  final String currency;
  final String basis;
  String get label => '$currency $amount $basis';
}

/// Draft-only choices. Their readable text enters the normal validated chat
/// request; selecting a date or budget never calls the assistant API.
class AssistantTripDetails {
  const AssistantTripDetails({this.dates, this.budget});
  final DateTimeRange? dates;
  final AssistantTripBudget? budget;

  String get requestText => [
        if (dates != null)
          'Travel dates: ${_date(dates!.start)} to ${_date(dates!.end)}.',
        if (budget != null) 'Maximum budget: ${budget!.label}.',
      ].join('\n');

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
}

/// Replaces only the previously inserted text, preserving the customer's edits.
String applyAssistantTripDetails(String draft, String previous, String next) {
  var text = draft;
  if (previous.isNotEmpty && text.contains(previous)) {
    text = text.replaceFirst(previous, '').trim();
  }
  return [text.trim(), next].where((part) => part.isNotEmpty).join('\n\n');
}

class AssistantQuickEntry extends StatefulWidget {
  const AssistantQuickEntry(
      {super.key,
      required this.value,
      required this.onChanged,
      this.enabled = true,
      this.trailing = const []});
  final AssistantTripDetails value;
  final ValueChanged<AssistantTripDetails> onChanged;
  final bool enabled;
  final List<Widget> trailing;

  @override
  State<AssistantQuickEntry> createState() => _AssistantQuickEntryState();
}

class _AssistantQuickEntryState extends State<AssistantQuickEntry> {
  Route<dynamic>? _route;
  NavigatorState? _navigator;

  Future<T?> _show<T>(WidgetBuilder builder) async {
    if (_route != null) return null;
    final navigator = _navigator = Navigator.of(context);
    final route = DialogRoute<T>(context: context, builder: builder);
    _route = route;
    final result = await navigator.push(route);
    if (!mounted || _route != route) return null;
    _route = null;
    return result;
  }

  @override
  void dispose() {
    final route = _route;
    final navigator = _navigator;
    _route = null;
    if (route != null) {
      scheduleMicrotask(() {
        if (navigator?.mounted == true && route.isActive) {
          navigator!.removeRoute(route);
        }
      });
    }
    super.dispose();
  }

  Future<void> _dates() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final today = DateUtils.dateOnly(DateTime.now());
    final current = widget.value.dates;
    final result =
        await _show<DateTimeRange>((context) => DateRangePickerDialog(
              firstDate: today,
              lastDate: DateTime(today.year + 2, today.month, today.day),
              initialDateRange:
                  current != null && !current.start.isBefore(today)
                      ? current
                      : null,
              initialEntryMode: DatePickerEntryMode.calendarOnly,
              helpText: context.tr('Departure and return dates'),
              saveText: context.tr('Use dates'),
            ));
    if (mounted && widget.enabled && result != null) {
      widget.onChanged(
          AssistantTripDetails(dates: result, budget: widget.value.budget));
    }
  }

  Future<void> _budget() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final result = await _show<AssistantTripBudget>(
        (context) => _BudgetDialog(value: widget.value.budget));
    if (mounted && widget.enabled && result != null) {
      widget.onChanged(
          AssistantTripDetails(dates: widget.value.dates, budget: result));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = widget.value.dates;
    final formats = MaterialLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            InputChip(
              key: const ValueKey('assistant-dates'),
              avatar: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(dates == null
                  ? context.tr('Dates')
                  : '${formats.formatCompactDate(dates.start)} – ${formats.formatCompactDate(dates.end)}'),
              onPressed: widget.enabled ? _dates : null,
              onDeleted: widget.enabled && dates != null
                  ? () => widget.onChanged(
                      AssistantTripDetails(budget: widget.value.budget))
                  : null,
              deleteButtonTooltipMessage: context.tr('Clear dates'),
            ),
            InputChip(
              key: const ValueKey('assistant-budget'),
              avatar: const Icon(Icons.payments_outlined, size: 18),
              label: Text(widget.value.budget?.label ?? context.tr('Budget')),
              onPressed: widget.enabled ? _budget : null,
              onDeleted: widget.enabled && widget.value.budget != null
                  ? () => widget.onChanged(AssistantTripDetails(dates: dates))
                  : null,
              deleteButtonTooltipMessage: context.tr('Clear budget'),
            ),
            ...widget.trailing,
          ]),
    );
  }
}

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({this.value});
  final AssistantTripBudget? value;
  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final TextEditingController _amount;
  late String _currency;
  late String _basis;
  final _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _amount =
        TextEditingController(text: widget.value?.amount.toString() ?? '');
    _currency = widget.value?.currency ?? 'EUR';
    _basis = widget.value?.basis ?? 'total for the trip';
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(context.tr('Trip budget')),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
              key: _form,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _currency,
                      isExpanded: true,
                      decoration:
                          InputDecoration(labelText: context.tr('Currency')),
                      items: [
                        for (final currency in ['EUR', 'USD', 'GBP', 'CHF'])
                          DropdownMenuItem(
                              value: currency, child: Text(currency))
                      ],
                      onChanged: (value) => setState(() => _currency = value!),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final amount in [250, 500, 1000, 2500, 5000])
                        ChoiceChip(
                            label: Text('$_currency $amount'),
                            selected: _amount.text == '$amount',
                            onSelected: (_) =>
                                setState(() => _amount.text = '$amount')),
                    ]),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('assistant-budget-amount'),
                      controller: _amount,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(7)
                      ],
                      decoration: InputDecoration(
                          labelText: context.tr('Or enter an amount'),
                          prefixText: '$_currency '),
                      onChanged: (_) => setState(() {}),
                      validator: (text) {
                        final amount = int.tryParse(text ?? '');
                        return amount == null || amount < 1 || amount > 1000000
                            ? context
                                .tr('Choose an amount from 1 to 1,000,000.')
                            : null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _basis,
                      isExpanded: true,
                      decoration: InputDecoration(
                          labelText: context.tr('Budget covers')),
                      items: [
                        for (final basis in [
                          'total for the trip',
                          'per person',
                          'per night'
                        ])
                          DropdownMenuItem(
                              value: basis, child: Text(context.tr(basis)))
                      ],
                      onChanged: (value) => setState(() => _basis = value!),
                    ),
                  ]),
            ))),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('Cancel'))),
          FilledButton(
              onPressed: () {
                if (_form.currentState!.validate()) {
                  Navigator.of(context).pop(AssistantTripBudget(
                      int.parse(_amount.text), _currency, _basis));
                }
              },
              child: Text(context.tr('Use budget'))),
        ],
      );
}
