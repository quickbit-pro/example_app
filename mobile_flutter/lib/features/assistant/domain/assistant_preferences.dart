import 'assistant_departure.dart';

/// Only coarse onboarding context reaches the app. The financial band stays
/// here: starter prompts contain a travel style, never KYC/financial values.
class AssistantPreferences {
  const AssistantPreferences({this.city, this.countryCode, this.monthlyVolume});

  factory AssistantPreferences.fromJson(Map<String, dynamic> json) {
    final city = json['city'];
    final country = json['countryCode'];
    final volume = json['expectedMonthlyVolume'];
    return AssistantPreferences(
      city: city is String && isValidAssistantDepartureCity(city.trim())
          ? city.trim()
          : null,
      countryCode: country is String && RegExp(r'^[A-Z]{2}$').hasMatch(country)
          ? country
          : null,
      monthlyVolume: volume is String && monthlyVolumeBands.contains(volume)
          ? volume
          : null,
    );
  }

  static const monthlyVolumeBands = {
    '0-1000',
    '1001-5000',
    '5001-15000',
    '15001-50000',
    '50001-100000',
    '100001+',
  };

  final String? city;
  final String? countryCode;
  final String? monthlyVolume;

  AssistantDeparture? get departure => city == null
      ? null
      : AssistantDeparture(city: city!, countryCode: countryCode);

  AssistantTravelStyle get style => switch (monthlyVolume) {
        '0-1000' => AssistantTravelStyle.value,
        '1001-5000' => AssistantTravelStyle.balanced,
        '5001-15000' => AssistantTravelStyle.comfort,
        '15001-50000' ||
        '50001-100000' ||
        '100001+' =>
          AssistantTravelStyle.premium,
        _ => AssistantTravelStyle.balanced,
      };
}

enum AssistantTravelStyle { value, balanced, comfort, premium }

class AssistantStarter {
  const AssistantStarter(this.title, this.prompt);
  final String title;
  final String prompt;
}

String assistantTravelStyleLabel(AssistantTravelStyle style) => switch (style) {
      AssistantTravelStyle.value => 'Value-focused ideas',
      AssistantTravelStyle.balanced => 'Everyday escapes',
      AssistantTravelStyle.comfort => 'Comfort and convenience',
      AssistantTravelStyle.premium => 'Special stays and experiences',
    };

/// Monthly account volume is a light starting point, not disposable income or
/// a travel budget. Every prompt asks the user for a separate budget and dates.
List<AssistantStarter> assistantStarters({
  AssistantDeparture? departure,
  AssistantPreferences preferences = const AssistantPreferences(),
}) {
  // The screen supplies its visible departure; an explicit clear stays clear.
  final origin = departure == null ? '' : ' from ${departure.city}';
  final nearby = departure == null ? 'near me' : 'near ${departure.city}';
  final style = preferences.style;
  final flight = switch (style) {
    AssistantTravelStyle.value =>
      'Compare low-cost flights$origin for a short break.',
    AssistantTravelStyle.balanced =>
      'Compare flights$origin for a long weekend, balancing price and flight times.',
    AssistantTravelStyle.comfort =>
      'Find convenient flights$origin for a relaxed weekend, prioritising nonstop options.',
    AssistantTravelStyle.premium =>
      'Compare convenient flights$origin for a special getaway, including premium and good-value options.',
  };
  final hotel = switch (style) {
    AssistantTravelStyle.value =>
      'Find a good-value hotel $nearby for a weekend stay, with free cancellation.',
    AssistantTravelStyle.balanced =>
      'Find a quiet hotel $nearby for a weekend stay, balancing comfort and price.',
    AssistantTravelStyle.comfort =>
      'Find a quiet spa hotel $nearby for a relaxing weekend, with flexible cancellation.',
    AssistantTravelStyle.premium =>
      'Compare boutique and luxury spa hotels $nearby for a special weekend, including a good-value alternative.',
  };
  final escape = switch (style) {
    AssistantTravelStyle.value =>
      'Plan an affordable two-night escape$origin for two, including transport and a hotel.',
    AssistantTravelStyle.balanced =>
      'Plan a three-night escape$origin for two, comparing the total cost of transport and a hotel.',
    AssistantTravelStyle.comfort =>
      'Plan a relaxing three-night escape$origin for two, with convenient travel and a comfortable hotel.',
    AssistantTravelStyle.premium =>
      'Plan a special three-night escape$origin for two, with a memorable stay and convenient travel.',
  };
  final dinner = switch (style) {
    AssistantTravelStyle.value =>
      'Find a good-value dinner and a free or low-cost activity $nearby for two.',
    AssistantTravelStyle.balanced =>
      'Plan dinner and a memorable local experience $nearby for two.',
    AssistantTravelStyle.comfort =>
      'Plan a relaxed dinner and a special experience $nearby for two.',
    AssistantTravelStyle.premium =>
      'Compare a tasting menu and a special evening experience $nearby for two, including a good-value option.',
  };
  return [
    AssistantStarter(
        'Find flights', '$flight Ask me for dates and a trip budget.'),
    AssistantStarter(
        'Find a hotel', '$hotel Ask me for dates and a nightly budget.'),
    AssistantStarter(
        'Plan my escape', '$escape Ask me for dates and a total trip budget.'),
    AssistantStarter('Dinner and experiences',
        '$dinner Ask me for the date and an evening budget.'),
  ];
}
