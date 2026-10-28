import '../../../core/models/banking_models.dart';

/// Receiving-bank details only. A bank's address is never the payee's residence.
class BankPayeeDraft {
  const BankPayeeDraft(
      {required this.iban,
      required this.accountHolder,
      required this.bankCountry,
      this.bic = '',
      this.bankName = '',
      this.bankAddress = '',
      this.paymentReference = ''});

  final String iban,
      accountHolder,
      bankCountry,
      bic,
      bankName,
      bankAddress,
      paymentReference;

  bool matches(Payee payee) =>
      normalizeIban(payee.accountReference) == normalizeIban(iban) &&
      (payee.currency.isEmpty || payee.currency.toUpperCase() == 'EUR') &&
      (payee.provider.isEmpty ||
          payee.provider.toLowerCase().contains('equals')) &&
      !const {'deleted', 'rejected'}.contains(payee.status.toLowerCase());

  static String normalizeIban(String value) =>
      value.replaceAll(RegExp(r'\s'), '').toUpperCase();
}
