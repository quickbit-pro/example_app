import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_tilt.dart';

void main() {
  testWidgets('tilts while held and springs back on release', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 190,
            child: ExampleTiltCard(child: ColoredBox(color: Colors.blue)),
          ),
        ),
      ),
    );
    Matrix4 transformOf() =>
        tester.widget<Transform>(find.byType(Transform).first).transform;

    expect(transformOf(), Matrix4.identity()..setEntry(3, 2, .0016));

    final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(ExampleTiltCard)) + const Offset(20, 20));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 120));
    expect(transformOf(), isNot(Matrix4.identity()..setEntry(3, 2, .0016)));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(transformOf(), Matrix4.identity()..setEntry(3, 2, .0016));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'phone tilt becomes exactly flat within five seconds without more events',
      (tester) async {
    final sensor = StreamController<Offset>.broadcast(sync: true);
    await _mountMotionCard(tester, sensor.stream);
    sensor.add(Offset.zero);
    sensor.add(const Offset(14, 8));
    await tester.pump();
    final initialTilt = _rotation(tester);
    expect(initialTilt, greaterThan(0));

    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(seconds: 2));
    expect(_rotation(tester), greaterThan(0));
    expect(_rotation(tester), lessThan(initialTilt));
    // Five seconds includes the initial 120ms stability delay. No implicit
    // tracking or spring animation may leave a tail after this deadline.
    await tester.pump(const Duration(milliseconds: 2880));
    expect(_transform(tester), _flat);
    await tester.pump(const Duration(seconds: 1));
    expect(_transform(tester), _flat);
    await tester.pumpWidget(const SizedBox());
    await sensor.close();
  });

  testWidgets('stationary sensor noise cannot postpone the five-second return',
      (tester) async {
    final sensor = StreamController<Offset>.broadcast(sync: true);
    await _mountMotionCard(tester, sensor.stream);
    sensor.add(Offset.zero);
    sensor.add(const Offset(14, 8));
    await tester.pump();
    expect(_rotation(tester), greaterThan(0));

    for (var sample = 0; sample < 50; sample++) {
      final jitter = sample.isEven ? .12 : -.12;
      sensor.add(Offset(14 + jitter, 8 - jitter));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(_transform(tester), _flat);
    // Continued tiny changes after returning must not wake the card again.
    sensor.add(const Offset(14, 8));
    await tester.pump(const Duration(milliseconds: 100));
    expect(_transform(tester), _flat);
    await tester.pumpWidget(const SizedBox());
    await sensor.close();
  });

  testWidgets(
      'new phone movement follows the phone and restarts its return deadline',
      (tester) async {
    final sensor = StreamController<Offset>.broadcast(sync: true);
    await _mountMotionCard(tester, sensor.stream);
    sensor.add(Offset.zero);
    sensor.add(const Offset(14, 8));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 3880));
    sensor.add(const Offset(-14, -8));
    await tester.pump();
    expect(_transform(tester).entry(0, 2), lessThan(0));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 880));
    expect(_rotation(tester), greaterThan(0),
        reason: 'the previous movement deadline must be cancelled');
    await tester.pump(const Duration(seconds: 4));
    expect(_transform(tester), _flat);
    await tester.pumpWidget(const SizedBox());
    await sensor.close();
  });

  testWidgets(
      'small successive phone movements accumulate past the noise threshold',
      (tester) async {
    final sensor = StreamController<Offset>.broadcast(sync: true);
    await _mountMotionCard(tester, sensor.stream);
    sensor.add(Offset.zero);
    for (var sample = 1; sample <= 20; sample++) {
      sensor.add(Offset(sample * .1, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_rotation(tester), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await sensor.close();
  });
  testWidgets('releasing a centered hold gives control back to phone motion',
      (tester) async {
    final sensor = StreamController<Offset>.broadcast(sync: true);
    await _mountMotionCard(tester, sensor.stream);
    sensor.add(Offset.zero);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ExampleTiltCard)),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_transform(tester), _flat);
    sensor.add(const Offset(14, 8));
    await tester.pump();
    expect(_rotation(tester), greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    await sensor.close();
  });
}

Future<void> _mountMotionCard(WidgetTester tester, Stream<Offset> stream) =>
    tester.pumpWidget(MaterialApp(
      home: Center(
        child: SizedBox(
          width: 300,
          height: 190,
          child: ExampleTiltCard(
            debugMotionStream: stream,
            child: const ColoredBox(color: Colors.blue),
          ),
        ),
      ),
    ));

Matrix4 get _flat => Matrix4.identity()..setEntry(3, 2, .0016);

Matrix4 _transform(WidgetTester tester) =>
    tester.widget<Transform>(find.byType(Transform).first).transform;

double _rotation(WidgetTester tester) {
  final transform = _transform(tester);
  return transform.entry(0, 2).abs() + transform.entry(1, 2).abs();
}
