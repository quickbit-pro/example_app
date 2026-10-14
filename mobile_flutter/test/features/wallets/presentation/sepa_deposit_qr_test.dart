import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/presentation/sepa_deposit_qr.dart';

void main() {
  const iban = 'DE89370400440532013000';
  const bic = 'COBADEFFXXX';
  test('EPC UTF-8 payload preserves beneficiary and uses no fixed amount', () {
    expect(
        sepaDepositQr(
            iban: 'DE89 3704 0044 0532 0130 00',
            beneficiary: 'ROK KOGOVŠEK',
            bic: bic),
        'BCD\n002\n1\nSCT\nCOBADEFFXXX\nROK KOGOVŠEK\n$iban');
  });
  test('preserves payment reference in its proper field', () {
    final lines = sepaDepositQr(
            iban: iban,
            beneficiary: 'Example',
            bic: bic,
            paymentReference: 'Deposit 123')!
        .split('\n');
    expect(lines.sublist(7), ['', '', '', 'Deposit 123']);
  });
  test('rejects invalid, masked or incomplete details and line injection', () {
    for (final value in [
      'DE89370400440532013001',
      'DE89********3000',
      '',
      '$iban\nEUR100'
    ]) {
      expect(
          sepaDepositQr(iban: value, beneficiary: 'Example', bic: bic), isNull);
    }
    expect(sepaDepositQr(iban: iban, beneficiary: '', bic: bic), isNull);
    expect(sepaDepositQr(iban: iban, beneficiary: 'Example', bic: 'INVALID'),
        isNull);
    expect(
        sepaDepositQr(
            iban: iban,
            beneficiary: 'Example',
            bic: bic,
            paymentReference: 'reference\nother'),
        isNull);
  });
  test(
      'rejects excessive characters and UTF-8 payload bytes without truncation',
      () {
    expect(sepaDepositQr(iban: iban, beneficiary: 'x' * 71, bic: bic), isNull);
    expect(
        sepaDepositQr(
            iban: iban,
            beneficiary: 'x',
            bic: bic,
            paymentReference: 'x' * 141),
        isNull);
    expect(
        sepaDepositQr(
            iban: iban,
            beneficiary: '漢' * 70,
            bic: bic,
            paymentReference: '漢' * 140),
        isNull);
  });
}
