import 'web_text_input_probe_stub.dart'
    if (dart.library.js_interop) 'web_text_input_probe_web.dart' as platform;

abstract interface class WebTextInputProbe {
  bool get supported;
  bool get documentFocused;
  bool get editingElementFocused;
  void Function() listen(void Function() onResume);
}

WebTextInputProbe createWebTextInputProbe() => platform.createProbe();
