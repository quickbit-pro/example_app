import 'package:flutter/material.dart';

enum CryptoTradeSide { buy, sell }

class HoppaMarketAsset {
  const HoppaMarketAsset({
    required this.symbol,
    required this.name,
    required this.price,
    required this.changePercent,
    required this.marketCapRank,
    required this.sparkline,
    required this.tint,
    this.hasPrice = true,
    this.hasChangePercent = true,
    this.hasMarketCapRank = true,
  });

  final String symbol;
  final String name;
  final double price;
  final double changePercent;
  final int marketCapRank;
  final List<double> sparkline;
  final Color tint;
  final bool hasPrice;
  final bool hasChangePercent;
  final bool hasMarketCapRank;
}

class HoppaPortfolioPosition {
  const HoppaPortfolioPosition({
    required this.asset,
    required this.amount,
    required this.costBasis,
    this.valueOverride,
  });

  final HoppaMarketAsset asset;
  final double amount;
  final double costBasis;
  final double? valueOverride;

  double get value => valueOverride ?? amount * asset.price;

  double get profitLoss => value - costBasis;

  double get profitLossPercent =>
      costBasis == 0 ? 0 : (profitLoss / costBasis) * 100;
}
