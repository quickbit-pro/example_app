import 'package:dio/dio.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/routes.dart';
import 'package:mobile_flutter/features/money/domain/bank_payee_draft.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_account_details.dart';

const _tronHex = '0x5CBDD86A2FA8DC4BDDD8A8F69DBA48572EEC07FB';
const _tronAddress = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
String _issued(int chain) => chain == -200 ? _tronAddress : 'issued-$chain';

class _DepositApi extends MobilePlatformApi {
  _DepositApi(this.accounts) : super(Dio());

  List<Map<String, dynamic>> accounts;
  final requestedChains = <int>[];
  final requestedCurrencies = <String>[];
  String kycStatus = 'accepted';
  bool failCreation = false;
  List<String>? issuedCurrencies;
  int? returnedChain;
  bool retainIssuedAccount = false;

  @override
  Future<Map<String, dynamic>> createExchangePayInAddress({
    required String currency,
    required int chainId,
  }) async {
    requestedCurrencies.add(currency);
    requestedChains.add(chainId);
    if (failCreation) throw StateError('Provider unavailable');
    if (retainIssuedAccount) {
      accounts.add({
        'reference': 'deposit-1-227-${currency.toLowerCase()}-$chainId',
        'chainId': chainId,
        'address': chainId == -200 ? _tronHex : 'issued-$chainId',
        'currencies': [currency],
        'ready': true,
      });
    }
    return {
      'depositWallet': {
        'chain_id': returnedChain ?? chainId,
        'address': chainId == -200 ? _tronHex : 'issued-$chainId',
        'status': 'Ready',
        'enabled': true,
        if (issuedCurrencies != null) 'currencies': issuedCurrencies,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> getExchangeSettlementAccounts() async => {
        'kycStatus': kycStatus,
        'accounts': accounts,
      };
}

const _placeholder = <String, dynamic>{
  'chainId': 0,
  'currencies': <String>[],
  'ready': false,
};
const _eur = <String, dynamic>{
  'chainId': 0,
  'currencies': ['EUR'],
  'ready': true,
  'address': 'TEST-IBAN',
};

Future<void> _open(WidgetTester tester, _DepositApi api) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    child: const MaterialApp(
      home: Scaffold(body: ExchangeAccountDetails()),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
}

Future<void> _select(WidgetTester tester, String currency, int chain) async {
  final selector = find.byWidgetPredicate((widget) =>
      widget is DropdownButtonFormField<int> &&
      widget.key.toString().contains('deposit-network-$currency-'));
  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await tester.pumpAndSettle();
  final label = switch (chain) {
    1 => 'Ethereum (ERC20)',
    -200 => 'Tron (TRC20)',
    _ => 'Solana',
  };
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _expectQr(WidgetTester tester, String key, String address) async {
  final canvas = tester.widget<CustomPaint>(find.descendant(
      of: find.byKey(ValueKey(key)), matching: find.byType(CustomPaint)));
  final painter = canvas.painter! as QrPainter;
  await tester.runAsync(() async {
    final actual = await painter.toImageData(160);
    final expected =
        await QrPainter(data: address, version: QrVersions.auto, gapless: true)
            .toImageData(160);
    expect(actual!.buffer.asUint8List(), expected!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('Add to Equals payees opens a draft with exact bank details', (tester) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    BankPayeeDraft? draft;
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (context, _) => Scaffold(body: TextButton(
        onPressed: () => showDialog<void>(context: context, builder: (_) => const ExchangeAccountDetails()),
        child: const Text('Open deposit')))),
      GoRoute(path: AppRoutes.payees, builder: (_, state) {
        draft = state.extra as BankPayeeDraft;
        return const Scaffold(body: Text('Review payee'));
      }),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      mobileTenantConfigProvider.overrideWith((ref) async => MobileTenantConfig.fromJson({'features': {'equalsMoneyEnabled': true}})),
      mobilePlatformApiProvider.overrideWithValue(_DepositApi([{
        'chainId': 0, 'currencies': ['EUR'], 'ready': true,
        'address': 'MT84MALT011000012345MTLCAST001S',
        'paymentReference': 'deposit-reference', 'reference': 'internal-id',
        'bank': {'accountHolderName': 'ANA NOVAK', 'bic': 'MALTMTMT',
          'country': 'MT', 'name': 'Receiving Bank', 'address': 'Malta bank address'},
      }])),
    ], child: MaterialApp.router(routerConfig: router)));
    await tester.tap(find.text('Open deposit'));
    await tester.pumpAndSettle();
    final add = find.text('Add to Equals payees');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Review payee'), findsOneWidget);
    expect(draft?.iban, 'MT84MALT011000012345MTLCAST001S');
    expect(draft?.accountHolder, 'ANA NOVAK');
    expect(draft?.bankCountry, 'MT');
    expect(draft?.bankAddress, 'Malta bank address');
    expect(draft?.paymentReference, 'deposit-reference');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [375.0, 1200.0]) {
    testWidgets('EUR bank QR, copy details and placeholder filtering at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _open(tester, _DepositApi([
        {'chainId': 0, 'currencies': ['EUR'], 'ready': false},
        {'chainId': 0, 'currencies': ['GBP'], 'ready': false},
        {'chainId': 0, 'currencies': ['EUR'], 'ready': true,
          'address': 'DE89370400440532013000', 'reference': 'internal-account-id',
          'bank': {'accountHolderName': 'ROK KOGOVŠEK', 'bic': 'COBADEFFXXX', 'name': 'Example Bank'}},
      ]));
      expect(find.text('EUR'), findsOneWidget);
      expect(find.text('GBP'), findsOneWidget);
      expect(find.text('These deposit details are not available yet. Refresh to check again.'), findsOneWidget);
      expect(find.text('Account holder'), findsOneWidget);
      final qrRect = tester.getRect(find.byType(QrImageView));
      final holderRect = tester.getRect(find.text('Account holder'));
      if (width >= 1000) {
        expect(holderRect.right, lessThan(qrRect.left), reason: 'Desktop keeps bank details beside the QR.');
      } else {
        expect(holderRect.bottom, lessThan(qrRect.top), reason: 'Phones prioritize copyable bank details above the optional QR.');
      }
      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      final painter = tester.widget<CustomPaint>(find.descendant(
          of: find.byType(QrImageView), matching: find.byType(CustomPaint))).painter! as QrPainter;
      await tester.runAsync(() async {
        final actual = await painter.toImageData(200);
        final expected = await QrPainter(data: 'BCD\n002\n1\nSCT\nCOBADEFFXXX\nROK KOGOVŠEK\nDE89370400440532013000',
            version: QrVersions.auto, errorCorrectionLevel: QrErrorCorrectLevel.M,
            gapless: true).toImageData(200);
        expect(actual!.buffer.asUint8List(), expected!.buffer.asUint8List());
      });
      expect(qr.errorCorrectionLevel, QrErrorCorrectLevel.M);
      final copy = find.text('Copy bank details');
      await tester.ensureVisible(copy);
      await tester.tap(copy);
      await tester.pumpAndSettle();
      expect(clipboard.single, contains('Account holder: ROK KOGOVŠEK'));
      expect(clipboard.single, isNot(contains('internal-account-id')));
      final copyBic = find.byTooltip('Copy BIC / SWIFT');
      await tester.ensureVisible(copyBic);
      await tester.tap(copyBic);
      await tester.pumpAndSettle();
      expect(clipboard.last, 'COBADEFFXXX');
      expect(tester.takeException(), isNull);
      await _close(tester);
    });
  }

  for (final (currency, chain) in [
    ('USDC', 1),
    ('USDC', -200),
    ('USDC', 1399811149),
    ('USDT', 1),
    ('USDT', -200)
  ]) {
    testWidgets(
        'creates $currency on $chain without requesting again on refresh',
        (tester) async {
      final api = _DepositApi([])..issuedCurrencies = [currency];
      await _open(tester, api);
      await _select(tester, currency, chain);
      final button =
          find.byKey(ValueKey('create-${currency.toLowerCase()}-$chain'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.requestedChains, [chain]);
      expect(api.requestedCurrencies, [currency]);
      expect(find.text(_issued(chain)), findsOneWidget);
      expect(button, findsNothing);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(api.requestedChains, [chain]);
      expect(find.text(_issued(chain)), findsOneWidget);
      await _close(tester);
    });
  }

  testWidgets(
      'default crypto account addresses are ignored while bank details remain',
      (tester) async {
    final api = _DepositApi([
      {
        'chainId': 1,
        'address': 'default-usdc-address',
        'currencies': ['USDC'],
        'ready': true
      },
      {
        'chainId': -200,
        'address': _tronHex,
        'currencies': ['USDT'],
        'ready': true
      },
      _eur,
    ]);
    await _open(tester, api);
    expect(find.text('default-usdc-address'), findsNothing);
    expect(find.text(_tronAddress), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const ValueKey('create-usdc-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('create-usdt-1')), findsOneWidget);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    expect(api.requestedChains, isEmpty);
    await _close(tester);
  });

  testWidgets(
      'USDC and USDT on the same chain are provisioned and retained separately',
      (tester) async {
    final api = _DepositApi([]);
    await _open(tester, api);
    for (final currency in ['USDC', 'USDT']) {
      final button = find.byKey(ValueKey('create-${currency.toLowerCase()}-1'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('deposit-address-$currency')), findsOneWidget);
    }
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(api.requestedCurrencies, ['USDC', 'USDT']);
    expect(api.requestedChains, [1, 1]);
    expect(find.byKey(const ValueKey('deposit-address-USDC')), findsOneWidget);
    expect(find.byKey(const ValueKey('deposit-address-USDT')), findsOneWidget);
    await _close(tester);
  });

  testWidgets(
      'reopening restores provisioned USDC without using default addresses',
      (tester) async {
    final api = _DepositApi([
      {
        'chainId': 1,
        'address': 'default-usdc-address',
        'currencies': ['USDC'],
        'ready': true
      },
    ])
      ..retainIssuedAccount = true;
    await _open(tester, api);
    final button = find.byKey(const ValueKey('create-usdc-1'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await _close(tester);
    await _open(tester, api);
    expect(find.text('default-usdc-address'), findsNothing);
    expect(find.text('issued-1'), findsOneWidget);
    expect(find.byKey(const ValueKey('create-usdc-1')), findsNothing);
    expect(find.byKey(const ValueKey('create-usdt-1')), findsOneWidget);
    expect(api.requestedCurrencies, ['USDC']);
    await _close(tester);
  });

  testWidgets(
      'reopening recovers both successful requests from provider accounts',
      (tester) async {
    final api = _DepositApi([])..retainIssuedAccount = true;
    await _open(tester, api);
    for (final chain in [1, -200]) {
      await _select(tester, 'USDT', chain);
      final button = find.byKey(ValueKey('create-usdt-$chain'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
    }
    await _close(tester);
    await _open(tester, api);
    expect(find.byKey(const ValueKey('create-usdt-1')), findsNothing);
    expect(find.textContaining('Waiting for confirmation'), findsNothing);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.text('issued-1'), findsOneWidget);
    expect(find.text(_tronAddress), findsNothing);
    await _select(tester, 'USDT', -200);
    expect(find.text(_tronAddress), findsOneWidget);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(api.requestedChains, [1, -200]);
    await _close(tester);
  });

  testWidgets('unrelated or incomplete accounts do not suppress creation',
      (tester) async {
    final api = _DepositApi([
      {
        'reference': 'deposit-1-227-usdc-1',
        'chainId': 1,
        'address': 'usdc-address',
        'currencies': ['USDC'],
        'ready': true
      },
      {
        'reference': 'deposit-1-227-usdt-1',
        'chainId': -200,
        'address': 'wrong-chain',
        'currencies': <String>[],
        'ready': false
      },
      {
        'reference': 'deposit-1-227-usdt--200',
        'chainId': -200,
        'currencies': <String>[],
        'ready': false
      },
    ]);
    await _open(tester, api);
    expect(find.byKey(const ValueKey('create-usdt-1')), findsOneWidget);
    await _select(tester, 'USDT', -200);
    expect(find.byKey(const ValueKey('create-usdt--200')), findsOneWidget);
    expect(api.requestedChains, isEmpty);
    await _close(tester);
  });

  testWidgets(
      'ready response without currencies displays selected USDT address',
      (tester) async {
    final api = _DepositApi([]);
    await _open(tester, api);
    await _select(tester, 'USDT', -200);
    final button = find.byKey(const ValueKey('create-usdt--200'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text(_tronAddress), findsOneWidget);
    expect(find.text(_tronHex), findsNothing);
    expect(find.text('Copy address'), findsOneWidget);
    expect(find.textContaining('Waiting for confirmation'), findsNothing);
    expect(button, findsNothing);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(api.requestedChains, [-200]);
    expect(find.text(_tronAddress), findsOneWidget);
    await _close(tester);
  });

  testWidgets('grouped networks update QR, warning and clipboard together',
      (tester) async {
    final api = _DepositApi([
      {
        'reference': 'deposit-1-227-usdt-1',
        'chainId': 1,
        'address': 'ethereum-address',
        'currencies': ['USDC', 'USDT'],
        'ready': true
      },
      {
        'reference': 'deposit-1-227-usdt--200',
        'chainId': -200,
        'address': _tronHex,
        'currencies': ['USDC', 'USDT'],
        'ready': true
      },
      {
        'reference': 'deposit-1-227-usdc-1399811149',
        'chainId': 1399811149,
        'address': 'solana-address',
        'currencies': ['USDC'],
        'ready': true
      },
      _eur,
    ]);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await _open(tester, api);
    expect(find.byKey(const ValueKey('deposit-currency-USDC')), findsOneWidget);
    expect(find.byKey(const ValueKey('deposit-currency-USDT')), findsOneWidget);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    await _select(tester, 'USDT', -200);
    await _expectQr(tester, 'deposit-qr-USDT--200', _tronAddress);
    expect(find.text('Only send USDT on Tron (TRC20).'), findsOneWidget);
    final copy = find.byKey(const ValueKey('copy-deposit-USDT'));
    await tester.ensureVisible(copy);
    await tester.tap(copy);
    await tester.pumpAndSettle();
    expect(copied, _tronAddress);
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    await _expectQr(tester, 'deposit-qr-USDT--200', _tronAddress);
    await _select(tester, 'USDC', 1399811149);
    await _expectQr(tester, 'deposit-qr-USDC-1399811149', 'solana-address');
    expect(find.byKey(const ValueKey('deposit-qr-USDT--200')), findsOneWidget);
    // Removing a selected rail must never leave its old QR or address behind.
    api.accounts = [api.accounts.first, _eur];
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('deposit-qr-USDT--200')), findsNothing);
    expect(
        find.byKey(const ValueKey('deposit-qr-USDC-1399811149')), findsNothing);
    expect(api.requestedChains, isEmpty);
    await _close(tester);
  });

  testWidgets('pending selected network has no QR or copy action',
      (tester) async {
    await _open(
        tester,
        _DepositApi([
          {
            'reference': 'deposit-1-227-usdc-1',
            'chainId': 1,
            'address': 'ready-address',
            'currencies': ['USDC'],
            'ready': true
          },
          {
            'reference': 'deposit-1-227-usdc--200',
            'chainId': -200,
            'address': _tronHex,
            'currencies': ['USDC'],
            'ready': false
          },
        ]));
    await _select(tester, 'USDC', -200);
    expect(find.byKey(const ValueKey('copy-deposit-USDC')), findsNothing);
    expect(find.byKey(const ValueKey('deposit-qr-USDC--200')), findsNothing);
    expect(find.text(_tronAddress), findsNothing);
    await _close(tester);
  });

  testWidgets('grouped deposits fit a narrow phone screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _open(
        tester,
        _DepositApi([
          {
            'reference': 'deposit-1-227-usdt-1',
            'chainId': 1,
            'address': '0xb22fdDb960439F79d40DC7a512304c4AD0F98a30',
            'currencies': ['USDT'],
            'ready': true
          },
          {
            'reference': 'deposit-1-227-usdt--200',
            'chainId': -200,
            'address': _tronHex,
            'currencies': ['USDT'],
            'ready': true
          },
        ]));
    await _select(tester, 'USDT', -200);
    await tester.ensureVisible(find.byKey(const ValueKey('copy-deposit-USDT')));
    expect(tester.takeException(), isNull);
    expect(find.text(_tronAddress), findsOneWidget);
    await _close(tester);
  });

  testWidgets('invalid Tron address cannot be copied', (tester) async {
    await _open(
        tester,
        _DepositApi([
          {
            'reference': 'deposit-1-227-usdt--200',
            'chainId': -200,
            'address': 'invalid',
            'currencies': ['USDT'],
            'ready': true
          },
        ]));
    expect(find.text('Copy address'), findsNothing);
    expect(find.text('invalid'), findsNothing);
    await _close(tester);
  });

  testWidgets('creation failure can retry and does not hide existing deposits',
      (tester) async {
    final api = _DepositApi([_eur])..failCreation = true;
    await _open(tester, api);
    final button = find.byKey(const ValueKey('create-usdt-1'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not create'), findsOneWidget);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    api.failCreation = false;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(api.requestedChains, [1, 1]);
    expect(find.textContaining('Could not create'), findsNothing);
    await _close(tester);
  });

  testWidgets('wrong network response is never displayed', (tester) async {
    final api = _DepositApi([])
      ..issuedCurrencies = ['USDT']
      ..returnedChain = 1;
    await _open(tester, api);
    await _select(tester, 'USDT', -200);
    final button = find.byKey(const ValueKey('create-usdt--200'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not create'), findsOneWidget);
    expect(find.text('issued--200'), findsNothing);
    await _close(tester);
  });

  testWidgets('pending KYC never offers address creation', (tester) async {
    final api = _DepositApi([])..kycStatus = 'pending';
    await _open(tester, api);
    expect(find.text('Create deposit address'), findsNothing);
    expect(api.requestedChains, isEmpty);
    await _close(tester);
  });

  testWidgets('empty provider entry does not appear above issued EUR account',
      (tester) async {
    await _open(tester, _DepositApi([_placeholder, _eur]));

    expect(find.text('Deposit account'), findsNothing);
    expect(find.textContaining('not available yet'), findsNothing);
    expect(find.text('Bank transfer · SEPA'), findsOneWidget);
    expect(find.text('EUR'), findsOneWidget);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    expect(find.text('Copy IBAN'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('only empty records show preparation notice and refresh to EUR',
      (tester) async {
    final api = _DepositApi([
      _placeholder,
      {
        ..._placeholder,
        'currencies': ['  ']
      },
    ]);
    await _open(tester, api);

    expect(find.text('Deposit account'), findsNothing);
    expect(find.textContaining('being prepared'), findsOneWidget);
    api.accounts = [_placeholder, _eur];
    await tester.tap(find.text('Refresh'));
    await tester.pumpAndSettle();
    expect(find.textContaining('being prepared'), findsNothing);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('currency-specific pending accounts remain visible',
      (tester) async {
    await _open(
        tester,
        _DepositApi([
          _placeholder,
          {
            ..._placeholder,
            'currencies': ['EUR']
          },
        ]));

    expect(find.text('Deposit account'), findsNothing);
    expect(find.text('EUR'), findsOneWidget);
    expect(find.textContaining('not available yet'), findsOneWidget);
    await _close(tester);
  });

  testWidgets('issued bank details remain visible without a currency label',
      (tester) async {
    await _open(
        tester,
        _DepositApi([
          _placeholder,
          {..._eur, 'currencies': <String>[]},
        ]));

    expect(find.text('Deposit account'), findsOneWidget);
    expect(find.text('TEST-IBAN'), findsOneWidget);
    expect(find.text('Copy IBAN'), findsOneWidget);
    expect(find.textContaining('not available yet'), findsNothing);
    await _close(tester);
  });
}
