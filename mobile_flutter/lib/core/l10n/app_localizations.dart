import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';

class AppLanguage {
  const AppLanguage(this.code, this.name);
  final String code;
  final String name;
  Locale get locale => Locale(code);
}

const appLanguages = <AppLanguage>[
  AppLanguage('en', 'English'),
  AppLanguage('de', 'Deutsch'),
  AppLanguage('es', 'Español'),
  AppLanguage('ar', 'العربية'),
  AppLanguage('fr', 'Français'),
  AppLanguage('pt', 'Português'),
  AppLanguage('hi', 'हिन्दी'),
  AppLanguage('it', 'Italiano'),
  AppLanguage('ja', '日本語'),
  AppLanguage('ko', '한국어'),
  AppLanguage('id', 'Bahasa Indonesia'),
  AppLanguage('pl', 'Polski'),
  AppLanguage('tr', 'Türkçe'),
];

/// Only application copy belongs in this catalogue. Values supplied by users,
/// providers, currency codes and identifiers must remain unmodified.
class AppLocalizations {
  const AppLocalizations(this.locale, this.messages);
  final Locale locale;
  final Map<String, String> messages;
  static const delegate = _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations) ??
      const AppLocalizations(Locale('en'), {});

  String translate(String key, [Map<String, Object?> values = const {}]) {
    final template = messages[key] ?? key;
    // A single pass prevents a substituted name containing braces from being
    // interpreted as another placeholder.
    return template.replaceAllMapped(RegExp(r'\{(p\d+)\}'), (match) {
      final name = match.group(1)!;
      return values.containsKey(name) ? '${values[name]}' : match.group(0)!;
    });
  }
}

extension AppTranslationContext on BuildContext {
  String tr(String key, [Map<String, Object?> values = const {}]) =>
      AppLocalizations.of(this).translate(key, values);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      appLanguages.any((language) => language.code == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async {
    if (locale.languageCode == 'en') {
      return const AppLocalizations(Locale('en'), {});
    }
    try {
      final source = await rootBundle
          .loadString('assets/l10n/${locale.languageCode}.json');
      final messages = (jsonDecode(source) as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String));
      return AppLocalizations(locale, messages);
    } catch (_) {
      // A PWA may be offline before this language has been cached. Keep the
      // app usable using its original copy rather than failing app startup.
      return AppLocalizations(locale, const {});
    }
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
