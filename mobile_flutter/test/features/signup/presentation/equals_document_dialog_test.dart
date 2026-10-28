import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/signup/presentation/equals_document_dialog.dart';

void main() {
  Uint8List bytes(String text) => Uint8List.fromList(utf8.encode(text));

  test(
      'HTML review keeps full legal text and links without executable or hidden styling',
      () {
    final content = equalsDocumentHtml(bytes(
        '<main><script>bad()</script><style>p{display:none}</style>'
        '<p style="display:none" onclick="bad()">${'First legal clause. ' * 10}</p>'
        '<h2>Last clause</h2><a href="https://equalsmoney.com/complaints">Complaints</a></main>'));
    expect(content, contains('Last clause'));
    expect(content, contains('https://equalsmoney.com/complaints'));
    expect(content, isNot(contains('bad()')));
    expect(content, isNot(contains('display:none')));
    expect(() => equalsDocumentHtml(bytes('<main>Loading...</main>')),
        throwsFormatException);
    expect(
        () => equalsDocumentHtml(
            bytes('<main><iframe src="/legal"></iframe></main>')),
        throwsFormatException);
  });

  for (final failure in ['offline', 'changed', 'empty']) {
    testWidgets('$failure document cannot unlock confirmation', (tester) async {
      await tester.pumpWidget(ProviderScope(
          overrides: [
            equalsDocumentProvider.overrideWith((ref, kind) async {
              if (failure == 'offline') throw Exception('offline');
              return EqualsDocument(
                  url: failure == 'changed'
                      ? 'https://example.test/new'
                      : 'https://example.test/current',
                  type: 'text/html',
                  bytes: bytes(failure == 'empty'
                      ? ''
                      : '<main>${'Legal text ' * 30}</main>'));
            }),
          ],
          child: const MaterialApp(
              home: Scaffold(
                  body: EqualsDocumentDialog(
                      kind: 'privacy',
                      title: 'Privacy',
                      url: 'https://example.test/current')))));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(
                  find.byKey(const Key('equals-document-confirm')))
              .onPressed,
          isNull);
      expect(find.text('Try again'), findsOneWidget);
    });
  }
}
