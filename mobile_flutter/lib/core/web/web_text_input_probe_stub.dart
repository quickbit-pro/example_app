import 'web_text_input_probe.dart';

WebTextInputProbe createProbe() => const _NoWebInput();

class _NoWebInput implements WebTextInputProbe {
  const _NoWebInput();
  @override
  bool get supported => false;
  @override
  bool get documentFocused => false;
  @override
  bool get editingElementFocused => false;
  @override
  void Function() listen(void Function() onResume) => () {};
}
