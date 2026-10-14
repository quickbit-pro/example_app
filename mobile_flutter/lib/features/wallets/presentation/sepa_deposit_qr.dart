import 'dart:convert';

/// EPC069-12 v3.1: UTF-8, SCT version 002, no preselected transfer amount.
/// Never truncate beneficiary or payment reference to make a payload fit.
String? sepaDepositQr({
  required String iban,
  required String beneficiary,
  String bic = '',
  String paymentReference = '',
}) {
  if ([iban, beneficiary, bic, paymentReference]
      .any((value) => RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))) {
    return null;
  }
  iban = iban.replaceAll(' ', '').toUpperCase();
  beneficiary = beneficiary.trim();
  bic = bic.trim().toUpperCase();
  paymentReference = paymentReference.trim();
  if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$').hasMatch(iban) ||
      beneficiary.isEmpty ||
      beneficiary.runes.length > 70 ||
      paymentReference.runes.length > 140 ||
      (bic.isNotEmpty &&
          !RegExp(r'^[A-Z]{6}[A-Z0-9]{2}([A-Z0-9]{3})?$').hasMatch(bic))) {
    return null;
  }
  // BIC is mandatory outside the EEA. Requiring it everywhere avoids an
  // incomplete payload when the bank country is not available.
  if (bic.isEmpty) return null;
  final rearranged = '${iban.substring(4)}${iban.substring(0, 4)}';
  var remainder = 0;
  for (final code in rearranged.codeUnits) {
    final digits =
        code >= 65 ? (code - 55).toString() : String.fromCharCode(code);
    for (final digit in digits.codeUnits) {
      remainder = (remainder * 10 + digit - 48) % 97;
    }
  }
  if (remainder != 1) return null;
  final lines = [
    'BCD',
    '002',
    '1',
    'SCT',
    bic,
    beneficiary,
    iban,
    '',
    '',
    '',
    paymentReference
  ];
  while (lines.last.isEmpty) {
    lines.removeLast();
  }
  final payload = lines.join('\n');
  return utf8.encode(payload).length <= 331 ? payload : null;
}
