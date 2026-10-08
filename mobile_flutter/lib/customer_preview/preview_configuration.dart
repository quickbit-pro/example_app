import 'dart:convert';
import 'package:flutter/services.dart';

import '../core/branding/app_design.dart';
import '../flavors.dart';

/// Translates the very same schema consumed by prepare-mobile-brand.py into
/// the production theme model. Source asset paths become bundle keys instead
/// of generated build paths; their bytes and the rendered widgets stay real.
class CustomerPreviewConfiguration {
  const CustomerPreviewConfiguration({
    required this.branding,
    required this.bundle,
    required this.screen,
    required this.brightness,
  });

  final AppBranding branding;
  final AssetBundle bundle;
  final String screen;
  final Brightness brightness;

  static const screens = {
    'home',
    'login',
    'cards',
    'profile',
    'splash',
    'loader'
  };
  static final Map<String, Future<String>> _fontFamilies = {};
  static int _fontVersion = 0;

  static Future<CustomerPreviewConfiguration> fromMessage(
    Map<String, dynamic> message, {
    int revision = 0,
    AssetBundle? fallbackBundle,
  }) async {
    final source = message['config'];
    if (source is! Map<String, dynamic> || source['schemaVersion'] != 1) {
      throw const FormatException('Expected a schemaVersion 1 app config');
    }
    final app = _object(source['app']);
    final design = jsonDecode(jsonEncode(_object(source['design'])))
        as Map<String, dynamic>;
    final originalDesign = AppDesign.fromJsonString(jsonEncode(design));
    for (final mode in ['light', 'dark']) {
      for (final color in _object(design[mode]).values) {
        if (color is String) AppDesign.parseColor(color);
      }
    }
    final uploads = <String, Uint8List>{};
    final rawAssets = message['assets'];
    final entries = rawAssets is List
        ? rawAssets
        : rawAssets is Map
            ? [
                for (final entry in rawAssets.entries)
                  {..._object(entry.value), 'path': entry.key},
              ]
            : const [];
    for (final raw in entries) {
      final entry = _object(raw);
      final path = _assetPath(entry['path']);
      final encoded = entry['data'];
      if (encoded is! String || encoded.length > 32 * 1024 * 1024) {
        throw const FormatException('An uploaded preview asset is too large');
      }
      uploads[path] = base64Decode(encoded);
    }
    final bundle = PreviewAssetBundle(
      uploads: uploads,
      fallback: fallbackBundle ?? rootBundle,
    );
    final assets = _object(design['assets']);
    for (final entry in assets.entries.toList()) {
      if (entry.value == null || entry.value == '') continue;
      final path = _assetPath(entry.value);
      final alias = 'customer-preview/$revision/$path';
      bundle.aliases[alias] = path;
      assets[entry.key] = alias;
    }
    design['assets'] = assets;

    final typography = _object(design['typography']);
    for (final rawFont
        in source['fonts'] is List ? source['fonts'] : const []) {
      final font = _object(rawFont);
      final family = font['family'];
      if (family is! String || family.isEmpty) continue;
      final files = font['files'] is List ? font['files'] as List : const [];
      final bytes = <ByteData>[];
      for (final rawFile in files) {
        final path = _assetPath(_object(rawFile)['path']);
        bytes.add(await bundle.loadSource(path));
      }
      if (bytes.isEmpty) continue;
      final signature =
          '$family:${Object.hashAll(bytes.map((data) => Object.hashAll(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes))))}';
      // Rapid wizard edits can overlap while a font is being decoded. Reserve
      // a unique family immediately and share its future, so an older upload
      // cannot win the same family name or paint before the new font is ready.
      final loadedFamily = await _fontFamilies.putIfAbsent(signature, () async {
        final loadedFamily = 'CustomerPreviewFont${_fontVersion++}_$family';
        final loader = FontLoader(loadedFamily);
        for (final data in bytes) {
          loader.addFont(Future.value(data));
        }
        await loader.load();
        return loadedFamily;
      });
      for (final key in ['fontFamily', 'monoFontFamily']) {
        if (typography[key] == family) typography[key] = loadedFamily;
      }
    }
    design['typography'] = typography;
    final light = _object(design['light']);
    final theme = message['theme'] == 'dark' ? 'dark' : 'light';
    final requestedScreen = message['screen'];
    if (requestedScreen != null && !screens.contains(requestedScreen)) {
      throw const FormatException('Unknown customer preview screen');
    }
    return CustomerPreviewConfiguration(
      screen: requestedScreen as String? ?? 'home',
      brightness: theme == 'dark' ? Brightness.dark : Brightness.light,
      bundle: bundle,
      branding: AppBranding(
        appName: app['name']?.toString().trim() ?? 'Your app',
        brandId: app['id']?.toString() ?? 'customer-preview',
        primarySeedHex: _seed(light['fill'], '621A96'),
        accentSeedHex: _seed(light['accent'], '4E1578'),
        loginBackgroundHex: '',
        themeMode: theme,
        fontFamily: '',
        logoAsset: assets['logo']?.toString() ?? '',
        radiusScale: (originalDesign.radiusScale ?? 1).toString(),
        supportEmail: app['supportEmail']?.toString() ?? '',
        supportPhone: app['supportPhone']?.toString() ?? '',
        legalEntity: app['legalEntity']?.toString() ?? '',
        // External URLs are deliberately not enabled in an offline preview.
        transferDashboardUrl: '',
        design: AppDesign.fromJsonString(jsonEncode(design)),
      ),
    );
  }
}

Map<String, dynamic> _object(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String _assetPath(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.startsWith('/') ||
      value.contains('\\') ||
      value.contains(':') ||
      value.split('/').contains('..')) {
    throw const FormatException('Assets must use relative config file paths');
  }
  return value.replaceFirst(RegExp(r'^\./'), '');
}

String _seed(Object? value, String fallback) {
  if (value is! String || value.isEmpty) return fallback;
  final hex = value.replaceFirst('#', '');
  return hex.length == 8 ? hex.substring(2) : hex;
}

class PreviewAssetBundle extends CachingAssetBundle {
  PreviewAssetBundle({required this.uploads, required this.fallback});

  final Map<String, Uint8List> uploads;
  final AssetBundle fallback;
  final Map<String, String> aliases = {};

  Future<ByteData> loadSource(String path) async {
    final bytes = uploads[path];
    if (bytes != null) return ByteData.sublistView(bytes);
    // The single-file packager includes original config files alongside the
    // generated Flutter assets so switching source configs needs no rebuild.
    return fallback.load('config/$path');
  }

  @override
  Future<ByteData> load(String key) {
    final source = aliases[key];
    return source == null ? fallback.load(key) : loadSource(source);
  }
}
