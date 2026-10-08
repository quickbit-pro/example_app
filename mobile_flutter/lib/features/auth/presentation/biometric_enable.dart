import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_providers.dart';
import '../application/biometric_providers.dart';
import '../data/biometric_authenticator.dart';

/// Confirms with the device authenticator and stores the current session for
/// biometric sign-in. Shared by Settings and the post-login nudge.
Future<bool> enableBiometricSignIn(
  BuildContext context,
  WidgetRef ref, {
  required String label,
}) async {
  final result = await ref.read(biometricAuthenticatorProvider).authenticate(
        reason: 'Confirm to enable $label sign-in',
      );
  if (result != BiometricAuthResult.success) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('{p0} was not enabled.', {'p0': label}))),
      );
    }
    return false;
  }
  await ref
      .read(authControllerProvider.notifier)
      .enableBiometricForCurrentSession();
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.tr('{p0} sign-in is on.', {'p0': label}))),
    );
  }
  return true;
}
