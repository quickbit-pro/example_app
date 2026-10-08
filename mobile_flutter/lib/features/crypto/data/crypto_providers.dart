import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/platform_models.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/crypto_models.dart';

final hoppaMarketAssetsProvider = FutureProvider<List<HoppaMarketAsset>>((ref) {
  return ref.watch(assetsProvider.future).then(_marketAssetsFromResources);
});

final hoppaPortfolioProvider =
    FutureProvider<List<HoppaPortfolioPosition>>((ref) async {
  final wallets = await ref.watch(walletsProvider.future);
  final marketAssets = await ref.watch(hoppaMarketAssetsProvider.future);
  final marketBySymbol = {
    for (final asset in marketAssets) asset.symbol.toUpperCase(): asset,
  };

  return wallets
      .expand(
          (wallet) => _portfolioPositionsFromResource(wallet, marketBySymbol))
      .whereType<HoppaPortfolioPosition>()
      .toList();
});

List<HoppaMarketAsset> _marketAssetsFromResources(
  List<PlatformResource> resources,
) {
  return resources
      .map(_marketAssetFromResource)
      .whereType<HoppaMarketAsset>()
      .toList();
}

HoppaMarketAsset? _marketAssetFromResource(PlatformResource resource) {
  final symbol = _assetCode(resource);
  if (symbol == null) {
    return null;
  }

  final price = _doubleValue(resource.metadata, const [
    'price',
    'Price',
    'marketPrice',
    'MarketPrice',
    'currentPrice',
    'CurrentPrice',
    'quote',
    'Quote',
    'rate',
    'Rate',
  ]);
  final changePercent = _doubleValue(resource.metadata, const [
    'changePercent',
    'ChangePercent',
    'priceChangePercent',
    'PriceChangePercent',
    'percentChange24h',
    'PercentChange24h',
    'change24h',
    'Change24h',
  ]);
  final rank = _intValue(resource.metadata, const [
    'marketCapRank',
    'MarketCapRank',
    'rank',
    'Rank',
  ]);

  return HoppaMarketAsset(
    symbol: symbol,
    name: _textValue(resource.metadata, const [
          'name',
          'Name',
          'displayName',
          'DisplayName',
          'assetName',
          'AssetName',
          'currencyName',
          'CurrencyName',
        ]) ??
        resource.title,
    price: price ?? 0,
    changePercent: changePercent ?? 0,
    marketCapRank: rank ?? 0,
    sparkline: _sparkline(resource.metadata),
    tint: _assetColor(symbol),
    hasPrice: price != null,
    hasChangePercent: changePercent != null,
    hasMarketCapRank: rank != null,
  );
}

HoppaPortfolioPosition? _portfolioPositionFromResource(
  PlatformResource wallet,
  Map<String, HoppaMarketAsset> marketBySymbol,
) {
  final symbol = _assetCode(wallet);
  if (symbol == null) {
    return null;
  }

  final amount = _doubleValue(wallet.metadata, const [
        'amount',
        'Amount',
        'balance',
        'Balance',
        'available',
        'Available',
        'availableBalance',
        'AvailableBalance',
        'quantity',
        'Quantity',
      ]) ??
      0;
  final value = _doubleValue(wallet.metadata, const [
    'fiatValue',
    'FiatValue',
    'value',
    'Value',
    'eurValue',
    'EurValue',
    'marketValue',
    'MarketValue',
  ]);
  final costBasis = _doubleValue(wallet.metadata, const [
        'costBasis',
        'CostBasis',
        'bookCost',
        'BookCost',
      ]) ??
      value ??
      0;
  final marketAsset = marketBySymbol[symbol.toUpperCase()];
  final asset = marketAsset ??
      HoppaMarketAsset(
        symbol: symbol,
        name: _textValue(wallet.metadata, const [
              'name',
              'Name',
              'displayName',
              'DisplayName',
              'assetName',
              'AssetName',
            ]) ??
            wallet.title,
        price: amount == 0 || value == null ? 0 : value / amount,
        changePercent: 0,
        marketCapRank: 0,
        sparkline: const [],
        tint: _assetColor(symbol),
        hasPrice: amount != 0 && value != null,
        hasChangePercent: false,
        hasMarketCapRank: false,
      );

  return HoppaPortfolioPosition(
    asset: asset,
    amount: amount,
    costBasis: costBasis,
    valueOverride: value,
  );
}

List<HoppaPortfolioPosition> _portfolioPositionsFromResource(
  PlatformResource wallet,
  Map<String, HoppaMarketAsset> marketBySymbol,
) {
  final balances = _listValue(wallet.metadata, const ['balances', 'Balances']);
  if (balances == null || balances.isEmpty) {
    final position = _portfolioPositionFromResource(wallet, marketBySymbol);
    return position == null ? const [] : [position];
  }

  return balances
      .whereType<Map>()
      .map((balance) =>
          balance.map((key, value) => MapEntry(key.toString(), value)))
      .map((balance) => _portfolioPositionFromBalance(balance, marketBySymbol))
      .whereType<HoppaPortfolioPosition>()
      .toList();
}

HoppaPortfolioPosition? _portfolioPositionFromBalance(
  Map<String, dynamic> balance,
  Map<String, HoppaMarketAsset> marketBySymbol,
) {
  final rawSymbol = _textValue(balance, const [
    'currency',
    'Currency',
    'currencyCode',
    'CurrencyCode',
    'asset',
    'Asset',
    'tokenSymbol',
    'TokenSymbol',
  ]);
  if (rawSymbol == null) {
    return null;
  }

  final symbol = rawSymbol.toUpperCase();
  final amount = _doubleValue(balance, const [
        'available',
        'Available',
        'balance',
        'Balance',
        'amount',
        'Amount',
      ]) ??
      0;
  final marketAsset = marketBySymbol[symbol];
  final asset = marketAsset ??
      HoppaMarketAsset(
        symbol: symbol,
        name: symbol,
        price: 0,
        changePercent: 0,
        marketCapRank: 0,
        sparkline: const [],
        tint: _assetColor(symbol),
        hasPrice: false,
        hasChangePercent: false,
        hasMarketCapRank: false,
      );

  return HoppaPortfolioPosition(
    asset: asset,
    amount: amount,
    costBasis: 0,
  );
}

String? _assetCode(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'asset',
    'Asset',
    'assetCode',
    'AssetCode',
    'currencyCode',
    'CurrencyCode',
    'token',
    'Token',
    'tokenSymbol',
    'TokenSymbol',
    'symbol',
    'Symbol',
    'currency',
    'Currency',
  ]);
}

List<Object?>? _listValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value;
    }
  }

  return null;
}

List<double> _sparkline(Map<String, dynamic> json) {
  final value = json['sparkline'] ??
      json['Sparkline'] ??
      json['prices'] ??
      json['Prices'] ??
      json['priceHistory'] ??
      json['PriceHistory'];
  if (value is List) {
    return value.map(_doubleFromAny).whereType<double>().toList();
  }

  return const [];
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return null;
}

double? _doubleValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _doubleFromAny(json[key]);
    if (value != null) {
      return value;
    }
  }

  return null;
}

double? _doubleFromAny(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.'));
  }
  if (value is Map<String, dynamic>) {
    final minorUnits = value['minorUnits'] ?? value['MinorUnits'];
    if (minorUnits != null) {
      final parsed = _doubleFromAny(minorUnits);
      return parsed == null ? null : parsed / 100;
    }

    return _doubleValue(value, const ['amount', 'Amount', 'value', 'Value']);
  }

  return null;
}

int? _intValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return parsed;
      }
    }
  }

  return null;
}

Color _assetColor(String symbol) {
  final colors = [
    Colors.blue,
    Colors.teal,
    Colors.indigo,
    Colors.green,
    Colors.deepOrange,
    Colors.purple,
  ];
  return colors[symbol.hashCode.abs() % colors.length];
}
