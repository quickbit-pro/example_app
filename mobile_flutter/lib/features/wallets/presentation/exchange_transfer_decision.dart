import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/exchange_models.dart';
import 'exchange_support.dart';

Future<void> showExchangeTransferDecision(BuildContext context, WidgetRef ref,
    BoomFiTransfer transfer, String decision) async {
  var busy = false, accepted = false;
  String? error;
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(builder: (context, setState) {
            final expiry = DateTime.tryParse(transfer.detail('quoteExpiresAt'));
            final expired = decision == 'approve' &&
                (expiry == null ||
                    !expiry.isAfter(
                        DateTime.now().add(const Duration(seconds: 2))));
            return PopScope(
                canPop: !busy,
                child: AlertDialog(
                    title: Text(decision == 'approve'
                        ? 'Review updated quote'
                        : decision == 'return'
                            ? 'Return funds'
                            : decision == 'keep'
                                ? 'Keep crypto in Exchange'
                                : 'Decline quote'),
                    content: SingleChildScrollView(
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          if (decision == 'approve') ...[
                            Text(
                                'Original rate: ${transfer.detail('initialExchangeRate')}'),
                            Text(
                                'Updated rate: ${transfer.detail('effectiveRate')}'),
                            Text(
                                'You receive ${transfer.detail('toAmount')} ${transfer.direction == 'equals_to_interlace' ? transfer.cryptoCurrency : transfer.fiatCurrency}'),
                            Text(
                                'Fees: ${transfer.detail('currentFeeAmount')} ${transfer.detail('currentFeeCurrency')}'),
                            Text(
                                'Quote expires: ${transfer.detail('quoteExpiresAt')}'),
                            if (expired)
                              const Text(
                                  'This quote expired. Refresh it and review the new quote before approving.'),
                          ],
                          if (decision == 'return')
                            const Text(
                                'Provider and network return fees are only available after submission. The returned amount may be lower than the original amount.'),
                          if (decision == 'decline')
                            Text(transfer.direction == 'equals_to_interlace'
                                ? 'Fiat must be returned before the 24-hour holding deadline.'
                                : 'You can keep the crypto in Exchange or return it after declining.'),
                          if (['approve', 'return'].contains(decision))
                            ExchangeTerms(
                                accepted: accepted,
                                enabled: !busy,
                                onChanged: (v) => setState(() => accepted = v),
                                withdrawal: decision == 'return'),
                          if (error != null) Text(error!),
                        ])),
                    actions: [
                      TextButton(
                          onPressed: busy ? null : () => Navigator.pop(dialog),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: busy ||
                                  (!expired &&
                                      ['approve', 'return']
                                          .contains(decision) &&
                                      !accepted)
                              ? null
                              : () async {
                                  if (decision == 'keep' &&
                                      !transfer.canKeepFunds) {
                                    return;
                                  }
                                  final expiredNow = decision == 'approve' &&
                                      (expiry == null ||
                                          !expiry.isAfter(DateTime.now().add(
                                              const Duration(seconds: 2))));
                                  if (expiredNow && !expired) {
                                    setState(() => accepted = false);
                                    return;
                                  }
                                  setState(() {
                                    busy = true;
                                    error = null;
                                  });
                                  try {
                                    // Refresh is a separate operation and cannot execute a newer provider quote.
                                    final result = await ref
                                        .read(mobilePlatformApiProvider)
                                        .decideExchangeTransfer(transfer.id,
                                            expired ? 'refresh' : decision);
                                    ref.invalidate(exchangeTransfersProvider);
                                    ref.invalidate(exchangeOverviewProvider);
                                    if (dialog.mounted) {
                                      Navigator.pop(dialog);
                                      ScaffoldMessenger.of(dialog).showSnackBar(
                                          SnackBar(
                                              content: Text(result.message)));
                                    }
                                  } catch (e) {
                                    if (dialog.mounted) {
                                      setState(() => error = e.toString());
                                    }
                                  } finally {
                                    if (dialog.mounted) {
                                      setState(() => busy = false);
                                    }
                                  }
                                },
                          child: Text(busy
                              ? 'Submitting…'
                              : expired
                                  ? 'Refresh quote'
                                  : 'Confirm')),
                    ]));
          }));
}
