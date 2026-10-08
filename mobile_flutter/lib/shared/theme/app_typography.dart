import 'package:flutter/material.dart';

/// Role of a slot in the Material [TextTheme]. Lets a brand re-tune the shared
/// scale by intent (display, headline, ...) instead of slot by slot; see
/// [AppTypography.mapRoles].
enum AppTextRole { display, headline, title, body, label }

abstract final class AppTypography {
  /// Builds a neo-banking text theme. [fontFamily] is the tenant-provided
  /// family (or empty for Material default). Body and label text uses the
  /// system default; headlines and balance numbers are tight and bold.
  ///
  /// All numeric / balance styles use `FontFeature.tabularFigures()` so digit
  /// columns line up — critical for currency UIs.
  /// Desktop display tier, for a marketing hero at 1440 and up.
  ///
  /// Deliberately NOT a role in [textTheme]: that ramp is shared with every
  /// white-label brand, and raising `displayLarge` there would move their
  /// pixels. The ceiling of the shared ramp is 44 px, which left the Example
  /// auth hero set at 30 px in an 860 px column — below every competitor on
  /// the board, including the one the research singles out as the easiest to
  /// out-hierarchy. 64 px is the answer at desktop width only; mobile keeps
  /// 44 / 36 / 30 and nothing at 375 or 393 reflows.
  static TextStyle displayXl(TextTheme theme) =>
      (theme.displayLarge ?? const TextStyle()).copyWith(
        fontSize: 64,
        height: 1.02,
        letterSpacing: -1.8,
      );

  static TextTheme textTheme(Color textColor, {String? fontFamily}) {
    final family =
        (fontFamily == null || fontFamily.trim().isEmpty) ? null : fontFamily;
    const tabular = [FontFeature.tabularFigures()];

    return TextTheme(
      displayLarge: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 44,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.6,
        fontFeatures: tabular,
      ),
      displayMedium: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 36,
        fontWeight: FontWeight.w800,
        height: 1.06,
        letterSpacing: -0.5,
        fontFeatures: tabular,
      ),
      displaySmall: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 30,
        fontWeight: FontWeight.w800,
        height: 1.08,
        letterSpacing: -0.4,
      ),
      headlineMedium: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 26,
        fontWeight: FontWeight.w800,
        height: 1.16,
        letterSpacing: -0.3,
      ),
      headlineSmall: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 22,
        fontWeight: FontWeight.w800,
        height: 1.18,
        letterSpacing: -0.2,
      ),
      titleLarge: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        height: 1.22,
      ),
      titleMedium: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w700,
        height: 1.25,
      ),
      titleSmall: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.28,
      ),
      bodyLarge: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 16,
        fontWeight: FontWeight.w400,
        height: 1.45,
      ),
      bodyMedium: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.42,
      ),
      bodySmall: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
      ),
      labelLarge: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 14,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.2,
      ),
      labelSmall: TextStyle(
        color: textColor,
        fontFamily: family,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: 0.4,
      ),
    );
  }

  /// Returns a copy of [base] with [tune] applied to each of the fifteen
  /// Material slots, tagged by [AppTextRole]. [base] is not mutated and
  /// [textTheme] itself is unchanged, so a brand that bundles its own typeface
  /// can re-track or re-lead the scale for that font's metrics without
  /// redeclaring it. Example does this in `ExampleTypography.textTheme`; every
  /// other brand keeps the scale exactly as [textTheme] builds it.
  static TextTheme mapRoles(
    TextTheme base,
    TextStyle? Function(TextStyle? style, AppTextRole role) tune,
  ) {
    return TextTheme(
      displayLarge: tune(base.displayLarge, AppTextRole.display),
      displayMedium: tune(base.displayMedium, AppTextRole.display),
      displaySmall: tune(base.displaySmall, AppTextRole.display),
      headlineLarge: tune(base.headlineLarge, AppTextRole.headline),
      headlineMedium: tune(base.headlineMedium, AppTextRole.headline),
      headlineSmall: tune(base.headlineSmall, AppTextRole.headline),
      titleLarge: tune(base.titleLarge, AppTextRole.title),
      titleMedium: tune(base.titleMedium, AppTextRole.title),
      titleSmall: tune(base.titleSmall, AppTextRole.title),
      bodyLarge: tune(base.bodyLarge, AppTextRole.body),
      bodyMedium: tune(base.bodyMedium, AppTextRole.body),
      bodySmall: tune(base.bodySmall, AppTextRole.body),
      labelLarge: tune(base.labelLarge, AppTextRole.label),
      labelMedium: tune(base.labelMedium, AppTextRole.label),
      labelSmall: tune(base.labelSmall, AppTextRole.label),
    );
  }

  /// Convenience style for hero balance amounts. Use over headlineMedium when
  /// rendering currency to keep digit columns aligned.
  static TextStyle balance(Color color, {double size = 36}) => TextStyle(
        color: color,
        fontSize: size,
        fontWeight: FontWeight.w800,
        height: 1.05,
        letterSpacing: -0.5,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}
