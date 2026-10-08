const nicknameRules =
    'Use 3–30 letters, numbers or underscores, starting with a letter.';

String normalizeNickname(String value) {
  final trimmed = value.trim();
  return (trimmed.startsWith('@') ? trimmed.substring(1) : trimmed)
      .toLowerCase();
}

bool isValidNickname(String value) =>
    RegExp(r'^[a-z][a-z0-9_]{2,29}$').hasMatch(value);

bool isNicknameLookup(String value) =>
    value.startsWith('@') ||
    (!value.contains('@') && RegExp(r'[a-zA-Z_]').hasMatch(value));

String? recipientLookupProblem(String query) {
  if (query.isEmpty) return 'Enter a nickname, email address or phone number.';
  if (isNicknameLookup(query)) {
    return isValidNickname(normalizeNickname(query)) ? null : nicknameRules;
  }
  if (query.contains('@')) {
    return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(query)
        ? null
        : 'Enter a valid email address.';
  }
  if (!RegExp(r'^[+\d\s().-]+$').hasMatch(query)) {
    return 'Enter a valid nickname, email address or phone number.';
  }
  final phone = query.replaceAll(RegExp(r'[\s().-]'), '');
  final digits = phone.startsWith('00')
      ? phone.substring(2)
      : phone.startsWith('+')
          ? phone.substring(1)
          : phone;
  return RegExp(r'^\d{6,15}$').hasMatch(digits)
      ? null
      : 'Enter the full phone number including the country code, for example +44.';
}
