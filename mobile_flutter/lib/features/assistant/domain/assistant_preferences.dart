import '../../../core/l10n/message_format.dart';
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
  String Function(String, [Map<String, Object?>]) translate = formatAppMessage,
  AssistantPreferences preferences = const AssistantPreferences(),
}) {
  // The screen supplies its visible departure; an explicit clear stays clear.
  final nearby = departure == null
      ? translate('near me')
      : translate('near {p0}', {'p0': departure.city});
  String flightFrom(String withoutOrigin, String withOrigin) =>
      departure == null
          ? translate(withoutOrigin)
          : translate(withOrigin, {'p0': departure.city});
  final style = preferences.style;
  final flight = switch (style) {
    AssistantTravelStyle.value => flightFrom(
        'Compare low-cost flights for a short break.',
        'Compare low-cost flights from {p0} for a short break.'),
    AssistantTravelStyle.balanced => flightFrom(
        'Compare flights for a long weekend, balancing price and flight times.',
        'Compare flights from {p0} for a long weekend, balancing price and flight times.'),
    AssistantTravelStyle.comfort => flightFrom(
        'Find convenient flights for a relaxed weekend, prioritising nonstop options.',
        'Find convenient flights from {p0} for a relaxed weekend, prioritising nonstop options.'),
    AssistantTravelStyle.premium => flightFrom(
        'Compare convenient flights for a special getaway, including premium and good-value options.',
        'Compare convenient flights from {p0} for a special getaway, including premium and good-value options.'),
  };
  final hotel = switch (style) {
    AssistantTravelStyle.value => translate(
        'Find a good-value hotel {p0} for a weekend stay, with free cancellation.',
        {'p0': nearby}),
    AssistantTravelStyle.balanced => translate(
        'Find a quiet hotel {p0} for a weekend stay, balancing comfort and price.',
        {'p0': nearby}),
    AssistantTravelStyle.comfort => translate(
        'Find a quiet spa hotel {p0} for a relaxing weekend, with flexible cancellation.',
        {'p0': nearby}),
    AssistantTravelStyle.premium => translate(
        'Compare boutique and luxury spa hotels {p0} for a special weekend, including a good-value alternative.',
        {'p0': nearby}),
  };
  final escape = switch (style) {
    AssistantTravelStyle.value => flightFrom(
        'Plan an affordable two-night escape for two, including transport and a hotel.',
        'Plan an affordable two-night escape from {p0} for two, including transport and a hotel.'),
    AssistantTravelStyle.balanced => flightFrom(
        'Plan a three-night escape for two, comparing the total cost of transport and a hotel.',
        'Plan a three-night escape from {p0} for two, comparing the total cost of transport and a hotel.'),
    AssistantTravelStyle.comfort => flightFrom(
        'Plan a relaxing three-night escape for two, with convenient travel and a comfortable hotel.',
        'Plan a relaxing three-night escape from {p0} for two, with convenient travel and a comfortable hotel.'),
    AssistantTravelStyle.premium => flightFrom(
        'Plan a special three-night escape for two, with a memorable stay and convenient travel.',
        'Plan a special three-night escape from {p0} for two, with a memorable stay and convenient travel.'),
  };
  final dinner = switch (style) {
    AssistantTravelStyle.value => translate(
        'Find a good-value dinner and a free or low-cost activity {p0} for two.',
        {'p0': nearby}),
    AssistantTravelStyle.balanced => translate(
        'Plan dinner and a memorable local experience {p0} for two.',
        {'p0': nearby}),
    AssistantTravelStyle.comfort => translate(
        'Plan a relaxed dinner and a special experience {p0} for two.',
        {'p0': nearby}),
    AssistantTravelStyle.premium => translate(
        'Compare a tasting menu and a special evening experience {p0} for two, including a good-value option.',
        {'p0': nearby}),
  };
  return [
    AssistantStarter('Find flights',
        translate('{p0} Ask me for dates and a trip budget.', {'p0': flight})),
    AssistantStarter(
        'Find a hotel',
        translate(
            '{p0} Ask me for dates and a nightly budget.', {'p0': hotel})),
    AssistantStarter(
        'Plan my escape',
        translate(
            '{p0} Ask me for dates and a total trip budget.', {'p0': escape})),
    AssistantStarter(
        'Dinner and experiences',
        translate(
            '{p0} Ask me for the date and an evening budget.', {'p0': dinner})),
  ];
}
