import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-controlled theme override. When `null`, the tenant default from
/// `AppBranding.materialThemeMode` wins. When set, this takes priority and
/// is persisted across launches.
class ThemePreferenceController extends AsyncNotifier<ThemeMode?> {
  static const _key = 'app.themeMode.v1';

  @override
  Future<ThemeMode?> build() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_key);
    return _decode(value);
  }

  Future<void> setMode(ThemeMode? mode) async {
    state = AsyncData(mode);
    final preferences = await SharedPreferences.getInstance();
    if (mode == null) {
      await preferences.remove(_key);
      return;
    }
    await preferences.setString(_key, _encode(mode));
  }

  static ThemeMode? _decode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      default:
        return null; // follow tenant default
    }
  }

  static String _encode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themePreferenceProvider =
    AsyncNotifierProvider<ThemePreferenceController, ThemeMode?>(
  ThemePreferenceController.new,
);

/// Debug-only theme flag for the web build: open the app with `?theme=light`,
/// `?theme=dark` or `?theme=system` (before the `#` route) to force that mode
/// for the launch without touching the stored preference.
///
/// It is the highest-priority input to the resolution chain in
/// `lib/app/mobile_app.dart` — URL flag, then the persisted preference, then
/// `APP_THEME_MODE`, then the system setting — so a reviewer can screenshot
/// both themes of any route without opening Settings, and cannot leave the
/// device in the wrong mode afterwards.
///
/// Default `null` means "no flag"; [debugThemeModeOverrides] supplies the
/// value at startup and returns nothing at all in release or on native, so
/// the parsing compiles out.
final debugThemeModeOverrideProvider = Provider<ThemeMode?>((ref) => null);

/// The stored theme mode as `main()` read it off disk, before the first
/// frame.
///
/// [ThemePreferenceController] is an `AsyncNotifier`: its answer arrives a
/// frame or two after launch, and until then the app has to resolve a theme
/// from the tenant default alone. On a dark-first tenant that means a
/// customer who chose Pearl daylight gets one or more Twilight frames, then a
/// full re-theme — a flash on every cold start, and the deepest luminance
/// jump the app can make.
///
/// So the same key is read once, synchronously with startup, in
/// [bootThemeModeOverrides], and injected here. `lib/app/mobile_app.dart`
/// uses it *only* while the notifier has no value yet, so the stored
/// preference stays the single source of truth the moment it lands and this
/// can never go stale.
///
/// Default `null` means "nothing stored", which resolves to the tenant
/// default exactly as before.
final bootThemeModeProvider = Provider<ThemeMode?>((ref) => null);

/// Reads the persisted theme mode before `runApp`, as a [ProviderScope]
/// override for [bootThemeModeProvider].
///
/// Returns an empty list when nothing is stored or when the platform store is
/// unavailable, so a failure here costs the old behaviour and nothing more.
Future<List<Override>> bootThemeModeOverrides() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    final mode = ThemePreferenceController._decode(
      preferences.getString(ThemePreferenceController._key),
    );
    if (mode == null) return const [];
    return [bootThemeModeProvider.overrideWithValue(mode)];
  } catch (_) {
    return const [];
  }
}

/// Overrides for [ProviderScope] carrying the `?theme=` flag, or an empty
/// list when the flag is absent, the build is not debug, or the platform is
/// not web.
List<Override> debugThemeModeOverrides() {
  if (!kDebugMode || !kIsWeb) return const [];
  final mode = ThemePreferenceController._decode(
    Uri.base.queryParameters['theme']?.toLowerCase(),
  );
  if (mode == null) return const [];
  return [debugThemeModeOverrideProvider.overrideWithValue(mode)];
}
