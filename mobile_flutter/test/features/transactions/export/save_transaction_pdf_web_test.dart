@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:mobile_flutter/features/transactions/export/save_transaction_pdf_web.dart';

@JS('Promise.reject')
external JSPromise<JSAny?> rejected(JSAny error);

void main() {
  test('file sharing starts synchronously with correct PDF bytes and name',
      () async {
    web.ShareData? captured;
    var called = false;
    final navigator = {
      'canShare': ((web.ShareData data) => true).toJS,
      'share': ((web.ShareData data) {
        called = true;
        captured = data;
        return Future<JSAny?>.value(null).toJS;
      }).toJS,
    }.jsify()!;
    final browser = {'navigator': navigator}.jsify()! as web.Window;
    final document = prepareTransactionPdf(
      Uint8List.fromList([37, 80, 68, 70]),
      'hoppa-activity.pdf',
      browserWindow: browser,
    );
    expect(document.canShare, isTrue);
    final result = document.share();
    expect(called, isTrue); // No async work before navigator.share.
    expect(await result, isTrue);
    final file = captured!.files.toDart.single;
    expect(file.name, 'hoppa-activity.pdf');
    expect(file.type, 'application/pdf');
    expect((await file.arrayBuffer().toDart).toDart.asUint8List(),
        [37, 80, 68, 70]);
    document.dispose();
  });

  test('cancel is distinct from denied sharing and unsupported share is hidden',
      () async {
    web.Window browserWithError(String name) => {
          'navigator': {
            'canShare': ((web.ShareData data) => true).toJS,
            'share': ((web.ShareData data) =>
                rejected(web.DOMException('Test', name))).toJS,
          },
        }.jsify()! as web.Window;
    final cancelled = prepareTransactionPdf(Uint8List(4), 'receipt.pdf',
        browserWindow: browserWithError('AbortError'));
    expect(await cancelled.share(), isFalse);
    cancelled.dispose();
    final denied = prepareTransactionPdf(Uint8List(4), 'receipt.pdf',
        browserWindow: browserWithError('NotAllowedError'));
    await expectLater(denied.share(), throwsA(isA<web.DOMException>()));
    denied.dispose();
    final unsupported = prepareTransactionPdf(Uint8List(4), 'receipt.pdf',
        browserWindow: {'navigator': {}}.jsify()! as web.Window);
    expect(unsupported.canShare, isFalse);
    unsupported.dispose();
  });

  test('open reports popup blocking and download uses a named PDF blob',
      () async {
    String? openedUrl;
    final browser = {
      'open': ((String url, String target) {
        openedUrl = url;
        expect(target, '_blank');
        return null;
      }).toJS,
    }.jsify()! as web.Window;
    final document = prepareTransactionPdf(Uint8List(4), 'hoppa-receipt.pdf',
        browserWindow: browser);
    expect(document.open(), isFalse);
    expect(openedUrl, startsWith('blob:'));
    var clicked = false;
    final listener = ((web.Event event) {
      final target = event.target;
      if (target is web.HTMLAnchorElement) {
        event.preventDefault();
        clicked = true;
        expect(target.download, 'hoppa-receipt.pdf');
        expect(target.href, openedUrl);
        expect(target.target, isEmpty);
        expect(target.rel, 'noopener');
      }
    }).toJS;
    web.document.addEventListener('click', listener);
    try {
      document.download();
      expect(clicked, isTrue);
      expect(web.document.querySelector('a[download="hoppa-receipt.pdf"]'),
          isNull);
    } finally {
      web.document.removeEventListener('click', listener);
      document.dispose();
    }
  });
}
