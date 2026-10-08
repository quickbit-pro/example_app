import 'dart:async';
import 'dart:typed_data';
import 'package:mobile_flutter/shared/widgets/safeguarding_statement.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/models/equals_money.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';

void main() {
  testWidgets(
      'Conversion starts with the requested budget instead of the first',
      (tester) async {
    await _openConversion(tester, _ConversionAdapter(),
        budgets: const [_mainBalance, _travelBalance],
        initialBudgetId: 'travel');
    final budgets = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .where((w) => w.items!.any((item) => item.value == 'travel'));
    expect(budgets.single.value, 'travel');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Max fills available funds and locks while quoting',
      (tester) async {
    final adapter = _ControlledAdapter();
    await _openConversion(tester, adapter);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '47.92');
    await tester.tap(find.text('Get live quote'));
    await tester.pump();
    final maxButton = find.widgetWithText(TextButton, 'Max');
    expect(tester.widget<TextButton>(maxButton).onPressed, isNull);
    adapter.pending.complete(_validQuote());
    await tester.pumpAndSettle();
    expect(find.text('Confirm conversion'), findsOneWidget);
    expect(tester.widget<TextButton>(maxButton).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('To offers every Equals currency while From stays funded',
      (tester) async {
    await _openConversion(tester, _ConversionAdapter());
    final dropdowns = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .toList();
    final source = dropdowns.first;
    final target = dropdowns.last;
    expect(source.items!.map((item) => item.value), ['EUR']);
    final choices = target.items!.map((item) => item.value).toSet();
    expect(choices, equalsSupportedCurrencyCodes.toSet()..remove('EUR'));
    expect(target.value, 'RON');
    target.onChanged!('CNY');
    await tester.pumpAndSettle();
    expect(
        tester
            .widgetList<DropdownButton<String>>(
                find.byType(DropdownButton<String>))
            .last
            .value,
        'CNY');
    expect(tester.takeException(), isNull);
  });

  test(
      'a funded single-currency account can convert to another Equals currency',
      () {
    const single = PlatformResource(
        id: 'equals-single',
        title: 'Account balance',
        subtitle: 'GBP',
        metadata: {
          'accountId': 'equals-single',
          'parentAccountId': 'parent',
          'supportedCurrencies': ['GBP'],
          'balances': [
            {'currency': 'GBP', 'amount': '20'}
          ],
        });
    expect(canConvertEqualsMoneyBudgets([single]), isTrue);
  });

  testWidgets('conversion survives the launching widget being disposed',
      (tester) async {
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    final adapter = _ConversionAdapter();
    await _openConversion(tester, adapter, launcherVisible: visible);
    visible.value = false;
    await tester.pump();
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Get live quote'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm conversion'), findsOneWidget);
    await tester.tap(find.text('Confirm conversion'));
    await tester.pumpAndSettle();
    expect(adapter.requestCount, 2);
    expect(find.text('Conversion completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quote failure can be retried without losing the amount',
      (tester) async {
    final adapter = _ControlledAdapter();
    await _openConversion(tester, adapter);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Get live quote'));
    await tester.pump();
    adapter.pending.complete(ResponseBody.fromString('{}', 503));
    await tester.pumpAndSettle();
    expect(
        find.text('The service is temporarily unavailable. Try again shortly.'),
        findsOneWidget);
    expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text, '1');
    adapter.pending = Completer<ResponseBody>();
    await tester.tap(find.text('Get live quote'));
    await tester.pump();
    adapter.pending.complete(_validQuote());
    await tester.pumpAndSettle();
    expect(find.text('Confirm conversion'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('late quote response after route removal is ignored',
      (tester) async {
    final adapter = _ControlledAdapter();
    await _openConversion(tester, adapter);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Get live quote'));
    await tester.pump();
    final context = tester.element(find.byType(TextField));
    Navigator.of(context).removeRoute(ModalRoute.of(context)!);
    await tester.pumpAndSettle();
    adapter.pending.complete(_validQuote());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'single account is a label and multiple budgets remain selectable',
      (tester) async {
    await _openConversion(tester, _ConversionAdapter());
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(2));
    expect(find.text('Account balance'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await _openConversion(tester, _ConversionAdapter(),
        budgets: [_mainBalance, _travelBalance]);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));
    await tester.tap(find.text('Account balance'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel budget').last);
    await tester.pumpAndSettle();
    expect(find.text('Travel budget'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('incomplete quote stays retryable and cannot be confirmed',
      (tester) async {
    final adapter = _ControlledAdapter();
    await _openConversion(tester, adapter);
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Get live quote'));
    await tester.pump();
    // System back must not detach the form during a request.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);
    adapter.pending.complete(ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    }));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'We could not retrieve a valid conversion quote. Please try again.'),
        findsOneWidget);
    expect(find.text('Get live quote'), findsOneWidget);
    expect(find.text('Confirm conversion'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('main Equals account balance is available for conversion', () {
    const mainBalance = PlatformResource(
      id: 'equals-main',
      title: 'Account balance',
      subtitle: 'GBP',
      metadata: {
        'accountId': 'equals-main',
        'parentAccountId': 'equals-parent',
        'displayName': 'Account balance',
        'supportedCurrencies': ['GBP', 'EUR'],
        'balances': [
          {'currency': 'GBP', 'amount': '377.00'},
        ],
      },
    );

    expect(canConvertEqualsMoneyBudgets([mainBalance]), isTrue);
  });

  test('does not offer resources from another provider', () {
    const interlaceBalance = PlatformResource(
      id: 'interlace-main',
      title: 'Account balance',
      subtitle: 'USD',
      metadata: {
        'accountId': 'interlace-main',
        'provider': 'Interlace',
        'supportedCurrencies': ['EUR', 'USD'],
        'balances': [
          {'currency': 'USD', 'amount': '20.00'},
        ],
      },
    );

    expect(canConvertEqualsMoneyBudgets([interlaceBalance]), isFalse);
  });

  testWidgets('confirming a conversion closes without disposing fields early',
      (tester) async {
    const mainBalance = PlatformResource(
      id: 'equals-main',
      title: 'Account balance',
      subtitle: 'GBP',
      metadata: {
        'accountId': 'equals-main',
        'parentAccountId': 'equals-parent',
        'displayName': 'Account balance',
        'supportedCurrencies': ['GBP', 'EUR'],
        'balances': [
          {'currency': 'GBP', 'amount': '377.00'},
        ],
      },
    );
    final dio = Dio()..httpClientAdapter = _ConversionAdapter();
    var recentLoads = 0;
    var activityLoads = 0;
    var accountLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileTenantConfigProvider.overrideWith((ref) async => _config),
          mobilePlatformApiProvider.overrideWithValue(MobilePlatformApi(dio)),
          transactionsProvider.overrideWith((ref) async {
            recentLoads++;
            return const [];
          }),
          activityTransactionsProvider.overrideWith((ref) async {
            activityLoads++;
            return const [];
          }),
          activityAccountTransactionsProvider.overrideWith((ref, id) async {
            accountLoads++;
            return const [];
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, child) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showEqualsMoneyConversionDialog(
                    context,
                    ref,
                    const [mainBalance],
                  ),
                  child: const Text('Convert'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(Consumer)),
      listen: false,
    );
    await container.read(transactionsProvider.future);
    await container.read(activityTransactionsProvider.future);
    await container
        .read(activityAccountTransactionsProvider('equals-main').future);

    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '1');
    await tester.tap(find.text('Get live quote'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirm conversion'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Conversion completed'), findsOneWidget);
    await container.read(transactionsProvider.future);
    await container.read(activityTransactionsProvider.future);
    await container
        .read(activityAccountTransactionsProvider('equals-main').future);
    expect([recentLoads, activityLoads, accountLoads], [2, 2, 2],
        reason: 'A completed FX conversion refreshes cached account activity.');
  });

  testWidgets('EXAMPLE Equals conversion uses the Exchange page composition',
      (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const mainBalance = PlatformResource(
      id: 'equals-main',
      title: 'Account balance',
      subtitle: 'GBP',
      metadata: {
        'accountId': 'equals-main',
        'parentAccountId': 'equals-parent',
        'displayName': 'Account balance',
        'supportedCurrencies': ['GBP', 'EUR'],
        'balances': [
          {'currency': 'GBP', 'amount': '377.00'},
          {'currency': 'EUR', 'amount': '42.00'},
        ],
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileTenantConfigProvider.overrideWith((ref) async => _config)
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            scaffoldBackgroundColor: ExampleColors.appBackground,
          ),
          home: Consumer(
            builder: (context, ref, child) => Scaffold(
              body: FilledButton(
                onPressed: () => showEqualsMoneyConversionDialog(
                  context,
                  ref,
                  const [mainBalance],
                ),
                child: const Text('Convert'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Convert'));
    await tester.pumpAndSettle();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Rate'), findsOneWidget);
    expect(find.text('Fee'), findsOneWidget);
    expect(find.text('Estimate'), findsOneWidget);
    expect(find.text('Review conversion'), findsOneWidget);
    expect(find.text('Fiat account'), findsNWidgets(2));
    expect(find.text('Safeguarding statement'), findsOneWidget);
    final swap = tester.getRect(find.byTooltip('Swap currencies'));
    final from = tester.getRect(find
        .ancestor(of: find.text('From'), matching: find.byType(Container))
        .first);
    final to = tester.getRect(find
        .ancestor(of: find.text('To'), matching: find.byType(Container))
        .first);
    expect(swap.top, greaterThanOrEqualTo(from.bottom));
    expect(swap.bottom, lessThanOrEqualTo(to.top));
    expect(swap.height, greaterThanOrEqualTo(44));
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '42.0');
    await tester.tap(find.byTooltip('Swap currencies'));
    await tester.pumpAndSettle();
    final currencies = tester
        .widgetList<DropdownButton<String>>(find.byType(DropdownButton<String>))
        .map((dropdown) => dropdown.value)
        .toList();
    // Balances are ordered by value, so the larger GBP balance leads.
    expect(currencies, ['GBP', 'EUR']);
    await tester.tap(find.text('Max'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '377.0');
    final statementButton = find.text('Safeguarding statement');
    final statement = ProviderScope.containerOf(tester.element(statementButton))
        .read(safeguardingStatementProvider);
    await tester.ensureVisible(statementButton);
    await tester.tap(statementButton);
    await tester.pumpAndSettle();
    expect(find.text(statement), findsOneWidget);
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    expect(find.text('Review conversion'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });
}

class _ConversionAdapter implements HttpClientAdapter {
  var requestCount = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    final body = requestCount == 1
        ? '{"orderId":"order-1","quoteRequestId":"quote-1"}'
        : '{"orderId":"trade-1"}';
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

const _mainBalance = PlatformResource(
  id: 'main',
  title: 'Account balance',
  subtitle: 'EUR',
  metadata: {
    'budgetId': 'main',
    'parentAccountId': 'owner',
    'balances': [
      {'currency': 'EUR', 'amount': 47.92}
    ],
    'supportedCurrencies': ['EUR', 'RON'],
  },
);
const _travelBalance = PlatformResource(
  id: 'travel',
  title: 'Travel budget',
  subtitle: 'EUR',
  metadata: {
    'budgetId': 'travel',
    'parentAccountId': 'owner',
    'balances': [
      {'currency': 'EUR', 'amount': 20}
    ],
    'supportedCurrencies': ['EUR', 'RON'],
  },
);

Future<void> _openConversion(
  WidgetTester tester,
  HttpClientAdapter adapter, {
  ValueNotifier<bool>? launcherVisible,
  List<PlatformResource> budgets = const [_mainBalance],
  String initialBudgetId = '',
}) async {
  final api = MobilePlatformApi(Dio()..httpClientAdapter = adapter);
  Widget launcher() => Consumer(
      builder: (context, ref, _) => FilledButton(
            onPressed: () => showEqualsMoneyConversionDialog(
                context, ref, budgets,
                initialBudgetId: initialBudgetId),
            child: const Text('Convert'),
          ));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mobilePlatformApiProvider.overrideWithValue(api),
      mobileTenantConfigProvider.overrideWith((ref) async => _config),
    ],
    child: MaterialApp(
      home: Scaffold(
          body: launcherVisible == null
              ? launcher()
              : ValueListenableBuilder<bool>(
                  valueListenable: launcherVisible,
                  builder: (_, visible, __) =>
                      visible ? launcher() : const SizedBox())),
    ),
  ));
  await tester.tap(find.text('Convert'));
  await tester.pumpAndSettle();
}

ResponseBody _validQuote() => ResponseBody.fromString(
      '{"orderId":"order-1","quoteRequestId":"quote-1"}',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

class _ControlledAdapter implements HttpClientAdapter {
  Completer<ResponseBody> pending = Completer<ResponseBody>();
  @override
  void close({bool force = false}) {}
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) =>
      pending.future;
}

const _config = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: false,
  referralRegistrationMode: 'code',
  vouchersEnabled: false,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);
