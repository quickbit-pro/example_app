import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/data/auth_api.dart';
import '../../auth/presentation/example_auth_field.dart';
import '../../signup/presentation/password_strength_checklist.dart';

// ─── The Example settings sheet ──────────────────────────────────────────────

/// The sheet every Settings detail opens in, in both themes.
///
/// Chrome ground (`navigationSurface` at night, white on paper), `AppRadii.xl`
/// top corners, a drag handle, and travel on [ExampleMotion.sheet] out with
/// [ExampleMotion.sheetCurve] and three quarters of that back on
/// [ExampleMotion.exit] — all collapsing to instant under reduced motion,
/// because the duration is read through [ExampleMotion.of].
///
/// The shell owns the safe area, the keyboard inset and the 20 pt gutter, so a
/// caller passes content only. [scrollable] is the default because a form at
/// text scale 1.3 with the keyboard up is taller than the sheet; pass false
/// when the content manages its own scrolling (a list, a fixed-height pane).
///
/// Nothing here renders differently for another brand by accident: the Example
/// ground is applied only under `context.isExampleTheme`, so a white-label
/// caller keeps the Material sheet it had.
Future<T?> showExampleSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool scrollable = true,
  EdgeInsets padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
  double maxWidth = 560,
}) {
  final example = context.isExampleTheme;
  final enter = ExampleMotion.of(context, ExampleMotion.sheet);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: example ? ExampleSurface.navigationOf(context) : null,
    constraints: BoxConstraints(maxWidth: maxWidth),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
    ),
    sheetAnimationStyle: AnimationStyle(
      duration: enter,
      reverseDuration: ExampleMotion.exitOf(enter),
      curve: ExampleMotion.sheetCurve,
      reverseCurve: ExampleMotion.exit,
    ),
    builder: (sheetContext) {
      final content = Builder(builder: builder);
      return SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: scrollable
              ? SingleChildScrollView(padding: padding, child: content)
              : Padding(padding: padding, child: content),
        ),
      );
    },
  );
}

/// Title line of a [showExampleSheet], with an optional trailing control row.
///
/// The title is the sheet's accessible header, so it is marked as one; icon
/// actions passed in [actions] must carry their own tooltip and a 44 pt box.
class ExampleSheetHeader extends StatelessWidget {
  const ExampleSheetHeader({
    required this.title,
    this.actions = const <Widget>[],
    super.key,
  });

  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final label = Semantics(
      header: true,
      child: Text(
        title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: (Theme.of(context).textTheme.titleMedium ??
                const TextStyle(fontSize: 16))
            .copyWith(
          fontWeight: FontWeight.w700,
          color: ExampleInk.primary(context),
          height: 1.25,
        ),
      ),
    );
    if (actions.isEmpty) {
      return SizedBox(width: double.infinity, child: label);
    }
    return Row(
      children: [
        Expanded(child: label),
        const SizedBox(width: AppSpacing.xs),
        ...actions,
      ],
    );
  }
}

/// Quiet explanatory copy under a [ExampleSheetHeader]: the secondary ink in
/// both themes (pearl .68 at night, night .72 on paper), never the tertiary
/// tone, because this is body text and has to hold 4.5:1.
class ExampleSheetNote extends StatelessWidget {
  const ExampleSheetNote(this.text, {this.icon, this.tone, super.key});

  final String text;

  /// Optional leading glyph; use it only for a caution, with [tone].
  final IconData? icon;

  /// Brand token for [icon], resolved through `ExampleInk.accent`: the hue
  /// itself at night, its daylight partner on paper.
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final body = Text(
      context.tr(text),
      style: (Theme.of(context).textTheme.bodySmall ??
              const TextStyle(fontSize: 12.5))
          .copyWith(color: ExampleInk.secondary(context), height: 1.45),
    );
    final glyph = icon;
    if (glyph == null) return body;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(
            glyph,
            size: 18,
            color: ExampleInk.accent(context, tone ?? ExampleColors.iris),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: body),
      ],
    );
  }
}

/// Emphasis of the one confirming action in a sheet.
enum ExampleSheetCtaTone {
  /// The themed primary fill.
  primary,

  /// A destructive confirmation the customer opened on purpose (turning
  /// two-step verification off, removing a duress password).
  danger,
}

/// The single confirming action of a sheet, on the product's CTA material.
///
/// Full width, 52 pt, and now a [ExampleGlassButton] rather than a themed
/// [FilledButton], so the decisive control in a security sheet is the same
/// object the customer met on the sign-in screen instead of a Material
/// default wearing brand colours. Its own busy state holds the silhouette,
/// width and position and swaps the label for a centred ring, which is what
/// the [ExampleStateSwitch] here used to do by hand.
///
/// `ExampleGlassGround.surface`, never `atmosphere`: a sheet is a painted
/// chrome ground over a scrim, so there is nothing behind it worth blurring —
/// the material goes opaque and keeps the identical silhouette, radius, edge
/// treatment and motion. No sheen either: these sheets confirm an action,
/// they do not announce one, and Settings is a utility register.
class ExampleSheetCta extends StatelessWidget {
  const ExampleSheetCta({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel = 'Working',
    this.tone = ExampleSheetCtaTone.primary,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  /// Announced while [busy]; a screen reader otherwise hears nothing happen.
  final String busyLabel;
  final ExampleSheetCtaTone tone;

  static const double height = 52;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: ExampleGlassButton(
          label: label,
          tone: tone == ExampleSheetCtaTone.danger
              ? ExampleGlassButtonTone.danger
              : ExampleGlassButtonTone.primary,
          height: height,
          loading: busy,
          // The sheets already write a full sentence here ("Checking your
          // password"), which is a better thing to hear than the widget's
          // generic "<label>, in progress".
          loadingSemanticsLabel: busyLabel,
          onPressed: busy ? null : onPressed,
        ),
      );
}

/// A quiet action under the CTA (copy, cancel). It never competes with the
/// CTA: text on the surface, on a 44 pt target.
class _SheetSecondary extends StatelessWidget {
  const _SheetSecondary({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44,
        child: ExamplePressable(
          child: TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: ExampleInk.accent(context, ExampleColors.iris),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}

/// Password field that password managers leave alone: no autofill hints,
/// no suggestions. Used for the duress password and for confirmations, so
/// managers never offer to replace the real password with the duress one.
///
/// Same 56 pt box, edges and state moves as the auth screens
/// ([ExampleAuthField]), so a customer meets one field in this product.
class _QuietPasswordField extends StatefulWidget {
  const _QuietPasswordField({
    required this.controller,
    required this.label,
    this.helper,
    this.autofocus = false,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? helper;
  final bool autofocus;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_QuietPasswordField> createState() => _QuietPasswordFieldState();
}

class _QuietPasswordFieldState extends State<_QuietPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => ExampleAuthField(
        controller: widget.controller,
        label: widget.label,
        helperText: widget.helper,
        obscureText: _obscured,
        autofocus: widget.autofocus,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const <String>[],
        keyboardType: TextInputType.visiblePassword,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        suffix: ExamplePasswordToggle(
          obscured: _obscured,
          onTap: () => setState(() => _obscured = !_obscured),
        ),
      );
}

/// A password field password managers *should* see: the current password on
/// the change-password sheet, and the new one it is asked to save.
class _ManagedPasswordField extends StatefulWidget {
  const _ManagedPasswordField({
    required this.controller,
    required this.label,
    required this.hints,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final Iterable<String> hints;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_ManagedPasswordField> createState() => _ManagedPasswordFieldState();
}

class _ManagedPasswordFieldState extends State<_ManagedPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) => ExampleAuthField(
        controller: widget.controller,
        label: widget.label,
        obscureText: _obscured,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: widget.hints,
        textInputAction: widget.textInputAction,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        suffix: ExamplePasswordToggle(
          obscured: _obscured,
          onTap: () => setState(() => _obscured = !_obscured),
        ),
      );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

// ─── Two-factor authentication ──────────────────────────────────────────────

Future<void> showTwoFactorSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool enabled,
}) =>
    enabled
        ? _showDisableTwoFactor(context, ref)
        : _showEnableTwoFactor(context, ref);

Future<void> _showEnableTwoFactor(BuildContext context, WidgetRef ref) =>
    showExampleSheet<void>(
      context,
      builder: (sheetContext) => _EnableTwoFactorSheet(controllerRef: ref),
    );

/// Password → authenticator → recovery codes, in one sheet.
///
/// Each stage swaps through [ExampleStateSwitch] at [ExampleMotion.state]: the
/// content crossfades and rises 2 px in place, so a step reads as a change of
/// state rather than a new screen, and it is instant under reduced motion.
class _EnableTwoFactorSheet extends StatefulWidget {
  const _EnableTwoFactorSheet({required this.controllerRef});

  final WidgetRef controllerRef;

  @override
  State<_EnableTwoFactorSheet> createState() => _EnableTwoFactorSheetState();
}

class _EnableTwoFactorSheetState extends State<_EnableTwoFactorSheet> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _code = TextEditingController();
  TwoFactorSetup? _setup;
  List<String>? _recoveryCodes;
  bool _busy = false;

  WidgetRef get _ref => widget.controllerRef;

  @override
  void dispose() {
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      final setup = await _ref
          .read(authApiProvider)
          .setupTwoFactor(password: _password.text);
      if (mounted) setState(() => _setup = setup);
    } catch (error) {
      if (mounted) _toast(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    setState(() => _busy = true);
    try {
      final codes =
          await _ref.read(authApiProvider).enableTwoFactor(code: _code.text);
      _ref.invalidate(accountSecurityProvider);
      if (mounted) setState(() => _recoveryCodes = codes);
    } catch (error) {
      if (mounted) _toast(context, friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final codes = _recoveryCodes;
    final pending = _setup;
    return ExampleStateSwitch(
      alignment: Alignment.topCenter,
      child: KeyedSubtree(
        key: ValueKey(
          codes != null
              ? 'codes'
              : pending != null
                  ? 'scan'
                  : 'password',
        ),
        child: codes != null
            ? _codesStage(codes)
            : pending != null
                ? _scanStage(pending)
                : _passwordStage(),
      ),
    );
  }

  Widget _passwordStage() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSheetHeader(title: context.tr('Two-step verification')),
          const SizedBox(height: AppSpacing.xs),
          ExampleSheetNote(
            context.tr(
                'Every sign-in will also need a code from an authenticator app. Confirm your password to start.'),
          ),
          const SizedBox(height: AppSpacing.md),
          _QuietPasswordField(
            controller: _password,
            label: context.tr('Current password'),
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_busy) _start();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleSheetCta(
            label: context.tr('Continue'),
            busy: _busy,
            busyLabel: 'Checking your password',
            onPressed: _start,
          ),
        ],
      );

  Widget _scanStage(TwoFactorSetup pending) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSheetHeader(title: context.tr('Scan with your authenticator')),
          const SizedBox(height: AppSpacing.xs),
          ExampleSheetNote(
            context.tr(
                'Open Google Authenticator, 1Password, Authy or any TOTP app, scan the code, then enter the 6-digit code it shows.'),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Semantics(
              image: true,
              label: context.tr('Authenticator QR code'),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  // A QR code is artwork: it stays on white in both themes
                  // because a scanner needs the quiet zone at full luminance.
                  color: ExampleColors.lightSurface,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  boxShadow: ExampleShadows.ambientOf(context),
                ),
                child: QrImageView(data: pending.otpauthUri, size: 168),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          const ExampleAuthFieldLabel('Manual key'),
          const SizedBox(height: AppSpacing.xxs),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExampleMono(
              pending.secret,
              group: 4,
              size: 13,
              weight: FontWeight.w500,
              copyable: true,
              onCopied: () => _toast(context, 'Key copied.'),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleAuthField(
            controller: _code,
            label: context.tr('6-digit code'),
            hintText: '000000',
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (_code.text.length == 6 && !_busy) _confirm();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleSheetCta(
            label: context.tr('Turn on two-step verification'),
            busy: _busy,
            busyLabel: 'Turning on two-step verification',
            onPressed: _code.text.length < 6 ? null : _confirm,
          ),
        ],
      );

  Widget _codesStage(List<String> codes) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSheetHeader(title: context.tr('Save your recovery codes')),
          const SizedBox(height: AppSpacing.xs),
          ExampleSheetNote(
            context.tr(
                'Each code signs you in once if you lose your authenticator. Keep them somewhere safe; they are shown only now.'),
          ),
          const SizedBox(height: AppSpacing.md),
          DecoratedBox(
            decoration: BoxDecoration(
              color: ExampleSurface.of(context, 1),
              borderRadius: BorderRadius.circular(AppRadii.sm),
              border: ExampleBorders.subtleOf(context),
              boxShadow: ExampleShadows.ambientOf(context),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Semantics(
                container: true,
                label: context.tr('Recovery codes'),
                child: Wrap(
                  spacing: AppSpacing.lg,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final item in codes)
                      ExampleMono(item, size: 14, weight: FontWeight.w500),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleSheetCta(
            label: context.tr('I saved them'),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _SheetSecondary(
            icon: Icons.copy_rounded,
            label: context.tr('Copy codes'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: codes.join('\n')));
              if (mounted) _toast(context, 'Recovery codes copied.');
            },
          ),
        ],
      );
}

Future<void> _showDisableTwoFactor(BuildContext context, WidgetRef ref) =>
    showExampleSheet<void>(
      context,
      builder: (sheetContext) => _DisableTwoFactorSheet(controllerRef: ref),
    );

class _DisableTwoFactorSheet extends StatefulWidget {
  const _DisableTwoFactorSheet({required this.controllerRef});

  final WidgetRef controllerRef;

  @override
  State<_DisableTwoFactorSheet> createState() => _DisableTwoFactorSheetState();
}

class _DisableTwoFactorSheetState extends State<_DisableTwoFactorSheet> {
  final TextEditingController _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.controllerRef
          .read(authApiProvider)
          .disableTwoFactor(code: _code.text);
      widget.controllerRef.invalidate(accountSecurityProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('Two-step verification is off.'))),
      );
    } catch (error) {
      if (mounted) {
        _toast(context, friendlyErrorMessage(error));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSheetHeader(
              title: context.tr('Turn off two-step verification')),
          const SizedBox(height: AppSpacing.xs),
          ExampleSheetNote(
            context.tr(
                'Enter the current code from your authenticator app, or one of your recovery codes.'),
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleAuthField(
            controller: _code,
            label: context.tr('Authenticator or recovery code'),
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[],
            onSubmitted: (_) {
              if (!_busy) _submit();
            },
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleSheetCta(
            label: context.tr('Turn off'),
            tone: ExampleSheetCtaTone.danger,
            busy: _busy,
            busyLabel: 'Turning off two-step verification',
            onPressed: _submit,
          ),
        ],
      );
}

// ─── Change password ────────────────────────────────────────────────────────

Future<void> showChangePasswordSheet(
    BuildContext context, WidgetRef ref) async {
  final auth = await ref.read(authControllerProvider.future);
  if (!context.mounted) return;
  FocusScope.of(context).unfocus();
  TextInput.finishAutofillContext(shouldSave: false);
  final email = auth.session?.email.trim() ?? '';
  return showExampleSheet<void>(
    context,
    builder: (_) => _ChangePasswordSheet(controllerRef: ref, email: email),
  );
}

class _ChangePasswordSheet extends StatefulWidget {
  const _ChangePasswordSheet(
      {required this.controllerRef, required this.email});

  final WidgetRef controllerRef;
  final String email;

  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  late final _email = TextEditingController(text: widget.email);
  final TextEditingController _current = TextEditingController();
  final TextEditingController _next = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    _email.dispose();
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!passwordMeetsPolicy(_next.text)) {
      setState(() => _submitted = true);
      _toast(context, 'The new password is too weak. Check the requirements.');
      return;
    }
    if (_next.text != _confirm.text) {
      _toast(context, 'The new passwords do not match.');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await widget.controllerRef.read(authApiProvider).changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );
      widget.controllerRef.invalidate(accountSecurityProvider);
      if (!mounted) return;
      TextInput.finishAutofillContext(shouldSave: _email.text.contains('@'));
      navigator.pop();
      messenger.showSnackBar(
          SnackBar(content: Text(context.tr('Password changed.'))));
    } catch (error) {
      if (mounted) {
        _toast(context, friendlyErrorMessage(error));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExampleSheetHeader(title: context.tr('Change password')),
            const SizedBox(height: AppSpacing.xs),
            ExampleSheetNote(
              context.tr(
                  'Other devices are signed out after the change. This device stays signed in.'),
            ),
            const SizedBox(height: AppSpacing.md),
            ExampleAuthField(
              controller: _email,
              label: context.tr('Email'),
              readOnly: true,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ManagedPasswordField(
              controller: _current,
              label: context.tr('Current password'),
              hints: const [AutofillHints.password],
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ManagedPasswordField(
                  controller: _next,
                  label: context.tr('New password'),
                  hints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                PasswordStrengthChecklist(
                  password: _next.text,
                  showErrors: _submitted,
                ),
                const SizedBox(height: AppSpacing.sm),
                _ManagedPasswordField(
                  controller: _confirm,
                  label: context.tr('Confirm new password'),
                  hints: const [AutofillHints.newPassword],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) {
                    if (!_busy) _submit();
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ExampleSheetCta(
              label: context.tr('Change password'),
              busy: _busy,
              busyLabel: 'Changing your password',
              onPressed: _submit,
            ),
          ],
        ),
      );
}

// ─── Duress password ────────────────────────────────────────────────────────

Future<void> showDuressPasswordSheet(
  BuildContext context,
  WidgetRef ref, {
  required bool isSet,
}) =>
    showExampleSheet<void>(
      context,
      builder: (sheetContext) =>
          _DuressPasswordSheet(controllerRef: ref, isSet: isSet),
    );

class _DuressPasswordSheet extends StatefulWidget {
  const _DuressPasswordSheet({
    required this.controllerRef,
    required this.isSet,
  });

  final WidgetRef controllerRef;
  final bool isSet;

  @override
  State<_DuressPasswordSheet> createState() => _DuressPasswordSheetState();
}

class _DuressPasswordSheetState extends State<_DuressPasswordSheet> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _duress = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _busy = false;
  bool _submitted = false;

  @override
  void dispose() {
    _current.dispose();
    _duress.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final isSet = widget.isSet;
    if (!isSet && !passwordMeetsPolicy(_duress.text)) {
      setState(() => _submitted = true);
      _toast(
        context,
        'The duress password is too weak. Check the requirements.',
      );
      return;
    }
    if (!isSet && _duress.text == _current.text) {
      _toast(
        context,
        'The duress password must differ from your real password.',
      );
      return;
    }
    if (!isSet && _duress.text != _confirm.text) {
      _toast(context, 'The duress passwords do not match.');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final api = widget.controllerRef.read(authApiProvider);
      if (isSet) {
        await api.removeDuressPassword(currentPassword: _current.text);
      } else {
        await api.setDuressPassword(
          currentPassword: _current.text,
          duressPassword: _duress.text,
        );
      }
      widget.controllerRef.invalidate(accountSecurityProvider);
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isSet
                ? context.tr('Duress password removed.')
                : context.tr('Duress password set.'),
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _toast(context, friendlyErrorMessage(error));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSet = widget.isSet;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(
          title: isSet
              ? context.tr('Duress password')
              : context.tr('Set a duress password'),
        ),
        const SizedBox(height: AppSpacing.xs),
        ExampleSheetNote(
          context.tr(
              'If someone forces you to sign in, use your duress password instead. It looks like a sign-in but locks the account and signs out every device. Only support can unlock it, and not before two days have passed.'),
        ),
        const SizedBox(height: AppSpacing.sm),
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleInk.tint(context, ExampleColors.warning),
            borderRadius: BorderRadius.circular(AppRadii.sm),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: ExampleSheetNote(
              context.tr(
                  'Do not let a password manager save it. If yours offers to update your saved password, choose "not now": the duress password must never replace your real one.'),
              icon: Icons.warning_amber_rounded,
              tone: ExampleColors.warning,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _QuietPasswordField(
          controller: _current,
          label: context.tr('Current password'),
          autofocus: true,
          textInputAction: isSet ? TextInputAction.done : TextInputAction.next,
          onSubmitted: isSet
              ? (_) {
                  if (!_busy) _submit();
                }
              : null,
        ),
        if (!isSet) ...[
          const SizedBox(height: AppSpacing.sm),
          _QuietPasswordField(
            controller: _duress,
            label: context.tr('Duress password'),
            helper: 'Must differ from your real password',
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.sm),
          PasswordStrengthChecklist(
            password: _duress.text,
            showErrors: _submitted,
          ),
          const SizedBox(height: AppSpacing.sm),
          _QuietPasswordField(
            controller: _confirm,
            label: context.tr('Confirm duress password'),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) {
              if (!_busy) _submit();
            },
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        ExampleSheetCta(
          label: isSet
              ? context.tr('Remove duress password')
              : context.tr('Set duress password'),
          tone: isSet ? ExampleSheetCtaTone.danger : ExampleSheetCtaTone.primary,
          busy: _busy,
          busyLabel: isSet
              ? 'Removing your duress password'
              : 'Setting your duress password',
          onPressed: _submit,
        ),
      ],
    );
  }
}
