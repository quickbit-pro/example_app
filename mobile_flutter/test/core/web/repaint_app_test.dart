import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/web/repaint_app.dart';

class _Painter extends CustomPainter {
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.green);
  }

  @override
  bool shouldRepaint(_Painter oldDelegate) => false;
}

void main() {
  testWidgets('Resume repaints retained child boundaries without rebuilding',
      (tester) async {
    final painter = _Painter();
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
          child: RepaintBoundary(
        child: CustomPaint(painter: painter, size: const Size(100, 100)),
      )),
    ));
    final before = painter.paints;
    // The old root-only repaint keeps this child's display list unchanged.
    for (final view in tester.binding.renderViews) {
      view.markNeedsPaint();
    }
    await tester.pump();
    expect(painter.paints, before);
    repaintApp(tester.binding);
    tester.binding.scheduleForcedFrame();
    await tester.pump();
    expect(painter.paints, greaterThan(before));
  });
}
