/// Card PIN rules, mirrored from the backend (`CardPinPolicy`): exactly six
/// digits, not a single repeated digit, not a run of consecutive digits up or
/// down (including 890123 / 210987), and not a short block repeated to fill
/// the PIN (121212, 123123).
const cardPinLength = 6;

class CardPinRule {
  const CardPinRule(this.label, this.test);

  final String label;
  final bool Function(String pin) test;
}

const cardPinRules = [
  CardPinRule('Exactly 6 digits', _isSixDigits),
  CardPinRule('Not one repeated digit (111111)', _notSingleDigit),
  CardPinRule('Not a run of digits (123456, 654321)', _notSequential),
  CardPinRule('Not a repeating pattern (121212, 123123)', _notRepeatedBlock),
];

bool cardPinMeetsPolicy(String pin) =>
    cardPinRules.every((rule) => rule.test(pin));

/// The first unmet rule, or null when the PIN is acceptable.
String? cardPinProblem(String pin) {
  for (final rule in cardPinRules) {
    if (!rule.test(pin)) return rule.label;
  }
  return null;
}

final _sixDigits = RegExp(r'^[0-9]{6}$');

bool _isSixDigits(String pin) => _sixDigits.hasMatch(pin);

bool _notSingleDigit(String pin) =>
    pin.isEmpty || pin.split('').toSet().length > 1;

bool _notSequential(String pin) {
  if (pin.length < 2) return true;
  var ascending = true;
  var descending = true;
  for (var i = 1; i < pin.length; i++) {
    final step = (pin.codeUnitAt(i) - pin.codeUnitAt(i - 1)) % 10;
    ascending &= step == 1;
    descending &= step == 9;
  }
  return !(ascending || descending);
}

bool _notRepeatedBlock(String pin) {
  for (var block = 1; block <= pin.length ~/ 2; block++) {
    if (pin.length % block != 0) continue;
    var repeated = true;
    for (var i = block; i < pin.length && repeated; i++) {
      repeated = pin[i] == pin[i - block];
    }
    if (repeated) return false;
  }
  return true;
}
