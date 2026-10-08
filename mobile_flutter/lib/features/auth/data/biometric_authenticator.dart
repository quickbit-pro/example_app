import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../../flavors.dart';
import 'web_biometric_gate.dart';

/// Thin wrapper around `local_auth` that surfaces both the device capability
/// (so we can show "Set up biometrics" vs "Use Face ID") and a single
/// `authenticate` entry point that returns a typed result.
class BiometricAuthenticator {
  BiometricAuthenticator([LocalAuthentication? auth])
      : this.forApp(AppBranding.fromEnvironment().appName, auth);

  BiometricAuthenticator.forApp(this.appName, [LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();

  final String appName;

  final LocalAuthentication _auth;

  Future<BiometricCapability> capability() async {
    if (kIsWeb) {
      // Installed web app: a platform passkey stands in for local_auth.
      final available = await WebBiometricGate.available();
      return BiometricCapability(
        available: available,
        types: available ? const [BiometricType.strong] : const [],
        reason: available
            ? BiometricUnavailableReason.none
            : BiometricUnavailableReason.unsupportedDevice,
      );
    }
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        return const BiometricCapability(
          available: false,
          types: [],
          reason: BiometricUnavailableReason.unsupportedDevice,
        );
      }
      final canCheck = await _auth.canCheckBiometrics;
      final types = await _auth.getAvailableBiometrics();
      if (!canCheck || types.isEmpty) {
        return BiometricCapability(
          available: false,
          types: types,
          reason: BiometricUnavailableReason.notEnrolled,
        );
      }

      return BiometricCapability(
        available: true,
        types: types,
        reason: BiometricUnavailableReason.none,
      );
    } on PlatformException {
      return const BiometricCapability(
        available: false,
        types: [],
        reason: BiometricUnavailableReason.platformError,
      );
    }
  }

  Future<void> cancel() async {
    try {
      if (kIsWeb) {
        WebBiometricGate.cancel();
      } else {
        await _auth.stopAuthentication();
      }
    } catch (_) {
      // The controller still ignores late results if the platform cannot stop.
    }
  }

  Future<BiometricAuthResult> authenticate({
    required String reason,
  }) async {
    if (kIsWeb) {
      if (!WebBiometricGate.hasCredential()) {
        // Creating the passkey itself runs the device biometric prompt.
        final created = await WebBiometricGate.register(appName);
        return created
            ? BiometricAuthResult.success
            : BiometricAuthResult.cancelled;
      }
      return switch (await WebBiometricGate.verify()) {
        'success' => BiometricAuthResult.success,
        'cancelled' => BiometricAuthResult.cancelled,
        _ => BiometricAuthResult.failed,
      };
    }
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
      return ok ? BiometricAuthResult.success : BiometricAuthResult.cancelled;
    } on PlatformException catch (error) {
      // `notAvailable`, `notEnrolled`, `lockedOut`, etc. — we surface a single
      // failure for the UI; the upper layer can re-query capability if needed.
      if (error.code == 'LockedOut' || error.code == 'PermanentlyLockedOut') {
        return BiometricAuthResult.lockedOut;
      }
      return BiometricAuthResult.failed;
    }
  }
}

extension BiometricAuthenticatorReset on BiometricAuthenticator {
  /// Drops the browser passkey when biometrics are switched off.
  void forget() {
    if (kIsWeb) WebBiometricGate.clear();
  }
}

class BiometricCapability {
  const BiometricCapability({
    required this.available,
    required this.types,
    required this.reason,
  });

  final bool available;
  final List<BiometricType> types;
  final BiometricUnavailableReason reason;

  bool get hasFaceId => types.contains(BiometricType.face);
  bool get hasFingerprint =>
      types.contains(BiometricType.fingerprint) ||
      types.contains(BiometricType.strong) ||
      types.contains(BiometricType.weak);

  /// Best-effort label for the primary biometric on this device.
  String describe() {
    if (hasFaceId) return 'Face ID';
    if (hasFingerprint) return 'Fingerprint';
    return 'Biometrics';
  }
}

enum BiometricUnavailableReason {
  none,
  unsupportedDevice,
  notEnrolled,
  platformError,
}

enum BiometricAuthResult {
  success,
  cancelled,
  failed,
  lockedOut,
}
