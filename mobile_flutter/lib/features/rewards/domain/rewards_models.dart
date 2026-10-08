import '../../../core/models/banking_models.dart';

class MobileTenantConfig {
  const MobileTenantConfig({
    required this.companyName,
    required this.brandName,
    required this.referralsEnabled,
    required this.referralRegistrationMode,
    required this.vouchersEnabled,
    required this.existingAccountClaimEnabled,
    required this.boomFiExchangeEnabled,
    required this.walletOutflowsEnabled,
    required this.equalsMoneyEnabled,
    this.businessOnboardingEnabled = true,
    this.supportEmail,
    this.termsUrl,
    this.privacyUrl,
    this.equalsRegulatoryDisclaimerEu,
    this.equalsRegulatoryDisclaimerUk,
    this.equalsRegulatoryRegionDefault = 'EU',
    this.eSignUrl,
    this.eCommunicationNoticeUrl,
    this.generalTermsUrl,
    this.generalTermsUsUrl,
    this.additionalAcknowledgementsUrl,
    this.equalsGeneralTermsUrl,
  });

  factory MobileTenantConfig.fromJson(Map<String, dynamic> json) {
    final company = _map(json['company']);
    final features = _map(json['features']);
    return MobileTenantConfig(
      companyName: _text(company['name']) ?? 'Your company',
      brandName: _text(company['brandName']) ??
          _text(company['name']) ??
          'Your company',
      referralsEnabled: _bool(features['referralsEnabled']),
      referralRegistrationMode:
          _text(features['referralRegistrationMode']) ?? 'disabled',
      vouchersEnabled: _bool(features['vouchersEnabled']),
      existingAccountClaimEnabled:
          _bool(features['existingAccountClaimEnabled']),
      boomFiExchangeEnabled: _bool(features['boomFiExchangeEnabled']),
      walletOutflowsEnabled: _bool(features['walletOutflowsEnabled']),
      equalsMoneyEnabled: _bool(features['equalsMoneyEnabled'], fallback: true),
      businessOnboardingEnabled:
          _bool(features['businessOnboardingEnabled'], fallback: true),
      supportEmail: _text(company['supportEmail']),
      termsUrl: _text(company['termsUrl']),
      privacyUrl: _text(company['privacyUrl']),
      equalsRegulatoryDisclaimerEu:
          _text(company['equalsRegulatoryDisclaimerEu']),
      equalsRegulatoryDisclaimerUk:
          _text(company['equalsRegulatoryDisclaimerUk']),
      equalsRegulatoryRegionDefault:
          _text(company['equalsRegulatoryRegionDefault']) ?? 'EU',
      eSignUrl: _text(company['eSignUrl']),
      eCommunicationNoticeUrl: _text(company['eCommunicationNoticeUrl']),
      generalTermsUrl: _text(company['generalTermsUrl']) ??
          _text(company['interlaceGeneralTermsUrl']),
      generalTermsUsUrl: _text(company['generalTermsUsUrl']) ??
          _text(company['interlaceGeneralTermsUrl2']),
      additionalAcknowledgementsUrl:
          _text(company['additionalAcknowledgementsUrl']),
      equalsGeneralTermsUrl: _text(company['equalsGeneralTermsUrl']),
    );
  }

  final String companyName;
  final String brandName;
  final bool referralsEnabled;
  final String referralRegistrationMode;
  final bool vouchersEnabled;
  final bool existingAccountClaimEnabled;
  final bool boomFiExchangeEnabled;
  final bool walletOutflowsEnabled;
  final bool equalsMoneyEnabled;

  /// False on personal-only installations: the business account type is not
  /// offered at signup and business onboarding routes are unavailable.
  final bool businessOnboardingEnabled;
  final String? supportEmail;
  final String? termsUrl;
  final String? privacyUrl;
  final String? equalsRegulatoryDisclaimerEu;
  final String? equalsRegulatoryDisclaimerUk;
  final String equalsRegulatoryRegionDefault;

  /// Legal metadata from the API. Registration uses the shared programme
  /// PDFs; provider-specific disclosures may add further agreements.
  final String? eSignUrl;
  final String? eCommunicationNoticeUrl;
  final String? generalTermsUrl;
  final String? generalTermsUsUrl;
  final String? additionalAcknowledgementsUrl;
  final String? equalsGeneralTermsUrl;

  bool get referralRequired =>
      referralsEnabled && referralRegistrationMode == 'required';
}

class RewardsSnapshot {
  const RewardsSnapshot({
    required this.config,
    this.referralSummary,
    this.assignedVouchers = const [],
    this.voucherStatus,
    this.referralRewards = const [],
    this.referralFriends = const [],
  });

  final MobileTenantConfig config;
  final Map<String, dynamic>? referralSummary;
  final List<Map<String, dynamic>> assignedVouchers;
  final Map<String, dynamic>? voucherStatus;

  /// The caller's reward ledger (first page), already parsed. Empty when the
  /// backend does not serve the v2 `rewards` resource yet.
  final List<ReferralReward> referralRewards;

  /// The caller's referred friends (first page), already parsed.
  final List<ReferralFriend> referralFriends;

  bool get referralsEnabled => config.referralsEnabled;

  bool get vouchersEnabled => config.vouchersEnabled;

  /// The v2 summary, or null when referrals are off or nothing was served.
  ReferralSummary? get summary => referralSummary == null
      ? null
      : ReferralSummary.fromJson(referralSummary!);

  /// Voucher entry and assigned-voucher sections are only meaningful when the
  /// programme delivers rewards as vouchers. A wallet-credit programme pays
  /// into the customer's balance, so nothing is claimed by hand. A voucher-only
  /// tenant (referrals off) keeps its voucher entry.
  bool get showsVoucherSections {
    if (!vouchersEnabled) return false;
    if (!referralsEnabled) return true;
    final parsed = summary;
    return parsed == null || parsed.usesVouchers;
  }
}

// ---------------------------------------------------------------------------
// Referral programme v2 — member-facing shapes. Every parser accepts both the
// camelCase the mobile backend forwards and the PascalCase the platform used
// to emit, and tolerates missing fields so an older backend still renders.
// ---------------------------------------------------------------------------

/// Delivery modes under which rewards become vouchers the member redeems.
const referralVoucherDeliveryModes = {
  'AUTOMATIC_TRANSFER',
  'VOUCHER_PER_COMMISSION',
};

/// Reward ledger stage as shown to the member.
enum ReferralRewardStage {
  pending,
  ready,
  crediting,
  paid,
  failed,
  unknown;

  static ReferralRewardStage fromWire(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'PENDING':
      case 'DELIVERY_PENDING':
        return ReferralRewardStage.pending;
      case 'READY':
      case 'AVAILABLE':
        return ReferralRewardStage.ready;
      case 'CREDITING':
      case 'PROCESSING':
        return ReferralRewardStage.crediting;
      case 'PAID':
        return ReferralRewardStage.paid;
      case 'FAILED':
        return ReferralRewardStage.failed;
      default:
        return ReferralRewardStage.unknown;
    }
  }

  /// English copy for the stage; screens pass it through `context.tr`.
  String get label {
    switch (this) {
      case ReferralRewardStage.pending:
        return 'Pending';
      case ReferralRewardStage.ready:
        return 'Ready';
      case ReferralRewardStage.crediting:
        return 'Crediting';
      case ReferralRewardStage.paid:
        return 'Paid';
      case ReferralRewardStage.failed:
        return 'Failed';
      case ReferralRewardStage.unknown:
        return 'Other';
    }
  }
}

/// Where a referred friend stands on the way to qualification.
enum ReferralFriendStage {
  invited,
  verifying,
  cardIssued,
  qualified,
  windowEnded,
  unknown;

  static ReferralFriendStage fromWire(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'INVITED':
        return ReferralFriendStage.invited;
      case 'VERIFYING':
      // The analytics journey names the stage by its outcome.
      case 'VERIFIED':
        return ReferralFriendStage.verifying;
      case 'CARD_ISSUED':
        return ReferralFriendStage.cardIssued;
      case 'QUALIFIED':
      // Earning is qualified inside the window; the window end is a date.
      case 'EARNING':
        return ReferralFriendStage.qualified;
      case 'WINDOW_ENDED':
        return ReferralFriendStage.windowEnded;
      default:
        return ReferralFriendStage.unknown;
    }
  }

  /// English copy for the stage; screens pass it through `context.tr`.
  String get label {
    switch (this) {
      case ReferralFriendStage.invited:
        return 'Invited';
      case ReferralFriendStage.verifying:
        return 'Verifying';
      case ReferralFriendStage.cardIssued:
        return 'Card issued';
      case ReferralFriendStage.qualified:
        return 'Qualified';
      case ReferralFriendStage.windowEnded:
        return 'Window ended';
      case ReferralFriendStage.unknown:
        return 'In progress';
    }
  }
}

/// The published offer as it applies to this member.
class ReferralOffer {
  const ReferralOffer({
    this.promoCodePolicyEnabled = false,
    this.welcomeAmount = 0,
    this.welcomeCurrency = 'USD',
    this.qualificationCalculationType = 'FIXED',
    this.qualificationRate = 0,
    this.topupCalculationType = 'PERCENT_OF_TOPUP',
    this.topupRate = 0,
    this.earningWindowDays = 0,
    this.earningWindowStart = 'QUALIFICATION',
    this.maxEligibleVolumePerRelationship,
    this.requiresKyc = true,
    this.requiresPaidCard = true,
    this.requiresTopup = true,
    this.minimumTopup,
    this.maximumRecurringReward,
    this.volumeCapSource,
    this.recurringRewardCapSource,
    this.customerRecurringRate = 0,
  });

  factory ReferralOffer.fromJson(Map<String, dynamic> json) {
    return ReferralOffer(
      promoCodePolicyEnabled: _bool(json['promoCodePolicyEnabled'] ?? json['PromoCodePolicyEnabled'], fallback: false),
      welcomeAmount: _num(json, 'welcomeAmount') ?? 0,
      welcomeCurrency: _field(json, 'welcomeCurrency') ?? 'USD',
      qualificationCalculationType:
          _field(json, 'qualificationCalculationType')?.toUpperCase() ??
              'FIXED',
      qualificationRate: _num(json, 'qualificationRate') ?? 0,
      topupCalculationType:
          _field(json, 'topupCalculationType')?.toUpperCase() ??
              'PERCENT_OF_TOPUP',
      topupRate: _num(json, 'topupRate') ?? 0,
      earningWindowDays: _num(json, 'earningWindowDays')?.round() ?? 0,
      earningWindowStart:
          _field(json, 'earningWindowStart')?.toUpperCase() ?? 'QUALIFICATION',
      maxEligibleVolumePerRelationship:
          _num(json, 'maxEligibleVolumePerRelationship'),
      requiresKyc:
          _bool(json['requiresKyc'] ?? json['RequiresKyc'], fallback: true),
      requiresPaidCard: _bool(
          json['requiresPaidCard'] ?? json['RequiresPaidCard'],
          fallback: true),
      requiresTopup:
          _bool(json['requiresTopup'] ?? json['RequiresTopup'], fallback: true),
      minimumTopup: _num(json, 'minimumTopup'),
      maximumRecurringReward: _num(json, 'maximumRecurringReward'),
      volumeCapSource: _field(json, 'volumeCapSource'),
      recurringRewardCapSource: _field(json, 'recurringRewardCapSource'),
      customerRecurringRate: _num(json, 'customerRecurringRate') ?? 0,
    );
  }

  final bool promoCodePolicyEnabled;
  final double welcomeAmount;
  final String welcomeCurrency;
  final String qualificationCalculationType;
  final double qualificationRate;
  final String topupCalculationType;
  final double topupRate;
  final int earningWindowDays;
  final String earningWindowStart;
  final double? maxEligibleVolumePerRelationship;
  final bool requiresKyc;
  final bool requiresPaidCard;
  final bool requiresTopup;
  final double? minimumTopup;
  final double? maximumRecurringReward;
  final String? volumeCapSource;
  final String? recurringRewardCapSource;
  final double customerRecurringRate;

  bool get hasWelcome => welcomeAmount > 0;

  bool get hasQualificationReward => qualificationRate > 0;

  bool get hasTopupReward => topupRate > 0;

  bool get hasReferrerReward => hasQualificationReward || hasTopupReward;
}

/// Published terms and whether this member accepted the current version.
class ReferralTerms {
  const ReferralTerms({
    required this.version,
    this.text,
    this.privacyNotice,
    this.accepted = false,
    this.acceptedVersion,
    this.acceptedAt,
  });

  factory ReferralTerms.fromJson(Map<String, dynamic> json) {
    return ReferralTerms(
      version: _num(json, 'version')?.round() ?? 0,
      text: _field(json, 'text'),
      privacyNotice: _field(json, 'privacyNotice'),
      accepted: _bool(json['accepted'] ?? json['Accepted']),
      acceptedVersion: _num(json, 'acceptedVersion')?.round(),
      acceptedAt: _date(json, 'acceptedAt'),
    );
  }

  final int version;
  final String? text;
  final String? privacyNotice;
  final bool accepted;
  final int? acceptedVersion;
  final DateTime? acceptedAt;

  /// Terms exist to accept only when text was published; a programme with no
  /// text has nothing to gate on.
  bool get published => text != null && text!.trim().isNotEmpty;

  bool get requiresAcceptance => published && !accepted;
}

/// Reward totals for the member, by delivery stage.
class ReferralRewardTotals {
  const ReferralRewardTotals({
    this.pending = 0,
    this.ready = 0,
    this.crediting = 0,
    this.paid = 0,
    this.failed = 0,
    this.currency = 'USD',
  });

  factory ReferralRewardTotals.fromJson(Map<String, dynamic> json) {
    return ReferralRewardTotals(
      pending: _num(json, 'pending') ?? 0,
      ready: _num(json, 'ready') ?? _num(json, 'available') ?? 0,
      crediting: _num(json, 'crediting') ?? 0,
      paid: _num(json, 'paid') ?? 0,
      failed: _num(json, 'failed') ?? 0,
      currency: _field(json, 'currency') ?? 'USD',
    );
  }

  final double pending;
  final double ready;
  final double crediting;
  final double paid;
  final double failed;
  final String currency;

  /// Everything earned that is not lost: what the programme has produced.
  double get earned => pending + ready + crediting + paid;

  /// Earned but not yet in the balance: waiting on the provider, on the
  /// wallet credit, or on a voucher claim.
  double get awaiting => pending + ready + crediting;

  double forStage(ReferralRewardStage stage) {
    switch (stage) {
      case ReferralRewardStage.pending:
        return pending;
      case ReferralRewardStage.ready:
        return ready;
      case ReferralRewardStage.crediting:
        return crediting;
      case ReferralRewardStage.paid:
        return paid;
      case ReferralRewardStage.failed:
        return failed;
      case ReferralRewardStage.unknown:
        return 0;
    }
  }
}

class ReferralCounts {
  const ReferralCounts({
    this.invited = 0,
    this.qualified = 0,
    this.inProgress = 0,
    this.earning = 0,
  });

  factory ReferralCounts.fromJson(Map<String, dynamic> json) {
    return ReferralCounts(
      invited: _num(json, 'invited')?.round() ?? 0,
      qualified: _num(json, 'qualified')?.round() ??
          _num(json, 'successful')?.round() ??
          0,
      inProgress: _num(json, 'inProgress')?.round() ?? 0,
      earning: _num(json, 'earning')?.round() ?? 0,
    );
  }

  final int invited;
  final int qualified;
  final int inProgress;
  final int earning;
}

class ReferralLevel {
  const ReferralLevel({
    this.id,
    this.code = '',
    required this.name,
    this.icon,
    this.color,
    this.displayOrder = 0,
    this.minimumMetricValue = 0,
    this.minimumQualifiedReferrals,
    this.minimumTopupVolume,
    this.qualificationCalculationType = 'FIXED',
    this.qualificationRate = 0,
    this.topupCalculationType = 'PERCENT_OF_TOPUP',
    this.topupRate = 0,
    this.hidden = false,
    this.volumeCapMode = 'INHERIT',
    this.volumeCapAmount,
    this.recurringRewardCapMode = 'INHERIT',
    this.recurringRewardCapAmount,
    this.effectiveVolumeCap,
    this.effectiveRecurringRewardCap,
    this.volumeCapSource,
    this.recurringRewardCapSource,
  });

  factory ReferralLevel.fromJson(Map<String, dynamic> json) {
    final minimumMetricValue = _num(json, 'minimumMetricValue') ?? 0;
    return ReferralLevel(
      id: _field(json, 'id'),
      code: _field(json, 'code') ?? '',
      name: _field(json, 'name') ?? _field(json, 'code') ?? '',
      icon: _field(json, 'icon'),
      color: _field(json, 'color'),
      displayOrder: _num(json, 'displayOrder')?.round() ?? 0,
      minimumMetricValue: minimumMetricValue,
      // A backend that predates the two conditions sends only the single
      // threshold, which counted qualified referrals; a current one keeps
      // that threshold equal to the qualified-referrals condition, so the
      // fallback is exact either way. Zero is "no condition" on both.
      minimumQualifiedReferrals: _positiveCount(
        _num(json, 'minimumQualifiedReferrals') ?? minimumMetricValue,
      ),
      minimumTopupVolume: _positive(_num(json, 'minimumTopupVolume')),
      qualificationCalculationType:
          _field(json, 'qualificationCalculationType')?.toUpperCase() ??
              'FIXED',
      qualificationRate: _num(json, 'qualificationRate') ?? 0,
      topupCalculationType:
          _field(json, 'topupCalculationType')?.toUpperCase() ??
              'PERCENT_OF_TOPUP',
      topupRate: _num(json, 'topupRate') ?? 0,
      hidden: _bool(json['hidden'] ?? json['Hidden']),
      volumeCapMode: _field(json, 'volumeCapMode') ?? 'INHERIT',
      volumeCapAmount: _num(json, 'volumeCapAmount'),
      recurringRewardCapMode:
          _field(json, 'recurringRewardCapMode') ?? 'INHERIT',
      recurringRewardCapAmount: _num(json, 'recurringRewardCapAmount'),
      effectiveVolumeCap: _num(json, 'effectiveVolumeCap'),
      effectiveRecurringRewardCap: _num(json, 'effectiveRecurringRewardCap'),
      volumeCapSource: _field(json, 'volumeCapSource'),
      recurringRewardCapSource: _field(json, 'recurringRewardCapSource'),
    );
  }

  final String? id;
  final String code;
  final String name;
  final String? icon;
  final String? color;
  final int displayOrder;

  /// Deprecated single threshold; equals [minimumQualifiedReferrals] or 0.
  final double minimumMetricValue;

  /// Level conditions. Null is "no condition"; every condition that is set
  /// must be met, so a level with both needs both.
  final int? minimumQualifiedReferrals;
  final double? minimumTopupVolume;
  final String qualificationCalculationType;
  final double qualificationRate;
  final String topupCalculationType;
  final double topupRate;
  final bool hidden;
  final String volumeCapMode;
  final double? volumeCapAmount;
  final String recurringRewardCapMode;
  final double? recurringRewardCapAmount;
  final double? effectiveVolumeCap;
  final double? effectiveRecurringRewardCap;
  final String? volumeCapSource;
  final String? recurringRewardCapSource;

  bool get hasConditions =>
      minimumQualifiedReferrals != null || minimumTopupVolume != null;
}

/// Which of the two level conditions a figure belongs to.
enum ReferralConditionKind { qualifiedReferrals, topupVolume }

/// One condition on the next level, with where the customer stands on it.
class ReferralLevelCondition {
  const ReferralLevelCondition({
    required this.kind,
    required this.current,
    required this.target,
    this.currency = 'USD',
  });

  final ReferralConditionKind kind;
  final double current;
  final double target;

  /// Only meaningful for [ReferralConditionKind.topupVolume].
  final String currency;

  bool get isMoney => kind == ReferralConditionKind.topupVolume;
  bool get met => current >= target;
  double get remaining => met ? 0 : target - current;

  /// Completion in 0..1; a condition without a positive target is met.
  double get fraction =>
      target <= 0 ? 1 : (current / target).clamp(0.0, 1.0).toDouble();
}

class ReferralProgress {
  const ReferralProgress({
    this.basis = '',
    this.currentValue = 0,
    this.nextThreshold,
    this.remaining,
    this.lookbackMonths = 0,
    int? qualifiedReferrals,
    this.topupVolume = 0,
    this.topupVolumeCurrency = 'USD',
    this.nextMinimumQualifiedReferrals,
    this.nextMinimumTopupVolume,
    this.remainingQualifiedReferrals,
    this.remainingTopupVolume,
  }) : qualifiedReferrals = qualifiedReferrals ?? 0;

  /// Tolerant of a backend that only knows the single threshold: there the
  /// threshold counts qualified referrals, and the per-condition fields fall
  /// back to it. A current backend keeps `currentValue`, `nextThreshold` and
  /// `remaining` equal to the qualified-referrals figures, so both spellings
  /// agree.
  factory ReferralProgress.fromJson(Map<String, dynamic> json) {
    final currentValue = _num(json, 'currentValue') ?? 0;
    final nextThreshold = _num(json, 'nextThreshold');
    final remaining = _num(json, 'remaining');
    final qualifiedReferrals =
        _num(json, 'qualifiedReferrals')?.round() ?? currentValue.round();
    final topupVolume = _num(json, 'topupVolume') ?? 0;
    final nextQualified = _positiveCount(
      _num(json, 'nextMinimumQualifiedReferrals') ?? nextThreshold,
    );
    final nextVolume = _positive(_num(json, 'nextMinimumTopupVolume'));
    return ReferralProgress(
      basis: _field(json, 'basis') ?? '',
      currentValue: currentValue,
      nextThreshold: nextThreshold,
      remaining: remaining,
      lookbackMonths: _num(json, 'lookbackMonths')?.round() ?? 0,
      qualifiedReferrals: qualifiedReferrals,
      topupVolume: topupVolume,
      topupVolumeCurrency: _field(json, 'topupVolumeCurrency') ?? 'USD',
      nextMinimumQualifiedReferrals: nextQualified,
      nextMinimumTopupVolume: nextVolume,
      remainingQualifiedReferrals: nextQualified == null
          ? null
          : _num(json, 'remainingQualifiedReferrals')?.round() ??
              remaining?.round() ??
              _floorAtZero((nextQualified - qualifiedReferrals).toDouble())
                  .round(),
      remainingTopupVolume: nextVolume == null
          ? null
          : _num(json, 'remainingTopupVolume') ??
              _floorAtZero(nextVolume - topupVolume),
    );
  }

  /// Always `SUCCESSFUL_REFERRAL_COUNT` from a current backend; retired.
  final String basis;

  /// Deprecated: the qualified-referrals figures under their old names.
  final double currentValue;
  final double? nextThreshold;
  final double? remaining;
  final int lookbackMonths;

  /// Qualified referrals inside the lookback window.
  final int qualifiedReferrals;

  /// Combined external card top-ups of the referred friends inside the
  /// window, in [topupVolumeCurrency].
  final double topupVolume;
  final String topupVolumeCurrency;

  /// The next level's conditions; null when that condition is not set on it
  /// (or there is no next level).
  final int? nextMinimumQualifiedReferrals;
  final double? nextMinimumTopupVolume;

  /// Distance left per condition; null when not set, 0 when already met.
  final int? remainingQualifiedReferrals;
  final double? remainingTopupVolume;

  /// The conditions set on the next level, qualified referrals first.
  List<ReferralLevelCondition> get nextConditions {
    final nextQualified = nextMinimumQualifiedReferrals;
    final nextVolume = nextMinimumTopupVolume;
    return [
      if (nextQualified != null)
        ReferralLevelCondition(
          kind: ReferralConditionKind.qualifiedReferrals,
          current: qualifiedReferrals.toDouble(),
          target: nextQualified.toDouble(),
        ),
      if (nextVolume != null)
        ReferralLevelCondition(
          kind: ReferralConditionKind.topupVolume,
          current: topupVolume,
          target: nextVolume,
          currency: topupVolumeCurrency,
        ),
    ];
  }

  /// The condition the customer is furthest from, by completion fraction —
  /// the one a single progress bar should show. Ties go to referrals. Null
  /// when the next level sets no condition (or there is none).
  ReferralLevelCondition? get focusCondition {
    ReferralLevelCondition? focus;
    for (final condition in nextConditions) {
      if (focus == null || condition.fraction < focus.fraction) {
        focus = condition;
      }
    }
    return focus;
  }
}

double _floorAtZero(double value) => value < 0 ? 0 : value;

/// Positive amounts only; zero and below are "no condition".
double? _positive(double? value) => value != null && value > 0 ? value : null;

int? _positiveCount(double? value) {
  final count = value?.round();
  return count != null && count > 0 ? count : null;
}

/// `GET rewards/referrals/summary`, v2 shape.
class ReferralSummary {
  const ReferralSummary({
    this.enabled = true,
    this.provider = '',
    this.referralCode,
    this.referralPath,
    this.currentLevel,
    this.nextLevel,
    this.levels = const [],
    this.progress = const ReferralProgress(),
    this.referrals = const ReferralCounts(),
    this.rewards = const ReferralRewardTotals(),
    this.offer,
    this.terms,
    this.deliveryMode = 'WALLET_CREDIT',
    this.minimumCreditAmount = 0,
    this.accumulatedTowardsCredit = 0,
    this.programId,
    this.programName,
    this.programDescription,
    this.canInvite = true,
    this.assignedLevel = false,
    this.participationStatus,
    this.participationReason,
  });

  factory ReferralSummary.fromJson(Map<String, dynamic> json) {
    final enabledRaw = json['enabled'] ?? json['Enabled'];
    final currentLevel = _map(json['currentLevel'] ?? json['CurrentLevel']);
    final nextLevel = _map(json['nextLevel'] ?? json['NextLevel']);
    final offer = _map(json['offer'] ?? json['Offer']);
    final terms = _map(json['terms'] ?? json['Terms']);
    final levelsRaw = json['levels'] ?? json['Levels'];
    final participation = _map(json['participationEligibility'] ?? json['ParticipationEligibility']);
    return ReferralSummary(
      enabled: enabledRaw == null ? true : _bool(enabledRaw),
      provider: _field(json, 'provider') ?? '',
      referralCode: _field(json, 'referralCode'),
      referralPath: _field(json, 'referralPath'),
      currentLevel:
          currentLevel.isEmpty ? null : ReferralLevel.fromJson(currentLevel),
      nextLevel: nextLevel.isEmpty ? null : ReferralLevel.fromJson(nextLevel),
      levels: levelsRaw is List
          ? [
              for (final item in levelsRaw)
                if (_map(item).isNotEmpty) ReferralLevel.fromJson(_map(item)),
            ]
          : const [],
      progress:
          ReferralProgress.fromJson(_map(json['progress'] ?? json['Progress'])),
      referrals:
          ReferralCounts.fromJson(_map(json['referrals'] ?? json['Referrals'])),
      rewards: ReferralRewardTotals.fromJson(
        _map(json['rewards'] ??
            json['Rewards'] ??
            json['commissions'] ??
            json['Commissions']),
      ),
      offer: offer.isEmpty ? null : ReferralOffer.fromJson(offer),
      terms: terms.isEmpty ? null : ReferralTerms.fromJson(terms),
      deliveryMode:
          _field(json, 'deliveryMode')?.toUpperCase() ?? 'WALLET_CREDIT',
      minimumCreditAmount: _num(json, 'minimumCreditAmount') ?? 0,
      accumulatedTowardsCredit: _num(json, 'accumulatedTowardsCredit') ?? 0,
      programId: _field(json, 'programId'),
      programName: _field(json, 'programName'),
      programDescription: _field(json, 'programDescription'),
      canInvite: _bool(json['canInvite'] ?? json['CanInvite'], fallback: true),
      assignedLevel: _bool(json['assignedLevel'] ?? json['AssignedLevel']),
      participationStatus: _field(participation, 'status'),
      participationReason: _field(participation, 'reason'),
    );
  }

  final bool enabled;
  final String provider;
  final String? referralCode;
  final String? referralPath;
  final ReferralLevel? currentLevel;
  final ReferralLevel? nextLevel;
  final List<ReferralLevel> levels;
  final ReferralProgress progress;
  final ReferralCounts referrals;
  final ReferralRewardTotals rewards;
  final ReferralOffer? offer;
  final ReferralTerms? terms;
  final String deliveryMode;
  final double minimumCreditAmount;
  final double accumulatedTowardsCredit;
  final String? programId;
  final String? programName;

  /// The tenant's own wording for the offer, written in the admin portal's
  /// programme Description. Null when the admin left it empty, in which case
  /// the app explains the offer from the programme's figures instead.
  final String? programDescription;
  final bool canInvite;
  final bool assignedLevel;
  final String? participationStatus;
  final String? participationReason;

  bool get residenceRestricted =>
      participationReason == 'GEO_RESIDENCE_EXCLUDED' ||
      participationReason == 'GEO_COUNTRY_UNVERIFIED';

  String get residenceRestrictionMessage =>
      participationReason == 'GEO_RESIDENCE_EXCLUDED'
          ? 'The referral programme is not available in your verified country of residence. Your previously paid rewards remain unchanged.'
          : 'Verify your country of residence before inviting friends or earning referral rewards.';

  /// Rewards are delivered as vouchers the member redeems.
  bool get usesVouchers => referralVoucherDeliveryModes.contains(deliveryMode);

  /// Rewards land in the member's balance without any action.
  bool get creditsWallet => !usesVouchers;

  /// The member must accept the current terms before sharing.
  bool get mustAcceptTerms => terms?.requiresAcceptance ?? false;

  /// A level ladder is only a story when there is more than one visible rung.
  bool get showsLevels => levels.length > 1;

  bool get hasShareableCode =>
      referralCode != null && referralCode!.trim().isNotEmpty;

  /// The tenant wrote its own explanation of the offer, so the generated
  /// sentence stays out of the way.
  bool get hasProgramDescription =>
      programDescription != null && programDescription!.trim().isNotEmpty;
}

/// One reward ledger row.
class ReferralRewardExplanation {
  const ReferralRewardExplanation({
    required this.basis,
    this.rate,
    this.termsVersion,
    required this.rounding,
    required this.deliveryExplanation,
    this.capNote,
  });
  factory ReferralRewardExplanation.fromJson(Map<String, dynamic> json) =>
      ReferralRewardExplanation(
        basis: _field(json, 'basis') ?? '',
        rate: _num(json, 'rate'),
        termsVersion: _num(json, 'termsVersion')?.toInt(),
        rounding: _field(json, 'rounding') ?? '',
        deliveryExplanation: _field(json, 'deliveryExplanation') ?? '',
        capNote: _field(json, 'capNote'),
      );
  final String basis;
  final double? rate;
  final int? termsVersion;
  final String rounding;
  final String deliveryExplanation;

  /// The engine's own sentence when a cap limited this reward ("Only $200 of
  /// this top-up was eligible…"); null when nothing was capped or the engine
  /// predates the field.
  final String? capNote;
  String get basisLabel => switch (basis) {
        'PERCENT_OF_TOPUP' => 'Eligible credited top-up',
        'PERCENT_OF_WL_FEE' => 'Settled white-label fee after cost',
        'PERCENT_OF_MARGIN' => 'Settled margin',
        'FIXED' => 'Fixed reward',
        _ => basis,
      };
}

/// Settlement evidence, separate from earned ledger value. Missing fields
/// remain unknown; historical paid statuses cannot manufacture cash evidence.
class ReferralRewardBalance {
  const ReferralRewardBalance(
      {this.cashPaid,
      this.offsetSettled,
      this.reservedCash,
      this.remainingPayable,
      this.legacyCashUnknown = true,
      this.cashPaidText,
      this.offsetSettledText,
      this.reservedCashText,
      this.remainingPayableText});
  factory ReferralRewardBalance.fromJson(Map<String, dynamic> json) =>
      ReferralRewardBalance(
          cashPaid: _num(json, 'cashPaid'),
          cashPaidText: _field(json, 'cashPaid'),
          offsetSettledText: _field(json, 'offsetSettled'),
          reservedCashText: _field(json, 'reservedCash'),
          remainingPayableText: _field(json, 'remainingPayable'),
          offsetSettled: _num(json, 'offsetSettled'),
          reservedCash: _num(json, 'reservedCash'),
          remainingPayable: _num(json, 'remainingPayable'),
          legacyCashUnknown: _bool(
              json['legacyCashUnknown'] ?? json['LegacyCashUnknown'],
              fallback: true));
  final double? cashPaid;
  final double? offsetSettled;
  final double? reservedCash;
  final double? remainingPayable;
  final bool legacyCashUnknown;
  final String? cashPaidText;
  final String? offsetSettledText;
  final String? reservedCashText;
  final String? remainingPayableText;
  bool get cashKnown => !legacyCashUnknown && cashPaid != null;
}

class ReferralReward {
  const ReferralReward({
    this.id,
    this.eventType = '',
    this.beneficiaryRole = '',
    this.levelCode = '',
    this.basisAmount = 0,
    this.basisCurrency = '',
    required this.amount,
    required this.currency,
    this.deliveryMode = 'WALLET_CREDIT',
    this.status = '',
    this.stage = ReferralRewardStage.unknown,
    this.creditId,
    this.voucherId,
    this.friendAlias,
    this.occurredAt,
    this.createdAt,
    this.paidAt,
    this.explanation,
    this.balance,
    this.holdReasons = const [],
    this.releaseAt,
  });

  factory ReferralReward.fromJson(Map<String, dynamic> json) {
    final status = _field(json, 'status') ?? '';
    return ReferralReward(
      id: _field(json, 'id'),
      eventType: _field(json, 'eventType')?.toUpperCase() ?? '',
      beneficiaryRole: _field(json, 'beneficiaryRole')?.toUpperCase() ?? '',
      levelCode: _field(json, 'levelCode') ?? '',
      basisAmount: _num(json, 'basisAmount') ?? 0,
      basisCurrency: _field(json, 'basisCurrency') ?? '',
      amount: _num(json, 'amount') ?? 0,
      currency: _field(json, 'currency') ?? 'USD',
      deliveryMode:
          _field(json, 'deliveryMode')?.toUpperCase() ?? 'WALLET_CREDIT',
      status: status,
      stage: ReferralRewardStage.fromWire(_field(json, 'stage') ?? status),
      creditId: _field(json, 'creditId'),
      voucherId: _field(json, 'voucherId'),
      friendAlias: _field(json, 'friendAlias'),
      occurredAt: _date(json, 'occurredAt'),
      createdAt: _date(json, 'createdAt'),
      paidAt: _date(json, 'paidAt'),
      balance: json['balance'] is Map || json['Balance'] is Map
          ? ReferralRewardBalance.fromJson(
              _map(json['balance'] ?? json['Balance']))
          : null,
      holdReasons: (json['holdReasons'] ?? json['HoldReasons']) is List
          ? ((json['holdReasons'] ?? json['HoldReasons']) as List)
              .map((x) => x.toString())
              .toList()
          : const [],
      releaseAt: _date(json, 'releaseAt'),
      explanation: json['Explanation'] is Map || json['explanation'] is Map
          ? ReferralRewardExplanation.fromJson(
              _map(json['Explanation'] ?? json['explanation']))
          : null,
    );
  }

  final String? id;
  final String eventType;
  final String beneficiaryRole;
  final String levelCode;
  final double basisAmount;
  final String basisCurrency;
  final double amount;
  final String currency;
  final String deliveryMode;
  final String status;
  final ReferralRewardStage stage;
  final String? creditId;
  final String? voucherId;
  final String? friendAlias;
  final DateTime? occurredAt;
  final DateTime? createdAt;
  final DateTime? paidAt;
  final ReferralRewardExplanation? explanation;
  final ReferralRewardBalance? balance;
  final List<String> holdReasons;
  final DateTime? releaseAt;

  /// English copy for what earned the reward; screens pass it through
  /// `context.tr`.
  String get eventLabel {
    switch (eventType) {
      case 'QUALIFICATION':
        return 'Friend qualified';
      case 'WELCOME':
        return 'Welcome reward';
      case 'CARD_TOPUP':
        return 'Top-up commission';
      case 'CARD_ISSUED':
        return 'Card reward';
      case 'ADJUSTMENT':
        return 'Adjustment';
      default:
        return 'Reward';
    }
  }
}

/// The stages a member's ledger is grouped into, in display order.
const referralLedgerStages = [
  ReferralRewardStage.pending,
  ReferralRewardStage.ready,
  ReferralRewardStage.crediting,
  ReferralRewardStage.paid,
];

/// Rewards by stage, in [referralLedgerStages] order, newest first inside a
/// group. Failed and unknown rows are left out: they are the operator's to
/// resolve and the summary carries their total.
Map<ReferralRewardStage, List<ReferralReward>> groupReferralRewards(
  Iterable<ReferralReward> rewards,
) {
  final groups = {
    for (final stage in referralLedgerStages) stage: <ReferralReward>[],
  };
  for (final reward in rewards) {
    groups[reward.stage]?.add(reward);
  }
  for (final rows in groups.values) {
    rows.sort((a, b) {
      final left = a.occurredAt ?? a.createdAt;
      final right = b.occurredAt ?? b.createdAt;
      if (left == null || right == null) return 0;
      return right.compareTo(left);
    });
  }
  return groups;
}

/// One referred friend as shown to the inviter.
class ReferralFriend {
  const ReferralFriend({
    this.id,
    required this.alias,
    this.stage = ReferralFriendStage.unknown,
    this.attributedAt,
    this.kycCompletedAt,
    this.firstCardAt,
    this.firstTopupAt,
    this.qualifiedAt,
    this.earningUntil,
    this.earnedAmount = 0,
    this.currency = 'USD',
    this.recipientName,
  });

  factory ReferralFriend.fromJson(Map<String, dynamic> json) {
    return ReferralFriend(
      id: _field(json, 'id'),
      alias: _field(json, 'alias') ?? _field(json, 'id') ?? '',
      stage: ReferralFriendStage.fromWire(
          _field(json, 'stage') ?? _field(json, 'status')),
      attributedAt: _date(json, 'attributedAt'),
      kycCompletedAt: _date(json, 'kycCompletedAt'),
      firstCardAt: _date(json, 'firstCardAt'),
      firstTopupAt: _date(json, 'firstTopupAt'),
      qualifiedAt: _date(json, 'qualifiedAt'),
      earningUntil: _date(json, 'earningUntil'),
      earnedAmount: _num(json, 'earnedAmount') ?? 0,
      currency: _field(json, 'currency') ?? 'USD',
      recipientName: _field(json, 'recipientName'),
    );
  }

  final String? id;
  final String alias;
  final ReferralFriendStage stage;
  final DateTime? attributedAt;
  final DateTime? kycCompletedAt;
  final DateTime? firstCardAt;
  final DateTime? firstTopupAt;
  final DateTime? qualifiedAt;
  final DateTime? earningUntil;
  final double earnedAmount;
  final String currency;
  final String? recipientName;

  /// The name the inviter typed into an email invitation, else the pseudonym.
  String get displayName {
    final name = recipientName?.trim();
    return name == null || name.isEmpty ? alias : name;
  }

  bool get isEarning =>
      stage == ReferralFriendStage.qualified &&
      (earningUntil == null || earningUntil!.isAfter(DateTime.now().toUtc()));
}

/// What a referral code promises the person entering it, from
/// `check-referral` or an invitation preview. Every field is optional so the
/// signup screen degrades to generic copy when a backend predates them.
class ReferralWelcome {
  const ReferralWelcome({
    this.valid = true,
    this.inviterDisplayName,
    this.welcomeAmount = 0,
    this.welcomeCurrency = 'USD',
    this.termsVersion,
    this.kind,
    this.destination,
    this.campaignLinkInactive = false,
  });

  factory ReferralWelcome.fromJson(Map<String, dynamic> json) {
    final validRaw = json['valid'] ?? json['Valid'];
    return ReferralWelcome(
      valid: validRaw == null ? true : _bool(validRaw),
      inviterDisplayName: _field(json, 'inviterDisplayName'),
      welcomeAmount: _num(json, 'welcomeAmount') ?? 0,
      welcomeCurrency: _field(json, 'welcomeCurrency') ?? 'USD',
      termsVersion: _num(json, 'termsVersion')?.round(),
      kind: _field(json, 'kind')?.toUpperCase(),
      destination: _field(json, 'destination')?.toLowerCase(),
    );
  }

  /// The answer for a campaign link that has been paused, archived or has
  /// expired: the code is real but no longer attributes, and the sign-up
  /// carries on without it.
  const ReferralWelcome.inactiveCampaignLink()
      : this(valid: false, campaignLinkInactive: true);

  final bool valid;
  final String? inviterDisplayName;
  final double welcomeAmount;
  final String welcomeCurrency;
  final int? termsVersion;

  /// What the code is: `PERSONAL` for a member's own code, `CAMPAIGN_LINK`
  /// for a tracking link (addendum A). Null on a backend that predates the
  /// field, which the app treats as a personal code.
  final String? kind;

  /// Where a campaign link sends the friend after sign-up, as the platform's
  /// allowlist word (`signup`, `home`, `cards`, `topup`, `rewards`); null
  /// for a personal code or an older backend.
  final String? destination;

  /// The platform answered `CAMPAIGN_LINK_INACTIVE` for this code.
  final bool campaignLinkInactive;

  bool get hasWelcome => welcomeAmount > 0;

  /// The code resolved to a live campaign link: the sign-up page records a
  /// click for it, and only for it.
  bool get isCampaignLink => kind == referralCampaignLinkKind;
}

/// `kind` of a `check-referral` answer that resolved to a campaign link.
const referralCampaignLinkKind = 'CAMPAIGN_LINK';

/// The error code the backend (and, underneath it, the platform) answers
/// for a campaign link that no longer attributes.
const referralCampaignLinkInactiveCode = 'CAMPAIGN_LINK_INACTIVE';

/// Whether an error body from `check-referral` says the code is a campaign
/// link that no longer attributes. The facade answers its own
/// `auth.referral.campaign_link_inactive` with the platform's code as the
/// detail; an older facade passes the platform body through as the detail,
/// so the whole body is searched rather than one field.
bool isReferralCampaignLinkInactive(Object? body) {
  if (body == null) return false;
  final text = body is String ? body : body.toString();
  return text.contains(referralCampaignLinkInactiveCode) ||
      text.contains('campaign_link_inactive');
}

// ---------------------------------------------------------------------------
// Member analytics (contract 2026-09-15): what happened in a period, scoped
// to the member's own earnings and pseudonymised friend stages. The resource
// is newer than the rest of the member API, so every shape here parses an
// empty map to zeros and the provider turns a 404 into "not served".
// ---------------------------------------------------------------------------

/// A reporting period; [wire] is the `range` query value.
enum ReferralAnalyticsRange {
  sevenDays('7d', 7),
  thirtyDays('30d', 30),
  ninetyDays('90d', 90),

  /// The current calendar month, UTC.
  month('month', null);

  const ReferralAnalyticsRange(this.wire, this.days);

  final String wire;

  /// Length of a rolling window, null for the calendar month.
  final int? days;

  static ReferralAnalyticsRange fromWire(String? value) {
    for (final range in values) {
      if (range.wire == value?.trim().toLowerCase()) return range;
    }
    return ReferralAnalyticsRange.thirtyDays;
  }
}

/// Friends attributed in the period, counted once each by the furthest
/// stage they reached.
class ReferralJourneyCounts {
  const ReferralJourneyCounts({
    this.invited = 0,
    this.verified = 0,
    this.cardIssued = 0,
    this.qualified = 0,
    this.earning = 0,
    this.windowEnded = 0,
  });

  factory ReferralJourneyCounts.fromJson(Map<String, dynamic> json) =>
      ReferralJourneyCounts(
        invited: _count(json, 'invited'),
        verified: _count(json, 'verified'),
        cardIssued: _count(json, 'cardIssued'),
        qualified: _count(json, 'qualified'),
        earning: _count(json, 'earning'),
        windowEnded: _count(json, 'windowEnded'),
      );

  final int invited;
  final int verified;
  final int cardIssued;
  final int qualified;
  final int earning;
  final int windowEnded;

  /// Every friend attributed in the period.
  int get total =>
      invited + verified + cardIssued + qualified + earning + windowEnded;

  /// The stages in journey order: a stable id for keys, the English label
  /// for `context.tr`, and the count.
  List<({String id, String label, int count})> get stages => [
        (id: 'invited', label: 'Invited', count: invited),
        (id: 'verified', label: 'Verified', count: verified),
        (id: 'cardIssued', label: 'Card issued', count: cardIssued),
        (id: 'qualified', label: 'Qualified', count: qualified),
        (id: 'earning', label: 'Earning', count: earning),
        (id: 'windowEnded', label: 'Window ended', count: windowEnded),
      ];
}

/// The period's headline figures. Rewards are those whose event fell in the
/// period; accrued is everything not cancelled, in the payout currency.
class ReferralAnalyticsTotals {
  const ReferralAnalyticsTotals({
    this.attributed = 0,
    this.qualified = 0,
    this.conversionRate = 0,
    this.rewardsAccrued = 0,
    this.rewardsPaid = 0,
    this.rewardsPending = 0,
  });

  factory ReferralAnalyticsTotals.fromJson(Map<String, dynamic> json) =>
      ReferralAnalyticsTotals(
        attributed: _count(json, 'attributed'),
        qualified: _count(json, 'qualified'),
        conversionRate: (_num(json, 'conversionRate') ?? 0).clamp(0, 1),
        rewardsAccrued: _num(json, 'rewardsAccrued') ?? 0,
        rewardsPaid: _num(json, 'rewardsPaid') ?? 0,
        rewardsPending: _num(json, 'rewardsPending') ?? 0,
      );

  final int attributed;
  final int qualified;

  /// qualified / attributed, 0..1.
  final double conversionRate;
  final double rewardsAccrued;
  final double rewardsPaid;
  final double rewardsPending;
}

/// One ISO week overlapping the period. Weeks with nothing in them are
/// still sent, so a chart keeps its axis.
class ReferralWeeklyBucket {
  const ReferralWeeklyBucket({
    required this.weekStart,
    this.attributed = 0,
    this.qualified = 0,
    this.rewardsAccrued = 0,
    this.rewardsPaid = 0,
  });

  /// Null when the row carries no parseable week start; the caller drops it.
  static ReferralWeeklyBucket? fromJson(Map<String, dynamic> json) {
    final weekStart = _date(json, 'weekStart');
    if (weekStart == null) return null;
    return ReferralWeeklyBucket(
      weekStart: weekStart,
      attributed: _count(json, 'attributed'),
      qualified: _count(json, 'qualified'),
      rewardsAccrued: _num(json, 'rewardsAccrued') ?? 0,
      rewardsPaid: _num(json, 'rewardsPaid') ?? 0,
    );
  }

  final DateTime weekStart;
  final int attributed;
  final int qualified;
  final double rewardsAccrued;
  final double rewardsPaid;
}

/// A friend on the period's leaderboard: the same pseudonym and stage the
/// friends list shows, and what they earned the member (paid + pending).
class ReferralTopFriend {
  const ReferralTopFriend({
    required this.alias,
    this.stage = ReferralFriendStage.unknown,
    this.earned = 0,
    this.qualifiedAt,
  });

  factory ReferralTopFriend.fromJson(Map<String, dynamic> json) =>
      ReferralTopFriend(
        alias: _field(json, 'alias') ?? '',
        stage: ReferralFriendStage.fromWire(_field(json, 'stage')),
        earned: _num(json, 'earned') ?? 0,
        qualifiedAt: _date(json, 'qualifiedAt'),
      );

  final String alias;
  final ReferralFriendStage stage;
  final double earned;
  final DateTime? qualifiedAt;
}

/// The member's analytics for one period.
class ReferralMemberAnalytics {
  const ReferralMemberAnalytics({
    this.from,
    this.to,
    this.range = ReferralAnalyticsRange.thirtyDays,
    this.currency = 'USD',
    this.generatedAt,
    this.journey = const ReferralJourneyCounts(),
    this.totals = const ReferralAnalyticsTotals(),
    this.weekly = const [],
    this.topFriends = const [],
    this.campaigns = const [],
  });

  factory ReferralMemberAnalytics.fromJson(Map<String, dynamic> json) {
    final weekly = _rows(json, 'weekly')
        .map(ReferralWeeklyBucket.fromJson)
        .whereType<ReferralWeeklyBucket>()
        .toList()
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    return ReferralMemberAnalytics(
      from: _date(json, 'from'),
      to: _date(json, 'to'),
      range: ReferralAnalyticsRange.fromWire(_field(json, 'range')),
      currency: _field(json, 'currency') ?? 'USD',
      generatedAt: _date(json, 'generatedAt'),
      journey: ReferralJourneyCounts.fromJson(
        _map(json['journey'] ?? json['Journey']),
      ),
      totals: ReferralAnalyticsTotals.fromJson(
        _map(json['totals'] ?? json['Totals']),
      ),
      weekly: weekly,
      topFriends: _rows(json, 'topFriends')
          .map(ReferralTopFriend.fromJson)
          .where((friend) => friend.alias.isNotEmpty)
          .toList(),
      campaigns: _rows(json, 'campaigns')
          .map(ReferralCampaignRow.fromJson)
          .where((row) => row.linkId.isNotEmpty || row.code.isNotEmpty)
          .toList(),
    );
  }

  final DateTime? from;

  /// Exclusive.
  final DateTime? to;
  final ReferralAnalyticsRange range;

  /// Payout currency of every amount here.
  final String currency;
  final DateTime? generatedAt;
  final ReferralJourneyCounts journey;
  final ReferralAnalyticsTotals totals;

  /// Oldest week first.
  final List<ReferralWeeklyBucket> weekly;
  final List<ReferralTopFriend> topFriends;

  /// The member's campaign links with what each brought in over the period
  /// (blueprint p17, "campaign performance"). Empty on a platform that
  /// predates campaign links or when no link had traffic.
  final List<ReferralCampaignRow> campaigns;

  /// Nothing happened in the period: no friend attributed, no reward
  /// accrued, no week with a figure. The screens show one empty state in
  /// place of every block.
  bool get isEmpty =>
      journey.total == 0 &&
      totals.attributed == 0 &&
      totals.qualified == 0 &&
      totals.rewardsAccrued == 0 &&
      totals.rewardsPaid == 0 &&
      totals.rewardsPending == 0 &&
      topFriends.isEmpty &&
      weekly.every((week) =>
          week.attributed == 0 &&
          week.qualified == 0 &&
          week.rewardsAccrued == 0 &&
          week.rewardsPaid == 0);
}

/// Money for the referral copy: the app's one formatter, minus the ".00" a
/// headline such as "$3 for them" does not want. Symbol, grouping and Private
/// Mode stay decided in one place.
String formatReferralAmount(String currency, double amount) {
  final text = Money.formatAmount(currency, amount);
  return text.replaceFirst(RegExp(r'\.00(?=\D|$)'), '');
}

/// A percentage for the referral copy: "0.25%" rather than "0.250000%".
String formatReferralPercent(double rate) {
  var fixed = rate.toStringAsFixed(4);
  while (fixed.contains('.') && (fixed.endsWith('0') || fixed.endsWith('.'))) {
    fixed = fixed.substring(0, fixed.length - 1);
  }
  return '$fixed%';
}

/// The referrer's side of the offer as one short expression, e.g.
/// "$1 + 0.25%". Null when the offer pays the referrer nothing.
String? describeReferrerReward(ReferralOffer offer) {
  final parts = <String>[];
  if (offer.hasQualificationReward) {
    parts.add(
      offer.qualificationCalculationType == 'PERCENT_OF_CARD_FEE'
          ? formatReferralPercent(offer.qualificationRate)
          : formatReferralAmount(
              offer.welcomeCurrency, offer.qualificationRate),
    );
  }
  if (offer.hasTopupReward) {
    parts.add(
      offer.topupCalculationType == 'FIXED'
          ? formatReferralAmount(offer.welcomeCurrency, offer.topupRate)
          : formatReferralPercent(offer.topupRate),
    );
  }
  return parts.isEmpty ? null : parts.join(' + ');
}

Map<String, dynamic> _map(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

String? _text(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

bool _bool(Object? value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    if (value.toLowerCase() == 'true') {
      return true;
    }
    if (value.toLowerCase() == 'false') {
      return false;
    }
  }
  return fallback;
}

String? _field(Map<String, dynamic> source, String camelName) {
  final pascal = camelName.isEmpty
      ? camelName
      : '${camelName[0].toUpperCase()}${camelName.substring(1)}';
  return _text(source[camelName] ?? source[pascal]);
}

double? _num(Map<String, dynamic> source, String camelName) {
  final pascal = camelName.isEmpty
      ? camelName
      : '${camelName[0].toUpperCase()}${camelName.substring(1)}';
  final value = source[camelName] ?? source[pascal];
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}

DateTime? _date(Map<String, dynamic> source, String camelName) {
  final text = _field(source, camelName);
  if (text == null) return null;
  return DateTime.tryParse(text)?.toUtc();
}

/// A whole number; a missing or negative figure counts as none.
int _count(Map<String, dynamic> source, String camelName) {
  final value = _num(source, camelName)?.round() ?? 0;
  return value < 0 ? 0 : value;
}

/// The object rows under a camelCase or PascalCase list field.
List<Map<String, dynamic>> _rows(
    Map<String, dynamic> source, String camelName) {
  final pascal = '${camelName[0].toUpperCase()}${camelName.substring(1)}';
  final value = source[camelName] ?? source[pascal];
  if (value is! List) return const [];
  return value.whereType<Map>().map(_map).toList();
}

// ---------------------------------------------------------------------------
// Campaign links (contract 2026-09-15, blueprint p27): tracking records a
// member owns. A link references the programme and the offer version in
// force, carries a name, an opaque code, a channel, a language and a
// lifecycle — and never a rate or any authority to change one. The resource
// is newer than the member API, so a 404 means "not deployed" and every
// parser tolerates missing fields.
// ---------------------------------------------------------------------------

/// Where a campaign link stands; [wire] is the platform's value.
enum ReferralCampaignLinkStatus {
  draft('DRAFT', 'Draft'),
  active('ACTIVE', 'Active'),
  paused('PAUSED', 'Paused'),
  expired('EXPIRED', 'Expired'),
  archived('ARCHIVED', 'Archived'),
  unknown('', 'Unknown');

  const ReferralCampaignLinkStatus(this.wire, this.label);

  final String wire;

  /// English copy key for the status, translated at the call site.
  final String label;

  static ReferralCampaignLinkStatus fromWire(String? value) {
    final normalized = value?.trim().toUpperCase() ?? '';
    for (final status in values) {
      if (status.wire == normalized && status != unknown) return status;
    }
    return ReferralCampaignLinkStatus.unknown;
  }
}

/// Where a link is shared; the platform's allowlist.
enum ReferralCampaignChannel {
  social('social', 'Social media'),
  community('community', 'Community'),
  email('email', 'Email'),
  website('website', 'Website'),
  event('event', 'Event'),
  other('other', 'Other');

  const ReferralCampaignChannel(this.wire, this.label);

  final String wire;

  /// English copy key for the channel, translated at the call site.
  final String label;

  static ReferralCampaignChannel? fromWire(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final channel in values) {
      if (channel.wire == normalized) return channel;
    }
    return null;
  }
}

/// Where a campaign link sends the friend after sign-up (addendum A); the
/// platform's allowlist. [label] is the English copy key of the human name.
enum ReferralCampaignDestination {
  signup('signup', 'Sign-up page'),
  home('home', 'Home after sign-up'),
  cards('cards', 'Cards'),
  topup('topup', 'Add money'),
  rewards('rewards', 'Rewards');

  const ReferralCampaignDestination(this.wire, this.label);

  final String wire;
  final String label;

  static ReferralCampaignDestination? fromWire(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final destination in values) {
      if (destination.wire == normalized) return destination;
    }
    return null;
  }
}

/// Sign-ups per unique click, or null before any unique click — the figure
/// the platform reports as `clickToSignupRate` (4 dp), computed the same
/// way for lists that carry only the counters.
double? referralClickToSignupRate(int signups, int uniqueClicks) {
  if (uniqueClicks <= 0) return null;
  return (signups / uniqueClicks * 10000).round() / 10000;
}

/// A rate as a percentage with one decimal ("12.5%"), or null for none.
String? formatReferralRate(double? rate) {
  if (rate == null || rate.isNaN) return null;
  final percent = rate * 100;
  final text = percent.toStringAsFixed(1);
  return '${text.endsWith('.0') ? text.substring(0, text.length - 2) : text}%';
}

/// One campaign link (`ReferralCampaignLinkResponse`).
class ReferralCampaignLink {
  const ReferralCampaignLink({
    required this.id,
    this.programId,
    this.programName,
    this.name = '',
    this.code = '',
    this.channel = '',
    this.locale = 'en',
    this.destination = 'signup',
    this.status = ReferralCampaignLinkStatus.unknown,
    this.activeFrom,
    this.expiresAt,
    this.createdAt,
    this.shareUrl,
    this.signupCount = 0,
    this.qualifiedCount = 0,
    this.clickCount = 0,
    this.uniqueClickCount = 0,
    this.clicksTracked = false,
    this.offerVersionId,
    this.suggestedCaption,
  });

  factory ReferralCampaignLink.fromJson(Map<String, dynamic> json) {
    final clicksTracked =
        json.containsKey('clickCount') || json.containsKey('ClickCount');
    return ReferralCampaignLink(
      id: _field(json, 'id') ?? '',
      programId: _field(json, 'programId'),
      programName: _field(json, 'programName'),
      name: _field(json, 'name') ?? '',
      code: _field(json, 'code') ?? '',
      channel: _field(json, 'channel')?.toLowerCase() ?? '',
      locale: _field(json, 'locale') ?? 'en',
      destination: _field(json, 'destination') ?? 'signup',
      status: ReferralCampaignLinkStatus.fromWire(_field(json, 'status')),
      activeFrom: _date(json, 'activeFrom'),
      expiresAt: _date(json, 'expiresAt'),
      createdAt: _date(json, 'createdAt'),
      shareUrl: _field(json, 'shareUrl'),
      signupCount: _count(json, 'signupCount'),
      qualifiedCount: _count(json, 'qualifiedCount'),
      clickCount: _count(json, 'clickCount'),
      uniqueClickCount: _count(json, 'uniqueClickCount'),
      clicksTracked: clicksTracked,
      offerVersionId: _field(json, 'offerVersionId'),
      suggestedCaption: _field(json, 'suggestedCaption'),
    );
  }

  final String id;
  final String? programId;
  final String? programName;
  final String name;
  final String code;
  final String channel;
  final String locale;
  final String destination;
  final ReferralCampaignLinkStatus status;
  final DateTime? activeFrom;
  final DateTime? expiresAt;
  final DateTime? createdAt;

  /// The address to share, built by the platform from its registration URL.
  final String? shareUrl;
  final int signupCount;
  final int qualifiedCount;

  /// Sign-up page visits since the link was created (addendum A), and the
  /// visitors among them counted once per day.
  final int clickCount;
  final int uniqueClickCount;

  /// The platform sent click counters at all; false on one that predates
  /// them, where the screens leave click figures out rather than show zero.
  final bool clicksTracked;
  final String? offerVersionId;

  /// One-sentence offer text generated by the platform for this link.
  final String? suggestedCaption;

  ReferralCampaignChannel? get channelValue =>
      ReferralCampaignChannel.fromWire(channel);

  ReferralCampaignDestination? get destinationValue =>
      ReferralCampaignDestination.fromWire(destination);

  /// Sign-ups per unique click since creation, or null before any.
  double? get clickToSignupRate =>
      referralClickToSignupRate(signupCount, uniqueClickCount);

  /// The status as it stands at [now]: a link whose expiry has passed reads
  /// as expired whatever the row says; an archived link stays archived.
  ReferralCampaignLinkStatus effectiveStatus([DateTime? now]) {
    if (status == ReferralCampaignLinkStatus.archived) return status;
    final expires = expiresAt;
    if (expires != null && !expires.isAfter(now ?? DateTime.now())) {
      return ReferralCampaignLinkStatus.expired;
    }
    return status;
  }

  bool isActive([DateTime? now]) =>
      effectiveStatus(now) == ReferralCampaignLinkStatus.active;

  bool canPause([DateTime? now]) => isActive(now);

  bool canResume([DateTime? now]) =>
      effectiveStatus(now) == ReferralCampaignLinkStatus.paused;

  bool canArchive([DateTime? now]) =>
      effectiveStatus(now) != ReferralCampaignLinkStatus.archived;

  /// The link, or the code alone when the platform sent no address.
  String get shareText =>
      shareUrl != null && shareUrl!.trim().isNotEmpty ? shareUrl!.trim() : code;
}

/// What one link brought in over a period (`links/{id}/performance`).
class ReferralCampaignLinkPerformance {
  const ReferralCampaignLinkPerformance({
    this.signups = 0,
    this.verified = 0,
    this.qualified = 0,
    this.earning = 0,
    this.rewardsAccrued = 0,
    this.rewardsPaid = 0,
    this.currency = 'USD',
    this.clicks = 0,
    this.uniqueClicks = 0,
    this.clickToSignupRate,
    this.clicksTracked = false,
  });

  factory ReferralCampaignLinkPerformance.fromJson(Map<String, dynamic> json) {
    final clicksTracked =
        json.containsKey('clicks') || json.containsKey('Clicks');
    final signups = _count(json, 'signups');
    final uniqueClicks = _count(json, 'uniqueClicks');
    final rate = _num(json, 'clickToSignupRate');
    return ReferralCampaignLinkPerformance(
      signups: signups,
      verified: _count(json, 'verified'),
      qualified: _count(json, 'qualified'),
      earning: _count(json, 'earning'),
      rewardsAccrued: _floorAtZero(_num(json, 'rewardsAccrued') ?? 0),
      rewardsPaid: _floorAtZero(_num(json, 'rewardsPaid') ?? 0),
      currency: _field(json, 'currency') ?? 'USD',
      clicks: _count(json, 'clicks'),
      uniqueClicks: uniqueClicks,
      // The platform's own figure when it sent one; the same computation
      // from the counters otherwise, and null before any unique click.
      clickToSignupRate: rate != null && rate >= 0
          ? rate
          : referralClickToSignupRate(signups, uniqueClicks),
      clicksTracked: clicksTracked,
    );
  }

  final int signups;
  final int verified;
  final int qualified;
  final int earning;
  final double rewardsAccrued;
  final double rewardsPaid;
  final String currency;

  /// Sign-up page visits through the link in the period (addendum A), the
  /// visitors among them counted once per day, and sign-ups per unique
  /// click (null before any unique click).
  final int clicks;
  final int uniqueClicks;
  final double? clickToSignupRate;

  /// The platform sent click figures at all.
  final bool clicksTracked;

  bool get isEmpty =>
      signups == 0 &&
      verified == 0 &&
      qualified == 0 &&
      earning == 0 &&
      rewardsAccrued == 0 &&
      rewardsPaid == 0 &&
      clicks == 0;
}

/// One campaign in the member's analytics for the period.
class ReferralCampaignRow {
  const ReferralCampaignRow({
    this.linkId = '',
    this.name = '',
    this.code = '',
    this.clicks = 0,
    this.signups = 0,
    this.qualified = 0,
    this.rewardsAccrued = 0,
  });

  factory ReferralCampaignRow.fromJson(Map<String, dynamic> json) {
    return ReferralCampaignRow(
      linkId: _field(json, 'linkId') ?? '',
      name: _field(json, 'name') ?? '',
      code: _field(json, 'code') ?? '',
      clicks: _count(json, 'clicks'),
      signups: _count(json, 'signups'),
      qualified: _count(json, 'qualified'),
      rewardsAccrued: _floorAtZero(_num(json, 'rewardsAccrued') ?? 0),
    );
  }

  final String linkId;
  final String name;
  final String code;

  /// Sign-up page visits through the link in the period (addendum A); zero
  /// on a platform that predates clicks.
  final int clicks;
  final int signups;
  final int qualified;
  final double rewardsAccrued;
}

/// A programme a link can belong to, for the creator's picker.
typedef ReferralCampaignProgramme = ({String id, String name});

/// The programmes the member can create a link in: the summary's own and any
/// other the member already has links in. The member API lists no
/// programmes, so this is what the app can know.
List<ReferralCampaignProgramme> referralCampaignProgrammes(
  ReferralSummary summary,
  Iterable<ReferralCampaignLink> links,
) {
  final seen = <String, String>{};
  final ownId = summary.programId;
  if (ownId != null && ownId.isNotEmpty) {
    seen[ownId] = summary.programName ?? '';
  }
  for (final link in links) {
    final id = link.programId;
    if (id == null || id.isEmpty) continue;
    final name = link.programName ?? '';
    if (!seen.containsKey(id) || (seen[id]!.isEmpty && name.isNotEmpty)) {
      seen[id] = name;
    }
  }
  return [for (final entry in seen.entries) (id: entry.key, name: entry.value)];
}

/// What the member asks for when creating a link. [toJson] is the facade's
/// `POST links` body.
class ReferralCampaignLinkDraft {
  const ReferralCampaignLinkDraft({
    required this.name,
    required this.channel,
    this.programId,
    this.code,
    this.locale,
    this.destination,
    this.expiresAt,
  });

  final String name;
  final ReferralCampaignChannel channel;
  final String? programId;

  /// Where friends land after sign-up; null leaves the platform's default
  /// (the sign-up page).
  final ReferralCampaignDestination? destination;

  /// A custom code; null lets the platform generate one from the name.
  final String? code;
  final String? locale;
  final DateTime? expiresAt;

  Map<String, dynamic> toJson() => {
        if (programId != null && programId!.isNotEmpty) 'programId': programId,
        'name': name.trim(),
        'channel': channel.wire,
        if (code != null && code!.trim().isNotEmpty)
          'code': code!.trim().toUpperCase(),
        if (locale != null && locale!.trim().isNotEmpty)
          'locale': locale!.trim(),
        if (destination != null) 'destination': destination!.wire,
        if (expiresAt != null)
          'expiresAt': expiresAt!.toUtc().toIso8601String(),
      };
}

/// Codes the platform refuses whatever the company: route words and the
/// personal-code namespace marker.
const referralCampaignReservedCodes = {
  'SIGNUP',
  'LOGIN',
  'ADMIN',
  'API',
  'REF',
};

final _campaignCodePattern = RegExp(r'^[A-Za-z0-9_-]{6,24}$');

/// The problem with a campaign name, as an English copy key, or null when
/// it is acceptable (1–80 characters after trimming).
String? referralCampaignNameError(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return 'Enter a name for this link';
  if (name.length > 80) return 'Use at most 80 characters';
  return null;
}

/// The problem with a custom code, as an English copy key, or null when it
/// is acceptable or blank (blank = the platform generates one). Mirrors the
/// platform: 6–24 characters of letters, digits, `_` and `-`, not a reserved
/// word. Uniqueness within the company is the platform's answer.
String? referralCampaignCodeError(String? value) {
  final code = value?.trim() ?? '';
  if (code.isEmpty) return null;
  if (!_campaignCodePattern.hasMatch(code)) {
    return 'Use 6–24 letters, digits, hyphens or underscores';
  }
  if (referralCampaignReservedCodes.contains(code.toUpperCase())) {
    return 'This code is reserved';
  }
  return null;
}

/// The problem with an expiry, as an English copy key, or null when it is
/// acceptable or absent: the link has to expire in the future.
String? referralCampaignExpiryError(DateTime? value, [DateTime? now]) {
  if (value == null) return null;
  if (!value.isAfter(now ?? DateTime.now())) {
    return 'Choose a date in the future';
  }
  return null;
}

/// Links newest first by creation; unknown dates last. Archived links sink
/// below everything else so the working set stays on top.
List<ReferralCampaignLink> sortReferralCampaignLinks(
  Iterable<ReferralCampaignLink> links, [
  DateTime? now,
]) {
  final list = links.toList();
  int rank(ReferralCampaignLink link) =>
      link.effectiveStatus(now) == ReferralCampaignLinkStatus.archived ? 1 : 0;
  list.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    final da = a.createdAt;
    final db = b.createdAt;
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return db.compareTo(da);
  });
  return list;
}

/// The links a member can hand out right now.
List<ReferralCampaignLink> activeReferralCampaignLinks(
  Iterable<ReferralCampaignLink> links, [
  DateTime? now,
]) =>
    [
      for (final link in links)
        if (link.isActive(now)) link
    ];
