class CryptoWithdrawalBalance {
  const CryptoWithdrawalBalance({
    required this.totalAvailableUsdt,
    required this.totalAvailableUsdc,
  });

  factory CryptoWithdrawalBalance.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    return CryptoWithdrawalBalance(
      totalAvailableUsdt: _number(
        data,
        const ['totalAvailableUSDT', 'TotalAvailableUSDT'],
      ),
      totalAvailableUsdc: _number(
        data,
        const ['totalAvailableUSDC', 'TotalAvailableUSDC'],
      ),
    );
  }

  final double totalAvailableUsdt;
  final double totalAvailableUsdc;

  double availableFor(String currency) => switch (currency.toUpperCase()) {
        'USDT' => totalAvailableUsdt,
        'USDC' => totalAvailableUsdc,
        _ => 0,
      };
}

class CryptoWithdrawalFee {
  const CryptoWithdrawalFee({
    required this.amount,
    required this.currency,
    required this.type,
  });

  factory CryptoWithdrawalFee.fromJson(Map<String, dynamic> json) =>
      CryptoWithdrawalFee(
        amount: _number(json, const ['amount', 'Amount']),
        currency: _text(json, const ['currency', 'Currency']),
        type: _text(json, const ['type', 'Type']),
      );

  final double amount;
  final String currency;
  final String type;
}

class CryptoWithdrawalQuote {
  const CryptoWithdrawalQuote({
    required this.code,
    required this.crossChainQuota,
    required this.crossChainFeeRate,
    required this.crossChainAmount,
    required this.fees,
    required this.message,
  });

  factory CryptoWithdrawalQuote.fromJson(Map<String, dynamic> json) {
    final root = _payload(json);
    final data = _map(root['data'] ?? root['Data']) ?? root;
    final rawFees = data['fees'] ?? data['Fees'];
    return CryptoWithdrawalQuote(
      code: _text(root, const ['code', 'Code']),
      crossChainQuota:
          _text(data, const ['crossChainQuota', 'CrossChainQuota']),
      crossChainFeeRate:
          _text(data, const ['crossChainFeeRate', 'CrossChainFeeRate']),
      crossChainAmount:
          _text(data, const ['crossChainAmount', 'CrossChainAmount']),
      fees: rawFees is List
          ? rawFees
              .map(_map)
              .whereType<Map<String, dynamic>>()
              .map(CryptoWithdrawalFee.fromJson)
              .toList()
          : const [],
      message: _text(root, const ['message', 'Message']),
    );
  }

  final String crossChainQuota;
  final String code;
  final String crossChainFeeRate;
  final String crossChainAmount;
  final List<CryptoWithdrawalFee> fees;
  final String message;

  bool get isSuccessful =>
      code.isEmpty || code == '000000' || code == '0' || code == '200';
}

class CryptoWithdrawalResult {
  const CryptoWithdrawalResult({
    required this.success,
    required this.otpRequired,
    required this.verificationToken,
    required this.status,
    required this.message,
    required this.transactionId,
    required this.otpExpiresAt,
    required this.fees,
  });

  factory CryptoWithdrawalResult.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    final rawFees = data['fees'] ?? data['Fees'];
    return CryptoWithdrawalResult(
      success: _boolean(data, const ['success', 'Success']),
      otpRequired: _boolean(data, const ['otpRequired', 'OtpRequired']),
      verificationToken:
          _text(data, const ['verificationToken', 'VerificationToken']),
      status: _text(data, const ['status', 'Status']),
      message: _text(data, const ['message', 'Message']),
      transactionId: _text(data, const ['transactionId', 'TransactionId']),
      otpExpiresAt: _dateTime(
        data['otpExpiresAt'] ?? data['OtpExpiresAt'] ?? data['expiresAt'],
      ),
      fees: rawFees is List
          ? rawFees
              .map(_map)
              .whereType<Map<String, dynamic>>()
              .map(CryptoWithdrawalFee.fromJson)
              .toList()
          : const [],
    );
  }

  final bool success;
  final bool otpRequired;
  final String verificationToken;
  final String status;
  final String message;
  final String transactionId;
  final DateTime? otpExpiresAt;
  final List<CryptoWithdrawalFee> fees;
}

class CryptoWithdrawalOtpResend {
  const CryptoWithdrawalOtpResend({
    required this.success,
    required this.message,
    required this.expiresAt,
  });

  factory CryptoWithdrawalOtpResend.fromJson(Map<String, dynamic> json) {
    final data = _payload(json);
    return CryptoWithdrawalOtpResend(
      success: _boolean(data, const ['success', 'Success']),
      message: _text(data, const ['message', 'Message']),
      expiresAt: _dateTime(data['expiresAt'] ?? data['ExpiresAt']),
    );
  }

  final bool success;
  final String message;
  final DateTime? expiresAt;
}

Map<String, dynamic> _payload(Map<String, dynamic> json) {
  final nested = _map(json['data'] ?? json['Data']);
  if (nested != null &&
      (nested.containsKey('Success') ||
          nested.containsKey('success') ||
          nested.containsKey('TotalAvailableUSDT') ||
          nested.containsKey('totalAvailableUSDT'))) {
    return nested;
  }
  return json;
}

Map<String, dynamic>? _map(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

String _text(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key]?.toString().trim();
    if (value != null && value.isNotEmpty) return value;
  }
  return '';
}

double _number(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return 0;
}

bool _boolean(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value?.toString().toLowerCase() == 'true') return true;
  }
  return false;
}

DateTime? _dateTime(Object? value) =>
    DateTime.tryParse(value?.toString() ?? '');
