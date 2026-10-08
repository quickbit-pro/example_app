import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/domain/tier_includes.dart';

void main() {
  group('tierPlanIncludesOf', () {
    test('reads the provider tier: price, prose, features and flags', () {
      final includes = tierPlanIncludesOf(PlatformResource.fromJson(const {
        'Id': 3,
        'Name': 'Hoppa Premium',
        'Description': 'Designed for everyday use.',
        'AccountType': 'personal',
        'MonthlyFee': 1,
        'YearlyFee': 10.5,
        'Features': [
          'Lower fees than Lite on account payments',
          'crypto_enabled_card',
          '',
        ],
        'IncludesEqualsIban': true,
        'IncludesEqualsCards': true,
      }));

      expect(includes.monthlyFee, 1);
      expect(includes.yearlyFee, 10.5);
      expect(includes.description, 'Designed for everyday use.');
      // Sentences stay as written; machine tokens become words.
      expect(includes.features, [
        'Lower fees than Lite on account payments',
        'Crypto Enabled Card',
      ]);
      expect(includes.includesIban, isTrue);
      expect(includes.hasBenefits, isTrue);
    });

    test('respects hidden prices and falls back to a flat price', () {
      final hidden = tierPlanIncludesOf(PlatformResource.fromJson(const {
        'monthlyFee': '9.99',
        'yearlyFee': '99.99',
        'hideMonthlyFee': 'true',
      }));
      expect(hidden.monthlyFee, isNull);
      expect(hidden.yearlyFee, 99.99);

      final flat = tierPlanIncludesOf(
          PlatformResource.fromJson(const {'price': '4', 'currency': 'EUR'}));
      expect(flat.monthlyFee, 4);
      expect(flat.currency, 'EUR');

      final none = tierPlanIncludesOf(PlatformResource.fromJson(const {}));
      expect(none.hasPrice, isFalse);
      expect(none.hasBenefits, isFalse);
    });
  });

  group('tierCardOffersOf', () {
    // The shape of GET tiers/card-tier/{tierId}.
    final payload = PlatformResource.fromJson(const {
      'CardTypeTiers': [
        {
          'CardTypeSecondaryId': 11,
          'CardTypeId': 3,
          'TierId': 7,
          'FreeCardsIncluded': 1,
          'FreeCardsPeriod': 'lifetime',
          'MonthlySubscriptionFee': null,
          'MaxCards': 10,
          'IsActive': true,
          'CardType': {
            'Id': 3,
            'Name': 'Hoppa Virtual',
            'Description': 'Spend your crypto anywhere.',
            'Features': ['Contactless Payment', 'GOOGLE_PAY'],
            'BaseFeatures': ['contactless payment', 'atm_withdrawal'],
            'MonthlyFee': 0.1,
            'IssuanceFee': 0.1,
            'MonthlySubscriptionFee': '0.10',
            'ReplacementFee': 5,
            'AtmWithdrawalFee': 2,
            'CurrencyCode': 'usd',
            'IsEnabled': true,
            'IsVirtual': true,
            'IsPhysical': false,
            'CardThumbnailUrl': 'https://cdn.example/thumb.png',
          },
        },
        {
          'CardTypeId': 4,
          'IsActive': false,
          'CardType': {'Id': 4, 'Name': 'Retired card', 'IsEnabled': true},
        },
        {
          'CardTypeId': 5,
          'IsActive': true,
          'CardType': {'Id': 5, 'Name': 'Switched off', 'IsEnabled': false},
        },
      ],
    });

    test('keeps only live programmes and reads their allowances and fees', () {
      final offers = tierCardOffersOf(payload);

      expect(offers.map((offer) => offer.name), ['Hoppa Virtual']);
      final offer = offers.single;
      expect(offer.isVirtual, isTrue);
      expect(offer.freeCards, 1);
      expect(offer.freeCardsPeriod, 'lifetime');
      expect(offer.maxCards, 10);
      expect(offer.currency, 'USD');
      expect(offer.issuanceFee, 0.1);
      expect(offer.planMonthlyFee, isNull);
      expect(offer.cardMonthlyFee, 0.1);
      expect(offer.serviceFee, 0.1);
      expect(offer.replacementFee, 5);
      expect(offer.atmWithdrawalFee, 2);
      expect(offer.imageUrl, 'https://cdn.example/thumb.png');
      // Features, base features and tokens merge into one list of words.
      expect(offer.features, [
        'Contactless Payment',
        'Google Pay',
        'ATM Withdrawal',
      ]);
    });

    test('reads a data wrapper and ignores anything that is not a card', () {
      expect(
        tierCardOffersOf(PlatformResource.fromJson(const {
          'data': {
            'cardTypeTiers': [
              {
                'cardType': {'name': 'Equals Card', 'isVirtual': true},
              },
              'noise',
              {'cardType': <String, Object?>{}},
            ],
          },
        })).map((offer) => offer.name),
        ['Equals Card'],
      );
      expect(tierCardOffersOf(PlatformResource.fromJson(const {})), isEmpty);
    });
  });
}
