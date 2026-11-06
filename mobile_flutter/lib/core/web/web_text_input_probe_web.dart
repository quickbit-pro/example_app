import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'web_text_input_probe.dart';

WebTextInputProbe createProbe() => const _BrowserInput();

class _BrowserInput implements WebTextInputProbe {
  const _BrowserInput();
  @override
  bool get supported {
    final agent = web.window.navigator.userAgent;
    return agent.contains('Chrome/') &&
        !RegExp('Android|Mobile|iPhone|iPad', caseSensitive: false)
            .hasMatch(agent);
  }

  @override
  bool get documentFocused =>
      web.document.visibilityState == 'visible' && web.document.hasFocus();
  @override
  bool get editingElementFocused {
    web.Element? element = web.document.activeElement;
    while (element?.shadowRoot?.activeElement != null) {
      element = element!.shadowRoot!.activeElement;
    }
    if (element == null) return false;
    // Respect native controls and embedded payment/verification frames.
    // A foreign input is not a missing Flutter editor.
    if (const {'IFRAME', 'BUTTON', 'SELECT'}.contains(element.tagName)) {
      return true;
    }
    final belongsToFlutter = element.classList.contains('flt-text-editing') ||
        element.closest('flt-semantics') != null;
    if (!belongsToFlutter) {
      return element.tagName == 'INPUT' || element.tagName == 'TEXTAREA';
    }
    if (element.isA<web.HTMLInputElement>()) {
      final input = element as web.HTMLInputElement;
      return !input.disabled && !input.readOnly;
    }
    if (element.isA<web.HTMLTextAreaElement>()) {
      final input = element as web.HTMLTextAreaElement;
      return !input.disabled && !input.readOnly;
    }
    return false;
  }

  @override
  void Function() listen(void Function() onResume) {
    final listener = ((web.Event _) {
      // Visibility can be reported before document.hasFocus becomes true.
      // Check focus in Flutter's next frame, after the browser finishes resuming.
      onResume();
    }).toJS;
    web.window.addEventListener('focus', listener);
    web.document.addEventListener('visibilitychange', listener);
    web.window.addEventListener('pageshow', listener);
    return () {
      web.window.removeEventListener('focus', listener);
      web.document.removeEventListener('visibilitychange', listener);
      web.window.removeEventListener('pageshow', listener);
    };
  }
}
