import 'package:flutter/material.dart';

/// Static brand-agnostic semantic palette. Tenant-specific accents flow through
/// `ColorScheme` (built from `AppBranding.primarySeedHex` /
/// `accentSeedHex`); these tokens are the framework around the seed and stay
/// consistent across white-label builds so component code can rely on them.
abstract final class HoppaColors {
  // === Light surfaces ===
  static const ink = Color(0xFF0E1116);
  static const mutedInk = Color(0xFF6B7280);
  static const paper = Color(0xFFF6F7FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceSubtle = Color(0xFFF1F3F8);
  static const softSurface = Color(0xFFE9ECF4);
  static const surfacePressed = Color(0xFFDFE3EE);
  static const border = Color(0xFFE3E6EE);

  // === Dark surfaces (neo-bank) ===
  static const inkDark = Color(0xFFF5F6FA);
  static const mutedInkDark = Color(0xFF9AA3B2);
  static const paperDark = Color(0xFF0B0B0F); // app background
  static const surfaceDark = Color(0xFF15161D); // raised card
  static const surfaceSubtleDark = Color(0xFF1B1D26);
  static const softSurfaceDark = Color(0xFF22242F);
  static const surfacePressedDark = Color(0xFF2A2C38);
  static const borderDark = Color(0xFF262833);

  // === Brand defaults (overridden by tenant seeds at runtime) ===
  static const primary = Color(0xFF7C5CFF); // electric violet
  static const primaryDark = Color(0xFF5B3BE0);
  static const accent = Color(0xFF2DD4BF); // complementary mint-teal
  static const lime = Color(0xFFD7F56D);
  static const blue = Color(0xFF4C8DFF);
  static const amber = Color(0xFFF7B955);
  static const rose = Color(0xFFFF6B81);
  static const success = Color(0xFF22C58A);
  static const cardDark = Color(0xFF101218);
  static const cardMetal = Color(0xFFCBD5E1);

  static Color statusColor(FinanceStatusTone tone) {
    return switch (tone) {
      FinanceStatusTone.success => success,
      FinanceStatusTone.warning => amber,
      FinanceStatusTone.danger => rose,
      FinanceStatusTone.info => blue,
      FinanceStatusTone.neutral => mutedInk,
    };
  }

  /// Tone background for light surfaces.
  static Color statusBackground(FinanceStatusTone tone) {
    return switch (tone) {
      FinanceStatusTone.success => const Color(0xFFE3F8EF),
      FinanceStatusTone.warning => const Color(0xFFFFF4DC),
      FinanceStatusTone.danger => const Color(0xFFFFE4E9),
      FinanceStatusTone.info => const Color(0xFFE5EEFF),
      FinanceStatusTone.neutral => const Color(0xFFEFF1F7),
    };
  }

  /// Tone background for dark surfaces (lower alpha keeps it from glowing).
  static Color statusBackgroundDark(FinanceStatusTone tone) {
    return statusColor(tone).withValues(alpha: 0.16);
  }
}

enum FinanceStatusTone {
  success,
  warning,
  danger,
  info,
  neutral,
}
