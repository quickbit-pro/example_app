// Rewards leads with its payoff.
//
// The screen used to open on four stacked panels of identical weight: a 36 px
// figure sharing a box with a 4 px progress bar, an invite code and a button,
// then a settings-style list of three referral counts, then a voucher field,
// then another list. Nothing led, and the number the whole programme exists to
// produce was set smaller than the balance on Home.
//
// These cases pin the three things that fixed it, because each one is easy to
// undo by accident: the figure is the hero volume, the tier rail is a filled
// object that arrives (and is final on frame one under reduced motion), and
// the referral counts carry proportional magnitude rather than being three
// right-aligned numerals. The two flows the brief protects — copying the
// invite link and redeeming a voucher — are pinned beside them, and the last
// case pins that a white-label tenant sees none of it.
//
// The last group is the price of that redesign: the magnitude bars, the
// rail's milestone notches and the rail's own fill edge each encode
// something no sentence on the screen repeats, so each is non-text UI and
// owes 1.4.11's 3:1. Each one shipped under it at least once, and an alpha
// is the easiest number in this file to nudge back down by eye. The rail's
// two marks are measured under the sheen band as well as bare: the band is
// not permanently on them — it crosses for the 1.2 to 1.6 s of a sweep, once
// per the scope's 7 s cadence — but its centre line is where the floor is
// tightest, so the peak is what these cases pin. The last case in that group
// is the one guard on the rail's shape rather than its colours: it pins that
// nothing is painted over the fill's tip.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/rewards/presentation/rewards_screen.dart';
import 'package:mobile_flutter/flavors.dart';

const _exampleBranding = AppBranding(
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

/// No `ExampleBrand` extension on the theme, so every Example-only widget on
/// this screen has to fall through to the pre-Example tree.
const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

const _tenantConfig = MobileTenantConfig(
  companyName: 'Example',
  brandName: 'Example',
  referralsEnabled: true,
  referralRegistrationMode: 'code',
  vouchersEnabled: true,
  existingAccountClaimEnabled: false,
  boomFiExchangeEnabled: false,
  walletOutflowsEnabled: false,
  equalsMoneyEnabled: true,
);

/// The demo programme, and the exact figures the design review looked at:
/// $1.00 available, 3 of 5 toward the next level, 8 invited / 3 qualified /
/// 2 in progress. 3 / 8 is 37.5 percent, which is the one rounding case worth
/// having in a fixture. The v2 summary shape: two visible levels so the
/// ladder is a journey, and voucher delivery so the voucher flows this file
/// protects are on the page.
const _snapshot = RewardsSnapshot(
  config: _tenantConfig,
  referralSummary: {
    'referralCode': 'EXAMPLE28',
    'referralPath': 'https://example.com/r/EXAMPLE28',
    'currentLevel': {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
    'nextLevel': {'code': 'ELITE', 'name': 'Elite', 'minimumMetricValue': 5},
    'levels': [
      {'code': 'PRO', 'name': 'Pro', 'minimumMetricValue': 0},
      {'code': 'ELITE', 'name': 'Elite', 'minimumMetricValue': 5},
    ],
    'progress': {'currentValue': 3, 'nextThreshold': 5},
    'referrals': {'invited': 8, 'qualified': 3, 'inProgress': 2, 'earning': 3},
    'rewards': {
      'pending': 0,
      'ready': 1,
      'crediting': 0,
      'paid': 0,
      'failed': 0,
      'currency': 'USD',
    },
    'offer': {
      'welcomeAmount': 3,
      'welcomeCurrency': 'USD',
      'qualificationCalculationType': 'FIXED',
      'qualificationRate': 1,
      'topupCalculationType': 'PERCENT_OF_TOPUP',
      'topupRate': 0.25,
      'earningWindowDays': 365,
    },
    'deliveryMode': 'AUTOMATIC_TRANSFER',
    'minimumCreditAmount': 0.01,
    'accumulatedTowardsCredit': 0,
  },
  voucherStatus: {'enabled': true},
);

Widget _host({
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  double textScale = 1,
  bool reducedMotion = false,
  RewardsSnapshot snapshot = _snapshot,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: [
      rewardsSnapshotProvider.overrideWith((ref) async => snapshot),
    ],
    child: MaterialApp(
      theme: theme,
      themeMode: ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 900),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: const RewardsScreen(),
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester, {
  required double width,
  Brightness brightness = Brightness.dark,
  AppBranding branding = _exampleBranding,
  double textScale = 1,
  bool reducedMotion = false,
  bool settle = true,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _host(
      width: width,
      brightness: brightness,
      branding: branding,
      textScale: textScale,
      reducedMotion: reducedMotion,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // One frame past the provider's future, so the data branch is built but
    // no arrival has been given a chance to run.
    await tester.pump();
    await tester.pump();
  }
}

/// Past the arm delay the arrival waits out, so the fill has started.
const Duration _pastArrival = Duration(milliseconds: 300);

/// The tier rail's painter. It is a private class in the screen, so the type
/// is matched by name — which is also the point: nothing else on the page is
/// allowed to be that painter.
Finder get _railPaint => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString() == '_TierRailPainter',
    );

CustomPainter _railPainter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_railPaint).painter!;

/// Every proportional bar on the page, in tree order.
List<double> _magnitudes(WidgetTester tester) => tester
    .widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox))
    .map((box) => box.widthFactor)
    .whereType<double>()
    .toList();

/// The rail painter's fill, 0..1. Dynamic because `_TierRailPainter` is
/// private to the screen; [_railPaint] is what pins that this is the right
/// object to be asking.
double _railProgress(CustomPainter painter) =>
    (painter as dynamic).progress as double;

/// The rail painter's three colours, read off the painter the screen actually
/// built rather than restated from tokens — a restated expectation only ever
/// proves that two copies of a number agree. Dynamic for the same reason as
/// [_railProgress].
({Color track, Color tick, Color fill}) _railColors(WidgetTester tester) {
  final dynamic painter = _railPainter(tester);
  return (
    track: painter.track as Color,
    tick: painter.tick as Color,
    fill: painter.fill as Color,
  );
}

/// The band the page's one sheen host actually paints, alpha included.
///
/// Read off the painter rather than restated, and for a sharper reason than
/// usual: `ExampleSheen` resolves the peak from the brightness, from the
/// intensity *and* from whether a scope is driving it — a live host peaks at
/// twice the static one — so a literal pinned here would keep passing after
/// any of those moved. The count is asserted because the floors below are
/// only the real floors if this is the band that lands on the rail.
Color _sheenPeak(WidgetTester tester) {
  final painters = tester
      .widgetList<CustomPaint>(
        find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint && widget.painter is ExampleSheenPainter,
        ),
      )
      .map((paint) => paint.painter! as ExampleSheenPainter)
      .toList();
  expect(painters, hasLength(1), reason: 'the page runs exactly one band');
  // And that it is the live band, not the resting one. A host with no
  // `ExampleSheenScope` above it falls back to a static highlight at half the
  // peak alpha, which would quietly halve every floor measured below without
  // failing anything. The screen mounts its own `ExampleAliveLayer`; this is
  // what says so.
  expect(
    painters.single.isStatic,
    isFalse,
    reason: 'the floors below are measured against the live peak',
  );
  return painters.single.peak;
}

/// Each funnel bar with the well it is drawn in, in tree order. The Twilight
/// well is a wash rather than a colour, so it is composited onto the level-1
/// surface the block sits on first: a wash has no contrast until it has
/// landed on something.
List<(Color, Color)> _funnelBars(WidgetTester tester, Brightness brightness) {
  final panel = ExampleSurface.forBrightness(brightness, 1);
  final stages = find.byType(FractionallySizedBox);
  return [
    for (var i = 0; i < tester.widgetList(stages).length; i++)
      (
        _boxColor(
          tester,
          find
              .descendant(of: stages.at(i), matching: find.byType(DecoratedBox))
              .first,
        ),
        Color.alphaBlend(
          _boxColor(
            tester,
            find
                .ancestor(of: stages.at(i), matching: find.byType(DecoratedBox))
                .first,
          ),
          panel,
        ),
      ),
  ];
}

Color _boxColor(WidgetTester tester, Finder finder) =>
    (tester.widget<DecoratedBox>(finder).decoration as BoxDecoration).color!;

/// Rasterises [painter] at [width] x [height] and returns the raw RGBA bytes.
///
/// The rail is the one thing on this screen whose defect is invisible to the
/// widget tree: a cap over the fill's tip is two columns of a `CustomPaint`,
/// not a widget, not a field, and not a colour the painter carries. Pixels
/// are the only place it exists.
Future<ByteData> _rasterise(
    CustomPainter painter, int width, int height) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), Size(width.toDouble(), height.toDouble()));
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  picture.dispose();
  return data!;
}

/// One pixel out of [_rasterise]'s bytes, as a [Color]. [stride] is the row
/// width the bytes were rasterised at.
Color _pixel(ByteData pixels, int stride, int x, int y) {
  final i = (y * stride + x) * 4;
  return Color.fromARGB(
    pixels.getUint8(i + 3),
    pixels.getUint8(i),
    pixels.getUint8(i + 1),
    pixels.getUint8(i + 2),
  );
}

/// Borders, focus rings, chart marks, icons — WCAG 2.1 AA 1.4.11. The palette
/// holds the same line in `test/brands/example/contrast_floor_test.dart`.
const double _nonTextFloor = 3;

/// Alpha-composites [color] over [ground] and returns the WCAG 2.1 contrast
/// ratio. Both arguments are painted colours, not tokens: the laws ask for
/// the ratio *after* compositing, which is the step an alpha-carrying token
/// makes easy to skip.
double _contrast(Color color, Color ground) {
  final composited = Color.alphaBlend(color, ground);
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);

  final a = luminance(composited);
  final b = luminance(ground);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  group('Example rewards hero', () {
    for (final width in const [375.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('states the reward at hero volume at $width in $brightness',
            (tester) async {
          await _pumpAt(tester, width: width, brightness: brightness);

          expect(tester.takeException(), isNull);
          // One amount on the page, and it is the 44 px volume Home gives its
          // balance. `always` because "1.00" without "USD" is a number, not
          // money the customer is about to claim.
          final amount = tester.widget<ExampleAmount>(find.byType(ExampleAmount));
          expect(amount.size, ExampleAmountSize.hero);
          expect(amount.code, ExampleAmountCode.always);
          expect(find.text('REWARDS AVAILABLE'), findsOneWidget);
          // The caption is derived from the funnel, never asserted: three
          // qualified referrals is what the money is made of.
          expect(
            find.text('Earned from 3 qualified referrals.'),
            findsOneWidget,
          );
          // Exactly one sweep on the screen, and it belongs to the hero.
          expect(find.byType(ExampleSweepBorder), findsOneWidget);
        });
      }
    }

    testWidgets('lays the figure beside the ladder on a desktop panel',
        (tester) async {
      await _pumpAt(tester, width: 1440);

      expect(tester.takeException(), isNull);
      // Side by side, not stacked: the figure's caption and the rail's
      // remainder line share a baseline band across the panel, and the rail
      // itself is far longer than the phone's because the panel is.
      final caption = tester.getRect(
        find.text('Earned from 3 qualified referrals.'),
      );
      final remainder = tester.getRect(find.text('2 more to go'));
      expect(remainder.left, greaterThan(caption.right));
      expect(tester.getSize(_railPaint).width, greaterThan(400));
    });

    testWidgets('stacks the same two halves on a phone', (tester) async {
      await _pumpAt(tester, width: 375);

      final caption = tester.getRect(
        find.text('Earned from 3 qualified referrals.'),
      );
      final remainder = tester.getRect(find.text('2 more to go'));
      expect(remainder.top, greaterThan(caption.bottom));
    });

    testWidgets('holds at a 1.3 text scale on a 375 phone', (tester) async {
      await _pumpAt(tester, width: 375, textScale: 1.3);

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleAmount), findsOneWidget);
      expect(find.text('3 of 5'), findsOneWidget);
    });
  });

  group('Example tier ladder', () {
    testWidgets('is a 10 px object with both distances stated', (tester) async {
      await _pumpAt(tester, width: 375);

      expect(_railPaint, findsOneWidget);
      // Ten, not the four the review called a hairline.
      expect(tester.getSize(_railPaint).height, 10);
      // Travelled, and left. The second one is the actionable half and the
      // old control never showed it.
      expect(find.text('3 of 5'), findsOneWidget);
      expect(find.text('2 more to go'), findsOneWidget);
    });

    testWidgets('fills on arrival', (tester) async {
      await _pumpAt(tester, width: 375, settle: false);
      final onArrival = _railPainter(tester);

      // Past the arm delay — nothing may run during the route transition, so
      // the fill is deliberately not moving in the frames before this.
      await tester.pump(_pastArrival);
      await tester.pumpAndSettle();

      // `shouldRepaint` is the painter's own statement that its progress
      // moved: the fill travelled out rather than being drawn in place.
      expect(onArrival.shouldRepaint(_railPainter(tester)), isTrue);
    });

    testWidgets('is final on the first frame under reduced motion',
        (tester) async {
      await _pumpAt(tester, width: 375, reducedMotion: true, settle: false);
      final first = _railPainter(tester);

      await tester.pump(_pastArrival);
      await tester.pumpAndSettle();

      // The value first, because stability alone does not carry this claim:
      // `shouldRepaint` is false for a rail that was correct on frame one and
      // equally false for one wedged at zero that never animates at all, and
      // the second of those is the failure this case exists to catch. 3 of 5
      // is the fixture, so .6 is the whole of "already correct".
      expect(_railProgress(first), 0.6);
      // And then that nothing changed between the first frame and the settled
      // tree, even past the point where the arrival would have fired: no
      // ticker ran.
      expect(first.shouldRepaint(_railPainter(tester)), isFalse);
    });
  });

  group('Example referral funnel', () {
    testWidgets('encodes the cohort in form as well as in numerals',
        (tester) async {
      await _pumpAt(tester, width: 375);

      expect(find.text('Referral funnel'), findsOneWidget);
      expect(find.text('Invited'), findsOneWidget);
      expect(find.text('Qualified'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      // 8, 3 and 2 drawn against the widest stage: the funnel narrows on the
      // page before anybody reads a digit.
      expect(_magnitudes(tester), const [1.0, 0.375, 0.25]);
      // Derived from the two figures above it, never a fourth number from
      // nowhere. 3 of 8 rounds to 38.
      expect(find.text('Converted'), findsOneWidget);
      expect(find.text('38%'), findsOneWidget);
    });

    testWidgets('the counts are no longer settings rows', (tester) async {
      await _pumpAt(tester, width: 375);

      // The old shape: a `ExampleListGroup` titled "Referral activity" holding
      // three `ExampleRow`s. A regression back to it would still render the
      // same three words, so the title is what pins the change.
      expect(find.text('Referral activity'), findsNothing);
    });
  });

  group('Example offer panel', () {
    /// The demo programme with the tenant's own explanation of the offer
    /// filled in on the admin side.
    final described = RewardsSnapshot(
      config: _tenantConfig,
      referralSummary: {
        ..._snapshot.referralSummary!,
        'programDescription':
            'Verified friends get \$3; you get \$1 and a share of their '
                'top-ups for a year.',
      },
      voucherStatus: _snapshot.voucherStatus,
    );

    testWidgets("carries the tenant's own explanation above the checklist",
        (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
        width: 375,
        brightness: Brightness.dark,
        reducedMotion: true,
        snapshot: described,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Still the Example tree: both rewards stated from the API's figures.
      expect(find.text('INVITE & EARN'), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_offer_friend'))).data,
        r'Friend gets $3',
      );
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_offer_you'))).data,
        r'You get $1 + 0.25% of eligible credited top-ups',
      );
      // The tenant's words sit above the checklist, and the checklist
      // stays: the legal conditions are never hidden behind marketing copy.
      final description = find.byKey(const Key('referral_offer_description'));
      expect(
        tester.widget<Text>(description).data,
        'Verified friends get \$3; you get \$1 and a share of their '
        'top-ups for a year.',
      );
      final steps = find.byKey(const Key('referral_offer_steps'));
      expect(tester.getTopLeft(description).dy,
          lessThan(tester.getTopLeft(steps).dy));
      expect(find.text('Verify their identity'), findsOneWidget);
      expect(find.text('Get a paid card'), findsOneWidget);
      expect(find.text('Make a first eligible external top-up'), findsOneWidget);
    });

    testWidgets(
        'explains the offer from the figures when the tenant wrote '
        'nothing', (tester) async {
      await _pumpAt(tester, width: 375, reducedMotion: true);

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('referral_offer_description')), findsNothing);
      expect(find.text('How your friend qualifies'), findsOneWidget);
      expect(find.text('Verify their identity'), findsOneWidget);
      expect(find.text('Get a paid card'), findsOneWidget);
      expect(find.text('Make a first eligible external top-up'), findsOneWidget);
      // The window, the eligibility rule and the delivery, all from the
      // offer's own figures — the fixture is a voucher programme.
      expect(
        tester.widget<Text>(find.byKey(const Key('referral_offer_window'))).data,
        '0.25% for 365 days',
      );
      expect(find.textContaining('Only external credited top-ups qualify.'),
          findsOneWidget);
      expect(find.byKey(const Key('referral_voucher_delivery')), findsOneWidget);
    });
  });

  group('Example rewards flows', () {
    testWidgets('Invite friends remains available when summary has no code',
        (tester) async {
      tester.view.physicalSize = const Size(375, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_host(
          width: 375,
          brightness: Brightness.dark,
          reducedMotion: true,
          snapshot: const RewardsSnapshot(
              config: _tenantConfig, referralSummary: {})));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
          find.widgetWithText(ExampleGlassButton, 'Invite friends'));
      await tester
          .tap(find.widgetWithText(ExampleGlassButton, 'Invite friends'));
      await tester.pumpAndSettle();
      expect(find.text('Send referral invitation'), findsOneWidget);
      expect(find.text('Send invitation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the invite link is still one tap from the clipboard',
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
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );

      await _pumpAt(tester, width: 375);
      expect(find.text('INVITE CODE', skipOffstage: false), findsOneWidget);

      // The offer card runs past a 900 px viewport; scroll the action into
      // reach and give the layout a frame before tapping.
      final copyLink = find.byKey(const Key('referral_copy_link'));
      await tester.ensureVisible(copyLink);
      await tester.pump();
      await tester.tap(copyLink);
      await tester.pump();

      expect(copied, ['https://example.com/r/EXAMPLE28']);
      expect(find.text('Invite link copied'), findsOneWidget);
    });

    for (final failSharing in [false, true]) {
      testWidgets(
          'Invite friends shares or copies when unavailable: $failSharing',
          (tester) async {
        final shared = <String>[];
        final copied = <String>[];
        const channel = MethodChannel('dev.fluttercommunity.plus/share');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
            (call) async {
          shared.add((call.arguments as Map)['text'] as String);
          if (failSharing) throw PlatformException(code: 'unavailable');
          return 'chosen-app';
        });
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        });
        addTearDown(() {
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });
        await _pumpAt(tester, width: 375);
        // The offer card runs past a 900 px viewport, which puts Share below
        // it. `ensureVisible` jumps the scroll position but lays nothing out
        // until the next frame, so a tap straight after it lands on stale
        // geometry — one frame first.
        final share = find.widgetWithText(ExampleGlassButton, 'Share');
        await tester.ensureVisible(share);
        await tester.pump();
        await tester.tap(share);
        await tester.pump();
        await tester.pump();
        expect(shared.single, contains('https://example.com/r/EXAMPLE28'));
        expect(shared.single, contains('EXAMPLE28'));
        if (failSharing) {
          expect(copied.single, shared.single);
          expect(find.text('Invitation copied. Paste it to invite a friend.'),
              findsOneWidget);
        } else {
          expect(copied, isEmpty);
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the voucher field is still redeemable', (tester) async {
      await _pumpAt(tester, width: 375);

      // The page runs exactly one sheen band and it is the tier rail's —
      // two controls of the same material, one shimmering and one still,
      // was the inconsistency this replaced. Counted before anything
      // scrolls: the list builds lazily, and once the hero leaves the
      // viewport its rail is not in the tree to count.
      expect(find.byType(ExampleSheen), findsOneWidget);
      expect(find.widgetWithText(ExampleGlassButton, 'Invite by email'),
          findsOneWidget);

      // The voucher panel sits under the offer, the invite card, the
      // friends and the ledger now, so it is reached by scrolling to it
      // rather than by a fixed drag.
      await tester.scrollUntilVisible(
        find.text('VOUCHER CODE'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      expect(find.text('VOUCHER CODE'), findsOneWidget);
      final redeem = tester.widget<ExampleGlassButton>(
        find.widgetWithText(ExampleGlassButton, 'Redeem'),
      );
      expect(redeem.onPressed, isNotNull);
      // Matte, like the invite CTA.
      expect(redeem.sheen, isFalse);
    });
  });

  group('Example rewards marks', () {
    for (final brightness in Brightness.values) {
      testWidgets('the funnel bars are all legible in $brightness',
          (tester) async {
        await _pumpAt(tester, width: 375, brightness: brightness);

        final bars = _funnelBars(tester, brightness);
        expect(bars, hasLength(3));
        final ratios = [for (final (bar, well) in bars) _contrast(bar, well)];

        for (final ratio in ratios) {
          expect(ratio, greaterThanOrEqualTo(_nonTextFloor));
        }
        // Invited carries both halves of the rule at once, which is why it
        // was the one that broke: it is the widest bar, so it must not be the
        // loudest — and it is the scale the other two are drawn against, so
        // it is the one bar that may not disappear either. Quietest of the
        // three, and still over the floor.
        expect(ratios.first, lessThan(ratios[1]));
        expect(ratios.first, lessThan(ratios[2]));
      });

      testWidgets('the rail marks read against what they sit on in $brightness',
          (tester) async {
        await _pumpAt(tester, width: 375, brightness: brightness);
        final rail = _railColors(tester);
        final band = _sheenPeak(tester);
        Color lit(Color ground) => Color.alphaBlend(band, ground);

        // On paper the track is opaque; in Twilight it is a pearl wash over
        // the hero's glass, and what is behind that glass is an atmosphere
        // rather than a fixed colour — so the wash is measured over every
        // surface in the ladder and both marks have to clear the floor on
        // all of them, not on a convenient one.
        for (var level = 0; level <= 3; level++) {
          final track = Color.alphaBlend(
            rail.track,
            ExampleSurface.forBrightness(brightness, level),
          );
          final notch = Color.alphaBlend(rail.tick, track);
          // The notches state a count, and the track is what they are cut
          // into. Bare first, then under the band. The band compresses the
          // pair in both themes — pearl lifting a dark track, lightIris
          // darkening a pale one — so the lit pair is the harder of the two.
          // Both assertions carry weight, but they catch different things:
          // the alphas this replaced cleared bare (3.25:1 on paper, 3.11:1
          // at worst in Twilight) and failed lit (2.73:1 and 2.56:1), while
          // the alphas before those failed bare as well (1.97:1 and 2.19:1).
          expect(
            _contrast(notch, track),
            greaterThanOrEqualTo(_nonTextFloor),
            reason: 'milestone notch over surface level $level',
          );
          expect(
            _contrast(lit(notch), lit(track)),
            greaterThanOrEqualTo(_nonTextFloor),
            reason: 'milestone notch under the band, surface level $level',
          );
          // "You are here" is the fill's own edge against the track, with
          // no cap drawn over it — a mark at the tip would abut the fill on
          // one side and the track on the other, and under the band no flat
          // colour clears 3:1 against both (the screen carries that
          // arithmetic). So the edge carries the position and the edge is
          // what has to hold, lit like the notch. This is the floor the
          // capless rail rests on; that the cap is actually gone is pinned
          // by the case below, not by this pair.
          //
          // The daylight half of this is also the guard on the fill's theme
          // mapping. The two themes fail it in opposite ways: swapping the
          // accent token (iris to violet) only moves Twilight, to 2.91:1,
          // because the light value is mapped from it; dropping the mapping
          // and painting the raw dark iris on paper only moves daylight, to
          // 1.92:1.
          expect(
            _contrast(lit(rail.fill), lit(track)),
            greaterThanOrEqualTo(_nonTextFloor),
            reason: 'fill edge against the track, surface level $level',
          );
        }
      });

      testWidgets("paints nothing over the fill's tip in $brightness",
          (tester) async {
        await _pumpAt(tester, width: 375, brightness: brightness);
        // Past the arm delay: the fill is at zero until the arrival has run,
        // and a rail with no fill has no tip to paint over.
        await tester.pump(_pastArrival);
        await tester.pumpAndSettle();
        final painter = _railPainter(tester);
        final fill = _railColors(tester).fill;

        // The colour cases above are floors on the palette; this one is a
        // guard on the shape, and it is the only case that can tell the
        // capless rail from the one that shipped before it. Those two rails
        // build the same `track`, `tick` and `fill`, so nothing read off the
        // painter's fields discriminates them — only the pixels do.
        //
        // Run the screen's own painter onto a canvas of our own, at a size
        // that makes the arithmetic exact: 100 x 10 with the arrived fixture
        // leaves the fill running from x = 0 to x = 60 with a 5 px round
        // end, and the four milestone notches at 20, 40, 60 and 80 — three
        // of them under that fill. So the whole walked run is one unbroken
        // bar of `fill` and nothing else, which is the property. The cap
        // this rail used to draw was `Rect.fromLTWH(width - 2, 0, 2,
        // height)`: the last two columns of the bar, column 58 among them.
        //
        // Sampled along the centre row, and only over the columns that are
        // wholly inside the shape: column 0 clips the left round end and
        // column 59 the right one, so both carry the end's antialiasing and
        // neither is a flat colour in any version of this rail. The progress
        // is asserted rather than assumed, because it is what puts the tip
        // at 60.
        expect(_railProgress(painter), 0.6);
        //
        // `runAsync` because rasterising is real async: the fake clock a
        // widget test runs on never completes `Picture.toImage`.
        final pixels =
            await tester.runAsync(() => _rasterise(painter, 100, 10));
        final walked = [
          for (var x = 1; x <= 58; x++) _pixel(pixels!, 100, x, 5),
        ];
        expect(
          walked,
          everyElement(fill),
          reason: 'columns 1 to 58 of the walked rail are the fill and '
              'nothing else',
        );
      });
    }
  });

  testWidgets('a white-label tenant keeps the pre-Example rewards tree',
      (tester) async {
    await _pumpAt(tester, width: 375, branding: _tenantBranding);

    expect(tester.takeException(), isNull);
    expect(find.byType(ExampleSweepBorder), findsNothing);
    expect(find.byType(ExampleAmount), findsNothing);
    expect(_railPaint, findsNothing);
    expect(find.text('Referral funnel'), findsNothing);
    // Its own layout, untouched: the Material invite button and the four-up
    // metric grid it has always rendered.
    expect(find.text('Email invite'), findsOneWidget);
    expect(find.text('Invited'), findsOneWidget);
  });
}
