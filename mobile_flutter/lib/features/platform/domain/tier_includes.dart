import '../../../core/models/platform_models.dart';

/// What a plan includes, read from the provider's own tier fields.
///
/// The plan and its cards arrive from two calls. `GET tiers` carries the
/// plan's price, description, features and benefit flags. `GET
/// tiers/card-tier/{tierId}` lists the card programmes the plan carries, with
/// the allowance, the order cap and the card's own fees. The plan price and
/// the card fees are separate charges, so they are separate types here, as
/// they are on the sheet.
class TierPlanIncludes {
  const TierPlanIncludes({
    this.monthlyFee,
    this.yearlyFee,
    this.currency = '',
    this.description = '',
    this.features = const [],
    this.benefits = const [],
    this.includesIban = false,
    this.dailyRewards = false,
  });

  /// Published subscription prices in major units. Null when the provider
  /// does not publish one or asks for it to be hidden.
  final double? monthlyFee;
  final double? yearlyFee;
  final String currency;

  /// The plan's own description, verbatim.
  final String description;

  /// The plan's feature lines, in the provider's order.
  final List<String> features;

  /// Benefits the provider words itself.
  final List<String> benefits;

  /// Benefits the provider flags rather than words.
  final bool includesIban;
  final bool dailyRewards;

  bool get hasPrice => monthlyFee != null || yearlyFee != null;

  bool get hasBenefits => includesIban || dailyRewards || benefits.isNotEmpty;
}

/// One card programme a plan carries.
class TierCardOffer {
  const TierCardOffer({
    required this.name,
    this.isVirtual = false,
    this.isPhysical = false,
    this.description = '',
    this.imageUrl = '',
    this.imageAlt = '',
    this.features = const [],
    this.freeCards,
    this.freeCardsPeriod = '',
    this.maxCards,
    this.currency = '',
    this.issuanceFee,
    this.planMonthlyFee,
    this.planYearlyFee,
    this.cardMonthlyFee,
    this.cardYearlyFee,
    this.serviceFee,
    this.replacementFee,
    this.atmWithdrawalFee,
  });

  final String name;
  final bool isVirtual;
  final bool isPhysical;
  final String description;
  final String imageUrl;
  final String imageAlt;
  final List<String> features;

  /// Cards the plan includes without the issuance fee, and over what period
  /// (`lifetime`, `monthly`, ...), exactly as the provider names it.
  final int? freeCards;
  final String freeCardsPeriod;

  /// How many of this card the customer may hold. Null when uncapped.
  final int? maxCards;

  /// Currency of every fee below. The provider prices cards separately from
  /// the plan, often in another currency.
  final String currency;
  final double? issuanceFee;

  /// The subscription this plan sets for the card, which replaces the card's
  /// own ([cardMonthlyFee]) when it is set.
  final double? planMonthlyFee;
  final double? planYearlyFee;
  final double? cardMonthlyFee;
  final double? cardYearlyFee;

  /// The card's monthly service fee, charged on top of any subscription.
  final double? serviceFee;
  final double? replacementFee;
  final double? atmWithdrawalFee;
}

TierPlanIncludes tierPlanIncludesOf(PlatformResource tier) {
  final json = tier.metadata;
  final monthlyHidden = _bool(json, const ['hideMonthlyFee', 'HideMonthlyFee']);
  final yearlyHidden = _bool(json, const ['hideYearlyFee', 'HideYearlyFee']);
  final flat = _number(json, const [
    'price',
    'Price',
    'subscriptionFee',
    'SubscriptionFee',
  ]);
  final monthly = monthlyHidden == true
      ? null
      : _number(json, const [
          'monthlyFee',
          'MonthlyFee',
          'monthlySubscriptionFee',
          'MonthlySubscriptionFee',
          'monthlyPrice',
          'MonthlyPrice',
        ]);
  final yearly = yearlyHidden == true
      ? null
      : _number(json, const [
          'yearlyFee',
          'YearlyFee',
          'yearlySubscriptionFee',
          'YearlySubscriptionFee',
          'yearlyPrice',
          'YearlyPrice',
        ]);

  return TierPlanIncludes(
    monthlyFee: monthly ?? (yearly == null ? flat : null),
    yearlyFee: yearly,
    currency: _text(json, const [
          'currency',
          'Currency',
          'priceCurrency',
          'PriceCurrency',
          'currencyCode',
          'CurrencyCode',
        ]) ??
        '',
    description:
        _text(json, const ['description', 'Description'])?.trim() ?? '',
    features: _lines(json, const [
      'features',
      'Features',
      'includedFeatures',
      'IncludedFeatures',
    ]),
    benefits: _lines(json, const [
      'benefits',
      'Benefits',
      'tierBenefits',
      'TierBenefits',
    ]),
    includesIban:
        _bool(json, const ['includesEqualsIban', 'IncludesEqualsIban']) == true,
    dailyRewards:
        _bool(json, const ['dailyRewardsEnabled', 'DailyRewardsEnabled']) ==
            true,
  );
}

/// The card programmes in a `tiers/card-tier/{tierId}` payload, without the
/// ones the provider has switched off.
List<TierCardOffer> tierCardOffersOf(PlatformResource cardTier) {
  return [
    for (final row in _cardTierRows(cardTier.metadata))
      if (_offerFrom(row) case final offer?) offer,
  ];
}

TierCardOffer? _offerFrom(Map<String, dynamic> row) {
  if (_bool(row, const ['isActive', 'IsActive']) == false) return null;
  final card = _map(row, const ['cardType', 'CardType']) ?? row;
  if (_bool(card, const ['isEnabled', 'IsEnabled']) == false) return null;
  final name = _text(card, const [
    'name',
    'Name',
    'displayName',
    'DisplayName',
    'cardTypeName',
    'CardTypeName',
  ]);
  if (name == null) return null;

  final features = <String>[];
  final seen = <String>{};
  for (final line in _lines(card, const [
    'features',
    'Features',
    'baseFeatures',
    'BaseFeatures',
    'subscriptionFeatures',
    'SubscriptionFeatures',
  ])) {
    if (seen.add(line.toLowerCase())) features.add(line);
  }

  return TierCardOffer(
    name: name.trim(),
    isVirtual: _bool(card, const ['isVirtual', 'IsVirtual']) == true,
    isPhysical: _bool(card, const ['isPhysical', 'IsPhysical']) == true,
    description:
        _text(card, const ['description', 'Description'])?.trim() ?? '',
    imageUrl: _text(card, const [
          'cardThumbnailUrl',
          'CardThumbnailUrl',
          'cardPreviewUrl',
          'CardPreviewUrl',
          'cardImageUrl',
          'CardImageUrl',
        ]) ??
        '',
    imageAlt: _text(card, const ['cardImageAlt', 'CardImageAlt']) ?? '',
    features: features,
    freeCards:
        _number(row, const ['freeCardsIncluded', 'FreeCardsIncluded'])?.round(),
    freeCardsPeriod:
        _text(row, const ['freeCardsPeriod', 'FreeCardsPeriod'])?.trim() ?? '',
    maxCards: _number(row, const ['maxCards', 'MaxCards'])?.round(),
    currency: (_text(card, const [
              'currencyCode',
              'CurrencyCode',
              'currency',
              'Currency',
            ]) ??
            '')
        .trim()
        .toUpperCase(),
    issuanceFee: _number(card, const [
      'issuanceFee',
      'IssuanceFee',
      'issueFee',
      'IssueFee',
    ]),
    planMonthlyFee: _number(row, const [
      'monthlySubscriptionFee',
      'MonthlySubscriptionFee',
    ]),
    planYearlyFee: _number(row, const [
      'yearlySubscriptionFee',
      'YearlySubscriptionFee',
    ]),
    cardMonthlyFee: _number(card, const [
      'monthlySubscriptionFee',
      'MonthlySubscriptionFee',
    ]),
    cardYearlyFee: _number(card, const [
      'yearlySubscriptionFee',
      'YearlySubscriptionFee',
    ]),
    serviceFee: _number(card, const ['monthlyFee', 'MonthlyFee']),
    replacementFee: _number(card, const ['replacementFee', 'ReplacementFee']),
    atmWithdrawalFee:
        _number(card, const ['atmWithdrawalFee', 'AtmWithdrawalFee']),
  );
}

/// The card-type-tier rows, from the provider's envelope or a `data` wrapper.
List<Map<String, dynamic>> _cardTierRows(Map<String, dynamic> json) {
  for (final key in const [
    'cardTypeTiers',
    'CardTypeTiers',
    'items',
    'Items',
  ]) {
    final value = json[key];
    if (value is List) {
      return [
        for (final item in value)
          if (item is Map) _stringMap(item),
      ];
    }
  }
  final data = _map(json, const ['data', 'Data']);
  if (data != null) return _cardTierRows(data);
  // A single row answered on its own.
  if (_map(json, const ['cardType', 'CardType']) != null) return [json];
  return const [];
}

/// Display lines from a list of strings or of `{name|title|description}`
/// objects. Machine tokens (`contactless_payment`) become words; sentences
/// are left exactly as the provider wrote them.
List<String> _lines(Map<String, dynamic> json, List<String> keys) {
  final lines = <String>[];
  void add(Object? value) {
    if (value == null) return;
    if (value is List) {
      value.forEach(add);
      return;
    }
    if (value is Map) {
      add(_text(_stringMap(value), const [
        'name',
        'Name',
        'title',
        'Title',
        'label',
        'Label',
        'description',
        'Description',
      ]));
      return;
    }
    final line = _words(value.toString());
    if (line.isNotEmpty) lines.add(line);
  }

  for (final key in keys) {
    add(json[key]);
  }
  return lines;
}

const _acronyms = {
  'ATM',
  'NFC',
  '3DS',
  'PIN',
  'IBAN',
  'SEPA',
  'SWIFT',
  'OTP',
  'SMS',
  'KYC',
  'EUR',
  'USD',
  'GBP',
  'USDC',
  'USDT',
};

String _words(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final token = !value.contains(' ') &&
      (value.contains('_') ||
          value == value.toUpperCase() ||
          value == value.toLowerCase());
  if (!token) return value;
  return value
      .split(RegExp(r'[_\-]+'))
      .where((part) => part.isNotEmpty)
      .map((part) {
    final upper = part.toUpperCase();
    if (_acronyms.contains(upper)) return upper;
    return upper[0] + part.substring(1).toLowerCase();
  }).join(' ');
}

String? _text(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.trim().isNotEmpty) return value;
    if (value is num) return value.toString();
  }
  return null;
}

double? _number(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.trim().replaceAll(',', ''));
      if (parsed != null) return parsed;
    }
  }
  return null;
}

bool? _bool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'true') return true;
      if (normalized == 'false') return false;
    }
  }
  return null;
}

Map<String, dynamic>? _map(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is Map) return _stringMap(value);
  }
  return null;
}

Map<String, dynamic> _stringMap(Map value) =>
    value.map((key, item) => MapEntry(key.toString(), item));
