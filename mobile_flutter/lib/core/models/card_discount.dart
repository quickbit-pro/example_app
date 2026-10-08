/// The same card-pricing fields returned to the dashboard's cards page.
class CardDiscount {
  CardDiscount.fromJson(Map<String, dynamic> json)
      : isValid = json['isValid'] == true,
        errorMessage = json['errorMessage'] as String?,
        discountType =
            (json['discountType'] as String? ?? 'percent').toLowerCase(),
        _values = json;

  final bool isValid;
  final String? errorMessage;
  final String discountType;
  final Map<String, dynamic> _values;

  double? _number(String key) {
    final value = _values[key];
    return value is num ? value.toDouble() : double.tryParse('$value');
  }

  /// Fixed discounts are replacement prices, not amounts to subtract.
  double price(double base, String fee) {
    if (!isValid) return base;
    final fixed = _number('${fee}DiscountFixed');
    if (discountType == 'fixed' && fixed != null) return fixed;
    final percent = _number('${fee}DiscountPercent') ?? 0;
    return percent > 0 ? base * (1 - percent / 100) : base;
  }

  String? description(String fee) {
    if (!isValid) return null;
    if (discountType == 'fixed' && _number('${fee}DiscountFixed') != null) {
      return 'Fixed price';
    }
    final percent = _number('${fee}DiscountPercent') ?? 0;
    if (percent <= 0) return null;
    final text = percent == percent.roundToDouble()
        ? percent.toInt().toString()
        : percent.toString();
    return '$text% off';
  }
}
