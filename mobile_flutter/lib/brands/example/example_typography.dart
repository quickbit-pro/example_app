import 'package:flutter/material.dart';

import '../../shared/theme/app_typography.dart';
import '../../core/branding/app_design.dart';
import 'example_colors.dart';

/// Example's bundled typefaces (`assets/fonts`, SIL OFL 1.1, licence text in
/// `assets/fonts/OFL-Geist.txt`).
///
/// The strings are the `family` aliases from the `fonts:` block in
/// pubspec.yaml. The engine registers the static instances (Geist
/// 400/500/600/700, Geist Mono 400/500) under those aliases on every platform,
/// so `fontWeight` on a TextStyle selects the matching file; weights outside
/// the shipped set snap to the nearest one.
///
/// Geist carries the UI and every numeral (tabular figures through `tnum`).
/// Geist Mono is reserved for machine strings: addresses, hashes, card
/// numbers, codes. Other brands never reach these names: the theme resolves
/// them only when `AppBranding.isExample` is true and no `APP_FONT_FAMILY`
/// override is set (see `lib/core/theme/app_theme.dart`).
abstract final class ExampleFonts {
  static const sans = 'Geist';
  static const mono = 'GeistMono';
}

/// The shared [AppTypography] scale re-tuned for Geist metrics.
///
/// Sizes and hierarchy stay Rok's. What changes, and why:
///
/// * tracking: Geist is drawn with open spacing, so display and headline slots
///   tighten to -0.022 em / -0.015 em, titles at 16 px and above to -0.01 em,
///   body stays at 0 and the 12 / 11 px label slots relax to +0.01 / +0.02 em;
/// * leading: body slots gain +0.05 for light-on-dark reading (Twilight is
///   dark-first); every other slot keeps the shared value so layouts do not
///   drift against the generic build;
/// * weight: w800 slots map to w700 because Geist ships in 400/500/600/700
///   and Geist Bold at display sizes is already heavy at this tracking;
/// * numerals: every slot carries `tnum`, so any number anywhere in Example
///   lines up in columns without per-screen `fontFeatures` overrides.
abstract final class ExampleTypography {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Geist-tuned Material text theme for Example. [ink] is the on-surface
  /// colour for the current brightness — [ExampleColors.pearl] on Twilight,
  /// [ExampleColors.lightTextPrimary] on Pearl daylight (19.3:1 on white,
  /// 17.9:1 on paper).
  ///
  /// Metrics are identical in both themes: the same sizes, weights, tracking,
  /// leading and tabular figures. Only the ink changes, so a screen keeps its
  /// exact line breaks and rhythm when the theme flips.
  static TextTheme textTheme(Color ink) {
    final base = AppTypography.textTheme(ink, fontFamily: ExampleFonts.sans);
    return AppTypography.mapRoles(base, _tuneForGeist);
  }

  static TextStyle? _tuneForGeist(TextStyle? style, AppTextRole role) {
    if (style == null) return null;
    final size = style.fontSize ?? 14;
    final weight = style.fontWeight == FontWeight.w800
        ? FontWeight.w700
        : style.fontWeight;
    switch (role) {
      case AppTextRole.display:
        return style.copyWith(
          fontWeight: weight,
          letterSpacing: _em(size, -0.022),
          fontFeatures: _tabular,
        );
      case AppTextRole.headline:
        return style.copyWith(
          fontWeight: weight,
          letterSpacing: _em(size, -0.015),
          fontFeatures: _tabular,
        );
      case AppTextRole.title:
        return style.copyWith(
          letterSpacing: size >= 16 ? _em(size, -0.01) : 0,
          fontFeatures: _tabular,
        );
      case AppTextRole.body:
        return style.copyWith(
          height: (style.height ?? 1.4) + 0.05,
          letterSpacing: 0,
          fontFeatures: _tabular,
        );
      case AppTextRole.label:
        return style.copyWith(
          letterSpacing: size >= 14 ? 0 : _em(size, size >= 12 ? 0.01 : 0.02),
          fontFeatures: _tabular,
        );
    }
  }

  /// Tracking in logical pixels for [em] of [size], rounded to 1/100 px so
  /// the resulting styles compare equal across builds.
  static double _em(double size, double em) =>
      (size * em * 100).roundToDouble() / 100;
}

/// Sizes for [ExampleTextStyles.amount]. One numeral voice, five volumes.
enum ExampleAmountSize {
  /// 44 px: the single hero balance on the dashboard.
  hero(44, FontWeight.w700, 1.05, -0.022),

  /// 36 px: primary balance on wallet, card and account detail.
  large(36, FontWeight.w700, 1.06, -0.022),

  /// 26 px: section totals, sheet headers, confirmation amounts.
  medium(26, FontWeight.w700, 1.12, -0.018),

  /// 18 px: row amounts and inline totals.
  small(18, FontWeight.w600, 1.2, -0.01),

  /// 14 px: dense lists, captions, secondary currencies.
  inline(14, FontWeight.w600, 1.3, 0);

  const ExampleAmountSize(
    this.fontSize,
    this.fontWeight,
    this.height,
    this.trackingEm,
  );

  final double fontSize;
  final FontWeight fontWeight;
  final double height;
  final double trackingEm;
}

/// Ready-made Example text styles for the three jobs the Material scale does
/// not name: money, machine strings and uppercase eyebrow labels. Each reads
/// the active theme so a tenant `APP_FONT_FAMILY` override, light mode and
/// text scaling all keep working; override colour with `copyWith`.
abstract final class ExampleTextStyles {
  static const _tabular = [FontFeature.tabularFigures()];

  /// Currency and quantity numerals with tabular figures. Defaults to the
  /// on-surface colour; pass a `FinanceTheme` colour through `copyWith` for
  /// signed deltas.
  static TextStyle amount(
    BuildContext context, {
    ExampleAmountSize size = ExampleAmountSize.large,
  }) {
    final theme = Theme.of(context);
    return TextStyle(
      fontFamily: theme.textTheme.bodyLarge?.fontFamily ?? ExampleFonts.sans,
      color: theme.colorScheme.onSurface,
      fontSize: size.fontSize * context.brandDesign.typographyScale,
      fontWeight: size.fontWeight,
      height: size.height,
      letterSpacing: ExampleTypography._em(size.fontSize, size.trackingEm),
      fontFeatures: _tabular,
    );
  }

  /// Geist Mono for wallet addresses, transaction hashes, card numbers and
  /// one-time codes. Slashed zero (`ss09`) is on so 0 and O never read alike;
  /// group digits with spaces at the call site rather than tracking.
  static TextStyle mono(
    BuildContext context, {
    double size = 13,
    FontWeight weight = FontWeight.w400,
  }) {
    final theme = Theme.of(context);
    return TextStyle(
      fontFamily: context.brandDesign.monoFontFamily,
      color: theme.colorScheme.onSurface,
      fontSize: size * context.brandDesign.typographyScale,
      fontWeight: weight,
      height: 1.45,
      letterSpacing: 0,
      fontFeatures: const [FontFeature('ss09')],
    );
  }

  /// Uppercase eyebrow label (section kickers, field captions, card
  /// "VALID THRU"). 11 px semibold at +0.06 em; the caller supplies the
  /// uppercase string. Secondary ink in both themes: pearl .68 on Twilight
  /// (7.98:1 on the app background), night .72 on Pearl daylight (7.96:1 on
  /// white, 7.60:1 on paper).
  static TextStyle label(BuildContext context) {
    final theme = Theme.of(context);
    return TextStyle(
      fontFamily: theme.textTheme.labelSmall?.fontFamily ?? ExampleFonts.sans,
      color: ExamplePalette.of(context).textSecondary,
      fontSize: 11 * context.brandDesign.typographyScale,
      fontWeight: FontWeight.w600,
      height: 1.2,
      letterSpacing: ExampleTypography._em(11, 0.06),
      fontFeatures: _tabular,
    );
  }
}
