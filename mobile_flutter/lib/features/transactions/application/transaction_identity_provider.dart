import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/transaction_identity.dart';

final transactionIdentityProvider =
    Provider.family<String?, LedgerTransaction>((ref, transaction) {
  final cards = transaction.cardId.trim().isEmpty
      ? const <PaymentCard>[]
      : ref.watch(cardsProvider).valueOrNull ?? const <PaymentCard>[];
  final cardLabel = transactionCardIdentityLabel(transaction.cardId, cards);
  if (cardLabel != null) return cardLabel;
  final hasAccountReference = transactionHasAccountReference(transaction);
  final accountsState =
      hasAccountReference ? ref.watch(accountsProvider) : null;
  final accounts = accountsState?.valueOrNull ?? const <AccountBalance>[];
  final accountLabel = transactionIdentityLabel(
    transaction,
    cards: cards,
    accounts: accounts,
  );
  // A real account roster match needs no Equals request. Wait for that roster
  // before looking up alternate budget identities unless the row names one.
  if (!transactionHasBudgetReference(transaction) &&
      (accountLabel != null || accountsState?.isLoading == true)) {
    return accountLabel;
  }
  final budgets = hasAccountReference
      ? ref.watch(budgetsProvider).valueOrNull ?? const <PlatformResource>[]
      : const <PlatformResource>[];
  final bankingInfo = transactionHasMatchingBudget(transaction, budgets)
      ? ref.watch(equalsBankingInfoProvider).valueOrNull ??
          const <PlatformResource>[]
      : const <PlatformResource>[];
  return transactionIdentityLabel(
    transaction,
    cards: cards,
    accounts: accounts,
    budgets: budgets,
    bankingInfo: bankingInfo,
  );
}, dependencies: [
  cardsProvider,
  accountsProvider,
  budgetsProvider,
  equalsBankingInfoProvider,
]);

/// A card receipt route carries its card identity even if the provider's raw
/// card transaction omits that field.
final cardIdentityProvider = Provider.family<String?, String>((ref, cardId) {
  if (cardId.trim().isEmpty) return null;
  final cards = ref.watch(cardsProvider).valueOrNull ?? const <PaymentCard>[];
  return transactionCardIdentityLabel(cardId, cards);
}, dependencies: [cardsProvider]);
