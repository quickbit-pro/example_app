import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf.dart';

void main() {
  testWidgets('exports all app languages without changing identifiers or money',
      (tester) async {
    await tester.runAsync(() async {
      final output = Platform.environment['EXAMPLE_PDF_TEST_OUTPUT'];
      for (final language in appLanguages) {
        final messages = (jsonDecode(File('assets/l10n/${language.code}.json')
                .readAsStringSync()) as Map<String, dynamic>)
            .cast<String, String>();
        final l10n = AppLocalizations(Locale(language.code), messages);
        final transaction = LedgerTransaction.fromJson({
          'id': 'fixture-123',
          'title': 'Merchant Example',
          'type': 'card_payment',
          'currency': 'EUR',
          'amount': -12.34,
          'bookedAt': '2026-09-09T10:00:00Z',
          'status': 'completed',
        });
        for (final receipt in [false, true]) {
          final snapshot = TransactionPdfSnapshot(
            transactions: [transaction],
            localizations: l10n,
            receipt: receipt,
            identityFor: (_) => 'BE15915963165430',
            generatedAt: DateTime.utc(2026, 9, 9, 12),
          );
          expect(
              snapshot.title,
              messages[
                  receipt ? 'Transaction receipt' : 'Transaction activity']);
          expect(snapshot.rows.single.reference, 'fixture-123');
          expect(snapshot.rows.single.identity, 'BE15915963165430');
          expect(snapshot.rows.single.amount, contains('12.34'));
          expect(snapshot.rows.single.status, messages['Completed']);
          final bytes = await buildTransactionPdf(snapshot);
          expect(latin1.decode(bytes), startsWith('%PDF-'));
          if (output != null) {
            await Directory(output).create(recursive: true);
            await File(
                    '$output/${language.code}-${receipt ? 'receipt' : 'activity'}.pdf')
                .writeAsBytes(bytes);
          }
        }
      }
    });
  }, timeout: const Timeout(Duration(minutes: 3)));
}
