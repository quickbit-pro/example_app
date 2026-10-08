import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mobile_flutter/app.dart';

void main() {
  testWidgets('renders mobile app login entrypoint', (tester) async {
    SharedPreferences.setMockInitialValues({});
    // The session store reads the platform keystore; give the test an
    // in-memory one so the restore resolves under the fake clock.
    FlutterSecureStorage.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: MobileApp()));

    // First frame for the synchronous shell + theme setup.
    await tester.pump();
    // Pump past the 350ms post-frame timer used by the login screen to
    // probe biometric enrollment so it doesn't leak into the next test.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    // Clear the startup splash: its intro plus fade runs about 1.5 s on
    // native, and the login screen only becomes visible after that.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 400));

    // The redesigned login screen renders a primary "Sign in" CTA on the
    // login card and a "Sign in" headline. We only assert at least one
    // is present so the test isn't coupled to layout duplication.
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Create account'), findsOneWidget);
  });
}
