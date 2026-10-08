import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:web/web.dart' as web;

/// Phone attitude in degrees, with gravity as a fallback for devices that
/// supply acceleration but no usable orientation events.
Stream<Offset> deviceTiltStream() {
  late StreamController<Offset> controller;
  JSFunction? listener;
  JSFunction? gravityListener;
  DateTime? lastOrientationAt;
  controller = StreamController<Offset>.broadcast(
    onListen: () {
      lastOrientationAt = null;
      listener = ((web.Event event) {
        // Read the fields dynamically: some browsers hand back null until
        // the sensor warms up, and the typed view would drop the event.
        final gamma = event.getProperty<JSAny?>('gamma'.toJS);
        final beta = event.getProperty<JSAny?>('beta'.toJS);
        if (gamma == null || beta == null) return;
        if (!gamma.isA<JSNumber>() || !beta.isA<JSNumber>()) return;
        final attitude = Offset(
          (gamma as JSNumber).toDartDouble,
          (beta as JSNumber).toDartDouble,
        );
        if (!attitude.dx.isFinite || !attitude.dy.isFinite) return;
        lastOrientationAt = DateTime.now();
        _permissionGranted = true;
        controller.add(attitude);
      }).toJS;
      gravityListener = ((web.Event event) {
        // Prefer the fused orientation sensor while it is delivering readings.
        if (lastOrientationAt != null &&
            DateTime.now().difference(lastOrientationAt!) <
                const Duration(seconds: 1)) {
          return;
        }
        final gravity = event.getProperty<JSObject?>(
          'accelerationIncludingGravity'.toJS,
        );
        if (gravity == null) return;
        double? component(String name) {
          final value = gravity.getProperty<JSAny?>(name.toJS);
          if (value == null || !value.isA<JSNumber>()) return null;
          final number = (value as JSNumber).toDartDouble;
          return number.isFinite ? number : null;
        }

        final x = component('x');
        final y = component('y');
        final z = component('z');
        if (x == null || y == null || z == null) return;
        final magnitude = math.sqrt(x * x + y * y + z * z);
        if (magnitude < .1) return;
        controller.add(Offset(
          math.atan2(-x, z) * 180 / math.pi,
          math.asin((y / magnitude).clamp(-1.0, 1.0)) * 180 / math.pi,
        ));
      }).toJS;
      web.window.addEventListener('deviceorientation', listener);
      web.window.addEventListener('devicemotion', gravityListener);
    },
    onCancel: () {
      if (listener != null) {
        web.window.removeEventListener('deviceorientation', listener);
      }
      if (gravityListener != null) {
        web.window.removeEventListener('devicemotion', gravityListener);
      }
    },
  );
  return controller.stream;
}

JSObject? get _orientationEvent =>
    web.window.getProperty<JSAny?>('DeviceOrientationEvent'.toJS) as JSObject?;

// Permission belongs to the page, not an individual card preview.
bool _permissionGranted = false;
Future<bool>? _permissionRequest;

/// iOS Safari only hands out orientation events after an explicit,
/// user-gesture-triggered permission request; other browsers have none.
bool get motionNeedsPermission =>
    !_permissionGranted &&
    (_orientationEvent?.has('requestPermission') ?? false);

Future<bool> requestMotionPermission() {
  if (_permissionGranted) return Future.value(true);
  return _permissionRequest ??= _requestMotionPermission().whenComplete(() {
    _permissionRequest = null;
  });
}

Future<bool> _requestMotionPermission() async {
  final target = _orientationEvent;
  if (target == null || !target.has('requestPermission')) return true;
  try {
    final result = await (target.callMethod<JSAny?>('requestPermission'.toJS)
            as JSPromise<JSString>)
        .toDart;
    _permissionGranted = result.toDart == 'granted';
    return _permissionGranted;
  } catch (_) {
    return false;
  }
}
