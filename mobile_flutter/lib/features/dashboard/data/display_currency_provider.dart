import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/application/platform_providers.dart';
import '../domain/dashboard_models.dart';

final homeDisplayCurrencyProvider = StateProvider<String>((ref) => 'USD');

/// Reuse the USD estimate used elsewhere. Only a different Home display unit
/// needs another quote; unrelated account and transaction data stays cached.
final homeDisplayRateProvider =
    FutureProvider<({String currency, double? rate})>((ref) async {
  final currency = ref.watch(homeDisplayCurrencyProvider);
  if (currency == 'USD') return (currency: currency, rate: 1.0);
  final api = ref.watch(mobilePlatformApiProvider);
  final base = await ref.watch(portfolioEstimateProvider.future);
  try {
    final quote = await api.getPortfolioEstimate(currency: currency);
    if (quote.baseCurrency != currency) return (currency: currency, rate: null);
    return (currency: currency, rate: portfolioCrossRate(base, quote));
  } on DioException {
    return (currency: currency, rate: null);
  }
});

/// Both responses value the same asset in different currencies. Comparing
/// their per-unit rates cancels its native amount and gives the display FX rate.
double? portfolioCrossRate(PortfolioEstimate base, PortfolioEstimate quote) {
  if (base.baseCurrency == quote.baseCurrency) return 1;
  final direct = quote.valuationRates[base.baseCurrency];
  if (direct != null && direct.isFinite && direct > 0) return direct;
  for (final entry in base.valuationRates.entries) {
    final target = quote.valuationRates[entry.key];
    if (target == null ||
        !target.isFinite ||
        target <= 0 ||
        !entry.value.isFinite ||
        entry.value <= 0) {
      continue;
    }
    final rate = target / entry.value;
    if (rate.isFinite && rate > 0) return rate;
  }
  return null;
}
