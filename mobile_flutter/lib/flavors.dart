import 'package:flutter/material.dart';

import 'core/branding/app_design.dart';

enum AppFlavor {
  dev,
  staging,
  prod;

  static AppFlavor fromEnvironment() {
    const value = String.fromEnvironment('APP_FLAVOR', defaultValue: 'dev');

    return AppFlavor.values.firstWhere(
      (flavor) => flavor.name == value,
      orElse: () => AppFlavor.dev,
    );
  }
}

/// White-label branding values. Every field is overridable from the build
/// pipeline via `--dart-define` so a customer can re-skin the app without
/// touching code.
///
/// Example release build:
/// ```
/// flutter build ipa \
///   --dart-define=APP_NAME="Acme Pay" \
///   --dart-define=APP_PRIMARY_COLOR=7C5CFF \
///   --dart-define=APP_ACCENT_COLOR=2DD4BF \
///   --dart-define=APP_LOGIN_BACKGROUND_COLOR=123ABC \
///   --dart-define=APP_THEME_MODE=dark \
///   --dart-define=APP_FONT_FAMILY=Inter \
///   --dart-define=APP_LOGO_ASSET=assets/brand/acme.png \
///   --dart-define=SUPPORT_EMAIL=help@acme.test \
///   --dart-define=APP_WEB_URL=https://app.acme.test
/// ```
class AppBranding {
  const AppBranding({
    required this.appName,
    required this.primarySeedHex,
    required this.accentSeedHex,
    required this.loginBackgroundHex,
    required this.themeMode,
    required this.fontFamily,
    required this.logoAsset,
    required this.radiusScale,
    required this.supportEmail,
    required this.supportPhone,
    required this.legalEntity,
    this.brandId = 'generic',
    this.transferDashboardUrl = '',
    this.design = const AppDesign(),
    this.webAppUrl = '',
  });

  factory AppBranding.fromEnvironment() {
    const appName = String.fromEnvironment(
      'APP_NAME',
      defaultValue: 'Hoppa',
    );
    const primarySeedHex = String.fromEnvironment(
      'APP_PRIMARY_COLOR',
      defaultValue: '7C5CFF', // electric violet, neo-bank default
    );
    const accentSeedHex = String.fromEnvironment(
      'APP_ACCENT_COLOR',
      defaultValue: '2DD4BF', // complementary mint-teal accent
    );
    const loginBackgroundHex = String.fromEnvironment(
      'APP_LOGIN_BACKGROUND_COLOR',
      defaultValue: '', // empty -> use the standard login gradient
    );
    const themeMode = String.fromEnvironment(
      'APP_THEME_MODE',
      defaultValue: 'dark', // dark-first neo-bank vibe
    );
    const fontFamily = String.fromEnvironment(
      'APP_FONT_FAMILY',
      defaultValue: '', // empty -> Material default
    );
    const logoAsset = String.fromEnvironment(
      'APP_LOGO_ASSET',
      defaultValue: '', // empty -> use icon glyph fallback
    );
    const radiusScale = String.fromEnvironment(
      'APP_RADIUS_SCALE',
      defaultValue: '1.0',
    );
    const supportEmail = String.fromEnvironment(
      'SUPPORT_EMAIL',
      defaultValue: 'support@example.com',
    );
    const supportPhone = String.fromEnvironment(
      'SUPPORT_PHONE',
      defaultValue: '',
    );
    const legalEntity = String.fromEnvironment(
      'LEGAL_ENTITY',
      defaultValue: '',
    );
    const brandId = String.fromEnvironment(
      'APP_BRAND_ID',
      defaultValue: 'generic',
    );
    // Web address of the provider dashboard where customers generate the
    // account-transfer QR (Security → App transfer), e.g. https://example.com
    const transferDashboardUrl = String.fromEnvironment(
      'ACCOUNT_TRANSFER_DASHBOARD_URL',
      defaultValue: '',
    );
    // Public address of the web app (PWA) where a referred friend can sign
    // up, e.g. https://hoppa.roks.dev. Native builds use it to write invite
    // links when the platform only returns a relative sign-up path; the web
    // build derives the link from its own address instead.
    const webAppUrl = String.fromEnvironment(
      'APP_WEB_URL',
      defaultValue: '',
    );

    const designJson = String.fromEnvironment('APP_DESIGN_JSON');
    return AppBranding(
      appName: appName == 'EXAMPLE' ? 'Example' : appName,
      primarySeedHex: primarySeedHex,
      accentSeedHex: accentSeedHex,
      loginBackgroundHex: loginBackgroundHex,
      themeMode: themeMode,
      fontFamily: fontFamily,
      logoAsset: logoAsset,
      radiusScale: radiusScale,
      supportEmail: supportEmail,
      supportPhone: supportPhone,
      legalEntity: legalEntity,
      brandId: brandId,
      transferDashboardUrl: transferDashboardUrl,
      design: AppDesign.fromJsonString(designJson),
      webAppUrl: webAppUrl,
    );
  }

  final String appName;
  final String primarySeedHex;
  final String accentSeedHex;
  final String loginBackgroundHex;

  /// One of `light` | `dark` | `system`. Anything else falls back to `dark`.
  final String themeMode;
  final String fontFamily;
  final String logoAsset;
  final String radiusScale;
  final String supportEmail;
  final String supportPhone;
  final String legalEntity;
  final String brandId;
  final AppDesign design;

  /// Dashboard URL shown in the account-transfer instructions; empty hides the link.
  final String transferDashboardUrl;

  /// Public web app URL used to build invite links on native builds; empty
  /// means none is configured.
  final String webAppUrl;

  bool get isExampleIdentity =>
      brandId.trim().toLowerCase() == 'example' ||
      appName.trim().toLowerCase() == 'example';

  /// Compatibility name for existing presentation call sites. Layout selection
  /// is independent of customer identity: a new brand can reuse the complete
  /// responsive layout without claiming to be Example.
  bool get isExample =>
      design.layout == null ? isExampleIdentity : design.layout == 'example';

  bool get usesExampleLayout => isExample;

  ThemeMode get materialThemeMode {
    switch (themeMode.toLowerCase()) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }

  bool get hasLogoAsset => logoAsset.trim().isNotEmpty;
  bool get hasCustomFont => resolvedFontFamily.isNotEmpty;
  String get resolvedFontFamily =>
      design.fontFamily.isNotEmpty ? design.fontFamily : fontFamily.trim();

  Color? get loginBackgroundColor {
    final sanitized = loginBackgroundHex.replaceAll('#', '').trim();
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(sanitized)) {
      return null;
    }

    return Color(int.parse('FF$sanitized', radix: 16));
  }

  double get resolvedRadiusScale {
    if (design.radiusScale != null) return design.radiusScale!;
    final parsed = double.tryParse(radiusScale);
    return (parsed ?? 1).clamp(0.65, 1.4);
  }
}

class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.apiBaseUrl,
    required this.branding,
  });

  factory AppConfig.fromEnvironment() {
    final flavor = AppFlavor.fromEnvironment();
    const configuredApiBaseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: '',
    );
    if (configuredApiBaseUrl.trim().isEmpty && flavor != AppFlavor.dev) {
      throw StateError(
        'API_BASE_URL must be supplied for staging and production builds.',
      );
    }
    return AppConfig(
      flavor: flavor,
      apiBaseUrl: configuredApiBaseUrl.trim().isEmpty
          ? 'https://demo-api.roks.dev'
          : configuredApiBaseUrl.trim(),
      branding: AppBranding.fromEnvironment(),
    );
  }

  final AppFlavor flavor;
  final String apiBaseUrl;
  final AppBranding branding;
}
