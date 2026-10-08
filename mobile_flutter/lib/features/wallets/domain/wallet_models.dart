import 'package:flutter/material.dart';

enum WalletView { assets, addresses, balances, exchange }

class HoppaWalletAsset {
  const HoppaWalletAsset({
    required this.symbol,
    required this.name,
    required this.network,
    required this.amount,
    required this.fiatValue,
    required this.address,
    required this.tint,
    required this.walletId,
    this.hasNetwork = true,
    this.hasFiatValue = true,
    this.hasAddress = true,
    this.canTopUp = false,
    this.canConvert = false,
  });

  final String symbol;
  final String name;
  final String network;
  final double amount;
  final double fiatValue;
  final String address;
  final Color tint;
  final String walletId;
  final bool hasNetwork;
  final bool hasFiatValue;
  final bool hasAddress;
  final bool canTopUp;
  final bool canConvert;

  String get shortAddress {
    if (address.length <= 14) {
      return address;
    }

    return '${address.substring(0, 7)}...${address.substring(address.length - 6)}';
  }
}

class HoppaWalletBalance {
  const HoppaWalletBalance({
    required this.label,
    required this.currency,
    required this.available,
    required this.reserved,
  });

  final String label;
  final String currency;
  final double available;
  final double reserved;
}
