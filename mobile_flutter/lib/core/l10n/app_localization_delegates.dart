import 'package:flutter/cupertino.dart' show CupertinoLocalizations;
import 'package:flutter/material.dart' show MaterialLocalizations;
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phone_form_field/phone_form_field.dart';

import 'app_localizations.dart';

/// Every delegate the app registers: its own copy, the framework's, and the
/// phone field's country names, search box and validation messages.
///
/// The phone field's package speaks most of [appLanguages] but not all of
/// them (Japanese and Indonesian are missing). A delegate that does not
/// support the running locale makes the framework report an error on every
/// build in debug, so those delegates are wrapped to answer every locale and
/// serve English copy where the package has none.
final appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  for (final delegate in PhoneFieldLocalization.delegates)
    if (!_frameworkTypes.contains(delegate.type))
      _EnglishFallbackDelegate(delegate),
];

/// The framework's own delegates, which the phone field's set repeats; the
/// app registers those itself above.
const _frameworkTypes = {
  MaterialLocalizations,
  WidgetsLocalizations,
  CupertinoLocalizations,
};

/// Wraps a delegate so that every locale is supported: locales the wrapped
/// delegate knows load as themselves, the rest load its English copy.
class _EnglishFallbackDelegate<T> extends LocalizationsDelegate<T> {
  const _EnglishFallbackDelegate(this.inner);

  final LocalizationsDelegate<T> inner;

  static const _fallback = Locale('en');

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<T> load(Locale locale) =>
      inner.load(inner.isSupported(locale) ? locale : _fallback);

  @override
  bool shouldReload(covariant _EnglishFallbackDelegate<T> old) =>
      inner.shouldReload(old.inner);

  /// The lookup key `Localizations.of` uses; it has to stay the wrapped
  /// delegate's, or the package would not find its own copy.
  @override
  Type get type => inner.type;

  @override
  String toString() => '$inner (English fallback)';
}
