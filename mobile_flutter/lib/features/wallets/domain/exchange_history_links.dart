import 'exchange_models.dart';

/// Presentation uses only the deposit claimed by the transfer engine. Equal
/// amounts or nearby timestamps are not enough to combine financial records.
BoomFiTransfer? transferForDeposit(
    BoomFiDeposit deposit, List<BoomFiTransfer> transfers) {
  if (!deposit.isDeposit || deposit.paymentId.isEmpty) return null;
  final matches = transfers.where((transfer) =>
      const {'equals_to_interlace', 'interlace_to_equals'}
          .contains(transfer.direction) &&
      !transfer.failedBeforeFunding &&
      (transfer.showInProgress || showTransferInHistory(transfer)) &&
      transfer.detail('boomFiDepositPaymentId') == deposit.paymentId).toList();
  return matches.length == 1 ? matches.single : null;
}

BoomFiDeposit? depositForTransfer(BoomFiTransfer transfer,
    List<BoomFiDeposit> deposits, List<BoomFiTransfer> transfers) {
  final matches = deposits.where((deposit) =>
      transferForDeposit(deposit, transfers)?.id == transfer.id).toList();
  return matches.length == 1 ? matches.single : null;
}

bool showTransferInHistory(BoomFiTransfer transfer) =>
    const {'equals_to_interlace', 'interlace_to_equals'}.contains(transfer.direction) &&
    transfer.status == 'completed';
