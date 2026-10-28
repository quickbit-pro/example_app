/// Account-scoped provider values. Unknown values stay unknown, never zero.
class BoomFiFeesAndLimits {
  const BoomFiFeesAndLimits(
      {this.minDeposit,
      this.maxDeposit,
      this.minWithdraw,
      this.maxWithdraw,
      this.withdrawFee,
      this.withdrawFeeRate});

  factory BoomFiFeesAndLimits.fromJson(Map<String, dynamic> json) {
    String? read(String snake, String camel, String pascal) {
      final raw = json[snake] ?? json[camel] ?? json[pascal];
      final text = raw?.toString().trim();
      return text != null && _Amount.parse(text) != null ? text : null;
    }

    return BoomFiFeesAndLimits(
      minDeposit: read('min_deposit', 'minDeposit', 'MinDeposit'),
      maxDeposit: read('max_deposit', 'maxDeposit', 'MaxDeposit'),
      minWithdraw: read('min_withdraw', 'minWithdraw', 'MinWithdraw'),
      maxWithdraw: read('max_withdraw', 'maxWithdraw', 'MaxWithdraw'),
      withdrawFee: read('withdraw_fee', 'withdrawFee', 'WithdrawFee'),
      withdrawFeeRate:
          read('withdraw_fee_rate', 'withdrawFeeRate', 'WithdrawFeeRate'),
    );
  }

  final String? minDeposit, maxDeposit, minWithdraw, maxWithdraw;
  final String? withdrawFee, withdrawFeeRate;
  // Confirmed by BoomFi: 0.01 represents 1%.
  String? get withdrawFeePercentage => withdrawFeeRate == null
      ? null
      : _Amount.parse(withdrawFeeRate!)?.asPercentage();

  bool get hasWithdrawalLimits => minWithdraw != null || maxWithdraw != null;

  String? validate(String amount, String currency, {required bool withdrawal}) {
    final value = _Amount.parse(amount.replaceAll(',', '.'));
    if (value == null) return 'Enter a valid amount.';
    final min = withdrawal ? minWithdraw : minDeposit;
    final max = withdrawal ? maxWithdraw : maxDeposit;
    final action = withdrawal ? 'withdrawal' : 'deposit';
    if (min != null && value.compareTo(_Amount.parse(min)!) < 0) {
      return 'Minimum $action is $min $currency.';
    }
    if (max != null && value.compareTo(_Amount.parse(max)!) > 0) {
      return 'Maximum $action is $max $currency.';
    }
    return null;
  }

  List<String> descriptions(String currency, {required bool withdrawal}) {
    final min = withdrawal ? minWithdraw : minDeposit;
    final max = withdrawal ? maxWithdraw : maxDeposit;
    final action = withdrawal ? 'withdrawal' : 'deposit';
    return [
      if (min != null) 'Minimum $action: $min $currency',
      if (max != null) 'Maximum $action: $max $currency',
      if (withdrawal) ...[
        if (withdrawFee != null) 'Fixed withdrawal fee: $withdrawFee $currency',
        if (withdrawFee == null)
          'Withdrawal fee unavailable. The provider may charge a fee.',
        if (withdrawFeePercentage != null)
          'Variable withdrawal fee: $withdrawFeePercentage%',
      ],
    ];
  }
}

// Compare decimal strings exactly, including tiny crypto amounts at a boundary.
// A double comparison can round an amount just outside a limit onto the limit.
class _Amount {
  const _Amount(this.units, this.scale);
  final BigInt units;
  final int scale;

  static _Amount? parse(String text) {
    if (text.length > 200) return null;
    if (text.startsWith('.')) text = '0$text';
    final match =
        RegExp(r'^\+?(\d+)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$').firstMatch(text);
    if (match == null) return null;
    final fraction = match[2] ?? '';
    final exponent = int.tryParse(match[3] ?? '0');
    if (exponent == null || exponent.abs() > 100) return null;
    final units = BigInt.parse('${match[1]}$fraction');
    final scale = fraction.length - exponent;
    return scale < 0
        ? _Amount(units * BigInt.from(10).pow(-scale), 0)
        : _Amount(units, scale);
  }

  String asPercentage() {
    final digits =
        (units * BigInt.from(100)).toString().padLeft(scale + 1, '0');
    if (scale == 0) return digits;
    final split = digits.length - scale;
    final formatted = '${digits.substring(0, split)}.${digits.substring(split)}'
        .replaceFirst(RegExp(r'0+$'), '');
    return formatted.endsWith('.')
        ? formatted.substring(0, formatted.length - 1)
        : formatted;
  }

  int compareTo(_Amount other) {
    final common = scale > other.scale ? scale : other.scale;
    return (units * BigInt.from(10).pow(common - scale))
        .compareTo(other.units * BigInt.from(10).pow(common - other.scale));
  }
}
