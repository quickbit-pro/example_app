class CardControlCapabilities {
  const CardControlCapabilities({
    required this.canFreeze,
    required this.canRevealSecureData,
    required this.canSetPin,
    required this.canUpdateLimits,
    required this.canMerchantLock,
    required this.canControlOnlinePayments,
    required this.canControlContactless,
    required this.canControlAtm,
    required this.canControlInternational,
    required this.isMerchantLocked,
    required this.lockedMerchantName,
    required this.supportedActions,
    required this.limits,
    this.autoFreezeEnabled = false,
    this.autoFreezeActiveUntil,
  });

  factory CardControlCapabilities.fromJson(Map<String, dynamic> json) =>
      CardControlCapabilities(
        canFreeze: json['canFreeze'] == true,
        canRevealSecureData: json['canRevealSecureData'] == true,
        canSetPin: json['canSetPin'] == true,
        canUpdateLimits: json['canUpdateLimits'] == true,
        canMerchantLock: json['canMerchantLock'] == true,
        canControlOnlinePayments: json['canControlOnlinePayments'] == true,
        canControlContactless: json['canControlContactless'] == true,
        canControlAtm: json['canControlAtm'] == true,
        canControlInternational: json['canControlInternational'] == true,
        isMerchantLocked: json['isMerchantLocked'] == true,
        lockedMerchantName:
            (json['lockedMerchantName'] ?? '').toString().trim(),
        supportedActions: (json['supportedActions'] is List
                ? json['supportedActions'] as List
                : const [])
            .map((value) => value.toString())
            .toList(),
        limits: json['limits'] is Map
            ? (json['limits'] as Map)
                .map((key, value) => MapEntry(key.toString(), value))
            : const {},
        autoFreezeEnabled: json['autoFreezeEnabled'] == true ||
            json['AutoFreezeEnabled'] == true,
        autoFreezeActiveUntil: DateTime.tryParse(
            (json['autoFreezeActiveUntil'] ??
                    json['AutoFreezeActiveUntil'] ??
                    '')
                .toString()),
      );

  final bool canFreeze;
  final bool canRevealSecureData;
  final bool canSetPin;
  final bool canUpdateLimits;
  final bool canMerchantLock;
  final bool canControlOnlinePayments;
  final bool canControlContactless;
  final bool canControlAtm;
  final bool canControlInternational;
  final bool isMerchantLocked;
  final String lockedMerchantName;
  final List<String> supportedActions;
  final Map<String, dynamic> limits;

  /// The issuer's auto-lock switch for this card: while on, Hoppa freezes
  /// the card again by itself ten minutes after it is unfrozen.
  final bool autoFreezeEnabled;

  /// When the current unfreeze window ends; null while frozen or off.
  final DateTime? autoFreezeActiveUntil;

  bool get hasAdvancedControls =>
      canUpdateLimits ||
      canMerchantLock ||
      canControlOnlinePayments ||
      canControlContactless ||
      canControlAtm ||
      canControlInternational;

  double? limit(String key) {
    final value = limits[key] ?? limits[_pascalCase(key)];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }
}

String _pascalCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
