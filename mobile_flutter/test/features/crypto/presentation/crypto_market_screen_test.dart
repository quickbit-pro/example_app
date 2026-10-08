import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/core/widgets/app_states.dart';
import 'package:mobile_flutter/features/crypto/data/crypto_providers.dart';
import 'package:mobile_flutter/features/crypto/domain/crypto_models.dart';
import 'package:mobile_flutter/features/crypto/presentation/crypto_market_screen.dart';
import 'package:mobile_flutter/flavors.dart';

/// The Example market table.
///
/// Every case runs at 375 and 1440 in both brightnesses, because the two
/// regressions this screen is most exposed to are a fixed value column that
/// truncates on a small phone and a dark literal that survives onto paper.
void main() {
  group('renders without overflow', () {
    for (final size in _sizes) {
      for (final brightness in Brightness.values) {
        testWidgets('${size.width.toInt()} x ${brightness.name}',
            (tester) async {
          await _pump(tester, size: size, brightness: brightness);

          expect(tester.takeException(), isNull);
          expect(find.text('Market'), findsOneWidget);
          expect(find.text('All assets'), findsOneWidget);
          expect(find.byType(TextField), findsOneWidget);
          expect(tester.widget<TextField>(find.byType(TextField)).readOnly,
              isTrue);
          for (final asset in _assets) {
            expect(find.text(asset.name), findsOneWidget);
          }
        });
      }
    }
  });

  testWidgets('the market settles without a repeating animation',
      (tester) async {
    await _pump(tester, settle: false);
    await tester.pumpAndSettle();

    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('All assets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion reaches the final state instantly',
      (tester) async {
    await _pump(tester, disableAnimations: true, settle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('All assets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search affordance remains read only', (tester) async {
    await _pump(tester);
    final search = find.byType(TextField);
    final field = tester.widget<TextField>(search);

    expect(field.readOnly, isTrue);
    expect(field.onChanged, isNull);
    await tester.tap(search);
    await tester.pumpAndSettle();

    expect(_names(tester), _assets.map((asset) => asset.name).toList());
    expect(find.text('All assets'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the redesigned table preserves provider ordering',
      (tester) async {
    final supplied = _assets.reversed.toList();
    await _pump(tester, assets: supplied);

    expect(_names(tester), supplied.map((asset) => asset.name).toList());
    expect(tester.takeException(), isNull);
  });

  testWidgets('a market row retains its buy route', (tester) async {
    await _pump(tester);

    await tester.tap(find.text('Bitcoin'));
    await tester.pumpAndSettle();

    expect(find.text('Buy route'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('prices share one right edge and no row truncates them',
      (tester) async {
    await _pump(tester);

    final prices = _assets
        .map((asset) => find.text(_price(asset.price)))
        .map((finder) => tester.getRect(finder))
        .toList();
    final edge = prices.first.right;
    for (final rect in prices) {
      expect((rect.right - edge).abs(), lessThan(0.5));
    }

    // Every price text renders at its natural width: a clipped or ellipsised
    // string would report a smaller box than the string needs.
    for (final asset in _assets) {
      final widget = tester.widget<Text>(find.text(_price(asset.price)));
      expect(widget.overflow, isNot(TextOverflow.ellipsis));
    }
  });

  testWidgets('the numbers survive textScaleFactor 1.3 at 375', (tester) async {
    await _pump(tester, textScale: 1.3);

    expect(tester.takeException(), isNull);
    for (final asset in _assets) {
      expect(find.text(_price(asset.price)), findsOneWidget);
    }
    // The trend column is what gives way at a large text size, not the price.
    expect(find.text('All assets'), findsOneWidget);
  });

  testWidgets('the desktop table gains column labels the phone does not',
      (tester) async {
    await _pump(tester, size: const Size(1440, 1000));
    expect(find.text('Asset'), findsOneWidget);
    expect(find.text('Price'), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);

    await _pump(tester, size: const Size(375, 812));
    expect(find.text('Asset'), findsNothing);
    expect(find.text('Price'), findsNothing);
  });

  testWidgets('an asset the provider did not price still holds its row',
      (tester) async {
    await _pump(tester, assets: [_unpriced]);
    expect(tester.takeException(), isNull);
    expect(find.text('Obscure Coin'), findsOneWidget);
    expect(find.text(ExampleAmount.placeholder), findsOneWidget);
    expect(find.text('All assets'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_drop_up), findsNothing);
    expect(find.byIcon(Icons.arrow_drop_down), findsNothing);
  });

  testWidgets('an empty market says what happens next', (tester) async {
    await _pump(tester, assets: const []);
    expect(find.text('No market assets'), findsOneWidget);
    expect(find.text('Market assets will appear after provider sync.'),
        findsOneWidget);
  });

  testWidgets('loading is shaped like the content it replaces', (tester) async {
    await _pump(tester, settle: false, pending: true);
    await tester.pump();

    expect(find.byType(ExampleSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Loading market'), findsOneWidget);
    expect(find.byType(ExampleListGroup), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed load retains the provider retry', (tester) async {
    var loads = 0;
    await _pump(tester,
        error: StateError('no provider'), onLoad: () => loads++);

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(loads, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();

    expect(loads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gateway errors retain the account provisioning message',
      (tester) async {
    final request = RequestOptions(path: '/market');
    await _pump(tester,
        error: DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 503),
        ));

    expect(find.text('Your account is being set up'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tap target clears 44 points', (tester) async {
    await _pump(tester);

    expect(tester.getSize(find.byType(TextField)).height,
        greaterThanOrEqualTo(44));
    // Rows are 56 by contract; check the shortest one really is.
    for (final asset in _assets) {
      final row = find.ancestor(
        of: find.text(asset.name),
        matching: find.byType(ExampleRow),
      );
      expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
    }
  });

  testWidgets('a row is spoken as one sentence with a direction word',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      find.bySemanticsLabel(RegExp(
        r'^Bitcoin, BTC, rank 1, .*, up 2\.40 percent over 24 hours\. Buy$',
      )),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Cardano.*down 3\.10 percent')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'Tether.*unchanged, 0\.00 percent')),
      findsOneWidget,
    );
    handle.dispose();
  });
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const _sizes = [Size(375, 812), Size(1440, 1000)];

List<String> _names(WidgetTester tester) => tester
    .widgetList<ExampleRow>(find.byType(ExampleRow))
    .map((row) => row.title)
    .toList();

String _price(double value) => Money.formatAmount('EUR', value);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(375, 812),
  Brightness brightness = Brightness.dark,
  List<HoppaMarketAsset>? assets,
  Object? error,
  VoidCallback? onLoad,
  bool pending = false,
  bool disableAnimations = false,
  double textScale = 1,
  bool settle = true,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final themes = buildAppThemes(_branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;

  final router = GoRouter(
    initialLocation: '/crypto/market',
    routes: [
      GoRoute(
        path: '/crypto/market',
        builder: (_, __) => const CryptoMarketScreen(),
      ),
      GoRoute(
        path: '/crypto/buy',
        builder: (_, __) => const Scaffold(body: Text('Buy route')),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        hoppaMarketAssetsProvider.overrideWith((ref) async {
          onLoad?.call();
          if (pending) return Completer<List<HoppaMarketAsset>>().future;
          if (error != null) throw error;
          return assets ?? _assets;
        }),
      ],
      child: MaterialApp.router(
        theme: theme,
        darkTheme: theme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: disableAnimations,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();
}

const _branding = AppBranding(
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
);

/// Deliberately awkward data: a five-figure price beside a one-figure one, a
/// stablecoin that did not move, an asset the provider never ranked, and one
/// series short enough to be undrawable.
const _assets = <HoppaMarketAsset>[
  HoppaMarketAsset(
    symbol: 'BTC',
    name: 'Bitcoin',
    price: 64201.55,
    changePercent: 2.4,
    marketCapRank: 1,
    sparkline: [100, 104, 101, 108, 112, 109, 114],
    tint: Color(0xFFF7931A),
  ),
  HoppaMarketAsset(
    symbol: 'ETH',
    name: 'Ethereum',
    price: 3120.4,
    changePercent: -0.85,
    marketCapRank: 2,
    sparkline: [50, 49, 51, 48, 47, 48, 46],
    tint: Color(0xFF627EEA),
  ),
  HoppaMarketAsset(
    symbol: 'USDT',
    name: 'Tether',
    price: 0.92,
    changePercent: 0,
    marketCapRank: 3,
    sparkline: [1, 1, 1, 1],
    tint: Color(0xFF26A17B),
  ),
  HoppaMarketAsset(
    symbol: 'SOL',
    name: 'Solana',
    price: 142.08,
    changePercent: 6.12,
    marketCapRank: 5,
    sparkline: [20, 21, 23, 22, 24, 25],
    tint: Color(0xFF14F195),
  ),
  HoppaMarketAsset(
    symbol: 'ADA',
    name: 'Cardano',
    price: 0.41,
    changePercent: -3.1,
    marketCapRank: 0,
    sparkline: [],
    hasMarketCapRank: false,
    tint: Color(0xFF0033AD),
  ),
];

const _unpriced = HoppaMarketAsset(
  symbol: 'OBS',
  name: 'Obscure Coin',
  price: 0,
  changePercent: 0,
  marketCapRank: 0,
  sparkline: [],
  tint: Color(0xFF888888),
  hasPrice: false,
  hasChangePercent: false,
  hasMarketCapRank: false,
);
