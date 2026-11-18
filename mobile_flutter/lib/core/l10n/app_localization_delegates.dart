import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_localizations.dart';
import 'phone_localizations.dart';

/// App, framework and phone-country picker copy in every supported language.
/// The phone adapters retain package translations and fill its locale gaps.
final appLocalizationsDelegates = <LocalizationsDelegate<dynamic>>[
  AppLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
  const AppPhoneLocalizationsDelegate(),
  const AppCountryLocalizationsDelegate(),
];
