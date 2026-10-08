import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'transaction_pdf.dart';

/// Use Flutter's text shaper for Arabic and Hindi pages so joined letters,
/// matras and bidirectional text match the app on every platform.
/// This path is loaded with the deferred PDF renderer, never during startup.
Future<Uint8List> buildShapedTransactionPdf(
  TransactionPdfSnapshot snapshot,
  AssetBundle bundle,
) async {
  final font = snapshot.rtl ? 'notosansarabic' : 'notosansdevanagari';
  final family = 'PdfShaped$font';
  await ui.loadFontFromList(
    (await bundle.load('assets/fonts/pdf/$font.ttf')).buffer.asUint8List(),
    fontFamily: family,
  );
  await ui.loadFontFromList(
    (await bundle.load('assets/fonts/Geist-Regular.ttf')).buffer.asUint8List(),
    fontFamily: 'PdfLatin',
  );
  const width = 595.28;
  const height = 841.89;
  const margin = 36.0;
  const bottom = height - 62;
  ui.Color color(String role, int fallback) =>
      snapshot.design.color(ui.Brightness.light, role, fallback: ui.Color(fallback));
  final ink = color('ink', 0xff202037);
  final muted = color('textSecondary', 0xff66667a);
  final rule = color('borderSubtle', 0xffdddded);
  final pages = <(ui.PictureRecorder, ui.Canvas)>[];
  late ui.Canvas canvas;
  var y = margin;

  String isolate(String value) =>
      snapshot.rtl && !RegExp(r'[\u0600-\u06ff]').hasMatch(value)
          ? '\u2066$value\u2069'
          : value;

  ui.Paragraph paragraph(String text, double size, ui.Color color, bool bold) {
    final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
      textDirection: snapshot.rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
      fontSize: size,
      fontFamily: family,
    ))
      ..pushStyle(ui.TextStyle(
        color: color,
        fontFamily: family,
        fontFamilyFallback: ['PdfLatin'],
        fontSize: size,
        fontWeight: bold ? ui.FontWeight.w700 : ui.FontWeight.w400,
      ))
      ..addText(text);
    return builder.build()
      ..layout(const ui.ParagraphConstraints(width: width - margin * 2));
  }

  void newPage() {
    final recorder = ui.PictureRecorder();
    canvas = ui.Canvas(recorder)..scale(2);
    canvas.drawRect(const ui.Rect.fromLTWH(0, 0, width, height),
        ui.Paint()..color = const ui.Color(0xffffffff));
    pages.add((recorder, canvas));
    final header = paragraph(snapshot.appName, 12, ink, true);
    canvas.drawParagraph(header, const ui.Offset(margin, margin));
    y = margin + header.height + 20;
    header.dispose();
  }

  void text(String value,
      {double size = 10,
      bool bold = false,
      ui.Color? color,
      double gap = 8}) {
    final p = paragraph(isolate(value), size, color ?? ink, bold);
    var consumed = 0.0;
    while (consumed < p.height) {
      if (y + size * 2 > bottom) newPage();
      final room = bottom - y;
      // Split only at shaped line boundaries; never cut a glyph at a page edge.
      var end = consumed;
      for (final line in p.computeLineMetrics()) {
        final lineBottom = line.baseline + line.descent;
        if (lineBottom > consumed && lineBottom - consumed <= room) {
          end = lineBottom;
        }
      }
      if (p.height - consumed <= room) end = p.height;
      if (end <= consumed) {
        newPage();
        continue;
      }
      canvas.save();
      canvas.clipRect(
          ui.Rect.fromLTWH(margin, y, width - margin * 2, end - consumed));
      canvas.drawParagraph(p, ui.Offset(margin, y - consumed));
      canvas.restore();
      y += end - consumed;
      consumed = end;
      if (consumed < p.height) newPage();
    }
    y += gap;
    p.dispose();
  }

  newPage();
  text(snapshot.title, size: 22, bold: true, gap: 12);
  if (!snapshot.receipt) {
    text(
        snapshot.tr(
            snapshot.rows.length == 1
                ? '{p0} transaction'
                : '{p0} transactions',
            {'p0': snapshot.rows.length}),
        color: muted);
  }
  if (snapshot.filters.isNotEmpty) {
    text(snapshot.filters.join(' | '), color: muted);
  }
  if (snapshot.rows.isEmpty) {
    text(snapshot.tr('No transactions match these filters.'));
  }
  for (final row in snapshot.rows) {
    if (bottom - y < 140) newPage();
    text(row.amount, size: snapshot.receipt ? 24 : 16, bold: true);
    text(row.title, size: 12, bold: true);
    for (final (label, value) in <(String, String)>[
      ('Status', row.status),
      ('Type', row.type),
      ('Reference', row.reference),
      ('Booked', row.booked),
      if (row.identity != null) ('Account / card', row.identity!),
      if (row.subtitle.isNotEmpty) ('Details', row.subtitle),
    ]) {
      text('${snapshot.tr(label)}: ${isolate(value)}');
    }
    if (row.settlementAmount != null) {
      text(snapshot.tr('{p0} settled', {'p0': row.settlementAmount}),
          color: muted);
    }
    if (y < bottom) {
      canvas.drawLine(ui.Offset(margin, y), ui.Offset(width - margin, y),
          ui.Paint()..color = rule);
      y += 16;
    }
  }
  final doc = pw.Document(title: snapshot.title, author: snapshot.appName);
  for (var i = 0; i < pages.length; i++) {
    final (recorder, pageCanvas) = pages[i];
    final footer = paragraph(
        '${snapshot.tr('Generated {p0}', {
              'p0': isolate(transactionPdfDateLabel(snapshot.generatedAt))
            })}\n${snapshot.tr('Not for official use')} · ${i + 1} / ${pages.length}',
        8,
        muted,
        false);
    pageCanvas.drawParagraph(footer, const ui.Offset(margin, height - 48));
    footer.dispose();
    final picture = recorder.endRecording();
    final image =
        await picture.toImage((width * 2).ceil(), (height * 2).ceil());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final asset = pw.MemoryImage(png!.buffer.asUint8List());
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.Image(asset, fit: pw.BoxFit.fill)));
    image.dispose();
    picture.dispose();
  }
  return doc.save();
}
