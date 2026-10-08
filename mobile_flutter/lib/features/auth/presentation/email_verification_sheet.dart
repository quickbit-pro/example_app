import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader, ExampleSheetNote, ExampleSheetCta;
import '../application/auth_providers.dart';
import 'example_auth_field.dart';
import 'forgot_password_sheet.dart'
    show ExampleCodeRecipient, ExampleSheetTextAction;

/// Enter the six-digit code from the registration email. Resolves to true
/// once the address is confirmed.
Future<bool> showEmailVerificationSheet(
  BuildContext context, {
  required String email,
  bool sendCodeFirst = false,
}) async {
  if (context.isExampleTheme) {
    return await showExampleSheet<bool>(
          context,
          builder: (_) => _EmailVerificationSheet(
            email: email,
            sendCodeFirst: sendCodeFirst,
          ),
        ) ??
        false;
  }
  final verified = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .93,
      child:
          _EmailVerificationSheet(email: email, sendCodeFirst: sendCodeFirst),
    ),
  );
  return verified ?? false;
}

class _EmailVerificationSheet extends ConsumerStatefulWidget {
  const _EmailVerificationSheet({
    required this.email,
    required this.sendCodeFirst,
  });

  final String email;
  final bool sendCodeFirst;

  @override
  ConsumerState<_EmailVerificationSheet> createState() =>
      _EmailVerificationSheetState();
}

class _EmailVerificationSheetState
    extends ConsumerState<_EmailVerificationSheet> {
  final _codeController = TextEditingController();
  bool _loading = false;
  bool _resent = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.sendCodeFirst) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _resend(silent: true));
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the six-digit code from the email.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(authApiProvider)
          .verifyEmail(email: widget.email, code: code);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend({bool silent = false}) async {
    setState(() {
      _loading = !silent;
      _error = null;
    });
    try {
      await ref.read(authApiProvider).resendEmailVerification(widget.email);
      if (!mounted) return;
      setState(() => _resent = !silent);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      context.isExampleTheme ? _buildExample(context) : _buildLegacy(context);

  Widget _buildExample(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSheetHeader(
            title: context.tr('Confirm your email'),
            actions: [
              IconButton(
                tooltip: context.tr('Close'),
                onPressed:
                    _loading ? null : () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ExampleSheetNote(
            context.tr(
                'Enter the six-digit code we sent to confirm your email address. The code is valid for 15 minutes.'),
          ),
          const SizedBox(height: AppSpacing.md),
          ExampleCodeRecipient(email: widget.email),
          const SizedBox(height: AppSpacing.md),
          ExampleAuthField(
            label: context.tr('Confirmation code'),
            controller: _codeController,
            hintText: '000000',
            prefixIcon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            textInputAction: TextInputAction.done,
            autofocus: true,
            enabled: !_loading,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmitted: (_) => _verify(),
          ),
          ExampleStateSwitch(
            alignment: Alignment.topCenter,
            child: _error == null
                ? const SizedBox(key: ValueKey('quiet'), width: double.infinity)
                : Padding(
                    key: ValueKey(_error),
                    padding: const EdgeInsets.only(top: AppSpacing.sm),
                    child: ExampleAuthAlert(message: _error!),
                  ),
          ),
          if (_resent) ...[
            const SizedBox(height: AppSpacing.sm),
            ExampleAuthAlert(
              message: context.tr(
                  'A new code is on its way. Check your spam folder if it does not arrive within a minute.'),
              icon: Icons.mark_email_read_outlined,
              tone: ExampleAuthAlertTone.info,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ExampleSheetCta(
            label: context.tr('Confirm email'),
            busy: _loading,
            onPressed: _loading ? null : _verify,
          ),
          const SizedBox(height: AppSpacing.xxs),
          ExampleSheetTextAction(
            icon: Icons.refresh_rounded,
            label: context.tr('Send a new code'),
            onTap: _loading ? null : () => _resend(),
          ),
        ],
      );

  Widget _buildLegacy(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(context.tr('Confirm your email')),
        actions: [
          IconButton(
            tooltip: context.tr('Close'),
            onPressed: _loading ? null : () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            context.tr(
                'We sent a six-digit code to {p0}. Enter it below to confirm the address. The code is valid for 15 minutes.',
                {'p0': widget.email}),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _codeController,
            enabled: !_loading,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            onSubmitted: (_) => _verify(),
            style: const TextStyle(fontSize: 22, letterSpacing: 6),
            decoration: InputDecoration(
              labelText: context.tr('Confirmation code'),
              prefixIcon: const Icon(Icons.pin_outlined, size: 18),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          if (_resent) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr(
                  'A new code is on its way. Check your spam folder if it does not arrive within a minute.'),
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 50,
            child: FilledButton(
              onPressed: _loading ? null : _verify,
              child: _loading
                  ? const SizedBox.square(
                      dimension: 20,
                      child: AppProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('Confirm email')),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(
            onPressed: _loading ? null : () => _resend(),
            child: Text(context.tr('Send a new code')),
          ),
        ],
      ),
    );
  }
}
