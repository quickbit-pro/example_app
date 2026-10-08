dynamic _value(Map<String, dynamic> json, String key) =>
    json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
Map<String, dynamic> _object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

class ReferralCommunity {
  const ReferralCommunity(
      {required this.enabled,
      required this.currency,
      required this.plan,
      required this.l2Percent,
      required this.l3Percent,
      required this.status,
      required this.enabledAt,
      required this.generations});
  factory ReferralCommunity.fromJson(Map<String, dynamic> json) {
    final member = _object(_value(json, 'membership'));
    final rows = _value(json, 'generations');
    return ReferralCommunity(
        enabled: _value(json, 'enabled') == true,
        currency: '${_value(json, 'currency') ?? 'USD'}',
        plan: '${_value(member, 'plan') ?? ''}',
        l2Percent: _number(_value(member, 'l2Bps')) / 100,
        l3Percent: _number(_value(member, 'l3Bps')) / 100,
        status: '${_value(member, 'status') ?? ''}',
        enabledAt: DateTime.tryParse('${_value(member, 'enabledAt')}'),
        generations: rows is List
            ? rows
                .map((x) => ReferralCommunityGeneration.fromJson(_object(x)))
                .toList()
            : const []);
  }
  final bool enabled;
  final String currency, plan, status;
  final double l2Percent, l3Percent;
  final DateTime? enabledAt;
  final List<ReferralCommunityGeneration> generations;
}

class ReferralCommunityGeneration {
  const ReferralCommunityGeneration(
      {required this.depth,
      required this.descendants,
      required this.qualified,
      required this.earning,
      required this.accrued,
      required this.cashPaid,
      required this.outstanding});
  factory ReferralCommunityGeneration.fromJson(Map<String, dynamic> json) =>
      ReferralCommunityGeneration(
          depth: _number(_value(json, 'depth')).toInt(),
          descendants: _number(_value(json, 'descendants')).toInt(),
          qualified: _number(_value(json, 'qualified')).toInt(),
          earning: _number(_value(json, 'earning')).toInt(),
          accrued: _number(_value(json, 'accrued')),
          cashPaid: _number(_value(json, 'cashPaid')),
          outstanding: _number(_value(json, 'outstanding')));
  final int depth, descendants, qualified, earning;
  final double accrued, cashPaid, outstanding;
}

class ReferralCommunityEarning {
  const ReferralCommunityEarning(
      {required this.id,
      required this.depth,
      required this.friendAlias,
      required this.amount,
      required this.cashPaid,
      required this.outstanding,
      required this.status,
      required this.requestedRate,
      required this.appliedRate,
      required this.reductionReason,
      required this.occurredAt});
  factory ReferralCommunityEarning.fromJson(Map<String, dynamic> json) =>
      ReferralCommunityEarning(
          id: '${_value(json, 'id') ?? ''}',
          depth: _number(_value(json, 'depth')).toInt(),
          friendAlias: '${_value(json, 'friendAlias') ?? ''}',
          amount: _number(_value(json, 'amount')),
          cashPaid: _number(_value(json, 'cashPaid')),
          outstanding: _number(_value(json, 'outstanding')),
          status: '${_value(json, 'status') ?? ''}',
          requestedRate: _number(_value(json, 'requestedRate')),
          appliedRate: _number(_value(json, 'appliedRate')),
          reductionReason: _value(json, 'reductionReason')?.toString(),
          occurredAt: DateTime.tryParse('${_value(json, 'occurredAt')}'));
  final String id, friendAlias, status;
  final int depth;
  final double amount, cashPaid, outstanding, requestedRate, appliedRate;
  final String? reductionReason;
  final DateTime? occurredAt;
}
