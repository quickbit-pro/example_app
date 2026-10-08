import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../../dashboard/data/dashboard_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../data/peer_transfers_api.dart';

final peerTransfersApiProvider = Provider<PeerTransfersApi>((ref) {
  return PeerTransfersApi(ref.watch(dioProvider));
});

final peerRequestsProvider = FutureProvider<PeerRequests>((ref) {
  return ref.watch(peerTransfersApiProvider).requests();
});

final peerContactsProvider = FutureProvider<List<PeerContact>>((ref) {
  return ref.watch(peerTransfersApiProvider).contacts();
});

final peerRecentProvider = FutureProvider<List<PeerTransfer>>((ref) {
  return ref.watch(peerTransfersApiProvider).recent(limit: 30);
});

/// Quota and pacing without an amount: enough for the hub's "10 free
/// transfers left today" hint. The composer asks again with the amount.
final peerFeeInfoProvider = FutureProvider<PeerFeeInfo>((ref) {
  return ref.watch(peerTransfersApiProvider).feeInfo();
});

/// Whether member transfers can settle on this installation: the recipient
/// credit is a wallet outflow on the provider side.
final peerTransfersEnabledProvider = FutureProvider<bool>((ref) async {
  final config = await ref.watch(mobileTenantConfigProvider.future);
  return config.walletOutflowsEnabled;
});

/// Spendable balance per currency members can send (USD card balance and
/// the USDC / USDT wallets), read from the dashboard snapshot.
final peerAvailableBalancesProvider =
    FutureProvider<Map<String, double>>((ref) async {
  final snapshot = await ref.watch(hoppaDashboardProvider.future);
  final balances = <String, double>{};
  for (final account in snapshot.accounts) {
    final code = account.currency.toUpperCase();
    if (code == 'USD') {
      balances[code] = (balances[code] ?? 0) + account.available;
    }
  }
  for (final holding in snapshot.holdings) {
    final code = holding.symbol.toUpperCase();
    if (code == 'USDC' || code == 'USDT') {
      balances[code] = (balances[code] ?? 0) + holding.amount;
    }
  }
  return balances;
});

/// Drops every cached peer list after a send, request or reply.
void invalidatePeerData(WidgetRef ref) {
  ref.invalidate(peerRequestsProvider);
  ref.invalidate(peerRecentProvider);
  ref.invalidate(peerFeeInfoProvider);
  ref.invalidate(peerContactsProvider);
  ref.invalidate(hoppaDashboardProvider);
  ref.invalidate(peerAvailableBalancesProvider);
}
