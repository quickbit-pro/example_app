import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/crypto/data/crypto_providers.dart';
import 'package:mobile_flutter/features/crypto/domain/crypto_models.dart';
import 'package:mobile_flutter/features/crypto/presentation/crypto_market_screen.dart';
import 'package:mobile_flutter/flavors.dart';

/// The market table as a *data-density* surface.
///
/// `crypto_market_screen_test.dart` next door proves the screen's behaviour —
/// provider order, states, and navigation. This file proves the three
/// properties that only fail silently, and that a behavioural test therefore
/// never catches:
///
/// * **Every width in the brief, not two of them.** 375 and 1440 were covered;
///   393 (the modern phone the app is most often opened on) and 834 (the
///   tablet, and the first width above `ExampleBreakpoints.desktop` on native)
///   were not. The measured value column is a function of width and text
///   scale, so an untested width is an untested column.
/// * **No glyph the bundled font cannot draw.** Geist's subset is Latin-1 plus
///   common punctuation. A `↑`, a `●` or a `₿` compiles, passes every
///   behavioural test, and ships a tofu box to a web reader. The only way to
///   catch that is to read the strings the tree actually renders, which is
///   what [_renderedStrings] does.
/// * **Direction survives greyscale.** A percentage whose only direction
///   signal is red-or-green is unreadable to about one man in twelve and to
///   anyone reading a screenshot in black and white. The caret is asserted as
///   a *widget*, so removing it fails here rather than in a design review.
void main() {
  // Every layout claim below is only worth what the font behind it is worth.
  // `flutter test` renders with a fallback face whose every glyph is exactly
  // one em wide — roughly 1.8x Geist — so a truncation assertion against it
  // is not a measurement, it is a rumour, and the only way to satisfy it is
  // to degrade real copy. The bundled Geist is right there in `assets/fonts`,
  // so it is loaded instead and these tests measure the shipping typeface.
  setUpAll(_loadGeist);

  group('holds every width in the brief', () {
    for (final size in _sizes) {
      for (final brightness in Brightness.values) {
        testWidgets('${size.width.toInt()} x ${brightness.name}',
            (tester) async {
          await _pump(tester, size: size, brightness: brightness);

          // A RenderFlex overflow is reported as an exception by the test
          // binding, so this is the overflow assertion.
          expect(tester.takeException(), isNull);

          for (final asset in _assets) {
            expect(find.text(asset.name), findsOneWidget);
            expect(find.text(_price(asset.price)), findsOneWidget);
          }

          // The numbers form a column: one right edge, shared by every row.
          final edges = _assets
              .map((asset) =>
                  tester.getRect(find.text(_price(asset.price))).right)
              .toList();
          for (final edge in edges) {
            expect((edge - edges.first).abs(), lessThan(0.5),
                reason: 'price column is ragged at ${size.width}');
          }

          // Nothing truncates. Asserting that no `Text` *may* ellipsise would
          // be the wrong test — a shared widget is entitled to set it
          // defensively — so this asserts what actually reached the glass:
          // no paragraph lost a line, and the two columns that carry the
          // reading were laid out at their full natural width.
          for (final paragraph in tester
              .renderObjectList<RenderParagraph>(find.byType(RichText))) {
            expect(paragraph.didExceedMaxLines, isFalse,
                reason: '"${paragraph.text.toPlainText()}" lost a line');
          }
          for (final asset in _assets) {
            for (final finder in [
              find.text(asset.name),
              find.text(_price(asset.price)),
            ]) {
              final paragraph = tester.renderObject<RenderParagraph>(finder);
              expect(
                paragraph.size.width + 0.5,
                greaterThanOrEqualTo(
                  paragraph.getMaxIntrinsicWidth(double.infinity),
                ),
                reason: '"${paragraph.text.toPlainText()}" is clipped at '
                    '${size.width}',
              );
            }
          }
        });
      }
    }
  });

  testWidgets('holds 393 at textScaleFactor 1.3', (tester) async {
    await _pump(tester, size: const Size(393, 852), textScale: 1.3);

    expect(tester.takeException(), isNull);
    for (final asset in _assets) {
      expect(find.text(_price(asset.price)), findsOneWidget);
      expect(find.text(asset.name), findsOneWidget);
    }
    // Asset rows keep their tap targets when the labels grow.
    expect(find.byType(ExampleRow), findsNWidgets(_assets.length));
    for (final row in find.byType(ExampleRow).evaluate()) {
      expect(tester.getSize(find.byWidget(row.widget)).height,
          greaterThanOrEqualTo(44));
    }
  });

  testWidgets('holds 834 at textScaleFactor 1.3', (tester) async {
    await _pump(tester, size: const Size(834, 1112), textScale: 1.3);
    expect(tester.takeException(), isNull);
    for (final asset in _assets) {
      expect(find.text(_price(asset.price)), findsOneWidget);
    }
  });

  testWidgets('desktop width is capped, not stretched', (tester) async {
    await _pump(tester, size: const Size(1440, 1000));

    final table = tester.getRect(find.byType(ExampleListGroup).first);
    expect(table.width, lessThanOrEqualTo(880),
        reason: 'the table should stop, not stretch into dead space');
    // Centred: the slack is even on both sides.
    expect((table.left - (1440 - table.right)).abs(), lessThan(1));
    // And it is genuinely wide, not a phone column marooned on a desktop.
    expect(table.width, greaterThan(700));
  });

  testWidgets('renders no glyph the bundled subset cannot draw',
      (tester) async {
    for (final size in _sizes) {
      await _pump(tester, size: size);
      final strings = _renderedStrings(tester).toList();
      // A scan over nothing passes every assertion below, so the sweep is
      // proved to have swept: the euro-signed price and the middot subtitle
      // are the two strings whose glyphs this test exists to police.
      expect(strings, contains(_price(64201.55)));
      expect(strings, contains('BTC  ·  Rank 1'));
      for (final string in strings) {
        for (final rune in string.runes) {
          expect(
            _forbidden.contains(rune),
            isFalse,
            reason: 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
                'in "$string" is missing from the Geist subset and from '
                'tenant fonts, and renders as a tofu box',
          );
          expect(
            rune <= 0x7E || _allowedNonAscii.contains(rune),
            isTrue,
            reason: 'U+${rune.toRadixString(16).toUpperCase().padLeft(4, '0')} '
                'in "$string" is outside the proven glyph set',
          );
        }
      }
    }
  });

  testWidgets('direction is a shape, not only a colour', (tester) async {
    await _pump(tester);

    // One riser, one faller, one flat in the fixture: the three carets have
    // to be three different glyphs, or the reading is carried by hue alone.
    expect(find.byIcon(Icons.arrow_drop_up), findsWidgets);
    expect(find.byIcon(Icons.arrow_drop_down), findsWidgets);
    expect(find.byIcon(Icons.remove_rounded), findsWidgets);

    Color inkOf(IconData glyph) => tester
        .widgetList<Icon>(find.byIcon(glyph))
        .map((icon) => icon.color)
        .whereType<Color>()
        .first;
    // The two directions are not the same ink either: shape *and* colour.
    expect(inkOf(Icons.arrow_drop_up), isNot(inkOf(Icons.arrow_drop_down)));
  });

  testWidgets('the complete asset list keeps its accessible heading',
      (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);

    expect(
      tester.getSemantics(find.text('All assets')),
      isSemantics(label: 'All assets', isLiveRegion: true),
    );

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(find.text('All assets')),
      isSemantics(label: 'All assets', isLiveRegion: true),
    );
    expect(find.byType(ExampleRow), findsNWidgets(_assets.length));
    handle.dispose();
  });

  testWidgets('pull to refresh is drawn in Example ink, not Material default',
      (tester) async {
    for (final brightness in Brightness.values) {
      await _pump(tester, brightness: brightness);
      final indicator =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      final palette = ExamplePalette.forBrightness(brightness);
      expect(indicator.color, palette.accentFor(ExampleColors.iris));
      expect(indicator.backgroundColor, palette.surfaceLevel(2));
    }
  });

  testWidgets('desktop refresh preserves the provider order and row layout',
      (tester) async {
    final providerOrder = _assets.reversed.toList();
    var loads = 0;
    await _pump(
      tester,
      size: const Size(1440, 1000),
      assets: providerOrder,
      onMarketLoad: () => loads++,
    );
    expect(loads, 1);
    expect(find.byTooltip('Refresh prices'), findsNothing);
    expect(
      tester
          .widgetList<ExampleRow>(find.byType(ExampleRow))
          .map((row) => row.title),
      providerOrder.map((asset) => asset.name),
    );

    final indicator =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final refreshing = indicator.onRefresh();
    await tester.pumpAndSettle();
    await refreshing;
    expect(loads, 2);
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widgetList<ExampleRow>(find.byType(ExampleRow))
          .map((row) => row.title),
      providerOrder.map((asset) => asset.name),
    );
  });

  testWidgets('on a phone the pull is the refresh, and the only one',
      (tester) async {
    await _pump(tester, size: const Size(375, 812));
    // A second affordance beside a working pull gesture is clutter.
    expect(find.byTooltip('Refresh prices'), findsNothing);
    expect(find.byType(RefreshIndicator), findsOneWidget);
  });

  testWidgets(
      'search retains its read-only behavior without opening a keyboard',
      (tester) async {
    await _pump(tester);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.readOnly, isTrue);
    expect(field.decoration?.labelText, 'Search assets');

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isFalse);
    expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty);
    expect(
      tester
          .widgetList<ExampleRow>(find.byType(ExampleRow))
          .map((row) => row.title),
      _assets.map((asset) => asset.name),
    );
  });

  testWidgets('reduced motion settles instantly at desktop width too',
      (tester) async {
    await _pump(
      tester,
      size: const Size(1440, 1000),
      disableAnimations: true,
      settle: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('All assets'), findsOneWidget);
    expect(find.byType(ExampleRow), findsNWidgets(_assets.length));
  });

  group('the inks this screen paints clear their floors', () {
    for (final brightness in Brightness.values) {
      test(brightness.name, () {
        final palette = ExamplePalette.forBrightness(brightness);
        final panel = palette.surfaceLevel(1);
        final field = palette.surfaceLevel(2);

        // Body and caption text, on every surface the screen puts it on.
        for (final probe in <(String, Color, Color)>[
          ('row title', palette.ink, panel),
          ('row subtitle', palette.textSecondary, panel),
          ('price', palette.ink, panel),
          ('column header', palette.textTertiary, panel),
          ('search label', palette.textSecondary, field),
          ('gain', palette.accentFor(ExampleColors.success), panel),
          ('loss', palette.accentFor(ExampleColors.danger), panel),
        ]) {
          expect(
            _contrast(probe.$2, probe.$3),
            greaterThanOrEqualTo(4.5),
            reason: '${probe.$1} is ${_contrast(probe.$2, probe.$3)}:1 '
                'in ${brightness.name}',
          );
        }

        // The sparkline strokes carry meaning, so they take the 3:1 floor.
        for (final probe in <(String, Color, Color)>[
          ('spark up', palette.accentFor(ExampleColors.success), panel),
          ('spark down', palette.accentFor(ExampleColors.danger), panel),
          ('spark flat', palette.textTertiary, panel),
        ]) {
          expect(_contrast(probe.$2, probe.$3), greaterThanOrEqualTo(3),
              reason: probe.$1);
        }
      });
    }
  });
}

// ---------------------------------------------------------------------------
// The real typeface
// ---------------------------------------------------------------------------

/// Registers the bundled Geist faces so the widget tree lays out in the font
/// it actually ships in.
///
/// Read from disk rather than through `rootBundle` so the test does not depend
/// on how the runner assembled the asset bundle; `flutter test` runs with the
/// package root as its working directory.
Future<void> _loadGeist() async {
  const faces = <String, List<String>>{
    'Geist': [
      'assets/fonts/Geist-Regular.ttf',
      'assets/fonts/Geist-Medium.ttf',
      'assets/fonts/Geist-SemiBold.ttf',
      'assets/fonts/Geist-Bold.ttf',
    ],
    'GeistMono': [
      'assets/fonts/GeistMono-Regular.ttf',
      'assets/fonts/GeistMono-Medium.ttf',
    ],
  };
  for (final face in faces.entries) {
    final loader = FontLoader(face.key);
    for (final path in face.value) {
      final file = File(path);
      // A missing font would silently fall back to the one-em face and turn
      // every assertion below into the rumour this exists to avoid.
      expect(file.existsSync(), isTrue, reason: 'missing $path');
      loader.addFont(file.readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }
}

// ---------------------------------------------------------------------------
// Glyph safety
// ---------------------------------------------------------------------------

/// Code points that are known-missing from the bundled Geist subsets, or that
/// exist in Geist but not in a white-label tenant's configured font.
const _forbidden = <int>{
  0x2190, // <-
  0x2191, // ^  (in Geist, absent from tenant fonts)
  0x2192, // ->
  0x2193, // v  (ditto)
  0x25B2, // filled up triangle
  0x25BC, // filled down triangle
  0x25CF, // filled circle
  0x2713, // check
  0x20BF, // bitcoin sign
  0x2B06,
  0x2B07,
};

/// Non-ASCII the screen is allowed to render: the euro the prices are quoted
/// in, and the middot the row subtitle separates its facts with. Both are in
/// every subset the app ships.
const _allowedNonAscii = <int>{
  0x00B7, // middot, the subtitle separator
  0x20AC, // euro, from Money.formatAmount
  0x2013, // en dash
  0x2019, // typographic apostrophe
};

/// Every string the tree actually paints.
Iterable<String> _renderedStrings(WidgetTester tester) sync* {
  for (final text in tester.widgetList<Text>(find.byType(Text))) {
    final data = text.data;
    if (data != null) yield data;
    final span = text.textSpan;
    if (span != null) yield span.toPlainText();
  }
  for (final field in tester.widgetList<TextField>(find.byType(TextField))) {
    final hint = field.decoration?.hintText;
    if (hint != null) yield hint;
  }
}

// ---------------------------------------------------------------------------
// Contrast
// ---------------------------------------------------------------------------

double _channel(double value) => value <= 0.03928
    ? value / 12.92
    : math.pow((value + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color color) =>
    0.2126 * _channel(color.r) +
    0.7152 * _channel(color.g) +
    0.0722 * _channel(color.b);

/// WCAG ratio of [foreground] over [background], alpha-composited first: an
/// ink at .53 is not its own colour, it is what it becomes on this surface.
double _contrast(Color foreground, Color background) {
  final composited = Color.alphaBlend(foreground, background);
  final a = _luminance(composited);
  final b = _luminance(background);
  final high = math.max(a, b);
  final low = math.min(a, b);
  return (high + 0.05) / (low + 0.05);
}

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

/// 375 and 1440 are the poles the sibling file already covers; 393 and 834 are
/// the two the brief names and nothing tested.
const _sizes = [
  Size(375, 812),
  Size(393, 852),
  Size(834, 1112),
  Size(1440, 1000),
];

String _price(double value) => Money.formatAmount('EUR', value);

Future<void> _pump(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  bool disableAnimations = false,
  bool settle = true,
  List<HoppaMarketAsset> assets = _assets,
  VoidCallback? onMarketLoad,
}) async {
  // `setSurfaceSize` resizes the render view but leaves `FlutterView`
  // untouched, so `MediaQuery.sizeOf` keeps reporting the harness default of
  // 800 x 600 while the tree lays out at the size asked for. Anything driven
  // by a `LayoutBuilder` looks right and anything driven by
  // `MediaQuery.sizeOf` - this screen's `desktop` flag, and therefore the app
  // bar - is silently pinned to desktop at every width. Driving the view
  // itself keeps the two in agreement.
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

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
          onMarketLoad?.call();
          return assets;
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

/// The same awkward fixture the sibling file uses: a five-figure price beside
/// a two-decimal one, a stablecoin that did not move, and an unranked asset
/// with a series too short to draw.
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
