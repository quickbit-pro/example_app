import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf_export_button.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/wallets_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _budgetId = 'actual-budget';
const _eurIban = 'BE68539007541234';
const _ronIban = 'RO49AAAA1B31007593845678';
const _swift = 'BBRUBEBB';
const _holder = 'Account Holder';
const _bank = 'Receiving Bank';

const _budget = PlatformResource(
  id: _budgetId,
  title: 'Account balance',
  subtitle: 'EUR',
  metadata: {
    'budgetId': _budgetId,
    'accountId': 'actual-owner',
    'displayName': 'Account balance',
    'supportedCurrencies': ['EUR', 'RON'],
    // RON sorts before EUR by raw amount. Selecting EUR must still open EUR.
    'balances': [
      {'currency': 'EUR', 'amount': '42.18'},
      {'currency': 'RON', 'amount': '930.25'},
    ],
  },
);

PlatformResource _receivingInfo({
  required String currency,
  required String iban,
  bool linked = true,
}) =>
    PlatformResource(
      id: 'receiving-$currency',
      title: 'Receiving account',
      subtitle: currency,
      metadata: {
        if (linked) 'budgetId': _budgetId,
        'currency': currency,
        'userName': _holder,
        'bankName': _bank,
        'routingCodes': [
          {'routingCodeType': 'IBAN', 'routingCodeValue': iban},
          {'routingCodeType': 'SWIFT_CODE', 'routingCodeValue': _swift},
        ],
      },
    );

List<PlatformResource> get _linkedInfo => [
      _receivingInfo(currency: 'RON', iban: _ronIban),
      _receivingInfo(currency: 'EUR', iban: _eurIban),
    ];

final _history = [
  LedgerTransaction.fromJson({
    'id': 'fx-eur-credit',
    'title': 'EUR conversion credit',
    'type': 'transfer_in',
    'currency': 'EUR',
    'amount': 12.18,
    'budgetId': _budgetId,
    'accountId': 'actual-owner',
    'status': 'completed',
    'bookedAt': '2026-09-06T08:00:00Z',
  }),
  LedgerTransaction.fromJson({
    'id': 'fx-ron-debit',
    'title': 'RON conversion debit',
    'type': 'transfer_out',
    'currency': 'RON',
    'amount': 60,
    'budgetId': _budgetId,
    'accountId': 'actual-owner',
    'status': 'completed',
    'bookedAt': '2026-09-06T08:00:00Z',
  }),
  LedgerTransaction.fromJson({
    'id': 'other-account-eur',
    'title': 'Another account credit',
    'type': 'transfer_in',
    'currency': 'EUR',
    'amount': 777,
    'budgetId': 'other-budget',
    'accountId': 'other-owner',
    'status': 'completed',
    'bookedAt': '2026-09-06T09:00:00Z',
  }),
  LedgerTransaction.fromJson({
    'id': 'sibling-budget-eur',
    'title': 'Sibling budget credit',
    'type': 'transfer_in',
    'currency': 'EUR',
    'amount': 555,
    'budgetId': 'sibling-budget',
    'accountId': 'actual-owner',
    'status': 'completed',
    'bookedAt': '2026-09-06T09:30:00Z',
  }),
];

Future<void> _loadFonts() async {
  const fonts = <String, List<String>>{
    'Geist': [
      'Geist-Regular.ttf',
      'Geist-Medium.ttf',
      'Geist-SemiBold.ttf',
      'Geist-Bold.ttf',
    ],
    'GeistMono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
  };
  for (final entry in fonts.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      final bytes = File('assets/fonts/$name').readAsBytesSync();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

Future<void> _pumpAccounts(
  WidgetTester tester, {
  String initialCurrency = '',
  String initialBudgetId = '',
  double width = 393,
  List<PlatformResource>? bankingInfo,
  List<LedgerTransaction>? history,
  Future<List<LedgerTransaction>>? historyFuture,
  Future<List<LedgerTransaction>> Function()? historyLoader,
  Future<List<PlatformResource>> Function()? budgetLoader,
  GoRouter? router,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final themes = buildAppThemes(const AppBranding(
    appName: 'EXAMPLE',
    brandId: 'example',
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: 'dark',
    fontFamily: '',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: 'support@example.com',
    supportPhone: '',
    legalEntity: 'EXAMPLE',
  ));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        mobileTenantConfigProvider.overrideWith(
          (ref) async => MobileTenantConfig.fromJson(const {
            'company': {'name': 'Example'},
            'features': {
              'equalsMoneyEnabled': true,
              'boomFiExchangeEnabled': true,
              'walletOutflowsEnabled': true,
            },
          }),
        ),
        dashboardProvider.overrideWith(
          (ref) => Completer<DashboardSnapshot>().future,
        ),
        hoppaWalletAssetsProvider.overrideWith((ref) async => const []),
        hoppaWalletAddressesProvider.overrideWith((ref) async => const []),
        hoppaWalletBalancesProvider.overrideWith((ref) async => const []),
        budgetsProvider.overrideWith((ref) async =>
            budgetLoader == null ? const [_budget] : budgetLoader()),
        equalsBankingInfoProvider.overrideWith(
          (ref) async => bankingInfo ?? _linkedInfo,
        ),
        exchangeTransfersProvider.overrideWith((ref) async => const []),
        exchangeOverviewProvider.overrideWith(
          (ref) => Completer<BoomFiExchangeOverview>().future,
        ),
        // The bounded Home feed intentionally has no rows. Account details
        // must read complete Activity history to find these conversion legs.
        transactionsProvider.overrideWith((ref) async => const []),
        activityTransactionsProvider.overrideWith(
          (ref) =>
              historyLoader?.call() ??
              historyFuture ??
              Future.value(history ?? _history),
        ),
        accountsProvider.overrideWith((ref) async => const []),
        cardsProvider.overrideWith((ref) async => const []),
      ],
      child: router != null
          ? MaterialApp.router(
              routerConfig: router,
              theme: themes.dark,
              builder: (context, navigator) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: ExampleSheenScope(child: navigator!),
              ),
            )
          : MaterialApp(
              theme: themes.dark,
              builder: (context, navigator) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: ExampleSheenScope(child: navigator!),
              ),
              home: Scaffold(
                body: WalletsScreen(
                  initialView: WalletView.balances,
                  embedded: true,
                  initialBudgetId: initialBudgetId,
                  initialCurrency: initialCurrency,
                ),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

GoRouter _accountsRouter({required String currency}) => GoRouter(
      initialLocation: '/wallets',
      routes: [
        // The real app places pages in a shell navigator, while budget
        // dialogs sit on the root navigator. Cover that same arrangement.
        ShellRoute(
          builder: (context, state, child) => Scaffold(body: child),
          routes: [
            GoRoute(
              path: '/wallets',
              builder: (context, state) => WalletsScreen(
                initialView: WalletView.balances,
                embedded: true,
                initialBudgetId: _budgetId,
                initialCurrency: currency,
              ),
            ),
            GoRoute(
              path: '/transactions',
              builder: (context, state) => TransactionsScreen(
                budgetId: state.uri.queryParameters['budgetId'] ?? '',
                currency: state.uri.queryParameters['currency'] ?? '',
                accountName: state.uri.queryParameters['accountName'] ?? '',
              ),
            ),
            GoRoute(
              path: '/transactions/:id',
              builder: (context, state) => TransactionDetailScreen(
                transactionId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
      ],
    );

Finder _inDialog(Finder matching) => find.descendant(
      of: find.byType(Dialog),
      matching: matching,
    );

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void _expectSelectedCurrency(String currency) {
  final euro = currency == 'EUR';
  final title = euro ? 'Euro Account · BE***1234' : 'RON Account · RO***5678';
  expect(_inDialog(find.text(title)), findsOneWidget);
  expect(
    _inDialog(find.text(Money.formatAmount(currency, euro ? 42.18 : 930.25))),
    findsOneWidget,
  );
  expect(
    _inDialog(find
        .text(Money.formatAmount(euro ? 'RON' : 'EUR', euro ? 930.25 : 42.18))),
    findsNothing,
  );
  expect(_inDialog(find.textContaining('Main')), findsNothing);
}

void main() {
  for (final width in [320.0, 1000.0]) {
    for (final currency in ['EUR', 'RON']) {
      testWidgets('Account Convert keeps $currency selected at width $width',
          (tester) async {
        await _pumpAccounts(tester,
            width: width,
            initialBudgetId: _budgetId,
            initialCurrency: currency);
        final buttons = ['Move', 'Convert', 'New transaction']
            .map((label) =>
                _inDialog(find.widgetWithText(OutlinedButton, label)))
            .toList();
        for (final button in buttons) {
          expect(button, findsOneWidget);
        }
        final rectangles = buttons.map(tester.getRect).toList();
        expect(rectangles.map((r) => r.top).toSet(), hasLength(1));
        expect(rectangles.map((r) => r.height).toSet(), {48.0});
        await _tapVisible(tester, _inDialog(find.text('Convert')));
        final values = tester
            .widgetList<DropdownButton<String>>(
                find.byType(DropdownButton<String>))
            .map((w) => w.value)
            .toList();
        // A single account is a label; the dropdowns are From and To.
        expect(values.first, currency);
        expect(values.last, isNot(currency));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('manual refresh updates balance in an already open budget',
      (tester) async {
    var amount = '42.18';
    var reads = 0;
    await _pumpAccounts(tester,
        initialBudgetId: _budgetId,
        initialCurrency: 'EUR', budgetLoader: () async {
      reads++;
      return [
        PlatformResource(
            id: _budget.id,
            title: _budget.title,
            subtitle: _budget.subtitle,
            metadata: {
              ..._budget.metadata,
              'balances': [
                {'currency': 'EUR', 'amount': amount}
              ]
            })
      ];
    });
    expect(
        _inDialog(find.text(Money.formatAmount('EUR', 42.18))), findsOneWidget);
    final before = reads;
    amount = '19.25';
    await _tapVisible(tester, _inDialog(find.byTooltip('Refresh')));
    expect(reads, greaterThan(before));
    await tester.drag(
        _inDialog(find.byType(ListView)).first, const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(
        _inDialog(find.text(Money.formatAmount('EUR', 19.25))), findsOneWidget);
    expect(
        _inDialog(find.text(Money.formatAmount('EUR', 42.18))), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  testWidgets('RON displays the same IBAN as its EUR account', (tester) async {
    await _pumpAccounts(tester,
        bankingInfo: [
          _receivingInfo(currency: 'EUR', iban: _eurIban),
        ],
        initialBudgetId: _budgetId,
        initialCurrency: 'RON');
    expect(_inDialog(find.text('RON Account · BE***1234')), findsOneWidget);
    expect(_inDialog(find.text(_eurIban)), findsOneWidget);
    expect(_inDialog(find.text(_swift)), findsOneWidget);
    expect(_inDialog(find.text(_holder)), findsOneWidget);
    expect(_inDialog(find.text('Receiving details unavailable')), findsNothing);
    await tester.drag(
        _inDialog(find.byType(ListView)).first, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text('Safeguarding statement')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EUR and RON account actions open their own balance and identity',
      (tester) async {
    await _pumpAccounts(tester);
    for (final currency in ['EUR', 'RON']) {
      final title = currency == 'EUR'
          ? 'Euro Account · BE***1234'
          : 'RON Account · RO***5678';
      final card = find
          .ancestor(
            of: find.text(title),
            matching: find.byType(ExampleGlassPanel),
          )
          .first;
      final details = find.descendant(
        of: card,
        matching: find.text('Account details'),
      );
      await _tapVisible(tester, details);
      _expectSelectedCurrency(currency);
      await tester.tap(_inDialog(find.byTooltip('Back')));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  for (final currency in ['EUR', 'RON']) {
    testWidgets(
        'initial $currency navigation opens the matching account details',
        (tester) async {
      await _pumpAccounts(
        tester,
        initialBudgetId: _budgetId,
        initialCurrency: currency,
      );
      expect(find.byType(Dialog), findsOneWidget);
      _expectSelectedCurrency(currency);
    });
  }

  testWidgets(
      'opening details replaces cached empty history and polls deposits',
      (tester) async {
    var rows = <LedgerTransaction>[];
    var requests = 0;
    await _pumpAccounts(tester, historyLoader: () async {
      requests++;
      return List.of(rows);
    });
    final container =
        ProviderScope.containerOf(tester.element(find.byType(WalletsScreen)));
    await container.read(activityTransactionsProvider.future);
    rows = [_history.first];
    final card = find
        .ancestor(
          of: find.text('Euro Account · BE***1234'),
          matching: find.byType(ExampleGlassPanel),
        )
        .first;
    await _tapVisible(tester,
        find.descendant(of: card, matching: find.text('Account details')));
    expect(_inDialog(find.text('EUR conversion credit')), findsOneWidget);
    expect(requests, greaterThan(1));
    rows = [
      LedgerTransaction.fromJson({
        'id': 'new-deposit',
        'title': 'New incoming deposit',
        'type': 'transfer_in',
        'currency': 'EUR',
        'amount': 2,
        'budgetId': _budgetId,
        'accountId': 'actual-owner',
        'status': 'completed',
        'bookedAt': '2026-09-09T14:00:00Z',
      }),
      ...rows
    ];
    await tester.pump(const Duration(seconds: 30));
    await tester.pumpAndSettle();
    expect(_inDialog(find.text('New incoming deposit')), findsOneWidget);
    await tester.tap(_inDialog(find.byTooltip('Back')));
    await tester.pumpAndSettle();
    final afterClose = requests;
    await tester.pump(const Duration(seconds: 30));
    expect(requests, afterClose);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account details show scoped FX credit from full Activity history',
      (tester) async {
    await _pumpAccounts(
      tester,
      initialBudgetId: _budgetId,
      initialCurrency: 'EUR',
    );
    expect(_inDialog(find.text('EUR conversion credit')), findsOneWidget);
    expect(_inDialog(find.text('RON conversion debit')), findsNothing);
    expect(_inDialog(find.text('Another account credit')), findsNothing);
    expect(_inDialog(find.text('Sibling budget credit')), findsNothing);
    expect(_inDialog(find.text('No transactions yet')), findsNothing);
    expect(
      _inDialog(find.text('+${Money.formatAmount('EUR', 12.18)}')),
      findsOneWidget,
    );
    expect(
      _inDialog(find.text('Account BE***1234')),
      findsOneWidget,
    );
    final timestamp = tester.widget<Text>(
      find.byKey(const ValueKey('budget-transaction-time-fx-eur-credit')),
    );
    final localizations = MaterialLocalizations.of(
      tester.element(find.byType(Dialog)),
    );
    final bookedAt = _history.first.bookedAt.toLocal();
    expect(
      timestamp.data,
      '${localizations.formatMediumDate(bookedAt)} · '
      '${localizations.formatTimeOfDay(TimeOfDay.fromDateTime(bookedAt), alwaysUse24HourFormat: true)}',
    );
  });

  testWidgets('account history does not invent missing dates or identities',
      (tester) async {
    await _pumpAccounts(
      tester,
      initialBudgetId: _budgetId,
      initialCurrency: 'EUR',
      bankingInfo: const [],
      history: [
        LedgerTransaction.fromJson({
          'id': 'undated-credit',
          'title': 'Credit without timestamp',
          'type': 'transfer_in',
          'currency': 'EUR',
          'amount': 12.18,
          'budgetId': _budgetId,
          'status': 'completed',
        }),
      ],
    );
    expect(
      _inDialog(find.text('Date and time unavailable')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('budget-transaction-identity-undated-credit')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  for (final currency in ['EUR', 'RON']) {
    testWidgets('More leaves the dialog and opens exact $currency history',
        (tester) async {
      final router = _accountsRouter(currency: currency);
      addTearDown(router.dispose);
      await _pumpAccounts(tester, router: router);
      expect(find.byType(Dialog), findsOneWidget);
      await _tapVisible(tester, _inDialog(find.text('More')));

      expect(find.byType(Dialog), findsNothing);
      final activity = tester.widget<TransactionsScreen>(
        find.byType(TransactionsScreen),
      );
      expect(activity.budgetId, _budgetId);
      expect(activity.currency, currency);
      expect(activity.accountId, isEmpty);
      final export = tester.widget<TransactionPdfExportButton>(
        find.byType(TransactionPdfExportButton),
      );
      expect(export.transactions!.map((row) => row.id), [
        currency == 'EUR' ? 'fx-eur-credit' : 'fx-ron-debit',
      ]);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.byType(WalletsScreen), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a recent transaction opens its receipt above account history',
      (tester) async {
    final router = _accountsRouter(currency: 'EUR');
    addTearDown(router.dispose);
    await _pumpAccounts(tester, router: router);
    await _tapVisible(tester, _inDialog(find.text('EUR conversion credit')));
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(TransactionDetailScreen), findsOneWidget);
    final receipt = tester.widget<TransactionPdfExportButton>(
      find.byType(TransactionPdfExportButton),
    );
    expect(receipt.receipt, isTrue);
    expect(receipt.transactions!.single.id, 'fx-eur-credit');
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest PDF contains only displayed budget and currency rows',
      (tester) async {
    final history = [
      ..._history,
      for (var index = 0; index < 6; index++)
        LedgerTransaction.fromJson({
          'id': 'older-eur-$index',
          'title': 'Older EUR credit $index',
          'type': 'transfer_in',
          'currency': 'EUR',
          'amount': '${index + 1}.25',
          'budgetId': _budgetId,
          'bookedAt': '2026-09-05T0$index:00:00Z',
        }),
    ];
    await _pumpAccounts(
      tester,
      initialBudgetId: _budgetId,
      initialCurrency: 'EUR',
      history: history,
    );
    final export = tester.widget<TransactionPdfExportButton>(
      find.byKey(const ValueKey('budget-latest-transactions-export')),
    );
    expect(export.transactions!.map((row) => row.id), [
      'fx-eur-credit',
      'older-eur-5',
      'older-eur-4',
      'older-eur-3',
      'older-eur-2',
    ]);
    expect(_inDialog(find.text('Older EUR credit 1')), findsNothing);
    final snapshot = TransactionPdfSnapshot(
      transactions: export.transactions!,
      filters: export.filters,
      identityFor: export.identityFor,
    );
    expect(snapshot.rows.map((row) => row.identity),
        everyElement('Account BE***1234'));
    expect(snapshot.rows.first.amount, '+€12.18 EUR');
    expect(snapshot.filters, contains('Currency: EUR'));
    expect(snapshot.filters, contains('Latest transactions shown'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest PDF remains disabled while history is loading or empty',
      (tester) async {
    final history = Completer<List<LedgerTransaction>>();
    await _pumpAccounts(
      tester,
      initialBudgetId: _budgetId,
      initialCurrency: 'EUR',
      historyFuture: history.future,
    );
    final button = find.descendant(
      of: find.byKey(const ValueKey('budget-latest-transactions-export')),
      matching: find.byType(TextButton),
    );
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    history.complete(const []);
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'unbound bank info never supplies an account identity or copy data',
      (tester) async {
    await _pumpAccounts(
      tester,
      initialBudgetId: _budgetId,
      initialCurrency: 'EUR',
      bankingInfo: [
        _receivingInfo(currency: 'EUR', iban: _eurIban, linked: false),
      ],
    );
    expect(_inDialog(find.text('Euro Account')), findsOneWidget);
    expect(find.textContaining('BE***1234'), findsNothing);
    expect(find.text(_eurIban), findsNothing);
    await tester
        .ensureVisible(_inDialog(find.text('Receiving details unavailable')));
    await tester.pumpAndSettle();
    expect(
        _inDialog(find.text('Receiving details unavailable')), findsOneWidget);
    expect(_inDialog(find.byTooltip('Copy IBAN')), findsNothing);
    expect(_inDialog(find.text('Copy all')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final width in [393.0, 1024.0]) {
    testWidgets('receiving fields and Copy all copy API values at width $width',
        (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await _pumpAccounts(
        tester,
        initialBudgetId: _budgetId,
        initialCurrency: 'EUR',
        width: width,
      );

      for (final field in const {
        'IBAN': _eurIban,
        'SWIFT/BIC': _swift,
        'Account holder': _holder,
      }.entries) {
        await _tapVisible(
            tester, _inDialog(find.byTooltip('Copy ${field.key}')));
        expect(copied.last, field.value);
      }
      final copyAll = _inDialog(find.widgetWithText(TextButton, 'Copy all'));
      await _tapVisible(tester, copyAll);
      expect(copied, [
        _eurIban,
        _swift,
        _holder,
        'Fiat account details\n'
            'IBAN: $_eurIban\n'
            'SWIFT/BIC: $_swift\n'
            'Account holder: $_holder\n'
            'Bank: $_bank',
      ]);
      final qr = _inDialog(find.byTooltip('Show account QR'));
      expect(qr, findsOneWidget);
      expect(
        (tester.getCenter(copyAll).dy - tester.getCenter(qr).dy).abs(),
        lessThan(2),
        reason: 'Copy all remains beside the account QR control.',
      );
      expect(tester.takeException(), isNull);
    });
  }
}
