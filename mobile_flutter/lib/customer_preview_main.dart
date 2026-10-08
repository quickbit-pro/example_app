import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'customer_preview/customer_preview_app.dart';
import 'customer_preview/preview_bridge.dart';

/// Deliberately separate from the shipped application entrypoint. This build
/// runs production presentation widgets with local fixtures, without starting
/// Firebase, restoring sessions, registering a service worker, or opening APIs.
void main() {
  configurePreviewPlatform();
  WidgetsFlutterBinding.ensureInitialized();
  // An isolated in-memory store also makes login/profile preferences safe when
  // the guide is hosted alongside an existing installed application.
  // This dedicated preview is a fixture host, just like the widget-test host.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues({});
  runApp(const CustomerPreviewHost());
}
