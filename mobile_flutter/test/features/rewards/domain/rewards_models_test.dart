import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  test('tenant configuration fails closed and parses referral mode', () {
    final config = MobileTenantConfig.fromJson(const {
      'company': {'name': 'Acme Ltd', 'brandName': 'Acme Pay'},
      'features': {
        'referralsEnabled': true,
        'referralRegistrationMode': 'required',
        'vouchersEnabled': false,
      },
    });

    expect(config.brandName, 'Acme Pay');
    expect(config.referralsEnabled, isTrue);
    expect(config.referralRequired, isTrue);
    expect(config.vouchersEnabled, isFalse);
    expect(config.boomFiExchangeEnabled, isFalse);
    expect(config.walletOutflowsEnabled, isFalse);
    expect(config.equalsMoneyEnabled, isTrue);
  });

  test('company configuration controls feature visibility', () {
    final config = MobileTenantConfig.fromJson(const {
      'features': {
        'referralsEnabled': true,
        'vouchersEnabled': true,
      },
    });
    final snapshot = RewardsSnapshot(
      config: config,
      referralSummary: const {'Enabled': false},
      voucherStatus: const {'enabled': false},
    );

    expect(snapshot.referralsEnabled, isTrue);
    expect(snapshot.vouchersEnabled, isTrue);
  });
}
