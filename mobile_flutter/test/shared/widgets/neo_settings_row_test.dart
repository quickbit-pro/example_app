import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/shared.dart';

void main() {
  testWidgets('aligns its icon with a title and subtitle block',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: NeoGroupedCard(
                children: [
                  NeoSettingsRow(
                    icon: Icons.dark_mode_outlined,
                    title: 'Appearance',
                    subtitle: 'Dark',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final icon = tester.getRect(find.byIcon(Icons.dark_mode_outlined));
    final title = tester.getRect(find.text('Appearance'));
    final subtitle = tester.getRect(find.text('Dark'));
    final textBlockCenter = (title.top + subtitle.bottom) / 2;

    expect((icon.center.dy - textBlockCenter).abs(), lessThan(2));
    expect(icon.left, greaterThanOrEqualTo(16));
  });
}
