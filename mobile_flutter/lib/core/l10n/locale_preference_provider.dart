import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_localizations.dart';

const _key = 'app.language.v1';

Locale? _decode(String? code) =>
    appLanguages.any((language) => language.code == code)
        ? Locale(code!)
        : null;

final bootLocaleProvider = Provider<Locale?>((ref) => null);

class LocalePreferenceController extends Notifier<Locale?> {
  @override
  Locale? build() => ref.read(bootLocaleProvider);

  Future<void> setLocale(Locale? locale) async {
    final selected = _decode(locale?.languageCode);
    final preferences = await SharedPreferences.getInstance();
    if (selected == null) {
      await preferences.remove(_key);
    } else {
      await preferences.setString(_key, selected.languageCode);
    }
    state = selected;
  }
}

final localePreferenceProvider =
    NotifierProvider<LocalePreferenceController, Locale?>(
        LocalePreferenceController.new);

Future<List<Override>> bootLocaleOverrides() async {
  try {
    final preferences = await SharedPreferences.getInstance();
    return [
      bootLocaleProvider
          .overrideWithValue(_decode(preferences.getString(_key))),
    ];
  } catch (_) {
    return const [];
  }
}
