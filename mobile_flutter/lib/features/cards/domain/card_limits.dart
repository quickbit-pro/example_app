/// One period's limit: what the customer set (if anything) and the tier
/// ceiling it may not exceed.
class CardLimitPeriod {
  const CardLimitPeriod(
      {required this.key, required this.label, this.current, this.cap});

  final String key;
  final String label;
  final double? current;
  final double? cap;

  bool get hasCap => cap != null && cap! > 0;
}

/// Spending limits for one card: current values as last set through the
/// app plus the ceilings from the customer's tier.
class CardLimitsInfo {
  const CardLimitsInfo({
    required this.currency,
    required this.canUpdate,
    required this.capSource,
    this.daily,
    this.weekly,
    this.monthly,
    this.capDaily,
    this.capWeekly,
    this.capMonthly,
    this.updatedAt,
    this.tierName,
  });

  factory CardLimitsInfo.fromJson(Map<String, dynamic> json) {
    final current = _map(json['current'] ?? json['Current']);
    final caps = _map(json['caps'] ?? json['Caps']);
    return CardLimitsInfo(
      currency: (json['currency'] ?? json['Currency'] ?? 'USD')
          .toString()
          .toUpperCase(),
      canUpdate: json['canUpdate'] != false && json['CanUpdate'] != false,
      capSource: (json['capSource'] ?? json['CapSource'] ?? 'none').toString(),
      daily: _double(current, 'daily'),
      weekly: _double(current, 'weekly'),
      monthly: _double(current, 'monthly'),
      capDaily: _double(caps, 'daily'),
      capWeekly: _double(caps, 'weekly'),
      capMonthly: _double(caps, 'monthly'),
      updatedAt: DateTime.tryParse(
          (current['updatedAt'] ?? current['UpdatedAt'] ?? '').toString()),
      tierName: (json['tierName'] ?? json['TierName'])?.toString(),
    );
  }

  final String currency;
  final bool canUpdate;
  final String capSource;
  final double? daily;
  final double? weekly;
  final double? monthly;
  final double? capDaily;
  final double? capWeekly;
  final double? capMonthly;
  final DateTime? updatedAt;
  final String? tierName;

  bool get hasCurrent => daily != null || weekly != null || monthly != null;

  bool get hasCaps =>
      capDaily != null || capWeekly != null || capMonthly != null;

  List<CardLimitPeriod> get periods => [
        CardLimitPeriod(
            key: 'daily', label: 'Daily', current: daily, cap: capDaily),
        CardLimitPeriod(
            key: 'weekly', label: 'Weekly', current: weekly, cap: capWeekly),
        CardLimitPeriod(
            key: 'monthly',
            label: 'Monthly',
            current: monthly,
            cap: capMonthly),
      ];

  static Map<String, dynamic> _map(Object? value) => value is Map
      ? value.map((key, item) => MapEntry(key.toString(), item))
      : const {};

  static double? _double(Map<String, dynamic> json, String key) {
    final value =
        json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}
