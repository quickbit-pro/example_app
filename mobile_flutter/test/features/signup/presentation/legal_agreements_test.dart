import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/legal_agreements.dart';

void main() {
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
    expect(documents, hasLength(5));
    final samePdf = legalDocumentLibrary(
        MobileTenantConfig.fromJson({
          'company': {
            'privacyUrl':
                'https://docs.hoppa.global/Hoppacard Privacy Policy.pdf'
          },
        }),
        appName: 'Hoppa');
    expect(samePdf, hasLength(5));
    expect(documents.first.label, 'E-Sign Agreement / GLBA Disclosure');
    expect(documents.map((d) => d.label), contains('Hoppa General Terms (US)'));
    final invalid = legalDocumentLibrary(
        MobileTenantConfig.fromJson({
          'company': {'termsUrl': 'javascript:alert(1)', 'privacyUrl': '   '},
        }),
        appName: 'Hoppa');
    expect(invalid, hasLength(5));
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
    expect(base.expand((s) => s.links), hasLength(5));
    for (final link in base.expand((s) => s.links)) {
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

  testWidgets('all five PDF labels have clickable underlined text',
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
    expect(links, hasLength(5));
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
}
