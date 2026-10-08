// Local display format, deliberately separate from permissive API parsing.
// Preserve precision, fee grouping, source identities and missing-value flags.
import 'package:flutter/material.dart';

import '../models/banking_models.dart';
import '../../features/dashboard/domain/dashboard_models.dart';

Map<String, dynamic> encodeMoney(Money value) => {
      'currency': value.currency,
      'minorUnits': value.minorUnits,
      'decimalAmount': value.decimalAmount,
    };

Money decodeMoney(Map<String, dynamic> json) => Money(
      currency: json['currency'] as String,
      minorUnits: json['minorUnits'] as int,
      decimalAmount: (json['decimalAmount'] as num).toDouble(),
    );

Map<String, dynamic> encodeLedgerTransaction(LedgerTransaction value) => {
      'id': value.id,
      'title': value.title,
      'subtitle': value.subtitle,
      'amount': encodeMoney(value.amount),
      'bookedAt': value.bookedAt.toIso8601String(),
      'type': value.type.name,
      'hasBookedAt': value.hasBookedAt,
      'accountId': value.accountId,
      'cardId': value.cardId,
      'walletId': value.walletId,
      'budgetId': value.budgetId,
      'rawType': value.rawType,
      'status': value.status,
      'isPrimary': value.isPrimary,
      'transactionAmount': value.transactionAmount == null
          ? null
          : encodeMoney(value.transactionAmount!),
      'metadata': value.metadata,
      'merchantLogoUrl': value.merchantLogoUrl,
      'merchantCategory': value.merchantCategory,
      'cardFees': value.cardFees.map(encodeLedgerTransaction).toList(),
    };

LedgerTransaction decodeLedgerTransaction(Map<String, dynamic> json) =>
    LedgerTransaction(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      amount: decodeMoney(Map<String, dynamic>.from(json['amount'] as Map)),
      bookedAt: DateTime.parse(json['bookedAt'] as String),
      type: TransactionType.values.byName(json['type'] as String),
      hasBookedAt: json['hasBookedAt'] as bool,
      accountId: json['accountId'] as String,
      cardId: json['cardId'] as String,
      walletId: json['walletId'] as String,
      budgetId: json['budgetId'] as String,
      rawType: json['rawType'] as String,
      status: json['status'] as String,
      isPrimary: json['isPrimary'] as bool,
      transactionAmount: json['transactionAmount'] == null
          ? null
          : decodeMoney(
              Map<String, dynamic>.from(json['transactionAmount'] as Map)),
      metadata: Map<String, dynamic>.from(json['metadata'] as Map),
      merchantLogoUrl: json['merchantLogoUrl'] as String,
      merchantCategory: json['merchantCategory'] as String,
      cardFees: (json['cardFees'] as List)
          .map((row) =>
              decodeLedgerTransaction(Map<String, dynamic>.from(row as Map)))
          .toList(),
    );

Map<String, dynamic> encodePaymentCard(PaymentCard value) => {
      'id': value.id,
      'label': value.label,
      'last4': value.last4,
      'network': value.network,
      'currency': value.currency,
      'status': value.status.name,
      'balance': encodeMoney(value.balance),
      'hasReportedBalance': value.hasReportedBalance,
      'spendThisMonth': encodeMoney(value.spendThisMonth),
      'limit': encodeMoney(value.limit),
      'virtual': value.virtual,
      'canSetPin': value.canSetPin,
      'bankProvider': value.bankProvider,
      'budgetId': value.budgetId,
      'budgetName': value.budgetName,
      'cardTypeId': value.cardTypeId,
      'cardTypeName': value.cardTypeName,
      'discountCode': value.discountCode,
      'cardImageUrl': value.cardImageUrl,
      'cardThumbnailUrl': value.cardThumbnailUrl,
      'cardPreviewUrl': value.cardPreviewUrl,
      'cardBackImageUrl': value.cardBackImageUrl,
      'cardBackThumbnailUrl': value.cardBackThumbnailUrl,
      'cardBackPreviewUrl': value.cardBackPreviewUrl,
      'cardImageAlt': value.cardImageAlt,
      'cardTextColor': value.cardTextColor,
    };

PaymentCard decodePaymentCard(Map<String, dynamic> json) => PaymentCard(
      id: json['id'] as String,
      label: json['label'] as String,
      last4: json['last4'] as String,
      network: json['network'] as String,
      currency: json['currency'] as String,
      status: CardStatus.values.byName(json['status'] as String),
      balance: decodeMoney(Map<String, dynamic>.from(json['balance'] as Map)),
      hasReportedBalance: json['hasReportedBalance'] as bool,
      spendThisMonth:
          decodeMoney(Map<String, dynamic>.from(json['spendThisMonth'] as Map)),
      limit: decodeMoney(Map<String, dynamic>.from(json['limit'] as Map)),
      virtual: json['virtual'] as bool,
      canSetPin: json['canSetPin'] as bool,
      bankProvider: json['bankProvider'] as String,
      budgetId: json['budgetId'] as String,
      budgetName: json['budgetName'] as String,
      cardTypeId: json['cardTypeId'] == null ? null : json['cardTypeId'] as int,
      cardTypeName: json['cardTypeName'] as String,
      discountCode: json['discountCode'] as String? ?? '',
      cardImageUrl: json['cardImageUrl'] as String,
      cardThumbnailUrl: json['cardThumbnailUrl'] as String,
      cardPreviewUrl: json['cardPreviewUrl'] as String,
      cardBackImageUrl: json['cardBackImageUrl'] as String,
      cardBackThumbnailUrl: json['cardBackThumbnailUrl'] as String,
      cardBackPreviewUrl: json['cardBackPreviewUrl'] as String,
      cardImageAlt: json['cardImageAlt'] as String,
      cardTextColor: json['cardTextColor'] as String,
    );

Map<String, dynamic> encodeHoppaFiatAccount(HoppaFiatAccount value) => {
      'id': value.id,
      'name': value.name,
      'currency': value.currency,
      'balance': value.balance,
      'available': value.available,
      'iban': value.iban,
      'tint': value.tint.toARGB32(),
      'provider': value.provider,
      'isPrimary': value.isPrimary,
      'budgetId': value.budgetId,
      'accountNumber': value.accountNumber,
    };

HoppaFiatAccount decodeHoppaFiatAccount(Map<String, dynamic> json) =>
    HoppaFiatAccount(
      id: json['id'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String,
      balance: (json['balance'] as num).toDouble(),
      available: (json['available'] as num).toDouble(),
      iban: json['iban'] as String,
      tint: Color(json['tint'] as int),
      provider: json['provider'] as String,
      isPrimary: json['isPrimary'] as bool,
      budgetId: json['budgetId'] as String,
      accountNumber: json['accountNumber'] as String,
    );

Map<String, dynamic> encodeHoppaCryptoHolding(HoppaCryptoHolding value) => {
      'symbol': value.symbol,
      'name': value.name,
      'amount': value.amount,
      'fiatValue': value.fiatValue,
      'price': value.price,
      'changePercent': value.changePercent,
      'tint': value.tint.toARGB32(),
      'hasFiatValue': value.hasFiatValue,
      'hasChangePercent': value.hasChangePercent,
    };

HoppaCryptoHolding decodeHoppaCryptoHolding(Map<String, dynamic> json) =>
    HoppaCryptoHolding(
      symbol: json['symbol'] as String,
      name: json['name'] as String,
      amount: (json['amount'] as num).toDouble(),
      fiatValue: (json['fiatValue'] as num).toDouble(),
      price: (json['price'] as num).toDouble(),
      changePercent: (json['changePercent'] as num).toDouble(),
      tint: Color(json['tint'] as int),
      hasFiatValue: json['hasFiatValue'] as bool,
      hasChangePercent: json['hasChangePercent'] as bool,
    );

Map<String, dynamic> encodeHoppaActivity(HoppaActivity value) => {
      'id': value.id,
      'title': value.title,
      'subtitle': value.subtitle,
      'amount': value.amount,
      'currency': value.currency,
      'kind': value.kind.name,
      'timeLabel': value.timeLabel,
      'statusLabel': value.statusLabel,
      'secondaryAmount': value.secondaryAmount,
      'secondaryCurrency': value.secondaryCurrency,
      'merchantLogoUrl': value.merchantLogoUrl,
      'bookedAt': value.bookedAt?.toIso8601String(),
      'transaction': value.transaction == null
          ? null
          : encodeLedgerTransaction(value.transaction!),
    };

HoppaActivity decodeHoppaActivity(Map<String, dynamic> json) => HoppaActivity(
      id: json['id'] as String,
      title: json['title'] as String,
      subtitle: json['subtitle'] as String,
      amount: (json['amount'] as num).toDouble(),
      currency: json['currency'] as String,
      kind: HoppaActivityKind.values.byName(json['kind'] as String),
      timeLabel: json['timeLabel'] as String,
      statusLabel: json['statusLabel'] as String,
      secondaryAmount: json['secondaryAmount'] == null
          ? null
          : (json['secondaryAmount'] as num).toDouble(),
      secondaryCurrency: json['secondaryCurrency'] as String,
      merchantLogoUrl: json['merchantLogoUrl'] as String,
      bookedAt: json['bookedAt'] == null
          ? null
          : DateTime.parse(json['bookedAt'] as String),
      transaction: json['transaction'] == null
          ? null
          : decodeLedgerTransaction(
              Map<String, dynamic>.from(json['transaction'] as Map)),
    );

Map<String, dynamic> encodePortfolioProviderTotal(
        PortfolioProviderTotal value) =>
    {
      'provider': value.provider,
      'total': value.total,
      'currency': value.currency,
      'assetCount': value.assetCount,
      'isAvailable': value.isAvailable,
      'unpricedAssetCodes': value.unpricedAssetCodes,
    };

PortfolioProviderTotal decodePortfolioProviderTotal(
        Map<String, dynamic> json) =>
    PortfolioProviderTotal(
      provider: json['provider'] as String,
      total: (json['total'] as num).toDouble(),
      currency: json['currency'] as String,
      assetCount: json['assetCount'] as int,
      isAvailable: json['isAvailable'] as bool,
      unpricedAssetCodes: (json['unpricedAssetCodes'] as List).cast<String>(),
    );

Map<String, dynamic> encodePortfolioEstimate(PortfolioEstimate value) => {
      'baseCurrency': value.baseCurrency,
      'total': value.total,
      'valuedAt': value.valuedAt?.toIso8601String(),
      'isPartial': value.isPartial,
      'isStale': value.isStale,
      'missingCurrencies': value.missingCurrencies,
      'providerTotals':
          value.providerTotals.map(encodePortfolioProviderTotal).toList(),
      'valuationRates': value.valuationRates,
    };

PortfolioEstimate decodePortfolioEstimate(Map<String, dynamic> json) =>
    PortfolioEstimate(
      baseCurrency: json['baseCurrency'] as String,
      total: (json['total'] as num).toDouble(),
      valuedAt: json['valuedAt'] == null
          ? null
          : DateTime.parse(json['valuedAt'] as String),
      isPartial: json['isPartial'] as bool,
      isStale: json['isStale'] as bool,
      missingCurrencies: (json['missingCurrencies'] as List).cast<String>(),
      providerTotals: (json['providerTotals'] as List)
          .map((row) => decodePortfolioProviderTotal(
              Map<String, dynamic>.from(row as Map)))
          .toList(),
      valuationRates: (json['valuationRates'] as Map).map(
          (key, value) => MapEntry(key as String, (value as num).toDouble())),
    );

Map<String, dynamic> encodeHoppaDashboardSnapshot(
        HoppaDashboardSnapshot value) =>
    {
      'customerName': value.customerName,
      'accountId': value.accountId,
      'accounts': value.accounts.map(encodeHoppaFiatAccount).toList(),
      'holdings': value.holdings.map(encodeHoppaCryptoHolding).toList(),
      'activities': value.activities.map(encodeHoppaActivity).toList(),
      'cards': value.cards.map(encodePaymentCard).toList(),
      'onboardingProgress': value.onboardingProgress,
      'marketSentiment': value.marketSentiment,
      'requiresKyc': value.requiresKyc,
      'accountReady': value.accountReady,
      'exchangeEnabled': value.exchangeEnabled,
      'outflowsEnabled': value.outflowsEnabled,
      'referralsEnabled': value.referralsEnabled,
      'vouchersEnabled': value.vouchersEnabled,
      'isBusinessAccount': value.isBusinessAccount,
      'fiatEnabled': value.fiatEnabled,
      'cardBalancesAvailable': value.cardBalancesAvailable,
      'portfolioEstimate': value.portfolioEstimate == null
          ? null
          : encodePortfolioEstimate(value.portfolioEstimate!),
    };

HoppaDashboardSnapshot decodeHoppaDashboardSnapshot(
        Map<String, dynamic> json) =>
    HoppaDashboardSnapshot(
      customerName: json['customerName'] as String,
      accountId: json['accountId'] as String? ?? '',
      accounts: (json['accounts'] as List)
          .map((row) =>
              decodeHoppaFiatAccount(Map<String, dynamic>.from(row as Map)))
          .toList(),
      holdings: (json['holdings'] as List)
          .map((row) =>
              decodeHoppaCryptoHolding(Map<String, dynamic>.from(row as Map)))
          .toList(),
      activities: (json['activities'] as List)
          .map((row) =>
              decodeHoppaActivity(Map<String, dynamic>.from(row as Map)))
          .toList(),
      cards: (json['cards'] as List)
          .map(
              (row) => decodePaymentCard(Map<String, dynamic>.from(row as Map)))
          .toList(),
      onboardingProgress: (json['onboardingProgress'] as num).toDouble(),
      marketSentiment: json['marketSentiment'] as String,
      requiresKyc: json['requiresKyc'] as bool,
      accountReady: json['accountReady'] as bool,
      exchangeEnabled: json['exchangeEnabled'] as bool,
      outflowsEnabled: json['outflowsEnabled'] as bool,
      referralsEnabled: json['referralsEnabled'] as bool,
      vouchersEnabled: json['vouchersEnabled'] as bool,
      isBusinessAccount: json['isBusinessAccount'] as bool,
      fiatEnabled: json['fiatEnabled'] as bool,
      cardBalancesAvailable: json['cardBalancesAvailable'] as bool,
      portfolioEstimate: json['portfolioEstimate'] == null
          ? null
          : decodePortfolioEstimate(
              Map<String, dynamic>.from(json['portfolioEstimate'] as Map)),
    );

Map<String, dynamic> encodeActivity(List<LedgerTransaction> rows) => {
      'transactions': rows.map(encodeLedgerTransaction).toList(),
    };

List<LedgerTransaction> decodeActivity(Map<String, dynamic> json) =>
    (json['transactions'] as List)
        .map((row) =>
            decodeLedgerTransaction(Map<String, dynamic>.from(row as Map)))
        .toList();
