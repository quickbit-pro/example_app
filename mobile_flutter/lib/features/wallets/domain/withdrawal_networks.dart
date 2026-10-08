/// Networks implemented by this client and accepted by the upstream V2
/// withdrawal validation. Quote/submission still recheck provider availability.
/// Do not infer payout support from a deposit address or add networks without
/// a corresponding destination validator.
const withdrawalNetworkNames = <String, String>{
  'ETH': 'Ethereum',
  'AVAX': 'Avalanche',
  'ARB': 'Arbitrum',
  'MATIC': 'Polygon',
  'TRX': 'Tron',
  'OP': 'Optimism',
};

Map<String, String> withdrawalNetworksFor(String currency) =>
    switch (currency.toUpperCase()) {
      'USDT' => withdrawalNetworkNames,
      'USDC' => Map.fromEntries(
          withdrawalNetworkNames.entries.where((e) => e.key != 'TRX')),
      _ => const {},
    };

const minimumCryptoWithdrawal = 5.0;
