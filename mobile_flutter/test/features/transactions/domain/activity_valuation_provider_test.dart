import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/dashboard/data/display_currency_provider.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/domain/market_rates.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/transactions/application/activity_valuation_provider.dart';

void main() {
  test(
      'Activity reuses Home FX, estimates stablecoins 1:1 and covers historical fiat',
      () async {
    final container = ProviderContainer(overrides: [
      portfolioEstimateProvider
          .overrideWith((ref) async => PortfolioEstimate.fromJson({
                'currency': 'USD',
                'valuationRates': [
                  {'currency': 'USDC', 'rate': .999},
                  {'currency': 'EUR', 'rate': 1.25},
                ],
              })),
      marketRatesProvider.overrideWith((ref) async => MarketRateTable.fromJson({
            'baseCurrency': 'USD',
            'rates': [
              {'symbol': 'AED', 'rate': .27}
            ],
          })),
      homeDisplayRateProvider.overrideWith((ref) async {
        final code = ref.watch(homeDisplayCurrencyProvider);
        return (currency: code, rate: code == 'EUR' ? .8 : 1.0);
      }),
    ]);
    addTearDown(container.dispose);
    await container.read(portfolioEstimateProvider.future);
    await container.read(marketRatesProvider.future);
    await container.read(homeDisplayRateProvider.future);
    expect(container.read(activityValuationProvider)['USDC'], 1);
    container.read(homeDisplayCurrencyProvider.notifier).state = 'EUR';
    await container.read(homeDisplayRateProvider.future);
    final rates = container.read(activityValuationProvider);
    expect(rates['EUR'], 1);
    expect(rates['USD'], .8);
    expect(rates['USDC'], .8);
    expect(rates['USDT'], .8);
    expect(rates['AED'], closeTo(.216, .00001));
  });
}
