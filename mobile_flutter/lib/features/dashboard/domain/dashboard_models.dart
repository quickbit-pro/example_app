import 'package:flutter/material.dart';

import '../../../core/models/banking_models.dart';
import '../../transactions/domain/transaction_flow.dart';
import '../../wallets/domain/receiving_account_details.dart';

enum HoppaActivityKind { card, transfer, crypto, deposit, account }

class HoppaFiatAccount {
  const HoppaFiatAccount({
    required this.id,
    required this.name,
    required this.currency,
    required this.balance,
    required this.available,
    required this.iban,
    required this.tint,
    required this.provider,
    this.isPrimary = false,
    this.budgetId = '',
    this.accountNumber = '',
  });

  final String id;
  final String name;
  final String currency;
  final double balance;
  final double available;
  final String iban;
  final String accountNumber;
  final Color tint;
  final String provider;
  final bool isPrimary;

  /// The real Equals budget behind this row, when the currency is unambiguous.
  final String budgetId;

  String get maskedIban {
    final normalized = iban.replaceAll(RegExp(r'\s'), '').toUpperCase();
    if (normalized.length <= 8) return '';
    return '${normalized.substring(0, 2)}***'
        '${normalized.substring(normalized.length - 4)}';
  }

  String get maskedIdentifier => accountNumber.trim().isEmpty
      ? maskedIban
      : ReceivingAccountDetails(
          accountNumber: accountNumber,
          swift: '',
          bankName: '',
          holder: '',
        ).maskedIdentifier;
}

class HoppaCryptoHolding {
  const HoppaCryptoHolding({
    required this.symbol,
    required this.name,
    required this.amount,
    required this.fiatValue,
    required this.price,
    required this.changePercent,
    required this.tint,
    this.hasFiatValue = true,
    this.hasChangePercent = true,
  });

  final String symbol;
  final String name;
  final double amount;
  final double fiatValue;
  final double price;
  final double changePercent;
  final Color tint;
  final bool hasFiatValue;
  final bool hasChangePercent;
}

class HoppaActivity {
  const HoppaActivity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.kind,
    required this.timeLabel,
    required this.statusLabel,
    this.secondaryAmount,
    this.secondaryCurrency = '',
    this.merchantLogoUrl = '',
    this.bookedAt,
    this.transaction,
  });

  final String id;
  final String title;
  final String subtitle;
  final double amount;
  final String currency;
  final HoppaActivityKind kind;
  final String timeLabel;
  final String statusLabel;
  final double? secondaryAmount;
  final String secondaryCurrency;
  final String merchantLogoUrl;
  final DateTime? bookedAt;

  /// Original API row, retained so previews resolve the same real account or
  /// card reference as the full Activity list and receipt.
  final LedgerTransaction? transaction;

  /// Portfolio movement in the chart's unit. Display amounts may be in the
  /// merchant's or converted currency, so prefer the actual settlement amount.
  /// USDT/USDC may use the product's 1:1 USD estimate. Other missing currency
  /// valuations remain unknown, never a one-to-one conversion.
  double? balanceChangeIn(String baseCurrency,
      {bool estimateStablecoins = true,
      Map<String, double> valuationRates = const {}}) {
    final ledger = transaction;
    final status =
        ((ledger?.status.isNotEmpty ?? false) ? ledger!.status : statusLabel)
            .trim()
            .toLowerCase();
    if (const {
      'failed',
      'fail',
      'declined',
      'rejected',
      'cancelled',
      'canceled',
      'reverted',
      'pending',
      'created',
      'processing',
      'authorised',
      'authorized',
    }.contains(status)) {
      return 0;
    }
    if (ledger != null && transactionIsInternalMovement(ledger)) return 0;

    final base = baseCurrency.trim().toUpperCase();
    if (base.isEmpty) return null;
    final settlementAmount = ledger?.amount.decimalAmount ?? amount;
    if (settlementAmount == 0) return 0;
    if (ledger != null && ledger.amount.currency.trim().toUpperCase() == base) {
      return ledger.amount.decimalAmount;
    }
    if (secondaryAmount != null &&
        secondaryCurrency.trim().toUpperCase() == base) {
      return secondaryAmount;
    }
    if (currency.trim().toUpperCase() == base) return amount;
    if (estimateStablecoins && base == 'USD') {
      final settlementCurrency =
          (ledger?.amount.currency ?? currency).trim().toUpperCase();
      if (const {'USDT', 'USDC'}.contains(settlementCurrency)) {
        return ledger?.amount.decimalAmount ?? amount;
      }
    }
    final rate = valuationRates[
        (ledger?.amount.currency ?? currency).trim().toUpperCase()];
    if (rate != null && rate.isFinite && rate > 0) {
      return settlementAmount * rate;
    }
    return null;
  }

  /// Booked, by the ledger's own status when it has one.
  bool get isCompleted {
    final rawStatus = transaction?.status.trim() ?? '';
    final status =
        (rawStatus.isEmpty ? statusLabel : rawStatus).trim().toLowerCase();
    return const {
      'complete',
      'completed',
      'closed',
      'settled',
      'success',
      'successful',
      'succeeded',
      'posted',
    }.contains(status);
  }

  /// Only booked spending contributes to the total, count and largest payment.
  bool get isCompletedOutgoing => amount < 0 && isCompleted;

  /// Money moved between this customer's own holdings, which is neither
  /// spending nor income.
  bool get isInternalMovement {
    final ledger = transaction;
    return ledger != null && transactionIsInternalMovement(ledger);
  }
}

class HoppaDashboardSnapshot {
  const HoppaDashboardSnapshot({
    required this.customerName,
    required this.accounts,
    required this.holdings,
    required this.activities,
    required this.cards,
    required this.onboardingProgress,
    required this.marketSentiment,
    required this.requiresKyc,
    required this.accountReady,
    required this.exchangeEnabled,
    required this.outflowsEnabled,
    required this.referralsEnabled,
    required this.vouchersEnabled,
    required this.isBusinessAccount,
    required this.portfolioEstimate,
    this.fiatEnabled = true,
    this.cardBalancesAvailable = true,
    this.accountId = '',
  });

  /// False when the installation has no fiat (Equals Money) banking: Home,
  /// the Accounts hub and navigation then lead with crypto instead.
  final bool fiatEnabled;

  final String accountId;
  final String customerName;
  final List<HoppaFiatAccount> accounts;
  final List<HoppaCryptoHolding> holdings;
  final List<HoppaActivity> activities;
  final List<PaymentCard> cards;

  /// False when a current card balance could not be fetched.
  final bool cardBalancesAvailable;
  final double onboardingProgress;
  final String marketSentiment;
  final bool requiresKyc;
  final bool accountReady;
  final bool exchangeEnabled;
  final bool outflowsEnabled;
  final bool referralsEnabled;
  final bool vouchersEnabled;
  final bool isBusinessAccount;
  final PortfolioEstimate? portfolioEstimate;
}

class PortfolioEstimate {
  const PortfolioEstimate({
    required this.baseCurrency,
    required this.total,
    required this.valuedAt,
    required this.isPartial,
    required this.isStale,
    required this.missingCurrencies,
    this.providerTotals = const [],
    this.valuationRates = const {},
  });

  factory PortfolioEstimate.fromJson(Map<String, dynamic> json) {
    final missing = json['missingCurrencies'] ??
        json['MissingCurrencies'] ??
        json['unpricedAssetCodes'] ??
        json['UnpricedAssetCodes'];
    final providerTotals = json['providerTotals'] ?? json['ProviderTotals'];
    return PortfolioEstimate(
      baseCurrency: (json['currency'] ??
              json['Currency'] ??
              json['baseCurrency'] ??
              json['BaseCurrency'] ??
              'USD')
          .toString()
          .trim()
          .toUpperCase(),
      total: _dashboardDouble(
            json['total'] ??
                json['Total'] ??
                json['totalValue'] ??
                json['TotalValue'] ??
                json['estimatedTotalAssets'] ??
                json['EstimatedTotalAssets'],
          ) ??
          0,
      valuedAt: DateTime.tryParse(
        (json['valuedAt'] ??
                json['ValuedAt'] ??
                json['asOf'] ??
                json['AsOf'] ??
                json['calculatedAt'] ??
                json['CalculatedAt'] ??
                '')
            .toString(),
      ),
      isPartial: json['isPartial'] == true ||
          json['IsPartial'] == true ||
          json['isComplete'] == false ||
          json['IsComplete'] == false,
      isStale: json['isStale'] == true || json['IsStale'] == true,
      missingCurrencies: missing is List
          ? missing
              .map((value) => value.toString().trim().toUpperCase())
              .where((value) => value.isNotEmpty)
              .toList()
          : const [],
      providerTotals: providerTotals is List
          ? providerTotals
              .whereType<Map>()
              .map(
                (value) => PortfolioProviderTotal.fromJson(
                  Map<String, dynamic>.from(value),
                ),
              )
              .toList(growable: false)
          : const [],
      valuationRates: {
        for (final row in (json['valuationRates'] ?? const []) as List)
          if (row is Map &&
              (_dashboardDouble(row['rate']) ?? 0) > 0 &&
              (_dashboardDouble(row['rate']) ?? 0).isFinite)
            row['currency'].toString().trim().toUpperCase():
                _dashboardDouble(row['rate'])!,
      },
    );
  }

  final String baseCurrency;
  final double total;
  final DateTime? valuedAt;
  final bool isPartial;
  final bool isStale;
  final List<String> missingCurrencies;
  final List<PortfolioProviderTotal> providerTotals;
  final Map<String, double> valuationRates;
}

class PortfolioProviderTotal {
  const PortfolioProviderTotal({
    required this.provider,
    required this.total,
    required this.currency,
    required this.assetCount,
    required this.isAvailable,
    required this.unpricedAssetCodes,
  });

  factory PortfolioProviderTotal.fromJson(Map<String, dynamic> json) {
    final unpriced = json['unpricedAssetCodes'] ?? json['UnpricedAssetCodes'];
    return PortfolioProviderTotal(
      provider: (json['provider'] ?? json['Provider'] ?? '')
          .toString()
          .trim()
          .toLowerCase(),
      total: _dashboardDouble(
            json['estimatedTotalAssets'] ??
                json['EstimatedTotalAssets'] ??
                json['total'] ??
                json['Total'],
          ) ??
          0,
      currency: (json['currency'] ?? json['Currency'] ?? 'USD')
          .toString()
          .trim()
          .toUpperCase(),
      assetCount: int.tryParse(
            (json['assetCount'] ?? json['AssetCount'])?.toString() ?? '',
          ) ??
          0,
      isAvailable: (json['isAvailable'] ?? json['IsAvailable']) != false,
      unpricedAssetCodes: unpriced is List
          ? unpriced
              .map((value) => value.toString().trim().toUpperCase())
              .where((value) => value.isNotEmpty)
              .toList(growable: false)
          : const [],
    );
  }

  final String provider;
  final double total;
  final String currency;
  final int assetCount;
  final bool isAvailable;
  final List<String> unpricedAssetCodes;
}

double? _dashboardDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}
