import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../dashboard/data/display_currency_provider.dart';
import '../../platform/application/platform_providers.dart';

/// The same display unit and quote as Home. Market rates also cover historical
/// currencies that the customer no longer holds in the current portfolio.
final activityValuationProvider = Provider<Map<String, double>>((ref) {
  final currency = ref.watch(homeDisplayCurrencyProvider);
  final portfolio = ref.watch(portfolioEstimateProvider).valueOrNull;
  final quote = ref.watch(homeDisplayRateProvider).valueOrNull;
  final market = ref.watch(marketRatesProvider).valueOrNull;
  final factor = currency == 'USD'
      ? 1.0
      : quote?.currency == currency
          ? quote?.rate
          : null;
  if (factor == null) return {currency: 1};
  final usdRates = <String, double>{
    if (market?.baseCurrency == 'USD')
      for (final entry in market!.rates.entries) entry.key: entry.value.rate,
    if (portfolio?.baseCurrency == 'USD') ...portfolio!.valuationRates,
    'USD': 1,
    'USDT': 1,
    'USDC': 1,
  };
  return {
    for (final entry in usdRates.entries) entry.key: entry.value * factor,
    currency: 1,
  };
});
