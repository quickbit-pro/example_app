import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example_colors.dart';
import '../../../core/branding/app_design.dart';
import '../../auth/application/biometric_providers.dart';
import '../../auth/data/biometric_authenticator.dart';
import '../data/peer_transfers_api.dart';

/// Step-up before money leaves the account: the device biometric prompt
/// where one is available (fingerprint, face, or the browser passkey the
/// customer enrolled in Settings), otherwise the account password, which the
/// backend verifies. Returns null when the customer backs out.
Future<PeerConfirmation?> confirmPeerAction(
  BuildContext context,
  WidgetRef ref, {
  required String reason,
}) async {
  final authenticator = ref.read(biometricAuthenticatorProvider);
  var useBiometric = false;
  if (kIsWeb) {
    try {
      final enrollment = await ref.read(biometricEnrollmentProvider.future);
      useBiometric = enrollment.enabled && enrollment.hasToken;
    } catch (_) {
      useBiometric = false;
    }
  } else {
    try {
      useBiometric = (await authenticator.capability()).available;
    } catch (_) {
      useBiometric = false;
    }
  }
  if (!context.mounted) return null;

  if (useBiometric) {
    final result = await authenticator.authenticate(reason: reason);
    if (!context.mounted) return null;
    switch (result) {
      case BiometricAuthResult.success:
        return const PeerConfirmation.biometric();
      case BiometricAuthResult.cancelled:
        return null;
      case BiometricAuthResult.lockedOut:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                  'Biometrics are locked. Unlock your device, or confirm with your password.'),
            ),
          ),
        );
        break;
      case BiometricAuthResult.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(context.tr('Identity confirmation was not completed.')),
          ),
        );
        break;
    }
  }

  final password = await _askPassword(context, reason: reason);
  if (password == null || password.isEmpty) return null;
  return PeerConfirmation.password(password);
}

Future<String?> _askPassword(BuildContext context, {required String reason}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: ExamplePalette.of(context).navigation,
      title: Text(context.tr('Confirm with your password')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            reason,
            style: TextStyle(
              fontSize: 12.5 * context.brandDesign.typographyScale,
              height: 1.4,
              color: ExamplePalette.of(context).textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            autofillHints: const [AutofillHints.password],
            decoration:
                InputDecoration(labelText: context.tr('Account password')),
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: Text(context.tr('Confirm')),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
