class ReferralGeoStatus {
  const ReferralGeoStatus(
      {required this.attributed,
      required this.status,
      this.canQualify,
      this.canPayout,
      this.pendingExpiresAt,
      this.acceptedTerms,
      this.acceptedLocale,
      this.acceptedVersion,
      this.acceptedHash,
      this.acceptedAt});
  factory ReferralGeoStatus.fromJson(Map<String, dynamic> json) {
    Object? field(Map map, String key) =>
        map[key] ?? map['${key[0].toUpperCase()}${key.substring(1)}'];
    final eligibility = field(json, 'eligibility');
    if (eligibility is! Map || field(eligibility, 'status') == null) {
      throw const FormatException('Referral eligibility was not provided');
    }
    final terms = field(json, 'acceptedTerms');
    return ReferralGeoStatus(
        attributed: field(json, 'attributed') == true,
        status: '${field(eligibility, 'status')}',
        canQualify: field(eligibility, 'canQualify') as bool?,
        canPayout: field(eligibility, 'canPayout') as bool?,
        pendingExpiresAt:
            DateTime.tryParse('${field(eligibility, 'pendingExpiresAt')}'),
        acceptedTerms: terms is Map ? field(terms, 'text')?.toString() : null,
        acceptedLocale:
            terms is Map ? field(terms, 'locale')?.toString() : null,
        acceptedVersion: terms is Map
            ? int.tryParse('${field(terms, 'termsVersion')}')
            : null,
        acceptedHash:
            terms is Map ? field(terms, 'contentHash')?.toString() : null,
        acceptedAt: terms is Map
            ? DateTime.tryParse('${field(terms, 'acceptedAt')}')
            : null);
  }
  final bool attributed;
  final String status;
  final bool? canQualify;
  final bool? canPayout;
  final DateTime? pendingExpiresAt;
  final String? acceptedTerms;
  final String? acceptedLocale;
  final int? acceptedVersion;
  final String? acceptedHash;
  final DateTime? acceptedAt;
  String get label => switch (status.toUpperCase()) {
        'ELIGIBLE' => 'Your referral country eligibility is confirmed.',
        'PENDING' => 'Referral eligibility is pending identity verification.',
        'EXPIRED' => 'The referral eligibility verification period has ended.',
        'INELIGIBLE' =>
          'This referral offer is unavailable in your verified country.',
        'NOT_ATTRIBUTED' => 'No referral has been attributed to your account.',
        _ => 'Referral eligibility is unavailable.',
      };
}
