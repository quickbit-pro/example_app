// Browser passkey gate used instead of `local_auth` on the web build.
export 'web_biometric_gate_stub.dart'
    if (dart.library.js_interop) 'web_biometric_gate_web.dart';
