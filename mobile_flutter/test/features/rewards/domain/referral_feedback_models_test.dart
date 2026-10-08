import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_copy.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_lifecycle.dart';
import 'package:mobile_flutter/features/rewards/domain/referral_member_status.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/domain/referral_quote.dart';

void main() {
  test(
      'forecast parses server time and dual progress without inventing protection',
      () {
    final value = ReferralLevelLifecycle.fromJson({
      'programId': 'p',
      'asOf': '2026-09-15T12:00:00Z',
      'currentLevel': {'name': 'Elite', 'topupRate': '50'},
      'progress': {
        'qualifiedReferrals': 4,
        'topupVolume': '80',
        'nextMinimumQualifiedReferrals': 5,
        'nextMinimumTopupVolume': '100'
      },
      'forecast': {
        'effectiveAt': '2026-09-18T12:00:00Z',
        'daysUntil': 3,
        'level': {'name': 'Starter'},
        'reason': 'LOOKBACK_EXPIRY'
      },
    });
    expect(value.currentLevel?.name, 'Elite');
    expect(value.forecast?.daysUntil, 3);
    expect(value.existingOffersProtected, isFalse);
    expect(value.progress.nextConditions, hasLength(2));
  });

  test('missing observation is not replaced with the client clock', () {
    expect(() => ReferralLevelLifecycle.fromJson({}), throwsFormatException);
  });

  test('partial cash and offsets remain separate from earned amount', () {
    final reward = ReferralReward.fromJson({
      'amount': '0.006',
      'currency': 'USD',
      'status': 'PAID',
      'balance': {
        'cashPaid': '0.004',
        'offsetSettled': '0',
        'reservedCash': '0',
        'remainingPayable': '0.002',
        'legacyCashUnknown': false
      }
    });
    expect(reward.balance?.remainingPayable, 0.002);
    expect(referralRewardEvidenceDelivery(reward, usesVouchers: false),
        ReferralRewardDelivery.awaitingCredit);
  });

  test('decimal string settlement evidence preserves its exact wire precision',
      () {
    final balance = ReferralRewardBalance.fromJson({
      'CashPaid': '123456789012.12345678',
      'OffsetSettled': '0.00000001',
      'ReservedCash': '1.23000000',
      'RemainingPayable': '0.00000002',
      'LegacyCashUnknown': false,
    });
    expect(balance.cashPaidText, '123456789012.12345678');
    expect(balance.offsetSettledText, '0.00000001');
    expect(balance.reservedCashText, '1.23000000');
    expect(balance.remainingPayableText, '0.00000002');
    expect(balance.cashKnown, isTrue);
  });

  test('only explicit pre-creation rejection releases the frozen attempt', () {
    expect(canRestartReferralSignup('auth.password.weak'), isTrue);
    expect(canRestartReferralSignup('auth.referral.validation_failed'), isTrue);
    for (final reason in [
      null,
      'auth.signup.creation_uncertain',
      'auth.signup.hoppa_user_missing_id',
      'auth.signup.provider_unavailable',
      'auth.signup.account_exists',
      'NETWORK_ERROR'
    ]) {
      expect(canRestartReferralSignup(reason), isFalse, reason: reason);
    }
  });

  test('quote snapshots boost terms and rejects a non-quoted receipt', () {
    final wire = <String, dynamic>{
      'quoteId': 'q',
      'registrationAttemptId': 'a',
      'termsVersion': 3,
      'termsText': 'Original offer',
      'termsHash': 't',
      'policyHash': 'p',
      'expiresAt': '2026-09-15T12:00:00Z',
      'status': 'QUOTED',
      'eligibilityNotice': 'Original eligibility notice',
      'boosts': [
        {
          'name': 'September',
          'kind': 'MULTIPLIER',
          'multiplier': '2',
          'startsAt': '2026-09-15T00:00:00Z',
          'endsAt': '2026-09-16T00:00:00Z',
          'maximumIncrementalReward': '5.25',
          'currency': 'USD',
        }
      ],
    };
    final quote = ReferralQuote.fromJson(wire);
    expect(quote.eligibilityNotice, 'Original eligibility notice');
    expect(quote.boosts.single.multiplier, 2);
    expect(quote.boosts.single.maximumIncrementalReward, 5.25);
    expect(() => ReferralQuote.fromJson({...wire, 'status': 'REJECTED'}),
        throwsFormatException);
  });

  test('legacy paid ledger is not evidence of actual cash', () {
    final reward = ReferralReward.fromJson({'amount': 7, 'status': 'PAID'});
    expect(referralRewardEvidenceDelivery(reward, usesVouchers: false),
        ReferralRewardDelivery.settlementUnavailable);
  });

  test('offset-only settlement never says cash credited', () {
    final reward = ReferralReward.fromJson({
      'amount': 7,
      'status': 'PAID',
      'balance': {
        'cashPaid': 0,
        'offsetSettled': 7,
        'reservedCash': 0,
        'remainingPayable': 0,
        'legacyCashUnknown': false
      }
    });
    expect(referralRewardEvidenceDelivery(reward, usesVouchers: false),
        ReferralRewardDelivery.offsetSettled);
  });

  test('a hold wins over the voucher READY stage', () {
    final reward = ReferralReward.fromJson({
      'amount': 7,
      'stage': 'READY',
      'status': 'HELD',
      'holdReasons': ['FRAUD_REVIEW'],
      'releaseAt': '2026-09-20T00:00:00Z'
    });
    expect(referralRewardEvidenceDelivery(reward, usesVouchers: true),
        ReferralRewardDelivery.held);
  });

  test('eligibility pending and accepted translation are distinct', () {
    final status = ReferralGeoStatus.fromJson({
      'attributed': true,
      'eligibility': {
        'status': 'PENDING',
        'canQualify': false,
        'canPayout': false
      },
      'acceptedTerms': {
        'locale': 'fr',
        'termsVersion': 3,
        'text': 'Conditions acceptées',
        'contentHash': 'original-hash',
        'acceptedAt': '2026-09-15T10:00:00Z'
      }
    });
    expect(status.canPayout, isFalse);
    expect(status.acceptedTerms, 'Conditions acceptées');
    expect(status.acceptedLocale, 'fr');
    expect(() => ReferralGeoStatus.fromJson({}), throwsFormatException);
  });

  test('quote rejects incomplete consent evidence and expires at boundary', () {
    expect(
        () => ReferralQuote.fromJson({'quoteId': 'a'}), throwsFormatException);
    final quote = ReferralQuote.fromJson({
      'quoteId': 'q',
      'registrationAttemptId': 'a',
      'termsVersion': 3,
      'termsText': 'Accepted text',
      'termsHash': 't',
      'policyHash': 'p',
      'expiresAt': '2026-09-15T12:00:00Z'
    });
    expect(quote.isExpired(DateTime.utc(2026, 9, 15, 12)), isTrue);
    expect(quote.isExpired(DateTime.utc(2026, 9, 15, 11, 59, 59)), isFalse);
  });

  test('account creation is not an attribution success', () {
    final outcome = ReferralSignupOutcome.fromJson(
        {'message': 'Account created', 'referralAttributed': true});
    expect(outcome.state, ReferralSignupState.unavailable);
    expect(
        ReferralSignupOutcome.fromJson({'referralAttributionStatus': 'PENDING'})
            .state,
        ReferralSignupState.pending);
    expect(
        ReferralSignupOutcome.fromJson({
          'referralAttributionStatus': 'NEEDS_REVIEW',
          'referralCommandId': 'c'
        }).correlationId,
        'c');
  });
}
