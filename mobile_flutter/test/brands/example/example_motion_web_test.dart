@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_motion_web.dart';
import 'package:mobile_flutter/brands/example/example_tilt.dart';
import 'package:web/web.dart' as web;

void orientation(double? gamma, double? beta) {
  final event = web.Event('deviceorientation');
  event.setProperty('gamma'.toJS, gamma?.toJS);
  event.setProperty('beta'.toJS, beta?.toJS);
  web.window.dispatchEvent(event);
}

void gravity(double? x, double? y, double? z) {
  final event = web.Event('devicemotion');
  final acceleration = JSObject();
  acceleration.setProperty('x'.toJS, x?.toJS);
  acceleration.setProperty('y'.toJS, y?.toJS);
  acceleration.setProperty('z'.toJS, z?.toJS);
  event.setProperty('accelerationIncludingGravity'.toJS, acceleration);
  web.window.dispatchEvent(event);
}

Widget previews(
        {bool enabled = true, bool motion = true, VoidCallback? onTap}) =>
    MaterialApp(
      home: Row(
        children: List.generate(
          2,
          (index) => SizedBox(
            width: 300,
            height: 190,
            child: ExampleTiltCard(
              key: ValueKey(index),
              enabled: enabled,
              motion: motion,
              child: GestureDetector(
                onTap: onTap,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

Matrix4 transformOf(WidgetTester tester, int index) => tester
    .widget<Transform>(find
        .descendant(
          of: find.byKey(ValueKey(index)),
          matching: find.byType(Transform),
        )
        .first)
    .transform;

Matrix4 get flat => Matrix4.identity()..setEntry(3, 2, .0016);

void main() {
  testWidgets('completed tap requests once and enables every preview',
      (tester) async {
    final original = web.window.getProperty<JSAny?>(
      'DeviceOrientationEvent'.toJS,
    );
    final constructor = JSObject();
    var calls = 0;
    late JSFunction resolvePermission;
    constructor.setProperty(
      'requestPermission'.toJS,
      (() {
        calls++;
        return JSPromise<JSString>(((JSFunction resolve, JSFunction reject) {
          resolvePermission = resolve;
        }).toJS);
      }).toJS,
    );
    web.window.setProperty('DeviceOrientationEvent'.toJS, constructor);
    addTearDown(() {
      web.window.setProperty('DeviceOrientationEvent'.toJS, original);
    });

    var cardTaps = 0;
    await tester.pumpWidget(previews(onTap: () => cardTaps++));
    expect(calls, 0);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey(0))),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(calls, 0, reason: 'Touch-down has no browser activation yet');
    await gesture.up();
    expect(cardTaps, 1, reason: 'Card navigation must still receive the tap');
    expect(calls, 1);
    await tester.tap(find.byKey(const ValueKey(1)));
    expect(calls, 1, reason: 'Concurrent requests share the pending prompt');
    resolvePermission.callAsFunction(null, 'denied'.toJS);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(motionNeedsPermission, isTrue);

    await tester.tap(find.byKey(const ValueKey(0)));
    expect(calls, 2, reason: 'A denied request can be retried by a tap');
    resolvePermission.callAsFunction(null, 'granted'.toJS);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(motionNeedsPermission, isFalse);
    orientation(0, 30);
    await tester.pump();
    orientation(15, 40);
    await tester.pump(const Duration(milliseconds: 50));
    expect(transformOf(tester, 0), isNot(flat));
    expect(transformOf(tester, 1), isNot(flat));

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(previews());
    orientation(0, 30);
    await tester.pump();
    orientation(-15, 20);
    await tester.pump(const Duration(milliseconds: 50));
    expect(transformOf(tester, 0), isNot(flat));
    await tester.tap(find.byKey(const ValueKey(0)));
    expect(calls, 2, reason: 'Remounting does not request permission again');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Android gravity fallback moves cards without a tap',
      (tester) async {
    await tester.pumpWidget(previews());
    orientation(null, null);
    gravity(null, 0, 9.8);
    gravity(0, 0, 0);
    gravity(double.nan, 0, 9.8);
    await tester.pumpAndSettle();
    expect(transformOf(tester, 0), flat);
    gravity(0, 0, 9.8);
    await tester.pump();
    gravity(-3, 2, 9);
    await tester.pump(const Duration(milliseconds: 50));
    expect(transformOf(tester, 0), isNot(flat));
    expect(transformOf(tester, 1), isNot(flat));
    await tester.pumpWidget(previews(motion: false));
    await tester.pumpAndSettle();
    expect(transformOf(tester, 0), flat);
    gravity(-5, 3, 8);
    await tester.pumpAndSettle();
    expect(transformOf(tester, 0), flat);
    await tester.pumpWidget(const SizedBox());
  });

  test('valid orientation wins over gravity; invalid readings are ignored',
      () async {
    final readings = <Offset>[];
    final subscription = deviceTiltStream().listen(readings.add);
    orientation(null, 0);
    orientation(double.nan, 0);
    orientation(0, double.infinity);
    orientation(12, 34);
    gravity(-3, 2, 9);
    await Future<void>.delayed(Duration.zero);
    expect(readings, [const Offset(12, 34)]);
    await subscription.cancel();
    orientation(20, 40);
    gravity(-5, 3, 8);
    await Future<void>.delayed(Duration.zero);
    expect(readings, hasLength(1));
  });
}
