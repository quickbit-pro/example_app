import 'dart:convert';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:web/web.dart' as web;

typedef PreviewMessageHandler = void Function(Map<String, dynamic> message);

@JS('Object.is')
external bool _sameObject(JSAny? first, JSAny? second);

/// The preview lives in an about:srcdoc iframe and its GoRouter destinations
/// are local presentation state. Null disables Flutter's browser-history
/// integration entirely; routerNeglect alone would still call replaceState.
void configurePreviewPlatform() {
  ui_web.urlStrategy = null;
}

void Function() listenForPreviewMessages(PreviewMessageHandler handler) {
  final callback = ((web.Event raw) {
    final event = raw as web.MessageEvent;
    // The single-file guide may have an opaque file:/sandbox origin, so check
    // the actual parent window rather than trusting a caller-supplied origin.
    if (!_sameObject(event.source, web.window.parent)) return;
    try {
      final value = event.data.dartify();
      if (value is! Map || value['type'] != 'customer-brand-update') return;
      handler(jsonDecode(jsonEncode(value)) as Map<String, dynamic>);
    } catch (error) {
      sendPreviewMessage({
        'type': 'customer-preview-error',
        'message': 'Could not read preview configuration: $error',
      });
    }
  }).toJS;
  web.window.addEventListener('message', callback);
  return () => web.window.removeEventListener('message', callback);
}

void sendPreviewMessage(Map<String, dynamic> message) {
  web.window.parent?.postMessage(message.jsify(), '*'.toJS);
}
