import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/platform_models.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/wallet_models.dart';

final hoppaWalletAssetsProvider =
    FutureProvider<List<HoppaWalletAsset>>((ref) async {
  var walletResources = const <PlatformResource>[];
  var assetResources = const <PlatformResource>[];
  try {
    walletResources = await ref.watch(userWalletsProvider.future);
  } catch (_) {
    // One provider can be unavailable while the other still has wallets.
  }
  try {
    assetResources = await ref.watch(userAssetsProvider.future);
  } catch (_) {
    // Preserve wallets already returned by the primary wallet endpoint.
  }

  // The assets endpoint carries the authoritative available balance and its
  // balance type. Wallet rows are primarily useful as an address fallback.
  final primary = _walletAssetsFromResources(assetResources);
  final primarySymbols = primary.map((asset) => asset.symbol).toSet();
  final combined = _mergeWalletAssets([
    ...primary,
    ..._walletAssetsFromResources(walletResources)
        .where((asset) => !primarySymbols.contains(asset.symbol)),
  ]);
  if (combined.isNotEmpty) return combined;

  return ref.watch(walletsProvider.future).then(_walletAssetsFromResources);
});

final hoppaWalletBalancesProvider =
    FutureProvider<List<HoppaWalletBalance>>((ref) {
  return ref
      .watch(bankingBalancesProvider.future)
      .then(_walletBalancesFromResources);
});

final hoppaWalletAddressesProvider =
    FutureProvider<List<HoppaWalletAsset>>((ref) {
  return ref
      .watch(depositAddressesProvider.future)
      .then((resources) => _walletAssetsFromResources(
            resources.where(hasCompleteDepositAddress).toList(),
          ));
});

List<HoppaWalletAsset> _walletAssetsFromResources(
  List<PlatformResource> resources,
) {
  final assets = <HoppaWalletAsset>[];
  for (final resource in resources) {
    assets.addAll(_walletAssetsFromResource(resource));
  }

  return _mergeWalletAssets(assets);
}

List<HoppaWalletBalance> _walletBalancesFromResources(
  List<PlatformResource> resources,
) {
  return resources.map(_walletBalanceFromResource).toList();
}

HoppaWalletAsset? _walletAssetFromResource(PlatformResource resource) {
  final rawSymbol = _assetCode(resource);
  if (rawSymbol == null) {
    return null;
  }
  final symbol = rawSymbol.toUpperCase();
  if (_shouldHideWalletAsset(resource, symbol)) {
    return null;
  }

  final network = _networkName(resource);
  final amount = _doubleValue(resource.metadata, const [
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
  final fiatValue = _doubleValue(resource.metadata, const [
    'fiatValue',
    'FiatValue',
    'value',
    'Value',
    'eurValue',
    'EurValue',
    'marketValue',
    'MarketValue',
  ]);
  final address = _depositAddress(resource);

  return HoppaWalletAsset(
    symbol: symbol,
    name: _assetName(symbol),
    network: network ?? '',
    amount: amount,
    fiatValue: fiatValue ?? 0,
    address: address ?? '',
    tint: _assetColor(symbol),
    walletId: _walletId(resource),
    hasNetwork: network != null,
    hasFiatValue: fiatValue != null,
    hasAddress: address != null,
    canTopUp: _canTopUp(resource, symbol),
    canConvert: _canConvert(resource, symbol),
  );
}

HoppaWalletBalance _walletBalanceFromResource(PlatformResource resource) {
  final currency = _assetCode(resource) ?? 'EUR';
  return HoppaWalletBalance(
    label: currency,
    currency: currency,
    available: _doubleValue(resource.metadata, const [
          'available',
          'Available',
          'availableBalance',
          'AvailableBalance',
          'balance',
          'Balance',
        ]) ??
        0,
    reserved: _doubleValue(resource.metadata, const [
          'reserved',
          'Reserved',
          'reservedBalance',
          'ReservedBalance',
          'pending',
          'Pending',
        ]) ??
        0,
  );
}

List<HoppaWalletAsset> _walletAssetsFromResource(PlatformResource resource) {
  final balances =
      _listValue(resource.metadata, const ['balances', 'Balances']);
  if (balances == null || balances.isEmpty) {
    final asset = _walletAssetFromResource(resource);
    return asset == null ? const [] : [asset];
  }

  return balances
      .whereType<Map>()
      .map((balance) =>
          balance.map((key, value) => MapEntry(key.toString(), value)))
      .map((balance) {
        final symbol = _textValue(balance, const [
          'currency',
          'Currency',
          'currencyCode',
          'CurrencyCode',
          'asset',
          'Asset',
          'tokenSymbol',
          'TokenSymbol',
        ]);
        if (symbol == null) {
          return null;
        }
        if (_shouldHideWalletAsset(resource, symbol)) {
          return null;
        }

        return HoppaWalletAsset(
          symbol: symbol.toUpperCase(),
          name: _assetName(symbol),
          network: '',
          amount: _doubleValue(balance, const [
                'available',
                'Available',
                'balance',
                'Balance',
                'amount',
                'Amount',
              ]) ??
              0,
          fiatValue: 0,
          address: '',
          tint: _assetColor(symbol),
          walletId: _walletId(resource),
          hasNetwork: false,
          hasFiatValue: false,
          hasAddress: false,
          canTopUp: _canTopUp(resource, symbol),
          canConvert: _canConvert(resource, symbol),
        );
      })
      .whereType<HoppaWalletAsset>()
      .toList();
}

List<HoppaWalletAsset> _mergeWalletAssets(List<HoppaWalletAsset> assets) {
  final merged = <String, HoppaWalletAsset>{};

  for (final asset in assets) {
    final key = asset.hasAddress
        ? '${asset.symbol.toUpperCase()}:${asset.address.toLowerCase()}'
        : asset.symbol.toUpperCase();
    final existing = merged[key];
    if (existing == null) {
      merged[key] = asset;
      continue;
    }

    merged[key] = HoppaWalletAsset(
      symbol: existing.symbol,
      name: existing.name,
      network: _mergeNetworkNames(existing.network, asset.network),
      amount: existing.hasAddress
          ? existing.amount
          : existing.amount + asset.amount,
      fiatValue: existing.fiatValue + asset.fiatValue,
      address: existing.address.isNotEmpty ? existing.address : asset.address,
      tint: existing.tint,
      walletId:
          existing.walletId.isNotEmpty ? existing.walletId : asset.walletId,
      hasNetwork: existing.hasNetwork || asset.hasNetwork,
      hasFiatValue: existing.hasFiatValue || asset.hasFiatValue,
      hasAddress: existing.hasAddress || asset.hasAddress,
      canTopUp: existing.canTopUp || asset.canTopUp,
      canConvert: existing.canConvert || asset.canConvert,
    );
  }

  return merged.values.toList();
}

String _mergeNetworkNames(String left, String right) {
  final names = <String>{};
  for (final value in [left, right]) {
    for (final part in value.split('/')) {
      final name = part.trim();
      if (name.isNotEmpty) {
        names.add(name.toUpperCase());
      }
    }
  }

  return names.join(' / ');
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

String _assetName(String symbol) {
  return symbol.trim().toUpperCase();
}

String _walletId(PlatformResource resource) {
  return _textValue(resource.metadata, const [
        'walletId',
        'WalletId',
        'balanceId',
        'BalanceId',
        'id',
        'Id',
        'accountId',
        'AccountId',
      ]) ??
      resource.id;
}

bool _canTopUp(PlatformResource resource, String symbol) {
  final network = _networkName(resource)?.toLowerCase();
  if (symbol.toUpperCase() != 'USD') {
    return false;
  }

  final balanceType = _balanceType(resource)?.toLowerCase();
  if (balanceType != null) {
    return balanceType == 'quantumaccount' || balanceType == 'quantum account';
  }

  return network == null ||
      network == 'quantumaccount' ||
      network == 'quantum account';
}

bool _canConvert(PlatformResource resource, String symbol) {
  return _canTopUp(resource, symbol);
}

bool _shouldHideWalletAsset(PlatformResource resource, String symbol) {
  final normalized = symbol.toUpperCase();
  if (!const {'USD', 'USDC', 'USDT'}.contains(normalized)) return true;
  final type = _balanceType(resource)?.toLowerCase().replaceAll(' ', '');
  if (normalized == 'USD') {
    // Card balances belong to individual cards. The wallets view exposes the
    // Interlace Quantum account, matching the public dashboard contract.
    return type != null && type != 'quantumaccount';
  }
  return false;
}

String? _balanceType(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'balanceType',
    'BalanceType',
    'type',
    'Type',
  ]);
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

String? _depositAddress(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'address',
    'Address',
    'depositAddress',
    'DepositAddress',
    'walletAddress',
    'WalletAddress',
    'cryptoAddress',
    'CryptoAddress',
    'destinationAddress',
    'DestinationAddress',
    'publicAddress',
    'PublicAddress',
    'blockchainAddress',
    'BlockchainAddress',
  ]);
}

String? _networkName(PlatformResource resource) {
  return _textValue(resource.metadata, const [
    'network',
    'Network',
    'chain',
    'Chain',
    'blockchain',
    'Blockchain',
    'blockchainNetwork',
    'BlockchainNetwork',
    'protocol',
    'Protocol',
  ]);
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
