// The browser's safe-area insets (iPhone notch and home indicator); zero
// outside the web build, where the platform reports them itself.
export 'web_safe_area_stub.dart'
    if (dart.library.js_interop) 'web_safe_area_web.dart';
