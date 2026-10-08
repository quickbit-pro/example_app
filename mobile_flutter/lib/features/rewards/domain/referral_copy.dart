import 'rewards_models.dart';

// ---------------------------------------------------------------------------
// Derived facts about a referral programme that more than one screen states:
// what the offer pays at the member's current level, how a friend qualifies,
// what a friend still has to do, and what a top-up would earn. Pure functions
// over the API models, so the copy in the widgets is a translation of these
// and never a second opinion on the numbers.
// ---------------------------------------------------------------------------

/// What a recurring reward is measured against.
enum ReferralRecurringBasis {
  /// A share of the friend's eligible credited top-up.
  topup,

  /// A share of the settled white-label fee after cost on the top-up.
  fee,

  /// A share of the settled margin on the top-up.
  margin,

  /// A fixed amount per top-up.
  fixed;

  static ReferralRecurringBasis fromWire(String calculationType) {
    switch (calculationType.trim().toUpperCase()) {
      case 'PERCENT_OF_WL_FEE':
        return ReferralRecurringBasis.fee;
      case 'PERCENT_OF_MARGIN':
        return ReferralRecurringBasis.margin;
      case 'FIXED':
        return ReferralRecurringBasis.fixed;
      default:
        return ReferralRecurringBasis.topup;
    }
  }

  bool get isPercent => this != ReferralRecurringBasis.fixed;

  /// The amount is only known once the provider has settled the fee or the
  /// margin, so anything computed ahead of time is an upper bound.
  bool get dependsOnSettlement =>
      this == ReferralRecurringBasis.fee ||
      this == ReferralRecurringBasis.margin;
}

/// A server offer is authoritative, including its accepted rates and resolved
/// caps. Never combine an accepted offer with a member's later tier. Older
/// responses without an offer may use the level for a rate-only illustration.
ReferralOffer effectiveReferralOffer(ReferralSummary summary) {
  if (summary.offer case final published?) return published;
  const offer = ReferralOffer();
  final level = summary.currentLevel;
  if (level == null || !(level.qualificationRate > 0 || level.topupRate > 0)) {
    return offer;
  }
  return ReferralOffer(
    welcomeAmount: offer.welcomeAmount,
    welcomeCurrency: offer.welcomeCurrency,
    qualificationCalculationType: level.qualificationCalculationType,
    qualificationRate: level.qualificationRate,
    topupCalculationType: level.topupCalculationType,
    topupRate: level.topupRate,
    earningWindowDays: offer.earningWindowDays,
    earningWindowStart: offer.earningWindowStart,
    maxEligibleVolumePerRelationship: offer.maxEligibleVolumePerRelationship,
    requiresKyc: offer.requiresKyc,
    requiresPaidCard: offer.requiresPaidCard,
    requiresTopup: offer.requiresTopup,
    minimumTopup: offer.minimumTopup,
    maximumRecurringReward: offer.maximumRecurringReward,
    volumeCapSource: offer.volumeCapSource,
    recurringRewardCapSource: offer.recurringRewardCapSource,
    customerRecurringRate: offer.customerRecurringRate,
  );
}

/// One thing a friend must do before the inviter is paid.
enum ReferralQualificationStep { verifyIdentity, getPaidCard, firstTopup }

/// The qualification checklist, in the order the friend meets it, from the
/// offer's flags. Empty when the programme pays on sign-up alone.
List<ReferralQualificationStep> referralQualificationSteps(
    ReferralOffer offer) {
  return [
    if (offer.requiresKyc) ReferralQualificationStep.verifyIdentity,
    if (offer.requiresPaidCard) ReferralQualificationStep.getPaidCard,
    if (offer.requiresTopup) ReferralQualificationStep.firstTopup,
  ];
}

/// Where a friend stands, as the next thing that has to happen.
enum ReferralFriendNextStep {
  verifyIdentity,
  getPaidCard,
  firstTopup,

  /// Qualified, inside the earning window (or a window with no end).
  earning,

  /// Qualified, window closed: nothing more is earned from this friend.
  windowEnded,

  /// The API sent a stage this build does not know.
  inProgress,
}

/// The friend's next requirement under [offer], or how their earning window
/// stands once they have qualified. Steps the offer does not require are
/// skipped, so a programme without a card requirement never asks for one.
ReferralFriendNextStep referralFriendNextStep(
  ReferralFriend friend,
  ReferralOffer offer, {
  DateTime? now,
}) {
  final steps = referralQualificationSteps(offer);
  ReferralFriendNextStep firstFrom(ReferralQualificationStep floor) {
    for (final step in steps) {
      if (step.index < floor.index) continue;
      switch (step) {
        case ReferralQualificationStep.verifyIdentity:
          return ReferralFriendNextStep.verifyIdentity;
        case ReferralQualificationStep.getPaidCard:
          return ReferralFriendNextStep.getPaidCard;
        case ReferralQualificationStep.firstTopup:
          return ReferralFriendNextStep.firstTopup;
      }
    }
    return ReferralFriendNextStep.inProgress;
  }

  switch (friend.stage) {
    case ReferralFriendStage.invited:
      return firstFrom(ReferralQualificationStep.verifyIdentity);
    case ReferralFriendStage.verifying:
      return offer.requiresKyc
          ? ReferralFriendNextStep.verifyIdentity
          : firstFrom(ReferralQualificationStep.getPaidCard);
    case ReferralFriendStage.cardIssued:
      return firstFrom(ReferralQualificationStep.firstTopup);
    case ReferralFriendStage.qualified:
      final until = friend.earningUntil;
      final moment = (now ?? DateTime.now()).toUtc();
      return until == null || until.isAfter(moment)
          ? ReferralFriendNextStep.earning
          : ReferralFriendNextStep.windowEnded;
    case ReferralFriendStage.windowEnded:
      return ReferralFriendNextStep.windowEnded;
    case ReferralFriendStage.unknown:
      return ReferralFriendNextStep.inProgress;
  }
}

/// Whole days left in a friend's earning window, or null when the window has
/// no end. Never negative: a closed window is [ReferralFriendNextStep
/// .windowEnded], not a countdown below zero.
int? referralEarningDaysLeft(ReferralFriend friend, {DateTime? now}) {
  final until = friend.earningUntil;
  if (until == null) return null;
  final left = until.difference((now ?? DateTime.now()).toUtc()).inDays;
  return left < 0 ? 0 : left;
}

/// What one top-up would earn the member, worked out ahead of settlement.
class ReferralRewardEstimate {
  const ReferralRewardEstimate({
    required this.amount,
    required this.basis,
    required this.eligibleAmount,
    required this.rate,
    this.isUpperBound = false,
    this.volumeCapped = false,
    this.rewardCapped = false,
  });

  /// The reward in the offer's currency.
  final double amount;
  final ReferralRecurringBasis basis;

  /// How much of the top-up counted, after the per-friend volume cap.
  final double eligibleAmount;

  /// The rate or fixed amount the estimate was built from.
  final double rate;

  /// True when the real figure depends on the settled fee or margin: the
  /// estimate is then the most the top-up can pay, not what it will.
  final bool isUpperBound;

  /// The top-up exceeded the per-friend eligible volume.
  final bool volumeCapped;

  /// The reward hit the per-friend recurring reward cap.
  final bool rewardCapped;
}

/// The recurring reward [offer] pays on a top-up of [amount], with both caps
/// applied. [eligibleVolumeUsed] is what this friend has already had counted,
/// when known; the summary does not carry it today, so it defaults to zero and
/// the estimate is an illustration, never a promise.
ReferralRewardEstimate estimateReferralReward(
  ReferralOffer offer,
  double amount, {
  double eligibleVolumeUsed = 0,
}) {
  final basis = ReferralRecurringBasis.fromWire(offer.topupCalculationType);
  final topup = amount < 0 ? 0.0 : amount;
  var eligible = topup;
  var volumeCapped = false;
  final volumeCap = offer.maxEligibleVolumePerRelationship;
  if (volumeCap != null) {
    final room = volumeCap - eligibleVolumeUsed;
    final allowed = room < 0 ? 0.0 : room;
    if (eligible > allowed) {
      eligible = allowed;
      volumeCapped = true;
    }
  }
  var reward = basis == ReferralRecurringBasis.fixed
      ? (eligible > 0 ? offer.topupRate : 0.0)
      : eligible * offer.topupRate / 100;
  var rewardCapped = false;
  final rewardCap = offer.maximumRecurringReward;
  if (rewardCap != null && reward > rewardCap) {
    reward = rewardCap;
    rewardCapped = true;
  }
  // Rewards round down to cents, as the ledger states; the illustration
  // should not show a cent the settlement will not pay.
  reward = (reward * 100).floorToDouble() / 100;
  return ReferralRewardEstimate(
    amount: reward,
    basis: basis,
    eligibleAmount: eligible,
    rate: offer.topupRate,
    isUpperBound: basis.dependsOnSettlement,
    volumeCapped: volumeCapped,
    rewardCapped: rewardCapped,
  );
}

/// Friends newest first by attribution; unknown dates sort last.
List<ReferralFriend> sortReferralFriendsNewestFirst(
    Iterable<ReferralFriend> friends) {
  final sorted = friends.toList();
  sorted.sort((a, b) {
    final left = a.attributedAt;
    final right = b.attributedAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return sorted;
}

/// Rewards newest first by occurrence, then creation; unknown dates last.
List<ReferralReward> sortReferralRewardsNewestFirst(
    Iterable<ReferralReward> rewards) {
  final sorted = rewards.toList();
  sorted.sort((a, b) {
    final left = a.occurredAt ?? a.createdAt;
    final right = b.occurredAt ?? b.createdAt;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return right.compareTo(left);
  });
  return sorted;
}

/// The member's view of a ledger row's delivery.
enum ReferralRewardDelivery {
  /// Waiting for the provider to confirm the event that earned it.
  awaitingConfirmation,

  /// Confirmed; waiting for the wallet credit to land.
  awaitingCredit,

  /// Confirmed; a voucher is waiting to be claimed.
  readyToClaim,

  /// In the member's balance.
  credited,

  /// Claimed as a voucher.
  claimed,

  /// The credit failed and is with the operator.
  failed,

  /// A stage this build does not know: still under review.
  underReview,
  held,
  offsetSettled,
  settlementUnavailable,
}

/// Maps a ledger stage to what the member sees, for the programme's delivery
/// mode. A pending reward is never "paid": the blueprint's one hard rule on
/// this screen is that provider-dependent steps are never announced as done.
ReferralRewardDelivery referralRewardDelivery(
  ReferralRewardStage stage, {
  required bool usesVouchers,
}) {
  switch (stage) {
    case ReferralRewardStage.pending:
      return ReferralRewardDelivery.awaitingConfirmation;
    case ReferralRewardStage.ready:
      return usesVouchers
          ? ReferralRewardDelivery.readyToClaim
          : ReferralRewardDelivery.awaitingCredit;
    case ReferralRewardStage.crediting:
      return ReferralRewardDelivery.awaitingCredit;
    case ReferralRewardStage.paid:
      return usesVouchers
          ? ReferralRewardDelivery.claimed
          : ReferralRewardDelivery.credited;
    case ReferralRewardStage.failed:
      return ReferralRewardDelivery.failed;
    case ReferralRewardStage.unknown:
      return ReferralRewardDelivery.underReview;
  }
}

/// Financial status uses server allocation evidence, not a PAID entitlement
/// alone. Held/review rewards never offer a voucher claim affordance.
ReferralRewardDelivery referralRewardEvidenceDelivery(ReferralReward reward,
    {required bool usesVouchers}) {
  if (reward.status.toUpperCase() == 'HELD' || reward.holdReasons.isNotEmpty) {
    return ReferralRewardDelivery.held;
  }
  final balance = reward.balance;
  if ((balance?.offsetSettled ?? 0) > 0 &&
      balance?.remainingPayable == 0 &&
      balance?.cashPaid == 0 &&
      balance?.legacyCashUnknown == false) {
    return ReferralRewardDelivery.offsetSettled;
  }
  if (!usesVouchers && reward.stage == ReferralRewardStage.paid) {
    if (balance?.cashKnown != true) {
      return ReferralRewardDelivery.settlementUnavailable;
    }
    if ((balance?.remainingPayable ?? 0) > 0) {
      return ReferralRewardDelivery.awaitingCredit;
    }
  }
  return referralRewardDelivery(reward.stage, usesVouchers: usesVouchers);
}

/// The friends list, narrowed to where a friend stands.
enum ReferralFriendsFilter {
  all,

  /// Not yet qualified.
  inProgress,

  /// Qualified and inside the earning window.
  earning,

  /// Qualified, window closed.
  ended;

  bool matches(ReferralFriend friend, ReferralOffer offer, {DateTime? now}) {
    if (this == ReferralFriendsFilter.all) return true;
    final next = referralFriendNextStep(friend, offer, now: now);
    switch (this) {
      case ReferralFriendsFilter.earning:
        return next == ReferralFriendNextStep.earning;
      case ReferralFriendsFilter.ended:
        return next == ReferralFriendNextStep.windowEnded;
      case ReferralFriendsFilter.inProgress:
        return next != ReferralFriendNextStep.earning &&
            next != ReferralFriendNextStep.windowEnded;
      case ReferralFriendsFilter.all:
        return true;
    }
  }
}

/// The reward ledger, narrowed to a delivery state. The wire names double as
/// the `status` query value on the earnings route.
enum ReferralEarningsFilter {
  all('all'),

  /// Pending, ready and crediting: earned but not in the balance.
  awaiting('awaiting'),

  /// In the balance, or claimed as a voucher.
  paid('paid'),

  /// With the operator.
  failed('failed');

  const ReferralEarningsFilter(this.wire);

  final String wire;

  static ReferralEarningsFilter fromWire(String? value) {
    for (final filter in values) {
      if (filter.wire == value?.trim().toLowerCase()) return filter;
    }
    return ReferralEarningsFilter.all;
  }

  bool matches(ReferralReward reward) {
    switch (this) {
      case ReferralEarningsFilter.all:
        return true;
      case ReferralEarningsFilter.awaiting:
        return reward.stage == ReferralRewardStage.pending ||
            reward.stage == ReferralRewardStage.ready ||
            reward.stage == ReferralRewardStage.crediting;
      case ReferralEarningsFilter.paid:
        return reward.stage == ReferralRewardStage.paid;
      case ReferralEarningsFilter.failed:
        return reward.stage == ReferralRewardStage.failed;
    }
  }
}
