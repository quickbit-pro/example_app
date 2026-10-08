/// The only location context that may leave the device for Ask AI.
/// Coordinates, home addresses and profile details deliberately do not belong
/// to this model. It is session-local and always visible/editable before Send.
class AssistantDeparture {
  const AssistantDeparture({
    required this.city,
    this.countryCode,
    this.airportCode,
  });

  final String city;
  final String? countryCode;
  final String? airportCode;

  String get displayLabel => [
        airportCode == null ? city : '$city ($airportCode)',
        if (countryCode != null) countryCode,
      ].join(', ');

  Map<String, String> toJson() => {
        'city': city,
        if (countryCode != null) 'countryCode': countryCode!,
        if (airportCode != null) 'airportCode': airportCode!,
      };
}

/// Single-line city/airport labels only, matching the server's Unicode policy.
/// Detailed addresses and instructions belong neither here nor in location
/// context. The server independently validates every field.
bool isValidAssistantDepartureCity(String value) {
  if (value.trim().isEmpty ||
      value.length > 100 ||
      !RegExp(r'\p{L}', unicode: true).hasMatch(value)) {
    return false;
  }
  return RegExp(r"^[\p{L}\p{M}\p{N} .,'’()\-]+$", unicode: true)
      .hasMatch(value);
}
