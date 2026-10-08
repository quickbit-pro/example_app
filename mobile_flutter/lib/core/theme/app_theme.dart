import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../flavors.dart';
import '../branding/app_design.dart';
import '../../shared/theme/app_colors.dart';
import '../../shared/theme/app_spacing.dart';
import '../../shared/theme/app_theme_extensions.dart';
import '../../shared/theme/app_typography.dart';
import '../../brands/example/example_colors.dart';
import '../../brands/example/example_typography.dart';
import '../../brands/example/example_ui.dart';

/// Resolves a tenant-defined hex color (with or without `#`) and falls back
/// to the neo-bank default if the value is malformed.
Color _colorFromHex(String hex, {Color fallback = HoppaColors.primary}) {
  final sanitized = hex.replaceAll('#', '').trim();
  if (sanitized.isEmpty) {
    return fallback;
  }
  final value = int.tryParse('FF$sanitized', radix: 16);

  return value == null ? fallback : Color(value);
}

/// Bundles the light + dark themes for a tenant. Build once at the root and
/// pass into MaterialApp's `theme` / `darkTheme` / `themeMode`.
class AppThemes {
  const AppThemes({
    required this.light,
    required this.dark,
    required this.mode,
  });

  final ThemeData light;
  final ThemeData dark;
  final ThemeMode mode;
}

AppThemes buildAppThemes(AppBranding branding) {
  return AppThemes(
    light: _buildTheme(branding, Brightness.light),
    dark: _buildTheme(branding, Brightness.dark),
    mode: branding.materialThemeMode,
  );
}

ThemeData _buildTheme(AppBranding branding, Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final isExample = branding.isExample;
  final design = branding.design;
  final palette = ExamplePalette.fromDesign(brightness, design);
  Color custom(String key, Color fallback) =>
      design.color(brightness, key, fallback: fallback);
  // Twilight keeps violet / iris. Pearl daylight re-darkens both until the
  // fill carries white at 5.36:1 and the accent carries a link at 6.23:1;
  // iris and violet themselves sit at 2.72:1 and 3.95:1 on paper, so reusing
  // them on light would fail every text and focus check.
  var primary = isExample
      ? (isDark ? ExampleColors.violet : ExampleColors.lightViolet)
      : _colorFromHex(
          branding.primarySeedHex,
          fallback: HoppaColors.primary,
        );
  var accent = isExample
      ? (isDark ? ExampleColors.iris : ExampleColors.lightIris)
      : _colorFromHex(
          branding.accentSeedHex,
          fallback: HoppaColors.accent,
        );
  // Typeface: a tenant `APP_FONT_FAMILY` always wins; otherwise Example
  // renders its bundled Geist and every other brand keeps the Material
  // default, exactly as before.
  final family = branding.hasCustomFont
      ? branding.resolvedFontFamily
      : (isExample ? ExampleFonts.sans : null);

  // Surface tokens
  var paper = isExample
      ? (isDark ? ExampleColors.appBackground : ExampleColors.lightPaper)
      : (isDark ? HoppaColors.paperDark : HoppaColors.paper);
  var surface = isExample
      ? (isDark ? ExampleColors.darkSurface : ExampleColors.lightSurface)
      : (isDark ? HoppaColors.surfaceDark : HoppaColors.surface);
  var surfaceSubtle = isExample
      ? (isDark
          ? ExampleColors.darkSurfaceSubtle
          : ExampleColors.lightSurfaceSubtle)
      : (isDark ? HoppaColors.surfaceSubtleDark : HoppaColors.surfaceSubtle);
  var softSurface = isExample
      ? (isDark ? ExampleColors.indigo : ExampleColors.lightSurfaceHigh)
      : (isDark ? HoppaColors.softSurfaceDark : HoppaColors.softSurface);
  var surfacePressed = isExample
      ? (isDark ? ExampleColors.darkSurfaceHigh : ExampleColors.lightSurfaceHigh)
      : (isDark ? HoppaColors.surfacePressedDark : HoppaColors.surfacePressed);
  var border = isExample
      ? (isDark ? ExampleColors.darkBorder : ExampleColors.lightBorder)
      : (isDark ? HoppaColors.borderDark : HoppaColors.border);
  // The boundary of an *interactive* container — a field, a search bar, an
  // outlined button. WCAG 1.4.11 asks 3:1 of it, and on paper `border`
  // (#DED3EF) is 1.33:1 against the ground and 1.43:1 against white: no
  // boundary at all. Daylight therefore draws controls with night .58, the
  // same ink the auth screens already proved at 4.66-4.77:1. Structural
  // hairlines — dividers, card outlines, chips — keep `border`: they separate,
  // they do not delineate a control. Dark is untouched (its 1.24:1 is a
  // pre-existing weakness that only a dark-pixel mandate may move).
  var controlEdge =
      isExample && !isDark ? ExampleColors.lightTextTertiary : border;
  var ink = isExample
      ? (isDark ? ExampleColors.pearl : ExampleColors.lightTextPrimary)
      : (isDark ? HoppaColors.inkDark : HoppaColors.ink);
  var mutedInk = isExample
      ? (isDark ? ExampleColors.lavender : ExampleColors.lightTextSecondary)
      : (isDark ? HoppaColors.mutedInkDark : HoppaColors.mutedInk);

  // Dividers. Example daylight separates rows with a lavender .30 hairline;
  // Twilight and every other brand keep the solid outline they render today.
  var hairline = isExample && !isDark ? ExampleColors.lightBorderSubtle : border;
  var cryptoAccent = isExample
      ? (isDark ? ExampleColors.teal : ExampleColors.lightTeal)
      : HoppaColors.blue;
  var errorColor = isExample
      ? (isDark ? ExampleColors.danger : ExampleColors.lightDanger)
      : HoppaColors.rose;
  // Field outlines kept HoppaColors.rose on every brand before light mode;
  // only daylight moves, so no dark screen changes a pixel.
  var errorBorderColor =
      isExample && !isDark ? ExampleColors.lightDanger : HoppaColors.rose;
  // The accent foreground role (links, active icons, active nav labels).
  var accentInk = isExample
      ? (isDark ? ExampleColors.iris : ExampleColors.lightIris)
      : primary;

  // Semantic overrides feed both layout presets and shared Material controls.
  primary = custom('fill', primary);
  accent = custom('accent', accent);
  paper = custom('paper', paper);
  surface = custom('surface', surface);
  surfaceSubtle = custom('surfaceSubtle', surfaceSubtle);
  softSurface = custom('surfaceHigh', softSurface);
  surfacePressed = custom('surfaceHigh', surfacePressed);
  border = custom('border', border);
  controlEdge = custom('controlEdge', controlEdge);
  ink = custom('ink', ink);
  mutedInk = custom('textSecondary', mutedInk);
  hairline = custom('borderSubtle', hairline);
  cryptoAccent = custom('teal', cryptoAccent);
  errorColor = custom('danger', errorColor);
  errorBorderColor = custom('danger', errorBorderColor);
  accentInk = custom('accent', accentInk);
  final onFill = custom('onFill', Colors.white);

  final colorScheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: brightness,
  ).copyWith(
    primary: primary,
    onPrimary: onFill,
    secondary: accent,
    onSecondary: custom('onAccent', Colors.black),
    tertiary: cryptoAccent,
    error: errorColor,
    onError: Colors.white,
    surface: surface,
    onSurface: ink,
    onSurfaceVariant: mutedInk,
    surfaceContainerLowest: paper,
    surfaceContainerLow: surface,
    surfaceContainer: surfaceSubtle,
    surfaceContainerHigh: softSurface,
    surfaceContainerHighest: surfacePressed,
    outline: border,
    outlineVariant: hairline,
  );

  // Example on Geist gets the shared scale re-tracked for Geist metrics
  // (ExampleTypography). Any other brand, or Example under a tenant font
  // override, builds the scale exactly as today.
  var textTheme = isExample && !branding.hasCustomFont
      ? ExampleTypography.textTheme(ink)
      : AppTypography.textTheme(ink, fontFamily: family);
  if (design.typographyScale != 1) {
    textTheme = textTheme.apply(fontSizeFactor: design.typographyScale);
  }
  var financeExt = isExample
      ? (isDark
          ? const FinanceTheme(
              positive: ExampleColors.success,
              negative: ExampleColors.danger,
              pending: ExampleColors.warning,
              crypto: ExampleColors.teal,
              cardGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ExampleColors.night, ExampleColors.indigo],
              ),
              mutedGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ExampleColors.darkSurface,
                  ExampleColors.darkSurfaceSubtle
                ],
              ),
              heroGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ExampleColors.appBackground, ExampleColors.night],
              ),
            )
          // Card artwork stays dark in both themes — a Example card is a dark
          // object lying on the page, not a tinted panel — so cardGradient is
          // unchanged and only the page-level gradients turn to paper.
          : const FinanceTheme(
              positive: ExampleColors.lightSuccess,
              negative: ExampleColors.lightDanger,
              pending: ExampleColors.lightWarning,
              crypto: ExampleColors.lightTeal,
              cardGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [ExampleColors.night, ExampleColors.indigo],
              ),
              mutedGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ExampleColors.lightSurfaceSubtle,
                  ExampleColors.lightSurfaceHigh,
                ],
              ),
              heroGradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  ExampleColors.lightPaper,
                  ExampleColors.lightSurfaceSubtle,
                ],
              ),
            ))
      : isDark
          ? FinanceTheme.dark(accent: accent)
          : FinanceTheme.light(accent: accent);
  LinearGradient gradient(String prefix, LinearGradient original) =>
      LinearGradient(
        begin: original.begin,
        end: original.end,
        colors: [
          custom('${prefix}Start', original.colors.first),
          custom('${prefix}End', original.colors.last),
        ],
      );
  financeExt = financeExt.copyWith(
    positive: custom('success', financeExt.positive),
    negative: custom('danger', financeExt.negative),
    pending: custom('warning', financeExt.pending),
    crypto: custom('teal', financeExt.crypto),
    cardGradient: gradient('card', financeExt.cardGradient),
    heroGradient: gradient('hero', financeExt.heroGradient),
    mutedGradient: gradient('muted', financeExt.mutedGradient),
  );
  final shapeExt = BrandShapeTheme(scale: branding.resolvedRadiusScale);
  double radius(double value) => shapeExt.radius(value);

  return ThemeData(
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    fontFamily: family,
    textTheme: textTheme,
    useMaterial3: true,
    splashFactory:
        isExample ? InkSparkle.splashFactory : InkRipple.splashFactory,
    extensions: [
      financeExt,
      shapeExt,
      AppDesignTheme(
          design: design,
          appName: branding.appName,
          logoAsset: branding.logoAsset),
      if (isExample) const ExampleBrand(),
    ],
    // EXAMPLE pages hand off through the orbiting mark (420 ms,
    // ExampleRouteTransition) on every platform: the desktop shell keeps its
    // rail and header fixed, so a slide or zoom of the content column looks
    // like the whole page is being re-created.
    pageTransitionsTheme: isExample
        ? PageTransitionsTheme(
            builders: {
              for (final platform in TargetPlatform.values)
                platform: ExampleFadeTransitionsBuilder(
                  duration: !branding.design.motionEnabled
                      ? Duration.zero
                      : Duration(
                          microseconds: (ExampleMotion.route.inMicroseconds *
                                  branding.design.motionDurationScale)
                              .round()),
                ),
            },
          )
        : null,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: isExample ? Colors.transparent : paper,
      // Transparent app bars cannot infer the brightness of the page below.
      systemOverlayStyle: isExample
          ? (isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
              .copyWith(statusBarColor: Colors.transparent)
          : null,
      surfaceTintColor: Colors.transparent,
      foregroundColor: ink,
      toolbarHeight: isExample ? 56 : null,
      titleTextStyle: isExample
          ? textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 22,
              letterSpacing: -.3,
            )
          : textTheme.titleLarge,
      iconTheme: IconThemeData(color: ink),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.lg)),
        side: BorderSide(color: border),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: Colors.transparent,
      labelColor: isDark ? Colors.white : Colors.white,
      unselectedLabelColor: mutedInk,
      labelStyle: textTheme.labelMedium,
      unselectedLabelStyle: textTheme.labelMedium,
      indicator: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(44, 52)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return isExample
                ? (isDark
                    ? palette.fill.withValues(alpha: .22)
                    : palette.fill.withValues(alpha: .14))
                : primary.withValues(alpha: .18);
          }
          if (!isExample) return surface;
          return palette.paper;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          // On light the selected label sits on lightViolet at .14
          // (#E7E7FB); lightIris clears it at 5.13:1, the fill itself only
          // at 4.41:1.
          return states.contains(WidgetState.selected)
              ? (isExample
                  ? (isDark
                      ? custom('onFill', ExampleColors.pearl)
                      : palette.accent)
                  : primary)
              : mutedInk;
        }),
        side: WidgetStatePropertyAll(
          BorderSide(
            color: isExample
                ? (isDark
                    ? custom('textSecondary', ExampleColors.lavender)
                        .withValues(alpha: .14)
                    : palette.borderSubtle)
                : border,
          ),
        ),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
                isExample && !design.isConfigured ? 16 : radius(16)),
          ),
        ),
        textStyle: WidgetStatePropertyAll(
          textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        backgroundColor: primary,
        foregroundColor: onFill,
        disabledBackgroundColor: primary.withValues(alpha: 0.45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius(AppRadii.md)),
        ),
        textStyle: textTheme.labelLarge,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 54),
        foregroundColor: ink,
        side: BorderSide(color: controlEdge, width: 1.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius(AppRadii.md)),
        ),
        textStyle: textTheme.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accentInk,
        textStyle: textTheme.labelLarge,
        shape: isExample
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    design.isConfigured ? radius(10) : 10))
            : null,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: ink,
        shape: isExample
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                    design.isConfigured ? radius(12) : 12))
            : null,
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surfaceSubtle,
      selectedColor: primary.withValues(alpha: 0.18),
      side: BorderSide(color: border),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      labelStyle: textTheme.labelMedium?.copyWith(color: ink),
      secondaryLabelStyle: textTheme.labelMedium?.copyWith(color: ink),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      iconTheme: IconThemeData(color: ink, size: 18),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceSubtle,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.sm)),
        borderSide: BorderSide(color: controlEdge),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.sm)),
        borderSide: BorderSide(color: controlEdge),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.sm)),
        borderSide: BorderSide(color: primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.sm)),
        borderSide: BorderSide(color: errorBorderColor, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      labelStyle: textTheme.bodyMedium?.copyWith(color: mutedInk),
      hintStyle: textTheme.bodyMedium?.copyWith(color: mutedInk),
      prefixIconColor: mutedInk,
      suffixIconColor: mutedInk,
    ),
    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(surfaceSubtle),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(0),
      side: WidgetStatePropertyAll(BorderSide(color: controlEdge)),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(
              isExample && !design.isConfigured ? 16 : radius(16)),
        ),
      ),
      textStyle: WidgetStatePropertyAll(textTheme.bodyMedium),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyMedium?.copyWith(color: mutedInk),
      ),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.md)),
      ),
      iconColor: mutedInk,
      textColor: ink,
    ),
    dividerTheme: DividerThemeData(
      color: hairline,
      thickness: 1,
      space: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: custom(
          'snackbar',
          isExample && !isDark
              ? ExampleColors.night
              : (isDark ? HoppaColors.surfaceDark : HoppaColors.ink)),
      contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.md)),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
            top: Radius.circular(design.isConfigured ? radius(28) : 28)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius(AppRadii.xl)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      elevation: 0,
      height: isExample ? 60 : 70,
      backgroundColor:
          isExample ? palette.navigationGlass : custom('navigation', surface),
      indicatorColor:
          isExample ? Colors.transparent : primary.withValues(alpha: 0.18),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return textTheme.labelSmall?.copyWith(
          color: selected
              ? accentInk
              : (isExample ? palette.textTertiary : mutedInk),
          fontSize: isExample ? 9.5 : null,
          letterSpacing: isExample ? -.1 : null,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected
              ? accentInk
              : (isExample ? palette.textTertiary : mutedInk),
          size: isExample ? 22 : 24,
        );
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: primary,
      // Daylight tracks a progress bar with tertiary ink rather than a surface
      // step: lightSurfaceHigh is 1.18:1 on paper, so the part of the process
      // still to run was invisible and the bar read as a stub. .35 of night
      // .58 is the solved split — the filled/unfilled state boundary WCAG
      // 1.4.11 actually asks 3:1 of measures 3.15:1, and the track reads
      // 1.58:1 against the page (five times its old delta). No alpha makes all
      // three of page, track and fill mutually 3:1, so a track that must show
      // its full extent — the signup step bar — outlines itself as well.
      linearTrackColor: isExample && !isDark
          ? palette.textTertiary.withValues(alpha: .35)
          : surfacePressed,
      circularTrackColor: isExample && !isDark
          ? palette.textTertiary.withValues(alpha: .35)
          : null,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? Colors.white : mutedInk),
      trackColor: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected) ? primary : surfacePressed),
      // Off state on paper: a white thumb on lightSurfaceHigh is 1.31:1 and
      // the track is 1.21:1 against the page, so an unset switch had no
      // boundary. The selected track carries its own colour and needs none.
      // Example daylight only. Null anywhere else restores Material's own
      // resolver verbatim — which differs from `controlEdge` in the DISABLED
      // unselected state (M3 paints onSurface at 12%, not a full-strength
      // border), so leaving this ungated silently repainted every white-label
      // tenant's disabled switches, and Example's dark ones too.
      trackOutlineColor: isExample && !isDark
          ? WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? Colors.transparent
                  : controlEdge)
          : null,
    ),
  );
}

/// Backwards-compatible single-theme builder kept for any callers that still
/// depend on the old name. New code should call [buildAppThemes].
ThemeData buildAppTheme(AppBranding branding) => buildAppThemes(branding).dark;
