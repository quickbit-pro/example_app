// Detects a newly deployed web build; no-op on native platforms.
export 'web_app_update_stub.dart'
    if (dart.library.js_interop) 'web_app_update_web.dart';
