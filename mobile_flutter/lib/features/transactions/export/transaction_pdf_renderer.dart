import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'transaction_pdf.dart';
import 'transaction_pdf_shaped.dart';

Future<Uint8List> buildTransactionPdf(
  TransactionPdfSnapshot snapshot, {
  AssetBundle? assetBundle,
}) async {
  final bundle = assetBundle ?? rootBundle;
  if (snapshot.rtl || snapshot.localizations.locale.languageCode == 'hi') {
    return buildShapedTransactionPdf(snapshot, bundle);
  }
  final fallback = <pw.Font>[];
  final locale = snapshot.localizations.locale.languageCode;
  final font = switch (locale) {
    'ar' => 'notosansarabic',
    'ja' => 'notosansjp',
    'ko' => 'notosanskr',
    _ => null,
  };
  if (font != null) {
    fallback.add(pw.Font.ttf(await bundle.load('assets/fonts/pdf/$font.ttf')));
  }
  final regularFont = await bundle.load('assets/fonts/Geist-Regular.ttf');
  final boldFont = await bundle.load('assets/fonts/Geist-Bold.ttf');
  final document = pw.Document(
    title: '${snapshot.appName} - ${snapshot.title}',
    author: snapshot.appName,
    creator: snapshot.appName,
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regularFont),
      bold: pw.Font.ttf(boldFont),
      fontFallback: fallback,
    ),
  );
  PdfColor color(String role, int fallback) => PdfColor.fromInt(snapshot.design
      .color(Brightness.light, role, fallback: Color(fallback))
      .toARGB32());
  final ink = color('ink', 0xff202037);
  final muted = color('textSecondary', 0xff66667a);
  final rule = color('borderSubtle', 0xffdddded);
  final tint = color('surfaceSubtle', 0xfff2f0fb);

  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    textDirection: snapshot.rtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
    margin: const pw.EdgeInsets.all(36),
    maxPages: snapshot.rows.length + 4,
    header: (context) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 16),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(snapshot.appName,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, color: ink, fontSize: 13)),
          pw.Text(snapshot.title,
              style: pw.TextStyle(color: muted, fontSize: 10)),
        ],
      ),
    ),
    footer: (context) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12),
      child: pw.Column(children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
                snapshot.tr('Generated {p0}',
                    {'p0': transactionPdfDateLabel(snapshot.generatedAt)}),
                style: pw.TextStyle(fontSize: 8, color: muted)),
            pw.Text('${context.pageNumber} / ${context.pagesCount}',
                style: pw.TextStyle(fontSize: 8, color: muted)),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Text(snapshot.tr('Not for official use'),
            style: pw.TextStyle(fontSize: 8, color: muted)),
      ]),
    ),
    build: (context) => [
      pw.Text(snapshot.title,
          style: pw.TextStyle(
              fontSize: 22, color: ink, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 8),
      if (!snapshot.receipt)
        pw.Text(
            snapshot.tr(
                snapshot.rows.length == 1
                    ? '{p0} transaction'
                    : '{p0} transactions',
                {'p0': snapshot.rows.length}),
            style: pw.TextStyle(fontSize: 10, color: muted)),
      if (snapshot.filters.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        pw.Text(snapshot.filters.join('  |  '),
            style: pw.TextStyle(fontSize: 10, color: muted)),
      ],
      pw.SizedBox(height: 18),
      if (snapshot.receipt)
        ..._receiptWidgets(snapshot, snapshot.rows.single, ink, muted, rule)
      else if (snapshot.rows.isEmpty)
        pw.Text(snapshot.tr('No transactions match these filters.'))
      else
        pw.TableHelper.fromTextArray(
          headers: ['Booked', 'Transaction', 'Amount', 'Status']
              .map(snapshot.tr)
              .toList(),
          data: [
            for (final row in snapshot.rows)
              [
                row.booked,
                [
                  row.title,
                  row.type,
                  ...row.subtitle
                      .split('\n')
                      .map((line) => line.trim())
                      .where(
                        (line) =>
                            line.isNotEmpty &&
                            line != row.type.trim() &&
                            line != row.status.trim() &&
                            line != row.title.trim(),
                      )
                      .toSet(),
                  if (row.identity != null) row.identity,
                  snapshot.tr('Ref: {p0}', {'p0': row.reference})
                ].join('\n'),
                [
                  row.amount,
                  if (row.settlementAmount != null)
                    '${row.settlementAmount}\n${snapshot.tr('settled')}'
                ].join('\n'),
                row.status,
              ],
          ],
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(3.2),
            2: pw.FlexColumnWidth(1.7),
            3: pw.FlexColumnWidth(1.1),
          },
          cellPadding:
              const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 10),
          cellStyle: pw.TextStyle(fontSize: 9, color: ink, lineSpacing: 3),
          headerStyle: pw.TextStyle(
              fontSize: 9, color: ink, fontWeight: pw.FontWeight.bold),
          headerAlignment: pw.Alignment.centerLeft,
          cellAlignments: const {2: pw.Alignment.topRight},
          headerAlignments: const {2: pw.Alignment.centerRight},
          headerDecoration: pw.BoxDecoration(color: tint),
          border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: rule, width: .5)),
        ),
    ],
  ));
  return document.save();
}

List<pw.Widget> _receiptWidgets(
  TransactionPdfSnapshot snapshot,
  TransactionPdfRow row,
  PdfColor ink,
  PdfColor muted,
  PdfColor rule,
) {
  final details = <(String, String)>[
    ('Status', row.status),
    ('Type', row.type),
    ('Reference', row.reference),
    ('Booked', row.booked),
    if (row.identity != null) ('Account / card', row.identity!),
    if (row.subtitle.trim().isNotEmpty && row.subtitle != row.status)
      ('Details', row.subtitle),
  ];
  return [
    pw.Text(row.amount,
        style: pw.TextStyle(
            fontSize: 24, color: ink, fontWeight: pw.FontWeight.bold)),
    if (row.settlementAmount != null) ...[
      pw.SizedBox(height: 6),
      pw.Text(snapshot.tr('{p0} settled', {'p0': row.settlementAmount}),
          style: const pw.TextStyle(fontSize: 11)),
    ],
    pw.SizedBox(height: 12),
    pw.Text(row.title, style: const pw.TextStyle(fontSize: 14)),
    pw.SizedBox(height: 22),
    for (final (label, value) in details)
      pw.Container(
        padding: const pw.EdgeInsets.symmetric(vertical: 11),
        decoration: pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(color: rule, width: .5))),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
                width: 105,
                child: pw.Text(snapshot.tr(label),
                    style: pw.TextStyle(fontSize: 10, color: muted))),
            pw.Expanded(
                child: pw.Text(value,
                    style: pw.TextStyle(fontSize: 10, color: ink))),
          ],
        ),
      ),
  ];
}
