import 'dart:convert';

import 'equals_money.dart';

enum OnboardingTaskStatus { pending, inProgress, complete, blocked }

enum CardStatus { active, frozen, pending, cancelled }

enum TransactionType { card, transfer, topUp, payment, fee }

class Money {
  const Money({
    required this.currency,
    required this.minorUnits,
    double? decimalAmount,
  }) : _decimalAmount = decimalAmount;

  factory Money.fromJson(
    Map<String, dynamic> json, {
    bool preservePrecision = false,
  }) {
    final currency =
        (json['currency'] ?? json['Currency'])?.toString() ?? 'EUR';
    final minorUnitValue = json['minorUnits'] ??
        json['MinorUnits'] ??
        json['amountMinor'] ??
        json['AmountMinor'];
    final decimalValue = json['available'] ??
        json['Available'] ??
        json['amount'] ??
        json['Amount'] ??
        json['value'] ??
        json['Value'];

    return Money(
      currency: currency,
      minorUnits: minorUnitValue == null
          ? _parseDecimalAmount(decimalValue)
          : _parseWholeMinorUnits(minorUnitValue),
      decimalAmount: preservePrecision && minorUnitValue == null
          ? _parseDecimal(decimalValue)
          : null,
    );
  }

  final String currency;
  final int minorUnits;
  final double? _decimalAmount;

  /// Provider amount in its own currency. Ledger parsing keeps native crypto
  /// decimals here; existing cent-based constructors retain their behavior.
  double get decimalAmount => _decimalAmount ?? minorUnits / 100;
  bool get isPositive => decimalAmount > 0;
  bool get isNegative => decimalAmount < 0;

  Money get negated => Money(
        currency: currency,
        minorUnits: -minorUnits,
        decimalAmount: _decimalAmount == null ? null : -_decimalAmount,
      );

  /// Human display form: `\$4,562.35`, `€6,234.75`, `-£12.00`,
  /// `1,420.00 USDC`. Crypto keeps meaningful decimals and a minimum of two.
  String get formatted => formatAmount(currency, decimalAmount);

  /// Fiat identity uses the banking provider's full supported currency list.
  /// Keep this separate from the amount formatter's existing decimal rules.
  static bool isFiatCurrency(String currency) {
    final code = currency.trim().toUpperCase();
    return _fiatCodes.contains(code) ||
        equalsSupportedCurrencyCodes.contains(code);
  }

  static const _fiatSymbols = {'USD': '\$', 'EUR': '€', 'GBP': '£'};
  static const _sixDecimalAssets = {'USDC', 'USDT'};
  static const _fiatCodes = {
    'USD',
    'EUR',
    'GBP',
    'AED',
    'CHF',
    'CAD',
    'AUD',
    'JPY',
    'SEK',
    'NOK',
    'DKK',
    'PLN',
    'CZK',
    'HUF',
    'RON',
    'BGN',
    'TRY',
    'ZAR',
    'SGD',
    'HKD',
    'NZD',
    'MXN',
    'BRL',
    'INR',
    'SAR',
    'QAR',
    'KWD',
    'BHD',
  };

  /// One formatter for every amount in the app so decimals stay consistent:
  /// fiat two decimals with a symbol where we have one, USDC/USDT up to six
  /// decimals and other crypto up to eight, with a minimum of two decimals.
  /// When Private Mode is on every amount renders as dots. Set by the
  /// private-mode controller before the app rebuilds.
  static bool maskAmounts = false;

  static String formatAmount(String currency, double amount) {
    if (maskAmounts) return '••••';
    return formatPlainAmount(currency, amount);
  }

  /// [formatAmount] without the Private Mode mask, for text that leaves the
  /// device (a shared invitation) where dots would be meaningless.
  static String formatPlainAmount(String currency, double amount) {
    final code = currency.trim().toUpperCase();
    final sign = amount < 0 ? '-' : '';
    final absolute = amount.abs();
    final decimals = _sixDecimalAssets.contains(code)
        ? 6
        : _fiatCodes.contains(code) || code.isEmpty
            ? 2
            : null;
    var fixed = absolute.toStringAsFixed(decimals ?? 8);
    if (decimals != 2) {
      final minimumLength = fixed.indexOf('.') + 3;
      while (fixed.length > minimumLength && fixed.endsWith('0')) {
        fixed = fixed.substring(0, fixed.length - 1);
      }
    }
    final dot = fixed.indexOf('.');
    final whole = _groupThousands(dot < 0 ? fixed : fixed.substring(0, dot));
    final fraction = dot < 0 ? '' : fixed.substring(dot);
    final symbol = _fiatSymbols[code];
    if (symbol != null) return '$sign$symbol$whole$fraction';
    return '$sign$whole$fraction${code.isEmpty ? '' : ' $code'}';
  }

  static String _groupThousands(String whole) {
    final buffer = StringBuffer();
    for (var index = 0; index < whole.length; index++) {
      final remaining = whole.length - index;
      buffer.write(whole[index]);
      if (remaining > 1 && remaining % 3 == 1) buffer.write(',');
    }
    return buffer.toString();
  }

  static int _parseWholeMinorUnits(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value) ??
          (double.tryParse(value.replaceAll(',', '.')) ?? 0).round();
    }

    return 0;
  }

  static int _parseDecimalAmount(Object? value) {
    if (value is int) {
      return value * 100;
    }
    if (value is num) {
      return (value * 100).round();
    }
    if (value is String) {
      return ((double.tryParse(value.replaceAll(',', '.')) ?? 0) * 100).round();
    }

    return 0;
  }
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.accountType,
    required this.kycStatus,
    required this.businessStatus,
    required this.onboardingStatus,
    this.interlaceKycApproved = false,
    this.nickname,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final firstName = json['firstName'] ?? json['FirstName'];
    final lastName = json['lastName'] ?? json['LastName'];
    final composedName = [firstName, lastName]
        .where((part) => part != null && part.toString().trim().isNotEmpty)
        .join(' ');

    return UserProfile(
      id: (json['id'] ?? json['Id'] ?? json['userId'] ?? json['UserId'])
              ?.toString() ??
          '',
      name: (json['name'] ??
                  json['Name'] ??
                  json['fullName'] ??
                  json['FullName'] ??
                  (composedName.isEmpty ? null : composedName))
              ?.toString() ??
          'User',
      email: (json['email'] ?? json['Email'])?.toString() ?? '',
      nickname: (json['nickname'] ?? json['Nickname'])?.toString(),
      accountType: (json['accountType'] ?? json['AccountType'])?.toString() ??
          'personal',
      kycStatus:
          (json['kycStatus'] ?? json['KycStatus'])?.toString() ?? 'pending',
      businessStatus:
          (json['businessStatus'] ?? json['BusinessStatus'])?.toString() ??
              'not_started',
      interlaceKycApproved:
          (json['interlaceKycApproved'] ?? json['InterlaceKycApproved']) ==
              true,
      onboardingStatus:
          (json['onboardingStatus'] ?? json['OnboardingStatus'])?.toString() ??
              'not_started',
    );
  }

  final String id;
  final String name;
  final String email;
  final String accountType;
  final String kycStatus;
  final String businessStatus;
  final String onboardingStatus;
  final bool interlaceKycApproved;
  final String? nickname;

  bool get isKycReady => _isReadyStatus(kycStatus);

  bool get isBusinessAccount => accountType.toLowerCase().trim() == 'business';

  bool get isBankOnboarded => _isReadyStatus(onboardingStatus);
}

extension DashboardReadiness on DashboardSnapshot {
  bool get canUseBanking => profile.isBankOnboarded || accounts.isNotEmpty;

  bool get canOrderCard => profile.interlaceKycApproved;
}

bool _isReadyStatus(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '-').trim();
  return normalized == 'approved' ||
      normalized == 'verified' ||
      normalized == 'complete' ||
      normalized == 'completed' ||
      normalized == 'active' ||
      normalized == 'ready';
}

class AccountBalance {
  const AccountBalance({
    required this.id,
    required this.name,
    required this.iban,
    required this.balance,
    required this.available,
    this.accountNumber = '',
    this.provider = '',
    this.status = '',
    this.supportedCurrencies = const [],
    this.currencyBalances = const [],
    this.linkedBankAccounts = const [],
    this.hasBalanceCurrency = true,
    this.budgetId = '',
    this.parentAccountId = '',
    this.accountType = '',
    this.accountHolderName = '',
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) {
    final linkedBankAccounts = _bankAccountDetailsList(
      json['linkedBankAccounts'] ?? json['LinkedBankAccounts'],
    );
    final primaryBank = linkedBankAccounts.firstOrNull;
    final accountId = json['id'] ??
        json['accountId'] ??
        json['AccountId'] ??
        json['balanceId'] ??
        json['BalanceId'];
    final displayName =
        json['name'] ?? json['displayName'] ?? json['DisplayName'];
    final iban = json['iban'] ??
        json['Iban'] ??
        primaryBank?.iban ??
        json['ibanLast4'] ??
        json['IbanLast4'];
    final balanceValue = json['balance'] ?? json['Balance'];
    final balanceCurrency = balanceValue is Map
        ? (balanceValue['currency'] ?? balanceValue['Currency'])
            ?.toString()
            .trim()
        : null;
    final hasBalanceCurrency = balanceCurrency?.isNotEmpty == true;
    return AccountBalance(
      id: accountId?.toString() ?? '',
      name: displayName?.toString() ?? 'Account',
      iban: iban?.toString() ?? '',
      balance: Money.fromJson(_moneyJson(balanceValue,
          currency: hasBalanceCurrency ? balanceCurrency! : 'USD')),
      available: Money.fromJson(
        _moneyJson(
          json['available'] ??
              json['availableBalance'] ??
              json['AvailableBalance'],
        ),
      ),
      accountNumber:
          (json['accountNumber'] ?? json['AccountNumber'])?.toString() ??
              primaryBank?.accountNumber ??
              '',
      provider: (json['provider'] ?? json['Provider'])?.toString() ?? '',
      status: (json['status'] ?? json['Status'])?.toString() ?? '',
      supportedCurrencies: _stringList(
        json['supportedCurrencies'] ?? json['SupportedCurrencies'],
      ),
      currencyBalances: _currencyBalanceList(json),
      linkedBankAccounts: linkedBankAccounts,
      hasBalanceCurrency: hasBalanceCurrency,
      budgetId: (json['budgetId'] ?? json['BudgetId'])?.toString() ?? '',
      parentAccountId:
          (json['parentAccountId'] ?? json['ParentAccountId'])?.toString() ??
              '',
      accountType:
          (json['accountType'] ?? json['AccountType'])?.toString() ?? '',
      accountHolderName:
          (json['accountHolderName'] ?? json['AccountHolderName'])
                  ?.toString() ??
              '',
    );
  }

  final String id;
  final String name;
  final String iban;
  final Money balance;
  final Money available;
  final String accountNumber;
  final String provider;
  final String status;
  final List<String> supportedCurrencies;
  final List<Money> currencyBalances;
  final List<BankAccountDetails> linkedBankAccounts;

  /// The API supplied the balance currency. A legacy display fallback must
  /// never become a currency filter for an otherwise unqualified account.
  final bool hasBalanceCurrency;

  /// Unified Equals accounts expose the shared owner as [id] and the actual
  /// allocated account as [budgetId]. Keep both; they are not interchangeable.
  final String budgetId;
  final String parentAccountId;
  final String accountType;
  final String accountHolderName;
}

class BankAccountDetails {
  const BankAccountDetails({
    required this.currency,
    required this.accountNumber,
    required this.iban,
    required this.bankName,
    required this.swift,
    required this.routingNumber,
    required this.routingType,
    required this.status,
  });

  factory BankAccountDetails.fromJson(Map<String, dynamic> json) {
    return BankAccountDetails(
      currency: (json['currency'] ?? json['Currency'])?.toString() ?? '',
      accountNumber:
          (json['accountNumber'] ?? json['AccountNumber'])?.toString() ?? '',
      iban: (json['iban'] ?? json['Iban'])?.toString() ?? '',
      bankName: (json['bankName'] ?? json['BankName'])?.toString() ?? '',
      swift: (json['swift'] ??
                  json['Swift'] ??
                  json['swiftCode'] ??
                  json['SwiftCode'])
              ?.toString() ??
          '',
      routingNumber:
          (json['routingNumber'] ?? json['RoutingNumber'])?.toString() ?? '',
      routingType:
          (json['routingType'] ?? json['RoutingType'])?.toString() ?? '',
      status: (json['status'] ?? json['Status'])?.toString() ?? '',
    );
  }

  final String currency;
  final String accountNumber;
  final String iban;
  final String bankName;
  final String swift;
  final String routingNumber;
  final String routingType;
  final String status;

  String get displayReference {
    if (iban.trim().isNotEmpty) {
      return iban;
    }
    if (accountNumber.trim().isNotEmpty) {
      return accountNumber;
    }
    return '';
  }
}

List<BankAccountDetails> _bankAccountDetailsList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .map(BankAccountDetails.fromJson)
      .toList();
}

List<String> _stringList(Object? value) {
  if (value is! List) {
    return const [];
  }

  return value
      .map((item) => item?.toString().trim() ?? '')
      .where((item) => item.isNotEmpty)
      .toList();
}

double _parseDecimal(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.replaceAll(',', '.')) ?? 0;
  }

  return 0;
}

double? _parseNullableDecimal(Object? value) {
  if (value == null) {
    return null;
  }

  return _parseDecimal(value);
}

int? _parseNullableInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }

  return null;
}

class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.label,
    required this.last4,
    required this.network,
    required this.currency,
    required this.status,
    required this.balance,
    this.hasReportedBalance = true,
    required this.spendThisMonth,
    required this.limit,
    required this.virtual,
    this.canSetPin = false,
    this.bankProvider = '',
    this.budgetId = '',
    this.budgetName = '',
    this.cardTypeId,
    this.cardTypeName = '',
    this.discountCode = '',
    this.cardImageUrl = '',
    this.cardThumbnailUrl = '',
    this.cardPreviewUrl = '',
    this.cardBackImageUrl = '',
    this.cardBackThumbnailUrl = '',
    this.cardBackPreviewUrl = '',
    this.cardImageAlt = '',
    this.cardTextColor = '',
  });

  factory PaymentCard.fromJson(Map<String, dynamic> json) {
    final source = _unwrapCardJson(json);
    final cardId = json['id'] ?? json['Id'] ?? json['cardId'] ?? json['CardId'];
    final resolvedCardId =
        source['id'] ?? source['Id'] ?? source['cardId'] ?? source['CardId'];
    final artwork = _cardArtworkSource(source);
    final label = source['label'] ??
        source['name'] ??
        source['Nickname'] ??
        source['CardName'] ??
        source['cardTypeName'] ??
        source['CardTypeName'] ??
        source['productCode'];
    final network = _firstString(source, const [
          'network',
          'Network',
          'brand',
          'Brand',
          'cardNetwork',
          'CardNetwork',
          'paymentNetwork',
          'PaymentNetwork',
          'cardBrand',
          'CardBrand',
          'cardScheme',
          'CardScheme',
          'scheme',
          'Scheme',
        ]) ??
        _firstString(artwork, const [
          'network',
          'Network',
          'brand',
          'Brand',
          'cardNetwork',
          'CardNetwork',
          'paymentNetwork',
          'PaymentNetwork',
          'cardBrand',
          'CardBrand',
          'cardScheme',
          'CardScheme',
          'scheme',
          'Scheme',
        ]);
    final cardNumber =
        (source['cardNumber'] ?? source['CardNumber'])?.toString();
    final currency = _cardCurrencyFromJson(source);
    final balanceJson = _cardBalanceJson(source, currency: currency);
    return PaymentCard(
      id: resolvedCardId?.toString() ?? cardId?.toString() ?? '',
      label: label?.toString() ?? 'Card',
      last4: (source['last4'] ?? source['Last4'])?.toString() ??
          (cardNumber == null || cardNumber.length < 4
              ? ''
              : cardNumber.substring(cardNumber.length - 4)),
      network: network ?? _cardNetworkFromNumber(cardNumber),
      currency: currency,
      status: _cardStatus(
          (source['status'] ?? source['Status'])?.toString() ?? 'pending'),
      balance:
          Money.fromJson(balanceJson ?? _moneyJson(null, currency: currency)),
      hasReportedBalance: balanceJson != null,
      spendThisMonth: Money.fromJson(
        _moneyJson(
          source['spendThisMonth'] ?? source['SpendThisMonth'],
          currency: currency,
        ),
      ),
      limit: Money.fromJson(
        _moneyJson(source['limit'] ?? source['Limit'], currency: currency),
      ),
      virtual: (source['virtual'] as bool?) ??
          (source['Virtual'] as bool?) ??
          ((source['CardType'] ?? source['cardType'])
                  ?.toString()
                  .toLowerCase()
                  .contains('virtual') ??
              true),
      // Hoppa flags cards whose PIN the customer may choose in the app.
      canSetPin: (source['canSetPin'] as bool?) ??
          (source['CanSetPin'] as bool?) ??
          (json['canSetPin'] as bool?) ??
          false,
      bankProvider: _cardBankProvider(source),
      budgetId: _firstString(source, const [
            'budgetId',
            'BudgetId',
            'budgetID',
            'BudgetID',
            'cardBudgetId',
            'CardBudgetId',
          ]) ??
          _firstString(_nestedMap(source, const ['budget', 'Budget']),
              const ['id', 'Id', 'accountId', 'AccountId']) ??
          '',
      budgetName: _firstString(source, const [
            'budgetName',
            'BudgetName',
          ]) ??
          _firstString(_nestedMap(source, const ['budget', 'Budget']), const [
            'name',
            'Name',
            'displayName',
            'DisplayName',
          ]) ??
          '',
      cardTypeId: _firstInt(source, const [
            'cardTypeId',
            'CardTypeId',
            'cardTypeTierId',
            'CardTypeTierId',
          ]) ??
          _firstInt(artwork, const ['id', 'Id', 'cardTypeId', 'CardTypeId']),
      discountCode: _firstString(source, const [
            'discountCode',
            'DiscountCode',
            'discount_code'
          ])?.trim() ??
          '',
      cardTypeName: _firstString(source, const [
            'cardTypeName',
            'CardTypeName',
          ]) ??
          _firstString(artwork, const [
            'name',
            'Name',
            'displayName',
            'DisplayName',
            'cardTypeName',
            'CardTypeName',
          ]) ??
          '',
      cardImageUrl: _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardImageUrl',
        'CardImageUrl',
        'imageUrl',
        'ImageUrl',
      ])),
      cardThumbnailUrl: _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardThumbnailUrl',
        'CardThumbnailUrl',
        'thumbnailUrl',
        'ThumbnailUrl',
      ])),
      cardPreviewUrl: _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardPreviewUrl',
        'CardPreviewUrl',
        'previewUrl',
        'PreviewUrl',
      ])),
      cardBackImageUrl: _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardBackImageUrl',
        'CardBackImageUrl',
      ])),
      cardBackThumbnailUrl:
          _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardBackThumbnailUrl',
        'CardBackThumbnailUrl',
      ])),
      cardBackPreviewUrl: _normalizeCardArtworkUrl(_firstString(artwork, const [
        'cardBackPreviewUrl',
        'CardBackPreviewUrl',
      ])),
      cardImageAlt: _firstString(artwork, const [
            'cardImageAlt',
            'CardImageAlt',
            'imageAlt',
            'ImageAlt',
          ]) ??
          '',
      cardTextColor: _firstString(artwork, const [
            'cardTextColor',
            'CardTextColor',
            'textColor',
            'TextColor',
          ]) ??
          '',
    );
  }

  final String id;
  final String label;
  final String last4;
  final String network;
  final String currency;
  final CardStatus status;
  final Money balance;

  /// Whether this response reported a balance, including an explicit zero.
  /// A balance borrowed from the card list is not a current detail balance.
  final bool hasReportedBalance;
  final Money spendThisMonth;
  final Money limit;
  final bool virtual;

  /// True when the provider lets the customer set this card's PIN in-app.
  final bool canSetPin;
  final String bankProvider;
  final String budgetId;
  final String budgetName;
  final int? cardTypeId;
  final String cardTypeName;
  final String discountCode;
  final String cardImageUrl;
  final String cardThumbnailUrl;
  final String cardPreviewUrl;
  final String cardBackImageUrl;
  final String cardBackThumbnailUrl;
  final String cardBackPreviewUrl;
  final String cardImageAlt;
  final String cardTextColor;

  String get artworkUrl {
    if (cardImageUrl.isNotEmpty) return cardImageUrl;
    if (cardPreviewUrl.isNotEmpty) return cardPreviewUrl;
    return cardThumbnailUrl;
  }

  String get backArtworkUrl {
    if (cardBackImageUrl.isNotEmpty) return cardBackImageUrl;
    if (cardBackPreviewUrl.isNotEmpty) return cardBackPreviewUrl;
    return cardBackThumbnailUrl;
  }

  /// Older tiers can omit back artwork; retain their existing presentation.
  String get secureArtworkUrl =>
      backArtworkUrl.isNotEmpty ? backArtworkUrl : artworkUrl;

  PaymentCard withFallback(PaymentCard fallback) {
    return PaymentCard(
      id: id.isEmpty ? fallback.id : id,
      label: label == 'Card' || label.isEmpty ? fallback.label : label,
      last4: last4.isEmpty ? fallback.last4 : last4,
      network: network.isEmpty ? fallback.network : network,
      currency: currency.isEmpty ? fallback.currency : currency,
      status: status,
      balance: hasReportedBalance ? balance : fallback.balance,
      hasReportedBalance: hasReportedBalance,
      spendThisMonth: spendThisMonth.minorUnits == 0
          ? fallback.spendThisMonth
          : spendThisMonth,
      limit: limit.minorUnits == 0 ? fallback.limit : limit,
      virtual: virtual,
      bankProvider: bankProvider.isEmpty ? fallback.bankProvider : bankProvider,
      budgetId: budgetId.isEmpty ? fallback.budgetId : budgetId,
      budgetName: budgetName.isEmpty ? fallback.budgetName : budgetName,
      cardTypeId: cardTypeId ?? fallback.cardTypeId,
      cardTypeName: cardTypeName.isEmpty ? fallback.cardTypeName : cardTypeName,
      cardImageUrl: cardImageUrl.isEmpty ? fallback.cardImageUrl : cardImageUrl,
      cardThumbnailUrl: cardThumbnailUrl.isEmpty
          ? fallback.cardThumbnailUrl
          : cardThumbnailUrl,
      cardPreviewUrl:
          cardPreviewUrl.isEmpty ? fallback.cardPreviewUrl : cardPreviewUrl,
      cardBackImageUrl: cardBackImageUrl.isEmpty
          ? fallback.cardBackImageUrl
          : cardBackImageUrl,
      cardBackThumbnailUrl: cardBackThumbnailUrl.isEmpty
          ? fallback.cardBackThumbnailUrl
          : cardBackThumbnailUrl,
      cardBackPreviewUrl: cardBackPreviewUrl.isEmpty
          ? fallback.cardBackPreviewUrl
          : cardBackPreviewUrl,
      cardImageAlt: cardImageAlt.isEmpty ? fallback.cardImageAlt : cardImageAlt,
      cardTextColor:
          cardTextColor.isEmpty ? fallback.cardTextColor : cardTextColor,
    );
  }

  /// Card name for lists: provider label, otherwise card type or form factor.
  String get displayLabel {
    final trimmed = label.trim();
    if (trimmed.isNotEmpty && trimmed.toLowerCase() != 'card') return trimmed;
    if (cardTypeName.trim().isNotEmpty) return cardTypeName.trim();
    return virtual ? 'Virtual card' : 'Physical card';
  }

  bool get isEqualsMoney {
    final normalized = bankProvider.toLowerCase().trim();
    return normalized == 'equalsmoney' || normalized == 'equals money';
  }

  String get providerLabel => isEqualsMoney ? 'Fiat account' : 'Crypto card';

  String get statusLabel {
    return switch (status) {
      CardStatus.active => 'Active',
      CardStatus.frozen => 'Frozen',
      CardStatus.pending => 'Pending',
      CardStatus.cancelled => 'Cancelled',
    };
  }
}

String _normalizeCardArtworkUrl(String? value) {
  final normalized = value?.trim() ?? '';
  final markdownLink =
      RegExp(r'^\[[^\]]*\]\((https?://[^)]+)\)$').firstMatch(normalized);
  final unwrapped = markdownLink?.group(1) ?? normalized;
  if (unwrapped.startsWith('/')) {
    return 'https://dashboard.hoppa.global$unwrapped';
  }
  return unwrapped;
}

String _cardNetworkFromNumber(String? cardNumber) {
  final digits = cardNumber?.replaceAll(RegExp(r'\D'), '') ?? '';
  if (digits.startsWith('4')) return 'Visa';
  if (digits.length < 4) return '';

  final firstTwo = int.tryParse(digits.substring(0, 2));
  final firstFour = int.tryParse(digits.substring(0, 4));
  if ((firstTwo != null && firstTwo >= 51 && firstTwo <= 55) ||
      (firstFour != null && firstFour >= 2221 && firstFour <= 2720)) {
    return 'Mastercard';
  }
  return '';
}

Map<String, dynamic> _cardArtworkSource(Map<String, dynamic> source) {
  for (final keys in const [
    ['cardTypeMetadata', 'CardTypeMetadata'],
    ['cardType', 'CardType'],
    ['cardProduct', 'CardProduct'],
    ['cardBenefit', 'CardBenefit'],
  ]) {
    final nested = _nestedMap(source, keys);
    if (nested != null) {
      return {
        ...nested,
        for (final entry in source.entries)
          if (entry.value != null &&
              (entry.value is! String ||
                  (entry.value as String).trim().isNotEmpty))
            entry.key: entry.value,
      };
    }
  }
  return source;
}

int? _firstInt(Map<String, dynamic>? source, List<String> keys) {
  if (source == null) return null;
  for (final key in keys) {
    final value = source[key];
    if (value is int) return value;
    if (value is num) return value.round();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

String _cardBankProvider(Map<String, dynamic> source) {
  final provider = _firstString(source, const [
    'bankProvider',
    'BankProvider',
    'provider',
    'Provider',
    'cardProvider',
    'CardProvider',
  ]);
  if (provider != null) {
    final normalized = provider.toLowerCase().trim();
    if (normalized == '2') {
      return 'equalsmoney';
    }
    return normalized;
  }

  final providerType = source['bankProviderType'] ??
      source['BankProviderType'] ??
      source['providerType'] ??
      source['ProviderType'];
  if (providerType?.toString() == '2') {
    return 'equalsmoney';
  }

  return '';
}

String? _firstString(Map<String, dynamic>? source, List<String> keys) {
  if (source == null) {
    return null;
  }

  for (final key in keys) {
    final value = source[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }

  return null;
}

Map<String, dynamic>? _nestedMap(
    Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    final value = source[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
  }

  return null;
}

Map<String, dynamic> _unwrapCardJson(Map<String, dynamic> json) {
  for (final key in const [
    'card',
    'Card',
    'data',
    'Data',
    'result',
    'Result',
    'payload',
    'Payload',
  ]) {
    final value = json[key];
    if (value is Map<String, dynamic>) {
      return _unwrapCardJson(value);
    }
    if (value is Map) {
      return _unwrapCardJson(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
  }

  return json;
}

class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.bookedAt,
    required this.type,
    this.hasBookedAt = true,
    this.accountId = '',
    this.cardId = '',
    this.walletId = '',
    this.budgetId = '',
    this.rawType = '',
    this.status = '',
    this.isPrimary = true,
    this.transactionAmount,
    this.metadata = const {},
    this.merchantLogoUrl = '',
    this.merchantCategory = '',
    this.cardFees = const [],
  });

  factory LedgerTransaction.fromJson(Map<String, dynamic> json) {
    final metadata = _transactionMetadata(json);
    final bookedAtValue = _firstPresent(json, _bookedAtKeys) ??
        _firstPresent(metadata, _bookedAtKeys);
    final parsedBookedAt = _parseDateTime(bookedAtValue);

    final currency = _firstString(json, const [
          'currency',
          'Currency',
          'settlementCurrency',
          'SettlementCurrency',
        ]) ??
        'USD';
    final parsedAmount = Money.fromJson(
      _moneyJson(
        json['amount'] ?? json['Amount'],
        currency: currency,
      ),
      preservePrecision: true,
    );
    final rawType = (json['type'] ?? json['Type'])?.toString() ?? '';
    final direction = (_firstPresent(json, _directionKeys) ??
            _firstPresent(metadata, _directionKeys))
        ?.toString()
        .toLowerCase()
        .trim();
    final isCredit =
        const {'credit', 'credited', 'incoming', 'inbound'}.contains(direction);
    final isDebit = const {
          'debit',
          'debited',
          'outgoing',
          'outbound',
          'withdrawal',
          'payment',
        }.contains(direction) ||
        (!isCredit &&
            (_isOutgoingType(rawType) ||
                _isUsdToCryptoFunding(
                    rawType, parsedAmount.currency, metadata)));
    final amount = isDebit && parsedAmount.isPositive
        ? parsedAmount.negated
        : parsedAmount;

    final status =
        (json['status'] ?? json['Status'] ?? json['state'] ?? json['State'])
                ?.toString() ??
            '';
    final transactionCurrency = _firstString(json, const [
      'transactionCurrency',
      'TransactionCurrency',
      'originalCurrency',
      'OriginalCurrency',
      'localCurrency',
      'LocalCurrency',
    ]);
    final transactionAmountValue = json['transactionAmount'] ??
        json['TransactionAmount'] ??
        json['originalAmount'] ??
        json['OriginalAmount'] ??
        json['localAmount'] ??
        json['LocalAmount'];
    final parsedTransactionAmount =
        transactionCurrency == null || transactionAmountValue == null
            ? null
            : Money.fromJson(
                _moneyJson(
                  transactionAmountValue,
                  currency: transactionCurrency,
                ),
                preservePrecision: true,
              );
    final transactionAmount = parsedTransactionAmount != null &&
            amount.isNegative &&
            parsedTransactionAmount.isPositive
        ? parsedTransactionAmount.negated
        : parsedTransactionAmount;
    final merchant = _firstString(json, const [
      'merchantName',
      'MerchantName',
      'merchant',
      'Merchant',
    ]);
    final explicitTitle = _firstString(json, const ['title', 'Title']);
    final detail = _firstString(json, const [
      'detail',
      'Detail',
      'remark',
      'Remark',
      'description',
      'Description',
      'reference',
      'Reference',
    ]);
    final typeLabel = _ledgerTransactionTypeLabel(rawType);
    final title = _equalsIncomingRemitter(metadata, amount, rawType) ??
        _usefulTransactionTitle(merchant, currency, rawType, status) ??
        _usefulTransactionTitle(explicitTitle, currency, rawType, status) ??
        _usefulTransactionTitle(detail, currency, rawType, status) ??
        typeLabel;
    final enrichment = _nestedMap(json, const [
      'enrichment',
      'Enrichment',
      'merchantEnrichment',
      'MerchantEnrichment',
      'merchantDetails',
      'MerchantDetails',
    ]);

    return LedgerTransaction(
      id: (json['id'] ??
                  json['Id'] ??
                  json['transactionId'] ??
                  json['TransactionId'])
              ?.toString() ??
          '',
      title: title,
      subtitle: (json['subtitle'] ?? json['Subtitle'])?.toString() ?? status,
      amount: amount,
      bookedAt: parsedBookedAt ?? DateTime.now(),
      hasBookedAt: parsedBookedAt != null,
      type: _transactionType(rawType.isEmpty ? 'card' : rawType),
      accountId: _firstString(json, const [
            'accountId',
            'AccountId',
            'sourceAccountId',
            'SourceAccountId',
          ]) ??
          '',
      cardId: _firstString(json, const ['cardId', 'CardId', 'card_id']) ??
          _firstString(metadata, const ['cardId', 'CardId', 'card_id']) ??
          '',
      walletId: _firstString(json, const [
            'walletId',
            'WalletId',
            'externalWalletId',
            'ExternalWalletId',
          ]) ??
          '',
      budgetId: _firstString(json, const [
            'budgetId',
            'BudgetId',
            'sourceBudgetId',
            'SourceBudgetId',
            'destinationBudgetId',
            'DestinationBudgetId',
          ]) ??
          '',
      rawType: rawType,
      status: status,
      isPrimary: (json['isPrimary'] ?? json['IsPrimary']) != false,
      transactionAmount: transactionAmount,
      metadata: metadata,
      merchantLogoUrl: _firstString(json, const [
            'merchantLogoUrl',
            'MerchantLogoUrl',
            'logoUrl',
            'LogoUrl',
          ]) ??
          _firstString(enrichment, const [
            'merchantLogoUrl',
            'MerchantLogoUrl',
            'logoUrl',
            'LogoUrl',
          ]) ??
          '',
      merchantCategory: _firstString(json, const [
            'merchantCategory',
            'MerchantCategory',
            'categoryName',
            'CategoryName',
          ]) ??
          _firstString(enrichment, const [
            'merchantCategory',
            'MerchantCategory',
            'categoryName',
            'CategoryName',
          ]) ??
          '',
    );
  }

  final String id;
  final String title;
  final String subtitle;
  final Money amount;
  final DateTime bookedAt;

  /// Whether the API supplied a valid booking date. The internal fallback
  /// keeps sorting compatible but must not be presented as a real timestamp.
  final bool hasBookedAt;
  final TransactionType type;
  final String accountId;
  final String cardId;
  final String walletId;
  final String budgetId;
  final String rawType;
  final String status;

  /// False for related provider ledger legs that the API excludes from its
  /// economic-operation statistics. Missing flags remain primary.
  final bool isPrimary;
  final Money? transactionAmount;
  final Map<String, dynamic> metadata;
  final String merchantLogoUrl;
  final String merchantCategory;
  final List<LedgerTransaction> cardFees;

  LedgerTransaction withCardFees(List<LedgerTransaction> fees) =>
      LedgerTransaction(
        id: id,
        title: title,
        subtitle: subtitle,
        amount: amount,
        bookedAt: bookedAt,
        type: type,
        hasBookedAt: hasBookedAt,
        accountId: accountId,
        cardId: cardId,
        walletId: walletId,
        budgetId: budgetId,
        rawType: rawType,
        status: status,
        isPrimary: isPrimary,
        transactionAmount: transactionAmount,
        metadata: metadata,
        merchantLogoUrl: merchantLogoUrl,
        merchantCategory: merchantCategory,
        cardFees: List.unmodifiable(fees),
      );

  Money get displayAmount => transactionAmount ?? amount;

  Money? get secondarySettlementAmount {
    final local = transactionAmount;
    if (local == null ||
        (local.currency.toUpperCase() == amount.currency.toUpperCase() &&
            local.decimalAmount == amount.decimalAmount)) {
      return null;
    }
    return amount;
  }

  String get displayType => _ledgerTransactionTypeLabel(rawType);
}

/// The payment rail describes how a deposit arrived, not who sent it.
String? _equalsIncomingRemitter(
    Map<String, dynamic> metadata, Money amount, String rawType) {
  final fields = {
    for (final entry in metadata.entries)
      entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''): entry.value,
  };
  final provider = fields['provider']
      ?.toString()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  final source = fields['source']?.toString().toLowerCase();
  if (provider != 'equalsmoney' ||
      !amount.isPositive ||
      (source != 'external_credit' &&
          (source != null && source.isNotEmpty ||
              rawType.toLowerCase() != 'deposit'))) {
    return null;
  }
  return _firstString(fields, const ['remittername']);
}

Map<String, dynamic> _transactionMetadata(Map<String, dynamic> json) {
  final metadata = <String, dynamic>{};
  for (final key in const ['metadata', 'Metadata', 'meta', 'Meta']) {
    final value = json[key];
    if (value is Map<String, dynamic>) metadata.addAll(value);
    if (value is Map) {
      metadata.addAll(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (value is String && value.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          metadata.addAll(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      } on FormatException {
        // Some providers return an opaque metadata string. Keep it visible.
        metadata['value'] = value;
      }
    }
  }

  for (final key in const [
    'enrichment',
    'Enrichment',
    'merchantEnrichment',
    'MerchantEnrichment',
    'merchantDetails',
    'MerchantDetails',
    'merchantName',
    'MerchantName',
    'merchantLogoUrl',
    'MerchantLogoUrl',
    'merchantCategory',
    'MerchantCategory',
    'mcc',
    'Mcc',
    'merchantCity',
    'MerchantCity',
    'merchantCountry',
    'MerchantCountry',
    'network',
    'Network',
    'networkName',
    'NetworkName',
    'chain',
    'Chain',
    'chainName',
    'ChainName',
    'blockchain',
    'Blockchain',
    'paymentRail',
    'PaymentRail',
    'paymentNetwork',
    'PaymentNetwork',
    'provider',
    'Provider',
    'source',
    'Source',
    'externalTransactionId',
    'ExternalTransactionId',
    'relatedCardTransactionId',
    'RelatedCardTransactionId',
    'clientTransactionId',
    'ClientTransactionId',
    'cardTransactionId',
    'CardTransactionId',
    // Provider grouping keys the fee and duplicate folding reads.
    'transactionGroupId',
    'TransactionGroupId',
    'parentTransactionId',
    'ParentTransactionId',
    'relationType',
    'RelationType',
    'tradeId',
    'TradeId',
    'feeAmount',
    'FeeAmount',
    'feeCurrency',
    'FeeCurrency',
    'remitterName',
    'RemitterName',
    'remitter_name',
    'paymentMethod',
    'PaymentMethod',
    'schemeName',
    'SchemeName',
  ]) {
    final value = json[key];
    if (value != null) metadata.putIfAbsent(key, () => value);
  }

  return Map.unmodifiable(metadata);
}

const _bookedAtKeys = [
  'bookedAt',
  'BookedAt',
  'postedAt',
  'PostedAt',
  'transactionTime',
  'TransactionTime',
  'transactionDate',
  'TransactionDate',
  'bookingDate',
  'BookingDate',
  'bookingDateTime',
  'BookingDateTime',
  'valueDate',
  'ValueDate',
  'completedAt',
  'CompletedAt',
  'settledAt',
  'SettledAt',
  'executedAt',
  'ExecutedAt',
  'createdAt',
  'CreatedAt',
  'createdDate',
  'CreatedDate',
  'created',
  'Created',
  'timestamp',
  'Timestamp',
  'date',
  'Date',
  'updatedAt',
  'UpdatedAt',
];

const _directionKeys = [
  'direction',
  'Direction',
  'creditDebitIndicator',
  'CreditDebitIndicator',
  'credit_debit_indicator',
  'debitCredit',
  'DebitCredit',
  'flow',
  'Flow',
];

Object? _firstPresent(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    if (value is String && value.trim().isEmpty) continue;
    return value;
  }
  return null;
}

DateTime? _parseDateTime(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is num) {
    final millis = value > 100000000000 ? value.round() : value.round() * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true).toLocal();
  }
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final numeric = int.tryParse(text);
  if (numeric != null) return _parseDateTime(numeric);
  return DateTime.tryParse(text)?.toLocal();
}

/// Provider types that move money out of the account or card when the
/// payload carries an unsigned amount and no explicit direction.
bool _isUsdToCryptoFunding(
  String rawType,
  String currency,
  Map<String, dynamic> metadata,
) {
  if (currency.trim().toUpperCase() != 'USD') return false;
  String compact(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toLowerCase();
  final type = compact(rawType);
  // This operation stores the USD spent as an unsigned amount. Received
  // crypto is separate metadata and must never be substituted at a 1:1 rate.
  if (type == 'quantumtocryptoexchange') return true;
  if (type != 'cryptoexchange') return false;
  final operation = _firstString(metadata, const [
    'operation',
    'Operation',
    'operationType',
    'OperationType',
  ]);
  return operation != null &&
      const {'quantumtocryptoexchange', 'quantumtocrypto', 'usdtocrypto'}
          .contains(compact(operation));
}

bool _isOutgoingType(String rawType) {
  final normalized = rawType.trim().toLowerCase();
  final numeric = int.tryParse(normalized);
  if (numeric != null) {
    return const {1, 3, 5, 7, 8, 9, 10, 13, 15, 16}.contains(numeric);
  }
  final compact = normalized.replaceAll(RegExp(r'[\s_-]+'), '');
  if (compact.contains('unload')) return true;
  if (const ['reversal', 'refund', 'topup', 'deposit', 'load', 'credit']
      .any(compact.contains)) {
    return false;
  }
  // Provider transfer legs: money leaving the customer for the programme
  // master account is an outflow; the mirror leg ("from master") is not.
  if (compact.contains('frommaster') || compact.contains('mastertouser')) {
    return false;
  }
  return const [
    'withdraw',
    'unload',
    'payment',
    'purchase',
    'fee',
    'payout',
    'send',
    'transferout',
    'tomaster',
    'usertomaster',
    'outgoing',
    'debit',
  ].any(compact.contains);
}

String? _usefulTransactionTitle(
  String? value,
  String currency,
  String type,
  String status,
) {
  final title = value?.trim() ?? '';
  if (title.isEmpty) return null;
  final normalized = title.toLowerCase().replaceAll(RegExp(r'[:\s]+$'), '');
  if (normalized == 'transaction' ||
      RegExp(r'^type\s*\d+$').hasMatch(normalized) ||
      normalized == currency.toLowerCase() ||
      normalized == type.toLowerCase() ||
      normalized == status.toLowerCase()) {
    return null;
  }
  return title;
}

String _ledgerTransactionTypeLabel(String value) {
  final normalized = value.trim().toLowerCase();
  final numericType = int.tryParse(normalized);
  if (numericType != null) {
    return switch (numericType) {
      0 || 4 || 6 || 14 => 'Card payment reversal',
      2 => 'Card top up',
      3 => 'Card unload',
      7 || 8 || 15 || 16 => 'Card fee',
      9 || 10 => 'Card payment fee',
      11 => 'Card frozen',
      12 => 'Card unfrozen',
      13 => 'Card withdrawal',
      _ => 'Card payment',
    };
  }
  if (normalized.isEmpty) return 'Transaction';
  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

class Payee {
  const Payee({
    required this.id,
    required this.name,
    required this.accountReference,
    this.firstName = '',
    this.lastName = '',
    this.userName = '',
    this.paymentType = '',
    this.paymentMethod = '',
    this.currency = '',
    this.bankName = '',
    this.provider = '',
    this.status = '',
    this.requiresConfirmation = false,
  });

  factory Payee.fromJson(Map<String, dynamic> json) {
    final id = json['id'] ?? json['payeeId'] ?? json['PayeeId'];
    final firstName =
        (json['firstName'] ?? json['FirstName'])?.toString() ?? '';
    final lastName = (json['lastName'] ?? json['LastName'])?.toString() ?? '';
    final userName = (json['userName'] ?? json['UserName'])?.toString() ?? '';
    final name = json['name'] ??
        json['displayName'] ??
        json['DisplayName'] ??
        [firstName, lastName].where((part) => part.trim().isNotEmpty).join(' ');
    return Payee(
      id: id?.toString() ?? '',
      name:
          name?.toString() ?? (userName.trim().isNotEmpty ? userName : 'Payee'),
      accountReference: (json['iban'] ??
                  json['Iban'] ??
                  json['accountReference'] ??
                  json['AccountReference'] ??
                  json['accountNumber'] ??
                  json['AccountNumber'])
              ?.toString() ??
          '',
      firstName: firstName,
      lastName: lastName,
      userName: userName,
      paymentType:
          (json['paymentType'] ?? json['PaymentType'])?.toString() ?? '',
      paymentMethod:
          (json['paymentMethod'] ?? json['PaymentMethod'])?.toString() ?? '',
      currency: (json['currency'] ?? json['Currency'])?.toString() ?? '',
      bankName: (json['bankName'] ?? json['BankName'])?.toString() ?? '',
      provider: (json['provider'] ?? json['Provider'])?.toString() ?? '',
      status: (json['status'] ?? json['Status'])?.toString() ?? '',
      requiresConfirmation: (json['requiresConfirmation'] ??
              json['RequiresConfirmation']) as bool? ??
          false,
    );
  }

  final String id;
  final String name;
  final String accountReference;
  final String firstName;
  final String lastName;
  final String userName;
  final String paymentType;
  final String paymentMethod;
  final String currency;
  final String bankName;
  final String provider;
  final String status;
  final bool requiresConfirmation;
}

class PayoutQuote {
  const PayoutQuote({
    required this.id,
    this.quoteRequestId = '',
    required this.sourceAmount,
    required this.sourceCurrency,
    required this.targetAmount,
    required this.targetCurrency,
    required this.exchangeRate,
    required this.fee,
    required this.expiresAt,
    this.provider = '',
  });

  factory PayoutQuote.fromJson(Map<String, dynamic> json) {
    final fees = json['fees'] ?? json['Fees'];
    return PayoutQuote(
      id: (json['quoteId'] ??
                  json['QuoteId'] ??
                  json['id'] ??
                  json['Id'] ??
                  json['orderId'] ??
                  json['OrderId'])
              ?.toString() ??
          '',
      quoteRequestId:
          (json['quoteRequestId'] ?? json['QuoteRequestId'])?.toString() ?? '',
      sourceAmount: _parseDecimal(json['sourceAmount'] ?? json['SourceAmount']),
      sourceCurrency: (json['sourceCurrency'] ??
                  json['SourceCurrency'] ??
                  json['fromCurrency'] ??
                  json['FromCurrency'])
              ?.toString() ??
          '',
      targetAmount: _parseDecimal(json['targetAmount'] ?? json['TargetAmount']),
      targetCurrency: (json['targetCurrency'] ??
                  json['TargetCurrency'] ??
                  json['toCurrency'] ??
                  json['ToCurrency'])
              ?.toString() ??
          '',
      exchangeRate: _parseDecimal(
        json['exchangeRate'] ??
            json['ExchangeRate'] ??
            json['rate'] ??
            json['Rate'],
      ),
      fee: _parseNullableDecimal(json['fee'] ?? json['Fee']) ??
          _feeFromList(fees),
      provider: (json['provider'] ?? json['Provider'])?.toString() ?? '',
      expiresAt: DateTime.tryParse(
        (json['expiresAt'] ??
                    json['ExpiresAt'] ??
                    json['expirationTime'] ??
                    json['ExpirationTime'])
                ?.toString() ??
            '',
      ),
    );
  }

  final String id;
  final String quoteRequestId;
  final double sourceAmount;
  final String sourceCurrency;
  final double targetAmount;
  final String targetCurrency;
  final double exchangeRate;
  final double? fee;
  final String provider;
  final DateTime? expiresAt;

  PayoutQuote withFallback({
    required double sourceAmount,
    required String sourceCurrency,
    required String targetCurrency,
  }) {
    final resolvedSourceAmount =
        this.sourceAmount <= 0 ? sourceAmount : this.sourceAmount;
    final resolvedSourceCurrency =
        this.sourceCurrency.isEmpty ? sourceCurrency : this.sourceCurrency;
    final resolvedTargetCurrency =
        this.targetCurrency.isEmpty ? targetCurrency : this.targetCurrency;
    final resolvedTargetAmount = targetAmount > 0
        ? targetAmount
        : resolvedSourceCurrency == resolvedTargetCurrency
            ? resolvedSourceAmount
            : exchangeRate > 0
                ? resolvedSourceAmount * exchangeRate
                : 0.0;

    return PayoutQuote(
      id: id,
      quoteRequestId: quoteRequestId,
      sourceAmount: resolvedSourceAmount,
      sourceCurrency: resolvedSourceCurrency,
      targetAmount: resolvedTargetAmount,
      targetCurrency: resolvedTargetCurrency,
      exchangeRate: exchangeRate,
      fee: fee,
      provider: provider,
      expiresAt: expiresAt,
    );
  }

  String get feeLabel => fee == null
      ? 'Not returned'
      : '${sourceCurrency.trim()} ${fee!.toStringAsFixed(2)}';

  String get rateLabel {
    if (exchangeRate <= 0) {
      return 'No exchange';
    }
    return '1 $sourceCurrency = ${exchangeRate.toStringAsFixed(6)} $targetCurrency';
  }
}

double? _feeFromList(Object? value) {
  if (value is! List || value.isEmpty) {
    return null;
  }

  var total = 0.0;
  var foundFee = false;
  for (final item in value) {
    if (item is Map) {
      final amount = _parseNullableDecimal(item['Amount'] ?? item['amount']);
      if (amount != null) {
        total += amount;
        foundFee = true;
      }
    }
  }

  return foundFee ? total : null;
}

class PayoutCheck {
  const PayoutCheck({
    required this.id,
    required this.pass,
    this.message = '',
  });

  factory PayoutCheck.fromJson(Map<String, dynamic> json) {
    return PayoutCheck(
      id: (json['checkId'] ?? json['CheckId'])?.toString() ?? '',
      pass: (json['pass'] ?? json['Pass']) as bool? ?? false,
      message:
          (json['detailMessage'] ?? json['DetailMessage'])?.toString() ?? '',
    );
  }

  final String id;
  final bool pass;
  final String message;
}

class PayoutOtpInitiation {
  const PayoutOtpInitiation({
    required this.success,
    this.verificationToken = '',
    this.message = '',
    this.expiresAt,
  });

  factory PayoutOtpInitiation.fromJson(Map<String, dynamic> json) {
    return PayoutOtpInitiation(
      success: (json['success'] ?? json['Success']) as bool? ?? false,
      verificationToken:
          (json['verificationToken'] ?? json['VerificationToken'])
                  ?.toString() ??
              '',
      message: (json['message'] ?? json['Message'])?.toString() ?? '',
      expiresAt: DateTime.tryParse(
        (json['expiresAt'] ?? json['ExpiresAt'])?.toString() ?? '',
      ),
    );
  }

  final bool success;
  final String verificationToken;
  final String message;
  final DateTime? expiresAt;
}

class OtpVerification {
  const OtpVerification({
    required this.success,
    this.message = '',
    this.verificationToken = '',
    this.remainingAttempts,
    this.isExpired = false,
    this.isLocked = false,
  });

  factory OtpVerification.fromJson(Map<String, dynamic> json) {
    return OtpVerification(
      success: (json['success'] ?? json['Success']) as bool? ?? false,
      message: (json['message'] ?? json['Message'])?.toString() ?? '',
      verificationToken:
          (json['verificationToken'] ?? json['VerificationToken'])
                  ?.toString() ??
              '',
      remainingAttempts: _parseNullableInt(
        json['remainingAttempts'] ?? json['RemainingAttempts'],
      ),
      isExpired: (json['isExpired'] ?? json['IsExpired']) as bool? ?? false,
      isLocked: (json['isLocked'] ?? json['IsLocked']) as bool? ?? false,
    );
  }

  final bool success;
  final String message;
  final String verificationToken;
  final int? remainingAttempts;
  final bool isExpired;
  final bool isLocked;
}

class OnboardingTask {
  const OnboardingTask({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.route,
  });

  factory OnboardingTask.fromJson(Map<String, dynamic> json) {
    return OnboardingTask(
      id: json['id']?.toString() ?? json['Id']?.toString() ?? 'task',
      title: json['title']?.toString() ?? json['Title']?.toString() ?? 'Task',
      description: json['description']?.toString() ??
          json['Description']?.toString() ??
          '',
      status: _taskStatus(
        json['status']?.toString() ?? json['Status']?.toString() ?? 'pending',
      ),
      route: json['route']?.toString() ?? json['Route']?.toString() ?? '/home',
    );
  }

  final String id;
  final String title;
  final String description;
  final OnboardingTaskStatus status;
  final String route;

  bool get isComplete => status == OnboardingTaskStatus.complete;
}

class DashboardSnapshot {
  const DashboardSnapshot({
    required this.profile,
    required this.accounts,
    required this.cards,
    required this.transactions,
    required this.onboarding,
  });

  final UserProfile profile;
  final List<AccountBalance> accounts;
  final List<PaymentCard> cards;
  final List<LedgerTransaction> transactions;
  final List<OnboardingTask> onboarding;

  Money get totalBalance {
    final total = accounts.fold<int>(
        0, (sum, account) => sum + account.balance.minorUnits);
    final currency = accounts.isEmpty ? 'EUR' : accounts.first.balance.currency;

    return Money(currency: currency, minorUnits: total);
  }
}

Map<String, dynamic> _moneyJson(Object? value, {String currency = 'USD'}) {
  if (value is Map<String, dynamic>) {
    return {
      'currency': currency,
      ...value,
    };
  }
  if (value is num || value is String) {
    return {'currency': currency, 'amount': value};
  }

  return {'currency': currency, 'minorUnits': 0};
}

List<Money> _currencyBalanceList(Map<String, dynamic> json) {
  final rows = <Money>[];
  final seen = <String>{};

  void addMoney(Money money) {
    final currency = money.currency.trim().toUpperCase();
    if (currency.isEmpty) {
      return;
    }
    final key = '$currency-${money.minorUnits}';
    if (!seen.add(key)) {
      return;
    }
    rows.add(Money(currency: currency, minorUnits: money.minorUnits));
  }

  void addRow(Map<String, dynamic> row) {
    final currency = (row['currency'] ??
                row['Currency'] ??
                row['currencyCode'] ??
                row['CurrencyCode'])
            ?.toString()
            .trim()
            .toUpperCase() ??
        '';
    final value = row['available'] ??
        row['Available'] ??
        row['availableBalance'] ??
        row['AvailableBalance'] ??
        row['balance'] ??
        row['Balance'] ??
        row['amount'] ??
        row['Amount'] ??
        row['value'] ??
        row['Value'];

    addMoney(Money.fromJson(_moneyJson(value, currency: currency)));
  }

  void addValue(Object? value, {String? impliedCurrency}) {
    if (value is List) {
      for (final item in value) {
        addValue(item);
      }
      return;
    }
    if (value is! Map) return;

    final map = value.map((key, item) => MapEntry(key.toString(), item));
    final hasExplicitCurrency = const [
      'currency',
      'Currency',
      'currencyCode',
      'CurrencyCode',
    ].any(map.containsKey);
    if (hasExplicitCurrency) {
      addRow(map);
      return;
    }

    for (final entry in map.entries) {
      final key = entry.key.trim();
      final nested = entry.value;
      if (nested is num || nested is String) {
        addMoney(Money.fromJson(_moneyJson(nested, currency: key)));
      } else if (nested is Map) {
        final nestedMap = nested.map(
          (nestedKey, item) => MapEntry(nestedKey.toString(), item),
        );
        addRow({
          'currency': impliedCurrency ?? key,
          ...nestedMap,
        });
      } else {
        addValue(nested, impliedCurrency: impliedCurrency ?? key);
      }
    }
  }

  for (final key in const [
    'balances',
    'Balances',
    'currencyBalances',
    'CurrencyBalances',
    'supportedCurrencyBalances',
    'SupportedCurrencyBalances',
    'availableBalances',
    'AvailableBalances',
  ]) {
    addValue(json[key]);
  }

  return rows;
}

Map<String, dynamic>? _cardBalanceJson(
  Map<String, dynamic> json, {
  required String currency,
}) {
  // The ledger balance may include pending/held funds. Prefer the provider's
  // spendable balance, including an explicit zero, on every card surface.
  final available = json['availableBalance'] ??
      json['AvailableBalance'] ??
      json['available'] ??
      json['Available'];
  if (available != null) {
    return _moneyJson(available, currency: currency);
  }

  final direct = json['balance'] ?? json['Balance'];
  if (direct is Map) {
    final nestedAvailable = direct['availableBalance'] ??
        direct['AvailableBalance'] ??
        direct['available'] ??
        direct['Available'];
    if (nestedAvailable != null) {
      return _moneyJson(nestedAvailable,
          currency: (direct['currency'] ?? direct['Currency'] ?? currency)
              .toString());
    }
  }
  if (direct != null) {
    return _moneyJson(direct, currency: currency);
  }

  final total = json['totalBalance'] ??
      json['TotalBalance'] ??
      json['currentBalance'] ??
      json['CurrentBalance'];
  if (total != null) {
    return _moneyJson(total, currency: currency);
  }

  final balances = json['balances'] ?? json['Balances'];
  if (balances is List && balances.isNotEmpty) {
    final first = balances.first;
    if (first is Map<String, dynamic>) {
      return _moneyJson(first, currency: currency);
    }
  }

  return null;
}

String _cardCurrencyFromJson(Map<String, dynamic> json) {
  final direct = json['currency'] ?? json['Currency'];
  if (direct != null && direct.toString().trim().isNotEmpty) {
    return direct.toString().trim().toUpperCase();
  }

  for (final key in const ['balance', 'Balance', 'limit', 'Limit']) {
    final value = json[key];
    if (value is Map) {
      final currency = value['currency'] ?? value['Currency'];
      if (currency != null && currency.toString().trim().isNotEmpty) {
        return currency.toString().trim().toUpperCase();
      }
    }
  }

  return 'USD';
}

CardStatus _cardStatus(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '');
  return CardStatus.values.firstWhere(
    (status) => status.name == normalized,
    orElse: () => CardStatus.pending,
  );
}

/// Buckets the provider's transaction type names into the app's filterable
/// kinds, following the names Hoppa actually emits: card_payment, refund,
/// cashback and chargeback are card activity; anything with "fee" is a fee;
/// card_topup / card_loading / deposit are top-ups; transfer_*, p2p_*,
/// withdrawals, payouts, exchanges and card_unload are transfers; merchant
/// payments and mandates are payments.
TransactionType _transactionType(String value) {
  final normalized = value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');
  for (final type in TransactionType.values) {
    if (type.name.toLowerCase() == normalized) return type;
  }
  if (normalized.contains('fee') || normalized.contains('subscription')) {
    return TransactionType.fee;
  }
  if (normalized.startsWith('card') &&
      (normalized.contains('payment') ||
          normalized.contains('purchase') ||
          normalized.contains('withdraw') ||
          normalized.contains('reversal') ||
          normalized.contains('settlement') ||
          normalized.contains('authorization') ||
          normalized.contains('decline'))) {
    return TransactionType.card;
  }
  // "pos" and "atm" only as prefixes: "deposit" contains "pos".
  if (normalized.startsWith('pos') ||
      normalized.startsWith('atm') ||
      const [
        'purchase',
        'authorization',
        'settlement',
        'refund',
        'cashback',
        'chargeback',
        'reversal',
        'merchant',
      ].any(normalized.contains)) {
    return TransactionType.card;
  }
  if (normalized.contains('unload')) return TransactionType.transfer;
  if (normalized.contains('topup') ||
      normalized.contains('loading') ||
      normalized.contains('load') ||
      normalized.contains('funding') ||
      normalized.contains('deposit')) {
    return TransactionType.topUp;
  }
  if (normalized.contains('transfer') ||
      normalized.contains('p2p') ||
      normalized.contains('peer') ||
      normalized.contains('withdraw') ||
      normalized.contains('payout') ||
      normalized.contains('exchange') ||
      normalized.contains('quantum') ||
      normalized.contains('swap') ||
      normalized.contains('send') ||
      normalized.contains('receive')) {
    return TransactionType.transfer;
  }
  if (normalized.contains('payment') ||
      normalized.contains('mandate') ||
      normalized.contains('bill')) {
    return TransactionType.payment;
  }
  return TransactionType.card;
}

OnboardingTaskStatus _taskStatus(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '');
  return OnboardingTaskStatus.values.firstWhere(
    (status) => status.name.toLowerCase() == normalized,
    orElse: () => OnboardingTaskStatus.pending,
  );
}
