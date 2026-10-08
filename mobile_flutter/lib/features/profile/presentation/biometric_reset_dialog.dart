import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/app_localizations.dart';
import '../../auth/application/auth_providers.dart';

/// Forgetting a broken device credential must not require that credential.
/// Signing out forces normal password/2FA authentication before further use.
Future<void> confirmBiometricReset(
    BuildContext context, WidgetRef ref, String label) async {
  final controller = ref.read(authControllerProvider.notifier);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Turn off {p0}?', {'p0': label})),
      content: Text(context.tr(
        'This resets sign-in on this device and signs you out. Sign in with your password to continue. You can set up {p0} again afterwards.',
        {'p0': label},
      )),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(context.tr('Turn off and sign out')),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await controller.logout(clearBiometric: true);
}
