/// Native platforms install from the store; this stub keeps the API compiling.
class WebInstallPrompt {
  static bool available() => false;
  static bool installed() => false;
  static String platform() => 'other';
  static void onChange(void Function(bool available) callback) {}
  static Future<String> prompt() async => 'unavailable';
}
