// The Example palette, measured.
//
// This walks every foreground/background pair `ExamplePalette` produces, in
// both brightnesses, and asserts the floor that pair actually owes:
//
//   * body and caption text          >= 4.5:1   (WCAG 2.1 AA, 1.4.3)
//   * large text (>=18pt / 14pt bold) >= 3:1
//   * borders, focus rings, chart strokes, icons, other non-text UI >= 3:1
//   * deliberately quiet marks (hairlines, sheen, skeletons, hover washes)
//     are held inside a *band*: present enough to see, quiet enough never to
//     be mistaken for content or for a control's boundary.
//
// Three rules keep it honest as the palette moves:
//
//   1. The ratios are computed here, from the sRGB transfer function and the
//      WCAG relative-luminance weights, after alpha-compositing. Nothing is
//      eyeballed and no expected ratio is written down — every expectation is
//      derived from the tokens under test, so the file still means something
//      after the next palette edit.
//   2. The pair table is built *from* `ExamplePalette`, not from a list of
//      hexes, so a re-toned token is re-measured rather than re-asserted.
//   3. Pairs that miss a floor because of a decision this file may not
//      reverse are listed in [_accepted], each recording the floor it does
//      hold. The walk asserts that recorded floor, so an exception can only
//      improve; and a separate guard fails if an exception starts passing,
//      so a fixed token forces its entry to be deleted instead of rotting.
//
// The last group renders the real app theme at 375 and 1440 in both
// brightnesses, so this proves the palette as `buildAppThemes` resolves it —
// not just as constants agree with each other.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';

// ─── WCAG 2.1, from the spec ────────────────────────────────────────────────

/// One sRGB channel (0..1) linearised, per WCAG 2.1 relative luminance.
double _linear(double channel) => channel <= 0.03928
    ? channel / 12.92
    : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();

/// Relative luminance of an **opaque** colour. Alpha is ignored on purpose:
/// a translucent colour has no luminance of its own, it has to be composited
/// against something first. [_flatten] is that step.
double _luminance(Color color) =>
    0.2126 * _linear(color.r) +
    0.7152 * _linear(color.g) +
    0.0722 * _linear(color.b);

/// [fg] alpha-composited over the opaque [bg]: source-over, straight alpha.
Color _flatten(Color fg, Color bg) {
  final a = fg.a;
  return Color.from(
    alpha: 1,
    red: fg.r * a + bg.r * (1 - a),
    green: fg.g * a + bg.g * (1 - a),
    blue: fg.b * a + bg.b * (1 - a),
  );
}

/// WCAG contrast ratio of [fg] against the opaque [bg], compositing first.
double _contrast(Color fg, Color bg) {
  final a = _luminance(_flatten(fg, bg));
  final b = _luminance(bg);
  final lighter = math.max(a, b);
  final darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).toUpperCase().padLeft(6, '0')}';

// ─── Floors ─────────────────────────────────────────────────────────────────

/// WCAG 2.1 AA, 1.4.3 — body and caption text.
const double _bodyFloor = 4.5;

/// WCAG 2.1 AA, 1.4.3 large text (>= 18pt, or >= 14pt bold) and 1.4.11
/// non-text contrast: borders that identify a control, focus rings, chart
/// strokes, icons.
const double _nonTextFloor = 3.0;

/// A quiet mark has to be visible at all. Below this a hairline is a rumour.
const double _quietFloor = 1.02;

/// ...and has to stay quiet. At or above [_nonTextFloor] a resting hairline
/// stops reading as a boundary and starts reading as a rule, and a skeleton
/// block starts reading as content.
const double _quietCeiling = _nonTextFloor;

// ─── Grounds, derived from the palette ──────────────────────────────────────

/// Every opaque ground a **sentence** can land on, translucent chrome already
/// composited. These are the grounds the three ink volumes must clear at
/// [_bodyFloor]; a caption is written in ink, and ink goes anywhere.
Map<String, Color> _textGrounds(ExamplePalette p) {
  final atmosphere = p.isDark
      // On night the atmosphere's indigo core sits ~1.16 screen-heights above
      // the top edge (`ExampleAtmosphere` auth/home presets), so the brightest
      // value that ever reaches a pixel is the named mid stop.
      ? <String, Color>{'atmosphere mid': ExampleColors.glowMid}
      // On paper the ceiling is on-canvas and the tokens state it outright.
      : <String, Color>{
          'atmosphere mid': ExampleColors.lightGlowMid,
          'atmosphere iris peak':
              _flatten(ExampleColors.lightGlowIris, ExampleColors.lightPaper),
          'atmosphere lavender peak':
              _flatten(ExampleColors.lightGlowLavender, ExampleColors.lightPaper),
        };
  return {
    'paper (level 0)': p.paper,
    'surface (level 1)': p.surface,
    'surfaceSubtle (level 2)': p.surfaceSubtle,
    'surfaceHigh (level 3)': p.surfaceHigh,
    'navigation': p.navigation,
    'navigationGlass over paper': _flatten(p.navigationGlass, p.paper),
    'rail over paper': _flatten(p.rail, p.paper),
    'glassTop over paper': _flatten(p.glassTop, p.paper),
    'glassBottom over paper': _flatten(p.glassBottom, p.paper),
    'glassTop over surfaceHigh': _flatten(p.glassTop, p.surfaceHigh),
    'skeleton block': p.skeletonBase,
    ...atmosphere,
  };
}

/// The subset of [_textGrounds] on which a **coloured accent** may carry a
/// sentence: level 0 and level 1 only.
///
/// This is the palette's own compositional rule, not a way round the floor.
/// Level 2 is the pressed tint and level 3 is the one selected element; both
/// take pills, chips, glyphs and one-word labels, and a status hue on them is
/// held to [_nonTextFloor] below. `glassBottom` is *defined* as level 2 at
/// .85, so the lower half of a frosted gradient inherits the level-2 rule
/// while its upper half is level 1.
Map<String, Color> _accentTextGrounds(ExamplePalette p) => {
      'paper (level 0)': p.paper,
      'surface (level 1)': p.surface,
      'navigation': p.navigation,
      'navigationGlass over paper': _flatten(p.navigationGlass, p.paper),
      'rail over paper': _flatten(p.rail, p.paper),
      'glassTop over paper': _flatten(p.glassTop, p.paper),
    };

/// The three ink volumes. All body-grade: tertiary carries row subtitles,
/// timestamps and limit captions, so 3:1 was never its floor.
Map<String, Color> _inks(ExamplePalette p) => {
      'ink': p.ink,
      'textSecondary': p.textSecondary,
      'textTertiary': p.textTertiary,
    };

/// The hues a sentence is ever written in. `fill` is deliberately absent: it
/// is a fill, and its floors are `onFill` on it (body) and itself as a focus
/// ring or indicator (non-text), both asserted separately.
Map<String, Color> _accentInks(ExamplePalette p) => {
      'accent': p.accent,
      'success': p.success,
      'danger': p.danger,
      'warning': p.warning,
      'teal': p.teal,
    };

/// Marks that are meant to be seen but never read: hairlines, the sheen band,
/// a skeleton block, the hover wash.
Map<String, Color> _quietMarks(ExamplePalette p) => {
      'borderSubtle': p.borderSubtle,
      'borderEmphasis': p.borderEmphasis,
      'sheenPeak': p.sheenPeak,
      'skeletonBase': p.skeletonBase,
      'skeletonHighlight': p.skeletonHighlight,
      'hover': p.hover,
    };

/// The grounds a quiet mark can be painted on.
Map<String, Color> _quietGrounds(ExamplePalette p) => {
      'surface': p.surface,
      'paper': p.paper,
      'fill': p.fill,
      'skeletonBase': p.skeletonBase,
    };

/// Every ground each quiet mark is actually painted on. The ceiling — never
/// loud enough to read — is measured against all of them. Pairs nothing
/// renders are left out on purpose: a skeleton block on a violet fill would
/// measure 4.08:1 and mean nothing, and a table that asserts noise stops being
/// read.
const _quietCeilingHosts = <String, List<String>>{
  'borderSubtle': ['surface', 'paper'],
  'borderEmphasis': ['surface', 'paper'],
  'sheenPeak': ['fill', 'surface'],
  'skeletonBase': ['surface', 'paper'],
  'skeletonHighlight': ['skeletonBase'],
  'hover': ['surface', 'paper'],
};

/// The ground each quiet mark has to be *visible* on. Narrower than the
/// ceiling table: a white sheen measured on a near-white surface is 1.02:1 and
/// should be — its hosts are the fill, the card artwork and a skeleton block,
/// and that is where it has to show up.
const _quietFloorHosts = <String, List<String>>{
  'borderSubtle': ['surface', 'paper'],
  'borderEmphasis': ['surface', 'paper'],
  'sheenPeak': ['fill'],
  'skeletonBase': ['surface', 'paper'],
  'skeletonHighlight': ['skeletonBase'],
  'hover': ['surface', 'paper'],
};

/// Every `Color` role on [ExamplePalette]. The coverage guard asserts each one
/// is measured by at least one pair above, so adding a role without measuring
/// it fails the suite. Add new roles here.
Map<String, Color> _allRoles(ExamplePalette p) => {
      'paper': p.paper,
      'surface': p.surface,
      'surfaceSubtle': p.surfaceSubtle,
      'surfaceHigh': p.surfaceHigh,
      'navigation': p.navigation,
      'navigationGlass': p.navigationGlass,
      'rail': p.rail,
      'glassTop': p.glassTop,
      'glassBottom': p.glassBottom,
      'ink': p.ink,
      'textSecondary': p.textSecondary,
      'textTertiary': p.textTertiary,
      'borderSubtle': p.borderSubtle,
      'borderEmphasis': p.borderEmphasis,
      'fill': p.fill,
      'onFill': p.onFill,
      'accent': p.accent,
      'success': p.success,
      'danger': p.danger,
      'warning': p.warning,
      'teal': p.teal,
      'shadowAmbient': p.shadowAmbient,
      'shadowLift': p.shadowLift,
      'skeletonBase': p.skeletonBase,
      'skeletonHighlight': p.skeletonHighlight,
      'sheenPeak': p.sheenPeak,
      'hover': p.hover,
      'hoverOff': p.hoverOff,
    };

/// The roles [ExamplePalette.accentFor] is contracted to accept: a hue used as
/// text or an icon, or something the method itself already returned. Surfaces,
/// borders and shadows are not in the domain — `accentFor` is documented to
/// take the brand token, and no call site hands it an edge.
Map<String, Color> _resolvableRoles(ExamplePalette p) => {
      'fill': p.fill,
      'accent': p.accent,
      'success': p.success,
      'danger': p.danger,
      'warning': p.warning,
      'teal': p.teal,
      'ink': p.ink,
      'textSecondary': p.textSecondary,
      'textTertiary': p.textTertiary,
      'onFill': p.onFill,
    };

/// The two `ColorScheme` slots this file measures that are not palette roles.
/// `buildAppThemes` fills them from the palette (dark `primary` *is*
/// [ExamplePalette.fill]) but `onPrimary` is Material's own white, so the pair
/// has to be named here to be accepted or fixed.
Map<String, Color> _materialRoles(ExamplePalette p) => {
      'primary': p.fill,
      'onPrimary': const Color(0xFFFFFFFF),
    };

/// The brand hues [ExamplePalette.accentFor] is documented to take.
const _brandHues = <String, Color>{
  'violet': ExampleColors.violet,
  'iris': ExampleColors.iris,
  'success': ExampleColors.success,
  'danger': ExampleColors.danger,
  'warning': ExampleColors.warning,
  'teal': ExampleColors.teal,
  'pearl': ExampleColors.pearl,
  'lavender': ExampleColors.lavender,
};

// ─── Accepted misses ────────────────────────────────────────────────────────

/// A pair that misses its proper floor because of a decision this file is not
/// allowed to reverse.
///
/// [holds] is the floor the pair *does* meet, recorded from a measurement, and
/// the walk asserts that instead of the proper floor — so the exception can
/// never quietly get worse. It is a ratchet, not a waiver: it does not record
/// the measured ratio, only the weaker floor, so tightening the token is
/// always legal and loosening it is always a failure.
@immutable
class _Accepted {
  const _Accepted({
    required this.brightness,
    required this.foreground,
    required this.ground,
    required this.holds,
    required this.why,
  });

  final Brightness brightness;
  final String foreground;
  final String ground;
  final double holds;
  final String why;

  String get key => '${brightness.name}/$foreground on $ground';
}

const _accepted = <_Accepted>[
  _Accepted(
    brightness: Brightness.dark,
    foreground: 'onFill',
    ground: 'fill',
    holds: _nonTextFloor,
    why: 'Pearl on Twilight violet is 3.37:1. Both halves are frozen: violet '
        'is the brand fill and one of the historical dark constants other '
        'tests prove identity against, and onFill is pearl in both themes by '
        'design so a primary control reads as one object across the two '
        'materials. The shipped primary button already refuses the flat slab '
        '(example_glass_button.dart builds an indigo body under a violet wash, '
        'where pearl measures 8.21:1); the remaining flat-violet host is the '
        'selected segment pill, and that is a call-site fix, not a token one.',
  ),
  _Accepted(
    brightness: Brightness.dark,
    foreground: 'onPrimary',
    ground: 'primary',
    holds: _nonTextFloor,
    why: 'The same flat Twilight violet, reached through Material: '
        'app_theme.dart sets onPrimary to Colors.white for every brand, and '
        'white on violet is 3.95:1. Example never renders that pair — its '
        'buttons are ExampleGlassButton and its pills carry pearl — but a bare '
        'FilledButton would, so the fix belongs in the ColorScheme and not '
        'here. Fixing it in this file would mean moving the brand fill.',
  ),
];

_Accepted? _acceptedFor(Brightness b, String fg, String ground) {
  for (final entry in _accepted) {
    if (entry.brightness == b &&
        entry.foreground == fg &&
        entry.ground == ground) {
      return entry;
    }
  }
  return null;
}

/// Records every pair the walk touched, so the coverage guard can prove no
/// role went unmeasured.
final Set<Color> _measured = <Color>{};

void _expectFloor(
  ExamplePalette p, {
  required String foreground,
  required Color fg,
  required String ground,
  required Color bg,
  required double floor,
}) {
  _measured
    ..add(fg)
    ..add(bg);
  final ratio = _contrast(fg, bg);
  final accepted = _acceptedFor(p.brightness, foreground, ground);
  final effective = accepted?.holds ?? floor;
  expect(
    ratio,
    greaterThanOrEqualTo(effective),
    reason: '${p.brightness.name}: $foreground ${_hex(fg)} on $ground '
        '${_hex(bg)} measures ${ratio.toStringAsFixed(2)}:1, under the '
        '${effective.toStringAsFixed(1)}:1 floor'
        '${accepted == null ? '' : ' recorded for this accepted miss'}.',
  );
}

// ─── The real app theme, for the widget group ───────────────────────────────

AppBranding _exampleBranding() => const AppBranding(
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
      legalEntity: '',
    );

void main() {
  group('the measurement itself', () {
    test('matches the two ratios WCAG fixes by definition', () {
      expect(_contrast(const Color(0xFFFFFFFF), const Color(0xFF000000)),
          closeTo(21, 0.001));
      expect(_contrast(const Color(0xFF808080), const Color(0xFF808080)),
          closeTo(1, 0.001));
    });

    test('agrees with Flutter on opaque luminance', () {
      for (final color in _allRoles(ExamplePalette.dark).values) {
        expect(_luminance(color), closeTo(color.computeLuminance(), 1e-9),
            reason: _hex(color));
      }
    });

    test('agrees with Flutter on alpha compositing', () {
      for (final alpha in const <double>[0, .14, .38, .53, .68, 1]) {
        final fg = ExampleColors.pearl.withValues(alpha: alpha);
        final mine = _flatten(fg, ExampleColors.appBackground);
        final theirs = Color.alphaBlend(fg, ExampleColors.appBackground);
        expect(_hex(mine), _hex(theirs), reason: 'alpha $alpha');
      }
    });

    test('a translucent ink is measured composited, not raw', () {
      // The trap this file exists to avoid: `computeLuminance` ignores alpha,
      // so measuring textTertiary raw reports pearl's luminance and a ratio
      // that no pixel ever had.
      final raw = ExampleColors.textTertiary.computeLuminance();
      final composited = _luminance(
        _flatten(ExampleColors.textTertiary, ExampleColors.appBackground),
      );
      expect(composited, lessThan(raw));
      expect(_contrast(ExampleColors.textTertiary, ExampleColors.appBackground),
          lessThan(_contrast(ExampleColors.pearl, ExampleColors.appBackground)));
    });
  });

  for (final palette in const [ExamplePalette.dark, ExamplePalette.light]) {
    final name = palette.isDark ? 'Twilight' : 'pearl daylight';

    group('$name: text floors', () {
      test('every ink volume is body-grade on every ground it can land on', () {
        _inks(palette).forEach((inkName, ink) {
          _textGrounds(palette).forEach((groundName, ground) {
            _expectFloor(
              palette,
              foreground: inkName,
              fg: ink,
              ground: groundName,
              bg: ground,
              floor: _bodyFloor,
            );
          });
        });
      });

      test('every accent hue carries a sentence on level 0 and level 1', () {
        _accentInks(palette).forEach((accentName, accentColor) {
          _accentTextGrounds(palette).forEach((groundName, ground) {
            _expectFloor(
              palette,
              foreground: accentName,
              fg: accentColor,
              ground: groundName,
              bg: ground,
              floor: _bodyFloor,
            );
          });
        });
      });

      test('the label on the primary fill is body-grade', () {
        _expectFloor(
          palette,
          foreground: 'onFill',
          fg: palette.onFill,
          ground: 'fill',
          bg: palette.fill,
          floor: _bodyFloor,
        );
      });
    });

    group('$name: non-text floors', () {
      test('accents stay legible as glyphs on level 2, level 3 and the sky',
          () {
        _accentInks(palette).forEach((accentName, accentColor) {
          _textGrounds(palette).forEach((groundName, ground) {
            _expectFloor(
              palette,
              foreground: accentName,
              fg: accentColor,
              ground: groundName,
              bg: ground,
              floor: _nonTextFloor,
            );
          });
        });
      });

      test('the fill reads as an indicator and a focus ring everywhere', () {
        _textGrounds(palette).forEach((groundName, ground) {
          _expectFloor(
            palette,
            foreground: 'fill',
            fg: palette.fill,
            ground: groundName,
            bg: ground,
            floor: _nonTextFloor,
          );
        });
      });

      test('a status pill glyph reads on its own wash', () {
        for (final entry in _brandHues.entries) {
          if (entry.key == 'pearl' || entry.key == 'lavender') continue;
          for (final ground in [palette.surface, palette.paper]) {
            final wash = _flatten(palette.tint(entry.value), ground);
            final glyph = palette.accentFor(entry.value);
            final ratio = _contrast(glyph, wash);
            _measured
              ..add(glyph)
              ..add(wash);
            expect(
              ratio,
              greaterThanOrEqualTo(_nonTextFloor),
              reason: '${palette.brightness.name}: ${entry.key} glyph '
                  '${_hex(glyph)} on its own tint ${_hex(wash)} measures '
                  '${ratio.toStringAsFixed(2)}:1',
            );
          }
        }
      });
    });

    group('$name: quiet marks stay inside their band', () {
      test('never loud enough to read, on any ground it is painted on', () {
        final grounds = _quietGrounds(palette);
        _quietMarks(palette).forEach((markName, mark) {
          for (final host in _quietCeilingHosts[markName]!) {
            final ground = grounds[host]!;
            final ratio = _contrast(mark, ground);
            _measured
              ..add(mark)
              ..add(ground);
            expect(
              ratio,
              lessThan(_quietCeiling),
              reason: '${palette.brightness.name}: $markName ${_hex(mark)} on '
                  '$host ${_hex(ground)} is ${ratio.toStringAsFixed(2)}:1 — '
                  'that is a rule or a border, not a quiet mark. If it is '
                  'meant to identify a control, move it to the non-text floor.',
            );
          }
        });
      });

      test('present enough to see, on the ground it is there to mark', () {
        final grounds = _quietGrounds(palette);
        _quietMarks(palette).forEach((markName, mark) {
          for (final host in _quietFloorHosts[markName]!) {
            final ground = grounds[host]!;
            final ratio = _contrast(mark, ground);
            _measured
              ..add(mark)
              ..add(ground);
            expect(
              ratio,
              greaterThanOrEqualTo(_quietFloor),
              reason: '${palette.brightness.name}: $markName ${_hex(mark)} on '
                  'its host $host ${_hex(ground)} is '
                  '${ratio.toStringAsFixed(3)}:1 — invisible',
            );
          }
        });
      });

      test('the hover wash is a whisper and never moves hue', () {
        final washed = _flatten(palette.hover, palette.surface);
        expect(_contrast(washed, palette.surface), lessThan(1.2));
        expect(palette.hoverOff.a, 0);
        expect(_hex(palette.hoverOff), _hex(palette.hover),
            reason: 'hoverOff must be hover at zero alpha, so an '
                'AnimatedContainer lerps within one hue');
      });
    });

    group('$name: accentFor', () {
      test('is idempotent for every hue the brand owns', () {
        for (final entry in _brandHues.entries) {
          final once = palette.accentFor(entry.value);
          final twice = palette.accentFor(once);
          expect(
            _hex(twice),
            _hex(once),
            reason: '${palette.brightness.name}: accentFor(${entry.key}) is '
                '${_hex(once)} but resolving that again gives ${_hex(twice)}. '
                'A caller that resolves twice — a wrapper, or a widget that '
                'stores its resolved accent — would deepen the hue a second '
                'time. Daylight success went #097A50 -> #0B483B this way.',
          );
        }
      });

      test('is idempotent for every role it is contracted to accept', () {
        _resolvableRoles(palette).forEach((roleName, role) {
          final once = palette.accentFor(role);
          expect(_hex(palette.accentFor(once)), _hex(once),
              reason: '${palette.brightness.name}: role $roleName');
        });
      });

      test('leaves an already-resolved hue exactly where it is', () {
        // The stronger statement: resolving a brand hue and handing the result
        // back must return the *same object*, not merely an equal-looking one.
        for (final entry in _brandHues.entries) {
          final once = palette.accentFor(entry.value);
          expect(palette.accentFor(once), once, reason: entry.key);
        }
      });

      test('is a no-op on every dark pixel', () {
        if (!palette.isDark) return;
        for (final entry in _brandHues.entries) {
          expect(palette.accentFor(entry.value), entry.value,
              reason: 'Twilight was drawn for night; resolving must not move '
                  'a single dark pixel (${entry.key})');
        }
      });

      test('resolves every brand hue to something body-grade on paper', () {
        for (final entry in _brandHues.entries) {
          final resolved = palette.accentFor(entry.value);
          final ratio = _contrast(resolved, palette.paper);
          expect(
            ratio,
            greaterThanOrEqualTo(_bodyFloor),
            reason: '${palette.brightness.name}: ${entry.key} resolves to '
                '${_hex(resolved)}, ${ratio.toStringAsFixed(2)}:1 on paper. '
                'accentFor exists precisely so a status hue can be handed to '
                'a TextStyle.',
          );
        }
      });
    });
  }

  group('the walk is complete', () {
    test('every palette role was measured in both brightnesses', () {
      // Runs after the groups above have populated `_measured`. Roles that are
      // pure alpha carriers (`hoverOff`) or that only ever appear as a shadow
      // are named here with the reason they carry no contrast obligation.
      const noContrastObligation = {
        'shadowAmbient': 'a shadow is cast behind an element, never read',
        'shadowLift': 'a shadow is cast behind an element, never read',
        'hoverOff': 'transparent by construction; it is hover at alpha 0',
        'navigationGlass': 'measured composited, as "navigationGlass over '
            'paper"',
        'rail': 'measured composited, as "rail over paper"',
        'glassTop': 'measured composited, over paper and over surfaceHigh',
        'glassBottom': 'measured composited, as "glassBottom over paper"',
      };
      for (final palette in const [ExamplePalette.dark, ExamplePalette.light]) {
        _allRoles(palette).forEach((roleName, role) {
          if (noContrastObligation.containsKey(roleName)) return;
          expect(
            _measured.contains(role),
            isTrue,
            reason: '${palette.brightness.name}: role $roleName '
                '${_hex(role)} is never measured against anything. Add it to '
                'a foreground or ground table above, or record why it carries '
                'no contrast obligation.',
          );
        });
      }
    });

    test('no accepted miss is still needed', () {
      for (final entry in _accepted) {
        final palette = ExamplePalette.forBrightness(entry.brightness);
        final known = {..._allRoles(palette), ..._materialRoles(palette)};
        final fg = known[entry.foreground];
        final bg = known[entry.ground];
        expect(fg, isNotNull, reason: 'unknown foreground ${entry.foreground}');
        expect(bg, isNotNull, reason: 'unknown ground ${entry.ground}');
        final ratio = _contrast(fg!, bg!);
        expect(
          ratio,
          lessThan(_bodyFloor),
          reason: '${entry.key} now measures ${ratio.toStringAsFixed(2)}:1 and '
              'clears the body floor. Delete its _accepted entry so the walk '
              'holds it to the real floor again.',
        );
      }
    });
  });

  group('the palette as the app resolves it', () {
    for (final size in const [Size(375, 812), Size(1440, 900)]) {
      for (final brightness in Brightness.values) {
        final width = size.width.toInt();
        testWidgets('$brightness at $width carries its own text',
            (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          final themes = buildAppThemes(_exampleBranding());
          late ThemeData theme;
          late ExamplePalette palette;
          await tester.pumpWidget(
            MaterialApp(
              theme: themes.light,
              darkTheme: themes.dark,
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              home: Builder(
                builder: (context) {
                  theme = Theme.of(context);
                  palette = ExamplePalette.of(context);
                  return const Scaffold(body: SizedBox.shrink());
                },
              ),
            ),
          );

          expect(theme.brightness, brightness);
          expect(palette.brightness, brightness);
          expect(theme.scaffoldBackgroundColor, palette.paper,
              reason: 'the scaffold is level 0');

          final scheme = theme.colorScheme;
          final scaffold = theme.scaffoldBackgroundColor;

          void floor(
            String what,
            Color? fg,
            Color bg,
            double min, {
            String? groundName,
          }) {
            expect(fg, isNotNull, reason: '$what is unset');
            final ratio = _contrast(fg!, bg);
            final accepted = groundName == null
                ? null
                : _acceptedFor(brightness, what, groundName);
            expect(
              ratio,
              greaterThanOrEqualTo(accepted?.holds ?? min),
              reason: '$brightness @$width: $what ${_hex(fg)} on ${_hex(bg)} '
                  'measures ${ratio.toStringAsFixed(2)}:1',
            );
          }

          floor('bodyMedium', theme.textTheme.bodyMedium?.color, scaffold,
              _bodyFloor);
          floor('bodySmall', theme.textTheme.bodySmall?.color, scaffold,
              _bodyFloor);
          floor('labelSmall', theme.textTheme.labelSmall?.color, scaffold,
              _bodyFloor);
          floor('onSurface', scheme.onSurface, scheme.surface, _bodyFloor);
          floor('onSurfaceVariant', scheme.onSurfaceVariant, scheme.surface,
              _bodyFloor);
          floor('error', scheme.error, scaffold, _bodyFloor);
          expect(scheme.primary, palette.fill,
              reason: 'the ColorScheme primary is the palette fill, so the '
                  'accepted miss recorded against "primary" is this pair');
          floor('onPrimary', scheme.onPrimary, scheme.primary, _bodyFloor,
              groundName: 'primary');
          floor(
              'primary as focus ring', scheme.primary, scaffold, _nonTextFloor);

          // The navigation bar's unselected label and icon are tertiary ink on
          // the navigation ground — the pair that started this audit.
          final navLabel = theme.navigationBarTheme.labelTextStyle
              ?.resolve(<WidgetState>{})?.color;
          floor(
              'unselected nav label', navLabel, palette.navigation, _bodyFloor);
          final navIcon = theme.navigationBarTheme.iconTheme
              ?.resolve(<WidgetState>{})?.color;
          floor('unselected nav icon', navIcon, palette.navigation,
              _nonTextFloor);
        });
      }
    }
  });
}
