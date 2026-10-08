import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/dashboard/data/display_currency_provider.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';

void main() {
  PortfolioEstimate quote(String currency, Map<String, double> rates) =>
      PortfolioEstimate.fromJson({
        'currency': currency,
        'valuationRates': [
          for (final entry in rates.entries)
            {'currency': entry.key, 'rate': entry.value},
        ]
      });

  test('display FX uses direct rates or a shared asset, never portfolio totals',
      () {
    final usd = quote('USD', {'USD': 1, 'USDC': .9999});
    expect(portfolioCrossRate(usd, quote('EUR', {'USD': .86})), .86);
    expect(portfolioCrossRate(usd, quote('EUR', {'EUR': 1, 'USDC': .859914})),
        closeTo(.86, .000001));
    expect(portfolioCrossRate(usd, quote('USD', {})), 1);
    expect(portfolioCrossRate(usd, quote('EUR', {'EUR': 1})), isNull);
  });
}
