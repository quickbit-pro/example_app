import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/cards/presentation/card_transactions_screen.dart';
// Layout and legibility proof for the Example ledger and receipt.
//
// The two screens here are utility surfaces opened dozens of times a day, so
// what is worth testing is not a moment but the invariants: no overflow and
// no truncation at 375, 393, 834 and 1440 in BOTH themes, pending money
// hoisted above the dated ledger, and date headings that scroll away with
// their rows without covering later activity.
import 'dart:async';
import 'dart:convert';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/widgets/app_states.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:mobile_flutter/features/transactions/presentation/transactions_screen.dart';
import 'package:mobile_flutter/features/transactions/application/activity_valuation_provider.dart';
import 'package:mobile_flutter/features/dashboard/data/display_currency_provider.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf_export_button.dart';
import 'package:mobile_flutter/shared/widgets/finance_transaction_row.dart';

AppBranding _branding(String mode, {bool hoppa = false}) => AppBranding(
      appName: hoppa ? 'Hoppa' : 'EXAMPLE',
      brandId: hoppa ? 'hoppa' : 'example',
      design: hoppa
          ? AppDesign.fromJsonString(jsonEncode(
              (jsonDecode(File('config/hoppa.json').readAsStringSync())
                  as Map)['design']))
          : const AppDesign(),
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: mode,
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: 'EXAMPLE',
    );

const _tenant = MobileTenantConfig(
  companyName: 'EXAMPLE',
  brandName: 'EXAMPLE',
  referralsEnabled: true,
  referralRegistrationMode: 'open',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
  supportEmail: 'support@example.com',
);

/// Anchored to 15:24 on whatever day the suite runs, not to a fixed calendar
/// date. The screen resolves its `Today` / `Yesterday` headings against the
/// real clock, so a literal date here passes on the day it is written and
/// fails every day after that. 15:24 leaves room for the largest same-day
/// offset below (9 hours) without crossing midnight.
final _today = () {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 15, 24);
}();

LedgerTransaction _tx({
  required String id,
  required String title,
  required int minorUnits,
  required DateTime bookedAt,
  String status = 'completed',
  String currency = 'USD',
  Money? transactionAmount,
}) =>
    LedgerTransaction(
      id: id,
      title: title,
      subtitle: status,
      status: status,
      amount: Money(currency: currency, minorUnits: minorUnits),
      // Set it to make the row an FX row: `displayAmount` becomes this and
      // `amount` drops to the settlement caption under it.
      transactionAmount: transactionAmount,
      bookedAt: bookedAt,
      type: TransactionType.card,
      rawType: 'card_payment',
      merchantCategory: 'Groceries',
    );

final _ledger = <LedgerTransaction>[
  _tx(
    id: 'tx-pending',
    title: 'Blue Bottle Coffee',
    minorUnits: -1899,
    bookedAt: _today.subtract(const Duration(hours: 2)),
    status: 'pending',
  ),
  _tx(
    id: 'tx-today',
    title: 'Whole Foods Market',
    minorUnits: -12450,
    bookedAt: _today.subtract(const Duration(hours: 5)),
  ),
  _tx(
    id: 'tx-today-2',
    title: 'Salary — Northwind Ltd',
    minorUnits: 540000,
    bookedAt: _today.subtract(const Duration(hours: 9)),
  ),
  _tx(
    id: 'tx-yesterday',
    title: 'Transport for London',
    minorUnits: -740,
    bookedAt: _today.subtract(const Duration(days: 1, hours: 3)),
  ),
  _tx(
    id: 'tx-older',
    title: 'Ocado Retail',
    // Seven figures: the widest amount the column has to keep aligned.
    minorUnits: -9999999,
    bookedAt: _today.subtract(const Duration(days: 6)),
  ),
];

/// The brand's own typefaces, so every width and truncation assertion below
/// is measured in Geist. Without this the binding falls back to the test
/// font, whose glyphs are square boxes roughly twice Geist's advance width,
/// and a layout proof measured in it is a proof about a font nobody ships.
const _exampleFonts = <String, List<String>>{
  'Geist': [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
    'Geist-Bold.ttf',
  ],
  'GeistMono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
};

Future<void> _loadFonts() async {
  for (final entry in _exampleFonts.entries) {
    final loader = FontLoader(entry.key);
    var found = false;
    for (final file in entry.value) {
      final font = File('assets/fonts/$file');
      if (!font.existsSync()) continue;
      found = true;
      loader.addFont(
        Future.value(ByteData.view(font.readAsBytesSync().buffer)),
      );
    }
    if (found) await loader.load();
  }
  // Widget tests do not automatically register the Material icon font.
  // Load the same bundled glyphs as the installed app for screenshot QA.
  ByteData materialIcons;
  try {
    materialIcons = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
  } catch (_) {
    final font = [
      'build/flutter_assets/fonts/MaterialIcons-Regular.otf',
      'build/app/intermediates/flutter/debug/flutter_assets/fonts/MaterialIcons-Regular.otf',
    ].map(File.new).where((file) => file.existsSync()).firstOrNull;
    if (font == null) rethrow;
    materialIcons = ByteData.sublistView(await font.readAsBytes());
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(materialIcons));
  await icons.load();
}

Widget _app(
  Widget home, {
  required bool light,
  List<LedgerTransaction>? ledger,
  Future<List<LedgerTransaction>> Function()? load,
  bool reducedMotion = false,
  bool hoppa = false,
  double textScale = 1,
}) {
  final themes =
      buildAppThemes(_branding(light ? 'light' : 'dark', hoppa: hoppa));
  return ProviderScope(
    overrides: [
      activityValuationProvider.overrideWith((ref) {
        final currency = ref.watch(homeDisplayCurrencyProvider);
        final factor = currency == 'EUR'
            ? 1 / 1.2
            : currency == 'GBP'
                ? 1 / 1.5
                : 1.0;
        return {
          'USD': factor,
          'USDT': factor,
          'USDC': factor,
          'EUR': 1.2 * factor,
          'GBP': 1.5 * factor
        };
      }),
      activityTransactionsProvider.overrideWith(
        (ref) => load == null ? Future.value(ledger ?? _ledger) : load(),
      ),
      activityAccountTransactionsProvider.overrideWith(
        (ref, accountId) async => ledger ?? _ledger,
      ),
      accountsProvider.overrideWith((ref) async => const []),
      budgetsProvider.overrideWith((ref) async => const []),
      mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      // Above the Navigator, so anything routed inherits it too.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: reducedMotion,
          textScaler: TextScaler.linear(textScale),
        ),
        child: RepaintBoundary(
          key: const ValueKey('activity-test-capture'),
          child: child!,
        ),
      ),
      home: home,
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget home,
  Size size, {
  required bool light,
  List<LedgerTransaction>? ledger,
  Future<List<LedgerTransaction>> Function()? load,
  bool settle = true,
  bool reducedMotion = false,
  bool hoppa = false,
  double textScale = 1,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    _app(
      home,
      light: light,
      ledger: ledger,
      load: load,
      reducedMotion: reducedMotion,
      hoppa: hoppa,
      textScale: textScale,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A loading state carries a looping sheen, so it never settles. Advance a
    // fixed amount instead of waiting for a tree that will not come to rest.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
}

/// Optional fixture captures for visual QA. This hook exists only in tests;
/// normal application data and installed builds are never replaced.
Future<void> _writeActivityScreenshot(
    WidgetTester tester, String filename) async {
  final output = Platform.environment['EXAMPLE_ACTIVITY_TEST_OUTPUT']?.trim();
  if (output == null || output.isEmpty) return;
  await tester.pumpAndSettle();
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('activity-test-capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) {
        throw StateError('Activity screenshot has no PNG bytes');
      }
      final directory = Directory(output);
      await directory.create(recursive: true);
      await File('${directory.path}/$filename')
          .writeAsBytes(bytes.buffer.asUint8List(), flush: true);
    } finally {
      image.dispose();
    }
  });
}

/// Every string this app writes renders whole: no ellipsis, no clipped glyph
/// run. Truncation is the failure mode a screenshot hides and a diff never
/// shows, so it is asserted rather than looked at.
///
/// Truncation has two shapes here and only one of them raises a flag.
///
/// * A run that is allowed to wrap fills its lines and sets
///   `didExceedMaxLines` when it runs out of them. That is the ellipsis case.
/// * A `softWrap: false` run never wraps, so it is always one line and that
///   flag is always false however far past its box it goes. It is laid out at
///   its full intrinsic width and then clipped — or faded, which is what
///   `ExampleAmount` asks for — by a narrower box, and the only thing left
///   behind is that the box is narrower than the glyphs in it. This is not
///   hypothetical: a wide amount can fade mid-string without reporting
///   that it exceeded its maximum line count.
///
/// Counterparty names are the one exception, and deliberately so. A merchant
/// name arrives from a payment network at whatever length it likes; the row's
/// contract is that it ellipsizes rather than overflowing, which is checked
/// separately. Everything else — headings, labels, amounts, descriptors,
/// status words — is copy this app controls, and copy that does not fit is a
/// design bug.
/// [within] narrows the sweep to one subtree, for a fixture that is
/// deliberately pathological somewhere else on the screen.
void _expectAppCopyIsWhole(WidgetTester tester, {Finder? within}) {
  final counterparties = {for (final item in _ledger) item.title};
  final texts = within == null
      ? find.byType(Text)
      : find.descendant(of: within, matching: find.byType(Text));
  for (final element in texts.evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph) continue;
    // Half a pixel of slack: intrinsic width and laid-out width are computed
    // by two different passes over the same glyphs and can disagree in the
    // last bit without a glyph having been lost.
    final clipped = !paragraph.softWrap &&
        paragraph.getMaxIntrinsicWidth(double.infinity) >
            paragraph.size.width + 0.5;
    if (!paragraph.didExceedMaxLines && !clipped) continue;
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (counterparties.contains(text)) continue;
    fail(clipped ? 'Clipped: "$text"' : 'Truncated: "$text"');
  }
}

/// The kind label in the row's descriptor (`15:24 · Card Payment`) survives
/// exactly as long as the row has room for it.
///
/// Both halves of that are failures worth catching, and they pull in opposite
/// directions:
///
/// * A row that keeps `time · kind` in a column too narrow for it ellipsizes
///   mid-word. That is what the amount column squeezing the text column
///   leaves behind, and at the default text scale a single seven-figure
///   amount is enough to do it.
/// * A row that drops the kind while its column had room throws away the one
///   token on the line that says what the movement was. A compaction rule
///   with no width term does exactly that on every row of a tablet ledger the
///   moment the reader nudges their font size up.
///
/// Measured against each paragraph's own style, scaler and layout constraints
/// rather than against a recomputation of the screen's arithmetic, so this
/// asserts the contract and not the implementation. Rows wearing a status
/// pill are exempt: they share the line with the pill and compact by design.
///
/// Every fixture built by [_tx] carries `rawType: 'card_payment'`, which the
/// ledger labels "Card Payment"; that is the string reconstructed here.
void _expectKindKeptWhereverItFits(
  WidgetTester tester,
  List<String> ids, {
  String kind = 'Card Payment',
}) {
  var checked = 0;
  for (final id in ids) {
    final row = find.byKey(ValueKey<String>(id));
    // Rows far enough down the ledger are outside the sliver cache extent and
    // were never built. Nothing to say about a row that is not on screen.
    if (row.evaluate().isEmpty) continue;
    final paragraphs = find
        .descendant(of: row, matching: find.byType(RichText))
        .evaluate()
        .map((element) => element.renderObject)
        .whereType<RenderParagraph>();
    for (final paragraph in paragraphs) {
      final span = paragraph.text;
      if (span is! TextSpan) continue;
      final text = span.toPlainText();
      // The descriptor is the only run on the row that opens with a clock.
      if (!RegExp(r'^\d\d:\d\d').hasMatch(text)) continue;
      checked++;
      if (text.contains(' \u00b7 ')) {
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: '$id kept the kind in a column too narrow for it: "$text"',
        );
        continue;
      }
      if (find
          .descendant(of: row, matching: find.byType(ExamplePill))
          .evaluate()
          .isNotEmpty) {
        continue;
      }
      final painter = TextPainter(
        text: TextSpan(text: '$text \u00b7 $kind', style: span.style),
        textDirection: TextDirection.ltr,
        textScaler: paragraph.textScaler,
        maxLines: 1,
      )..layout();
      final needed = painter.width;
      painter.dispose();
      final room = paragraph.constraints.maxWidth;
      expect(
        needed,
        greaterThan(room),
        reason: '$id dropped the kind with ${room.toStringAsFixed(1)} pt of '
            'room for a ${needed.toStringAsFixed(1)} pt descriptor',
      );
    }
  }
  expect(checked, greaterThan(0), reason: 'no descriptor was examined');
}

const _viewports = <(String, Size)>[
  ('375', Size(375, 812)),
  ('393', Size(393, 852)),
  ('834', Size(834, 1194)),
  ('1440', Size(1440, 900)),
];

/// The magnitude band painted behind one row, or null when the row is too
/// small to be worth drawing.
///
/// Reaches through the private painter deliberately: the band is the screen's
/// central design claim — size is length, direction is which edge it hangs
/// from — and a claim that can only be checked by looking at a screenshot is
/// a claim nothing defends.
({double extent, bool fromStart, Color color})? _band(
  WidgetTester tester,
  String id,
) {
  final painters = find.descendant(
    of: find.byKey(ValueKey<String>(id)),
    matching: find.byType(CustomPaint),
  );
  for (final element in painters.evaluate()) {
    final dynamic painter = (element.widget as CustomPaint).painter;
    if (painter == null) continue;
    if (!painter.runtimeType.toString().contains('MagnitudeWash')) continue;
    return (
      extent: painter.extent as double,
      fromStart: painter.fromStart as bool,
      // The wash itself, so the contrast proof below measures the ground the
      // row actually gets rather than one it assumes.
      color: painter.color as Color,
    );
  }
  return null;
}

/// [ink] composited onto the opaque [ground] beneath it.
Color _over(Color ink, Color ground) => Color.from(
      alpha: 1,
      red: ink.r * ink.a + ground.r * (1 - ink.a),
      green: ink.g * ink.a + ground.g * (1 - ink.a),
      blue: ink.b * ink.a + ground.b * (1 - ink.a),
    );

/// WCAG 2.1 contrast of [ink] against [ground], compositing first so a
/// translucent ink is measured as it is actually seen.
///
/// Calibrated against the palette's own recorded ratios: it returns 5.10 for
/// tertiary on `darkSurface` and 4.84 on `darkSurfaceSubtle`, which are the
/// two figures `ExampleColors.textTertiary` documents for those grounds.
double _contrast(Color ink, Color ground) {
  double luminance(Color color) {
    double channel(double value) => value <= 0.04045
        ? value / 12.92
        : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  final a = luminance(_over(ink, ground)) + 0.05;
  final b = luminance(ground) + 0.05;
  return a > b ? a / b : b / a;
}

LedgerTransaction _sourceTransaction(String id, String type,
        {String currency = 'USD',
        double amount = -10,
        String cardId = '',
        Map<String, dynamic> metadata = const {}}) =>
    LedgerTransaction.fromJson({
      'id': id,
      'title': id,
      'type': type,
      'currency': currency,
      'amount': amount,
      'cardId': cardId,
      'metadata': metadata,
      'status': 'completed',
      'bookedAt': _today.toIso8601String(),
    });

Future<void> _selectActivityDirection(WidgetTester tester, String label) async {
  final group = find.byKey(const ValueKey('activity-direction-filter'));
  final segment = find.descendant(of: group, matching: find.text(label));
  await tester.ensureVisible(segment);
  await tester.pumpAndSettle();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

Future<void> _selectActivityAsset(WidgetTester tester, String label) async {
  final group = find.byKey(const ValueKey('activity-asset-filter'));
  final segment = find.descendant(of: group, matching: find.text(label));
  await tester.ensureVisible(segment);
  await tester.pumpAndSettle();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

Future<void> _selectActivityType(WidgetTester tester, String label) async {
  final menu = find.byType(PopupMenuButton<Object>);
  await tester.ensureVisible(menu);
  await tester.tap(menu);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _selectActivityScope(WidgetTester tester, String label) async {
  final dropdown = find.byKey(const ValueKey('activity-scope-dropdown'));
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _selectActivityAccount(WidgetTester tester, String label) async {
  final dropdown = find.byKey(const ValueKey('activity-account-dropdown'));
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'card-specific activity groups fee and retains purchase details link',
      (tester) async {
    final resources = [
      PlatformResource.fromJson({
        'id': 'fee',
        'type': 9,
        'status': 'closed',
        'merchantName': 'Separate fee',
        'amount': .5,
        'currency': 'USD',
        'createdAt': _today.toIso8601String(),
        'clientTransactionId': 'card-ref_Fee_Consumption'
      }),
      PlatformResource.fromJson({
        'id': 'purchase',
        'type': 1,
        'status': 'closed',
        'merchantName': 'Card merchant',
        'amount': 10,
        'currency': 'USD',
        'createdAt': _today.toIso8601String(),
        'clientTransactionId': 'card-ref'
      }),
    ];
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          cardsProvider.overrideWith((ref) async => []),
          cardTransactionsProvider.overrideWith((ref, id) async => resources),
        ], child: const CardTransactionsScreen(cardId: '17')),
        const Size(393, 1000),
        light: false);
    expect(find.text('Separate fee'), findsNothing);
    expect(find.text('Card merchant'), findsOneWidget);
    expect(find.textContaining('Consumption fee USD 0.50'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _writeActivityScreenshot(tester, 'grouped-card-specific-phone.png');
  });

  testWidgets('Hoppa linked card fee renders in one transaction row',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          LedgerTransaction.fromJson({
            'id': 'fee',
            'type': 'card_payment_fee',
            'title': 'Separate consumption fee',
            'status': 'closed',
            'amount': .5,
            'currency': 'USD',
            'cardId': '17',
            'transactionDate': _today.toIso8601String(),
            'metadata': {'clientTransactionId': 'join_Fee_Consumption'}
          }),
          LedgerTransaction.fromJson({
            'id': 'purchase',
            'type': 'card_payment',
            'title': 'Coffee merchant',
            'status': 'closed',
            'amount': 10,
            'currency': 'USD',
            'cardId': '17',
            'transactionDate': _today.toIso8601String(),
            'metadata': {'clientTransactionId': 'join'}
          }),
        ]);
    expect(find.byType(ExampleTransactionRow), findsOneWidget);
    final row =
        tester.widget<ExampleTransactionRow>(find.byType(ExampleTransactionRow));
    expect(row.amount, -10.5);
    expect(row.identityLabel, contains('Consumption fee USD 0.50'));
    expect(find.text('Separate consumption fee'), findsNothing);
    expect(tester.takeException(), isNull);
    await _writeActivityScreenshot(tester, 'grouped-card-fee-phone.png');
  });

  testWidgets('one net flow follows Home currency and Activity filters',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: true,
        ledger: [
          _tx(
              id: 'eur',
              title: 'Euro deposit',
              minorUnits: 10000,
              currency: 'EUR',
              bookedAt: _today),
          _tx(
              id: 'usd',
              title: 'Dollar payment',
              minorUnits: -2000,
              bookedAt: _today)
        ]);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsScreen)));
    String total() => tester
        .widget<Text>(find.byKey(const ValueKey('activity-net-flow-value')))
        .data!;
    expect(total(), '+\$100.00');
    expect(find.text('IN  +\$120.00'), findsOneWidget);
    expect(find.text('OUT  -\$20.00'), findsOneWidget);
    expect(find.text('2 EVENTS'), findsOneWidget);
    await _writeActivityScreenshot(tester, 'net-flow-light.png');
    for (final entry in {'EUR': '+€83.33', 'GBP': '+£66.67'}.entries) {
      container.read(homeDisplayCurrencyProvider.notifier).state = entry.key;
      await tester.pumpAndSettle();
      expect(total(), entry.value);
      expect(find.text('All amounts in ${entry.key}'), findsOneWidget);
    }
    await _selectActivityDirection(tester, 'Out');
    expect(total(), '-£13.33');
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the net flow masthead carries the Home currency dropdown',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        ledger: [
          _tx(
              id: 'eur',
              title: 'Euro deposit',
              minorUnits: 10000,
              currency: 'EUR',
              bookedAt: _today),
          _tx(
              id: 'usd',
              title: 'Dollar payment',
              minorUnits: -2000,
              bookedAt: _today)
        ]);
    String total() => tester
        .widget<Text>(find.byKey(const ValueKey('activity-net-flow-value')))
        .data!;
    expect(total(), '+\$100.00');

    // The same control Home's total balance carries, on the same provider,
    // sits beside the title and shows the unit the figures are valued in.
    final selector = find.byKey(const ValueKey('activity-net-flow-currency'));
    expect(selector, findsOneWidget);
    expect(find.descendant(of: selector, matching: find.text('USD')),
        findsOneWidget);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    // The majors, plus the currencies the ledger actually moves.
    for (final code in const ['USD', 'EUR', 'GBP']) {
      expect(find.widgetWithText(PopupMenuItem<String>, code), findsOneWidget);
    }
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'EUR'));
    await tester.pumpAndSettle();

    expect(total(), '+€83.33');
    expect(find.text('All amounts in EUR'), findsOneWidget);
    expect(find.descendant(of: selector, matching: find.text('EUR')),
        findsOneWidget);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsScreen)));
    expect(container.read(homeDisplayCurrencyProvider), 'EUR');
    await _writeActivityScreenshot(tester, 'net-flow-currency-dark.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('provider fee shapes fold into the row they charge',
      (tester) async {
    final day = DateTime(_today.year, _today.month, _today.day);
    String at(int h, int m, int sec) =>
        DateTime(day.year, day.month, day.day, h, m, sec).toIso8601String();
    LedgerTransaction json(Map<String, dynamic> row) =>
        LedgerTransaction.fromJson(row);
    final ledger = [
      // Equals FX trade seen as order, ledger leg, exchange record and fee.
      json({
        'id': '80005',
        'externalTransactionId': 'EOP354YEVZD1',
        'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1',
        'isPrimary': true,
        'type': 'fx_trade',
        'description': 'FX Trade: 15 EUR → 12.72 GBP',
        'amount': 12.72,
        'currency': 'GBP',
        'status': 'completed',
        'transactionDate': at(7, 22, 41),
        'tradeId': 'EOP354YEVZD1',
      }),
      json({
        'id': '80007',
        'externalTransactionId': '145910597',
        'transactionGroupId': 'equalsmoney:ledger:145910597',
        'isPrimary': true,
        'type': 'deposit',
        'description': 'Budget credit from Igor Lavrih',
        'amount': 12.72,
        'currency': 'GBP',
        'status': 'completed',
        'transactionDate': at(7, 22, 39),
        'metadata': {'source': 'exchange', 'boxTransactionId': 145910597},
      }),
      json({
        'id': '80008',
        'externalTransactionId': '8982500',
        'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1',
        'isPrimary': true,
        'type': 'exchange',
        'description': 'exchange',
        'amount': 12.72,
        'currency': 'GBP',
        'status': 'completed',
        'transactionDate': at(7, 22, 37),
        'tradeId': 'EOP354YEVZD1',
        'metadata': {'boxTransactionId': '145910597'},
      }),
      json({
        'id': '80009',
        'transactionGroupId': 'equalsmoney:order:EOP354YEVZD1-Fee',
        'isPrimary': true,
        'type': 'fees',
        'description': 'fee',
        'amount': 0.01,
        'currency': 'EUR',
        'status': 'completed',
        'transactionDate': at(7, 22, 36),
        'tradeId': 'EOP354YEVZD1-Fee',
      }),
      // A declined card purchase that still cost two fees.
      json({
        'id': '76750',
        'type': 'card_decline_fee',
        'description': 'Card decline fee for transaction',
        'amount': -0.5,
        'currency': 'USD',
        'status': 'completed',
        'transactionDate': at(9, 44, 46),
        'cardId': '541',
        'relatedCardTransactionId': 'ext-76748',
      }),
      json({
        'id': '76749',
        'type': 'card_payment_fee',
        'amount': 0.5,
        'currency': 'USD',
        'status': 'closed',
        'transactionDate': at(9, 44, 43),
        'cardId': '541',
        'metadata': {
          'clientTransactionId': '2094723116296110081_Fee_Consumption'
        },
      }),
      json({
        'id': '76748',
        'externalTransactionId': 'ext-76748',
        'type': 'card_payment',
        'description': 'Type1: MESARIJA SELAK',
        'amount': 66.87,
        'currency': 'USD',
        'status': 'fail',
        'transactionDate': at(9, 44, 43),
        'cardId': '541',
        'metadata': {'clientTransactionId': '2094723116296110081', 'type': 1},
      }),
      // An older decline whose fee the provider never linked by reference.
      json({
        'id': '53421',
        'relatedCardTransactionId': '633ac32d',
        'type': 'card_payment_fee',
        'description': 'Type10: ',
        'amount': 0,
        'currency': 'USD',
        'status': 'closed',
        'transactionDate': at(17, 9, 3),
        'cardId': '396',
        'feeAmount': 0.5,
        'metadata': {'clientTransactionId': 'd2edd680', 'type': 10},
      }),
      json({
        'id': '53420',
        'type': 'card_payment',
        'description': 'Type1: GOOGLE*GOOGLE PLAY APP DUBLIN',
        'amount': 11.66,
        'currency': 'USD',
        'status': 'fail',
        'transactionDate': at(17, 9, 3),
        'cardId': '396',
        'metadata': {'clientTransactionId': '73a6dc78', 'type': 1},
      }),
    ];
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1400),
        light: false, ledger: ledger);

    // One row per movement, each carrying its fee.
    for (final hidden in [
      '80007',
      '80008',
      '80009',
      '76750',
      '76749',
      '53421'
    ]) {
      expect(find.byKey(ValueKey<String>(hidden)), findsNothing,
          reason: '$hidden should fold into the row it belongs to');
    }
    for (final shown in ['80005', '76748', '53420']) {
      expect(find.byKey(ValueKey<String>(shown)), findsOneWidget);
    }
    expect(find.textContaining('Fee EUR 0.01'), findsOneWidget);
    expect(
        find.textContaining('Decline fee USD 0.50 · Consumption fee USD 0.50'),
        findsOneWidget);
    expect(find.textContaining('Decline fee USD 0.50'), findsNWidgets(2));
    // The two declines say so on the row, and their amount is the fee taken.
    expect(find.text('Failed'), findsNWidgets(2));
    expect(find.text('3 EVENTS'), findsOneWidget);
    await _writeActivityScreenshot(tester, 'grouped-fees-dark.png');
    expect(tester.takeException(), isNull);
  });

  testWidgets('flow bar shows the reference proportions in dark mode',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          _tx(id: 'in', title: 'Deposit', minorUnits: 285000, bookedAt: _today),
          _tx(
              id: 'out',
              title: 'Payment',
              minorUnits: -91885,
              bookedAt: _today),
        ]);
    expect(find.text('+\$1,931.15'), findsOneWidget);
    final bar = find.byKey(const ValueKey('activity-net-flow-bar'));
    final segments = tester.widget<Row>(bar).children;
    final incoming = tester.getSize(find.byWidget(segments.first)).width;
    final outgoing = tester.getSize(find.byWidget(segments.last)).width;
    expect(incoming / outgoing, closeTo(2850 / 918.85, .001));
    await _writeActivityScreenshot(tester, 'net-flow-dark.png');
    expect(tester.takeException(), isNull);
  });

  setUpAll(_loadFonts);

  if (Platform.environment['EXAMPLE_ACTIVITY_TEST_OUTPUT']?.trim().isNotEmpty ??
      false) {
    for (final width in [393.0, 1440.0]) {
      testWidgets('Activity open account menu QA captures at $width',
          (tester) async {
        const longAccountName =
            'Business travel and international supplier expenses account';
        await _pumpAt(
          tester,
          ProviderScope(overrides: [
            accountsProvider.overrideWith((ref) async => const [
                  AccountBalance(
                    id: 'qa-euro-operating',
                    name: 'Account balance',
                    iban: 'BE12345678901234',
                    balance: Money(currency: 'EUR', minorUnits: 2000),
                    available: Money(currency: 'EUR', minorUnits: 2000),
                  ),
                  AccountBalance(
                    id: 'qa-euro-reserve',
                    name: 'Account balance',
                    iban: 'BE12345678905678',
                    balance: Money(currency: 'EUR', minorUnits: 1500),
                    available: Money(currency: 'EUR', minorUnits: 1500),
                  ),
                  AccountBalance(
                    id: 'qa-long-name-account',
                    name: longAccountName,
                    iban: 'GB29NWBK60161331909012',
                    balance: Money(currency: 'GBP', minorUnits: 3500),
                    available: Money(currency: 'GBP', minorUnits: 3500),
                  ),
                ]),
          ], child: const TransactionsScreen()),
          Size(width, 1000),
          light: false,
          reducedMotion: true,
          ledger: [
            _sourceTransaction('Bank transfer received', 'transfer',
                currency: 'EUR',
                amount: 25,
                metadata: {'accountId': 'qa-euro-operating'}),
            _sourceTransaction('Monthly account fee', 'fees',
                currency: 'EUR',
                amount: -2,
                metadata: {'accountId': 'qa-euro-reserve'}),
          ],
        );
        final dropdown =
            find.byKey(const ValueKey('activity-account-dropdown'));
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        for (final label in const [
          'All accounts',
          'EUR account · BE***1234',
          'EUR account · BE***5678',
          '$longAccountName · GBP · GB***9012',
        ]) {
          final text = find.text(label).last;
          expect(text, findsOneWidget);
          final paragraph = tester.renderObject<RenderParagraph>(text);
          expect(paragraph.didExceedMaxLines, isFalse,
              reason: 'The open account menu must keep "$label" readable.');
          final bounds = tester.getRect(text);
          expect(bounds.left, greaterThanOrEqualTo(0));
          expect(bounds.right, lessThanOrEqualTo(width));
          expect(bounds.top, greaterThanOrEqualTo(0));
          expect(bounds.bottom, lessThanOrEqualTo(1000));
        }
        await _writeActivityScreenshot(
            tester, 'activity-${width.toInt()}-open-account-menu.png');
        expect(tester.takeException(), isNull);
      });
    }
    for (final width in [320.0, 393.0, 1440.0]) {
      testWidgets('Activity toolbar QA captures at $width', (tester) async {
        const accountId = 'qa-euro-account';
        await _pumpAt(
          tester,
          ProviderScope(overrides: [
            accountsProvider.overrideWith((ref) async => const [
                  AccountBalance(
                    id: accountId,
                    name: 'Euro account',
                    iban: 'BE12345678901234',
                    balance: Money(currency: 'EUR', minorUnits: 2000),
                    available: Money(currency: 'EUR', minorUnits: 2000),
                  ),
                  AccountBalance(
                    id: 'qa-usd-account',
                    name: 'Dollar account',
                    iban: 'BE12345678905678',
                    balance: Money(currency: 'USD', minorUnits: 0),
                    available: Money(currency: 'USD', minorUnits: 0),
                  ),
                ]),
          ], child: const TransactionsScreen()),
          Size(width, 1000),
          light: false,
          reducedMotion: true,
          ledger: [
            _sourceTransaction('Monthly account fee', 'fees',
                currency: 'EUR',
                amount: -2,
                metadata: {'accountId': accountId}),
            _sourceTransaction('Bank transfer received', 'transfer',
                currency: 'EUR',
                amount: 25,
                metadata: {'accountId': accountId}),
            _sourceTransaction('Dollar transfer', 'transfer',
                amount: 42, metadata: {'accountId': 'qa-usd-account'}),
          ],
        );
        await _writeActivityScreenshot(
            tester, 'activity-${width.toInt()}-all-accounts.png');
        await _selectActivityAccount(tester, 'Euro account · EUR · BE***1234');
        expect(
            tester
                .widget<DropdownButton<String>>(
                    find.byKey(const ValueKey('activity-account-dropdown')))
                .value,
            'account:qa-euro-account:EUR');
        await _writeActivityScreenshot(
            tester, 'activity-${width.toInt()}-selected-account.png');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
      'All In Out preserve amount direction and include zero only in All',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(393, 852),
      light: false,
      ledger: [
        _tx(
            id: 'incoming',
            title: 'Incoming payment',
            minorUnits: 500,
            bookedAt: _today),
        _tx(
            id: 'outgoing',
            title: 'Outgoing payment',
            minorUnits: -300,
            bookedAt: _today),
        _tx(
            id: 'zero',
            title: 'Zero authorization',
            minorUnits: 0,
            bookedAt: _today),
      ],
    );
    expect(find.byKey(const ValueKey<String>('incoming')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('outgoing')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('zero')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('zero')),
        matching: find.text('+\$0.00'),
      ),
      findsNothing,
    );

    await tester.tap(find.text('In'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('incoming')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('outgoing')), findsNothing);
    expect(find.byKey(const ValueKey<String>('zero')), findsNothing);

    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('incoming')), findsNothing);
    expect(find.byKey(const ValueKey<String>('outgoing')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('zero')), findsNothing);

    await _selectActivityDirection(tester, 'All');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('incoming')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('outgoing')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('zero')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Type options reflect assets while retaining selected card scope',
      (tester) async {
    final card = _sourceTransaction('Card debit', 'card_payment', cardId: '1');
    final crypto = _sourceTransaction('Crypto credit', 'crypto_deposit',
        currency: 'USDC', amount: 20);
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          cardsProvider.overrideWith((ref) async => [
                PaymentCard.fromJson(
                    {'id': '1', 'label': 'Metal', 'last4': '1234'}),
              ]),
          activityCardTransactionsProvider
              .overrideWith((ref, id) async => [card]),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false,
        ledger: [card, crypto]);
    await _selectActivityType(tester, 'Card');
    await _selectActivityScope(tester, 'Metal · •••• 1234');
    await _selectActivityAsset(tester, 'Crypto');
    final scope = find.byKey(const ValueKey('activity-scope-dropdown'));
    expect(tester.widget<DropdownButton<String>>(scope).value, '1');
    expect(find.byKey(const ValueKey('activity-active-type')), findsNothing);
    expect(find.byKey(const ValueKey<String>('Crypto credit')), findsNothing,
        reason:
            'An empty card scope must not switch to unrelated global rows.');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Card debit')), findsNothing);
    await _selectActivityScope(tester, 'All cards');
    expect(find.byKey(const ValueKey<String>('Crypto credit')), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<Object>));
    await tester.pumpAndSettle();
    expect(find.text('Card'), findsNothing,
        reason: 'This crypto view has no actual card transactions.');
    expect(find.text('Account').last, findsOneWidget);
    expect(find.text('Fee'), findsNothing);
    await tester.tap(find.text('All types'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending or failed global refresh does not clear selected card',
      (tester) async {
    final card =
        _sourceTransaction('Card purchase', 'card_payment', cardId: '1');
    final refresh = Completer<List<LedgerTransaction>>();
    var loads = 0;
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          activityTransactionsProvider.overrideWith((ref) {
            loads++;
            return loads == 1 ? Future.value([card]) : refresh.future;
          }),
          cardsProvider.overrideWith((ref) async => [
                PaymentCard.fromJson(
                    {'id': '1', 'label': 'Metal', 'last4': '1234'}),
              ]),
          activityCardTransactionsProvider
              .overrideWith((ref, id) async => [card]),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false);
    await _selectActivityType(tester, 'Card');
    await _selectActivityScope(tester, 'Metal · •••• 1234');
    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsScreen)));
    container.invalidate(activityTransactionsProvider);
    await tester.pump();
    await _selectActivityAsset(tester, 'Crypto');
    final scope = find.byKey(const ValueKey('activity-scope-dropdown'));
    expect(tester.widget<DropdownButton<String>>(scope).value, '1');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    refresh.completeError(StateError('Global activity refresh failed'));
    await tester.pumpAndSettle();
    await _selectActivityDirection(tester, 'In');
    expect(tester.widget<DropdownButton<String>>(scope).value, '1');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';

    for (final (label, size) in _viewports) {
      testWidgets('ledger lays out at $label in $theme', (tester) async {
        await _pumpAt(tester, const TransactionsScreen(), size, light: light);

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);

        // Scroll past the expanded flow summary to inspect the dated ledger.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
        await tester.pumpAndSettle();
        // The ledger is dated and the pending block is hoisted out of it.
        expect(find.text('Today'), findsOneWidget);
        expect(find.text('Yesterday'), findsOneWidget);

        // Twice: once as the block heading, once as the pill on the row it
        // owns. Redundant encoding is the point — neither is load-bearing on
        // its own.
        expect(find.text('Pending'), findsNWidgets(2));

        // Position, not colour, carries "not final yet". `.first` is the
        // heading: the header sliver is built before the rows it heads.
        expect(
          tester.getTopLeft(find.text('Pending').first).dy,
          lessThan(tester.getTopLeft(find.text('Today')).dy),
        );
      });

      testWidgets('receipt lays out at $label in $theme', (tester) async {
        await _pumpAt(
          tester,
          const TransactionDetailScreen(transactionId: 'tx-today'),
          size,
          light: light,
        );

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);

        // Settlement is drawn as a track, so the state is legible without
        // reading a colour, and the status word is not also repeated as a
        // fact row. 'Booked' is the track's first node plus the record's
        // timestamp label; the track states what, the record states when.
        expect(find.text('Booked'), findsNWidgets(2));
        expect(find.text('Settled'), findsOneWidget);
        expect(find.text('Status'), findsNothing);
      });
    }
  }

  // A merchant name longer than its column must ellipsize, which is the row's
  // designed behaviour, and must never overflow, which is a bug. The
  // no-truncation rule above covers the copy this app writes; this covers the
  // copy a payment network sends.
  testWidgets('a pathological merchant name ellipsizes, never overflows',
      (tester) async {
    const name = 'Societe Generale de Restauration Rapide et Traiteur SARL';
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: true,
      ledger: [
        _tx(
          id: 'tx-long',
          title: name,
          minorUnits: -1234567,
          bookedAt: _today,
        ),
      ],
    );
    expect(tester.takeException(), isNull);

    // Ellipsized, and said so. `takeException` on its own passes just as
    // happily on a name that fits, so until this assertion the word
    // "ellipsizes" in the test's own title was the only place the truncation
    // was claimed. `ExampleRow` sets the title `maxLines: 1` with
    // `TextOverflow.ellipsis`, and that combination sets `didExceedMaxLines`
    // exactly when the run was cut.
    final title = tester.renderObject<RenderParagraph>(
      find.descendant(of: find.text(name), matching: find.byType(RichText)),
    );
    expect(
      title.didExceedMaxLines,
      isTrue,
      reason: 'the fixture no longer overruns the title column',
    );
  });

  // The three states the research found missing from Revolut web and ether.fi
  // Cash. They are cheap to ship and expensive to omit, so they are asserted.
  for (final (label, size) in const [
    ('375', Size(375, 812)),
    ('1440', Size(1440, 900)),
  ]) {
    testWidgets('loading lays out at $label', (tester) async {
      await _pumpAt(
        tester,
        const TransactionsScreen(),
        size,
        light: false,
        settle: false,
        load: () => Completer<List<LedgerTransaction>>().future,
      );

      expect(tester.takeException(), isNull);
      // Shape-matched placeholders, never a spinner.
      expect(find.byType(ExampleSkeleton), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  }

  testWidgets('an empty ledger is designed, not blank', (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: true,
      ledger: const [],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('No transactions yet'), findsOneWidget);
    _expectAppCopyIsWhole(tester);
  });

  testWidgets('a failed ledger offers a way back', (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      load: () => Future<List<LedgerTransaction>>.error(
        Exception('ledger unavailable'),
      ),
    );

    expect(find.byType(ErrorState), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    _expectAppCopyIsWhole(tester);
  });

  testWidgets('a pending receipt shows an unsettled track', (tester) async {
    await _pumpAt(
      tester,
      const TransactionDetailScreen(transactionId: 'tx-pending'),
      const Size(393, 852),
      light: false,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Booked'), findsNWidgets(2));
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Settled'), findsNothing);
  });

  // The skeleton reserves a block where the settlement track will be, and the
  // size it reserves is a claim about the track's height that nothing else
  // checks. Pinned here in both directions: the reservation must not shrink
  // below the track (the facts would be pushed down when the receipt lands)
  // and must not grow far past it (the gap becomes a visible hole).
  testWidgets('the receipt skeleton reserves the track it stands in for',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionDetailScreen(transactionId: 'tx-today'),
      const Size(375, 812),
      light: false,
    );

    // The track is the one 220 pt-capped box on the receipt; `Settled` is its
    // second node's label, so the box is found through it rather than by a
    // private type.
    final track = find.ancestor(
      of: find.text('Settled'),
      matching: find.byType(ConstrainedBox),
    );
    expect(track, findsOneWidget);
    final height = tester.getSize(track).height;

    // 34.0 at 375 in the default text scale, against the 44 the skeleton
    // reserves — see `_ExampleDetailLoading`. The window is the reservation's
    // two failure modes, not a tolerance on the measurement.
    expect(height, closeTo(34, 1));
    expect(height, lessThanOrEqualTo(44));
    expect(44 - height, lessThan(16));
  });

  // A declined purchase must not be presented as booked or settled.
  for (final light in const [false, true]) {
    testWidgets('a declined receipt keeps its declined status', (tester) async {
      await _pumpAt(
        tester,
        const TransactionDetailScreen(transactionId: 'tx-declined'),
        const Size(375, 812),
        light: light,
        ledger: [
          _tx(
            id: 'tx-declined',
            title: 'Blue Bottle Coffee',
            minorUnits: -1899,
            bookedAt: _today,
            status: 'declined',
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(ExamplePill),
          matching: find.text('Declined'),
        ),
        findsOneWidget,
      );
      expect(find.text('Settled'), findsNothing);
      expect(find.text('Status'), findsOneWidget);
      _expectAppCopyIsWhole(tester);
    });

    testWidgets('a Hoppa "fail" receipt reads Declined, never Booked',
        (tester) async {
      await _pumpAt(
        tester,
        const TransactionDetailScreen(transactionId: 'tx-fail'),
        const Size(375, 812),
        light: light,
        ledger: [
          _tx(
            id: 'tx-fail',
            title: 'GOOGLE*GOOGLE ONE',
            minorUnits: -2613,
            bookedAt: _today,
            status: 'fail',
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(ExamplePill),
          matching: find.text('Declined'),
        ),
        findsOneWidget,
      );
      // "Booked" survives only as the date row's label, never as a status.
      expect(
        find.descendant(
          of: find.byType(ExamplePill),
          matching: find.text('Booked'),
        ),
        findsNothing,
      );
    });
  }

  testWidgets('day headings scroll away without covering later activity',
      (tester) async {
    // Scroll far enough to move the heading above the viewport while its
    // transactions remain visible.
    final busyDay = <LedgerTransaction>[
      for (var i = 0; i < 14; i++)
        _tx(
          id: 'tx-busy-$i',
          title: 'Merchant $i',
          minorUnits: -100 * (i + 1),
          bookedAt: _today.subtract(Duration(minutes: 20 * (i + 1))),
        ),
      _tx(
        id: 'tx-busy-yesterday',
        title: 'Transport for London',
        minorUnits: -740,
        bookedAt: _today.subtract(const Duration(days: 1, hours: 3)),
      ),
    ];

    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(393, 852),
      light: false,
      ledger: busyDay,
    );

    // The section starts above its own transactions.
    expect(find.text('Today'), findsOneWidget);

    final viewportTop = tester.getTopLeft(find.byType(CustomScrollView)).dy;
    final headingBefore = tester.getTopLeft(find.text('Today')).dy;
    final rowBefore = tester.getTopLeft(find.text('Merchant 0')).dy;
    expect(headingBefore, greaterThanOrEqualTo(viewportTop));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pumpAndSettle();

    // The header leaves the scroll view instead of covering the remaining
    // transactions. Scrolling back restores it above the same rows.
    expect(find.text('Today'), findsNothing);
    final rowAfter = tester.getTopLeft(find.text('Merchant 0')).dy;
    expect(rowBefore - rowAfter, greaterThan(300));
    expect(find.byType(ExampleTransactionRow).hitTestable(), findsWidgets);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Today').hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(find.text('Today')).dy,
        lessThan(tester.getTopLeft(find.text('Merchant 0')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Activity retains direction and asset controls with one net flow',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 852),
        light: false);
    final direction = find.byKey(const ValueKey('activity-direction-filter'));
    final asset = find.byKey(const ValueKey('activity-asset-filter'));
    expect(direction.hitTestable(), findsOneWidget);
    expect(asset.hitTestable(), findsOneWidget);
    expect(tester.getTopLeft(asset).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(direction).dy));
    for (final label in ['All', 'In', 'Out']) {
      expect(find.descendant(of: direction, matching: find.text(label)),
          findsOneWidget);
    }
    for (final label in ['All', 'Fiat', 'Crypto']) {
      expect(find.descendant(of: asset, matching: find.text(label)),
          findsOneWidget);
    }
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(find.byType(ExampleSweepBorder), findsNothing);
    expect(find.byType(PopupMenuButton<Object>).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // A day heading used to be a word floating over a list. It now carries the
  // block's shape: what it is, how many movements it holds, what they came to.
  testWidgets('a day heading carries the shape of its block', (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: true,
    );

    // Today: a 124.50 charge and a 5,400 credit.
    expect(find.text('2 events'), findsOneWidget);
    expect(find.text('\$5,275.50'), findsNothing);

    // The count sits beside the day, not under the rows, and both are on the
    // same 44 pt band.
    final band = tester.getRect(find.text('Today'));
    final count = tester.getRect(find.text('2 events'));
    expect(count.left, greaterThan(band.right));
    expect((count.center.dy - band.center.dy).abs(), lessThan(4));
  });

  // Size and direction, drawn. The claim under test is that a reader can find
  // the big movement and tell which way it went without reading a digit.
  testWidgets('a row draws its magnitude and its direction', (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-in',
          title: 'Salary',
          minorUnits: 200000,
          bookedAt: _today.subtract(const Duration(hours: 1)),
        ),
        _tx(
          id: 'tx-out',
          title: 'Rent',
          minorUnits: -200000,
          bookedAt: _today.subtract(const Duration(hours: 2)),
        ),
        _tx(
          id: 'tx-small',
          title: 'Coffee',
          minorUnits: -500,
          bookedAt: _today.subtract(const Duration(hours: 3)),
        ),
      ],
    );

    final incoming = _band(tester, 'tx-in');
    final outgoing = _band(tester, 'tx-out');
    expect(incoming, isNotNull);
    expect(outgoing, isNotNull);

    // Equal money, equal band. The two largest movements are the same size
    // and the scale says so.
    expect(incoming!.extent, closeTo(outgoing!.extent, 0.001));

    // Direction is which edge the weight sits on, in LTR: money in from the
    // left, money out from the right. That survives greyscale and colour
    // blindness, which a green tint and a plus sign do not.
    expect(incoming.fromStart, isTrue);
    expect(outgoing.fromStart, isFalse);

    // 5.00 against a 2,000 peak is 5 percent of the scale: a smudge, not a
    // quantity. Nothing is painted rather than painting a lie.
    expect(_band(tester, 'tx-small'), isNull);
    expect(tester.takeException(), isNull);
  });

  // A ledger written in more than one currency. The band is a comparison and a
  // comparison needs a common unit, so the rows the ledger is mostly written
  // in are scaled together and every other row is left with no band at all.
  // The path this covers is untouched by every other test here: `_tx` defaults
  // to USD, so a second currency has never rendered in this suite.
  testWidgets('a lone foreign row is left unbanded, never made maximal',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-usd-big',
          title: 'Northwind Ltd',
          minorUnits: 540000,
          bookedAt: _today.subtract(const Duration(hours: 1)),
        ),
        _tx(
          id: 'tx-usd-small',
          title: 'Whole Foods Market',
          minorUnits: -12450,
          bookedAt: _today.subtract(const Duration(hours: 2)),
        ),
        // One fare, in a currency nothing else on this screen is written in.
        // Keyed per currency it was its own maximum — share 1.0, the widest
        // band in the list, drawn the same width as the 5,400 salary above it.
        _tx(
          id: 'tx-jpy',
          title: 'Tokyo Metro',
          minorUnits: -60000,
          bookedAt: _today.subtract(const Duration(hours: 3)),
          currency: 'JPY',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(
      _band(tester, 'tx-jpy'),
      isNull,
      reason: 'a currency with a bucket of one has no scale to be drawn on',
    );

    // The majority currency keeps a scale, and it is that currency's own peak:
    // the salary reaches full width and the grocery run a fraction of it.
    final big = _band(tester, 'tx-usd-big');
    final small = _band(tester, 'tx-usd-small');
    expect(big, isNotNull);
    expect(small, isNotNull);
    expect(big!.extent, greaterThan(small!.extent * 2));

    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    _expectAppCopyIsWhole(tester);
  });

  // The band puts a new ground under type that was signed off against the
  // surface ladder, and the smallest ink standing on it is the 11.5 px
  // settlement caption an FX row writes in tertiary — in the trailing amount
  // column, which is exactly where an outgoing row anchors the band at full
  // strength. So the peak is measured rather than eyeballed, on both levels a
  // block can rest on and in both materials.
  //
  // And measured on the ground the caption actually gets, which is not the
  // block's surface. Every ledger row is given an `onTap`, so
  // `ExampleTransactionRow` arms a `MouseRegion` and paints `ExampleInk.hover`
  // inside the row — on top of the painter, which sits in a `Positioned.fill`
  // underneath it. A real mouse is put on each row here and the wash it arms
  // is read back out of the tree, so the composite below is
  // surface -> band -> hover because that is what the screen does, not
  // because this test assumed it.
  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';

    testWidgets('the magnitude wash stays off the body floor in $theme',
        (tester) async {
      await _pumpAt(
        tester,
        const TransactionsScreen(),
        const Size(375, 812),
        light: light,
        // Four rows at one magnitude, so every one of them is drawn at the
        // wash's peak alpha: two in the pending block (level 2, the darker
        // ground and the tighter of the two) and two in the day below it.
        ledger: [
          _tx(
            id: 'held-out',
            title: 'Rent',
            minorUnits: -200000,
            bookedAt: _today,
            status: 'pending',
          ),
          _tx(
            id: 'held-in',
            title: 'Refund',
            minorUnits: 200000,
            bookedAt: _today.subtract(const Duration(minutes: 30)),
            status: 'pending',
          ),
          _tx(
            id: 'booked-out',
            title: 'Ocado Retail',
            minorUnits: -200000,
            bookedAt: _today.subtract(const Duration(hours: 1)),
          ),
          _tx(
            id: 'booked-in',
            title: 'Northwind Ltd',
            minorUnits: 200000,
            bookedAt: _today.subtract(const Duration(hours: 2)),
          ),
        ],
      );

      expect(tester.takeException(), isNull);
      final palette = ExamplePalette.of(
        tester.element(find.byType(TransactionsScreen)),
      );

      // The calibration: the two grounds the palette publishes a figure for.
      expect(
        _contrast(palette.textTertiary, palette.surfaceLevel(1)),
        closeTo(light ? 5.09 : 5.10, 0.01),
      );
      expect(
        _contrast(palette.textTertiary, palette.surfaceLevel(2)),
        closeTo(light ? 4.88 : 4.84, 0.01),
      );

      // And the figure the level-2 carve-out below turns on, computed from
      // palette tokens alone so it does not depend on anything the band does:
      // the hover wash on its own already spends most of what tertiary has
      // left on a pending row, and it spends more of it in Twilight.
      expect(
        _contrast(
          palette.textTertiary,
          _over(palette.hover, palette.surfaceLevel(2)),
        ),
        closeTo(light ? 4.74 : 4.59, 0.01),
      );

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      addTearDown(mouse.removePointer);

      for (final (id, level) in const [
        ('held-out', 2),
        ('held-in', 2),
        ('booked-out', 1),
        ('booked-in', 1),
      ]) {
        final row = find.byKey(ValueKey<String>(id));
        await tester.scrollUntilVisible(row, 100,
            scrollable: find
                .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable))
                .first);
        await tester.pumpAndSettle();
        final band = _band(tester, id);

        // Twilight level 2 is the one ground that cannot pay for a band: with
        // the hover wash on it the caption has 0.09 of a ratio left before the
        // floor, and the largest alpha that fits under that is .01. So the
        // pending block goes unbanded on night and keeps its band on paper,
        // where the same ground still has 0.24 to spend.
        if (level == 2 && !light) {
          expect(
            band,
            isNull,
            reason: 'Twilight level 2 has no headroom for a band and must '
                'not paint one',
          );
          continue;
        }
        expect(band, isNotNull, reason: '$id draws no band to measure');

        // The pointer has not reached this row yet, so its hover wash is off.
        Finder hoverWash() => find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is AnimatedContainer &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration! as BoxDecoration).color ==
                        palette.hover,
              ),
            );
        expect(hoverWash(), findsNothing);

        await mouse.moveTo(tester.getCenter(row));
        await tester.pumpAndSettle();
        expect(
          hoverWash(),
          findsOneWidget,
          reason: '$id arms no hover wash under a pointer, so the ground '
              'measured below is not the one it renders',
        );

        // Paint order: surface, then the band under the row, then the hover
        // wash the row paints inside itself, then the caption.
        final washed = _over(
          palette.hover,
          _over(band!.color, palette.surfaceLevel(level)),
        );
        expect(
          _contrast(palette.textTertiary, washed),
          greaterThanOrEqualTo(4.5),
          reason: '$id: the wash puts the settlement caption under the '
              'body floor tertiary ink exists to hold',
        );
      }

      // The carve-out is exactly one material wide. Paper's pending rows are
      // still banded, so the encoding is not quietly gone from the product.
      if (light) {
        expect(_band(tester, 'held-out'), isNotNull);
        expect(_band(tester, 'held-in'), isNotNull);
      }
    });
  }

  // One sheen clock per screen. Both of these screens are ShellRoute children
  // and the shell already runs a clock, so a scope of their own would be a
  // second ticker on a second schedule.
  //
  // What this does *not* prove is a kill switch, and the screens do not claim
  // one: `ExampleAliveLayer(enabled: false)` returns its child bare rather than
  // publishing a switched-off binding, so `existsAbove` cannot tell it from no
  // layer at all and both screens would still mount a scope under one. The
  // layer here is the default, enabled one, which is the case that exists in
  // the app — both of `BankingShell`'s take the default.
  testWidgets('neither screen starts a second sheen clock under the shell',
      (tester) async {
    await _pumpAt(
      tester,
      const ExampleAliveLayer(child: TransactionsScreen()),
      const Size(375, 812),
      light: false,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ExampleSheenScope), findsOneWidget);

    // The receipt's loading skeleton has the same shape and the same fix.
    await _pumpAt(
      tester,
      const ExampleAliveLayer(
        child: TransactionDetailScreen(transactionId: 'tx-today'),
      ),
      const Size(375, 812),
      light: false,
      settle: false,
      load: () => Completer<List<LedgerTransaction>>().future,
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ExampleSheenScope), findsOneWidget);
  });

  testWidgets('hosted alone, the ledger still supplies its own clock',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
    );
    expect(find.byType(ExampleSheenScope), findsOneWidget);
  });

  // Reduced motion is the final visual state, reached instantly — the
  // convention every other Example suite carries, and the one this screen
  // needs now that it hosts a sheen and a swept rim.
  //
  // *When* the count is taken is the whole test, and this one used to take it
  // at the wrong moment: two pumps in, `transientCallbackCount` is zero with
  // motion switched on as well, because the arrival sweep has not started yet.
  // Flipping `reducedMotion` to false left the test passing, which is the
  // definition of a guard that guards nothing.
  //
  // Probed on this fixture at 375 in twilight, stepping 200 ms at a time, the
  // full-motion count runs 0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0 — the sweep
  // starts near 600 ms, ends near 2 s, and the scope then waits on a timer
  // rather than a ticker until its next cadence. So the count is taken at all
  // twelve of those steps: eight of them are moments a full-motion tree has a
  // ticker registered, and reduced motion must have none at any of them.
  testWidgets('reduced motion lands the ledger finished on the first frame',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _app(const TransactionsScreen(), light: false, reducedMotion: true),
    );
    // One frame to resolve the provider, one to build the data state.
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Today'), findsOneWidget);

    for (var step = 1; step <= 12; step++) {
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'an animation is still running under reduced motion, '
            'at ${step * 200} ms',
      );
    }
  });

  // The skeleton is the one state on this screen that loops rather than
  // sweeping once and stopping, so a reduced-motion leak here would be
  // permanent rather than momentary — and it is the state a slow network
  // leaves a viewer sitting in. Probed the same way: with motion on, the first
  // frame holds nine tickers and every frame from 360 ms on holds one, for as
  // long as the load is outstanding; with reduced motion there are none at any
  // of those moments.
  testWidgets('reduced motion leaves the loading skeleton without a clock',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(375, 812));
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _app(
        const TransactionsScreen(),
        light: false,
        reducedMotion: true,
        load: () => Completer<List<LedgerTransaction>>().future,
      ),
    );

    expect(find.byType(ExampleSkeleton), findsWidgets);
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason: 'the skeleton started a ticker on its first frame',
    );
    for (var step = 1; step <= 8; step++) {
      await tester.pump(const Duration(milliseconds: 120));
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'the skeleton is still looping under reduced motion, '
            'at ${step * 120} ms',
      );
    }
  });

  // Wide individual amounts remain complete beside the net-flow summary.
  testWidgets('a seven-figure row amount remains whole', (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-huge',
          title: 'Ocado Retail',
          minorUnits: -1234567890,
          bookedAt: _today,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    final amount = find.descendant(
      of: find.byKey(const ValueKey<String>('tx-huge')),
      matching: find.text('-\$12,345,678.90'),
    );
    expect(amount, findsOneWidget);

    _expectAppCopyIsWhole(tester);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tx-huge')),
        matching: find.text('15:24'),
      ),
      findsOneWidget,
      reason: 'the row beside a seven-figure amount should have compacted',
    );
    _expectKindKeptWhereverItFits(tester, const ['tx-huge']);
  });

  // Header controls and row copy remain legible at larger text sizes.
  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';
    for (final scale in const [1.3, 1.5]) {
      testWidgets('the ledger holds its copy at ${scale}x text in $theme',
          (tester) async {
        await _pumpAt(
          tester,
          const TransactionsScreen(),
          const Size(375, 812),
          light: light,
          textScale: scale,
        );

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);

        expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
        expect(find.byKey(const ValueKey('activity-asset-filter')),
            findsOneWidget);
      });
    }
  }

  // The trade the ledger makes for a larger text size, checked where it is
  // actually paid rather than only at 375.
  //
  // The rule this replaced had no width term: it compared the scaled point
  // size of the descriptor against one ceiling measured on a 375 phone and
  // applied the answer at every width. From 1.101x up that took the kind off
  // every row of an 834 or 1440 ledger whose descriptor column had four
  // hundred points to spare, and nothing here saw it, because every scaled
  // test ran at 375.
  //
  // 834 and 1440 are the two viewports where the column is wide enough that
  // no scale in the supported range can justify the trade, so they are the
  // ones that pin it. Widths are identical in both themes — the palette
  // changes no metric — so the sweep runs in Twilight and daylight is spot
  // checked at the two ends.
  for (final (label, size) in _viewports) {
    for (final scale in const [1.0, 1.15, 1.3, 1.5]) {
      testWidgets('the kind survives at $label as long as $scale' 'x fits',
          (tester) async {
        await _pumpAt(
          tester,
          const TransactionsScreen(),
          size,
          light: label == '375' || label == '1440',
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -240));
        await tester.pumpAndSettle();
        _expectKindKeptWhereverItFits(
          tester,
          [for (final item in _ledger) item.id],
        );
      });
    }
  }

  // The same claim stated as a fact rather than as an invariant, on the two
  // viewports and the one scale where the old rule was most obviously wrong:
  // an 834 tablet at 1.5x has 580 pt of descriptor column and needs 177.
  for (final (label, size) in const <(String, Size)>[
    ('834', Size(834, 1194)),
    ('1440', Size(1440, 900)),
  ]) {
    testWidgets('a $label ledger keeps the kind at 1.5x text', (tester) async {
      await _pumpAt(
        tester,
        const TransactionsScreen(),
        size,
        light: false,
        textScale: 1.5,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tx-today')),
          matching: find.text('10:24 \u00b7 Card Payment'),
        ),
        findsOneWidget,
        reason: 'the kind was dropped on a ledger with room for it',
      );
    });
  }

  // A currency with no symbol, at the width where the amount column has to be
  // modelled to the point.
  //
  // `Money.formatAmount` appends " AED" to a currency it has no symbol for,
  // and `ExampleAmount` peels that code off and sets it at 11 pt beside 18 pt
  // numerals. A row that measured the raw formatted string at the numerals'
  // size would read its own amount column about twelve points too wide and
  // take the kind off a line that had room. -12,345.67 AED at 375 leaves the
  // descriptor 120.2 pt for a 118.1 pt string: it fits by two points, and
  // only if the code is measured the way it is drawn.
  testWidgets('a code-suffixed amount is measured the way it is set',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-aed',
          title: 'Emirates NBD',
          minorUnits: -1234567,
          bookedAt: _today,
          currency: 'AED',
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    _expectKindKeptWhereverItFits(tester, const ['tx-aed']);
    expect(find.text('15:24 \u00b7 Card Payment'), findsOneWidget);
    _expectAppCopyIsWhole(tester);
  });

  // The decision is the row's, not the screen's. One seven-figure amount in a
  // day takes the kind off its own row and leaves the row under it alone, in
  // the same block, at the same width and the same text scale — which is the
  // whole reason it is measured per row instead of switched by a rule the
  // ledger applies to everything at once.
  testWidgets('one wide amount compacts its own row and no other',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-wide',
          title: 'Ocado Retail',
          minorUnits: -1234567890,
          bookedAt: _today,
        ),
        _tx(
          id: 'tx-narrow',
          title: 'Transport for London',
          minorUnits: -740,
          bookedAt: _today.subtract(const Duration(hours: 1)),
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tx-wide')),
        matching: find.text('15:24'),
      ),
      findsOneWidget,
      reason: 'the seven-figure row should have dropped its kind',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tx-narrow')),
        matching: find.text('14:24 \u00b7 Card Payment'),
      ),
      findsOneWidget,
      reason: 'the row beside it had room and should have kept its kind',
    );
    _expectKindKeptWhereverItFits(tester, const ['tx-wide', 'tx-narrow']);
    _expectAppCopyIsWhole(tester);
  });

  // An FX row's settlement caption shares the trailing column with the amount
  // and can be the wider of the two, so it is the caption that decides what
  // the descriptor has left. A $7.40 payment out of a yen balance writes
  // `-12,345,678,901.23 JPY` under `-$7.40`: measured at 375, the amount on
  // its own leaves the descriptor 183.0 pt — that is exactly what the same
  // -$7.40 row gets in the main ledger — and the caption cuts it to 111.7,
  // which is 6.5 short of the 118.1 `15:24 · Card Payment` wants. A row that
  // weighed only its amount would keep the kind and ellipsize it.
  testWidgets('an FX row measures the caption under its amount',
      (tester) async {
    await _pumpAt(
      tester,
      const TransactionsScreen(),
      const Size(375, 812),
      light: false,
      ledger: [
        _tx(
          id: 'tx-fx',
          title: 'Emirates NBD',
          minorUnits: -1234567890123,
          currency: 'JPY',
          transactionAmount: const Money(currency: 'USD', minorUnits: -740),
          bookedAt: _today,
        ),
      ],
    );

    expect(tester.takeException(), isNull);
    // Scope the assertion to the row whose settlement caption is measured.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tx-fx')),
        matching: find.text('-12,345,678,901.23 JPY'),
      ),
      findsOneWidget,
    );
    _expectKindKeptWhereverItFits(tester, const ['tx-fx']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('tx-fx')),
        matching: find.text('15:24'),
      ),
      findsOneWidget,
      reason: 'the row should have compacted for its own settlement caption',
    );
    _expectAppCopyIsWhole(tester);
  });

  testWidgets('header filters keep their position while activity loads',
      (tester) async {
    final gate = Completer<List<LedgerTransaction>>();
    await _pumpAt(tester, const TransactionsScreen(), const Size(375, 812),
        light: false, settle: false, load: () => gate.future);
    final direction = find.byKey(const ValueKey('activity-direction-filter'));
    final assets = find.byKey(const ValueKey('activity-asset-filter'));
    final directionRect = tester.getRect(direction);
    final assetsRect = tester.getRect(assets);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsNothing);
    gate.complete([
      _tx(
          id: 'tx-usd',
          title: 'Ocado Retail',
          minorUnits: -1000,
          bookedAt: _today),
    ]);
    await tester.pumpAndSettle();
    expect(tester.getRect(direction), directionRect);
    expect(tester.getRect(assets), assetsRect);
    expect(find.text('Ocado Retail'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active chips remove one filter and Clear all restores the feed',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          _sourceTransaction('USD credit', 'transfer', amount: 10),
          _sourceTransaction('USDC debit', 'crypto_withdrawal',
              currency: 'USDC', amount: 5),
        ]);
    await _selectActivityDirection(tester, 'Out');
    await _selectActivityAsset(tester, 'Crypto');
    expect(find.byKey(const ValueKey('activity-active-direction')),
        findsOneWidget);
    final assetChip = find.byKey(const ValueKey('activity-active-asset'));
    expect(assetChip, findsOneWidget);
    await tester.ensureVisible(assetChip);
    await tester.tap(find.byTooltip('Remove Assets: Crypto filter'));
    await tester.pumpAndSettle();
    expect(assetChip, findsNothing);
    expect(find.byKey(const ValueKey('activity-active-direction')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('USD credit')), findsNothing);
    final clear = find.byKey(const ValueKey('activity-clear-filters'));
    await tester.ensureVisible(clear);
    await tester.tap(clear);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('activity-active-filters')), findsNothing);
    expect(find.byKey(const ValueKey<String>('USD credit')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('USDC debit')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing API booking date is labelled instead of shown as Today',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          LedgerTransaction.fromJson({
            'id': 'undated',
            'title': 'Undated API payment',
            'type': 'transfer',
            'amount': -5,
            'currency': 'USD',
            'status': 'completed',
          }),
          _sourceTransaction('Known payment', 'transfer'),
        ]);
    expect(find.text('Date unavailable'), findsOneWidget);
    expect(find.text('Time unavailable'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Date unavailable')).dy,
        lessThan(tester.getTopLeft(find.text('Undated API payment')).dy));
    expect(tester.getTopLeft(find.text('Undated API payment')).dy,
        lessThan(tester.getTopLeft(find.text('Today')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'route currency keeps account activity in its actual denomination',
      (tester) async {
    await _pumpAt(
        tester,
        const TransactionsScreen(accountId: 'wallet-1', currency: ' eur '),
        const Size(393, 1000),
        light: false,
        ledger: [
          _sourceTransaction('EUR movement', 'transfer', currency: 'EUR'),
          _sourceTransaction('RON movement', 'transfer', currency: 'RON'),
        ]);
    expect(find.byKey(const ValueKey<String>('EUR movement')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('RON movement')), findsNothing);
    await _selectActivityAsset(tester, 'All');
    expect(find.byKey(const ValueKey<String>('EUR movement')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('RON movement')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'budget activity excludes siblings sharing the same parent account',
      (tester) async {
    const parent = 'parent-account';
    const budget = 'selected-budget';
    final rows = [
      _sourceTransaction('Selected EUR budget movement', 'transfer',
          currency: 'EUR', metadata: {'accountId': parent, 'budgetId': budget}),
      _sourceTransaction('Sibling EUR budget movement', 'transfer',
          currency: 'EUR',
          metadata: {'accountId': parent, 'budgetId': 'sibling-budget'}),
      _sourceTransaction('Selected RON budget movement', 'transfer',
          currency: 'RON', metadata: {'accountId': parent, 'budgetId': budget}),
      _sourceTransaction('Parent-only EUR movement', 'transfer',
          currency: 'EUR', metadata: {'accountId': parent}),
    ];
    await _pumpAt(
        tester,
        ProviderScope(
            overrides: [
              accountsProvider.overrideWith((ref) async => const []),
            ],
            child: const TransactionsScreen(
                accountId: parent, budgetId: budget, currency: 'EUR')),
        const Size(393, 1000),
        light: false,
        ledger: rows);
    expect(find.byKey(const ValueKey<String>('Selected EUR budget movement')),
        findsOneWidget);
    for (final id in [
      'Sibling EUR budget movement',
      'Selected RON budget movement',
      'Parent-only EUR movement'
    ]) {
      expect(find.byKey(ValueKey<String>(id)), findsNothing);
    }
    expect(
        tester
            .widget<TransactionPdfExportButton>(
                find.byType(TransactionPdfExportButton))
            .transactions
            ?.map((row) => row.id),
        ['Selected EUR budget movement']);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'PDF action receives the visible subset and disables during refresh failure',
      (tester) async {
    final rows = [
      _sourceTransaction('USD transfer', 'transfer', amount: -20),
      _sourceTransaction('USDC deposit', 'crypto_deposit',
          currency: 'USDC', amount: 10),
      _sourceTransaction('USDC withdrawal', 'crypto_withdrawal',
          currency: 'USDC', amount: 5),
    ];
    final refresh = Completer<List<LedgerTransaction>>();
    var loads = 0;
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          activityTransactionsProvider.overrideWith((ref) {
            loads++;
            return loads == 1 ? Future.value(rows) : refresh.future;
          }),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false);
    await _selectActivityAsset(tester, 'Crypto');
    await _selectActivityDirection(tester, 'Out');
    final export = find.byType(TransactionPdfExportButton);
    expect(
        tester
            .widget<TransactionPdfExportButton>(export)
            .transactions
            ?.map((row) => row.id),
        ['USDC withdrawal']);

    final container = ProviderScope.containerOf(
        tester.element(find.byType(TransactionsScreen)));
    container.invalidate(activityTransactionsProvider);
    await tester.pump();
    await tester.pump();
    expect(
        tester.widget<TransactionPdfExportButton>(export).transactions, isNull);
    expect(
        tester
            .widget<IconButton>(
                find.descendant(of: export, matching: find.byType(IconButton)))
            .onPressed,
        isNull);
    refresh.completeError(StateError('Activity refresh failed'));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TransactionPdfExportButton>(export).transactions, isNull);
    expect(
        tester
            .widget<IconButton>(
                find.descendant(of: export, matching: find.byType(IconButton)))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'card identity remains readable beside timestamp and amount at 320',
      (tester) async {
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          cardsProvider.overrideWith((ref) async => [
                PaymentCard.fromJson(
                    {'id': '1', 'label': 'Metal', 'last4': '1462'}),
              ]),
        ], child: const TransactionsScreen()),
        const Size(320, 700),
        light: false,
        ledger: [
          _sourceTransaction('Identified card payment', 'card_payment',
              cardId: '1', amount: -12.34),
        ]);
    final row = find.byKey(const ValueKey<String>('Identified card payment'));
    final identity =
        find.descendant(of: row, matching: find.text('Card •••• 1462'));
    final amount = find.descendant(of: row, matching: find.text('-\$12.34'));
    expect(identity, findsOneWidget);
    expect(amount, findsOneWidget);
    expect(tester.getRect(identity).overlaps(tester.getRect(amount)), isFalse);
    expect(tester.getBottomRight(identity).dx,
        lessThanOrEqualTo(tester.getBottomRight(row).dx));
    expect(find.descendant(of: row, matching: find.textContaining('15:24')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mixed-currency activity retains fiat and crypto row amounts',
      (tester) async {
    final ledger = [
      LedgerTransaction.fromJson({
        'id': 'usd-deposit',
        'title': 'Bank deposit',
        'amount': 550,
        'currency': 'USD',
        'type': 'deposit',
        'status': 'completed',
        'bookedAt': _today.toIso8601String(),
      }),
      LedgerTransaction.fromJson({
        'id': 'usdc-withdrawal',
        'title': 'Crypto withdrawal',
        'amount': 550,
        'currency': 'USDC',
        'type': 'crypto_withdrawal',
        'status': 'completed',
        'bookedAt': _today.toIso8601String(),
      }),
      LedgerTransaction.fromJson({
        'id': 'related-credit',
        'title': 'Related funding entry',
        'amount': 550,
        'currency': 'USD',
        'type': 'transfer',
        'isPrimary': false,
        'status': 'completed',
        'bookedAt': _today.toIso8601String(),
      }),
    ];
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 852),
        light: false, ledger: ledger);
    expect(find.byKey(const ValueKey<String>('usd-deposit')), findsOneWidget);
    final withdrawal = find.byKey(const ValueKey<String>('usdc-withdrawal'));
    expect(find.descendant(of: withdrawal, matching: find.text('-550.00 USDC')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('related-credit')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    await _selectActivityDirection(tester, 'Out');
    expect(withdrawal, findsOneWidget);
    expect(find.byKey(const ValueKey<String>('usd-deposit')), findsNothing);
    expect(find.byKey(const ValueKey<String>('related-credit')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account scope includes its related funding debit',
      (tester) async {
    await _pumpAt(
        tester,
        const TransactionsScreen(accountId: 'wallet-1', accountName: 'USD'),
        const Size(393, 852),
        light: false,
        ledger: [
          LedgerTransaction.fromJson({
            'id': 'wallet-debit',
            'walletId': 'wallet-1',
            'title': 'Card funding',
            'amount': -50,
            'currency': 'USD',
            'type': 'transfer',
            'isPrimary': false,
            'status': 'completed',
            'bookedAt': _today.toIso8601String(),
          }),
        ]);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey<String>('wallet-debit')),
            matching: find.text('-\$50.00')),
        findsOneWidget);
    expect(find.text('Card funding'), findsOneWidget);
  });

  testWidgets('small crypto withdrawals retain precision and remain in Out',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 852),
        light: false,
        ledger: [
          LedgerTransaction.fromJson({
            'id': 'btc-withdrawal',
            'title': 'Bitcoin withdrawal',
            'amount': 0.00012345,
            'currency': 'BTC',
            'type': 'crypto_withdrawal',
            'status': 'completed',
            'bookedAt': _today.toIso8601String(),
          }),
        ]);
    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();
    final row = find.byKey(const ValueKey<String>('btc-withdrawal'));
    expect(find.descendant(of: row, matching: find.text('-0.00012345 BTC')),
        findsOneWidget);
    expect(find.text('Bitcoin withdrawal'), findsOneWidget);
    expect(find.text('Nothing matches those filters'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  for (final light in [false, true]) {
    testWidgets('card picker uses card API and preserves direction ($light)',
        (tester) async {
      final first = _sourceTransaction('First card purchase', 'card_payment',
          cardId: '1');
      final second = _sourceTransaction('Second card refund', 'card_refund',
          cardId: '2', amount: 20);
      final requests = <String>[];
      await _pumpAt(
          tester,
          ProviderScope(overrides: [
            cardsProvider.overrideWith((ref) async => [
                  PaymentCard.fromJson(
                      {'id': '1', 'label': 'Metal', 'last4': '1234'}),
                  PaymentCard.fromJson(
                      {'id': '2', 'label': 'Virtual', 'last4': '5678'}),
                ]),
            activityCardTransactionsProvider.overrideWith((ref, id) async {
              requests.add(id);
              return id == '1' ? [first] : [second];
            }),
          ], child: const TransactionsScreen()),
          const Size(393, 1000),
          light: light,
          ledger: [first, second]);
      await _selectActivityType(tester, 'Card');
      expect(find.text('All cards'), findsOneWidget);
      await _selectActivityScope(tester, 'Metal · •••• 1234');
      expect(requests, ['1']);
      expect(find.byKey(const ValueKey<String>('First card purchase')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('Second card refund')),
          findsNothing);
      await tester.tap(find.text('In'));
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches those filters'), findsOneWidget);
      await _selectActivityScope(tester, 'All cards');
      expect(find.byKey(const ValueKey<String>('Second card refund')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('First card purchase')),
          findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account picker matches provider account IDs in ledger metadata',
      (tester) async {
    const firstId = '73bceaa1-a892-4f09-a363-3a88526f1668';
    const secondId = '4cbf1482-6959-4767-b8d2-c2e659e7831d';
    final first = _sourceTransaction('Current account transfer', 'transfer',
        metadata: {'accountId': firstId});
    final second = _sourceTransaction('Savings account transfer', 'transfer',
        amount: 50,
        metadata: {
          'destination': {'accountId': secondId}
        });
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          accountsProvider.overrideWith((ref) async => [
                for (final entry in [
                  (firstId, 'Current'),
                  (secondId, 'Savings'),
                  (firstId, 'Current')
                ])
                  AccountBalance(
                      id: entry.$1,
                      name: entry.$2,
                      iban: '',
                      balance: const Money(currency: 'USD', minorUnits: 0),
                      available: const Money(currency: 'USD', minorUnits: 0)),
              ]),
          activityAccountTransactionsProvider.overrideWith((ref, id) async {
            fail('Provider account IDs must not be sent as numeric wallet IDs');
          }),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false,
        ledger: [first, second]);
    expect(find.text('All accounts'), findsOneWidget);
    await _selectActivityAccount(tester, 'Savings · USD');
    expect(find.byKey(const ValueKey<String>('Savings account transfer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Current account transfer')),
        findsNothing);
    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    await _selectActivityAccount(tester, 'All accounts');
    expect(find.byKey(const ValueKey<String>('Current account transfer')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card API-only fee survives account filtering and PDF export',
      (tester) async {
    const accountId = 'linked-account';
    const accountLabel = 'Current · USD · BE***1234';
    final purchase = _sourceTransaction('Known card purchase', 'card_payment',
        cardId: '1', metadata: {'accountId': accountId});
    // A card endpoint can return a newer fee absent from the cached global
    // ledger, with ownership in metadata but no redundant cardId field.
    final fee = _sourceTransaction('Card API fee only', 'fees',
        amount: -2.25, metadata: {'accountId': accountId});
    final otherAccountFee = _sourceTransaction(
        'Different account card fee', 'fees',
        amount: -9, metadata: {'accountId': 'other-account'});
    final requests = <String>[];
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          cardsProvider.overrideWith((ref) async => [
                PaymentCard.fromJson(
                    {'id': '1', 'label': 'Metal', 'last4': '1234'}),
              ]),
          accountsProvider.overrideWith((ref) async => const [
                AccountBalance(
                  id: accountId,
                  name: 'Current',
                  iban: 'BE12345678901234',
                  balance: Money(currency: 'USD', minorUnits: 0),
                  available: Money(currency: 'USD', minorUnits: 0),
                ),
              ]),
          activityCardTransactionsProvider.overrideWith((ref, id) async {
            requests.add(id);
            return [purchase, fee, otherAccountFee];
          }),
          activityAccountTransactionsProvider.overrideWith((ref, id) async {
            fail('Account UI scope must not replace the selected card feed');
          }),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false,
        ledger: [purchase]);
    await _selectActivityType(tester, 'Card');
    await _selectActivityScope(tester, 'Metal · •••• 1234');
    await _selectActivityAccount(tester, accountLabel);
    expect(find.byKey(const ValueKey<String>('Card API fee only')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Different account card fee')),
        findsNothing);

    // Type choices must use the same selected-card snapshot as the list.
    await _selectActivityType(tester, 'Fee');
    await _selectActivityDirection(tester, 'Out');
    await _selectActivityAsset(tester, 'Fiat');
    expect(requests, ['1']);
    expect(find.byKey(const ValueKey<String>('Card API fee only')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Known card purchase')),
        findsNothing);
    final export = tester.widget<TransactionPdfExportButton>(
        find.byType(TransactionPdfExportButton));
    expect(export.transactions, [fee]);
    expect(export.filters, contains('Account: $accountLabel'));
    expect(export.filters, contains('Card •••• 1234'));
    expect(export.filters, contains('Type: Fee'));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account selection persists across Fee, direction and asset filters',
      (tester) async {
    const ownedId = 'owned-bank-account';
    const emptyId = 'empty-bank-account';
    const selectedKey = 'account:owned-bank-account:USD';
    const accountLabel = 'Current · USD · BE***1234';
    final fee = _sourceTransaction('Selected account fee', 'fees',
        amount: -2, metadata: {'accountId': ownedId});
    final deposit = _sourceTransaction('Selected account credit', 'transfer',
        amount: 20, metadata: {'accountId': ownedId});
    final unrelated = _sourceTransaction('Different account fee', 'fees',
        amount: -8, metadata: {'accountId': 'other-account'});
    await _pumpAt(
        tester,
        ProviderScope(overrides: [
          accountsProvider.overrideWith((ref) async => const [
                AccountBalance(
                  id: ownedId,
                  name: 'Current',
                  iban: 'BE12345678901234',
                  balance: Money(currency: 'USD', minorUnits: 0),
                  available: Money(currency: 'USD', minorUnits: 0),
                ),
                AccountBalance(
                  id: emptyId,
                  name: 'Savings',
                  iban: 'BE12345678905678',
                  balance: Money(currency: 'USD', minorUnits: 0),
                  available: Money(currency: 'USD', minorUnits: 0),
                ),
              ]),
          activityAccountTransactionsProvider.overrideWith((ref, id) async {
            fail('UI account keys must never be sent as API wallet IDs');
          }),
        ], child: const TransactionsScreen()),
        const Size(393, 1000),
        light: false,
        ledger: [fee, deposit, unrelated]);
    final dropdown = find.byKey(const ValueKey('activity-account-dropdown'));
    expect(dropdown, findsOneWidget,
        reason: 'Accounts are available before choosing an operation Type.');
    await _selectActivityAccount(tester, accountLabel);
    await _selectActivityType(tester, 'Fee');
    await _selectActivityDirection(tester, 'Out');
    await _selectActivityAsset(tester, 'Fiat');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, selectedKey);
    expect(find.byKey(const ValueKey<String>('Selected account fee')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Different account fee')),
        findsNothing);
    expect(find.byKey(const ValueKey<String>('Selected account credit')),
        findsNothing);
    final export = tester.widget<TransactionPdfExportButton>(
        find.byType(TransactionPdfExportButton));
    expect(export.transactions, [fee]);
    expect(export.filters, contains('Account: $accountLabel'));
    expect(export.filters, contains('Type: Fee'));
    expect(export.filters.join(' '), isNot(contains(ownedId)));
    expect(export.filters.join(' '), isNot(contains('BE12345678901234')));

    await _selectActivityAsset(tester, 'Crypto');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, selectedKey);
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    await _selectActivityDirection(tester, 'In');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, selectedKey);
    await _selectActivityAsset(tester, 'Fiat');
    expect(find.byKey(const ValueKey<String>('Selected account credit')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Selected account fee')),
        findsNothing);

    // A real roster account remains selectable even with no transaction rows.
    await _selectActivityAccount(tester, 'Savings · USD · BE***5678');
    expect(tester.widget<DropdownButton<String>>(dropdown).value,
        'account:empty-bank-account:USD');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    await _selectActivityAccount(tester, 'All accounts');
    expect(tester.widget<DropdownButton<String>>(dropdown).value, '');
    expect(find.byKey(const ValueKey<String>('Selected account credit')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('asset controls remain usable when direction has no matches',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          _sourceTransaction('USDC withdrawal', 'crypto_withdrawal',
              currency: 'USDC', amount: 5),
          _sourceTransaction('USDT withdrawal', 'crypto_withdrawal',
              currency: 'USDT', amount: 10),
          _sourceTransaction('Bank transfer', 'transfer', amount: 50),
        ]);
    await _selectActivityAsset(tester, 'Crypto');
    expect(
        find.byKey(const ValueKey<String>('USDC withdrawal')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('USDT withdrawal')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('Bank transfer')), findsNothing);
    expect(find.byKey(const ValueKey('activity-scope-dropdown')), findsNothing);

    await _selectActivityDirection(tester, 'In');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-asset-filter')).hitTestable(),
        findsOneWidget);
    expect(find.byType(PopupMenuButton<Object>).hitTestable(), findsOneWidget);
    await _selectActivityAsset(tester, 'Fiat');
    expect(find.byKey(const ValueKey<String>('Bank transfer')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('USDC withdrawal')), findsNothing);

    await _selectActivityAsset(tester, 'Crypto');
    expect(find.text('Nothing matches those filters'), findsOneWidget);
    await _selectActivityDirection(tester, 'Out');
    expect(
        find.byKey(const ValueKey<String>('USDC withdrawal')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('USDT withdrawal')), findsOneWidget);
    await _selectActivityAsset(tester, 'All');
    expect(find.byKey(const ValueKey<String>('Bank transfer')), findsNothing,
        reason: 'Changing asset class keeps the selected Out direction.');
    expect(find.byKey(const ValueKey('activity-scope-dropdown')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'asset controls classify displayed currency independently of type',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          _sourceTransaction('USD conversion leg', 'crypto_to_quantum',
              amount: 30, metadata: {'sourceCurrency': 'USDT'}),
          _sourceTransaction('USD bank debit', 'transfer', amount: -5),
          _sourceTransaction('USDC deposit', 'crypto_deposit',
              currency: 'USDC', amount: 20),
          _sourceTransaction('USDC withdrawal', 'crypto_withdrawal',
              currency: 'USDC', amount: 5),
          _tx(
            id: 'displayed-crypto',
            title: 'Crypto-denominated card purchase',
            currency: 'USD',
            minorUnits: -200,
            transactionAmount: const Money(currency: 'USDC', minorUnits: -200),
            bookedAt: _today,
          ),
        ]);

    await _selectActivityAsset(tester, 'Crypto');
    expect(
        find.byKey(const ValueKey<String>('USD conversion leg')), findsNothing);
    expect(find.byKey(const ValueKey<String>('USD bank debit')), findsNothing);
    expect(find.byKey(const ValueKey<String>('USDC deposit')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('USDC withdrawal')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('displayed-crypto')), findsOneWidget);

    await _selectActivityDirection(tester, 'Out');
    expect(find.byKey(const ValueKey<String>('USDC deposit')), findsNothing);
    expect(
        find.byKey(const ValueKey<String>('USDC withdrawal')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('displayed-crypto')), findsOneWidget);

    await _selectActivityAsset(tester, 'Fiat');
    expect(
        find.byKey(const ValueKey<String>('USD bank debit')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('displayed-crypto')), findsNothing);
    expect(find.byKey(const ValueKey<String>('USDC withdrawal')), findsNothing);
    await _selectActivityDirection(tester, 'In');
    expect(find.byKey(const ValueKey<String>('USD conversion leg')),
        findsOneWidget,
        reason: 'A USD conversion leg is fiat because the row displays USD.');
    expect(find.byKey(const ValueKey<String>('USDC deposit')), findsNothing);

    await _selectActivityAsset(tester, 'All');
    expect(find.byKey(const ValueKey<String>('USD conversion leg')),
        findsOneWidget);
    expect(find.byKey(const ValueKey<String>('USDC deposit')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('USD bank debit')), findsNothing,
        reason: 'Changing asset class must preserve the In direction.');
    await _selectActivityDirection(tester, 'All');
    expect(
        find.byKey(const ValueKey<String>('USD bank debit')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('USDC withdrawal')), findsOneWidget);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final source in ['Card']) {
    testWidgets('$source scope combines with asset and direction controls',
        (tester) async {
      const accountId = '73bceaa1-a892-4f09-a363-3a88526f1668';
      final selected = [
        for (final entry in [
          (id: 'Scoped fiat debit', currency: 'USD', amount: -8.0),
          (id: 'Scoped crypto debit', currency: 'USDC', amount: -5.0),
          (id: 'Scoped crypto credit', currency: 'USDC', amount: 10.0),
        ])
          _sourceTransaction(entry.id, 'transfer',
              currency: entry.currency,
              amount: entry.amount,
              cardId: source == 'Card' ? '1' : '',
              metadata: {'accountId': accountId}),
      ];
      final other = _sourceTransaction('Different scope debit', 'transfer',
          currency: 'USDC',
          amount: -50,
          cardId: source == 'Card' ? '2' : '',
          metadata: {'accountId': '4cbf1482-6959-4767-b8d2-c2e659e7831d'});
      final cardRequests = <String>[];
      await _pumpAt(
          tester,
          ProviderScope(overrides: [
            cardsProvider.overrideWith((ref) async => [
                  PaymentCard.fromJson(
                      {'id': '1', 'label': 'Metal', 'last4': '1234'}),
                ]),
            accountsProvider.overrideWith((ref) async => [
                  const AccountBalance(
                    id: accountId,
                    name: 'Current',
                    iban: '',
                    balance: Money(currency: 'USD', minorUnits: 1000),
                    available: Money(currency: 'USD', minorUnits: 1000),
                  ),
                ]),
            activityCardTransactionsProvider.overrideWith((ref, id) async {
              cardRequests.add(id);
              return selected;
            }),
          ], child: const TransactionsScreen()),
          const Size(393, 1000),
          light: false,
          ledger: [...selected, other]);

      await _selectActivityType(tester, source);
      final scope = find.byKey(const ValueKey('activity-scope-dropdown'));
      expect(scope.hitTestable(), findsOneWidget);
      await _selectActivityScope(
          tester, source == 'Card' ? 'Metal · •••• 1234' : 'Current · USD');
      await _selectActivityAsset(tester, 'Crypto');
      await _selectActivityDirection(tester, 'Out');
      expect(find.byKey(const ValueKey<String>('Scoped crypto debit')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('Scoped fiat debit')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('Scoped crypto credit')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('Different scope debit')),
          findsNothing);

      await _selectActivityAsset(tester, 'Fiat');
      expect(find.byKey(const ValueKey<String>('Scoped fiat debit')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('Scoped crypto debit')),
          findsNothing);
      await _selectActivityAsset(tester, 'All');
      expect(find.byKey(const ValueKey<String>('Scoped fiat debit')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('Scoped crypto debit')),
          findsOneWidget);
      await _selectActivityDirection(tester, 'In');
      expect(find.byKey(const ValueKey<String>('Scoped crypto credit')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('Scoped fiat debit')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('Different scope debit')),
          findsNothing);
      expect(scope.hitTestable(), findsOneWidget);
      expect(cardRequests, source == 'Card' ? ['1'] : isEmpty,
          reason: 'Asset and direction filters keep the selected data scope.');
      expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('conversion rows stay searchable under direction filters',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1100),
        light: false,
        ledger: [
          _sourceTransaction('External USDT deposit', 'crypto_deposit',
              currency: 'USDT', amount: 100),
          _sourceTransaction('Convert USDT to USD', 'crypto_to_quantum',
              amount: 99.6,
              metadata: {'sourceCurrency': 'USDT', 'sourceAmount': 100}),
          _sourceTransaction('Conversion counterpart', 'crypto_exchange',
              amount: 99.6),
          _sourceTransaction(
              'Convert USD to USDC', 'quantum_to_crypto_exchange',
              amount: 99.6,
              metadata: {
                'targetCurrency': 'USDC',
                'cryptoAmountReceived': 99.5
              }),
          _sourceTransaction('External USDC withdrawal', 'crypto_withdrawal',
              currency: 'USDC', amount: 99.5),
          _sourceTransaction('External fee', 'fee', amount: .1),
        ]);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    // Conversions stay available in the ledger and in direction filters.
    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Convert USD to USDC');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('Convert USD to USDC')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversion-only activity remains visible with zero net flow',
      (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 852),
        light: true,
        ledger: [
          _sourceTransaction('Conversion only', 'crypto_exchange', amount: 100),
        ]);
    expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('activity-net-flow-value')))
            .data,
        '\$0.00');
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('Conversion only')), findsOneWidget);
    expect(find.byType(ExampleSweepBorder), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed withdrawals remain visible under Out', (tester) async {
    await _pumpAt(tester, const TransactionsScreen(), const Size(393, 1000),
        light: false,
        hoppa: true,
        ledger: [
          _sourceTransaction('Completed deposit', 'crypto_deposit',
              currency: 'USDC', amount: 20),
          LedgerTransaction.fromJson({
            'id': 'failed-withdrawal',
            'title': 'Failed withdrawal',
            'type': 'crypto_withdrawal',
            'currency': 'USDC',
            'amount': 100,
            'status': 'failed',
            'bookedAt': _today.toIso8601String(),
          }),
        ]);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    await tester.tap(find.text('Out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('failed-withdrawal')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('activity-net-flow')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
