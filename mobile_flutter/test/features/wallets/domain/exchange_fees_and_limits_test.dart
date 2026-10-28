import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';

void main() {
  test(
      'converts provider rates to exact percentages including zero and tiny rates',
      () {
    for (final entry in {
      '0.01': '1',
      '0.005': '0.5',
      '0': '0',
      '1': '100',
      '1e-8': '0.000001',
      '0.01234567890123456789': '1.234567890123456789'
    }.entries) {
      final fees =
          BoomFiFeesAndLimits.fromJson({'withdraw_fee_rate': entry.key});
      expect(fees.withdrawFeePercentage, entry.value);
      expect(fees.descriptions('EUR', withdrawal: true),
          contains('Variable withdrawal fee: ${entry.value}%'));
    }
    expect(const BoomFiFeesAndLimits().withdrawFeePercentage, isNull);
    expect(
        BoomFiFeesAndLimits.fromJson({'withdraw_fee_rate': 'invalid'})
            .withdrawFeePercentage,
        isNull);
  });

  test('account fallback matches the network and never inherits a parent', () {
    final overview = BoomFiExchangeOverview.fromJson({
      'account': {
        'id': 1,
        'fees_and_limits': {'min_withdraw': '99'},
        'sub_accounts': [
          {
            'id': 2,
            'chain_id': 1,
            'fees_and_limits': {'min_withdraw': '5'}
          },
        ]
      },
      'balances': {
        'balances': [
          {
            'account_id': 2,
            'currency': 'USDC',
            'chain': {'id': 1}
          },
          {
            'account_id': 2,
            'currency': 'USDC',
            'chain': {'id': -200}
          },
          {'account_id': 3, 'currency': 'EUR'},
        ]
      },
    });
    expect(overview.feesFor(overview.balances[0])!.minWithdraw, '5');
    expect(overview.feesFor(overview.balances[1]), isNull);
    expect(overview.feesFor(overview.balances[2]), isNull);
  });

  test(
      'parses provider strings and numeric values without replacing unknowns by zero',
      () {
    final fees = BoomFiFeesAndLimits.fromJson({
      'min_deposit': '1',
      'min_withdraw': 5,
      'withdraw_fee': '1',
      'withdraw_fee_rate': '0',
      'max_withdraw': '100',
      'max_deposit': 'NaN',
    });
    expect(fees.minDeposit, '1');
    expect(fees.minWithdraw, '5');
    expect(fees.withdrawFeeRate, '0');
    expect(fees.maxDeposit, isNull);
    expect(fees.validate('0.99', 'EUR', withdrawal: false),
        'Minimum deposit is 1 EUR.');
    expect(fees.validate('1', 'EUR', withdrawal: false), isNull);
    expect(fees.validate('4.999999999999999999', 'USDC', withdrawal: true),
        'Minimum withdrawal is 5 USDC.');
    expect(fees.validate('5', 'USDC', withdrawal: true), isNull);
    expect(fees.validate('100', 'USDC', withdrawal: true), isNull);
    expect(fees.validate('100.000000000000000001', 'USDC', withdrawal: true),
        'Maximum withdrawal is 100 USDC.');
    expect(fees.validate('5,00', 'USDC', withdrawal: true), isNull);
  });

  test(
      'malformed absent and negative fields remain unknown; explicit zero is retained',
      () {
    final fees = BoomFiFeesAndLimits.fromJson({
      'min_deposit': '-1',
      'max_deposit': 'Infinity',
      'min_withdraw': {},
      'withdraw_fee': 0,
      'max_withdraw': 0,
    });
    expect(fees.minDeposit, isNull);
    expect(fees.maxDeposit, isNull);
    expect(fees.minWithdraw, isNull);
    expect(fees.withdrawFee, '0');
    expect(fees.validate('1', 'EUR', withdrawal: true),
        'Maximum withdrawal is 0 EUR.');
    expect(
        const BoomFiFeesAndLimits()
            .validate('100000', 'EUR', withdrawal: false),
        isNull);
    expect(
        const BoomFiFeesAndLimits()
            .descriptions('EUR', withdrawal: true)
            .single,
        contains('unavailable'));
  });

  test('accepts supported naming variants and exponent-form JSON numbers', () {
    final fees =
        BoomFiFeesAndLimits.fromJson({'minDeposit': 1e-8, 'MaxWithdraw': '5'});
    expect(fees.validate('0.000000009', 'USDC', withdrawal: false), isNotNull);
    expect(fees.validate('0.00000001', 'USDC', withdrawal: false), isNull);
    expect(fees.maxWithdraw, '5');
  });

  test('shows fixed fee and confirmed percentage without assuming a total', () {
    final fees = BoomFiFeesAndLimits.fromJson(
        {'withdraw_fee': '1', 'withdraw_fee_rate': '0.01'});
    expect(fees.descriptions('EUR', withdrawal: true), [
      'Fixed withdrawal fee: 1 EUR',
      'Variable withdrawal fee: 1%',
    ]);
  });

  test(
      'overview uses exact accounts and distinct funding rails, never sibling limits',
      () {
    final overview = BoomFiExchangeOverview.fromJson({
      'account': {
        'id': 10,
        'fees_and_limits': {'min_withdraw': '50'},
        'sub_accounts': [
          {
            'id': 20,
            'fees_and_limits': {'min_withdraw': '5'}
          },
          {'id': 21},
        ]
      },
      'fiat_funding_fees_and_limits': {
        'EUR': {'min_deposit': '3'}
      },
      'balances': {
        'balances': [
          {'account_id': 10, 'currency': 'EUR'},
          {
            'account_id': 20,
            'currency': 'USDC',
            'chain': {'id': 1},
            'fees_and_limits': {'min_withdraw': '6'}
          },
          {
            'account_id': 21,
            'currency': 'USDC',
            'chain': {'id': -200}
          },
        ]
      },
    });
    expect(overview.feesFor(overview.balances[0])!.minWithdraw, '50');
    expect(overview.feesFor(overview.balances[1])!.minWithdraw, '6');
    expect(overview.feesFor(overview.balances[2]), isNull);
    expect(overview.fiatFundingFeesAndLimits['EUR']!.minDeposit, '3');
    expect(overview.fiatFundingFeesAndLimits['USD'], isNull);
  });
}
