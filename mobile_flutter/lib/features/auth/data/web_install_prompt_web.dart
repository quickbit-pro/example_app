import 'dart:js_interop';

@JS('exampleInstall.available')
external JSBoolean _available();

@JS('exampleInstall.installed')
external JSBoolean _installed();

@JS('exampleInstall.platform')
external JSString _platform();

@JS('exampleInstall.onChange')
external void _onChange(JSFunction callback);

@JS('exampleInstall.prompt')
external JSPromise<JSString> _prompt();

/// Bridges to the `exampleInstall` helper in `web/index.html`, which holds the
/// browser's deferred `beforeinstallprompt` event.
class WebInstallPrompt {
  static bool available() {
    try {
      return _available().toDart;
    } catch (_) {
      return false;
    }
  }

  static bool installed() {
    try {
      return _installed().toDart;
    } catch (_) {
      return false;
    }
  }

  /// `android`, `ios` or `other`, from the browser user agent.
  static String platform() {
    try {
      return _platform().toDart;
    } catch (_) {
      return 'other';
    }
  }

  static void onChange(void Function(bool available) callback) {
    try {
      _onChange(((JSBoolean value) => callback(value.toDart)).toJS);
    } catch (_) {}
  }

  /// Returns `accepted`, `dismissed` or `unavailable`.
  static Future<String> prompt() async {
    try {
      return (await _prompt().toDart).toDart;
    } catch (_) {
      return 'unavailable';
    }
  }
}
