import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/dashboard/domain/market_rates.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';

void main() {
  test('parses provider timestamps and values balances in the base currency',
      () {
    final table = MarketRateTable.fromJson({
      'baseCurrency': 'USD',
      'refreshedAt': '2026-09-01T08:00:00Z',
      'isStale': false,
      'isPartial': true,
      'missingSymbols': ['ZMW'],
      'rates': [
        {
          'symbol': 'GBP',
          'rate': 1.31,
          'provider': 'wise',
          'observedAt': '2026-09-01T07:59:00Z',
        },
      ],
    });

    expect(table.baseCurrency, 'USD');
    expect(table.value('gbp', 10), closeTo(13.1, 0.000001));
    expect(table.value('AED', 10), isNull);
    expect(table.isPartial, isTrue);
    expect(table.missingSymbols, ['ZMW']);
    expect(table.rates['GBP']?.provider, 'wise');
  });

  test('parses the normalized Hoppa portfolio estimate', () {
    final estimate = PortfolioEstimate.fromJson({
      'currency': 'usd',
      'total': 24562.35,
      'valuedAt': '2026-09-01T08:00:00Z',
      'isPartial': true,
      'missingCurrencies': ['ZMW'],
    });

    expect(estimate.baseCurrency, 'USD');
    expect(estimate.total, 24562.35);
    expect(estimate.valuedAt, DateTime.utc(2026, 9, 1, 8));
    expect(estimate.isPartial, isTrue);
    expect(estimate.missingCurrencies, ['ZMW']);
  });
}
