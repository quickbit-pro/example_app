import '../../../core/models/platform_models.dart';
import 'wallet_models.dart';

const exchangeDefaultChainId = 137;

int exchangeChainId(String network) {
  final n = network.trim().toLowerCase();
  // A merged display label is not an exact transfer route.
  if (n.contains('/') || n.contains(',')) return 0;
  if (n.contains('tron') || n == 'trx' || n == 'trc20') return -200;
  if (n.contains('polygon') || n == 'matic') return 137;
  if (n.contains('arbitrum') || n == 'arb') return 42161;
  if (n.contains('optimism') || n == 'op') return 10;
  if (n.contains('avalanche') || n == 'avax') return 43114;
  if (n.contains('ethereum') || n == 'eth' || n == 'erc20') return 1;
  return 0;
}

List<HoppaWalletAsset> exchangeTransferRoutes(
  List<HoppaWalletAsset> addresses,
  List<HoppaWalletAsset> balances,
) {
  final routes = <String, HoppaWalletAsset>{};
  for (final address in addresses) {
    final symbol = address.symbol.trim().toUpperCase();
    final chain = exchangeChainId(address.network);
    if (!['USDC', 'USDT'].contains(symbol) ||
        chain == 0 ||
        address.address.trim().isEmpty) {
      continue;
    }
    // Interlace balances are shared across chains. Deposit-address rows only
    // identify a route; their amounts must never replace or multiply a balance.
    final balance = balances
        .where((b) => b.symbol.trim().toUpperCase() == symbol)
        .firstOrNull;
    routes.putIfAbsent(
        '$symbol:$chain:${address.address}',
        () => HoppaWalletAsset(
              symbol: symbol,
              name: address.name,
              network: address.network,
              amount: balance?.amount ?? 0,
              fiatValue: balance?.fiatValue ?? 0,
              address: address.address,
              tint: address.tint,
              walletId: address.walletId,
            ));
  }
  return [
    ...routes.values
        .where((w) => exchangeChainId(w.network) == exchangeDefaultChainId),
    ...routes.values
        .where((w) => exchangeChainId(w.network) != exchangeDefaultChainId),
  ];
}

// Present one choice per currency while retaining the exact route for requests.
// Callers pass only routes supported by both the card wallet and BoomFi.
List<HoppaWalletAsset> exchangeTransferCurrencyRoutes(
  List<HoppaWalletAsset> routes, {
  required bool Function(String) canTrade,
}) {
  final choices = <HoppaWalletAsset>[];
  for (final symbol in ['USDC', 'USDT']) {
    if (!canTrade(symbol)) continue;
    final matching = routes.where((w) => w.symbol.toUpperCase() == symbol);
    final selected = matching
            .where((w) => exchangeChainId(w.network) == exchangeDefaultChainId)
            .firstOrNull ??
        matching.firstOrNull;
    if (selected != null) choices.add(selected);
  }
  return choices;
}

String exchangeRouteKey(HoppaWalletAsset wallet) =>
    '${wallet.symbol}:${exchangeChainId(wallet.network)}:${wallet.address}';

Object? _field(Map map, String name) =>
    map[name] ?? map['${name[0].toUpperCase()}${name.substring(1)}'];

Set<String> exchangeBudgetCurrencies(PlatformResource budget) {
  final supported = _field(budget.metadata, 'supportedCurrencies');
  return {
    if (supported is List)
      ...supported.map((c) => c.toString().trim().toUpperCase()),
    ...exchangeBudgetBalances(budget).keys,
    (_field(budget.metadata, 'currency') ?? 'EUR')
        .toString()
        .trim()
        .toUpperCase(),
  };
}

Map<String, double> exchangeBudgetBalances(PlatformResource budget) {
  final result = <String, double>{};
  void add(Map row) {
    final currency =
        (_field(row, 'currency') ?? _field(row, 'currencyCode') ?? '')
            .toString()
            .trim()
            .toUpperCase();
    final amount = double.tryParse((_field(row, 'availableBalance') ??
            _field(row, 'available') ??
            _field(row, 'amount') ??
            _field(row, 'balance') ??
            '')
        .toString());
    if (currency.isNotEmpty && amount != null && amount.isFinite) {
      result.putIfAbsent(currency, () => amount);
    }
  }

  for (final key in [
    'balances',
    'currencyBalances',
    'supportedCurrencyBalances',
    'availableBalances'
  ]) {
    final rows = _field(budget.metadata, key);
    if (rows is List) {
      for (final row in rows.whereType<Map>()) {
        add(row);
      }
    }
  }
  add(budget.metadata);
  return result;
}
