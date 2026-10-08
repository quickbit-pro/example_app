import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/banking_models.dart';
import '../domain/card_pin_policy.dart';

/// Asks for a new six-digit card PIN (entered twice) and checks it against
/// [cardPinRules] live. Resolves with the PIN once it is valid and confirmed,
/// or null when dismissed. Sending it to the card provider is the caller's job.
Future<String?> showSetCardPinSheet(BuildContext context, PaymentCard card) {
  final isExample = context.isExampleTheme;
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: isExample ? ExampleSurface.of(context, 1) : null,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _SetCardPinForm(card: card),
      ),
    ),
  );
}

class _SetCardPinForm extends StatefulWidget {
  const _SetCardPinForm({required this.card});

  final PaymentCard card;

  @override
  State<_SetCardPinForm> createState() => _SetCardPinFormState();
}

class _SetCardPinFormState extends State<_SetCardPinForm> {
  final _pin = TextEditingController();
  final _confirm = TextEditingController();
  var _showErrors = false;

  @override
  void dispose() {
    _pin.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _pinValid => cardPinMeetsPolicy(_pin.text);
  bool get _matches => _confirm.text == _pin.text;
  bool get _canSave => _pinValid && _matches;

  void _submit() {
    if (!_canSave) {
      setState(() => _showErrors = true);
      return;
    }
    Navigator.of(context).pop(_pin.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final secondary = isExample
        ? ExampleInk.secondary(context)
        : theme.colorScheme.onSurfaceVariant;
    final label = widget.card.last4.isEmpty
        ? widget.card.label
        : '${widget.card.label} •• ${widget.card.last4}';
    final confirmError = _showErrors && !_matches && _confirm.text.isNotEmpty
        ? 'The PINs do not match.'
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Set card PIN'),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr(
              'Choose a 6-digit PIN for {p0}. Pick something only you would know; it is never shown again.',
              {'p0': label}),
          style: TextStyle(fontSize: 12.5, height: 1.45, color: secondary),
        ),
        const SizedBox(height: 16),
        _PinField(
          controller: _pin,
          label: context.tr('New PIN'),
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 10),
        CardPinChecklist(pin: _pin.text, showErrors: _showErrors),
        const SizedBox(height: 14),
        _PinField(
          controller: _confirm,
          label: context.tr('Confirm PIN'),
          errorText: confirmError,
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 18),
        if (isExample)
          ExampleGlassButton(
            label: context.tr('Save PIN'),
            onPressed: _canSave ? _submit : null,
          )
        else
          FilledButton(
            onPressed: _canSave ? _submit : null,
            child: Text(context.tr('Save PIN')),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
      ],
    );
  }
}

class _PinField extends StatelessWidget {
  const _PinField({
    required this.controller,
    required this.label,
    required this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [],
        keyboardType: TextInputType.number,
        textInputAction:
            onSubmitted == null ? TextInputAction.next : TextInputAction.done,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(cardPinLength),
        ],
        style: const TextStyle(letterSpacing: 6, fontSize: 18),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          counterText: '',
        ),
      );
}

/// Live checklist of the PIN rules: ticks as each is satisfied, and the
/// unmet ones turn red once the user has tried to save.
class CardPinChecklist extends StatelessWidget {
  const CardPinChecklist({
    required this.pin,
    this.showErrors = false,
    super.key,
  });

  final String pin;
  final bool showErrors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;
    final okColor = isExample
        ? ExamplePalette.of(context).success
        : context.brandDesign.color(theme.brightness, 'success',
            fallback: Colors.green.shade700);
    final badColor =
        isExample ? ExamplePalette.of(context).warning : theme.colorScheme.error;
    final muted = isExample
        ? ExampleInk.tertiary(context)
        : theme.colorScheme.onSurfaceVariant;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final rule in cardPinRules)
          Builder(
            builder: (context) {
              // Structural rules only make sense once the PIN is complete;
              // until then they read as pending rather than failed.
              final complete = pin.length == cardPinLength;
              final met =
                  rule.test(pin) && (complete || rule == cardPinRules.first);
              final failed = showErrors && !met;
              final color = met
                  ? okColor
                  : failed
                      ? badColor
                      : muted;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      met
                          ? Icons.check_circle_rounded
                          : failed
                              ? Icons.cancel_rounded
                              : Icons.radio_button_unchecked_rounded,
                      size: 16,
                      color: color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rule.label,
                        style: TextStyle(fontSize: 12.5, color: color),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
