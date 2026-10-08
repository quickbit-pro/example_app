import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/notifications/data/firebase_configuration.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('unconfigured sample does not initialize Firebase on $platform', () {
      debugDefaultTargetPlatformOverride = platform;
      expect(FirebaseConfiguration.isConfigured, isFalse);
      expect(() => FirebaseConfiguration.current, throwsStateError);
    });
  }
}
