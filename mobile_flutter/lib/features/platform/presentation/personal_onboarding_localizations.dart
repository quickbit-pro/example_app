import 'package:flutter/widgets.dart';
import 'package:flutter_country_selector/flutter_country_selector.dart';

import '../../../core/l10n/app_localizations.dart';

/// Labels are translated only for display; submitted options retain provider enums.
String personalOnboardingOptionLabel(BuildContext context, String value) {
  const labels = <String, String>{
    'SALARY_OR_INCOME': 'Salary or income',
    'PERSONAL_TRANSFERS_OR_LIVING_EXPENSES':
        'Personal transfers or living expenses',
    'FAMILY_SUPPORT': 'Family support',
    'MORTGAGE_OR_RENT_OR_UTILITY_BILLS': 'Mortgage, rent or utility bills',
    'SAVINGS': 'Savings',
    'INVESTMENT_PURPOSES': 'Investments',
    'INVESTMENT_OR_TRADING_IN_CRYPTOCURRENCIES':
        'Investment Or Trading In Cryptocurrencies',
    'RECEIVING_OR_SENDING_LOAN_PAYMENTS': 'Receiving or sending loan payments',
    'PURCHASE_OF_GOODS_OR_SERVICES': 'Purchases of goods or services',
    'TRAVEL': 'Travel',
    'EDUCATION': 'Education',
    'MEDICAL_EXPENSES': 'Medical expenses',
    'CHARITABLE_DONATIONS': 'Charitable donations',
    'RECEIVING_FUNDS_FROM_OWN_ACCOUNTS': 'Receiving Funds From Own Accounts',
    'RECEIVING_SALARY_PENSION_OR_DIVIDENDS': 'Salary, pension or dividends',
    'RECEIVING_GIFTS_OR_INHERITANCES': 'Gifts or inheritances',
    'PROCEEDS_FROM_INVESTMENTS': 'Proceeds from investments',
    'PROCEEDS_FROM_CRYPTOCURRENCY_SALES_OR_TRADING':
        'Proceeds From Cryptocurrency Sales Or Trading',
    'PROCEEDS_FROM_SALE_OF_A_PROPERTY_OR_PHYSICAL_ASSET':
        'Proceeds from selling property or physical assets',
    'OTHER': 'Other',
    'FEWER-THAN-5': 'Fewer than 5 payments',
    'MORE-THAN-20': 'More than 20 payments',
  };
  final label = labels[value];
  return label == null ? value : context.tr(label);
}

/// Country names are display-only; the provider receives the original ISO code.
String personalOnboardingCountryLabel(BuildContext context, String code) {
  final countries = IsoCode.values.where((item) => item.name == code);
  // Territories without a telephone calling code are absent from the phone selector.
  const territories = {
    'AQ': 'Antarctica',
    'BV': 'Bouvet Island',
    'GS': 'South Georgia and the South Sandwich Islands',
    'HM': 'Heard Island and McDonald Islands',
    'PN': 'Pitcairn Islands',
    'TF': 'French Southern Territories',
    'UM': 'United States Minor Outlying Islands',
  };
  if (countries.isEmpty) return context.tr(territories[code] ?? code);
  final localization = CountrySelectorLocalization.of(context) ??
      CountrySelectorLocalizationEn();
  return localization.countryName(countries.first);
}
