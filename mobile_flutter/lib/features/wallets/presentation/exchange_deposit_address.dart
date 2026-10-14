import 'package:crypto/crypto.dart';

const _base58 = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

/// Normalize only addresses explicitly associated with the TRON network.
/// https://developers.tron.network/docs/encoding
String? exchangeDepositAddress(int? chain, String value) {
  final address = value.trim();
  if (address.isEmpty) return null;
  if (chain != -200) return address;
  var hex = address.startsWith('0x') ? address.substring(2) : address;
  if (RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(hex)) hex = '41$hex';
  if (RegExp(r'^41[0-9a-fA-F]{40}$').hasMatch(hex)) {
    final bytes = [
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ];
    final checksum = sha256.convert(sha256.convert(bytes).bytes).bytes.take(4);
    var number = BigInt.zero;
    for (final byte in [...bytes, ...checksum]) {
      number = (number << 8) | BigInt.from(byte);
    }
    var encoded = '';
    while (number > BigInt.zero) {
      encoded = _base58[(number % BigInt.from(58)).toInt()] + encoded;
      number ~/= BigInt.from(58);
    }
    return encoded;
  }
  if (address.length != 34 || !address.startsWith('T')) return null;
  var number = BigInt.zero;
  for (final char in address.split('')) {
    final digit = _base58.indexOf(char);
    if (digit < 0) return null;
    number = number * BigInt.from(58) + BigInt.from(digit);
  }
  final bytes = <int>[];
  while (number > BigInt.zero) {
    bytes.insert(0, (number & BigInt.from(255)).toInt());
    number >>= 8;
  }
  if (bytes.length != 25 || bytes.first != 0x41) return null;
  final checksum =
      sha256.convert(sha256.convert(bytes.sublist(0, 21)).bytes).bytes;
  for (var i = 0; i < 4; i++) {
    if (bytes[21 + i] != checksum[i]) return null;
  }
  return address;
}
