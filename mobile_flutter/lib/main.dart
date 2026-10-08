import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/l10n/locale_preference_provider.dart';
import 'core/theme/theme_preference_provider.dart';
import 'flavors.dart';
import 'core/web/web_app_recovery.dart';
import 'features/notifications/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  WebAppRecovery.initialize();
  // Notifications must not hold up the first visible frame. Activation also
  // awaits initialization before using Firebase.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(PushNotificationService.initializeFirebase());
  });
  // Match the first frame to the customer's chosen Example palette.
  final themeOverrides = AppBranding.fromEnvironment().isExample
      ? await bootThemeModeOverrides()
      : const <Override>[];
  final localeOverrides = await bootLocaleOverrides();
  runApp(ProviderScope(
      overrides: [...themeOverrides, ...localeOverrides],
      child: const MobileApp()));
}
