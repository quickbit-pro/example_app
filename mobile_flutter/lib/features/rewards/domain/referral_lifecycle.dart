import 'rewards_models.dart';

Object? _value(Map<String, dynamic> json, String key) =>
    json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const {};
DateTime? _date(Object? value) => DateTime.tryParse('$value');
int _integer(Object? value) => int.tryParse('$value') ?? 0;
ReferralLevel? _level(Object? value) =>
    value is Map ? ReferralLevel.fromJson(_map(value)) : null;

/// A server observation of the invitation offer. A forecast is conditional,
/// never a change to the terms accepted by an existing referred friend.
class ReferralLevelLifecycle {
  const ReferralLevelLifecycle({
    required this.programId,
    required this.asOf,
    this.observedAt,
    this.currentLevel,
    this.assigned = false,
    this.progress = const ReferralProgress(),
    this.forecast,
    this.protectedRelationshipCount = 0,
    this.existingOffersProtected = false,
    this.forecastAssumption = '',
  });

  factory ReferralLevelLifecycle.fromJson(Map<String, dynamic> json) {
    final asOf = _date(_value(json, 'asOf'));
    if (asOf == null) {
      throw const FormatException('Missing level observation time');
    }
    return ReferralLevelLifecycle(
      programId: '${_value(json, 'programId') ?? ''}',
      asOf: asOf,
      observedAt: _date(_value(json, 'observedAt')),
      currentLevel: _level(_value(json, 'currentLevel')),
      assigned: _value(json, 'assigned') == true,
      progress: ReferralProgress.fromJson(_map(_value(json, 'progress'))),
      forecast: _value(json, 'forecast') is Map
          ? ReferralLevelForecast.fromJson(_map(_value(json, 'forecast')))
          : null,
      protectedRelationshipCount:
          _integer(_value(json, 'protectedRelationshipCount')),
      existingOffersProtected: _value(json, 'existingOffersProtected') == true,
      forecastAssumption: '${_value(json, 'forecastAssumption') ?? ''}',
    );
  }

  final String programId;
  final DateTime asOf;
  final DateTime? observedAt;
  final ReferralLevel? currentLevel;
  final bool assigned;
  final ReferralProgress progress;
  final ReferralLevelForecast? forecast;
  final int protectedRelationshipCount;
  final bool existingOffersProtected;
  final String forecastAssumption;
}

class ReferralLevelForecast {
  const ReferralLevelForecast(
      {required this.effectiveAt,
      required this.daysUntil,
      this.level,
      this.assigned = false,
      this.reason = ''});
  factory ReferralLevelForecast.fromJson(Map<String, dynamic> json) {
    final at = _date(_value(json, 'effectiveAt'));
    if (at == null) throw const FormatException('Missing forecast time');
    return ReferralLevelForecast(
        effectiveAt: at,
        daysUntil: _integer(_value(json, 'daysUntil')),
        level: _level(_value(json, 'level')),
        assigned: _value(json, 'assigned') == true,
        reason: '${_value(json, 'reason') ?? ''}');
  }
  final DateTime effectiveAt;
  final int daysUntil;
  final ReferralLevel? level;
  final bool assigned;
  final String reason;
}

class ReferralLevelChange {
  const ReferralLevelChange(
      {required this.id,
      required this.effectiveAt,
      required this.observedAt,
      required this.kind,
      this.previousLevel,
      this.currentLevel,
      this.effectiveTimeBasis = ''});
  factory ReferralLevelChange.fromJson(Map<String, dynamic> json) {
    final at = _date(_value(json, 'effectiveAt'));
    final observed = _date(_value(json, 'observedAt'));
    if (at == null || observed == null) {
      throw const FormatException('Missing level change time');
    }
    return ReferralLevelChange(
        id: '${_value(json, 'id') ?? ''}',
        effectiveAt: at,
        observedAt: observed,
        kind: '${_value(json, 'kind') ?? ''}',
        previousLevel: _level(_value(json, 'previousLevel')),
        currentLevel: _level(_value(json, 'currentLevel')),
        effectiveTimeBasis: '${_value(json, 'effectiveTimeBasis') ?? ''}');
  }
  final String id;
  final DateTime effectiveAt;
  final DateTime observedAt;
  final String kind;
  final ReferralLevel? previousLevel;
  final ReferralLevel? currentLevel;
  final String effectiveTimeBasis;
}

class ReferralLevelHistory {
  const ReferralLevelHistory(
      {this.items = const [], this.page = 1, this.hasMore = false});
  factory ReferralLevelHistory.fromJson(Map<String, dynamic> json) =>
      ReferralLevelHistory(
          items: [
            if (_value(json, 'items') is List)
              for (final row in _value(json, 'items') as List)
                if (row is Map) ReferralLevelChange.fromJson(_map(row))
          ],
          page: _integer(_value(json, 'page')),
          hasMore: _value(json, 'hasMore') == true);
  final List<ReferralLevelChange> items;
  final int page;
  final bool hasMore;
}
