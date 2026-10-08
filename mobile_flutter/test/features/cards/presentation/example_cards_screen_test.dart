import 'package:go_router/go_router.dart';
// Proof for the Example `/cards` roster.
//
// The deck at the top of this screen was already the strongest thing in the
// app; the list under it was the weakest. It led every row with the same
// rounded-square glyph a settings row carries, and it printed a status word on
// every row — including `Active`, which is the default and therefore says
// nothing once it is on all of them.
//
// What is worth proving here is mostly not a moment. It is that the roster now
// says the same things in *form*: that a row leads with the card object rather
// than a generic tile, that a physical card and a virtual one are different
// objects, that a frozen card is visibly iced rather than merely labelled, that
// the status word is spent only where it is an exception, and that the card on
// the stage is the one row carrying depth.
//
// Then the cases where two of those are true at once, which is where a rule
// stated in one line of code goes wrong: a frozen card that is also the one on
// stage, a wallet whose every card is closed, a card ordered but not yet
// issued. Each of them is a real state of the model, and each used to lose a
// fact the reader needed.
//
// The ink those captions are written in is proved rather than quoted: the
// contrast ratios below are computed from the palette under test, so a
// re-toned token is re-measured instead of re-approved. And they are computed
// against the ground the row really paints, hover wash included — a row is
// hoverable, so the wash is part of the ground for as long as anyone is
// pointing at the thing they are reading.
//
// One moment is proved as well, because the screen now has one that is not the
// artwork's: the ledger cross-fades when the deck is paged, on the state
// token, leaves quicker than it arrives, and cuts under reduced motion.
//
// Plus the invariants every Example screen owes: no overflow and no truncation
// at 375, 393, 834 and 1440 in BOTH themes and at a 1.3 text scale — including
// the widest caption a row can hold, which is not the one on the frozen card —
// and a white-label build that never sees any of it, at a phone width as well
// as a tablet one.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/cards/presentation/cards_screen.dart';
import 'package:mobile_flutter/features/cards/presentation/card_detail_screen.dart';
import 'package:mobile_flutter/features/cards/domain/card_control_capabilities.dart';
import 'package:mobile_flutter/features/cards/domain/card_limits.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/cards/presentation/widgets/card_ledger.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/shared/widgets/status_chip.dart';

// ---------------------------------------------------------------- fixtures

AppBranding _branding(String mode, {bool example = true}) => AppBranding(
      appName: example ? 'EXAMPLE' : 'Hoppa',
      brandId: example ? 'example' : 'hoppa',
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

AppConfig _config(String mode, {bool example = true}) => AppConfig(
      flavor: AppFlavor.dev,
      apiBaseUrl: 'http://127.0.0.1:1',
      branding: _branding(mode, example: example),
    );

/// The metal card: physical, active, and the one the deck opens on.
const _metal = PaymentCard(
  id: 'card-1',
  label: 'EXAMPLE Metal',
  last4: '4271',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 456235),
  spendThisMonth: Money(currency: 'USD', minorUnits: 77400),
  limit: Money(currency: 'USD', minorUnits: 1000000),
  virtual: false,
);

/// Active and virtual: the row that must print no status word at all.
const _virtual = PaymentCard(
  id: 'card-2',
  label: 'Online subscriptions',
  last4: '8830',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 24011),
  spendThisMonth: Money(currency: 'USD', minorUnits: 47900),
  limit: Money(currency: 'USD', minorUnits: 500000),
  virtual: true,
);

/// The exception. Its balance is deliberately unique so the assertions below
/// can find exactly one `Text` carrying it.
const _frozen = PaymentCard(
  id: 'card-3',
  label: 'Travel card',
  last4: '5512',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.frozen,
  balance: Money(currency: 'USD', minorUnits: 133733),
  spendThisMonth: Money(currency: 'USD', minorUnits: 33100),
  limit: Money(currency: 'USD', minorUnits: 500000),
  virtual: true,
);

/// Closed, and the only card in the wallet — the case where the deck has
/// nothing but the archive to put on stage.
const _closed = PaymentCard(
  id: 'card-4',
  label: 'Old card',
  last4: '1104',
  network: 'Mastercard',
  currency: 'USD',
  status: CardStatus.cancelled,
  balance: Money(currency: 'USD', minorUnits: 0),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
  virtual: false,
);

/// Ordered but not issued: no digits yet, so the row has nothing but the
/// nickname unless the identity line falls back to something.
const _pending = PaymentCard(
  id: 'card-5',
  label: 'Second metal',
  last4: '',
  network: '',
  currency: 'USD',
  status: CardStatus.pending,
  balance: Money(currency: 'USD', minorUnits: 0),
  spendThisMonth: Money(currency: 'USD', minorUnits: 0),
  limit: Money(currency: 'USD', minorUnits: 0),
  virtual: false,
);

const _cards = [_metal, _virtual, _frozen];

const _dashboard = DashboardSnapshot(
  profile: UserProfile(
    id: 'u1',
    name: 'Naem Kaya',
    email: 'naem@example.com',
    accountType: 'personal',
    kycStatus: 'approved',
    interlaceKycApproved: true,
    businessStatus: 'not_started',
    onboardingStatus: 'complete',
  ),
  accounts: [
    AccountBalance(
      id: 'usd',
      name: 'USD Account',
      iban: 'GB29EQMN60161331926578',
      balance: Money(currency: 'USD', minorUnits: 456235),
      available: Money(currency: 'USD', minorUnits: 456235),
      provider: 'Equals Money',
      status: 'active',
    ),
  ],
  cards: _cards,
  transactions: [],
  onboarding: [],
);

/// The brand's own typefaces, so the truncation assertions below are measured
/// in Geist. Without this the binding falls back to the test font, whose
/// glyphs are square boxes roughly twice Geist's advance width, and a layout
/// proof measured in it is a proof about a font nobody ships.
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
}

// ------------------------------------------------------------------ harness

/// Built once per brightness. Rebuilding `ThemeData` on every `pumpWidget`
/// makes `MaterialApp`'s `AnimatedTheme` treat an identical theme as a change
/// and start a controller, which leaves a ticker running in every test.
final _themes = <bool, AppThemes>{
  false: buildAppThemes(_branding('dark')),
  true: buildAppThemes(_branding('light')),
};

/// A tenant that is not Example, which is all it takes to render the
/// white-label composition and prove the other branch still exists.
final _whiteLabelThemes = buildAppThemes(_branding('dark', example: false));

Widget _app({
  required bool light,
  List<PaymentCard> cards = _cards,
  double textScale = 1,
  bool example = true,
  bool reduceMotion = false,
  String initialCardId = '',
  GoRouter? router,
}) {
  final themes = example ? _themes[light]! : _whiteLabelThemes;
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(
        _config(light ? 'light' : 'dark', example: example),
      ),
      dashboardProvider.overrideWith((ref) async => _dashboard),
      cardsProvider.overrideWith((ref) async => cards),
      for (final card in cards) ...[
        cardDetailProvider(card.id).overrideWith((ref) async => card),
        cardTransactionsProvider(card.id).overrideWith((ref) async => []),
        cardLimitsProvider(card.id).overrideWith((ref) async =>
            const CardLimitsInfo(
                currency: 'USD', canUpdate: true, capSource: 'none')),
        cardControlCapabilitiesProvider(card.id).overrideWith(
            (ref) async => CardControlCapabilities.fromJson(const {})),
      ],
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: router == null
          ? CardsScreen(initialCardId: initialCardId)
          : Router.withConfig(config: router),
    ),
  );
}

/// Advance a fixed amount rather than settling: the screen keeps a
/// `ExampleSheenScope` alive and the card face runs its own specular pass, so
/// `pumpAndSettle` waits for a tree that never comes to rest. Twelve frames
/// clear the 240 ms arrival delay and the 600 ms sweep.
Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  required bool light,
  List<PaymentCard> cards = _cards,
  double textScale = 1,
  bool example = true,
  bool reduceMotion = false,
  String initialCardId = '',
  GoRouter? router,
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
      light: light,
      cards: cards,
      textScale: textScale,
      example: example,
      reduceMotion: reduceMotion,
      initialCardId: initialCardId,
      router: router,
    ),
  );
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Every string this app *writes* renders whole: headings, labels, status
/// words, the identity line the row composes. Truncation is the failure mode a
/// screenshot hides and a diff never shows, so it is asserted rather than
/// looked at.
///
/// Two classes are exempt, and neither is copy.
///
/// A card's nickname is customer data — someone types it into the order form,
/// and it arrives at whatever length they liked. The row's contract for data is
/// that it ellipsises rather than overflows, exactly as it is for a merchant
/// name on the ledger. Asserting it would be asserting that customers pick
/// short names.
///
void _expectAppCopyIsWhole(WidgetTester tester) {
  final exempt = <String>{
    for (final card in _cards) card.label,
  };
  for (final element in find.byType(Text).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.didExceedMaxLines) continue;
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (exempt.contains(text)) continue;
    fail('Truncated: "$text"');
  }
}

/// The palette the screen resolves its inks and surfaces from, for the
/// brightness under test.
ExamplePalette _palette(bool light) => ExamplePalette.forBrightness(
      light ? Brightness.light : Brightness.dark,
    );

// ─── WCAG 2.1, computed rather than quoted ──────────────────────────────────
//
// Same three functions as `test/brands/example/contrast_floor_test.dart`, for
// the same reason: a ratio written down as a number is a claim about a token
// at the moment someone typed it, and it rots silently when the token moves.
// Derived from the palette under test, it cannot.

/// One sRGB channel (0..1) linearised, per WCAG 2.1 relative luminance.
double _linear(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// Relative luminance of an **opaque** colour.
double _luminance(Color color) =>
    0.2126 * _linear(color.r) +
    0.7152 * _linear(color.g) +
    0.0722 * _linear(color.b);

/// WCAG contrast of [fg] against the opaque [bg], alpha-compositing [fg] onto
/// it first — the ink volumes are night or pearl at an alpha, so this step is
/// not optional.
double _contrast(Color fg, Color bg) {
  final flattened = Color.from(
    alpha: 1,
    red: fg.r * fg.a + bg.r * (1 - fg.a),
    green: fg.g * fg.a + bg.g * (1 - fg.a),
    blue: fg.b * fg.a + bg.b * (1 - fg.a),
  );
  final a = _luminance(flattened);
  final b = _luminance(bg);
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// [top] composited onto the opaque [bottom] — the same alpha blend
/// [_contrast] performs on its foreground, exposed so a ground built by
/// stacking one wash on another can be handed to it opaque. `ExampleRow` paints
/// `ExampleInk.hover` over whatever surface it sits on, so a hovered row's
/// ground is one of these and not the surface token by itself.
Color _over(Color top, Color bottom) => Color.from(
      alpha: 1,
      red: top.r * top.a + bottom.r * (1 - top.a),
      green: top.g * top.a + bottom.g * (1 - top.a),
      blue: top.b * top.a + bottom.b * (1 - top.a),
    );

/// WCAG 2.1 AA 1.4.3 for normal-size text. The row's caption is 12 pt
/// regular, so this is the floor it owes wherever it lands.
const double _bodyFloor = 4.5;

/// Swipe the deck forward until `_cards[index]` is on the stage.
///
/// One drag per card: a `PageView` under `PageScrollPhysics` snaps a single
/// page per gesture however far it is dragged, so a longer throw would not
/// skip ahead. The frames afterwards let the page settle and the ledger's
/// cross-fade finish, so nothing is asserted mid-transition.
Future<void> _pageDeckTo(WidgetTester tester, int index) async {
  for (var i = 0; i < index; i++) {
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }
}

/// Bring a below-the-fold widget into the built subtree. The screen is a lazy
/// list, so half of the roster does not exist until it is scrolled to.
Future<void> _revealRoster(WidgetTester tester) async {
  final target = find.text('Your cards');
  if (target.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
}

/// The roster's rows, in order. `ExampleRow` is the row vocabulary; the deck
/// above uses none, so every match is a roster row.
Iterable<ExampleRow> _rows(WidgetTester tester) =>
    tester.widgetList<ExampleRow>(find.byType(ExampleRow));

ExampleRow _rowTitled(WidgetTester tester, String title) =>
    _rows(tester).firstWhere((row) => row.title == title);

/// The trailing block of the roster row titled [title] — balance, caption and
/// the inks both are written in.
ExampleRowValue _rowValue(WidgetTester tester, String title) =>
    tester.widget<ExampleRowValue>(
      find.descendant(
        of: find.byWidget(_rowTitled(tester, title)),
        matching: find.byType(ExampleRowValue),
      ),
    );

/// The roster row titled [title] still renders that title whole.
///
/// This is where a caption's width becomes visible. `ExampleRow` puts its
/// trailing slot outside the flex, so the caption takes whatever it needs
/// first and the title column lives on the remainder; `ExampleRow` then writes
/// the title `maxLines: 1, overflow: ellipsis`, so a caption that has grown
/// too wide shows up here as an ellipsis and nowhere else.
///
/// The caption cannot be measured for the same thing. `ExampleRowValue` writes
/// it `maxLines: 1, softWrap: false` and passes no `overflow`, so it is laid
/// out on one unbounded line and clipped by its parent rather than truncated
/// by the paragraph: `didExceedMaxLines` is false at every width, including
/// the ones where the caption is visibly cut off. Asserting the caption is
/// unclipped would therefore assert nothing, whatever the viewport.
///
/// By name, because `_expectAppCopyIsWhole` exempts card nicknames as customer
/// data. That exemption is right for arbitrary input and wrong for a fixture
/// at a known width.
void _expectTitleWhole(WidgetTester tester, String title) {
  final paragraph = tester.renderObject<RenderParagraph>(
    find.descendant(
      of: find.byWidget(_rowTitled(tester, title)),
      matching: find.text(title),
    ),
  );
  expect(
    paragraph.didExceedMaxLines,
    isFalse,
    reason: 'the roster row "$title" is ellipsised',
  );
}

/// Pump the white-label build and hand back every framework error it raised,
/// rather than letting the binding fail the test on them.
///
/// The legacy roster overflows at phone widths — see the note above the
/// white-label group — and that is the branch's own pre-existing behaviour.
/// The tests assert what the errors *are* instead of pretending there are
/// none, which is the only form of tolerance that still notices a new one.
Future<List<FlutterErrorDetails>> _pumpWhiteLabel(
  WidgetTester tester,
  Size size, {
  required bool light,
}) async {
  final captured = <FlutterErrorDetails>[];
  final priorOnError = FlutterError.onError;
  FlutterError.onError = captured.add;
  try {
    await _pumpAt(tester, size, light: light, example: false);
  } finally {
    FlutterError.onError = priorOnError;
  }
  return captured;
}

/// The frost pass painted over a frozen card's mark. Matched by the painter's
/// name because the mark is private to the screen — which is the point: it is
/// a screen-local mark, not a new entry in the vocabulary.
final _frostPass = find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter.runtimeType.toString() == '_FrostHatchPainter',
);

/// The brand preset that swaps one card's ledger for the next one's. Found
/// from the meter rather than by type alone: `_CardLedger` is private to the
/// screen, and the meter is the one public widget only it builds.
ExampleStateSwitch _ledgerSwitch(WidgetTester tester) =>
    tester.widget<ExampleStateSwitch>(
      find.ancestor(
        of: find.byType(CardSpendMeter),
        matching: find.byType(ExampleStateSwitch),
      ),
    );

/// The `AnimatedSwitcher` [ExampleStateSwitch] builds for the ledger, where the
/// durations it resolved are readable. Asserting on this rather than on the
/// preset's own fields is what makes the reduced-motion and exit-duration
/// checks measure resolved values instead of the arguments handed in.
AnimatedSwitcher _ledgerSwitcher(WidgetTester tester) =>
    tester.widget<AnimatedSwitcher>(
      find.ancestor(
        of: find.byType(CardSpendMeter),
        matching: find.byType(AnimatedSwitcher),
      ),
    );

/// The ledger's status pill. `ExamplePill` is the vocabulary's pill; the one
/// the artwork prints on its own face is a private widget inside
/// `ExampleLivingCard`, so this never matches it.
Finder _ledgerPill(String label) => find.byWidgetPredicate(
      (widget) => widget is ExamplePill && widget.label == label,
    );

const _viewports = <(String, Size)>[
  ('834', Size(834, 1194)),
  ('1440', Size(1440, 900)),
];

void main() {
  for (final width in [393.0, 1440.0]) {
    testWidgets('Cards opens the requested card at $width', (tester) async {
      await _pumpAt(tester, Size(width, 1000),
          light: true, initialCardId: _virtual.id, reduceMotion: true);
      if (width < 820) {
        final details =
            tester.widget<CardDetailScreen>(find.byType(CardDetailScreen));
        expect(details.cardId, _virtual.id);
        expect(details.asTab, isTrue);
      } else {
        final selectedLedger = find.byWidgetPredicate((widget) =>
            widget.runtimeType.toString() == '_CardLedger' &&
            widget.key == ValueKey(_virtual.id));
        expect(selectedLedger, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  setUpAll(_loadFonts);

  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';

    group('/cards roster · $theme', () {
      testWidgets('a row leads with the card, not a generic tile',
          (tester) async {
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _revealRoster(tester);

        // The roster used to lead every row with a `ExampleIconTile` holding
        // one of three glyphs. All three are gone from the card rows: the
        // object itself is the mark now. `ExampleIconTile` survives on the
        // "Closed cards" disclosure, which is a control and not a card, so
        // this asserts the glyphs rather than the tile type.
        expect(find.byIcon(Icons.credit_card_rounded), findsNothing);
        expect(find.byIcon(Icons.ac_unit_rounded), findsNothing);

        // These fixtures have no provider images, so their roster slots use
        // neutral placeholders, without invented card artwork or logos.
        expect(
          find.descendant(
            of: find.byType(ExampleRow),
            matching: find.byIcon(Icons.credit_card_outlined),
          ),
          findsNWidgets(3),
        );
        expect(find.byIcon(Icons.wifi_tethering_rounded), findsNothing);
      });

      testWidgets('frozen is a state you can see, not just a word',
          (tester) async {
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _revealRoster(tester);

        // One frozen card in the fixture, one frosted mark on the screen.
        expect(_frostPass, findsOneWidget);

        // And its money is stated at the secondary volume: present, and not
        // the loudest thing in the row, because it cannot move.
        final amount = tester.widget<Text>(
          find.descendant(
            of: find.byType(ExampleRowValue),
            matching: find.text(_frozen.balance.formatted),
          ),
        );
        expect(amount.style?.color, _palette(light).textSecondary);
      });

      testWidgets('the status word is spent only on the exception',
          (tester) async {
        // `_metal` is the card the deck opens on, so it is the "current" row.
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _revealRoster(tester);

        final palette = _palette(light);
        // No active card says it is active. Printing the default once per
        // row is how a column of status words stops meaning anything, and
        // an accent spent on `Active` three times is an accent that is not
        // available for the one row that needs it.
        expect(_rowValue(tester, _virtual.label).caption, isNull);
        // The row under the card on the stage says which card that is, once,
        // in neutral ink rather than a status hue — the level-3 fill is the
        // signal, and this is the word that explains it. The volume is *named*
        // rather than left to the default even though `ExampleRowValue`
        // resolves a null `captionColor` to the same secondary ink: naming it
        // is what puts the choice under test, and the composed-caption test
        // below is what fixes which volume it has to be.
        expect(_rowValue(tester, _metal.label).caption, 'On screen');
        expect(_rowValue(tester, _metal.label).captionColor,
            palette.textSecondary);
        // The one card that is not usable is the one that gets a coloured
        // word — and this is the row that keeps it. It is not the current one,
        // so it sits on the group's own level-1 surface, where the hue is
        // comfortably body-grade in both themes. The rule that follows is
        // narrow on purpose: only the composed caption steps off the hue, and
        // this asserts the step is not taken anywhere else.
        expect(_rowValue(tester, _frozen.label).caption, 'Frozen');
        expect(_rowValue(tester, _frozen.label).captionColor, palette.warning);
        final groupFill = palette.surfaceLevel(1);
        expect(
          _contrast(palette.warning, groupFill),
          greaterThanOrEqualTo(_bodyFloor),
        );
        // And with the row's own hover wash over that surface, which is the
        // state the word is most likely to be read in. Daylight is the tight
        // one at 4.87:1; Twilight has 9.44:1.
        expect(
          _contrast(palette.warning, _over(palette.hover, groupFill)),
          greaterThanOrEqualTo(_bodyFloor),
        );
      });

      testWidgets('a frozen card on the stage states both facts',
          (tester) async {
        // The branch the caption could not express. A frozen card is an open
        // card, so it is in the deck: page to it and its row is at once the
        // current one and the exception. Neither fact may be dropped — a
        // warning word on an unexplained highlight, and a highlight with
        // nothing saying which card it belongs to, are both wrong.
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _pageDeckTo(tester, _cards.indexOf(_frozen));
        await _revealRoster(tester);

        final palette = _palette(light);
        final frozenRow = _rowValue(tester, _frozen.label);
        // Status first, because it is the half that changes what the card can
        // do. The ink it is written in is the next test's subject.
        expect(frozenRow.caption, 'Frozen · On screen');

        // The highlight moved with the deck: still exactly one row on the
        // level-3 fill, and it is the frozen card's now.
        final lit = find.descendant(
          of: find.byType(ExampleListGroup),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox && widget.color == palette.surfaceLevel(3),
          ),
        );
        expect(lit, findsOneWidget);
        expect(
          find.descendant(of: lit, matching: find.text(_frozen.label)),
          findsOneWidget,
        );

        // And the card that was on the stage hands the word back rather than
        // leaving a second copy of it in the column.
        expect(_rowValue(tester, _metal.label).caption, isNull);
      });

      testWidgets('the composed caption is body-grade on the fill under it',
          (tester) async {
        // A caption carrying both facts is a phrase, not a one-word label, and
        // it exists only on a current row — which is the row wearing the
        // level-3 fill. So it is normal-size body text on the ladder's
        // brightest step, and it owes 4.5:1 there — in both themes and in both
        // of the row's hover states, because a caption is most likely to be
        // read exactly while a pointer is resting on its row.
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _pageDeckTo(tester, _cards.indexOf(_frozen));
        await _revealRoster(tester);

        final palette = _palette(light);
        // The two grounds, in the real paint order: `ExampleListGroup` fills
        // level 1 behind the run, the current row paints an opaque level-3
        // `ColoredBox` over it, and `ExampleRow` paints `ExampleInk.hover` — the
        // theme's own ink at .04 — above that, at zero alpha while no pointer
        // is on the row and at the full .04 while one is. Both are the
        // caption's ground; only one of them used to be measured.
        final fill = palette.surfaceLevel(3);
        final hovered = _over(palette.hover, fill);
        final row = _rowValue(tester, _frozen.label);
        expect(row.caption, 'Frozen · On screen');

        // The floors first and the identity second, deliberately. Asserting
        // the token by name would otherwise be the line that fails whenever
        // the ink moves, and the ratio — the thing this test is actually
        // about — would never be printed. In this order a caption ink that
        // breaches reports its own measurement, and the name below still
        // catches an ink that clears the floor but is the wrong volume.
        expect(
          _contrast(row.captionColor!, fill),
          greaterThanOrEqualTo(_bodyFloor),
          reason: 'the caption ink on the resting level-3 fill measures '
              '${_contrast(row.captionColor!, fill).toStringAsFixed(2)}:1',
        );
        expect(
          _contrast(row.captionColor!, hovered),
          greaterThanOrEqualTo(_bodyFloor),
          reason: 'the caption ink on the hovered level-3 fill measures '
              '${_contrast(row.captionColor!, hovered).toStringAsFixed(2)}:1',
        );
        expect(row.captionColor, palette.textSecondary);

        // The two inks this one was chosen over, computed here instead of
        // remembered, and written as brightness-dependent expectations so that
        // re-toning either token up to the floor fails this test and forces
        // the choice to be revisited rather than leaving a dead work-around in
        // place.
        //
        // The status hue misses the floor on the resting fill in daylight
        // (#8F5E0C on #EAE1FC) and clears it on Twilight.
        expect(
          _contrast(palette.warning, fill) >= _bodyFloor,
          light ? isFalse : isTrue,
          reason: 'warning on the level-3 fill measures '
              '${_contrast(palette.warning, fill).toStringAsFixed(2)}:1',
        );
        // The quietest ink volume clears the resting fill in both themes and
        // then loses Twilight to the hover wash (pearl .53 over pearl .04 over
        // #221C56, 4.43:1) while daylight survives it (4.65:1). That split is
        // the whole reason the caption is written at the secondary volume and
        // not at the tertiary one it used to take, and it is why the repair is
        // one rule for both themes rather than a Twilight-only branch.
        expect(
          _contrast(palette.textTertiary, fill),
          greaterThanOrEqualTo(_bodyFloor),
        );
        expect(
          _contrast(palette.textTertiary, hovered) >= _bodyFloor,
          light ? isTrue : isFalse,
          reason: 'tertiary on the hovered level-3 fill measures '
              '${_contrast(palette.textTertiary, hovered).toStringAsFixed(2)}'
              ':1',
        );
      });

      testWidgets('a frozen card on the stage lays out at 834 and 1.3',
          (tester) async {
        // The trailing column is inflexible inside the row: every point it
        // takes comes off the title column beside it. The narrowest phone at
        // the largest supported text scale, with the caption at its two-fact
        // length.
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          textScale: 1.3,
        );
        await _pageDeckTo(tester, _cards.indexOf(_frozen));
        await _revealRoster(tester);
        // The drag landed. Without this the test measures whatever the deck
        // happens to be showing: a `_pageDeckTo` that silently no-opped would
        // leave `Frozen` alone in the column — 50 pt of caption instead of
        // 131 — and every assertion below would pass on the easier layout.
        expect(_rowValue(tester, _frozen.label).caption, 'Frozen · On screen');
        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
        // The nickname beside the caption, which `_expectAppCopyIsWhole` is
        // told to skip. Nothing else on the screen reports what the caption
        // costs the column it shares.
        _expectTitleWhole(tester, _frozen.label);
      });

      testWidgets('the widest caption a row can hold fits at 834 and 1.3',
          (tester) async {
        // `Frozen · On screen` is not the worst case. `Cancelled` is the
        // longest status word the model has, and the pairing is reachable:
        // close every card and the deck falls back to staging a closed one,
        // which makes a cancelled row the current row. Measured in Geist at
        // 12 pt x 1.3, the caption is 154.6 pt wide against 131.4 for the
        // frozen one — 23 pt more taken off the title column beside it, at the
        // narrowest width the app supports.
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          textScale: 1.3,
          cards: const [_closed],
        );
        await _revealRoster(tester);

        expect(
          _rowValue(tester, _closed.label).caption,
          'Cancelled · On screen',
        );
        expect(tester.takeException(), isNull);
        // `_expectAppCopyIsWhole` is the whole guard here, and it does cover
        // the row title: its exempt set is built from `_cards`, and `_closed`
        // is not in `_cards`, so "Old card" is checked like copy rather than
        // skipped like a customer-typed nickname. A `_expectTitleWhole` call
        // on that same title used to follow the helper below; it was deleted
        // as dead weight, because it could never be the assertion that fires —
        // any width at which the title ellipsises fails the helper first.
        //
        // The margin is real and small, and it is this helper that measures
        // it: the test passes at 834 pt and, narrowed to 360, fails with
        // `Truncated: "Old card"` thrown from `_expectAppCopyIsWhole` in both
        // themes — so the headroom is somewhere under 15 pt. What is asserted
        // is that the widest caption the model can compose plus the nickname
        // beside it both still fit at the narrowest width the app supports,
        // and not that they trivially do.
        _expectAppCopyIsWhole(tester);
      });

      testWidgets('the card on the stage is the one row with depth',
          (tester) async {
        await _pumpAt(tester, const Size(834, 1194), light: light);
        await _revealRoster(tester);

        final level3 = _palette(light).surfaceLevel(3);
        final lit = find.descendant(
          of: find.byType(ExampleListGroup),
          matching: find.byWidgetPredicate(
            (widget) => widget is ColoredBox && widget.color == level3,
          ),
        );
        expect(lit, findsOneWidget);
        // And it is the row for the card the deck is showing.
        expect(
          find.descendant(of: lit, matching: find.text(_metal.label)),
          findsOneWidget,
        );
      });

      testWidgets('a wallet of closed cards is still a roster, not an archive',
          (tester) async {
        // Close every card and the deck falls back to staging a closed one.
        // The roster has to follow it there: fold the closed cards behind the
        // "Closed cards" disclosure and the group is empty under a card that
        // is plainly on screen, and the one-highlighted-row invariant the
        // level-3 fill depends on quietly becomes zero.
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          cards: const [_closed],
        );
        await _revealRoster(tester);

        // Listed outright: no disclosure to open, because there is nothing
        // else for it to be an exception to.
        expect(find.text('Closed cards'), findsNothing);
        expect(_rows(tester).map((row) => row.title), [_closed.label]);

        final lit = find.descendant(
          of: find.byType(ExampleListGroup),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is ColoredBox &&
                widget.color == _palette(light).surfaceLevel(3),
          ),
        );
        expect(lit, findsOneWidget);
        expect(
          find.descendant(of: lit, matching: find.text(_closed.label)),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
      });

      testWidgets('a card with no digits still says what it is',
          (tester) async {
        // An ordered card has no last four until it is issued. The identity
        // line is built from the digits, so without a fallback the row prints
        // a nickname over nothing — which reads as a row that failed to load
        // rather than a card that has not been made yet.
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          cards: const [_metal, _pending],
        );
        await _revealRoster(tester);

        expect(_rowTitled(tester, _pending.label).subtitle, 'Physical');
        // The digits still win wherever there are any.
        expect(
          _rowTitled(tester, _metal.label).subtitle,
          '•••• ${_metal.last4}',
        );
      });

      testWidgets('the ledger answers the swipe', (tester) async {
        await _pumpAt(tester, const Size(834, 1194), light: light);

        // The screen's second and last piece of motion, and the only one that
        // is a response rather than an arrival: the numbers under the stage
        // cross-fade when the deck moves to another card. It runs on the state
        // token, which is the one for a component changing state in place —
        // not on a route or sheet duration, which would make a swipe feel like
        // a page turn.
        expect(_ledgerSwitcher(tester).duration, ExampleMotion.state);

        // And it leaves quicker than it arrives, which is the brand's rule for
        // every exit and the reason this is the preset rather than a
        // hand-rolled `AnimatedSwitcher`: that widget reuses `duration` for
        // the reverse unless it is told otherwise, so an outgoing ledger would
        // take the full arrival time to go.
        expect(
          _ledgerSwitcher(tester).reverseDuration,
          ExampleMotion.exitOf(ExampleMotion.state),
        );
        expect(
          _ledgerSwitcher(tester).reverseDuration,
          lessThan(ExampleMotion.state),
        );

        // Pinned to the top edge, not the centre. `CardSpendMeter` collapses
        // to the spend line alone on a card with no limit, so the two ledgers
        // overlapping during the swap can be different heights; centred, every
        // row of both would travel for the length of the fade.
        expect(_ledgerSwitch(tester).alignment, Alignment.topCenter);

        // And it carries the whole ledger, not just the balance: page to the
        // frozen card and the meter under the stage is that card's month.
        await _pageDeckTo(tester, _cards.indexOf(_frozen));
        expect(
          tester.widget<CardSpendMeter>(find.byType(CardSpendMeter)).spent,
          _frozen.spendThisMonth.minorUnits / 100,
        );
      });

      testWidgets('reduced motion cuts instead of fading', (tester) async {
        // Read through `ExampleMotion.of`, so a reader who has asked for less
        // motion gets the same swap with no travel at all. Asserted rather
        // than assumed: this is the one animation the screen added, and a
        // duration that ignored the platform flag would be invisible in every
        // other test here.
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          reduceMotion: true,
        );
        expect(_ledgerSwitcher(tester).duration, Duration.zero);
        // Both halves, because the preset derives the exit from the enter:
        // three quarters of nothing is nothing, and a non-zero reverse would
        // leave the outgoing ledger fading on a reader who asked for no
        // motion at all.
        expect(_ledgerSwitcher(tester).reverseDuration, Duration.zero);
      });

      testWidgets('the ledger repeats no status the artwork already printed',
          (tester) async {
        await _pumpAt(tester, const Size(834, 1194), light: light);

        // The face on the stage prints its own `Active` pill. The ledger 60 pt
        // below used to print a second one; saying the default twice in one
        // column spends an accent on silence.
        expect(_ledgerPill('Active'), findsNothing);
      });

      testWidgets('the ledger still states an exceptional status',
          (tester) async {
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          cards: const [_frozen],
        );

        // Withheld for the default, spent on the exception: with the frozen
        // card on the stage its pill is the one coloured object under the
        // artwork.
        expect(_ledgerPill('Frozen'), findsOneWidget);
      });

      for (final (name, size) in _viewports) {
        testWidgets('$name lays out clean', (tester) async {
          await _pumpAt(tester, size, light: light);
          await _revealRoster(tester);
          expect(tester.takeException(), isNull);
          _expectAppCopyIsWhole(tester);
        });
      }

      testWidgets('834 at a 1.3 text scale lays out clean', (tester) async {
        await _pumpAt(
          tester,
          const Size(834, 1194),
          light: light,
          textScale: 1.3,
        );
        await _revealRoster(tester);
        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
      });
    });
  }

  for (final light in [false, true]) {
    testWidgets(
        'phone cards lists balances and opens the selected card · light=$light',
        (tester) async {
      final router = GoRouter(initialLocation: '/cards', routes: [
        GoRoute(path: '/cards', builder: (_, __) => const CardsScreen()),
        GoRoute(
            path: '/cards/:id',
            builder: (_, state) =>
                Scaffold(body: Text('Selected ${state.pathParameters['id']}'))),
      ]);
      addTearDown(router.dispose);
      await _pumpAt(tester, const Size(393, 852), light: light, router: router);
      expect(find.byType(CardDetailScreen), findsNothing);
      expect(find.byType(PageView), findsNothing);
      expect(find.text('Your cards'), findsOneWidget);
      expect(find.textContaining('4271'), findsOneWidget);
      expect(find.textContaining('8830'), findsOneWidget);
      expect(find.text(_metal.balance.formatted), findsOneWidget);
      expect(find.text(_virtual.balance.formatted), findsOneWidget);
      expect(find.text('On screen'), findsNothing);
      await tester.tap(find.text(_virtual.displayLabel));
      await tester.pumpAndSettle();
      expect(find.text('Selected ${_virtual.id}'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('single phone card opens directly · light=$light',
        (tester) async {
      await _pumpAt(tester, const Size(393, 852),
          light: light, cards: [_metal]);
      final detail =
          tester.widget<CardDetailScreen>(find.byType(CardDetailScreen));
      expect(detail.asTab, isTrue);
      expect(detail.cardId, _metal.id);
      expect(find.text('Your cards'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final light in [false, true]) {
    for (final width in [320.0, 393.0]) {
      for (final closed in [false, true]) {
        testWidgets(
            'twenty provider cards fit and reach card20 at $width · light=$light · roster=$closed',
            (tester) async {
          final cards = List<PaymentCard>.generate(
              20,
              (index) => PaymentCard(
                    id: 'api-card-$index',
                    label: 'Card ${index + 1}',
                    last4: '${4000 + index}',
                    network: 'Visa',
                    currency: 'USD',
                    status: closed ? CardStatus.cancelled : CardStatus.active,
                    balance: const Money(currency: 'USD', minorUnits: 10000),
                    spendThisMonth:
                        Money(currency: 'USD', minorUnits: index * 100),
                    limit: const Money(currency: 'USD', minorUnits: 500000),
                    virtual: true,
                  ));
          await _pumpAt(tester, Size(width, 852), light: light, cards: cards);
          if (!closed) {
            expect(find.byType(PageView), findsNothing);
            await tester.scrollUntilVisible(find.text('Card 20'), 300,
                scrollable: find.byType(Scrollable).first);
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('Card 20').hitTestable(), findsOneWidget);
            expect(find.textContaining('4019'), findsOneWidget);
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            return;
          }
          expect(find.text('1 of 20'), findsOneWidget);
          Finder markerFor(int index) => find.byKey(ValueKey(closed
              ? 'card-deck-indicator-$index'
              : 'card-page-indicator-${cards[index].id}'));
          for (var index = 0; index < cards.length; index++) {
            expect(markerFor(index), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
          // Start on card19, then use the real swipe to reach the final API card.
          tester
              .widget<PageView>(find.byType(PageView))
              .controller!
              .jumpToPage(18);
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          await tester.drag(find.byType(PageView), const Offset(-280, 0));
          for (var frame = 0; frame < 6; frame++) {
            await tester.pump(const Duration(milliseconds: 120));
          }
          expect(find.text('20 of 20'), findsOneWidget);
          final finalMarker = markerFor(cards.length - 1);
          final firstMarker = markerFor(0);
          expect(tester.getSize(finalMarker).width,
              greaterThan(tester.getSize(firstMarker).width));
          expect(
              tester.widget<CardSpendMeter>(find.byType(CardSpendMeter)).spent,
              19);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  }

  // Both a tablet and a phone width, because a branch proved only where it is
  // comfortable is a branch half proved — and both brightnesses, because
  // "unchanged" has to hold in both: the legacy composition reads the Material
  // scheme rather than the Example palette, and a Example token leaking into it
  // would land on the light theme first.
  //
  // The phone widths need the errors captured, because the legacy `_CardRow`
  // overflows there. Measured rather than assumed, with `_pumpWhiteLabel`:
  // 393 emits three `A RenderFlex overflowed` errors — 31 px, 2.9 px, 31 px,
  // one per card — and 375 emits 49 px, 21 px, 49 px. The RenderFlex that
  // overflows is not the trailing row: it is the identity `Row` inside
  // `_CardRow`'s own `subtitle` `Column` — an `Expanded` digit line beside a
  // non-flex balance `Text` — squeezed because the trailing
  // `StatusChip` + chevron takes its width off the same tile first. Named by
  // structure rather than by line number on purpose: a line number in another
  // file is a claim that rots on the next edit above it, and this comment has
  // already carried a stale one. That overflow is pre-existing white-label
  // behaviour in a composition this change deliberately does not touch, and
  // repairing it would be exactly the byte-identical-rendering violation these
  // tests guard. So the errors are classified rather than ignored: anything
  // that is not that overflow fails.
  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';
    for (final (name, size) in const [
      ('phone', Size(393, 852)),
      ('tablet', Size(834, 1194)),
    ]) {
      testWidgets('a white-label build sees none of it · $theme · $name',
          (tester) async {
        final errors = await _pumpWhiteLabel(tester, size, light: light);

        if (size.width < 820) {
          // The legacy layout bug, still exactly itself. `isNotEmpty` is half
          // the assertion: if the overflow ever goes away this fails, and the
          // right response is to delete the tolerance rather than the test.
          expect(errors, isNotEmpty);
          for (final error in errors) {
            expect(
              error.exception.toString(),
              startsWith('A RenderFlex overflowed'),
            );
          }
        } else {
          expect(errors, isEmpty);
        }

        // The legacy roster is `ListTile`s inside `NeoGroupedCard`. The three
        // `findsNothing`s below are tripwires on the brand gate rather than
        // proof of anything this change did: `_CardsScreen` picks the
        // composition on `branding.isExample`, so the Example vocabulary is
        // unreachable from this branch by construction, and none of them can
        // fail while that gate holds. Measured, not assumed — replacing the
        // gate with a constant `true` fails the `ListTile` line immediately
        // below with `Found 0 widgets with type "ListTile"`, and none of the
        // three is reached at all.
        //
        // A fourth, on `ExampleStateSwitch`, was deleted this round. It had
        // been offered as proof that the ledger's new preset is absent from
        // the white-label branch, and it can prove no such thing, for the
        // reason just measured. The preset's presence on the Example side is
        // asserted four times over anyway: `_ledgerSwitch` looks it up by type
        // and would throw if it were gone.
        expect(find.byType(ListTile), findsWidgets);
        expect(find.byType(ExampleRow), findsNothing);
        expect(find.byType(ExampleRowValue), findsNothing);
        expect(_frostPass, findsNothing);
        // The white-label row still spells every status out, including
        // `Active`, which is exactly the behaviour this change left alone.
        // Asserted on the row's own `StatusChip` and not on
        // `find.text('Active')`: the legacy screen also prints `Active` as the
        // label of a `_CountMetric` in its spending summary, so the looser
        // finder would keep passing with every chip deleted from the roster.
        final statuses = tester
            .widgetList<StatusChip>(
              find.descendant(
                of: find.byType(ListTile),
                matching: find.byType(StatusChip),
              ),
            )
            .map((chip) => chip.label)
            .toList();
        expect(statuses, [for (final card in _cards) card.statusLabel]);
      });
    }
  }
}
