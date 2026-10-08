import 'dart:js_interop';

@JS('exampleBiometrics.available')
external JSPromise<JSBoolean> _available();

@JS('exampleBiometrics.hasCredential')
external JSBoolean _hasCredential();

@JS('exampleBiometrics.register')
external JSPromise<JSBoolean> _register(JSString userName);

@JS('exampleBiometrics.verify')
external JSPromise<JSString> _verify();

@JS('exampleBiometrics.cancel')
external void _cancel();

@JS('exampleBiometrics.clear')
external void _clear();

/// Bridges to the `exampleBiometrics` helper in `web/index.html`, which wraps
/// WebAuthn platform authenticators (Face ID, Touch ID, Android biometrics).
class WebBiometricGate {
  static Future<bool> available() async {
    try {
      return (await _available().toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static bool hasCredential() {
    try {
      return _hasCredential().toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> register(String userName) async {
    try {
      return (await _register(userName.toJS).toDart).toDart;
    } catch (_) {
      return false;
    }
  }

  static Future<String> verify() async {
    try {
      return (await _verify().toDart).toDart;
    } catch (_) {
      return 'failed';
    }
  }

  static void cancel() {
    try {
      _cancel();
    } catch (_) {}
  }

  static void clear() {
    try {
      _clear();
    } catch (_) {}
  }
}
