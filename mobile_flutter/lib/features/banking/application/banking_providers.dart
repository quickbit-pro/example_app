import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../data/mobile_banking_api.dart';
import '../../platform/application/platform_providers.dart';

final mobileBankingApiProvider = Provider<MobileBankingApi>((ref) {
  return MobileBankingApi(ref.watch(dioProvider));
});

final dashboardProvider = FutureProvider<DashboardSnapshot>((ref) {
  return ref.watch(mobileBankingApiProvider).getDashboard();
});

final accountsProvider = FutureProvider<List<AccountBalance>>((ref) {
  return ref.watch(mobileBankingApiProvider).getAccounts();
});

final cardsProvider = FutureProvider<List<PaymentCard>>((ref) {
  return ref.watch(mobileBankingApiProvider).getCards();
});

final transactionsProvider = FutureProvider<List<LedgerTransaction>>((ref) {
  return ref.watch(mobileBankingApiProvider).getTransactions();
});

/// Complete history for Activity and transaction receipts. The dashboard's
/// [transactionsProvider] deliberately keeps its original bounded request.
final activityTransactionsProvider =
    FutureProvider<List<LedgerTransaction>>((ref) {
  return ref.watch(mobileBankingApiProvider).getActivityTransactions();
});

final activityAccountTransactionsProvider =
    FutureProvider.family<List<LedgerTransaction>, String>((ref, accountId) {
  return ref.watch(mobileBankingApiProvider).getActivityTransactions(
        accountId: accountId,
      );
});

final activityCardTransactionsProvider =
    FutureProvider.family<List<LedgerTransaction>, String>((ref, cardId) {
  return ref.watch(mobileBankingApiProvider).getActivityTransactions(
        cardId: cardId,
      );
});

/// Activity and budget previews share one fresh ledger request. Scoped feeds
/// are invalidated too, so switching filters cannot restore an older snapshot.
final refreshActivityProvider = Provider<Future<void> Function()>((ref) {
  Future<void>? inFlight;
  Future<void> refresh() async {
    ref.invalidate(transactionsProvider);
    ref.invalidate(activityTransactionsProvider);
    ref.invalidate(activityAccountTransactionsProvider);
    ref.invalidate(activityCardTransactionsProvider);
    ref.invalidate(accountTransactionsProvider);
    await ref.read(activityTransactionsProvider.future);
  }

  return () => inFlight ??= (() {
        // Entry/resume can coincide with the first fetch. Share that request
        // instead of invalidating it and paying for the same API calls twice.
        final current = ref.read(activityTransactionsProvider);
        if (current.isLoading) {
          return ref
              .read(activityTransactionsProvider.future)
              .then<void>((_) {});
        }
        return refresh();
      })()
          .whenComplete(() => inFlight = null);
});

typedef AccountTransactionsQuery = ({String accountId, int limit});

final accountTransactionsProvider =
    FutureProvider.family<List<LedgerTransaction>, AccountTransactionsQuery>(
        (ref, query) {
  return ref.watch(mobileBankingApiProvider).getTransactions(
        accountId: query.accountId,
        limit: query.limit,
      );
});

final payeesProvider = FutureProvider<List<Payee>>((ref) {
  return ref.watch(mobileBankingApiProvider).getPayees();
});

final onboardingProvider = FutureProvider<List<OnboardingTask>>((ref) {
  return ref.watch(mobileBankingApiProvider).getOnboardingTasks();
});

final bankingActionControllerProvider =
    AsyncNotifierProvider<BankingActionController, void>(
  BankingActionController.new,
);

class BankingActionController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> freezeCard(String cardId, bool freeze) async {
    await _run(
        () => ref.read(mobileBankingApiProvider).freezeCard(cardId, freeze));
  }

  Future<void> orderCard({
    required String label,
    required bool virtual,
    String currency = 'USD',
    int? cardTypeId,
    String? productCode,
    String? phoneCode,
    String? phone,
    String? addressLine1,
    String? city,
    String? state,
    String? country,
    String? postalCode,
    String? budgetId,
    String? discountCode,
    Map<String, dynamic>? legalAgreements,
  }) async {
    await _run(
      () async {
        // Recheck at submission, even when the screen was opened while approved.
        final kyc = await ref.refresh(kycDetailedStatusProvider.future);
        if (!kyc.interlaceKycApproved) {
          throw StateError(
              'Card verification pending. Interlace must approve your verification before you can order a card.');
        }
        await ref.read(mobileBankingApiProvider).orderCard(
              label: label,
              virtual: virtual,
              currency: currency,
              cardTypeId: cardTypeId,
              productCode: productCode,
              phoneCode: phoneCode,
              phone: phone,
              addressLine1: addressLine1,
              city: city,
              state: state,
              country: country,
              postalCode: postalCode,
              budgetId: budgetId,
              discountCode: discountCode,
              legalAgreements: legalAgreements,
            );
      },
    );
  }

  Future<void> topUpCard({
    required String cardId,
    required Money amount,
    String? token,
  }) async {
    await _run(
      () => ref.read(mobileBankingApiProvider).topUpCard(
            cardId: cardId,
            amount: amount,
            token: token,
          ),
    );
  }

  Future<void> loadCard({
    required String cardId,
    required Money amount,
    String? token,
  }) async {
    await _run(
      () => ref.read(mobileBankingApiProvider).loadCard(
            cardId: cardId,
            amount: amount,
            token: token,
          ),
    );
  }

  Future<void> createPayee({
    required String paymentType,
    required String currency,
    required String paymentMethod,
    required String countryCode,
    required String firstName,
    required String lastName,
    required String accountNumber,
    String? displayName,
    String? bankName,
    String? routingCodeType,
    String? routingCodeValue,
    String? addressLine1,
    String? city,
    String? postalCode,
    String? comments,
    String? verificationMethod,
  }) async {
    await _run(
      () => ref.read(mobileBankingApiProvider).createPayee(
            paymentType: paymentType,
            currency: currency,
            paymentMethod: paymentMethod,
            countryCode: countryCode,
            firstName: firstName,
            lastName: lastName,
            accountNumber: accountNumber,
            displayName: displayName,
            bankName: bankName,
            routingCodeType: routingCodeType,
            routingCodeValue: routingCodeValue,
            addressLine1: addressLine1,
            city: city,
            postalCode: postalCode,
            comments: comments,
            verificationMethod: verificationMethod,
          ),
    );
  }

  Future<void> createTransfer({
    required String fromAccountId,
    required String payeeId,
    required Money amount,
    required String reference,
  }) async {
    await _run(
      () => ref.read(mobileBankingApiProvider).createTransfer(
            fromAccountId: fromAccountId,
            payeeId: payeeId,
            amount: amount,
            reference: reference,
          ),
    );
  }

  Future<void> createPayment({
    required String fromAccountId,
    required String payeeId,
    required Money amount,
    required String reference,
  }) async {
    await _run(
      () => ref.read(mobileBankingApiProvider).createPayment(
            fromAccountId: fromAccountId,
            payeeId: payeeId,
            amount: amount,
            reference: reference,
          ),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
    ref.invalidate(accountsProvider);
    ref.invalidate(dashboardProvider);
    ref.invalidate(cardsProvider);
    ref.invalidate(transactionsProvider);
    ref.invalidate(activityTransactionsProvider);
    ref.invalidate(activityAccountTransactionsProvider);
    ref.invalidate(activityCardTransactionsProvider);
    ref.invalidate(payeesProvider);
  }
}
