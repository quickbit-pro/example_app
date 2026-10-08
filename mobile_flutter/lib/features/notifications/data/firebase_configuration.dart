import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Customer builds supply options from their brand configuration. An
/// unconfigured sample never initializes the upstream Firebase project.
abstract final class FirebaseConfiguration {
  static const _projectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
    defaultValue: '',
  );
  static const _senderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
    defaultValue: '',
  );
  static const _apiKey = String.fromEnvironment(
    'FIREBASE_API_KEY',
    defaultValue: '',
  );
  static const _androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
    defaultValue: _apiKey,
  );
  static const _androidAppId = String.fromEnvironment(
    'FIREBASE_ANDROID_APP_ID',
    defaultValue: '',
  );
  static const _iosAppId = String.fromEnvironment(
    'FIREBASE_IOS_APP_ID',
    defaultValue: '',
  );
  static const _iosApiKey = String.fromEnvironment(
    'FIREBASE_IOS_API_KEY',
    defaultValue: _apiKey,
  );
  static const _iosBundleId = String.fromEnvironment(
    'FIREBASE_IOS_BUNDLE_ID',
    defaultValue: '',
  );

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool get isConfigured {
    if (!isSupported || _projectId.isEmpty || _senderId.isEmpty) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android
        ? _androidAppId.isNotEmpty && _androidApiKey.isNotEmpty
        : _iosAppId.isNotEmpty && _iosApiKey.isNotEmpty;
  }

  static FirebaseOptions get current {
    if (!isConfigured) {
      throw StateError('Firebase push configuration is incomplete.');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const FirebaseOptions(
        apiKey: _androidApiKey,
        appId: _androidAppId,
        messagingSenderId: _senderId,
        projectId: _projectId,
      );
    }
    return const FirebaseOptions(
      apiKey: _iosApiKey,
      appId: _iosAppId,
      messagingSenderId: _senderId,
      projectId: _projectId,
      iosBundleId: _iosBundleId,
    );
  }
}
