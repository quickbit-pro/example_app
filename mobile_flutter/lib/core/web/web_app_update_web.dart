import 'dart:js_interop';

@JS('exampleUpdate.ready')
external JSBoolean _ready();

@JS('exampleUpdate.onChange')
external void _onChange(JSFunction callback);

@JS('exampleUpdate.reload')
external void _reload();

/// Bridges to the `exampleUpdate` helper in `web/index.html`.
class WebAppUpdate {
  static bool ready() {
    try {
      return _ready().toDart;
    } catch (_) {
      return false;
    }
  }

  static void onChange(void Function(bool ready) callback) {
    try {
      _onChange(((JSBoolean value) => callback(value.toDart)).toJS);
    } catch (_) {}
  }

  static void reload() {
    try {
      _reload();
    } catch (_) {}
  }
}
