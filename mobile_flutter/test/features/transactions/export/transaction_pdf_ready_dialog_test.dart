import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf_delivery.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf_ready_dialog.dart';

class _Document implements TransactionPdfDelivery {
  @override
  bool canShare = true;
  bool openResult = false;
  int downloads = 0;
  int opens = 0;
  int shares = 0;
  Completer<bool>? pendingShare;

  @override
  bool open() {
    opens++;
    return openResult;
  }

  @override
  void download() {
    downloads++;
  }

  @override
  Future<bool> share() {
    shares++;
    return pendingShare!.future;
  }

  @override
  void dispose() {}
}

void main() {
  Future<void> show(WidgetTester tester, _Document document) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: Builder(
          builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        TransactionPdfReadyDialog(document: document)),
                child: const Text('Export'),
              )),
    )));
    await tester.tap(find.text('Export'));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'does not deliver until tapped and retains blocked download alternatives',
      (tester) async {
    final document = _Document()..canShare = false;
    await show(tester, document);
    expect(document.downloads + document.opens + document.shares, 0);
    expect(find.text('Share PDF'), findsNothing);
    await tester.tap(find.text('Open PDF'));
    await tester.pump();
    expect(document.opens, 1);
    expect(find.textContaining('was blocked'), findsOneWidget);
    await tester.tap(find.text('Download PDF'));
    await tester.pump();
    expect(document.downloads, 1);
    expect(
        find.textContaining('Check your browser downloads.'), findsOneWidget);
    expect(find.text('PDF ready'), findsOneWidget);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('PDF ready'), findsNothing);
  });

  testWidgets('cancelled or failed share leaves PDF available for retry',
      (tester) async {
    final document = _Document()..pendingShare = Completer<bool>();
    await show(tester, document);
    await tester.tap(find.text('Share PDF'));
    expect(document.shares, 1); // Invoked inside the gesture, before pumping.
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Open PDF'))
            .onPressed,
        isNull);
    document.pendingShare!.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('Sharing cancelled.'), findsOneWidget);
    document.pendingShare = Completer<bool>();
    await tester.tap(find.text('Share PDF'));
    document.pendingShare!.completeError(StateError('share denied'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not share'), findsOneWidget);
    document.openResult = true;
    await tester.tap(find.text('Open PDF'));
    await tester.pump();
    expect(find.text('Use the PDF viewer’s menu to print.'), findsOneWidget);
  });
}
