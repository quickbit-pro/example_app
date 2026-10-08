import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/models/banking_models.dart';
import '../../banking/application/banking_providers.dart';
import '../domain/transaction_activity_type.dart';

/// Narrows an activity type to an actual card, account, or crypto asset.
class ActivityScopeDropdown extends ConsumerWidget {
  const ActivityScopeDropdown({
    required this.type,
    required this.transactions,
    required this.selectedId,
    required this.onChanged,
    super.key,
  });

  final TransactionActivityType type;
  final List<LedgerTransaction> transactions;
  final String selectedId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (type) {
      case TransactionActivityType.card:
        return ref.watch(cardsProvider).when(
              data: (cards) {
                final options = <String, String>{};
                for (final card in cards) {
                  final id = card.id.trim();
                  if (id.isEmpty) continue;
                  final last4 = card.last4.trim();
                  options.putIfAbsent(
                    id,
                    () => last4.isEmpty
                        ? card.displayLabel
                        : '${card.displayLabel} · •••• $last4',
                  );
                }
                return _dropdown(context, 'All cards', 'Card', options);
              },
              loading: () => _status(context, 'Loading cards…'),
              error: (_, __) => _status(
                context,
                'Could not load cards',
                onRetry: () => ref.invalidate(cardsProvider),
              ),
            );
      case TransactionActivityType.account:
        return ref.watch(accountsProvider).when(
              data: (accounts) {
                final options = <String, String>{};
                for (final account in accounts) {
                  final id = account.id.trim();
                  if (id.isEmpty) continue;
                  final name = account.name.trim();
                  final currency = account.balance.currency.trim();
                  options.putIfAbsent(
                    id,
                    () => [
                      name.isEmpty ? 'Account' : name,
                      if (currency.isNotEmpty) currency,
                    ].join(' · '),
                  );
                }
                return _dropdown(context, context.tr('All accounts'),
                    context.tr('Account'), options);
              },
              loading: () => _status(context, 'Loading accounts…'),
              error: (_, __) => _status(
                context,
                'Could not load accounts',
                onRetry: () => ref.invalidate(accountsProvider),
              ),
            );
      case TransactionActivityType.crypto:
        final assets = transactions.expand(transactionCryptoAssets).toSet()
          ..removeWhere((asset) => asset.trim().isEmpty);
        final sortedAssets = assets.toList()..sort();
        return _dropdown(
          context,
          'All crypto',
          'Crypto asset',
          {for (final asset in sortedAssets) asset: asset},
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _dropdown(
    BuildContext context,
    String allLabel,
    String scopeLabel,
    Map<String, String> options,
  ) {
    final isExample = context.isExampleTheme;
    final labels = {'': allLabel, ...options};
    final selectionUnavailable =
        selectedId.isNotEmpty && !labels.containsKey(selectedId);
    if (selectionUnavailable) {
      labels[selectedId] = type == TransactionActivityType.crypto
          ? '$selectedId (unavailable)'
          : 'Selected ${scopeLabel.toLowerCase()} unavailable';
    }
    final color = isExample
        ? ExampleInk.primary(context)
        : Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: context
          .tr('Filter activity by {p0}', {'p0': scopeLabel.toLowerCase()}),
      child: InputDecorator(
        decoration: _decoration(context),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const ValueKey('activity-scope-dropdown'),
            value: selectedId,
            isExpanded: true,
            isDense: true,
            dropdownColor: isExample ? ExampleSurface.of(context, 2) : null,
            borderRadius: BorderRadius.circular(16),
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: isExample ? ExampleInk.secondary(context) : null,
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
            items: [
              for (final option in labels.entries)
                DropdownMenuItem<String>(
                  value: option.key,
                  enabled: !selectionUnavailable || option.key != selectedId,
                  child: Text(
                    option.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ),
    );
  }

  Widget _status(
    BuildContext context,
    String message, {
    VoidCallback? onRetry,
  }) {
    final isExample = context.isExampleTheme;
    return Semantics(
      liveRegion: true,
      child: InputDecorator(
        decoration: _decoration(context).copyWith(
          contentPadding: const EdgeInsets.only(left: 14, right: 4),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              if (onRetry == null) ...[
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isExample ? ExampleInk.secondary(context) : null,
                      ),
                ),
              ),
              if (onRetry != null)
                IconButton(
                  tooltip: context.tr('Retry loading {p0}s', {'p0': type.name}),
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(BuildContext context) {
    final isExample = context.isExampleTheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: isExample
          ? ExampleBorders.controlSideOf(context)
          : BorderSide(color: Theme.of(context).colorScheme.outline),
    );
    return InputDecoration(
      constraints: const BoxConstraints(minHeight: 48),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      isDense: true,
      filled: true,
      fillColor: isExample
          ? ExampleSurface.of(context, 2)
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(
          color: isExample
              ? ExampleInk.selection(context)
              : Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
    );
  }
}
