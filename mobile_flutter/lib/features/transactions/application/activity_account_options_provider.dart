import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/platform_models.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../domain/activity_account_option.dart';

class ActivityAccountOptionsState {
  const ActivityAccountOptionsState({
    required this.options,
    required this.isLoading,
    required this.errors,
    required this.retry,
  });

  final List<ActivityAccountOption> options;
  final bool isLoading;

  /// Source labels only; internal API errors are not exposed as dropdown text.
  final List<String> errors;
  final void Function() retry;
}

final activityAccountOptionsProvider = Provider<ActivityAccountOptionsState>(
    (ref) {
  final accounts = ref.watch(accountsProvider);
  final budgets = ref.watch(budgetsProvider);
  final needsReceiving = budgets.valueOrNull?.isNotEmpty ?? false;
  final receiving = needsReceiving
      ? ref.watch(equalsBankingInfoProvider)
      : const AsyncData<List<PlatformResource>>([]);
  return ActivityAccountOptionsState(
    options: buildActivityAccountOptions(
      accounts: accounts.valueOrNull ?? const [],
      budgets: budgets.valueOrNull ?? const [],
      bankingInfo: receiving.valueOrNull ?? const [],
    ),
    isLoading: accounts.isLoading || budgets.isLoading || receiving.isLoading,
    errors: [
      if (accounts.hasError) 'Accounts',
      if (budgets.hasError) 'Bank accounts',
      if (receiving.hasError) 'Account details',
    ],
    retry: () {
      if (accounts.hasError) ref.invalidate(accountsProvider);
      if (budgets.hasError) ref.invalidate(budgetsProvider);
      if (receiving.hasError) ref.invalidate(equalsBankingInfoProvider);
    },
  );
}, dependencies: [
  accountsProvider,
  budgetsProvider,
  equalsBankingInfoProvider
]);
