import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/features/signup/presentation/equals_document_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/legal_agreements.dart';

void main() {
  test('Personal signup requires explicit Equals Money consent when enabled',
      () {
    const termsUrl = 'https://example.test/equals-money-terms.pdf';
    final config = MobileTenantConfig.fromJson({
      'company': {
        'brandName': 'CARDEO',
        'equalsGeneralTermsUrl': termsUrl,
      },
      'features': {'equalsMoneyEnabled': true},
    });
    final specs = legalAgreementSpecs(config, business: false);
    final equals =
        specs.singleWhere((s) => s.key == LegalAgreementKey.equalsTerms);
    expect(equals.links.single.label, 'Equals Money Terms and Conditions');
    expect(equals.links.single.url, termsUrl);

    final accepted = specs.map((s) => s.key).toSet()
      ..remove(LegalAgreementKey.equalsTerms);
    expect(allLegalAgreementsAccepted(specs, accepted), isFalse);
    expect(legalAgreementsPayload(specs, accepted, config)['equalsTerms'],
        isFalse);

    accepted.add(LegalAgreementKey.equalsTerms);
    expect(allLegalAgreementsAccepted(specs, accepted), isTrue);
    final payload = legalAgreementsPayload(specs, accepted, config);
    expect(payload['equalsTerms'], isTrue);
    expect((payload['documents'] as Map)['equalsGeneralTermsUrl'], termsUrl);
    expect(DateTime.parse(payload['acceptedAt'] as String).isUtc, isTrue);
  });

  test(
      'personal signup requires Equals consent even if its configured document is missing',
      () {
    for (final settings in [
      (enabled: false, url: 'https://example.test/equals-money-terms.pdf'),
      (enabled: true, url: null),
      (enabled: true, url: '   '),
    ]) {
      final config = MobileTenantConfig.fromJson({
        'company': {
          'brandName': 'CARDEO',
          'equalsGeneralTermsUrl': settings.url,
        },
        'features': {'equalsMoneyEnabled': settings.enabled},
      });
      expect(
        legalAgreementSpecs(config, business: false).map((s) => s.key),
        settings.enabled
            ? contains(LegalAgreementKey.equalsTerms)
            : isNot(contains(LegalAgreementKey.equalsTerms)),
      );
    }
  });

  test('settings library includes every registration and card-order document',
      () {
    final config = MobileTenantConfig.fromJson({
      'company': {
        'brandName': 'Acme',
        'eCommunicationNoticeUrl': 'https://example.test/glba.pdf',
        'equalsGeneralTermsUrl': 'https://example.test/fiat.pdf',
        'termsUrl': 'https://example.test/company-terms.pdf',
        'privacyUrl': 'https://example.test/company-privacy.pdf',
      },
      'features': {'equalsMoneyEnabled': false},
    });
    final documents = legalDocumentLibrary(config, appName: 'Acme');
    final urls = documents.map((d) => d.url).toList();
    for (final spec in [
      ...legalAgreementSpecs(config, business: false),
      ...legalAgreementSpecs(config, business: true),
      ...cardOrderAgreementSpecs(config),
    ]) {
      for (final link in spec.links) {
        expect(urls, contains(link.url));
      }
    }
    expect(urls.toSet().length, urls.length);
    expect(
        urls,
        containsAll([
          'https://example.test/company-terms.pdf',
          'https://example.test/company-privacy.pdf',
          'https://example.test/fiat.pdf'
        ]));
    expect(documents.map((d) => d.label).join(' '), isNot(contains('Example')));
  });

  test('settings retains shared PDFs with no config and combines GLBA fallback',
      () {
    final documents = legalDocumentLibrary(null, appName: 'Hoppa');
    expect(documents, hasLength(7));
    final samePdf = legalDocumentLibrary(
        MobileTenantConfig.fromJson({
          'company': {
            'privacyUrl':
                'https://docs.hoppa.global/Hoppacard Privacy Policy.pdf'
          },
        }),
        appName: 'Hoppa');
    expect(samePdf, hasLength(7));
    expect(documents.first.label, 'E-Sign Agreement / GLBA Disclosure');
    expect(documents.map((d) => d.label), contains('Hoppa General Terms (US)'));
    final invalid = legalDocumentLibrary(
        MobileTenantConfig.fromJson({
          'company': {'termsUrl': 'javascript:alert(1)', 'privacyUrl': '   '},
        }),
        appName: 'Hoppa');
    expect(invalid, hasLength(7));
  });

  test('registration PDFs are shared even when tenant URLs differ', () {
    final base = legalAgreementSpecs(null, business: false, appName: 'Hoppa');
    final tenant = legalAgreementSpecs(
        MobileTenantConfig.fromJson({
          'company': {
            'brandName': 'Acme',
            'eSignUrl': 'https://example.test/old',
            'privacyUrl': 'https://example.test/privacy',
            'generalTermsUrl': 'https://example.test/terms',
            'generalTermsUsUrl': 'https://example.test/us',
            'additionalAcknowledgementsUrl': 'https://example.test/extra',
          }
        }),
        business: false);
    expect(tenant.expand((s) => s.links).map((l) => l.url),
        base.expand((s) => s.links).map((l) => l.url));
    final programmeLinks = base
        .where((s) =>
            s.key != LegalAgreementKey.equalsTerms &&
            s.key != LegalAgreementKey.equalsPrivacy)
        .expand((s) => s.links);
    expect(programmeLinks, hasLength(5));
    for (final link in programmeLinks) {
      expect(Uri.parse(link.url!).host, 'docs.hoppa.global');
      expect(Uri.parse(link.url!).path, endsWith('.pdf'));
    }
    final payload =
        legalAgreementsPayload(base, base.map((s) => s.key).toSet(), null);
    final documents = payload['documents'] as Map;
    for (final link in base.expand((s) => s.links)) {
      expect(documents.values, contains(link.url));
    }
    expect(tenant.map((s) => s.title).join(' '), contains('Acme'));
    expect(tenant.map((s) => s.title).join(' '), isNot(contains('Example')));
  });

  test('dashboard opt-in supplies legal URLs and current consent version', () {
    final config = MobileTenantConfig.fromJson({
      'company': {
        'legalDocumentsFromDashboard': true,
        'eSignUrl': 'https://example.test/esign.pdf',
        'generalTermsUrl': 'https://example.test/non-us.pdf',
        'generalTermsUsUrl': 'https://example.test/us.pdf',
        'privacyUrl': 'https://example.test/privacy.pdf',
        'equalsGeneralTermsUrl': 'https://example.test/equals.pdf',
        'equalsTermsVersion': '1.2',
      }
    });
    final specs = legalAgreementSpecs(config, business: false);
    final payload =
        legalAgreementsPayload(specs, specs.map((s) => s.key).toSet(), config);
    expect(payload['equalsTermsVersion'], '1.2');
    expect((payload['documents'] as Map)['generalTermsUrl'],
        'https://example.test/non-us.pdf');
    expect((payload['documents'] as Map)['eSignUrl'],
        'https://example.test/esign.pdf');
    expect((payload['documents'] as Map)['privacyUrl'],
        'https://example.test/privacy.pdf');
  });

  testWidgets(
      'programme PDFs and Equals privacy have clickable underlined text',
      (tester) async {
    final specs = legalAgreementSpecs(null, business: false, appName: 'Hoppa');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
      child: LegalAgreementsSection(
          specs: specs, accepted: const {}, onChanged: (_, __) {}),
    ))));
    final links = <TextSpan>[];
    for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
      rich.text.visitChildren((span) {
        if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
          links.add(span);
        }
        return true;
      });
    }
    expect(links, hasLength(6));
    expect(links.map((s) => s.style?.decoration),
        everyElement(TextDecoration.underline));
    expect(
        links.map((s) => s.text),
        containsAll([
          'E-Sign Agreement',
          'Privacy Policy',
          'Hoppa General Terms (Non-US)',
          'Hoppa General Terms (US)'
        ]));
  });
  testWidgets(
      'both Equals agreements require full review and separate acceptance',
      (tester) async {
    const termsUrl = 'https://example.test/terms.pdf';
    final specs = legalAgreementSpecs(
            MobileTenantConfig.fromJson({
              'company': {'equalsGeneralTermsUrl': termsUrl},
              'features': {'equalsMoneyEnabled': true},
            }),
            business: false)
        .where((s) =>
            s.key == LegalAgreementKey.equalsTerms ||
            s.key == LegalAgreementKey.equalsPrivacy)
        .toList();
    final accepted = <LegalAgreementKey>{};
    await tester.pumpWidget(ProviderScope(
        overrides: [
          equalsDocumentProvider.overrideWith((ref, kind) async {
            return EqualsDocument(
                url: kind == 'terms' ? termsUrl : equalsPrivacyPolicyUrl('EU'),
                type: 'text/html',
                bytes: Uint8List.fromList(utf8.encode(
                    '<main>${List.generate(80, (i) => '<p>Legal paragraph $i. Read this document in full.</p>').join()}</main>')));
          }),
        ],
        child: MaterialApp(
            home: Scaffold(
                body: StatefulBuilder(
          builder: (context, setState) => LegalAgreementsSection(
              specs: specs,
              accepted: accepted,
              onChanged: (key, value) => setState(() {
                    if (value) {
                      accepted.add(key);
                    } else {
                      accepted.remove(key);
                    }
                  })),
        )))));
    final titles = [
      'I accept the Equals Money Terms and Conditions',
      'I confirm I have read and agree to the Equals Privacy Policy',
    ];
    FilledButton confirm() =>
        tester.widget(find.byKey(const Key('equals-document-confirm')));
    // Closing before reaching the bottom leaves consent untouched.
    await tester.tap(find.text(titles.first));
    await tester.pumpAndSettle();
    expect(confirm().onPressed, isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(accepted, isEmpty);
    for (final title in titles) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNull);
      final scroll = tester
          .widget<SingleChildScrollView>(
              find.byKey(const Key('equals-document-scroll')))
          .controller!;
      scroll.jumpTo(scroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(confirm().onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('equals-document-confirm')));
      await tester.pumpAndSettle();
      // Confirming review does not tick the agreement.
      expect(accepted.length, titles.indexOf(title));
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    expect(accepted,
        {LegalAgreementKey.equalsTerms, LegalAgreementKey.equalsPrivacy});
  });
}
