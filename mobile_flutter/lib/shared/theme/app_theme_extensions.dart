import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class FinanceTheme extends ThemeExtension<FinanceTheme> {
  const FinanceTheme({
    required this.positive,
    required this.negative,
    required this.pending,
    required this.crypto,
    required this.cardGradient,
    required this.mutedGradient,
    required this.heroGradient,
  });

  /// Light variant — used when tenant chooses `themeMode=light`.
  const FinanceTheme.light({
    Color accent = HoppaColors.primary,
  })  : positive = HoppaColors.success,
        negative = HoppaColors.rose,
        pending = HoppaColors.amber,
        crypto = HoppaColors.blue,
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B1D26),
            Color(0xFF3B2D6B),
          ],
        ),
        mutedGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFF1F3F8),
            Color(0xFFE9ECF4),
          ],
        ),
        heroGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HoppaColors.primary,
            Color(0xFF4C32C7),
          ],
        );

  /// Dark variant — neo-bank default.
  const FinanceTheme.dark({
    Color accent = HoppaColors.primary,
  })  : positive = HoppaColors.success,
        negative = HoppaColors.rose,
        pending = HoppaColors.amber,
        crypto = HoppaColors.blue,
        cardGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1F1A33),
            Color(0xFF7C5CFF),
          ],
        ),
        mutedGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1B1D26),
            Color(0xFF15161D),
          ],
        ),
        heroGradient = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF6E48FF),
            Color(0xFF301F9C),
          ],
        );

  final Color positive;
  final Color negative;
  final Color pending;
  final Color crypto;
  final LinearGradient cardGradient;
  final LinearGradient mutedGradient;
  final LinearGradient heroGradient;

  @override
  FinanceTheme copyWith({
    Color? positive,
    Color? negative,
    Color? pending,
    Color? crypto,
    LinearGradient? cardGradient,
    LinearGradient? mutedGradient,
    LinearGradient? heroGradient,
  }) {
    return FinanceTheme(
      positive: positive ?? this.positive,
      negative: negative ?? this.negative,
      pending: pending ?? this.pending,
      crypto: crypto ?? this.crypto,
      cardGradient: cardGradient ?? this.cardGradient,
      mutedGradient: mutedGradient ?? this.mutedGradient,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  FinanceTheme lerp(ThemeExtension<FinanceTheme>? other, double t) {
    if (other is! FinanceTheme) {
      return this;
    }

    return FinanceTheme(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      pending: Color.lerp(pending, other.pending, t)!,
      crypto: Color.lerp(crypto, other.crypto, t)!,
      cardGradient: LinearGradient.lerp(cardGradient, other.cardGradient, t)!,
      mutedGradient:
          LinearGradient.lerp(mutedGradient, other.mutedGradient, t)!,
      heroGradient: LinearGradient.lerp(heroGradient, other.heroGradient, t)!,
    );
  }
}

extension FinanceThemeLookup on BuildContext {
  FinanceTheme get financeTheme =>
      Theme.of(this).extension<FinanceTheme>() ?? const FinanceTheme.dark();
}

@immutable
class BrandShapeTheme extends ThemeExtension<BrandShapeTheme> {
  const BrandShapeTheme({required this.scale});

  final double scale;

  double radius(double value) => value * scale;

  @override
  BrandShapeTheme copyWith({double? scale}) =>
      BrandShapeTheme(scale: scale ?? this.scale);

  @override
  BrandShapeTheme lerp(ThemeExtension<BrandShapeTheme>? other, double t) {
    if (other is! BrandShapeTheme) {
      return this;
    }
    return BrandShapeTheme(scale: scale + (other.scale - scale) * t);
  }
}

extension BrandShapeThemeLookup on BuildContext {
  BrandShapeTheme get brandShape =>
      Theme.of(this).extension<BrandShapeTheme>() ??
      const BrandShapeTheme(scale: 1);
}
