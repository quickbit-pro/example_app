import 'dart:convert';
import 'dart:io';

import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phone_form_field/phone_form_field.dart' show IsoCode;
import 'package:mobile_flutter/core/l10n/app_localization_delegates.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/core/l10n/phone_localizations.dart';
import 'package:mobile_flutter/core/documents/original_receipt_button.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_fees_and_limits.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_reference_data.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_disclaimer.dart';
import 'package:mobile_flutter/shared/widgets/legal_disclosure.dart';
import 'package:mobile_flutter/shared/widgets/localized_disclosure.dart';

class _CatalogDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _CatalogDelegate(this.catalog);
  final AppLocalizations catalog;
  @override
  bool isSupported(Locale locale) => locale == catalog.locale;
  @override
  Future<AppLocalizations> load(Locale locale) => SynchronousFuture(catalog);
  @override
  bool shouldReload(_CatalogDelegate old) => old.catalog != catalog;
}

AppLocalizations catalogFor(String code) => AppLocalizations(
    Locale(code),
    (jsonDecode(File('assets/l10n/$code.json').readAsStringSync())
            as Map<String, dynamic>)
        .cast<String, String>());

Widget localizedApp(AppLocalizations catalog, Widget home) => ProviderScope(
      child: MaterialApp(
        locale: catalog.locale,
        supportedLocales: appLanguages.map((language) => language.locale),
        localizationsDelegates: [
          _CatalogDelegate(catalog),
          ...appLocalizationsDelegates,
        ],
        home: home,
      ),
    );

void main() {
  setUp(rootBundle.clear);
  for (final language in appLanguages.where((l) => l.code != 'en')) {
    testWidgets('${language.code}: card artwork status translates',
        (tester) async {
      final catalog = catalogFor(language.code);
      const statuses = {
        CardStatus.active: 'Active',
        CardStatus.frozen: 'Frozen',
        CardStatus.pending: 'Pending',
        CardStatus.cancelled: 'Closed',
      };
      for (final entry in statuses.entries) {
        await tester.pumpWidget(localizedApp(
            catalog,
            Scaffold(
                body: SizedBox(
              width: 360,
              child: ExamplePaymentCard(status: entry.key),
            ))));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(find.text(catalog.translate(entry.value)), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
    testWidgets(
        '${language.code}: country selector and receipt action translate',
        (tester) async {
      final catalog = catalogFor(language.code);
      String? selected;
      await tester.pumpWidget(localizedApp(
          catalog,
          Scaffold(
            body: ExchangeCountryField(
                label: 'Bank country',
                value: 'DE',
                onChanged: (value) => selected = value),
          )));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(find.text(catalog.translate('Bank country')), findsOneWidget);
      expect(find.text(catalog.translate('Germany')), findsOneWidget);
      final dropdown = tester
          .widget<DropdownButton<String>>(find.byType(DropdownButton<String>));
      expect(dropdown.value, 'DE');
      dropdown.onChanged!('FR');
      expect(selected, 'FR');
      await tester.pumpWidget(localizedApp(catalog,
          const Scaffold(body: OriginalReceiptButton(documentId: 'receipt'))));
      await tester.pumpAndSettle();
      expect(find.text(catalog.translate('View original receipt')),
          findsOneWidget);
      expect(find.text('View original receipt'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('German validation keeps null and translates the returned error',
      (tester) async {
    late BuildContext context;
    await tester
        .pumpWidget(localizedApp(catalogFor('de'), Builder(builder: (c) {
      context = c;
      return const Scaffold();
    })));
    await tester.pumpAndSettle();
    expect(context.localizeValidator<String>(null), isNull);
    final validate = context.localizeValidator<String>(
        (value) => value == 'valid' ? null : 'Enter city')!;
    expect(validate('valid'), isNull);
    expect(validate(''), catalogFor('de').translate('Enter city'));
    expect(validate(''), isNot('Enter city'));
  });

  test('fee limits preserve the exact amount and asset in each language', () {
    const limits = BoomFiFeesAndLimits(minWithdraw: '0.0000100');
    for (final language in appLanguages) {
      final catalog = catalogFor(language.code);
      final error = limits.validate('0.0000099', 'BTC',
          withdrawal: true, translate: catalog.translate);
      expect(error, contains('0.0000100'));
      expect(error, contains('BTC'));
      if (language.code != 'en')
        expect(error, isNot(contains('Minimum withdrawal is')));
      expect(
          limits.validate('0.0000100', 'BTC',
              withdrawal: true, translate: catalog.translate),
          isNull);
    }
  });

  test(
      'every translated disclosure preserves regulatory and company identifiers',
      () {
    const fiat = 'FIAT ACCOUNTS: $defaultEqualsPaymentServicesDisclosure';
    const documents = {
      exchangeTerms: ['C 88757', 'ZBL-24354', 'ZBL-28410', 'BKR 4013'],
      cryptoServicesDisclaimer: ['C 88757', 'ZBL-24354', 'ZBL-28410'],
      fiat: ['488396', '05539698', '900493', 'EC4V 3BJ'],
    };
    for (final language in appLanguages.where((l) => l.code != 'en')) {
      final catalog = catalogFor(language.code);
      for (final entry in documents.entries) {
        final translation = catalog.translate(entry.key);
        expect(translation, isNot(entry.key), reason: language.code);
        for (final id in entry.value) {
          expect(translation, contains(id), reason: language.code);
        }
      }
    }
  });

  testWidgets('the original and translated exchange terms can both be read',
      (tester) async {
    final catalog = catalogFor('es');
    await tester.pumpWidget(localizedApp(
        catalog,
        const Scaffold(
            body: SingleChildScrollView(
                child: LocalizedDisclosure(exchangeTerms)))));
    await tester.pumpAndSettle();
    expect(find.text(catalog.translate(exchangeTerms)), findsOneWidget);
    final original =
        find.text(catalog.translate('Original document (English)'));
    await tester.ensureVisible(original);
    await tester.tap(original);
    await tester.pumpAndSettle();
    expect(find.text(exchangeTerms), findsOneWidget);
  });

  for (final code in ['ja', 'id', 'ko']) {
    testWidgets('$code: phone and country picker do not fall back to English',
        (tester) async {
      rootBundle.clear();
      final phone = (await tester.runAsync(
          () => const AppPhoneLocalizationsDelegate().load(Locale(code))))!;
      final countries = (await tester.runAsync(
          () => const AppCountryLocalizationsDelegate().load(Locale(code))))!;
      expect(phone.invalidPhoneNumber, isNot('Invalid phone number'));
      expect(phone.phoneNumber, isNot('Phone number'));
      expect(countries.search, isNot('Search'));
      expect(countries.countryName(IsoCode.DE),
          {'ja': 'ドイツ', 'id': 'Jerman', 'ko': '독일'}[code]);
      for (final iso in IsoCode.values) {
        expect(countries.countryName(iso), isNotEmpty);
      }
    });
  }
}
