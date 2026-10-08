class ReferralInvitationPreview {
  const ReferralInvitationPreview({
    required this.email,
    required this.referralCode,
    required this.inviterDisplayName,
    required this.expiresAt,
    this.welcomeAmount = 0,
    this.welcomeCurrency = 'USD',
    this.termsVersion,
  });

  factory ReferralInvitationPreview.fromJson(Map<String, dynamic> json) {
    return ReferralInvitationPreview(
      email: _requiredText(json, 'email'),
      referralCode: _requiredText(json, 'referralCode'),
      inviterDisplayName: _requiredText(json, 'inviterDisplayName'),
      expiresAt: DateTime.parse(_requiredText(json, 'expiresAt')).toUtc(),
      welcomeAmount: _number(json['welcomeAmount']) ?? 0,
      welcomeCurrency: _optionalText(json['welcomeCurrency']) ?? 'USD',
      termsVersion: _number(json['termsVersion'])?.round(),
    );
  }

  final String email;
  final String referralCode;
  final String inviterDisplayName;
  final DateTime expiresAt;

  /// Welcome reward the invitee earns at qualification; 0 when the programme
  /// pays none or the backend predates the field.
  final double welcomeAmount;
  final String welcomeCurrency;

  /// Terms version the invitee accepts by registering; echoed back as
  /// `referralTermsVersion`. Null when the backend predates the field.
  final int? termsVersion;

  bool get hasWelcome => welcomeAmount > 0;
}

enum ReferralInvitationFailureType { invalid, expired, network }

class ReferralInvitationFailure implements Exception {
  const ReferralInvitationFailure(this.type);

  final ReferralInvitationFailureType type;

  @override
  String toString() => 'Referral invitation could not be resolved.';
}

String _requiredText(Map<String, dynamic> json, String key) {
  final value = json[key]?.toString().trim();
  if (value == null || value.isEmpty) {
    throw const FormatException('Invalid referral invitation response.');
  }
  return value;
}

String? _optionalText(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

double? _number(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value.trim());
  return null;
}
