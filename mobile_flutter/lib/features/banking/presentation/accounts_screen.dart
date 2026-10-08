import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../brands/example/example.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/models/equals_money.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../../flavors.dart';
import '../../../shared/shared.dart';
import '../application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../platform/presentation/onboarding_banking_screen.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Accounts'))),
      body: const AccountsContent(),
    );
  }
}

class AccountsContent extends ConsumerWidget {
  const AccountsContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kycStatus = ref.watch(kycDetailedStatusProvider);

    return kycStatus.when(
      data: (detailedStatus) {
        if (detailedStatus.requiresEqualsMoneyAction) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              EqualsMoneyRequiredActionCard(status: detailedStatus),
            ],
          );
        }

        return const _AccountsList();
      },
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(kycDetailedStatusProvider),
      ),
      loading: () =>
          LoadingState(label: context.tr('Checking onboarding status')),
    );
  }
}

class _AccountsList extends ConsumerWidget {
  const _AccountsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final equalsInfo = ref.watch(equalsBankingInfoProvider);
    final budgets = ref.watch(budgetsProvider);
    final tenantConfig = ref.watch(mobileTenantConfigProvider).valueOrNull;
    final disclosure = resolveEqualsPaymentServicesDisclosure(
      localeCountryCode:
          WidgetsBinding.instance.platformDispatcher.locale.countryCode ?? '',
      defaultRegion: tenantConfig?.equalsRegulatoryRegionDefault ?? 'EU',
      euDisclosure: tenantConfig?.equalsRegulatoryDisclaimerEu,
      ukDisclosure: tenantConfig?.equalsRegulatoryDisclaimerUk,
    );
    final showSandboxFunding =
        ref.watch(appConfigProvider).flavor != AppFlavor.prod;

    return accounts.when(
      data: (items) {
        final accountDetails = items
            .where(
              (account) =>
                  _isEqualsMoneyAccount(account) ||
                  account.linkedBankAccounts.isNotEmpty,
            )
            .toList();
        final isExample = context.isExampleTheme;
        final list = ListView(
          padding: isExample
              ? const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  110,
                )
              : const EdgeInsets.all(16),
          children: <Widget>[
            budgets.maybeWhen(
              data: (budgetItems) => budgetItems.isEmpty
                  ? _SupportedCurrencyBalances(
                      accounts: items,
                      details: _equalsMoneyGroups(
                        equalsInfo.valueOrNull ?? const [],
                      ),
                    )
                  : _EqualsBudgetAccountCards(
                      budgets: budgetItems,
                      details: _equalsMoneyGroups(
                        equalsInfo.valueOrNull ?? const [],
                      ),
                      disclosure: disclosure,
                    ),
              orElse: () => _SupportedCurrencyBalances(
                accounts: items,
                details: _equalsMoneyGroups(equalsInfo.valueOrNull ?? const []),
              ),
            ),
            const SafeguardingStatementButton(),
            if (showSandboxFunding) ...[
              SizedBox(height: isExample ? AppSpacing.lg : 12),
              _SandboxFundTestCard(accounts: accountDetails),
            ],
          ],
        );
        if (!isExample) return list;
        // One sheen clock for the screen. The app shell already provides one
        // when this page is mounted inside it, so ask before adding a second.
        if (ExampleSheenScope.existsAbove(context)) return list;
        return ExampleSheenScope(child: list);
      },
      error: (error, stackTrace) => ErrorState(
        error: error,
        onRetry: () => ref.invalidate(accountsProvider),
      ),
      loading: () => LoadingState(label: context.tr('Loading accounts')),
    );
  }
}

String _formattedDecimalBalance(String currency, double amount) {
  final code = currency.toUpperCase();
  final symbol = switch (code) {
    'GBP' => '£',
    'EUR' => '€',
    'USD' => r'$',
    _ => '$code ',
  };
  return '$symbol${amount.toStringAsFixed(2)}';
}

class _SandboxFundTestCard extends ConsumerStatefulWidget {
  const _SandboxFundTestCard({required this.accounts});

  final List<AccountBalance> accounts;

  @override
  ConsumerState<_SandboxFundTestCard> createState() =>
      _SandboxFundTestCardState();
}

class _SandboxFundTestCardState extends ConsumerState<_SandboxFundTestCard> {
  final _amountController = TextEditingController(text: '100.00');
  String? _accountKey;
  String _currency = 'GBP';
  var _isSubmitting = false;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = widget.accounts;
    final accountOptions = _accountOptions(accounts);
    final selectedEntry = _selectedAccountEntry(accountOptions);
    final selectedAccount = selectedEntry?.account;
    final currencyOptions = _accountCurrencyOptions(selectedAccount);

    if (selectedAccount != null && !currencyOptions.contains(_currency)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currency = currencyOptions.first);
        }
      });
    }

    final isExample = context.isExampleTheme;
    const notice = 'Sandbox only. This uses the provider staging fund-test '
        'and must not be shown for production funding.';

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (isExample)
              const ExampleIconTile(
                icon: Icons.science_outlined,
                color: ExampleColors.warning,
              )
            else
              const Icon(Icons.science_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                context.tr('Fund Account Balance'),
                style: isExample
                    ? TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: ExampleInk.primary(context),
                      )
                    : Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isExample
                ? ExampleInk.tint(context, ExampleColors.warning)
                : Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(isExample ? AppRadii.sm : 8),
          ),
          child: Text(
            notice,
            style: isExample
                ? TextStyle(
                    fontSize: 12.5,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.accent(context, ExampleColors.warning),
                  )
                : Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
          ),
        ),
        const SizedBox(height: 12),
        if (accounts.isEmpty)
          Text(context.tr('No fiat account is available to fund.'))
        else ...[
          // `isExpanded` on Example only. Without it the button row is sized to
          // the label's intrinsic width, and a real Equals account — a name
          // plus its supported currencies — overflowed the field by 120 px at
          // 375, which the laws forbid outright. Expanding bounds the label so
          // the ellipsis below can do its job. The flag is gated because it
          // also moves the arrow to the field's right edge, and a white-label
          // tenant's dropdown must keep the pixels it renders today.
          DropdownButtonFormField<String>(
            isExpanded: isExample,
            initialValue: selectedEntry?.key,
            decoration: InputDecoration(labelText: context.tr('Account')),
            items: [
              for (final option in accountOptions)
                DropdownMenuItem(
                  value: option.key,
                  // A no-op while the label is unbounded (the white-label
                  // path), and the truncation rule while it is bounded.
                  child: Text(
                    _accountOptionLabel(option.account),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _isSubmitting
                ? null
                : (value) {
                    setState(() {
                      _accountKey = value;
                      final account =
                          _selectedAccountEntry(accountOptions)?.account;
                      _currency = _accountCurrencyOptions(account).first;
                    });
                  },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            // Matched to the field above so the pair reads as one column
            // rather than two dropdowns of different widths.
            isExpanded: isExample,
            initialValue: _currency,
            decoration: InputDecoration(labelText: context.tr('Currency')),
            items: [
              for (final currency in currencyOptions)
                DropdownMenuItem(value: currency, child: Text(currency)),
            ],
            onChanged: _isSubmitting
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _currency = value);
                    }
                  },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            enabled: !_isSubmitting,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: context.tr('Amount'),
              prefixIcon: const Icon(Icons.payments_outlined),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            // Left exactly as it was: this Align wraps the white-label branch
            // too, and swapping it for AlignmentDirectional would change a
            // non-Example tenant's tree.
            alignment: Alignment.centerRight,
            // Example gets the house material so this panel stops being the
            // one place in banking that answers with a Material slab — but
            // `neutral`, not `primary`, and that is the point. The accounts
            // ledger deliberately has no decisive action (see the account
            // details sheet, which is where the one glass primary lives);
            // making a sandbox fund-test the loudest object on the screen
            // would put the emphasis on the only control here that must never
            // reach production. Neutral keeps the silhouette, the 44 pt
            // floor, the press and the focus ring, and stays quiet.
            //
            // `loading` replaces the spinner-in-the-icon-slot: the button
            // holds its width and position instead of shrinking its label to
            // an 18 px dot, and a screen reader hears "in progress".
            child: context.isExampleTheme
                ? ExampleGlassButton(
                    label: context.tr('Fund test balance'),
                    icon: Icons.add,
                    tone: ExampleGlassButtonTone.neutral,
                    expand: false,
                    sheen: false,
                    loading: _isSubmitting,
                    loadingSemanticsLabel: 'Funding test balance',
                    onPressed: _isSubmitting || selectedAccount == null
                        ? null
                        : () => _submit(context, selectedAccount),
                  )
                : FilledButton.icon(
                    onPressed: _isSubmitting || selectedAccount == null
                        ? null
                        : () => _submit(context, selectedAccount),
                    icon: _isSubmitting
                        ? const SizedBox.square(
                            dimension: 18,
                            child: AppProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: Text(context.tr('Fund test balance')),
                  ),
          ),
        ],
      ],
    );

    if (!isExample) {
      return Card(
        child: Padding(padding: const EdgeInsets.all(16), child: body),
      );
    }
    return _ExamplePanel(child: body);
  }

  _AccountDropdownOption? _selectedAccountEntry(
    List<_AccountDropdownOption> accounts,
  ) {
    if (accounts.isEmpty) {
      return null;
    }
    final selectedKey = _accountKey;
    if (selectedKey != null) {
      for (final option in accounts) {
        if (option.key == selectedKey) {
          return option;
        }
      }
    }

    return accounts.first;
  }

  Future<void> _submit(BuildContext context, AccountBalance account) async {
    final amount = double.tryParse(
      _amountController.text.trim().replaceAll(',', '.'),
    );
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(context.tr('Enter an amount greater than zero.'))),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref.read(mobileBankingApiProvider).fundTestAccount(
            accountId: account.id,
            amount: Money(
              currency: _currency,
              minorUnits: (amount * 100).round(),
            ),
          );
      ref
        ..invalidate(accountsProvider)
        ..invalidate(dashboardProvider)
        ..invalidate(bankingBalancesProvider)
        ..invalidate(budgetsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('Sandbox balance funded.'))),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }
}

class _EqualsBudgetAccountCards extends StatelessWidget {
  const _EqualsBudgetAccountCards({
    required this.budgets,
    required this.details,
    required this.disclosure,
  });

  final List<PlatformResource> budgets;
  final List<_EqualsMoneyInfoGroup> details;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return _ExampleBudgetsSection(
        budgets: budgets,
        details: details,
        disclosure: disclosure,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Fiat account'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          context.tr('Accounts and budgets'),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < budgets.length; index++) ...[
          _EqualsBudgetAccountCard(
            budget: budgets[index],
            details: index < details.length
                ? [details[index]]
                : details.length == 1
                    ? details
                    : const [],
            disclosure: disclosure,
          ),
          if (index != budgets.length - 1)
            const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
        PaymentServicesDisclosureButton(disclosure: disclosure),
      ],
    );
  }
}

class _EqualsBudgetAccountCard extends StatelessWidget {
  const _EqualsBudgetAccountCard({
    required this.budget,
    required this.details,
    required this.disclosure,
  });

  final PlatformResource budget;
  final List<_EqualsMoneyInfoGroup> details;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balances = _equalsBudgetBalances(budget);
    final currencies = _equalsBudgetCurrencies(budget, balances);
    return NeoSurfaceCard(
      onTap: () => _showEqualsBudgetDetails(
        context,
        budget: budget,
        balances: balances,
        details: details,
        disclosure: disclosure,
      ),
      color: theme.colorScheme.surfaceContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: .14),
            child: Icon(Icons.account_balance_rounded,
                color: theme.colorScheme.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fallbackText(budget.title, 'Fiat budget'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.tr('Fiat account'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (balances.isEmpty)
                  Text(
                    context.tr('No funded balance'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  for (final balance in balances)
                    Text(
                      _formattedDecimalBalance(
                        balance.currency,
                        balance.amount,
                      ),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                if (currencies.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (currencies.length > 1)
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(context.tr('Multi-currency')),
                        ),
                      for (final currency in currencies.take(4))
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(currency),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _EqualsBudgetMoney {
  const _EqualsBudgetMoney({required this.currency, required this.amount});

  final String currency;
  final double amount;
}

List<_EqualsBudgetMoney> _equalsBudgetBalances(PlatformResource budget) {
  final totals = <String, double>{};
  final seen = <String>{};

  void add(Map<String, dynamic> row) {
    final currency = _textValue(row, const [
      'currency',
      'Currency',
      'currencyCode',
      'CurrencyCode',
    ])?.toUpperCase();
    final amount = _equalsBudgetAmount(row);
    if (currency == null || amount == null || amount.abs() < .00000001) return;
    if (!seen.add('$currency:${amount.toStringAsFixed(8)}')) return;
    totals.update(currency, (value) => value + amount, ifAbsent: () => amount);
  }

  for (final key in const [
    'balances',
    'Balances',
    'currencyBalances',
    'CurrencyBalances',
    'availableBalances',
    'AvailableBalances',
  ]) {
    final rows = budget.metadata[key];
    if (rows is List) {
      for (final value in rows.whereType<Map>()) {
        add(value.map((key, value) => MapEntry(key.toString(), value)));
      }
    }
  }
  add(budget.metadata);
  return totals.entries
      .map((entry) =>
          _EqualsBudgetMoney(currency: entry.key, amount: entry.value))
      .toList()
    ..sort((left, right) => left.currency.compareTo(right.currency));
}

double? _equalsBudgetAmount(Map<String, dynamic> row) {
  for (final key in const [
    'available',
    'Available',
    'availableBalance',
    'AvailableBalance',
    'balance',
    'Balance',
    'amount',
    'Amount',
  ]) {
    final value = row[key];
    if (value is Map) {
      final nested = _equalsBudgetAmount(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (nested != null) return nested;
    }
    if (value is num) return value.toDouble();
    if (value is String) {
      final parsed = double.tryParse(value.replaceAll(',', '.'));
      if (parsed != null) return parsed;
    }
  }
  return null;
}

List<String> _equalsBudgetCurrencies(
  PlatformResource budget,
  List<_EqualsBudgetMoney> balances,
) {
  final values = <String>{for (final balance in balances) balance.currency};
  for (final key in const [
    'currencies',
    'Currencies',
    'supportedCurrencies',
    'SupportedCurrencies',
  ]) {
    final raw = budget.metadata[key];
    if (raw is List) {
      values.addAll(raw.map((value) => value.toString().toUpperCase()));
    }
  }
  return values.where((value) => value.trim().isNotEmpty).toList()..sort();
}

void _showEqualsBudgetDetails(
  BuildContext context, {
  required PlatformResource budget,
  required List<_EqualsBudgetMoney> balances,
  required List<_EqualsMoneyInfoGroup> details,
  required String disclosure,
}) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Account & budget details')),
          leading: Builder(
            builder: (dialogContext) => IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: [
            Text(
              fallbackText(budget.title, 'Fiat budget'),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 4),
            Text(context.tr('Fiat account')),
            const SizedBox(height: AppSpacing.lg),
            if (context.isExampleTheme)
              _ExampleBalanceBlock(balances: balances)
            else
              NeoSurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.tr('Available balance')),
                    const SizedBox(height: AppSpacing.xs),
                    if (balances.isEmpty)
                      Text(context.tr('No funded balance'))
                    else
                      for (final balance in balances)
                        Text(
                          _formattedDecimalBalance(
                            balance.currency,
                            balance.amount,
                          ),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                  ],
                ),
              ),
            const SafeguardingStatementButton(),
            if (details.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              if (context.isExampleTheme) ...[
                ExampleSectionTitle(title: context.tr('Receiving details')),
                const SizedBox(height: AppSpacing.sm),
                ExampleListGroup(
                  children: [
                    for (final group in details)
                      ExampleRow(
                        title: group.title,
                        subtitle: _maskAccountIdentifier(
                          _groupAccountIdentifier(group),
                        ),
                        leading: const ExampleIconTile(
                          icon: Icons.account_balance_outlined,
                          color: ExampleColors.iris,
                        ),
                        trailing: const Icon(
                          Icons.qr_code_2_rounded,
                          size: 20,
                        ),
                        semanticsLabel: context.tr(
                            'Show QR and bank details for {p0}',
                            {'p0': group.title}),
                        onTap: () => _showAccountQrDialog(context, group),
                      ),
                  ],
                ),
              ] else ...[
                Text(context.tr('Receiving details'),
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.sm),
                for (final group in details)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: NeoSurfaceCard(
                      onTap: () => _showAccountQrDialog(context, group),
                      child: Row(
                        children: [
                          const Icon(Icons.account_balance_outlined),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(group.title),
                                Text(
                                  _maskAccountIdentifier(
                                    _groupAccountIdentifier(group),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.qr_code_2_rounded),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
            const SizedBox(height: AppSpacing.md),
            PaymentServicesDisclosureButton(disclosure: disclosure),
          ],
        ),
      ),
    ),
  );
}

class _SupportedCurrencyBalances extends StatelessWidget {
  const _SupportedCurrencyBalances({
    required this.accounts,
    this.details = const [],
  });

  final List<AccountBalance> accounts;
  final List<_EqualsMoneyInfoGroup> details;

  @override
  Widget build(BuildContext context) {
    if (accounts.isEmpty) {
      return EmptyState(
        title: context.tr('No balances yet'),
        message: context
            .tr('Provider balances appear after money reaches the account.'),
        icon: Icons.account_balance_wallet_outlined,
      );
    }

    if (context.isExampleTheme) {
      return _ExampleAccountsSection(accounts: accounts, details: details);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('My accounts'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (var index = 0; index < accounts.length; index++) ...[
          _EqualsAccountCard(
            account: accounts[index],
            details: _detailsForAccount(
              accounts[index],
              details,
              accountIndex: index,
              accountCount: accounts.length,
            ),
          ),
          if (index != accounts.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _EqualsAccountCard extends StatelessWidget {
  const _EqualsAccountCard({required this.account, this.details});

  final AccountBalance account;
  final _EqualsMoneyInfoGroup? details;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balances = _displayAccountBalances(account);
    final identifier = _accountDisplayIdentifier(account).isNotEmpty
        ? _accountDisplayIdentifier(account)
        : _groupAccountIdentifier(details);
    final currencies = <String>{
      ...account.supportedCurrencies,
      ...balances.map((balance) => balance.currency),
    }.where((value) => value.trim().isNotEmpty).toList();
    final provider = account.provider.trim();

    return NeoSurfaceCard(
      color: theme.colorScheme.surfaceContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: .14),
                child: Icon(
                  Icons.account_balance_wallet_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fallbackText(account.name, 'Account'),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (provider.isNotEmpty)
                      Text(
                        provider,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              _StatusChip(status: account.status),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (currencies.length > 1)
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(context.tr('Multi-currency')),
                ),
              for (final currency in currencies.take(4))
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(currency.toUpperCase()),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (balances.isEmpty)
            Text(
              context.tr('No funded balance'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final balance in balances)
                  Text(
                    balance.formatted,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
          if (identifier.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              _maskAccountIdentifier(identifier),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: .4,
              ),
            ),
          ],
          if (details != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showAccountQrDialog(context, details!),
                icon: const Icon(Icons.account_balance_outlined),
                label: Text(context.tr('Account details & QR')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountDropdownOption {
  const _AccountDropdownOption({
    required this.key,
    required this.account,
  });

  final String key;
  final AccountBalance account;
}

List<_AccountDropdownOption> _accountOptions(List<AccountBalance> accounts) {
  return [
    for (var index = 0; index < accounts.length; index++)
      _AccountDropdownOption(
        key: '${accounts[index].id}#$index',
        account: accounts[index],
      ),
  ];
}

String _accountOptionLabel(AccountBalance account) {
  final currencies = _accountCurrencyOptions(account).take(3).join(', ');
  final name = fallbackText(account.name, account.id);
  return currencies.isEmpty ? name : '$name ($currencies)';
}

List<String> _accountCurrencyOptions(AccountBalance? account) {
  if (account == null) {
    return const ['GBP'];
  }

  final currencies = <String>{
    ...account.supportedCurrencies,
    ...account.linkedBankAccounts.map((bank) => bank.currency),
    account.available.currency,
    account.balance.currency,
  }
      .map((currency) => currency.trim().toUpperCase())
      .where(equalsSupportedCurrencyCodes.contains)
      .toList()
    ..sort();

  if (currencies.isEmpty) {
    return equalsSupportedCurrencyCodes;
  }

  return currencies;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = friendlyStatus(status);
    if (context.isExampleTheme) {
      return ExamplePill(label: label, color: _statusTone(status), dot: true);
    }
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
    );
  }
}

/// Status hues by meaning, as brand tokens. `ExamplePill` washes the pill in
/// the hue and deepens the label for the active theme, so nothing here reaches
/// a `TextStyle` directly.
Color _statusTone(String status) {
  final normalized = status.trim().toLowerCase().replaceAll('_', ' ');
  if (_activeStatuses.contains(normalized)) return ExampleColors.success;
  if (normalized.contains('pend') ||
      normalized.contains('review') ||
      normalized.contains('progress')) {
    return ExampleColors.warning;
  }
  if (normalized.contains('block') ||
      normalized.contains('fail') ||
      normalized.contains('reject') ||
      normalized.contains('closed') ||
      normalized.contains('suspend')) {
    return ExampleColors.danger;
  }
  return ExampleColors.iris;
}

const Set<String> _activeStatuses = {'active', 'open', 'enabled', 'live', 'ok'};

/// True when a status is the unremarkable one. A banking list that labels
/// every healthy row "Active" is labelling nothing; the pill is for the
/// exception.
bool _isRoutineStatus(String status) =>
    _activeStatuses.contains(status.trim().toLowerCase().replaceAll('_', ' '));

class _EqualsMoneyInfoGroup {
  const _EqualsMoneyInfoGroup({
    required this.title,
    required this.rows,
    required this.qrPayload,
  });

  final String title;
  final List<(String, String)> rows;
  final String qrPayload;
}

String _maskAccountIdentifier(String value) {
  final compact = value.replaceAll(' ', '');
  if (compact.length <= 8) return value;
  return '${compact.substring(0, 4)} •••• ${compact.substring(compact.length - 4)}';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) return _example(context);

    if (label == 'Available currencies') {
      final currencies = value
          .split(',')
          .map((currency) => currency.trim())
          .where((currency) => currency.isNotEmpty)
          .toList();
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 12),
          title: Text(
            context.tr('Available currencies'),
            style: Theme.of(context).textTheme.labelLarge,
          ),
          subtitle: Text(context
              .tr('{p0} supported currencies', {'p0': currencies.length})),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final currency in currencies)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(currency),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final isIdentifier = _identifierLabels.contains(label);
    if (isIdentifier) {
      return Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      maxLines: 1,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: context.brandDesign.isConfigured
                                ? context.brandDesign.monoFontFamily
                                : 'monospace',
                            letterSpacing: .2,
                          ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr('Copy {p0}', {'p0': label}),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _copyAccountDetail(context, label, value),
                  icon: const Icon(Icons.copy_rounded, size: 18),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }

  /// The daylight-and-Twilight form: a flexible label, a flexible value, and
  /// machine strings in [ExampleMono] that elide in the middle and copy in
  /// place. No fixed label column and no `FittedBox` — a shrinking IBAN is
  /// truncation with extra steps.
  Widget _example(BuildContext context) {
    if (label == 'Available currencies') {
      final currencies = value
          .split(',')
          .map((currency) => currency.trim().toUpperCase())
          .where((currency) => currency.isNotEmpty)
          .toList();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Available currencies'),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: ExampleInk.secondary(context),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final currency in currencies)
                  ExamplePill(label: currency, color: ExampleColors.iris),
              ],
            ),
          ],
        ),
      );
    }

    final mono = _identifierLabels.contains(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 40/60, both halves flexible: the value keeps the right edge, and
          // neither a long label nor a long IBAN can push the other out of the
          // row the way a natural-width child would.
          Expanded(
            flex: 4,
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.35,
                color: ExampleInk.secondary(context),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 6,
            child: mono
                ? ExampleMono(
                    value,
                    group: label == 'IBAN' ? 4 : 0,
                    truncate: ExampleMonoTruncate.middle,
                    head: 10,
                    tail: 4,
                    size: 12.5,
                    textAlign: TextAlign.end,
                    copyable: true,
                  )
                : Text(
                    value,
                    maxLines: 3,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                      color: ExampleInk.primary(context),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Labels whose value is a machine string: set in mono, elided in the middle,
/// copied whole.
const Set<String> _identifierLabels = {
  'Account number',
  'IBAN',
  'SWIFT/BIC',
  'Sort code',
  'Routing number',
};

Future<void> _copyAccountDetail(
  BuildContext context,
  String label,
  String value,
) async {
  await Clipboard.setData(ClipboardData(text: value));
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(context.tr('{p0} copied', {'p0': label}))),
  );
}

void _showAccountQrDialog(
  BuildContext context,
  _EqualsMoneyInfoGroup group,
) {
  showDialog<void>(
    context: context,
    useSafeArea: false,
    builder: (_) => Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: Builder(
            builder: (pageContext) => IconButton(
              tooltip: context.tr('Close'),
              onPressed: () => Navigator.of(pageContext).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          title: Text(context.tr('Account details')),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 120),
          children: [
            Text(
              group.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              context.tr('Share this QR code or copy the bank details.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            LayoutBuilder(
              builder: (context, constraints) {
                final qrSize = (constraints.maxWidth - 32).clamp(180.0, 260.0);
                return Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: QrImageView(
                        data: group.qrPayload,
                        version: QrVersions.auto,
                        size: qrSize,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            if (context.isExampleTheme)
              _ExamplePanel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in group.rows)
                      _DetailRow(label: row.$1, value: row.$2),
                  ],
                ),
              )
            else
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final row in group.rows)
                        _DetailRow(label: row.$1, value: row.$2),
                    ],
                  ),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(24, 12, 24, 16),
          child: Builder(
            builder: (pageContext) {
              // The reason this sheet was opened, and the only decisive action
              // in banking: the account list itself is a ledger and correctly
              // gets no glass button at all. Pinned in a bar with the page
              // scrolling under it, so it takes the plain-ground material —
              // the bar is painted, there is nothing behind it to bend, and an
              // opaque body cannot dissolve over a pale QR block.
              if (!pageContext.isExampleTheme) {
                return FilledButton.icon(
                  onPressed: () => _copyAccountDetail(
                    pageContext,
                    'Account details',
                    group.qrPayload,
                  ),
                  icon: const Icon(Icons.copy),
                  label: Text(context.tr('Copy account details')),
                );
              }
              return ExampleGlassButton(
                label: context.tr('Copy account details'),
                icon: Icons.copy_rounded,
                onPressed: () => _copyAccountDetail(
                  pageContext,
                  'Account details',
                  group.qrPayload,
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}

List<(String, String)> _equalsMoneyRows(PlatformResource info) {
  final metadata = _payloadMap(info.metadata);
  final linkedBankAccounts =
      _listValue(metadata, const ['linkedBankAccounts', 'LinkedBankAccounts']);
  final bank = linkedBankAccounts?.whereType<Map>().firstOrNull;
  final bankMetadata =
      bank?.map((key, value) => MapEntry(key.toString(), value)) ?? metadata;
  final routingCodes = _routingCodeRows(metadata);

  final values = <(String, String?)>[
    ('Currency', _textValue(metadata, const ['currency', 'Currency'])),
    (
      'Payment method',
      _textValue(metadata, const ['paymentMethod', 'PaymentMethod'])
    ),
    ('Account holder', _textValue(metadata, const ['userName', 'UserName'])),
    ('Currency', _textValue(bankMetadata, const ['currency', 'Currency'])),
    ('IBAN', _textValue(bankMetadata, const ['iban', 'Iban'])),
    (
      'Account number',
      _textValue(bankMetadata, const ['accountNumber', 'AccountNumber'])
    ),
    (
      'SWIFT/BIC',
      _textValue(
          bankMetadata, const ['swift', 'Swift', 'swiftCode', 'SwiftCode'])
    ),
    (
      'Routing number',
      _textValue(bankMetadata, const ['routingNumber', 'RoutingNumber'])
    ),
    ('Bank', _textValue(bankMetadata, const ['bankName', 'BankName'])),
    ('Status', _textValue(metadata, const ['status', 'Status'])),
  ];

  final rows = <(String, String)>[];
  final seenIdentifiers = <String>{};
  for (final row in [
    ...values
        .where((row) => row.$2 != null && row.$2!.trim().isNotEmpty)
        .map((row) => (row.$1, row.$2!.trim())),
    ...routingCodes,
  ]) {
    final isAccountIdentifier = row.$1 == 'IBAN' || row.$1 == 'Account number';
    final normalized = row.$2.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (isAccountIdentifier && !seenIdentifiers.add(normalized)) continue;
    rows.add(row);
  }
  return rows;
}

List<_EqualsMoneyInfoGroup> _equalsMoneyGroups(List<PlatformResource> infos) {
  final grouped = <String, _MutableEqualsMoneyInfoGroup>{};

  for (final info in infos) {
    final metadata = _payloadMap(info.metadata);
    final linkedBankAccounts = _listValue(
        metadata, const ['linkedBankAccounts', 'LinkedBankAccounts']);
    final bank = linkedBankAccounts?.whereType<Map>().firstOrNull;
    final bankMetadata =
        bank?.map((key, value) => MapEntry(key.toString(), value)) ?? metadata;
    final paymentMethod =
        _textValue(metadata, const ['paymentMethod', 'PaymentMethod']) ??
            'Unknown method';
    final accountNumber = _accountIdentifier(bankMetadata, metadata);
    final key = accountNumber.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final currency = _currencyFromInfo(info).trim().toUpperCase();

    final group = grouped.putIfAbsent(
      key,
      () => _MutableEqualsMoneyInfoGroup(
        accountNumber: accountNumber,
        rows: _equalsMoneyRowsWithoutCurrency(info),
      ),
    );
    group.paymentMethods.add(paymentMethod);
    for (final row in _equalsMoneyRowsWithoutCurrency(info)) {
      if (!group.rows.contains(row)) {
        group.rows.add(row);
      }
    }
    if (currency.isNotEmpty && currency != 'ACCOUNT') {
      group.currencies.add(currency);
    }
  }

  return grouped.values.map((group) {
    final currencies = group.currencies.toList()..sort();
    final paymentMethods = group.paymentMethods.toList()..sort();
    final rows = <(String, String)>[
      if (paymentMethods.isNotEmpty)
        ('Payment methods', paymentMethods.join(', ')),
      if (currencies.isNotEmpty)
        ('Available currencies', currencies.join(', ')),
      ...group.rows,
    ];

    return _EqualsMoneyInfoGroup(
      title: group.accountNumber == 'Account'
          ? paymentMethods.join(' / ')
          : 'Account ${_maskAccountIdentifier(group.accountNumber)}',
      rows: rows,
      qrPayload: _accountQrPayload(paymentMethods.join(' / '), rows),
    );
  }).toList();
}

class _MutableEqualsMoneyInfoGroup {
  _MutableEqualsMoneyInfoGroup({
    required this.accountNumber,
    required this.rows,
  });

  final String accountNumber;
  final List<(String, String)> rows;
  final Set<String> paymentMethods = {};
  final Set<String> currencies = {};
}

List<(String, String)> _equalsMoneyRowsWithoutCurrency(PlatformResource info) {
  return _equalsMoneyRows(info)
      .where(
        (row) =>
            row.$1.toLowerCase() != 'currency' &&
            row.$1.toLowerCase() != 'payment method',
      )
      .toList();
}

String _accountQrPayload(String paymentMethod, List<(String, String)> rows) {
  final rowMap = {
    for (final row in rows) row.$1.toLowerCase(): row.$2,
  };
  final accountNumber = rowMap['iban'] ?? rowMap['account number'];
  final holder = rowMap['account holder'];
  final bank = rowMap['bank'];
  final swift = rowMap['swift/bic'];
  final sortCode = rowMap['sort code'];
  final currencies = rowMap['available currencies'];

  final lines = <String>[
    'Fiat account details',
    if (paymentMethod.trim().isNotEmpty) 'Payment method: $paymentMethod',
    if (holder != null) 'Account holder: $holder',
    if (accountNumber != null) 'Account number: $accountNumber',
    if (swift != null) 'SWIFT/BIC: $swift',
    if (sortCode != null) 'Sort code: $sortCode',
    if (bank != null) 'Bank: $bank',
    if (currencies != null) 'Currencies: $currencies',
  ];

  return lines.join('\n');
}

String _accountIdentifier(
  Map<String, dynamic> bankMetadata,
  Map<String, dynamic> metadata,
) {
  return _textValue(bankMetadata, const ['accountNumber', 'AccountNumber']) ??
      _textValue(bankMetadata, const ['iban', 'Iban']) ??
      _textValue(metadata, const ['accountNumber', 'AccountNumber']) ??
      _textValue(metadata, const ['externalId', 'ExternalId']) ??
      'Account';
}

bool _isEqualsMoneyAccount(AccountBalance account) {
  return account.provider.toLowerCase().contains('equals');
}

String _currencyFromInfo(PlatformResource info) {
  return _textValue(
        _payloadMap(info.metadata),
        const ['currency', 'Currency'],
      ) ??
      'Account';
}

List<(String, String)> _routingCodeRows(Map<String, dynamic> metadata) {
  final routingCodes =
      _listValue(metadata, const ['routingCodes', 'RoutingCodes']);
  if (routingCodes == null) {
    return const [];
  }

  return routingCodes
      .whereType<Map>()
      .map((item) {
        final code = item.map((key, value) => MapEntry(key.toString(), value));
        final type =
            _textValue(code, const ['routingCodeType', 'RoutingCodeType']);
        final value =
            _textValue(code, const ['routingCodeValue', 'RoutingCodeValue']);
        if (type == null || value == null) {
          return null;
        }

        return (_routingLabel(type), value);
      })
      .whereType<(String, String)>()
      .toList();
}

String _routingLabel(String type) {
  final normalized = type.toLowerCase().replaceAll('-', '_').trim();
  return switch (normalized) {
    'iban' => 'IBAN',
    'swift' || 'swift_code' => 'SWIFT/BIC',
    'sort_code' => 'Sort code',
    _ => type,
  };
}

List<Money> _displayAccountBalances(AccountBalance account) {
  final rows = <Money>[];
  final seen = <String>{};
  final supported = account.supportedCurrencies
      .map((value) => value.trim().toUpperCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  final candidates = account.currencyBalances.isNotEmpty
      ? account.currencyBalances
      : <Money>[account.available, account.balance];

  for (final balance in candidates) {
    final currency = balance.currency.trim().toUpperCase();
    if (currency.isEmpty ||
        balance.minorUnits == 0 ||
        (supported.isNotEmpty && !supported.contains(currency))) {
      continue;
    }
    final key = '$currency:${balance.minorUnits}';
    if (seen.add(key)) {
      rows.add(balance);
    }
  }
  return rows;
}

_EqualsMoneyInfoGroup? _detailsForAccount(
  AccountBalance account,
  List<_EqualsMoneyInfoGroup> groups, {
  required int accountIndex,
  required int accountCount,
}) {
  final identifiers = <String>{
    account.iban,
    account.accountNumber,
    for (final bank in account.linkedBankAccounts) bank.iban,
    for (final bank in account.linkedBankAccounts) bank.accountNumber,
  }
      .map(_normalizedAccountIdentifier)
      .where((value) => value.isNotEmpty)
      .toSet();

  for (final group in groups) {
    final groupIdentifiers = group.rows
        .where((row) => row.$1 == 'IBAN' || row.$1 == 'Account number')
        .map((row) => _normalizedAccountIdentifier(row.$2));
    if (groupIdentifiers.any(identifiers.contains)) return group;
  }
  if (groups.length == accountCount && accountIndex < groups.length) {
    return groups[accountIndex];
  }
  return null;
}

String _groupAccountIdentifier(_EqualsMoneyInfoGroup? group) {
  if (group == null) return '';
  return group.rows
          .where((row) => row.$1 == 'IBAN' || row.$1 == 'Account number')
          .map((row) => row.$2.trim())
          .where((value) => value.isNotEmpty)
          .firstOrNull ??
      '';
}

String _normalizedAccountIdentifier(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

String _accountDisplayIdentifier(AccountBalance account) {
  if (account.iban.trim().isNotEmpty) return account.iban.trim();
  for (final bank in account.linkedBankAccounts) {
    if (bank.iban.trim().isNotEmpty) return bank.iban.trim();
  }
  if (account.accountNumber.trim().isNotEmpty) {
    return account.accountNumber.trim();
  }
  for (final bank in account.linkedBankAccounts) {
    if (bank.accountNumber.trim().isNotEmpty) {
      return bank.accountNumber.trim();
    }
  }
  return '';
}

Map<String, dynamic> _payloadMap(Map<String, dynamic> metadata) {
  for (final key in const ['data', 'Data', 'account', 'Account', 'result']) {
    final value = metadata[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
  }

  return metadata;
}

List<Object?>? _listValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) {
      return value;
    }
  }

  return null;
}

String? _textValue(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString();
    }
  }

  return null;
}

// ---------------------------------------------------------------------------
// Example presentation
//
// Both themes are first class here: every colour is a named role resolved for
// the active brightness through ExampleSurface / ExampleInk / ExampleBorders /
// ExampleShadows, so Twilight keeps the values it always had and Pearl daylight
// is designed rather than inverted. Nothing in this section renders for
// another brand — every entry point is behind `context.isExampleTheme`.
// ---------------------------------------------------------------------------

/// A matte Example panel: level-1 surface, `AppRadii.lg` corners, one shadow
/// and no border. The shadow is the containment — the violet lift at night,
/// the night ambient on paper — which is why there is no edge to go with it.
class _ExamplePanel extends StatelessWidget {
  const _ExamplePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: BorderRadius.circular(AppRadii.lg),
          boxShadow: ExampleTheme.isLight(context)
              ? ExampleShadows.ambientLight
              : ExampleShadows.lift,
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: child,
        ),
      );
}

/// The one hairline on the page, and the screen's only sheen host.
///
/// It opens the account panel under the total, which is the law's "panel's top
/// hairline". Soft intensity, one band, on the shared screen clock — and a
/// fixed highlight with no ticker under reduced motion, because [ExampleSheen]
/// never reaches a ticker in that case.
class _ExampleSheenHairline extends StatelessWidget {
  const _ExampleSheenHairline();

  @override
  Widget build(BuildContext context) => ExampleSheen(
        intensity: ExampleSheenIntensity.soft,
        borderRadius: BorderRadius.zero,
        child: SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(
            color: ExampleBorders.hairlineSideOf(context).color,
          ),
        ),
      );
}

/// One currency's total across a set of accounts or budgets.
class _CurrencyTotal {
  const _CurrencyTotal({required this.currency, required this.amount});

  final String currency;
  final double amount;
}

/// The one figure on the screen, on a panel that is nothing but type and a
/// single closing hairline.
///
/// Deliberately not a card: a total inside a card inside a page is the nested
/// card the laws reject, and the balance does not need a container to be the
/// loudest thing here. Money that sits in more than one currency has no honest
/// single total, so the largest currency is the headline and the rest follow
/// underneath at inline size — never a summed number that means nothing.
class _ExampleTotalPanel extends StatelessWidget {
  const _ExampleTotalPanel({
    required this.label,
    required this.totals,
    required this.caption,
  });

  final String label;
  final List<_CurrencyTotal> totals;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final primary = totals.isEmpty ? null : totals.first;
    final others =
        totals.length > 1 ? totals.sublist(1) : const <_CurrencyTotal>[];
    // At large text scales the 36 px line cannot hold a seven-figure balance
    // on a 375 px page, so the amount steps down a notch rather than fading
    // its own last digits. On a desktop page the opposite problem applies: a
    // 36 px total floating in a 1440 px column has no more presence than a row
    // label, and this number is the whole reason the page exists, so it takes
    // the top of the amount scale there. Nothing below 834 moves.
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final size = textScale > 1.15
        ? ExampleAmountSize.medium
        : MediaQuery.sizeOf(context).width >= 834 && textScale <= 1.0
            ? ExampleAmountSize.hero
            : ExampleAmountSize.large;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ExampleTextStyles.label(context),
              ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(
                caption,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: ExampleInk.tertiary(context),
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ExampleAmount(
          amount: primary?.amount,
          currency: primary?.currency ?? '',
          size: size,
          code: ExampleAmountCode.always,
        ),
        if (others.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final total in others)
                ExampleAmount(
                  amount: total.amount,
                  currency: total.currency,
                  size: ExampleAmountSize.inline,
                  code: ExampleAmountCode.always,
                  animate: false,
                  color: ExampleInk.secondary(context),
                ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        const _ExampleSheenHairline(),
      ],
    );
  }
}

/// The trailing money column of a row: the amount in tabular figures, right
/// aligned, with a quiet caption under it. `ExampleAmount` already sets
/// `maxLines: 1` and `softWrap: false`, so the column keeps one line per row
/// and the digits of a list line up down the page.
class _ExampleTrailingAmount extends StatelessWidget {
  const _ExampleTrailingAmount({
    required this.amount,
    required this.currency,
    this.caption,
  });

  final double? amount;
  final String currency;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final captionText = caption;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ExampleAmount(
          amount: amount,
          currency: currency,
          size: ExampleAmountSize.small,
          code: ExampleAmountCode.never,
          animate: false,
          textAlign: TextAlign.end,
        ),
        if (captionText != null && captionText.isNotEmpty)
          Text(
            captionText,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
              color: ExampleInk.tertiary(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// The accounts screen in the Example register: one total, one hairline, one
/// list group. No arrival moment — this is a utility screen and the balance is
/// already the loudest thing on it.
class _ExampleAccountsSection extends StatelessWidget {
  const _ExampleAccountsSection({required this.accounts, required this.details});

  final List<AccountBalance> accounts;
  final List<_EqualsMoneyInfoGroup> details;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExampleTotalPanel(
          label: context.tr('Total balance'),
          totals: _accountTotals(accounts),
          caption: accounts.length == 1
              ? context.tr('1 account')
              : context.tr('{p0} accounts', {'p0': accounts.length}),
        ),
        const SizedBox(height: AppSpacing.md),
        ExampleListGroup(
          children: [
            for (var index = 0; index < accounts.length; index++)
              _ExampleAccountRow(
                account: accounts[index],
                details: _detailsForAccount(
                  accounts[index],
                  details,
                  accountIndex: index,
                  accountCount: accounts.length,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// One account: currency badge, name, the IBAN fragment in [ExampleMono], and
/// the balance right-aligned in tabular figures.
///
/// The status pill only appears when the status is not the routine one — a
/// list that labels every healthy account "Active" is labelling nothing. The
/// row's metrics are `ExampleRow`'s exactly (56 pt floor, 40 pt leading slot,
/// 12 pt gap), so the group's dividers inset to the same text column.
class _ExampleAccountRow extends StatelessWidget {
  const _ExampleAccountRow({required this.account, this.details});

  final AccountBalance account;
  final _EqualsMoneyInfoGroup? details;

  @override
  Widget build(BuildContext context) {
    final group = details;
    final balances = _displayAccountBalances(account);
    final primary = balances.isNotEmpty ? balances.first : account.balance;
    final identifier = _accountDisplayIdentifier(account).isNotEmpty
        ? _accountDisplayIdentifier(account)
        : _groupAccountIdentifier(group);
    final currency = primary.currency.trim().toUpperCase();
    final name = fallbackText(account.name, 'Account');
    final status = account.status.trim();
    final showStatus = status.isNotEmpty && !_isRoutineStatus(status);
    final provider = account.provider.trim();

    Widget row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: Row(
          children: [
            SizedBox.square(
              dimension: ExampleRow.leadingSize,
              child: Center(
                child: ExampleCurrencyAvatar(code: currency, size: 34),
              ),
            ),
            const SizedBox(width: ExampleRow.leadingGap),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                  // A `Wrap`, not a `Row`: a pill is natural-width, and a
                  // provider that returns a long status string ("Pending
                  // verification") would tear a `Row` at 375 px. Here it drops
                  // under the reference instead, and the row grows with it.
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xxs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (identifier.isNotEmpty)
                        ExampleMono(
                          _maskAccountIdentifier(identifier),
                          size: 12,
                          color: ExampleInk.secondary(context),
                        )
                      else
                        Text(
                          fallbackText(provider, 'Account'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                      if (showStatus)
                        ExamplePill(
                          label: friendlyStatus(status),
                          color: _statusTone(status),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (balances.isEmpty)
                  Text(
                    context.tr('No funded balance'),
                    style: TextStyle(
                      fontSize: 12,
                      color: ExampleInk.secondary(context),
                    ),
                  )
                else
                  for (final balance in balances)
                    _ExampleTrailingAmount(
                      amount: balance.minorUnits / 100,
                      currency: balance.currency,
                      caption: balance.currency.toUpperCase(),
                    ),
              ],
            ),
            if (group != null) ...[
              const SizedBox(width: AppSpacing.xxs),
              ExampleRow.chevronOf(context),
            ],
          ],
        ),
      ),
    );

    if (group == null) return MergeSemantics(child: row);
    return ExamplePressable(
      onTap: () => _showAccountQrDialog(context, group),
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
      semanticsLabel: context.tr('Account details and QR for {p0}, {p1}',
          {'p0': name, 'p1': primary.formatted}),
      child: row,
    );
  }
}

/// The budget variant of the same page: one total, one hairline, one group of
/// budget rows, and the payment-services disclosure under it.
class _ExampleBudgetsSection extends StatelessWidget {
  const _ExampleBudgetsSection({
    required this.budgets,
    required this.details,
    required this.disclosure,
  });

  final List<PlatformResource> budgets;
  final List<_EqualsMoneyInfoGroup> details;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExampleTotalPanel(
          label: context.tr('Fiat account'),
          totals: _budgetTotals(budgets),
          caption: budgets.length == 1
              ? context.tr('1 budget')
              : context.tr('{p0} budgets', {'p0': budgets.length}),
        ),
        const SizedBox(height: AppSpacing.md),
        ExampleListGroup(
          children: [
            for (var index = 0; index < budgets.length; index++)
              _ExampleBudgetRow(
                budget: budgets[index],
                details: index < details.length
                    ? [details[index]]
                    : details.length == 1
                        ? details
                        : const [],
                disclosure: disclosure,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        PaymentServicesDisclosureButton(disclosure: disclosure),
      ],
    );
  }
}

/// One budget row. The currencies it holds are the subtitle; the money is the
/// trailing column.
class _ExampleBudgetRow extends StatelessWidget {
  const _ExampleBudgetRow({
    required this.budget,
    required this.details,
    required this.disclosure,
  });

  final PlatformResource budget;
  final List<_EqualsMoneyInfoGroup> details;
  final String disclosure;

  @override
  Widget build(BuildContext context) {
    final balances = _equalsBudgetBalances(budget);
    final currencies = _equalsBudgetCurrencies(budget, balances);
    final primary = balances.isEmpty ? null : balances.first;
    final title = fallbackText(budget.title, 'Fiat budget');
    final subtitle = currencies.isEmpty
        ? context.tr('Fiat account')
        : currencies.take(4).join(' · ');

    return ExampleRow(
      title: title,
      subtitle: subtitle,
      leading: const ExampleIconTile(
        icon: Icons.account_balance_rounded,
        color: ExampleColors.violet,
      ),
      trailing: _ExampleTrailingAmount(
        amount: primary?.amount,
        currency: primary?.currency ?? '',
        caption: balances.length > 1
            ? context.tr('+{p0} more', {'p0': balances.length - 1})
            : primary?.currency ?? '',
      ),
      semanticsLabel:
          context.tr('Account and budget details for {p0}', {'p0': title}),
      onTap: () => _showEqualsBudgetDetails(
        context,
        budget: budget,
        balances: balances,
        details: details,
        disclosure: disclosure,
      ),
    );
  }
}

/// The available-balance block at the head of the budget details sheet.
class _ExampleBalanceBlock extends StatelessWidget {
  const _ExampleBalanceBlock({required this.balances});

  final List<_EqualsBudgetMoney> balances;

  @override
  Widget build(BuildContext context) {
    return _ExamplePanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('AVAILABLE BALANCE'),
            style: ExampleTextStyles.label(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          if (balances.isEmpty)
            const ExampleAmount(
              amount: null,
              currency: '',
              size: ExampleAmountSize.medium,
              animate: false,
            )
          else
            for (final balance in balances)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: ExampleAmount(
                  amount: balance.amount,
                  currency: balance.currency,
                  size: ExampleAmountSize.medium,
                  code: ExampleAmountCode.always,
                  animate: false,
                ),
              ),
        ],
      ),
    );
  }
}

/// Totals per currency across the accounts, largest first. Currencies are
/// never summed together: a page that adds euros to pounds is lying.
List<_CurrencyTotal> _accountTotals(List<AccountBalance> accounts) {
  final sums = <String, double>{};
  for (final account in accounts) {
    final balances = _displayAccountBalances(account);
    final entries = balances.isEmpty ? <Money>[account.balance] : balances;
    for (final balance in entries) {
      final code = balance.currency.trim().toUpperCase();
      if (code.isEmpty) continue;
      sums[code] = (sums[code] ?? 0) + balance.minorUnits / 100;
    }
  }
  return _sortedTotals(sums);
}

/// Totals per currency across the budgets, largest first.
List<_CurrencyTotal> _budgetTotals(List<PlatformResource> budgets) {
  final sums = <String, double>{};
  for (final budget in budgets) {
    for (final balance in _equalsBudgetBalances(budget)) {
      final code = balance.currency.trim().toUpperCase();
      if (code.isEmpty) continue;
      sums[code] = (sums[code] ?? 0) + balance.amount;
    }
  }
  return _sortedTotals(sums);
}

List<_CurrencyTotal> _sortedTotals(Map<String, double> sums) {
  return [
    for (final entry in sums.entries)
      _CurrencyTotal(currency: entry.key, amount: entry.value),
  ]..sort((a, b) {
      final byMagnitude = b.amount.abs().compareTo(a.amount.abs());
      return byMagnitude != 0 ? byMagnitude : a.currency.compareTo(b.currency);
    });
}
