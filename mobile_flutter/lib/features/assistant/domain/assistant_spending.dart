/// Server-computed totals for the signed-in user. No account or counterparty identifiers.
class AssistantSpendingSummary {
  const AssistantSpendingSummary(this.from, this.to, this.currencies,
      {this.activity = const []});
  final String from;
  final String to;
  final List<AssistantSpendingCurrency> currencies;
  final List<AssistantActivityCurrency> activity;
  factory AssistantSpendingSummary.fromJson(Map<String, dynamic> json) {
    final from = json['from'] as String;
    final to = json['to'] as String;
    if (DateTime.tryParse(from) == null || DateTime.tryParse(to) == null) {
      throw const FormatException('Invalid summary period');
    }
    final currencies = (json['currencies'] as List)
        .map((item) => AssistantSpendingCurrency.fromJson(
            Map<String, dynamic>.from(item as Map)))
        .toList(growable: false);
    if (currencies.length > 10) {
      throw const FormatException('Too many currencies');
    }
    return AssistantSpendingSummary(from, to, currencies,
        activity: ((json['activity'] as List?) ?? const [])
            .map((item) => AssistantActivityCurrency.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(growable: false));
  }
}

class AssistantSpendingCurrency {
  const AssistantSpendingCurrency(this.currency, this.purchases, this.refunds,
      this.net, this.purchaseCount, this.refundCount, this.categories);
  final String currency;
  final num purchases, refunds, net;
  final int purchaseCount, refundCount;
  final List<AssistantSpendingCategory> categories;
  factory AssistantSpendingCurrency.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(currency)) {
      throw const FormatException('Invalid currency');
    }
    final purchases = json['purchases'] as num;
    final refunds = json['refunds'] as num;
    final net = json['net'] as num;
    if (![purchases, refunds, net].every((value) => value.isFinite)) {
      throw const FormatException('Invalid amount');
    }
    return AssistantSpendingCurrency(
        currency,
        purchases,
        refunds,
        net,
        json['purchaseCount'] as int,
        json['refundCount'] as int,
        (json['categories'] as List)
            .map((item) => AssistantSpendingCategory.fromJson(
                Map<String, dynamic>.from(item as Map)))
            .toList(growable: false));
  }
}

class AssistantSpendingCategory {
  const AssistantSpendingCategory(this.category, this.purchases, this.refunds);
  final String category;
  final num purchases, refunds;
  factory AssistantSpendingCategory.fromJson(Map<String, dynamic> json) {
    final category = json['category'] as String;
    if (!const {
      'Groceries',
      'Food and dining',
      'Travel',
      'Transport',
      'Shopping',
      'Bills and subscriptions',
      'Other'
    }.contains(category)) {
      throw const FormatException('Invalid category');
    }
    return AssistantSpendingCategory(
        category, json['purchases'] as num, json['refunds'] as num);
  }
}

class AssistantActivityCurrency {
  const AssistantActivityCurrency(
      this.currency,
      this.incoming,
      this.outgoing,
      this.net,
      this.count,
      this.pending,
      this.failed,
      this.internal,
      this.related);
  final String currency;
  final num incoming, outgoing, net;
  final int count, pending, failed, internal, related;
  factory AssistantActivityCurrency.fromJson(Map<String, dynamic> json) {
    final currency = json['currency'] as String;
    final incoming = json['incoming'] as num;
    final outgoing = json['outgoing'] as num;
    final net = json['net'] as num;
    if (!RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(currency) ||
        ![incoming, outgoing, net].every((v) => v.isFinite)) {
      throw const FormatException('Invalid activity totals');
    }
    return AssistantActivityCurrency(
        currency,
        incoming,
        outgoing,
        net,
        json['count'] as int,
        json['pending'] as int,
        json['failed'] as int,
        json['internal'] as int,
        json['related'] as int);
  }
}
