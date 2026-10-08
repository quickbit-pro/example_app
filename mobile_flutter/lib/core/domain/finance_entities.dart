import 'money.dart';

enum AccountKind {
  fiat,
  crypto,
}

enum CardKind {
  virtual,
  physical,
}

enum CardStatus {
  active,
  frozen,
  pending,
}

enum TransactionStatus {
  completed,
  pending,
  failed,
}

class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.kind,
    required this.balance,
    this.assetCode,
    this.iban,
  });

  final String id;
  final String name;
  final AccountKind kind;
  final MoneyAmount balance;
  final String? assetCode;
  final String? iban;
}

class PaymentCard {
  const PaymentCard({
    required this.id,
    required this.label,
    required this.last4,
    required this.kind,
    required this.status,
    required this.monthlySpend,
  });

  final String id;
  final String label;
  final String last4;
  final CardKind kind;
  final CardStatus status;
  final MoneyAmount monthlySpend;
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.status,
    required this.occurredAt,
    this.assetCode,
  });

  final String id;
  final String title;
  final String subtitle;
  final MoneyAmount amount;
  final TransactionStatus status;
  final DateTime occurredAt;
  final String? assetCode;
}

class CryptoQuote {
  const CryptoQuote({
    required this.assetCode,
    required this.assetName,
    required this.price,
    required this.changePercent24h,
  });

  final String assetCode;
  final String assetName;
  final MoneyAmount price;
  final double changePercent24h;
}
