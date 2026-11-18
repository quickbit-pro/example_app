import 'package:flutter/widgets.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';
// The package exposes the delegate through PhoneFieldLocalization, but keeps
// its localization type internal. This adapter supplies its missing locales.
// ignore: implementation_imports
import 'package:phone_form_field/src/localization/generated/phone_field_localization_impl.dart';
// ignore: implementation_imports
import 'package:phone_form_field/src/localization/generated/phone_field_localization_impl_en.dart';

import 'app_localizations.dart';

part 'country_names.dart';

class AppPhoneLocalizationsDelegate
    extends LocalizationsDelegate<PhoneFieldLocalizationImpl> {
  const AppPhoneLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<PhoneFieldLocalizationImpl> load(Locale locale) async {
    if (PhoneFieldLocalizationImpl.delegate.isSupported(locale)) {
      return PhoneFieldLocalizationImpl.delegate.load(locale);
    }
    return _AppPhoneLocalizations(await AppLocalizations.delegate.load(locale));
  }

  @override
  bool shouldReload(AppPhoneLocalizationsDelegate old) => false;
}

class AppCountryLocalizationsDelegate
    extends LocalizationsDelegate<CountrySelectorLocalization> {
  const AppCountryLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLocalizations.delegate.isSupported(locale);

  @override
  Future<CountrySelectorLocalization> load(Locale locale) async {
    if (CountrySelectorLocalization.delegate.isSupported(locale)) {
      return CountrySelectorLocalization.delegate.load(locale);
    }
    return _AppCountryNames(await AppLocalizations.delegate.load(locale),
        _countryNames[locale.languageCode]!);
  }

  @override
  bool shouldReload(AppCountryLocalizationsDelegate old) => false;
}

class _AppPhoneLocalizations extends PhoneFieldLocalizationImplEn {
  _AppPhoneLocalizations(this.app) : super(app.locale.languageCode);
  final AppLocalizations app;

  @override
  String get invalidPhoneNumber => app.translate('Invalid phone number');
  @override
  String get invalidCountry => app.translate('Invalid country');
  @override
  String get invalidMobilePhoneNumber =>
      app.translate('Invalid mobile phone number');
  @override
  String get invalidFixedLinePhoneNumber =>
      app.translate('Invalid fixed line phone number');
  @override
  String get requiredPhoneNumber => app.translate('Phone number is required');
  @override
  String get phoneNumber => app.translate('Phone number');
  @override
  String selectACountrySemanticLabel(String countryName, String dialCode) =>
      app.translate('Select a country. Current selection: {p0} {p1}',
          {'p0': countryName, 'p1': dialCode});
  @override
  String currentValueSemanticLabel(String currentValue) =>
      app.translate('Current value: {p0}', {'p0': currentValue});
}
