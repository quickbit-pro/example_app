import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_destination_form.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_account_details.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_support.dart';

class _Api extends MobilePlatformApi {
  _Api() : super(Dio());
  Map<String, dynamic>? saved;
  bool fail = false;
  int id = 123;
  @override
  Future<List<Map<String, dynamic>>> getExchangeDestinations() async => [];
  @override
  Future<Map<String, dynamic>> registerExchangeCrypto(
      Map<String, dynamic> request) async {
    saved = request;
    if (fail) throw StateError('Provider unavailable');
    return {'id': id};
  }

  @override
  Future<Map<String, dynamic>> registerExchangeBank(
          Map<String, dynamic> request) =>
      registerExchangeCrypto(request);
}

Future<void> _open(WidgetTester t, _Api api, {bool bank = false}) async {
  t.view.physicalSize = const Size(1200, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(ProviderScope(
      overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => ExchangeDestinationForm(bank: bank)),
                      child: const Text('Open')))))));
  await t.tap(find.text('Open'));
  await t.pumpAndSettle();
}

Future<void> fillCrypto(WidgetTester t) async {
  await t.enterText(
      find.byKey(const ValueKey('destination-name')), 'My wallet');
  await t.enterText(find.byKey(const ValueKey('destination-address')),
      '0x1111111111111111111111111111111111111111');
}

Future<void> confirm(WidgetTester t) async {
  await t.pumpAndSettle();
  final f = find.byKey(const ValueKey('confirm-destination-details'));
  await t.ensureVisible(f);
  await t.tap(f);
  await t.pumpAndSettle();
}

Finder get save => find.byKey(const ValueKey('save-exchange-destination'));
void main() {
  testWidgets(
      'saved destinations lets users add before withdrawals are enabled',
      (t) async {
    final api = _Api();
    t.view.physicalSize = const Size(1200, 1800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(ProviderScope(
        overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
            home: Scaffold(
                body: ExchangeAccountDetails(
                    destinations: true, outflowsEnabled: false)))));
    await t.pumpAndSettle();
    expect(find.text('Add bank account'), findsOneWidget);
    await t.tap(find.text('Add crypto address'));
    await t.pumpAndSettle();
    await fillCrypto(t);
    await confirm(t);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(find.text('My wallet'), findsOneWidget);
    expect(find.text('Destination saved. No funds were transferred.'),
        findsOneWidget);
  });
  testWidgets(
      'save crypto requires confirmation and only registers destination',
      (t) async {
    final api = _Api();
    await _open(t, api);
    await fillCrypto(t);
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    await confirm(t);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(api.saved, {
      'name': 'My wallet',
      'currency': 'USDT',
      'chain_id': 1,
      'address': '0x1111111111111111111111111111111111111111'
    });
    expect(find.byType(ExchangeDestinationForm), findsNothing);
  });
  testWidgets('changing network clears confirmation and rejects wrong address',
      (t) async {
    await _open(t, _Api());
    await fillCrypto(t);
    await confirm(t);
    final network = find.byType(DropdownButtonFormField<int>);
    await t.ensureVisible(network);
    await t.tap(network);
    await t.pumpAndSettle();
    await t.tap(find.text('Tron (TRC20)').last);
    await t.pumpAndSettle();
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('destination-address')),
        'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8');
    await confirm(t);
    expect(t.widget<FilledButton>(save).onPressed, isNotNull);
  });
  for (final missingId in [false, true]) {
    testWidgets(
        'provider ${missingId ? 'missing ID' : 'error'} keeps form open and allows retry',
        (t) async {
      final api = _Api()
        ..fail = !missingId
        ..id = missingId ? 0 : 123;
      await _open(t, api);
      await fillCrypto(t);
      await confirm(t);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.byType(ExchangeDestinationForm), findsOneWidget);
      expect(t.widget<FilledButton>(save).onPressed, isNotNull);
      api.fail = false;
      api.id = 123;
      await t.tap(save);
      await t.pumpAndSettle();
      expect(find.byType(ExchangeDestinationForm), findsNothing);
    });
  }
  testWidgets('bank form validates IBAN and sends provider field names',
      (t) async {
    final api = _Api();
    await _open(t, api, bank: true);
    final fields =
        t.widget<ExchangeBankFields>(find.byType(ExchangeBankFields));
    fields.onChanged({
      'name': 'My bank',
      'accountNumber': 'DE89370400440532013001',
      'bankName': 'Bank',
      'accountHolderName': 'Jane Doe',
      'country': 'DE',
      'beneficiaryType': 'individual',
      'firstName': 'Jane',
      'lastName': 'Doe'
    });
    await t.pumpAndSettle();
    await confirm(t);
    expect(t.widget<FilledButton>(save).onPressed, isNull);
    await t.enterText(find.byKey(const ValueKey('bank-accountNumber')),
        'DE89 3704 0044 0532 0130 00');
    await confirm(t);
    await t.tap(save);
    await t.pumpAndSettle();
    expect(api.saved, {
      'name': 'My bank',
      'currency': 'EUR',
      'account_number': 'DE89370400440532013000',
      'bank_name': 'Bank',
      'account_holder_name': 'Jane Doe',
      'country': 'DE',
      'beneficiary_type': 'individual',
      'first_name': 'Jane',
      'last_name': 'Doe'
    });
    expect(find.byType(ExchangeDestinationForm), findsNothing);
  });
  testWidgets('dashboard disclaimer and terms are available before saving',
      (t) async {
    await _open(t, _Api());
    final disclaimer = find.text('Crypto Services Disclaimer');
    await t.ensureVisible(disclaimer);
    await t.tap(disclaimer);
    await t.pumpAndSettle();
    expect(find.textContaining('Zillion Bits').last, findsOneWidget);
    await t.tap(find.text('Close'));
    await t.pumpAndSettle();
    final terms = find.text('ZBX Terms & Risk Disclosure');
    await t.ensureVisible(terms);
    await t.tap(terms);
    await t.pumpAndSettle();
    expect(find.byType(SelectableText), findsOneWidget);
  });
}
