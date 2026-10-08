import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/crypto/crypto_address_validator.dart';
import 'package:mobile_flutter/core/crypto/keccak.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('keccak256', () {
    test('matches the known empty-string digest', () {
      expect(
        _hex(keccak256(const [])),
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
      );
    });

    test('is deterministic and 32 bytes long', () {
      final first = keccak256(utf8.encode('abc'));
      expect(first.length, 32);
      expect(_hex(first), _hex(keccak256(utf8.encode('abc'))));
      expect(_hex(first), isNot(_hex(keccak256(utf8.encode('abd')))));
    });
  });

  group('ERC-20 addresses', () {
    const checksummed = [
      '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      '0xfB6916095ca1df60bB79Ce92cE3Ea74c37c5d359',
      '0xdbF03B407c01E7cD3CBea99509d93f8DDDC8C6FB',
      '0xD1220A0cf47c7B9Be7A2E6BA89F429762e7b9aDb',
    ];

    test('accepts EIP-55 checksummed addresses', () {
      for (final address in checksummed) {
        expect(
          CryptoAddressValidator.validate(address, network: 'ETH').isValid,
          isTrue,
          reason: address,
        );
      }
    });

    test('accepts all-lowercase and all-uppercase addresses', () {
      expect(
        CryptoAddressValidator.validate(checksummed.first.toLowerCase(),
                network: 'ARB')
            .isValid,
        isTrue,
      );
      expect(
        CryptoAddressValidator.validate(
                '0x${checksummed.first.substring(2).toUpperCase()}',
                network: 'MATIC')
            .isValid,
        isTrue,
      );
    });

    test('rejects a wrong checksum, wrong length, and Tron addresses', () {
      const broken = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAeD';
      expect(
        CryptoAddressValidator.validate(broken, network: 'ETH').error,
        contains('checksum'),
      );
      expect(
        CryptoAddressValidator.validate('0x1234', network: 'ETH').isValid,
        isFalse,
      );
      expect(
        CryptoAddressValidator.validate('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
                network: 'ETH')
            .error,
        contains('Tron'),
      );
    });
  });

  group('TRC-20 addresses', () {
    test('accepts a valid Tron address', () {
      expect(
        CryptoAddressValidator.validate('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
                network: 'TRX')
            .isValid,
        isTrue,
      );
    });

    test('rejects a corrupted checksum and non-Tron input', () {
      expect(
        CryptoAddressValidator.validate('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6u',
                network: 'TRX')
            .error,
        contains('checksum'),
      );
      expect(
        CryptoAddressValidator.validate(
                '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
                network: 'TRX')
            .error,
        contains('ERC-20'),
      );
      expect(
        CryptoAddressValidator.validate('Tshort', network: 'TRX').isValid,
        isFalse,
      );
    });
  });
}
