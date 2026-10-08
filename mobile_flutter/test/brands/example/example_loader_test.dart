import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_mark.dart';
import 'package:mobile_flutter/shared/widgets/brand_loader.dart';

void main() {
  testWidgets('loading uses reusable customer artwork', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ExampleLoader(size: 42, semanticsLabel: 'Loading accounts'),
    )));
    final loader = tester.widget<BrandLoader>(find.byType(BrandLoader));
    expect(loader.size, 42);
    expect(loader.semanticsLabel, 'Loading accounts');
    expect(loader.spin, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('route transition holds its customer artwork still', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: ExampleLoader.transition(color: Colors.indigo),
    )));
    final loader = tester.widget<BrandLoader>(find.byType(BrandLoader));
    expect(loader.spin, isFalse);
    expect(loader.color, Colors.indigo);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
