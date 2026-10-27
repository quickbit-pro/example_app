import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_deposit_address.dart';

void main() {
  const hex = '415CBDD86A2FA8DC4BDDD8A8F69DBA48572EEC07FB';
  const base58 = 'TJRabPrwbZy45sbavfcjinPJC18kjpRTv8';
  test('TRON documented vector supports wire and raw 20-byte formats', () {
    expect(exchangeDepositAddress(-200, hex), base58);
    expect(exchangeDepositAddress(-200, '0x${hex.substring(2)}'), base58);
    expect(exchangeDepositAddress(-200, base58), base58);
  });
  test('Tron checksum and malformed addresses are rejected', () {
    for (final address in [
      '',
      '0x123',
      '${base58.substring(0, 33)}9',
      '42${hex.substring(2)}',
      'T000000000000000000000000000000000'
    ]) {
      expect(exchangeDepositAddress(-200, address), isNull);
    }
  });
  test('other networks are never converted to Tron', () {
    expect(exchangeDepositAddress(1, '0x${hex.substring(2)}'),
        '0x${hex.substring(2)}');
  });
}
