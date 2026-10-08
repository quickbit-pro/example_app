/// Non-web platforms use `local_auth`; this stub keeps the API compiling.
class WebBiometricGate {
  static Future<bool> available() async => false;
  static bool hasCredential() => false;
  static Future<bool> register(String userName) async => false;
  static Future<String> verify() async => 'none';
  static void cancel() {}
  static void clear() {}
}
