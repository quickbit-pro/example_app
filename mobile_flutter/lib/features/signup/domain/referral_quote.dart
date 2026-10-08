/// Immutable terms shown before referral consent. A successful account signup
/// is distinct from the authoritative referral attribution outcome.
class ReferralQuote {
  const ReferralQuote(
      {required this.quoteId,
      required this.registrationAttemptId,
      required this.termsVersion,
      required this.termsText,
      required this.termsHash,
      required this.policyHash,
      required this.expiresAt,
      this.locale,
      this.eligibilityNotice,
      this.boosts = const []});

  factory ReferralQuote.fromJson(Map<String, dynamic> json) {
    Object? field(String key) =>
        json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
    String text(String key) => '${field(key) ?? ''}';
    final expiresAt = DateTime.tryParse(text('expiresAt'));
    final version = int.tryParse(text('termsVersion'));
    if (text('quoteId').isEmpty ||
        text('registrationAttemptId').isEmpty ||
        text('termsHash').isEmpty ||
        text('policyHash').isEmpty ||
        expiresAt == null ||
        (field('status') != null && text('status') != 'QUOTED') ||
        version == null) {
      throw const FormatException('Referral offer could not be verified');
    }
    return ReferralQuote(
        quoteId: text('quoteId'),
        registrationAttemptId: text('registrationAttemptId'),
        termsVersion: version,
        termsText: text('termsText'),
        termsHash: text('termsHash'),
        policyHash: text('policyHash'),
        expiresAt: expiresAt,
        locale: field('locale')?.toString(),
        eligibilityNotice: field('eligibilityNotice')?.toString(),
        boosts: [
          if (field('boosts') is List)
            for (final boost in field('boosts') as List)
              if (boost is Map)
                ReferralQuotedBoost.fromJson(Map<String, dynamic>.from(boost))
        ]);
  }
  final String quoteId;
  final String registrationAttemptId;
  final int termsVersion;
  final String termsText;
  final String termsHash;
  final String policyHash;
  final DateTime expiresAt;
  final String? locale;
  final String? eligibilityNotice;
  final List<ReferralQuotedBoost> boosts;
  bool isExpired(DateTime at) => !at.toUtc().isBefore(expiresAt.toUtc());
}

enum ReferralSignupState {
  applied,
  pending,
  needsReview,
  rejected,
  unavailable
}

class ReferralSignupOutcome {
  const ReferralSignupOutcome(this.state, {this.correlationId});
  factory ReferralSignupOutcome.fromJson(Map<String, dynamic> json) {
    final status =
        '${json['referralAttributionStatus'] ?? json['ReferralAttributionStatus'] ?? ''}'
            .toUpperCase();
    return ReferralSignupOutcome(
        switch (status) {
          'APPLIED' || 'COMMITTED' => ReferralSignupState.applied,
          'PENDING' => ReferralSignupState.pending,
          'NEEDS_REVIEW' => ReferralSignupState.needsReview,
          'REJECTED' => ReferralSignupState.rejected,
          _ => ReferralSignupState.unavailable,
        },
        correlationId: (json['referralCommandId'] ??
                json['ReferralCommandId'] ??
                json['registrationAttemptId'] ??
                json['RegistrationAttemptId'])
            ?.toString());
  }
  final ReferralSignupState state;
  final String? correlationId;
  String get label => switch (state) {
        ReferralSignupState.applied => 'Your referral is confirmed.',
        ReferralSignupState.pending =>
          'Your account is created. Your referral is awaiting confirmation.',
        ReferralSignupState.needsReview =>
          'Your account is created. Your referral needs review.',
        ReferralSignupState.rejected =>
          'Your account is created. The referral was not applied.',
        ReferralSignupState.unavailable =>
          'Your account is created. Referral confirmation is unavailable.',
      };
}

class ReferralQuotedBoost {
  const ReferralQuotedBoost(
      {required this.name,
      required this.kind,
      required this.startsAt,
      required this.endsAt,
      required this.currency,
      required this.maximumIncrementalReward,
      this.multiplier,
      this.qualifiedFriendCount,
      this.milestoneAmount});
  factory ReferralQuotedBoost.fromJson(Map<String, dynamic> json) {
    Object? field(String key) =>
        json[key] ?? json['${key[0].toUpperCase()}${key.substring(1)}'];
    double? number(String key) => double.tryParse('${field(key)}');
    final start = DateTime.tryParse('${field('startsAt')}');
    final end = DateTime.tryParse('${field('endsAt')}');
    final maximum = number('maximumIncrementalReward');
    final kind = '${field('kind') ?? ''}';
    final multiplier = number('multiplier');
    final count = number('qualifiedFriendCount')?.toInt();
    final amount = number('milestoneAmount');
    if (start == null ||
        end == null ||
        maximum == null ||
        field('currency') == null ||
        (kind == 'MULTIPLIER' && multiplier == null) ||
        (kind == 'MILESTONE' && (count == null || amount == null)) ||
        (kind != 'MULTIPLIER' && kind != 'MILESTONE')) {
      throw const FormatException('Referral boost terms are incomplete');
    }
    return ReferralQuotedBoost(
        name: '${field('name') ?? ''}',
        kind: kind,
        startsAt: start,
        endsAt: end,
        currency: '${field('currency')}',
        maximumIncrementalReward: maximum,
        multiplier: multiplier,
        qualifiedFriendCount: count,
        milestoneAmount: amount);
  }
  final String name;
  final String kind;
  final DateTime startsAt;
  final DateTime endsAt;
  final String currency;
  final double maximumIncrementalReward;
  final double? multiplier;
  final int? qualifiedFriendCount;
  final double? milestoneAmount;
}

/// Only explicit facade rejections before account creation release the frozen
/// signup attempt. Transport failures and unknown provider results never do.
bool canRestartReferralSignup(String? code) => const {
      'auth.signup_required_fields',
      'auth.password.weak',
      'auth.signup.business_disabled',
      'auth.referral.required',
      'auth.referral.disabled',
      'auth.referral.invalid',
      'auth.referral.validation_failed',
    }.contains(code);
