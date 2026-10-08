import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'keccak.dart';

/// Address families supported for stablecoin withdrawals.
enum CryptoAddressFamily {
  /// 0x-prefixed 20-byte addresses (Ethereum, Arbitrum, Polygon, Avalanche
  /// C-Chain, Optimism, OKX Chain); ERC-20 style tokens.
  evm,

  /// Base58Check addresses starting with `T` (Tron); TRC-20 tokens.
  tron,
}

class CryptoAddressCheck {
  const CryptoAddressCheck._(this.isValid, this.error);

  const CryptoAddressCheck.valid() : this._(true, null);

  const CryptoAddressCheck.invalid(String error) : this._(false, error);

  final bool isValid;
  final String? error;
}

/// Client-side format and checksum validation for destination addresses.
/// The provider validates again server-side; this catches typos before a
/// quote is requested.
class CryptoAddressValidator {
  const CryptoAddressValidator._();

  static const _base58Alphabet =
      '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

  /// Maps the provider's network codes to an address family.
  static CryptoAddressFamily? familyForNetwork(String network) {
    switch (network.trim().toUpperCase()) {
      case 'ETH':
      case 'ETHEREUM':
      case 'ERC20':
      case 'ARB':
      case 'ARBITRUM':
      case 'MATIC':
      case 'POLYGON':
      case 'AVAX':
      case 'AVALANCHE':
      case 'OP':
      case 'OPTIMISM':
      case 'OKT':
      case 'BSC':
      case 'BEP20':
      case 'BASE':
        return CryptoAddressFamily.evm;
      case 'TRX':
      case 'TRON':
      case 'TRC20':
        return CryptoAddressFamily.tron;
    }
    return null;
  }

  static String hint(CryptoAddressFamily? family) => switch (family) {
        CryptoAddressFamily.evm =>
          'ERC-20 format: starts with 0x followed by 40 hex characters.',
        CryptoAddressFamily.tron =>
          'TRC-20 format: starts with T and is 34 characters long.',
        null => 'The address must support the selected network.',
      };

  static CryptoAddressCheck validate(String address,
      {required String network}) {
    final value = address.trim();
    if (value.isEmpty) {
      return const CryptoAddressCheck.invalid(
          'Enter the destination wallet address.');
    }
    final family = familyForNetwork(network);
    switch (family) {
      case CryptoAddressFamily.evm:
        return _validateEvm(value);
      case CryptoAddressFamily.tron:
        return _validateTron(value);
      case null:
        return value.length >= 10
            ? const CryptoAddressCheck.valid()
            : const CryptoAddressCheck.invalid(
                'Enter a valid destination wallet address.');
    }
  }

  static CryptoAddressCheck _validateEvm(String value) {
    if (value.startsWith('T') && value.length == 34) {
      return const CryptoAddressCheck.invalid(
        'This looks like a Tron (TRC-20) address. Switch the network to Tron or enter a 0x address.',
      );
    }
    if (!RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(value)) {
      return const CryptoAddressCheck.invalid(
        'ERC-20 addresses start with 0x followed by exactly 40 hex characters.',
      );
    }
    final hex = value.substring(2);
    final hasUpper = hex != hex.toLowerCase();
    final hasLower = hex != hex.toUpperCase();
    if (hasUpper && hasLower && !_eip55Matches(hex)) {
      return const CryptoAddressCheck.invalid(
        'The address checksum does not match. Check it for typos.',
      );
    }
    return const CryptoAddressCheck.valid();
  }

  /// EIP-55: each hex letter is upper-case iff the matching nibble of
  /// keccak256(lowercase address) is >= 8.
  static bool _eip55Matches(String hex) {
    final lower = hex.toLowerCase();
    final hash = keccak256(ascii.encode(lower));
    for (var i = 0; i < 40; i++) {
      final char = lower[i];
      if (!RegExp('[a-f]').hasMatch(char)) continue;
      final nibble = i.isEven ? hash[i ~/ 2] >> 4 : hash[i ~/ 2] & 0x0f;
      final expected = nibble >= 8 ? char.toUpperCase() : char;
      if (hex[i] != expected) return false;
    }
    return true;
  }

  static CryptoAddressCheck _validateTron(String value) {
    if (value.startsWith('0x')) {
      return const CryptoAddressCheck.invalid(
        'This looks like an ERC-20 address. Switch the network to Ethereum or enter a T… address.',
      );
    }
    if (!value.startsWith('T') || value.length != 34) {
      return const CryptoAddressCheck.invalid(
        'TRC-20 addresses start with T and are exactly 34 characters long.',
      );
    }
    final decoded = _base58Decode(value);
    if (decoded == null || decoded.length != 25 || decoded[0] != 0x41) {
      return const CryptoAddressCheck.invalid(
        'This is not a valid Tron address.',
      );
    }
    final payload = decoded.sublist(0, 21);
    final checksum = sha256.convert(sha256.convert(payload).bytes).bytes;
    for (var i = 0; i < 4; i++) {
      if (checksum[i] != decoded[21 + i]) {
        return const CryptoAddressCheck.invalid(
          'The address checksum does not match. Check it for typos.',
        );
      }
    }
    return const CryptoAddressCheck.valid();
  }

  static Uint8List? _base58Decode(String input) {
    var number = BigInt.zero;
    final base = BigInt.from(58);
    for (final char in input.split('')) {
      final digit = _base58Alphabet.indexOf(char);
      if (digit < 0) return null;
      number = number * base + BigInt.from(digit);
    }
    final bytes = <int>[];
    while (number > BigInt.zero) {
      bytes.insert(0, (number & BigInt.from(0xff)).toInt());
      number = number >> 8;
    }
    for (final char in input.split('')) {
      if (char != '1') break;
      bytes.insert(0, 0);
    }
    return Uint8List.fromList(bytes);
  }
}
