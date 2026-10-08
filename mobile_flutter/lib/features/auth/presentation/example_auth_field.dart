import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import 'auth_keyboard_recovery.dart';

/// The edge of an *interactive container* on an auth surface: an input, a
/// secondary button, a choice tile.
///
/// Now an alias for [ExampleBorders.controlSideOf], which is where the rule
/// belongs — every wave needs the 3:1 control boundary, not only auth. Kept so
/// the auth call sites read in their own vocabulary and so no import moves.
///
/// Twilight spends the lavender .14 hairline, because the control is already
/// lighter than the ground behind it and the edge only has to describe the
/// corner. On paper a white control on F8F5FC carries 1.03:1 of its own, so
/// the edge is the entire affordance and has to hold the 3:1 WCAG 1.4.11 asks
/// of a control boundary: night .58 measures 4.77:1 on white, where the
/// daylight hairline (lavender .30) measures 1.18:1 and would leave the
/// control invisible.
///
/// Structural hairlines — dividers, rules, row separators — are not controls
/// and keep [ExampleBorders.subtleSideOf].
BorderSide exampleControlEdge(BuildContext context, {double width = 1}) =>
    ExampleBorders.controlSideOf(context, width: width);

/// Example text field for the auth screens (login, signup, account claim), in
/// both themes.
///
/// A 56 pt box on `ExampleSurface.of(context, 1)` with `AppRadii.sm` corners and
/// a one-pixel edge that moves between rest, focus and invalid over
/// `ExampleMotion.state` with `ExampleMotion.arrive`. Twilight keeps its exact
/// three edges (lavender .14, iris .38, danger); pearl daylight re-earns each
/// one against white — night .58 at rest so the boundary clears 3:1, the solid
/// accent on focus so focus is louder than rest, and `lightDanger` when
/// invalid. The prefix icon follows the same three states. Validation text
/// arrives under the box
/// through [ExampleStateSwitch] as a live region; [helperText] sits in the same
/// slot while the field is valid. Every transition collapses to instant under
/// reduced motion.
///
/// It is a [FormField], so `Form.validate`, `save` and `reset` work exactly as
/// they do for `TextFormField`, and [controller] stays the source of truth:
/// programmatic writes (a remembered email, an invitation address) are picked
/// up by validation without any extra call.
///
/// Sibling controls placed in [suffix] must be 44 pt targets; see
/// [ExamplePasswordToggle].
class ExampleAuthField extends FormField<String> {
  ExampleAuthField({
    required this.controller,
    this.label,
    this.hintText,
    this.helperText,
    this.prefixIcon,
    this.suffix,
    this.obscureText = false,
    this.readOnly = false,
    this.autofocus = false,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.keyboardType,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    super.enabled = true,
    super.validator,
    super.onSaved,
    super.autovalidateMode,
    super.key,
  }) : super(initialValue: controller.text, builder: _build);

  /// Source of truth for the text; the field listens to it.
  final TextEditingController controller;

  /// Caption above the box, in the theme's `labelMedium`.
  final String? label;
  final String? hintText;

  /// Quiet guidance under the box; replaced by the error while invalid.
  final String? helperText;
  final IconData? prefixIcon;

  /// Trailing control inside the box (a [ExamplePasswordToggle]). Must be a
  /// 44 pt target; the box gives it a 44 pt slot.
  final Widget? suffix;
  final bool obscureText;
  final bool readOnly;
  final bool autofocus;
  final bool autocorrect;
  final bool enableSuggestions;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// Height of the input box. 56 keeps 16 pt above and below a 24 pt line.
  static const double height = 56;

  /// Width and height of the prefix and suffix slots.
  static const double controlSize = 44;

  static Widget _build(FormFieldState<String> field) =>
      (field as _ExampleAuthFieldState)._buildField();

  @override
  FormFieldState<String> createState() => _ExampleAuthFieldState();
}

class _ExampleAuthFieldState extends FormFieldState<String> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'ExampleAuthField');
  bool _focused = false;

  ExampleAuthField get _field => widget as ExampleAuthField;

  @override
  void initState() {
    super.initState();
    _field.controller.addListener(_handleControllerChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant ExampleAuthField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != _field.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      _field.controller.addListener(_handleControllerChanged);
      if (_field.controller.text != value) {
        setValue(_field.controller.text);
      }
    }
  }

  @override
  void dispose() {
    _field.controller.removeListener(_handleControllerChanged);
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  @override
  void reset() {
    super.reset();
    _field.controller.text = widget.initialValue ?? '';
  }

  void _handleControllerChanged() {
    if (_field.controller.text != value) {
      didChange(_field.controller.text);
    }
  }

  void _handleFocusChanged() {
    final focused = _focusNode.hasFocus;
    if (focused != _focused) {
      setState(() => _focused = focused);
    }
  }

  Widget _buildField() {
    final field = _field;
    final theme = Theme.of(context);
    final light = ExampleTheme.isLight(context);
    final ink = ExampleInk.primary(context);
    // Placeholder and resting glyph: the tertiary ink in both themes.
    final muted = ExampleInk.tertiary(context);
    final caption = ExampleInk.secondary(context);
    final restEdge = exampleControlEdge(context).color;
    // Focus has to read louder than rest in both themes, so daylight focus is
    // the solid accent (6.2:1) rather than the .55 violet edge (2.3:1).
    final focusEdge = light
        ? ExamplePalette.of(context).accent
        : ExamplePalette.of(context).borderEmphasis;
    final dangerInk = ExamplePalette.of(context).danger;
    final accentInk = ExamplePalette.of(context).accent;
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    final error = errorText;
    final invalid = error != null;
    final edge = invalid
        ? dangerInk
        : _focused
            ? focusEdge
            : restEdge;
    final iconColor = invalid
        ? dangerInk
        : _focused
            ? accentInk
            : muted;
    // Explicit line height so the box lands on exactly 56 pt: 16 above and
    // below a 24 pt line at the default text scale.
    final inputStyle = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(color: ink, fontSize: 16, height: 1.5);
    final hasPrefix = field.prefixIcon != null;
    final hasSuffix = field.suffix != null;
    const radius = BorderRadius.all(Radius.circular(AppRadii.sm));
    const slot = BoxConstraints(
      minWidth: ExampleAuthField.controlSize,
      minHeight: ExampleAuthField.controlSize,
    );

    final input = TextField(
      controller: field.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      readOnly: field.readOnly,
      autofocus: field.autofocus,
      obscureText: field.obscureText,
      obscuringCharacter: '•',
      autocorrect: field.autocorrect,
      enableSuggestions: field.enableSuggestions,
      keyboardType: field.keyboardType,
      textInputAction: field.textInputAction,
      textCapitalization: field.textCapitalization,
      autofillHints: field.autofillHints,
      inputFormatters: field.inputFormatters,
      style: inputStyle,
      cursorColor: accentInk,
      textAlignVertical: TextAlignVertical.center,
      onChanged: (text) {
        didChange(text);
        field.onChanged?.call(text);
      },
      onSubmitted: field.onSubmitted,
      onTapAlwaysCalled: true,
      onTap: field.readOnly
          ? null
          : () => recoverAuthKeyboard(context, _focusNode),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        focusedErrorBorder: InputBorder.none,
        contentPadding: EdgeInsets.fromLTRB(
          hasPrefix ? AppSpacing.xxs : AppSpacing.md,
          AppSpacing.md,
          hasSuffix ? AppSpacing.xxs : AppSpacing.md,
          AppSpacing.md,
        ),
        hintText: field.hintText,
        hintStyle: inputStyle.copyWith(color: muted),
        prefixIcon: hasPrefix
            ? TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: iconColor),
                duration: duration,
                curve: ExampleMotion.arrive,
                builder: (context, color, _) =>
                    Icon(field.prefixIcon, size: 20, color: color),
              )
            : null,
        prefixIconConstraints: slot,
        suffixIcon: field.suffix,
        suffixIconConstraints: slot,
      ),
    );

    // The box paints fill and edge itself: the edge is a foreground
    // decoration so its colour can move without touching layout, and the
    // decorator above draws nothing.
    final box = AnimatedContainer(
      duration: duration,
      curve: ExampleMotion.arrive,
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: radius,
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: edge),
        borderRadius: radius,
      ),
      child: input,
    );

    final bodySmall = theme.textTheme.bodySmall ?? const TextStyle();
    final Widget subtext;
    if (invalid) {
      subtext = Padding(
        key: ValueKey('error:$error'),
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Semantics(
          liveRegion: true,
          child: Text(
            error,
            style: bodySmall.copyWith(color: dangerInk),
          ),
        ),
      );
    } else if (field.helperText != null) {
      subtext = Padding(
        key: const ValueKey('helper'),
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        // Caption, not the placeholder grey: helper text is content, and it
        // has to clear 4.5:1 the way the label above the box does.
        child: Text(
          field.helperText!,
          style: bodySmall.copyWith(color: caption),
        ),
      );
    } else {
      subtext = const SizedBox.shrink(key: ValueKey('none'));
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.label != null) ...[
          ExampleAuthFieldLabel(field.label!, color: caption),
          const SizedBox(height: AppSpacing.xs),
        ],
        AnimatedOpacity(
          opacity: widget.enabled ? 1 : ExampleOpacity.disabled,
          duration: duration,
          curve: ExampleMotion.arrive,
          child: box,
        ),
        ExampleStateSwitch(alignment: Alignment.topLeft, child: subtext),
      ],
    );
  }
}

/// Caption above an auth input, in the theme's `labelMedium`. [ExampleAuthField]
/// draws it for its [ExampleAuthField.label]; third-party inputs that cannot
/// take the field (the phone number input) use it directly so every caption
/// on the form matches.
class ExampleAuthFieldLabel extends StatelessWidget {
  const ExampleAuthFieldLabel(this.text, {this.color, super.key});

  final String text;

  /// Defaults to the secondary ink of the active theme: pearl .68 in Twilight,
  /// night .72 on paper.
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color ?? ExampleInk.secondary(context),
            ),
      );
}

/// Show / hide control for a password [ExampleAuthField]: a 44 pt
/// [ExamplePressable] target whose icon crossfades between the two states.
class ExamplePasswordToggle extends StatelessWidget {
  const ExamplePasswordToggle({
    required this.obscured,
    required this.onTap,
    super.key,
  });

  final bool obscured;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final message =
        obscured ? context.tr('Show password') : context.tr('Hide password');
    final direction = Directionality.of(context);
    final view = View.of(context);
    return Tooltip(
      message: message,
      child: ExamplePressable(
        onTap: () {
          onTap();
          // The field itself has no live region, so a screen reader would
          // otherwise never learn that the characters became visible.
          SemanticsService.sendAnnouncement(
            view,
            obscured ? 'Password shown' : 'Password hidden',
            direction,
          );
        },
        semanticsLabel: message,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
        child: SizedBox.square(
          dimension: ExampleAuthField.controlSize,
          child: Center(
            child: ExampleStateSwitch(
              child: Icon(
                obscured
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                key: ValueKey(obscured),
                size: 20,
                color: ExampleInk.tertiary(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Inline notice above an auth form's primary action: the server's answer to
/// a sign-in or a sign-up, in the place the user is already looking.
///
/// A snack bar is the wrong channel for this — it is off-screen for a
/// magnified user, it is dismissed by the next frame's route work, and a
/// second identical failure is never re-announced. This is a live region, so
/// assistive technology reads it the moment it appears, and it sits in the
/// form's own flow so nothing about it can be missed.
///
/// Give it the already-humanised message (`friendlyErrorMessage(error)`);
/// it never formats an exception itself.
class ExampleAuthAlert extends StatelessWidget {
  const ExampleAuthAlert({
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.tone = ExampleAuthAlertTone.error,
    super.key,
  });

  final String message;
  final IconData icon;
  final ExampleAuthAlertTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = switch (tone) {
      ExampleAuthAlertTone.error => ExamplePalette.of(context).danger,
      ExampleAuthAlertTone.info => ExamplePalette.of(context).accent,
    };
    return Semantics(
      container: true,
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
          border: Border.all(color: accent),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(color: accent),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum ExampleAuthAlertTone { error, info }
