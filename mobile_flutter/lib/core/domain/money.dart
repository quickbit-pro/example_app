class MoneyAmount {
  const MoneyAmount({
    required this.minorUnits,
    required this.currencyCode,
  });

  final int minorUnits;
  final String currencyCode;

  bool get isNegative => minorUnits < 0;

  String get formatted {
    final absolute = minorUnits.abs();
    final major = absolute ~/ 100;
    final cents = (absolute % 100).toString().padLeft(2, '0');
    final sign = isNegative ? '-' : '';

    return '$sign$currencyCode $major.$cents';
  }
}
