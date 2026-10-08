import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/widgets/additional_information_dialog.dart';

void main() {
  testWidgets('submits text without disposing dialog dependencies early',
      (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showAdditionalInformationDialog(
                  context,
                  title: 'Describe the source of funds',
                  supportingText: 'Equals Money requires more information.',
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Consulting income');
    await tester.tap(find.text('Submit'));
    await tester.pumpAndSettle();

    expect(result, 'Consulting income');
    expect(tester.takeException(), isNull);
  });
}
