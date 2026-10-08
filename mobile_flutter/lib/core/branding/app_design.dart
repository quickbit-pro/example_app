import 'dart:convert';

import 'package:flutter/material.dart';

/// Build-time visual configuration, independent of the app's business identity.
///
/// The brand preparation tool validates the source JSON and places this subset
/// in APP_DESIGN_JSON. Values are public app resources, never credentials.
@immutable
class AppDesign {
  const AppDesign([this.values = const <String, dynamic>{}]);

  factory AppDesign.fromJsonString(String value) {
    if (value.trim().isEmpty) return const AppDesign();
    final decoded = jsonDecode(value);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('APP_DESIGN_JSON must contain a JSON object');
    }
    final design = AppDesign(Map<String, dynamic>.unmodifiable(decoded));
    final layout = design.layout;
    if (layout != null && layout != 'example' && layout != 'generic') {
      throw const FormatException('design.layout must be example or generic');
    }
    return design;
  }

  final Map<String, dynamic> values;

  Map<String, dynamic> _section(String name) {
    final section = values[name];
    return section is Map<String, dynamic> ? section : const {};
  }

  String _string(String section, String name, [String fallback = '']) {
    final value = _section(section)[name];
    return value is String && value.trim().isNotEmpty ? value.trim() : fallback;
  }

  double _number(String section, String name, double fallback,
      {required double min, required double max}) {
    final value = _section(section)[name];
    final parsed = value is num ? value.toDouble() : double.tryParse('$value');
    if (parsed == null || !parsed.isFinite) return fallback;
    return parsed.clamp(min, max);
  }

  String? get layout =>
      values['layout'] is String ? (values['layout'] as String).trim() : null;
  bool get isConfigured => values.isNotEmpty;
  String get fontFamily => _string('typography', 'fontFamily');
  String get monoFontFamily =>
      _string('typography', 'monoFontFamily', 'GeistMono');
  double get typographyScale =>
      _number('typography', 'scale', 1, min: .75, max: 1.5);
  double? get radiusScale => _section('shape').containsKey('radiusScale')
      ? _number('shape', 'radiusScale', 1, min: .0, max: 2)
      : null;
  String get loaderStyle => _string('loader', 'style', 'circular');
  int get loaderDurationMs =>
      _number('loader', 'durationMs', 1200, min: 200, max: 10000).round();
  bool get splashEnabled => _section('splash')['enabled'] != false;
  int get splashMinimumDurationMs =>
      _number('splash', 'minimumDurationMs', 450, min: 0, max: 10000).round();
  int get splashMaximumDurationMs =>
      _number('splash', 'maximumDurationMs', 8000, min: 0, max: 30000)
          .round()
          .clamp(splashMinimumDurationMs, 30000);
  bool get motionEnabled => _section('motion')['enabled'] != false;
  double get motionDurationScale =>
      _number('motion', 'durationScale', 1, min: .1, max: 3);

  String asset(String key) => _string('assets', key);
  String logoFor(Brightness brightness) {
    final dark = asset('logoDark');
    return brightness == Brightness.dark && dark.isNotEmpty
        ? dark
        : asset('logo');
  }

  static Color parseColor(String value) {
    final hex = value.trim().replaceFirst(RegExp(r'^#'), '');
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      throw FormatException('Expected #RRGGBB or #AARRGGBB color', value);
    }
    return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
  }

  Color color(Brightness brightness, String key, {required Color fallback}) {
    final value = _string(brightness.name, key);
    return value.isEmpty ? fallback : parseColor(value);
  }

  Color splashBackground(Brightness brightness, {required Color fallback}) {
    final value = _string('splash',
        brightness == Brightness.dark ? 'backgroundDark' : 'backgroundLight');
    return value.isEmpty ? fallback : parseColor(value);
  }
}

/// Carries the same configuration through Material themes and component trees.
@immutable
class AppDesignTheme extends ThemeExtension<AppDesignTheme> {
  const AppDesignTheme({
    required this.design,
    this.appName = '',
    this.logoAsset = '',
  });
  final AppDesign design;
  final String appName;
  final String logoAsset;

  static AppDesign of(BuildContext context) =>
      Theme.of(context).extension<AppDesignTheme>()?.design ??
      const AppDesign();

  static String nameOf(BuildContext context) =>
      Theme.of(context).extension<AppDesignTheme>()?.appName ?? '';

  static String logoOf(BuildContext context) {
    final extension = Theme.of(context).extension<AppDesignTheme>();
    final configured =
        extension?.design.logoFor(Theme.of(context).brightness) ?? '';
    return configured.isNotEmpty ? configured : extension?.logoAsset ?? '';
  }

  @override
  AppDesignTheme copyWith(
          {AppDesign? design, String? appName, String? logoAsset}) =>
      AppDesignTheme(
        design: design ?? this.design,
        appName: appName ?? this.appName,
        logoAsset: logoAsset ?? this.logoAsset,
      );

  @override
  AppDesignTheme lerp(covariant AppDesignTheme? other, double t) =>
      other == null || t < .5 ? this : other;
}

extension AppDesignLookup on BuildContext {
  AppDesign get brandDesign => AppDesignTheme.of(this);
}
