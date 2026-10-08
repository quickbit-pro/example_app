import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';

enum CardTransactionCategory { purchase, crypto, control }

class CardTransactionActivity {
  const CardTransactionActivity({
    required this.title,
    required this.subtitle,
    required this.settlementAmount,
    required this.status,
    required this.reference,
    required this.type,
    required this.category,
    this.transactionAmount,
    this.merchantLogoUrl = '',
    this.merchantCategory = '',
  });

  factory CardTransactionActivity.fromResource(PlatformResource resource) {
    final metadata = _flattenMetadata(resource.metadata);
    final type = _firstText(metadata, const ['type', 'Type']) ?? '';
    final status = _firstText(metadata, const ['status', 'Status']) ?? '';
    final settlementAmount = _requiredMoney(
      metadata,
      amountKeys: const [
        'amount',
        'Amount',
        'settlementAmount',
        'SettlementAmount',
      ],
      currencyKeys: const [
        'currency',
        'Currency',
        'settlementCurrency',
        'SettlementCurrency',
      ],
      fallbackCurrency: 'USD',
    );
    final transactionAmount = _optionalMoney(
      metadata,
      amountKeys: const [
        'transactionAmount',
        'TransactionAmount',
        'originalAmount',
        'OriginalAmount',
        'localAmount',
        'LocalAmount',
      ],
      currencyKeys: const [
        'transactionCurrency',
        'TransactionCurrency',
        'originalCurrency',
        'OriginalCurrency',
        'localCurrency',
        'LocalCurrency',
      ],
    );
    final typeLabel = _transactionTypeLabel(type);
    final merchant = _firstText(metadata, const [
      'merchantName',
      'MerchantName',
      'merchant',
      'Merchant',
    ]);
    final detail = _firstText(metadata, const [
      'detail',
      'Detail',
      'remark',
      'Remark',
      'description',
      'Description',
    ]);
    final resourceTitle = _usefulResourceTitle(
      resource.title,
      settlementAmount.currency,
      type,
      status,
    );
    final title = merchant ?? detail ?? resourceTitle ?? typeLabel;
    final enrichment = _nestedMap(metadata, const [
      'enrichment',
      'Enrichment',
      'merchantEnrichment',
      'MerchantEnrichment',
      'merchantDetails',
      'MerchantDetails',
    ]);
    final location = _merchantLocation(metadata);
    final subtitle = [
      if (title.toLowerCase() != typeLabel.toLowerCase()) typeLabel,
      if (location.isNotEmpty) location,
    ].join(' • ');

    return CardTransactionActivity(
      title: title,
      subtitle: subtitle.isEmpty ? typeLabel : subtitle,
      settlementAmount: settlementAmount,
      transactionAmount: transactionAmount,
      status: _friendlyStatus(status),
      reference: resource.id.trim().isEmpty ? 'Reference pending' : resource.id,
      type: type,
      category: _categoryFor('$type $title $detail'),
      merchantLogoUrl: _firstText(metadata, const [
            'merchantLogoUrl',
            'MerchantLogoUrl',
            'logoUrl',
            'LogoUrl',
          ]) ??
          _firstText(enrichment ?? const {}, const [
            'merchantLogoUrl',
            'MerchantLogoUrl',
            'logoUrl',
            'LogoUrl',
          ]) ??
          '',
      merchantCategory: _firstText(metadata, const [
            'merchantCategory',
            'MerchantCategory',
            'categoryName',
            'CategoryName',
          ]) ??
          _firstText(enrichment ?? const {}, const [
            'merchantCategory',
            'MerchantCategory',
            'categoryName',
            'CategoryName',
          ]) ??
          '',
    );
  }

  final String title;
  final String subtitle;
  final Money settlementAmount;
  final Money? transactionAmount;
  final String status;
  final String reference;
  final String type;
  final CardTransactionCategory category;
  final String merchantLogoUrl;
  final String merchantCategory;

  Money get displayAmount => transactionAmount ?? settlementAmount;

  Money? get secondarySettlementAmount {
    final local = transactionAmount;
    if (local == null ||
        (local.currency.toUpperCase() ==
                settlementAmount.currency.toUpperCase() &&
            local.minorUnits == settlementAmount.minorUnits)) {
      return null;
    }
    return settlementAmount;
  }

  bool get isCredit {
    final normalized = type.toLowerCase();
    return settlementAmount.minorUnits < 0 ||
        normalized.contains('reversal') ||
        normalized.contains('refund') ||
        normalized.contains('topup') ||
        normalized.contains('top_up');
  }
}

Map<String, dynamic> _flattenMetadata(Map<String, dynamic> source) {
  final nested = source['metadata'] ?? source['Metadata'];
  if (nested is Map<String, dynamic>) {
    return {...nested, ...source};
  }
  if (nested is Map) {
    return {
      ...nested.map((key, value) => MapEntry(key.toString(), value)),
      ...source,
    };
  }
  return source;
}

Money _requiredMoney(
  Map<String, dynamic> source, {
  required List<String> amountKeys,
  required List<String> currencyKeys,
  required String fallbackCurrency,
}) {
  final value = _firstValue(source, amountKeys);
  final currency = _firstText(source, currencyKeys);
  if (value is Map<String, dynamic>) {
    return Money.fromJson({
      ...value,
      if (currency != null) 'currency': currency,
    });
  }
  if (value is Map) {
    return Money.fromJson({
      ...value.map((key, value) => MapEntry(key.toString(), value)),
      if (currency != null) 'currency': currency,
    });
  }
  return Money.fromJson({
    'amount': value ?? 0,
    'currency': currency ?? fallbackCurrency,
  });
}

Money? _optionalMoney(
  Map<String, dynamic> source, {
  required List<String> amountKeys,
  required List<String> currencyKeys,
}) {
  final value = _firstValue(source, amountKeys);
  final currency = _firstText(source, currencyKeys);
  if (value == null || currency == null) return null;
  return _requiredMoney(
    source,
    amountKeys: amountKeys,
    currencyKeys: currencyKeys,
    fallbackCurrency: currency,
  );
}

Object? _firstValue(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    if (source.containsKey(key) && source[key] != null) return source[key];
  }
  return null;
}

Map<String, dynamic>? _nestedMap(
  Map<String, dynamic> source,
  List<String> keys,
) {
  final value = _firstValue(source, keys);
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return null;
}

String? _firstText(Map<String, dynamic> source, List<String> keys) {
  final value = _firstValue(source, keys)?.toString().trim();
  return value == null || value.isEmpty ? null : value;
}

String? _usefulResourceTitle(
  String value,
  String currency,
  String type,
  String status,
) {
  final title = value.trim();
  if (title.isEmpty) return null;
  final normalized = title.toLowerCase();
  if (normalized == currency.toLowerCase() ||
      normalized == type.toLowerCase() ||
      normalized == status.toLowerCase()) {
    return null;
  }
  return title;
}

String _merchantLocation(Map<String, dynamic> metadata) {
  final city = _firstText(metadata, const ['merchantCity', 'MerchantCity']);
  final country =
      _firstText(metadata, const ['merchantCountry', 'MerchantCountry']);
  return [city, country]
      .where((value) => value != null && value.isNotEmpty)
      .join(', ');
}

String _transactionTypeLabel(String rawType) {
  final normalized = rawType.trim().toLowerCase();
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
  if (normalized.isEmpty) return 'Card transaction';
  return normalized
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1))
      .join(' ');
}

String _friendlyStatus(String value) {
  if (value.trim().isEmpty) return 'Booked';
  return value
      .trim()
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
      .join(' ');
}

CardTransactionCategory _categoryFor(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('crypto') ||
      normalized.contains('btc') ||
      normalized.contains('usdc') ||
      normalized.contains('usdt') ||
      normalized.contains('eth')) {
    return CardTransactionCategory.crypto;
  }
  if (normalized.contains('freeze') ||
      normalized.contains('pin') ||
      normalized.contains('limit')) {
    return CardTransactionCategory.control;
  }
  return CardTransactionCategory.purchase;
}
