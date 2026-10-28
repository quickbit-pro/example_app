import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/shared/widgets/payee_name_check.dart';

void main() {
  testWidgets(
      'close match shows returned name and requires an explicit unchecked acknowledgement',
      (tester) async {
    bool accepted = false;
    final check = {
      'status': 'warning',
      'outcome': 'close_match',
      'title': 'Close name match',
      'actualName': 'Jane Doe',
      'requiresAcknowledgement': true,
      'canProceed': true
    };
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StatefulBuilder(
                builder: (context, setState) => Column(children: [
                      PayeeNameCheck(
                          result: check,
                          acknowledged: accepted,
                          onChanged: (value) =>
                              setState(() => accepted = value)),
                      FilledButton(
                          onPressed: accepted ? () {} : null,
                          child: const Text('Confirm payee')),
                    ])))));
    expect(find.text('Account holder name: Jane Doe'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(accepted, isTrue);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });

  test('API parsing preserves name-check results rather than discarding them',
      () {
    final response = PayoutOtpInitiation.fromJson({
      'success': true,
      'verificationToken': 'test',
      'verificationResult': {
        'outcome': 'no_match',
        'requiresAcknowledgement': true
      }
    });
    expect(response.verificationResult?['outcome'], 'no_match');
    expect(PayeeNameCheck.needsAcknowledgement(response.verificationResult!),
        isTrue);
    expect(
        PayeeNameCheck.needsAcknowledgement(
            {'status': 'matched', 'outcome': 'match'}),
        isFalse);
    expect(PayeeNameCheck.needsAcknowledgement({'status': 'warning'}), isTrue);
  });
}
