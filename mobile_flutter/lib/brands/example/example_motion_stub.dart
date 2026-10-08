import 'dart:async';

import 'package:flutter/painting.dart';

/// Device-orientation tilt is a browser feature; native builds get no stream.
Stream<Offset> deviceTiltStream() => const Stream<Offset>.empty();

Future<bool> requestMotionPermission() async => false;

bool get motionNeedsPermission => false;
