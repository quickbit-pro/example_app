import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../data/biometric_authenticator.dart';
import '../data/biometric_credential_storage.dart';

final biometricAuthenticatorProvider = Provider<BiometricAuthenticator>((ref) {
  return BiometricAuthenticator.forApp(
    ref.watch(appConfigProvider).branding.appName,
  );
});

final biometricStorageProvider = Provider<BiometricCredentialStorage>((ref) {
  return BiometricCredentialStorage();
});

/// Device capability — refreshes lazily; UI reads it via `.future` to gate
/// the unlock button.
final biometricCapabilityProvider = FutureProvider<BiometricCapability>((ref) {
  return ref.watch(biometricAuthenticatorProvider).capability();
});

/// Whether the user has previously opted in AND there's a stored token to
/// rehydrate. This is the source of truth for "show the biometric unlock CTA
/// on the login screen".
final biometricEnrollmentProvider = FutureProvider<BiometricEnrollment>((ref) {
  final storage = ref.watch(biometricStorageProvider);
  return Future.wait([
    storage.isEnabled(),
    storage.hasStoredToken(),
    storage.readEmail(),
    storage.readUserName(),
    storage.readRefreshToken(),
  ]).then((values) {
    return BiometricEnrollment(
      enabled: values[0] as bool,
      hasToken: values[1] as bool,
      email: (values[2] as String?) ?? '',
      userName: (values[3] as String?) ?? '',
      refreshToken: (values[4] as String?) ?? '',
    );
  });
});

class BiometricEnrollment {
  const BiometricEnrollment({
    required this.enabled,
    required this.hasToken,
    required this.email,
    required this.userName,
    required this.refreshToken,
  });

  final bool enabled;
  final bool hasToken;
  final String email;
  final String userName;
  final String refreshToken;

  /// Both flags must be true before we offer biometric unlock.
  bool get canUnlock => enabled && hasToken;
}
