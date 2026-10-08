import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('exampleSafeArea.insets')
external JSString _insets();

/// Bridges to the `exampleSafeArea` helper in the web page, which measures
/// `env(safe-area-inset-*)` on a probe element. Returns
/// "top,right,bottom,left" in CSS pixels, which are Flutter's logical pixels.
class WebSafeArea {
  static EdgeInsets insets() {
    try {
      final parts = _insets().toDart.split(',');
      if (parts.length != 4) return EdgeInsets.zero;
      final values = parts.map((part) => double.tryParse(part) ?? 0).toList();
      return EdgeInsets.fromLTRB(values[3], values[0], values[1], values[2]);
    } catch (_) {
      return EdgeInsets.zero;
    }
  }
}
