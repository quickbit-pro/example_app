import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_models.dart';
import 'package:mobile_flutter/features/wallets/domain/exchange_history_links.dart';

BoomFiTransfer transfer(int id, String? paymentId, [String status = 'completed', String direction = 'equals_to_interlace']) => BoomFiTransfer.fromJson({
  'id': id, 'status': status, 'transferDirection': direction,
  'boomFiDepositPaymentId': paymentId, 'cryptoCurrency': 'USDC',
  'cryptoAmount': '11.073355', 'fiatCurrency': 'EUR',
});
BoomFiDeposit deposit(String id) => BoomFiDeposit.fromJson({
  'id': 1, 'paymentId': id, 'amount': '10', 'currency': 'EUR', 'status': 'completed',
});
void main() {
  test('same-amount deposits link only to their confirmed transfer', () {
    final transfers = [transfer(133, 'pay_first'), transfer(145, 'pay_second', 'payout_failed')];
    expect(transferForDeposit(deposit('pay_first'), transfers)?.id, 133);
    expect(transferForDeposit(deposit('pay_second'), transfers)?.id, 145);
    expect(transferForDeposit(deposit('pay_external'), transfers), isNull);
    expect(transferForDeposit(deposit('pay_first'), [transfer(133, null)]), isNull);
    expect(depositForTransfer(transfers.first, [deposit('pay_first'), deposit('pay_second')], transfers)?.paymentId, 'pay_first');
  });
  test('ambiguous links and non-deposits remain standalone', () {
    expect(transferForDeposit(deposit('pay_first'), [transfer(1, 'pay_first'), transfer(2, 'pay_first')]), isNull);
    final payout = BoomFiDeposit.fromJson({'paymentId':'pay_first', 'paymentMethod':'Withdrawal'});
    expect(transferForDeposit(payout, [transfer(1, 'pay_first')]), isNull);
  });
  test('reverse route links and completed history keeps real transfers only', () {
    final reverse = transfer(3, 'pay_crypto', 'completed', 'interlace_to_equals');
    expect(transferForDeposit(deposit('pay_crypto'), [reverse]), reverse);
    expect(showTransferInHistory(reverse), isTrue);
    expect(transferForDeposit(deposit('pay_crypto'), [transfer(4, 'pay_crypto', 'funds_held')]), isNull);
    expect(showTransferInHistory(transfer(4, null, 'completed', 'exchange_to_bank')), isFalse);
    expect(showTransferInHistory(transfer(4, 'pay_crypto', 'funds_held')), isFalse);
    expect(showTransferInHistory(transfer(4, 'pay_crypto', 'payout_submitted')), isFalse);
    expect(showTransferInHistory(transfer(1, 'pay_first')), isTrue);
    expect(showTransferInHistory(transfer(1, 'pay_first', 'payout_failed')), isFalse);
    expect(showTransferInHistory(transfer(1, null, 'failed')), isFalse);
    expect(showTransferInHistory(transfer(1, null, 'exchange_quoted')), isFalse);
  });
}
