import 'dart:async';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader, ExampleSheetNote, ExampleSheetCta;
import '../../signup/presentation/password_strength_checklist.dart';
import '../application/auth_providers.dart';
import 'example_auth_field.dart';
import 'example_otp_field.dart';

/// Wall clock keeps resend deadlines correct while a PWA is suspended.
final passwordRecoveryClockProvider =
    Provider<DateTime Function()>((ref) => DateTime.now);

/// Successful reset credentials, held only in memory for the return to sign-in.
class PasswordResetResult {
  const PasswordResetResult({required this.email, required this.password});

  final String email;
  final String password;
}

/// Two-step password recovery: request a code by email, then set a new
/// password with it. Presented as a modal sheet like the other account flows.
Future<PasswordResetResult?> showForgotPasswordSheet(
  BuildContext context, {
  String initialEmail = '',
}) {
  FocusScope.of(context).unfocus();
  // Keep the old login credentials out of the recovery autofill context.
  TextInput.finishAutofillContext(shouldSave: false);
  if (context.isExampleTheme) {
    return showExampleSheet<PasswordResetResult>(
      context,
      builder: (_) => _ForgotPasswordSheet(initialEmail: initialEmail),
    );
  }
  return showModalBottomSheet<PasswordResetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .93,
      child: _ForgotPasswordSheet(initialEmail: initialEmail),
    ),
  );
}

class _ForgotPasswordSheet extends ConsumerStatefulWidget {
  const _ForgotPasswordSheet({required this.initialEmail});

  final String initialEmail;

  @override
  ConsumerState<_ForgotPasswordSheet> createState() =>
      _ForgotPasswordSheetState();
}

class _ForgotPasswordSheetState extends ConsumerState<_ForgotPasswordSheet> {
  late final _emailController =
      TextEditingController(text: widget.initialEmail);
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  bool _obscure = true;
  bool _submitted = false;
  String? _error;
  Timer? _cooldownTimer;
  DateTime? _resendAt;

  int get _remaining {
    final deadline = _resendAt;
    if (deadline == null) return 0;
    final now = ref.read(passwordRecoveryClockProvider)();
    return (deadline.difference(now).inMilliseconds / 1000)
        .ceil().clamp(0, 3600);
  }

  String get _resendLabel => _remaining > 0
      ? context.tr('Resend in {p0}s', {'p0': _remaining})
      : context.tr('Send a new code');

  void _startCooldown(int seconds) {
    _resendAt = ref.read(passwordRecoveryClockProvider)()
        .add(Duration(seconds: seconds));
    _cooldownTimer?.cancel();
    if (seconds <= 0) return;
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted || _remaining == 0) timer.cancel();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  String? _passwordProblem(String value) {
    if (value.length < 12 ||
        !value.contains(RegExp('[A-Z]')) ||
        !value.contains(RegExp('[a-z]')) ||
        !value.contains(RegExp('[0-9]'))) {
      return context.tr(
          'Use at least 12 characters with uppercase, lowercase, and a number.');
    }
    return null;
  }

  Future<void> _sendCode() async {
    if (_loading || _remaining > 0) return;
    final email = _emailController.text.trim();
    if (!email.contains('@')) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cooldown = await ref.read(authApiProvider).requestPasswordReset(email);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _startCooldown(cooldown);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reset() async {
    final email = _emailController.text.trim();
    final code = _codeController.text.trim();
    final password = _passwordController.text;
    if (code.length != 6) {
      setState(() => _error = 'Enter the six-digit code from the email.');
      return;
    }
    final problem = _passwordProblem(password);
    if (problem != null) {
      setState(() {
        _submitted = true;
        _error = problem;
      });
      return;
    }
    if (password != _confirmController.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).resetPassword(
            email: email,
            code: code,
            newPassword: password,
          );
      if (!mounted) return;
      TextInput.finishAutofillContext(shouldSave: true);
      Navigator.of(context)
          .pop(PasswordResetResult(email: email, password: password));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              context.tr('Password updated. Sign in with your new password.')),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AutofillGroup(
        onDisposeAction: AutofillContextAction.cancel,
        child: context.isExampleTheme
            ? _buildExample(context)
            : _buildLegacy(context),
      );

  Widget _buildExample(BuildContext context) => ExampleStateSwitch(
        alignment: Alignment.topCenter,
        child: KeyedSubtree(
          key: ValueKey(_codeSent ? 'reset' : 'request'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExampleSheetHeader(
                title: _codeSent
                    ? context.tr('Set a new password')
                    : context.tr('Reset your password'),
                actions: [
                  IconButton(
                    tooltip: context.tr('Close'),
                    onPressed:
                        _loading ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              ExampleSheetNote(
                _codeSent
                    ? context.tr(
                        'If this email is registered, check your inbox and spam for the latest code.')
                    : context.tr(
                        'Enter your email and we will send you a one-time code to choose a new password.'),
              ),
              const SizedBox(height: AppSpacing.md),
              ExampleAuthField(
                label: context.tr('Email'),
                controller: _emailController,
                readOnly: _codeSent,
                hintText: context.tr('name@example.com'),
                prefixIcon: Icons.mail_outline,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email
                ],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enabled: !_loading,
                onSubmitted: _codeSent ? null : (_) => _sendCode(),
              ),
              if (_codeSent) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  context.tr('Six-digit code'),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: ExampleInk.secondary(context),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 7),
                AutofillGroup(
                  child: ExampleOtpField(
                    controller: _codeController,
                    label: context.tr('Six-digit code'),
                    enabled: !_loading,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                ExampleAuthField(
                  label: context.tr('New password'),
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  enabled: !_loading,
                  suffix: ExamplePasswordToggle(
                    obscured: _obscure,
                    onTap: () => setState(() => _obscure = !_obscure),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.sm),
                PasswordStrengthChecklist(
                  password: _passwordController.text,
                  showErrors: _submitted,
                  dark: Theme.of(context).brightness == Brightness.dark,
                ),
                const SizedBox(height: AppSpacing.sm),
                ExampleAuthField(
                  label: context.tr('Confirm new password'),
                  controller: _confirmController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: _obscure,
                  autofillHints: const [AutofillHints.newPassword],
                  enabled: !_loading,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _reset(),
                ),
              ],
              ExampleStateSwitch(
                alignment: Alignment.topCenter,
                child: _error == null
                    ? const SizedBox(
                        key: ValueKey('quiet'), width: double.infinity)
                    : Padding(
                        key: ValueKey(_error),
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: ExampleAuthAlert(message: _error!),
                      ),
              ),
              const SizedBox(height: AppSpacing.md),
              ExampleSheetCta(
                label: _codeSent
                    ? context.tr('Reset password')
                    : context.tr('Send code'),
                busy: _loading,
                onPressed: _loading ? null : (_codeSent ? _reset : _sendCode),
              ),
              if (_codeSent) ...[
                const SizedBox(height: AppSpacing.xxs),
                ExampleSheetTextAction(
                  icon: Icons.refresh_rounded,
                  label: _resendLabel,
                  onTap: _loading || _remaining > 0 ? null : _sendCode,
                ),
              ],
            ],
          ),
        ),
      );

  Widget _buildLegacy(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(_codeSent
            ? context.tr('Set a new password')
            : context.tr('Reset your password')),
        actions: [
          IconButton(
            tooltip: context.tr('Close'),
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _codeSent
                  ? context.tr(
                      'If {p0} is registered, check your inbox and spam for the latest code.',
                      {
                          'p0': _emailController.text.trim()
                        })
                  : context.tr(
                      'Enter your email and we will send you a one-time code to choose a new password.'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _emailController,
              readOnly: _codeSent,
              enabled: !_loading,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [
                AutofillHints.username,
                AutofillHints.email
              ],
              autocorrect: false,
              onSubmitted: _codeSent ? null : (_) => _sendCode(),
              decoration: InputDecoration(
                labelText: context.tr('Email'),
                prefixIcon: const Icon(Icons.mail_outline, size: 18),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.md),
              Text(context.tr('Six-digit code')),
              const SizedBox(height: 7),
              AutofillGroup(
                child: ExampleOtpField(
                  controller: _codeController,
                  enabled: !_loading,
                  label: context.tr('Six-digit code'),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _passwordController,
                enabled: !_loading,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: context.tr('New password'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? context.tr('Show password')
                        : context.tr('Hide password'),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              PasswordStrengthChecklist(
                password: _passwordController.text,
                showErrors: _submitted,
                dark: Theme.of(context).brightness == Brightness.dark,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _confirmController,
                enabled: !_loading,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _reset(),
                decoration: InputDecoration(
                  labelText: context.tr('Confirm new password'),
                  prefixIcon: const Icon(Icons.lock_outline, size: 18),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              height: 50,
              child: FilledButton(
                onPressed: _loading ? null : (_codeSent ? _reset : _sendCode),
                child: _loading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: AppProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_codeSent
                        ? context.tr('Reset password')
                        : context.tr('Send code')),
              ),
            ),
            if (_codeSent) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: _loading || _remaining > 0 ? null : _sendCode,
                child: Text(_resendLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ExampleCodeRecipient extends StatelessWidget {
  const ExampleCodeRecipient({
    required this.email,
    this.caption = 'Code sent to this address',
    super.key,
  });

  final String email;

  /// Line under the address. Defaults to the phrase both sheets use.
  final String caption;

  @override
  Widget build(BuildContext context) => ExampleListGroup(
        dividers: false,
        children: [
          ExampleRow(
            title: email,
            subtitle: caption,
            // The token name, not a hex: ExampleIconTile resolves it through
            // ExampleInk for the active theme (iris at night, its daylight
            // partner on paper).
            leading: ExampleIconTile(
              icon: Icons.mail_outline,
              color: context.brandDesign.color(
                  Theme.of(context).brightness, 'accent',
                  fallback: ExampleColors.iris),
            ),
          ),
        ],
      );
}

class ExampleSheetTextAction extends StatelessWidget {
  const ExampleSheetTextAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;

  /// Null disables the action, exactly as on a `TextButton`.
  final VoidCallback? onTap;

  /// Tap target floor, in logical pixels.
  static const double minHeight = 44;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: double.infinity,
          minHeight: minHeight,
        ),
        child: ExamplePressable(
          enabled: onTap != null,
          child: TextButton.icon(
            onPressed: onTap,
            style: TextButton.styleFrom(
              foregroundColor: ExamplePalette.of(context).accent,
              disabledForegroundColor: ExampleInk.secondary(context),
            ),
            icon: Icon(icon, size: 18),
            label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
      );
}
