import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import '../../../lib/core/compliance/equals_compliance_screen.dart';

Map<String, dynamic> snapshot() => {
      'profile': {
        'businessType': 'PRIVATE_COMPANY',
        'website': 'https://example.com'
      },
      'data': {
        'isDropshipping': false,
        'hasTrustOwnership': false,
        'noProhibitedRegionalExposure': true,
        'sourceOfFundsRoute': 'AUDITED',
        'noWebsiteEvidenceRoute': 'BANK_STATEMENTS',
        'answers': {
          'OWNERSHIP': {
            'text': 'Alex controls the company.',
            'documentIds': [42]
          }
        }
      },
      'documents': [
        {
          'complianceDocumentId': 42,
          'purpose': 'PROOF_OF_OWNERSHIP_STRUCTURE',
          'fileName': 'ownership.pdf'
        }
      ]
    };
Map<String, dynamic> requirements({List<String> errors = const []}) => {
      'policyVersion': 'test-policy-2',
      'errors': errors,
      'requiresDirector': true,
      'requirements': [
        {
          'id': 'OWNERSHIP',
          'label': 'Describe ownership and control',
          'documentPurpose': 'PROOF_OF_OWNERSHIP_STRUCTURE'
        }
      ]
    };
void main() {
  testWidgets(
      'interrupted upload retains answers and retry saves only confirmed evidence IDs',
      (tester) async {
    var attempts = 0;
    Map<String, dynamic>? saved;
    final state = snapshot();
    state['documents'] = <dynamic>[];
    state['data']['answers']['OWNERSHIP']['documentIds'] = <int>[];
    await tester.pumpWidget(MaterialApp(
        home: EqualsComplianceScreen(
            load: () async => state,
            pickFile: () async => PlatformFile(
                name: 'ownership.pdf', size: 1, bytes: Uint8List.fromList([1])),
            upload: (purpose, file) async {
              attempts++;
              if (attempts == 1)
                throw StateError('Connection interrupted. Retry the upload.');
              return 99;
            },
            call: (operation, body) async {
              if (operation == 'requirements') return requirements();
              saved = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
              return {'success': true};
            })));
    await tester.pumpAndSettle();
    final button = find.descendant(
        of: find.byKey(const ValueKey('OWNERSHIP')),
        matching: find.text('Upload supporting evidence'));
    await tester.scrollUntilVisible(button, 300,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saved, isNull);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(
        saved!['answers']['OWNERSHIP']['text'], 'Alex controls the company.');
    expect(saved!['answers']['OWNERSHIP']['documentIds'], [99]);
  });

  testWidgets(
      'resumes answers and evidence and saves current policy before continuing',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: EqualsComplianceScreen(
            load: () async => snapshot(),
            upload: (purpose, file) async => 99,
            call: (operation, data) async {
              calls.add(operation);
              if (operation == 'requirements') return requirements();
              expect(data['policyVersion'], 'test-policy-2');
              expect(data['answers']['OWNERSHIP']['documentIds'], [42]);
              expect(data['answers']['OWNERSHIP']['text'],
                  'Alex controls the company.');
              return {'success': true};
            })));
    await tester.pumpAndSettle();
    expect(find.text('Policy: test-policy-2'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Save checklist and continue'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save checklist and continue'));
    await tester.pumpAndSettle();
    expect(calls, ['requirements', 'draft', 'requirements', '']);
  });
  testWidgets('eligibility errors prevent complete save and remain visible',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(MaterialApp(
        home: EqualsComplianceScreen(
            load: () async => snapshot(),
            upload: (purpose, file) async => 99,
            call: (operation, body) async {
              calls.add(operation);
              return operation == 'requirements'
                  ? requirements(
                      errors: ['Equals Money prohibits this region.'])
                  : {'success': true};
            })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.text('Save checklist and continue'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save checklist and continue'));
    await tester.pumpAndSettle();
    expect(calls, isNot(contains('')));
    expect(find.text('Save checklist and continue'), findsOneWidget);
  });
  testWidgets('failed save keeps entered responses available for retry',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: EqualsComplianceScreen(
            load: () async => snapshot(),
            upload: (purpose, file) async => 99,
            call: (operation, body) async {
              if (operation == 'requirements') return requirements();
              throw DioException(
                  requestOptions: RequestOptions(path: '/compliance'),
                  response: Response(
                      requestOptions: RequestOptions(path: '/compliance'),
                      statusCode: 400,
                      data: {
                        'errors': ['Upload three months of statements.']
                      }));
            })));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Save progress'), 350,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Save progress'));
    await tester.pumpAndSettle();
    expect(find.text('Alex controls the company.'), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Upload three months of statements.'), -350,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Upload three months of statements.'), findsOneWidget);
  });
}
