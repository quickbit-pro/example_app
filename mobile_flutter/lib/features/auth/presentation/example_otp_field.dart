import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import 'auth_keyboard_recovery.dart';
import 'example_auth_field.dart' show exampleControlEdge;

/// One code cell per digit, all backed by a single input so typing, paste,
/// backspace and platform one-time-code autofill work without manually moving
/// between fields. Six cells by default; the payout, payee and withdrawal
/// flows ask for eight.
class ExampleOtpField extends StatefulWidget {
  const ExampleOtpField({
    super.key,
    required this.controller,
    this.length = 6,
    this.enabled = true,
    this.autofocus = true,
    this.label,
    this.onChanged,
  }) : assert(length > 0, 'An OTP field needs at least one cell');

  final TextEditingController controller;

  /// How many digits the code has; also the cell count and the input cap.
  final int length;
  final bool enabled;
  final bool autofocus;

  /// Accessible name of the hidden input. Defaults to a length-aware
  /// "Six-digit code" / "8-digit code".
  final String? label;
  final ValueChanged<String>? onChanged;

  @override
  State<ExampleOtpField> createState() => _ExampleOtpFieldState();
}

class _ExampleOtpFieldState extends State<ExampleOtpField>
    with WidgetsBindingObserver {
  final _focus = FocusNode(debugLabel: 'ExampleOtpField');
  bool _resumed = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resumed = true;
  }

  void _recoverInput() {
    if (_resumed && _focus.hasFocus) {
      _focus.unfocus();
      FocusManager.instance.applyFocusChangesIfNeeded();
      _focus.requestFocus();
    } else {
      recoverAuthKeyboard(context, _focus);
    }
    _resumed = false;
  }

  int get length => widget.length;
  bool get enabled => widget.enabled;
  bool get autofocus => widget.autofocus;
  String? get label => widget.label;
  TextEditingController get controller => widget.controller;
  ValueChanged<String>? get onChanged => widget.onChanged;

  /// Eight cells have to share the width six used to, so the gap between them
  /// tightens rather than the cells themselves: at 360 logical pixels inside
  /// 20 px of surface padding each cell still keeps about 34 px.
  double get _gap => length > 6 ? 6 : 8;

  String _defaultLabel(BuildContext context) => length == 6
      ? context.tr('Six-digit code')
      : context.tr('{p0}-digit code', {'p0': length});

  /// Platform autofill delivers a code to a field only through an
  /// [AutofillScope]. A caller that already groups its fields keeps its own
  /// scope; a lone field brings one along, so autofill works wherever the
  /// cells are dropped.
  Widget _scoped(BuildContext context, Widget input) =>
      AutofillGroup.maybeOf(context) == null
          ? AutofillGroup(child: input)
          : input;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Stack(
          children: [
            ExcludeSemantics(
              child: ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, child) => Row(
                  children: [
                    for (var index = 0; index < length; index++) ...[
                      Expanded(
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ExampleSurface.of(context, 1),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              // A code cell is a control, so its resting edge
                              // has to clear 3:1 on paper — the daylight
                              // hairline would leave six invisible boxes.
                              color: index < value.text.length
                                  ? ExamplePalette.of(context).accent
                                  : exampleControlEdge(context).color,
                              width: index < value.text.length ? 1.5 : 1,
                            ),
                          ),
                          child: Text(
                            index < value.text.length ? value.text[index] : '',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                      ),
                      if (index != length - 1) SizedBox(width: _gap),
                    ],
                  ],
                ),
              ),
            ),
            Positioned.fill(
              child: Semantics(
                label: label ?? _defaultLabel(context),
                child: Opacity(
                  opacity: 0,
                  alwaysIncludeSemantics: true,
                  child: _scoped(
                    context,
                    TextFormField(
                      controller: controller,
                      focusNode: _focus,
                      onTapAlwaysCalled: true,
                      onTap: _recoverInput,
                      enabled: enabled,
                      autofocus: autofocus,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(length),
                      ],
                      decoration: const InputDecoration(
                        counterText: '',
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        errorBorder: InputBorder.none,
                      ),
                      onChanged: onChanged,
                      validator: (value) => value?.length == length
                          ? null
                          : context.tr('Enter all {p0} digits', {'p0': length}),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
