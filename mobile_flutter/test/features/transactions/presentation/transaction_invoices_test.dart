import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/documents/document_api.dart';
import 'package:mobile_flutter/features/transactions/data/transaction_documents_api.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_invoices.dart';

const _invoice = TransactionDocument(
    id: 'attachment',
    documentId: 'document',
    filename: 'invoice.pdf',
    contentType: 'application/pdf',
    byteLength: 12);

class _Picker extends InvoicePicker {
  final calls = <bool>[];
  InvoiceFile? file =
      InvoiceFile(Uint8List.fromList('%PDF-1.7'.codeUnits), 'invoice.pdf');
  @override
  Future<InvoiceFile?> pick({required bool camera}) async {
    calls.add(camera);
    return file;
  }
}

class _Documents extends DocumentApi {
  _Documents() : super(Dio());
  int uploads = 0;
  bool fail = false;
  Completer<String>? pending;
  @override
  Future<String> upload(
      {required Uint8List bytes, required String filename}) async {
    uploads++;
    if (fail) throw Exception('storage failure');
    return pending == null ? 'document' : pending!.future;
  }
}

class _Attachments extends TransactionDocumentsApi {
  _Attachments() : super(Dio());
  final rows = <String, List<TransactionDocument>>{};
  final attached = <String>[];
  bool fail = false;
  @override
  Future<List<TransactionDocument>> list(String transactionId,
          {CancelToken? cancelToken}) async =>
      rows[transactionId] ?? [];
  @override
  Future<void> attach(String transactionId, String documentId) async {
    if (fail) throw Exception('attachment failure');
    attached.add(transactionId);
    rows[transactionId] = [_invoice];
  }

  @override
  Future<void> remove(String id) async {
    rows.clear();
  }
}

Future<ProviderContainer> _mount(WidgetTester tester, _Picker picker,
    _Documents documents, _Attachments attachments) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final container = ProviderContainer(overrides: [
    invoicePickerProvider.overrideWithValue(picker),
    documentApiProvider.overrideWithValue(documents),
    transactionDocumentsApiProvider.overrideWithValue(attachments)
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child:
                      TransactionInvoices(transactionId: 'transaction-1'))))));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
      'failed attachment retains the original and retries without picking or uploading again',
      (tester) async {
    final picker = _Picker();
    final documents = _Documents();
    final attachments = _Attachments()..fail = true;
    await _mount(tester, picker, documents, attachments);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(documents.uploads, 1);
    attachments.fail = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(documents.uploads, 1);
    expect(picker.calls, [false]);
    expect(attachments.attached, ['transaction-1']);
    expect(find.text('Invoice saved.'), findsOneWidget);
  });

  testWidgets(
      'file and camera upload attach, persist on reload and detach on phone',
      (tester) async {
    final picker = _Picker();
    final documents = _Documents();
    final attachments = _Attachments();
    final container = await _mount(tester, picker, documents, attachments);
    expect(find.text('No invoices attached yet.'), findsOneWidget);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(picker.calls, [false]);
    expect(documents.uploads, 1);
    expect(attachments.attached, ['transaction-1']);
    expect(find.text('invoice.pdf'), findsOneWidget);
    container.invalidate(transactionDocumentsProvider('transaction-1'));
    await tester.pumpAndSettle();
    expect(find.text('invoice.pdf'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove attachment'));
    await tester.pumpAndSettle();
    expect(find.text('No invoices attached yet.'), findsOneWidget);
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(picker.calls, [false, true]);
    expect(find.text('invoice.pdf'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'cancelled and oversized selections never upload; failed storage never attaches',
      (tester) async {
    final picker = _Picker()..file = null;
    final documents = _Documents();
    final attachments = _Attachments();
    await _mount(tester, picker, documents, attachments);
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(documents.uploads, 0);
    picker.file = InvoiceFile(Uint8List(10 * 1024 * 1024 + 1), 'huge.pdf');
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(documents.uploads, 0);
    expect(find.text('Choose an invoice up to 10 MB.'), findsOneWidget);
    picker.file =
        InvoiceFile(Uint8List.fromList('%PDF-1.7'.codeUnits), 'invoice.pdf');
    documents.fail = true;
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(attachments.attached, isEmpty);
    expect(find.text('Could not save the invoice. Please try again.'),
        findsOneWidget);
    documents.fail = false;
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(attachments.attached, ['transaction-1']);
  });
  testWidgets('account change during upload never attaches to the new session',
      (tester) async {
    final picker = _Picker();
    final documents = _Documents()..pending = Completer<String>();
    final attachments = _Attachments();
    final container = await _mount(tester, picker, documents, attachments);
    await tester.tap(find.text('Choose file'));
    await tester.pump();
    await tester.pump();
    expect(documents.uploads, 1);
    container.read(authSessionGenerationProvider.notifier).state++;
    documents.pending!.complete('old-owner-document');
    await tester.pumpAndSettle();
    expect(attachments.attached, isEmpty);
    expect(find.text('Invoice saved.'), findsNothing);
  });
}
