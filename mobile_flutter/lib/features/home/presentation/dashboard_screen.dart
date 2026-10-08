import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import '../../../shared/widgets/safeguarding_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/banking_models.dart';
import '../../../core/widgets/app_states.dart';
import '../../banking/application/banking_providers.dart';
import '../../banking/presentation/widgets/banking_tiles.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Home'))),
      body: dashboard.when(
        data: (snapshot) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _BalanceHeader(snapshot: snapshot),
              if (snapshot.accounts.any((account) =>
                  account.provider.toLowerCase().contains('equals')))
                const SafeguardingStatementButton(),
              const SizedBox(height: 16),
              _OnboardingChecklist(
                tasks: snapshot.onboarding,
                isBusinessAccount: snapshot.profile.isBusinessAccount,
              ),
              const SizedBox(height: 16),
              _SectionHeader(
                title: context.tr('Accounts'),
                actionLabel: context.tr('View'),
                onAction: () => context.go('/accounts'),
              ),
              if (snapshot.accounts.isEmpty)
                _InlineEmpty(
                  icon: Icons.account_balance_wallet_outlined,
                  title: context.tr('No accounts yet'),
                  message: context
                      .tr('Complete onboarding to open your first account.'),
                )
              else
                for (final account in snapshot.accounts)
                  AccountTile(account: account),
              const SizedBox(height: 16),
              _SectionHeader(
                title: context.tr('Cards'),
                actionLabel: context.tr('Manage'),
                onAction: () => context.go('/cards'),
              ),
              if (snapshot.cards.isEmpty)
                _InlineEmpty(
                  icon: Icons.credit_card,
                  title: context.tr('No cards yet'),
                  message:
                      context.tr('Order a card when your account is ready.'),
                )
              else
                ...snapshot.cards.take(2).map<Widget>(
                      (card) => CardTile(
                        card: card,
                        onTap: () => context.go('/cards/${card.id}'),
                      ),
                    ),
              const SizedBox(height: 16),
              _SectionHeader(
                title: context.tr('Recent activity'),
                actionLabel: context.tr('All'),
                onAction: () => context.go('/activity'),
              ),
              if (snapshot.transactions.isEmpty)
                _InlineEmpty(
                  icon: Icons.receipt_long_outlined,
                  title: context.tr('No activity yet'),
                  message: context
                      .tr('Transfers and card payments will appear here.'),
                )
              else
                for (final transaction in snapshot.transactions.take(4))
                  TransactionTile(
                    transaction: transaction,
                    onTap: () => context.go('/transactions/${transaction.id}'),
                  ),
            ],
          ),
        ),
        error: (error, stackTrace) => ErrorState(
          error: error,
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        loading: () => LoadingState(label: context.tr('Loading dashboard')),
      ),
    );
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('Total balance'),
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Text(
            snapshot.totalBalance.formatted,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: snapshot.canUseBanking
                    ? () => context.go('/money/pay')
                    : () => context.go('/onboarding/banking'),
                icon: const Icon(Icons.receipt_long),
                label: Text(context.tr('Pay')),
              ),
              OutlinedButton.icon(
                onPressed: snapshot.canOrderCard
                    ? () => context.go('/cards/order')
                    : null,
                icon: const Icon(Icons.add_card),
                label: Text(context.tr('Order card')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingChecklist extends StatelessWidget {
  const _OnboardingChecklist({
    required this.tasks,
    required this.isBusinessAccount,
  });

  final List<OnboardingTask> tasks;
  final bool isBusinessAccount;

  @override
  Widget build(BuildContext context) {
    final completed = tasks.where((task) => task.isComplete).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Onboarding'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: tasks.isEmpty ? 0 : completed / tasks.length,
            ),
            const SizedBox(height: 12),
            if (tasks.isEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.task_alt),
                title: Text(context.tr('No onboarding steps pending')),
                subtitle: Text(
                    context.tr('Your next required actions will appear here.')),
              )
            else
              for (final task in tasks)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_taskIcon(task.status)),
                  title: Text(task.title),
                  subtitle: Text(
                    fallbackText(
                      task.description,
                      _taskStatusMessage(task.status),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go(_safeTaskRoute(task.route)),
                ),
            const Divider(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.verified_user_outlined),
                  label: const Text('KYC'),
                  onPressed: () => context.go('/kyc'),
                ),
                if (isBusinessAccount)
                  ActionChip(
                    avatar: const Icon(Icons.business),
                    label: Text(context.tr('KYB')),
                    onPressed: () => context.go('/business'),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.account_balance),
                  label: Text(context.tr('Banking')),
                  onPressed: () => context.go('/onboarding/banking'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.savings_outlined),
                  label: Text(context.tr('Budgets')),
                  onPressed: () => context.go('/onboarding/banking'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.people_outline),
                  label: Text(context.tr('Payees')),
                  onPressed: () => context.go('/money/payees'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.account_balance_wallet_outlined),
                  label: Text(context.tr('Wallets')),
                  onPressed: () => context.go('/wallets'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.qr_code_2),
                  label: Text(context.tr('Deposit')),
                  onPressed: () => context.go('/wallets/addresses'),
                ),
                ActionChip(
                  avatar: const Icon(Icons.query_stats),
                  label: Text(context.tr('Sync')),
                  onPressed: () => context.go('/transactions/status'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

IconData _taskIcon(OnboardingTaskStatus status) {
  return switch (status) {
    OnboardingTaskStatus.complete => Icons.check_circle,
    OnboardingTaskStatus.inProgress => Icons.timelapse,
    OnboardingTaskStatus.blocked => Icons.lock_outline,
    OnboardingTaskStatus.pending => Icons.radio_button_unchecked,
  };
}

String _taskStatusMessage(OnboardingTaskStatus status) {
  return switch (status) {
    OnboardingTaskStatus.complete => 'Completed',
    OnboardingTaskStatus.inProgress => 'In review or awaiting completion',
    OnboardingTaskStatus.blocked => 'Action required before this can continue',
    OnboardingTaskStatus.pending => 'Ready when you are',
  };
}

String _safeTaskRoute(String route) {
  final normalized = route.trim();
  if (normalized.startsWith('/money/payees')) {
    return '/money/payees';
  }
  if (normalized.startsWith('/money/pay')) {
    return '/money/pay';
  }
  if (normalized.startsWith('/money')) {
    return '/money/pay';
  }
  if (normalized.startsWith('/wallets/addresses')) {
    return '/wallets/addresses';
  }
  if (normalized.startsWith('/wallets/assets')) {
    return '/wallets/assets';
  }
  if (normalized.startsWith('/wallets/balances')) {
    return '/wallets/balances';
  }
  if (normalized.startsWith('/wallets')) {
    return '/wallets';
  }
  if (normalized.startsWith('/cards/order')) {
    return '/cards/order';
  }
  if (normalized.startsWith('/cards')) {
    return normalized;
  }

  const supportedRoutes = {
    '/home',
    '/accounts',
    '/activity',
    '/kyc',
    '/kyc/status',
    '/business',
    '/onboarding/banking',
    '/banking/services',
    '/tiers',
    '/payments',
    '/transactions/status',
    '/profile',
  };

  return supportedRoutes.contains(normalized) ? normalized : '/home';
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        TextButton(onPressed: onAction, child: Text(actionLabel)),
      ],
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(message),
      ),
    );
  }
}
