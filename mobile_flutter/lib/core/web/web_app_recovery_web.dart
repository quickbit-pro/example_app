import 'dart:js_interop';
import 'dart:ui' show FrameTiming;

import 'package:flutter/widgets.dart';

import 'repaint_app.dart';

@JS('exampleRecovery.onRedraw')
external void _onRedraw(JSFunction callback);

@JS('exampleRecovery.frameRendered')
external void _frameRendered();

class WebAppRecovery {
  static bool _waitingForFrame = false;

  static void initialize() {
    try {
      _onRedraw(_redraw.toJS);
    } catch (_) {
      // Embedders without the PWA recovery script still run normally.
    }
  }

  static void _redraw() {
    final binding = WidgetsBinding.instance;
    if (!_waitingForFrame) {
      _waitingForFrame = true;
      binding.addTimingsCallback(_didRender);
    }
    repaintApp(binding);
    // A pending pre-suspension vsync can make scheduleForcedFrame a no-op.
    // Warm-up frames use timers on web, so repaint without waiting for vsync.
    binding.scheduleWarmUpFrame();
  }

  static void _didRender(List<FrameTiming> timings) {
    if (timings.isEmpty) return;
    WidgetsBinding.instance.removeTimingsCallback(_didRender);
    _waitingForFrame = false;
    try {
      _frameRendered();
    } catch (_) {}
  }
}
