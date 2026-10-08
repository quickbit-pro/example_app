import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/cards/data/card_auto_top_up_api.dart';
import 'package:mobile_flutter/features/cards/presentation/card_auto_top_up_sheet.dart';

const card = PaymentCard(
  id: '123',
  label: 'Example',
  last4: '4242',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.active,
  virtual: true,
  balance: Money(currency: 'USD', minorUnits: 1000),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
);
Map<String, dynamic> settings() => {
      'success': true,
      'lowBalanceEnabled': true,
      'watermark': 10,
      'targetBalance': 50,
      'lowBalanceMonthlyLimit': 500,
      'lowBalanceUsedThisMonth': 25,
      'failedTxEnabled': false,
      'failedTxMaxAmount': 40,
      'failedTxMonthlyLimit': 300,
      'depositEnabled': false,
      'depositSettings': [
        {
          'currency': 'USDC',
          'enabled': false,
          'maxAmount': 75,
          'usedThisMonth': 12
        },
        {
          'currency': 'USDT',
          'enabled': false,
          'maxAmount': 80,
          'usedThisMonth': 0
        },
      ],
    };

class FakeApi extends CardAutoTopUpApi {
  FakeApi() : super(Dio());
  Map<String, dynamic> current = settings();
  Map<String, dynamic>? saved;
  String? mode;
  bool failLoad = false, failSave = false;
  Completer<void>? gate;
  int saves = 0;
  @override
  Future<Map<String, dynamic>> load(String cardId) async {
    if (failLoad) throw StateError('Unavailable');
    return current;
  }

  @override
  Future<Map<String, dynamic>> save(
      String mode, Map<String, dynamic> payload) async {
    saves++;
    this.mode = mode;
    saved = payload;
    if (gate != null) await gate!.future;
    if (failSave) throw StateError('Unavailable');
    current = {
      ...current,
      'lowBalanceEnabled': mode == 'low-balance' && payload['enabled'] == true,
      'failedTxEnabled': mode == 'failed-tx' && payload['enabled'] == true,
      'depositEnabled': mode == 'deposit' &&
          (payload['settings'] as List).any((s) => s['enabled'] == true)
    };
    return current;
  }
}

Future<void> pump(WidgetTester tester, FakeApi api) async {
  await tester.binding.setSurfaceSize(const Size(500, 1500));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ProviderScope(
      overrides: [cardAutoTopUpApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CardAutoTopUpSheet(card: card))))));
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save settings'));
  await tester.tap(find.text('Save settings'));
  await tester.pumpAndSettle();
}

Future<void> select(WidgetTester tester, String label) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saved toast appears above the modal and dismisses automatically',
      (tester) async {
    final api = FakeApi();
    await tester.binding.setSurfaceSize(const Size(500, 1500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
      overrides: [cardAutoTopUpApiProvider.overrideWithValue(api)],
      child: MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showCardAutoTopUp(context, card),
                      child: const Text('Open Auto-Reload'))))),
    ));
    await tester.tap(find.text('Open Auto-Reload'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(SwitchListTile));
    await save(tester);
    final toast = find.text('Automatic top-up settings saved.');
    expect(toast, findsOneWidget);
    expect(tester.getBottomLeft(toast).dy,
        lessThan(tester.getTopLeft(find.text('Auto-Reload')).dy));
    expect(find.byType(CardAutoTopUpSheet), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(toast, findsNothing);
    expect(find.byType(CardAutoTopUpSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'loaded configuration requires explicit consent and sends target balance',
      (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    expect(find.text('Active: Low balance'), findsOneWidget);
    await save(tester);
    expect(api.saves, 0);
    expect(find.textContaining('Accept the automatic'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await save(tester);
    expect(api.saved, {
      'cardId': 123,
      'disclaimerAccepted': true,
      'enabled': true,
      'monthlyLimit': 500.0,
      'watermark': 10.0,
      'targetBalance': 50.0
    });
    expect(find.text('Automatic top-up settings saved.'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false);
  });
  testWidgets('disable needs no consent and no positive amounts',
      (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    await tester.tap(find.byType(SwitchListTile));
    await save(tester);
    expect(api.saved!['enabled'], false);
    expect(api.saved!['disclaimerAccepted'], false);
    expect(api.saved!['watermark'], 0);
    expect(find.text('Status: Off'), findsOneWidget);
  });
  testWidgets('failed payment and deposit send distinct payloads',
      (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    await select(tester, 'Failed payment');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await save(tester);
    expect(api.mode, 'failed-tx');
    expect(api.saved!['maxAmount'], 40);
    expect(api.saved!['monthlyLimit'], 300);
    await select(tester, 'Crypto deposit');
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(CheckboxListTile));
    await save(tester);
    expect(api.mode, 'deposit');
    expect(api.saved!['settings'], [
      {'currency': 'USDC', 'enabled': true, 'maxAmount': 75.0},
      {'currency': 'USDT', 'enabled': false, 'maxAmount': 0},
    ]);
    expect(find.text('Active: Crypto deposit'), findsOneWidget);
  });
  testWidgets('invalid target cannot be saved', (tester) async {
    final api = FakeApi();
    await pump(tester, api);
    await tester.enterText(find.byType(TextFormField).at(1), '5');
    await tester.tap(find.byType(CheckboxListTile));
    await save(tester);
    expect(api.saves, 0);
    expect(find.textContaining('Target balance must'), findsOneWidget);
  });
  testWidgets('load failure permits retry and save failure retains edits',
      (tester) async {
    final api = FakeApi()..failLoad = true;
    await pump(tester, api);
    expect(find.text('Save settings'), findsNothing);
    api.failLoad = false;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), '65');
    await tester.tap(find.byType(CheckboxListTile));
    api.failSave = true;
    await save(tester);
    expect(find.text('65'), findsOneWidget);
    expect(find.text('Automatic top-up settings saved.'), findsNothing);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
  testWidgets('pending request blocks duplicate submission', (tester) async {
    final api = FakeApi()..gate = Completer<void>();
    await pump(tester, api);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.tap(find.text('Save settings'));
    await tester.pump();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(api.saves, 1);
    expect(find.text('Automatic top-up settings saved.'), findsNothing);
    api.gate!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
  });
}
