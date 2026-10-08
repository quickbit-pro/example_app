import '../domain/finance_entities.dart';

abstract interface class AccountService {
  Future<List<FinanceAccount>> listAccounts();
}

abstract interface class CardService {
  Future<List<PaymentCard>> listCards();
}

abstract interface class CryptoService {
  Future<List<CryptoQuote>> listQuotes();
}

abstract interface class TransactionService {
  Future<List<FinanceTransaction>> listTransactions();
}

abstract interface class FinanceDataService
    implements AccountService, CardService, CryptoService, TransactionService {}
