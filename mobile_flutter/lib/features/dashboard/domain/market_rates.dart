class MarketRateTable {
  const MarketRateTable({
    required this.baseCurrency,
    required this.refreshedAt,
    required this.isStale,
    required this.isPartial,
    required this.missingSymbols,
    required this.rates,
  });

  factory MarketRateTable.fromJson(Map<String, dynamic> json) {
    final rows = json['rates'];
    final parsedRates = <String, MarketRate>{};
    if (rows is List) {
      for (final value in rows.whereType<Map>()) {
        final row = value.map(
          (key, item) => MapEntry(key.toString(), item),
        );
        final rate = MarketRate.fromJson(row);
        if (rate.symbol.isNotEmpty && rate.rate > 0) {
          parsedRates[rate.symbol] = rate;
        }
      }
    }

    final missing = json['missingSymbols'];
    return MarketRateTable(
      baseCurrency:
          (json['baseCurrency'] ?? 'USD').toString().trim().toUpperCase(),
      refreshedAt: DateTime.tryParse(json['refreshedAt']?.toString() ?? ''),
      isStale: json['isStale'] == true,
      isPartial: json['isPartial'] == true,
      missingSymbols: missing is List
          ? missing
              .map((value) => value.toString().trim().toUpperCase())
              .where((value) => value.isNotEmpty)
              .toList()
          : const [],
      rates: parsedRates,
    );
  }

  final String baseCurrency;
  final DateTime? refreshedAt;
  final bool isStale;
  final bool isPartial;
  final List<String> missingSymbols;
  final Map<String, MarketRate> rates;

  double? value(String symbol, double amount) {
    final rate = rates[symbol.trim().toUpperCase()]?.rate;
    return rate == null ? null : amount * rate;
  }
}

class MarketRate {
  const MarketRate({
    required this.symbol,
    required this.rate,
    required this.provider,
    required this.observedAt,
  });

  factory MarketRate.fromJson(Map<String, dynamic> json) => MarketRate(
        symbol: (json['symbol'] ?? '').toString().trim().toUpperCase(),
        rate: _doubleFromAny(json['rate']) ?? 0,
        provider: (json['provider'] ?? '').toString().trim(),
        observedAt: DateTime.tryParse(json['observedAt']?.toString() ?? ''),
      );

  final String symbol;
  final double rate;
  final String provider;
  final DateTime? observedAt;
}

double? _doubleFromAny(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.replaceAll(',', '.'));
  return null;
}
