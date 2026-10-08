import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../../brands/example/example.dart';
import '../../../../core/models/banking_models.dart';
import '../../../../core/formatters/transaction_display.dart';
import '../../../../core/widgets/app_states.dart';
import '../../../../shared/shared.dart';

/// A matte Example tile: level-1 surface, `AppRadii.lg` corners, one considered
/// shadow and no border.
///
/// The old tiles were a border and a fill; this is the opposite bet. Depth
/// comes from a single shadow that changes role with the theme — the violet
/// lift on the night ground, the night ambient on paper — so the tile reads as
/// an object resting on the page instead of a rectangle drawn on it. Presses
/// go through [ExamplePressable] at the 120 ms product default.
class _ExampleMatteTile extends StatelessWidget {
  const _ExampleMatteTile({
    required this.child,
    this.onTap,
    this.semanticsLabel,
    this.padding = const EdgeInsets.all(AppSpacing.md),
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final EdgeInsetsGeometry padding;

  static const BorderRadius _radius =
      BorderRadius.all(Radius.circular(AppRadii.lg));

  @override
  Widget build(BuildContext context) {
    Widget tile = DecoratedBox(
      decoration: BoxDecoration(
        color: ExampleSurface.of(context, 1),
        borderRadius: _radius,
        boxShadow: ExampleTheme.isLight(context)
            ? ExampleShadows.ambientLight
            : ExampleShadows.lift,
      ),
      child: Padding(padding: padding, child: child),
    );
    if (onTap != null) {
      tile = ExamplePressable(
        onTap: onTap,
        borderRadius: _radius,
        semanticsLabel: semanticsLabel,
        child: tile,
      );
    }
    // The tiles are dropped straight into a page `ListView`, so the rhythm
    // between them belongs to the tile, the way `Card`'s own margin used to
    // carry it.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: tile,
    );
  }
}

/// `Label` on the left, its value on the right.
///
/// Machine strings (IBAN, account number, SWIFT) are set in [ExampleMono] and
/// elide in the middle, so the prefix that names the scheme and the digits
/// people actually compare both survive at 375 px. No fixed label column: the
/// label is `Expanded` and the value `Flexible`, so a long label shortens
/// instead of pushing the value off the row.
class _ExampleDetailLine extends StatelessWidget {
  const _ExampleDetailLine({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A 40/60 split rather than a fixed label column: both halves are
          // flexible, so the value always lands on the right edge and neither
          // side can push the other out of the row.
          Expanded(
            flex: 4,
            child: Text(
              context.tr(label),
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
                    truncate: ExampleMonoTruncate.middle,
                    head: 8,
                    tail: 4,
                    size: 12.5,
                    textAlign: TextAlign.end,
                  )
                : Text(
                    value,
                    maxLines: 2,
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

/// One account: its currency badge, name, reference and balance.
///
/// On Example the tile is matte and its details open in place. Disclosure is a
/// state, not an arrival: the chevron swaps through [ExampleStateSwitch] at
/// `ExampleMotion.state` and the detail block simply appears — no animated
/// height, because the law forbids motion that moves layout. Outside the
/// Example theme the tile renders the exact `Card` + `ExpansionTile` it always
/// did, so a white-label build is unchanged.
class AccountTile extends StatefulWidget {
  const AccountTile({required this.account, super.key});

  final AccountBalance account;

  @override
  State<AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<AccountTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    if (!context.isExampleTheme) return _legacy(context, account);

    final primaryBank = account.linkedBankAccounts.firstOrNull;
    final reference = accountReference(account);
    final currency = accountCurrencyCode(account);
    final details = _accountDetailLines(account, primaryBank);
    final name = fallbackText(account.name, 'Account');

    return _ExampleMatteTile(
      onTap:
          details.isEmpty ? null : () => setState(() => _expanded = !_expanded),
      semanticsLabel: details.isEmpty
          ? null
          : _expanded
              ? context.tr('Hide details for {p0}', {'p0': name})
              : context.tr('Show details for {p0}', {'p0': name}),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 40,
                  child: Center(
                    child: ExampleCurrencyAvatar(code: currency, size: 34),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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
                      if (reference.isNotEmpty)
                        ExampleMono(
                          reference,
                          truncate: ExampleMonoTruncate.middle,
                          head: 8,
                          tail: 4,
                          size: 12,
                          color: ExampleInk.secondary(context),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                ExampleRowValue(
                  value: account.balance.formatted,
                  // The caption earns its width only when the two numbers
                  // differ; "Available" repeated under every equal balance is
                  // noise that costs the account name its characters.
                  caption: _availableCaption(account),
                ),
                if (details.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.xs),
                  ExampleStateSwitch(
                    child: Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      key: ValueKey<bool>(_expanded),
                      size: 20,
                      color: ExampleInk.tertiary(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_expanded && details.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: ExampleBorders.hairlineSideOf(context)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: details,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// The white-label composition, unchanged.
  Widget _legacy(BuildContext context, AccountBalance account) {
    final primaryBank = account.linkedBankAccounts.firstOrNull;
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.account_balance_wallet_outlined),
        title: Text(fallbackText(account.name, 'Account')),
        subtitle: Text(_accountSubtitle(account)),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(account.balance.formatted),
            Text(
              context.tr('Available {p0}', {'p0': account.available.formatted}),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (account.provider.trim().isNotEmpty)
            _DetailRow(label: context.tr('Provider'), value: account.provider),
          if (account.status.trim().isNotEmpty)
            _DetailRow(label: context.tr('Status'), value: account.status),
          if (account.id.trim().isNotEmpty)
            _DetailRow(label: context.tr('Account ID'), value: account.id),
          if (primaryBank != null) ...[
            if (primaryBank.currency.trim().isNotEmpty)
              _DetailRow(
                  label: context.tr('Currency'), value: primaryBank.currency),
            if (primaryBank.iban.trim().isNotEmpty)
              _DetailRow(label: 'IBAN', value: primaryBank.iban),
            if (primaryBank.accountNumber.trim().isNotEmpty)
              _DetailRow(
                label: context.tr('Account number'),
                value: primaryBank.accountNumber,
              ),
            if (primaryBank.swift.trim().isNotEmpty)
              _DetailRow(label: 'SWIFT/BIC', value: primaryBank.swift),
            if (primaryBank.routingNumber.trim().isNotEmpty)
              _DetailRow(
                label: primaryBank.routingType.trim().isEmpty
                    ? context.tr('Routing number')
                    : primaryBank.routingType,
                value: primaryBank.routingNumber,
              ),
            if (primaryBank.bankName.trim().isNotEmpty)
              _DetailRow(
                  label: context.tr('Bank'), value: primaryBank.bankName),
          ],
        ],
      ),
    );
  }
}

List<Widget> _accountDetailLines(
  AccountBalance account,
  BankAccountDetails? primaryBank,
) {
  return <Widget>[
    if (account.provider.trim().isNotEmpty)
      _ExampleDetailLine(label: 'Provider', value: account.provider.trim()),
    if (account.status.trim().isNotEmpty)
      _ExampleDetailLine(label: 'Status', value: friendlyStatus(account.status)),
    if (account.id.trim().isNotEmpty)
      _ExampleDetailLine(label: 'Account ID', value: account.id, mono: true),
    if (primaryBank != null) ...[
      if (primaryBank.currency.trim().isNotEmpty)
        _ExampleDetailLine(
          label: 'Currency',
          value: primaryBank.currency.trim().toUpperCase(),
        ),
      if (primaryBank.iban.trim().isNotEmpty)
        _ExampleDetailLine(
          label: 'IBAN',
          value: primaryBank.iban.trim(),
          mono: true,
        ),
      if (primaryBank.accountNumber.trim().isNotEmpty)
        _ExampleDetailLine(
          label: 'Account number',
          value: primaryBank.accountNumber.trim(),
          mono: true,
        ),
      if (primaryBank.swift.trim().isNotEmpty)
        _ExampleDetailLine(
          label: 'SWIFT/BIC',
          value: primaryBank.swift.trim(),
          mono: true,
        ),
      if (primaryBank.routingNumber.trim().isNotEmpty)
        _ExampleDetailLine(
          label: primaryBank.routingType.trim().isEmpty
              ? 'Routing number'
              : primaryBank.routingType.trim(),
          value: primaryBank.routingNumber.trim(),
          mono: true,
        ),
      if (primaryBank.bankName.trim().isNotEmpty)
        _ExampleDetailLine(label: 'Bank', value: primaryBank.bankName.trim()),
    ],
  ];
}

/// `Available €120.00`, but only when the available balance differs from the
/// booked one.
String? _availableCaption(AccountBalance account) {
  final balance = account.balance;
  final available = account.available;
  if (available.currency.trim().toUpperCase() ==
          balance.currency.trim().toUpperCase() &&
      available.minorUnits == balance.minorUnits) {
    return null;
  }
  return 'Available ${available.formatted}';
}

/// The reference people recognise an account by, most durable first.
String accountReference(AccountBalance account) {
  final primaryBank = account.linkedBankAccounts.firstOrNull;
  final candidates = <String>[
    account.iban,
    primaryBank?.iban ?? '',
    account.accountNumber,
    primaryBank?.accountNumber ?? '',
  ];
  for (final candidate in candidates) {
    if (candidate.trim().isNotEmpty) return candidate.trim();
  }
  return '';
}

/// The currency the badge shows: the balance's own code, then the first linked
/// bank account's, then the first supported one.
String accountCurrencyCode(AccountBalance account) {
  final candidates = <String>[
    account.balance.currency,
    account.available.currency,
    account.linkedBankAccounts.firstOrNull?.currency ?? '',
    account.supportedCurrencies.firstOrNull ?? '',
  ];
  for (final candidate in candidates) {
    if (candidate.trim().isNotEmpty) return candidate.trim().toUpperCase();
  }
  return '';
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              context.tr(label),
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}

/// One movement on the ledger.
///
/// On Example this is a [ExampleRow], not a card: 56 pt, the currency badge in
/// the leading slot, the status under the title, and the amount trailing in
/// tabular figures — credits in the success token, debits in the danger token,
/// both resolved through `ExampleInk.accent` inside [ExampleRowValue] so neither
/// falls below 4.5:1 on paper. A run of these is a ledger; a run of cards is
/// wallpaper.
class TransactionTile extends StatelessWidget {
  const TransactionTile({required this.transaction, this.onTap, super.key});

  final LedgerTransaction transaction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      final amount = transaction.displayAmount;
      final title = transactionDisplayTitle(transaction.title);
      final status = transactionDisplayStatus(transaction.subtitle);
      return ExampleRow(
        title: title,
        subtitle: status,
        leading: ExampleCurrencyAvatar(code: amount.currency, size: 30),
        trailing: ExampleRowValue(
          value: amount.formatted,
          color: amount.minorUnits >= 0
              ? ExampleColors.success
              : ExampleColors.danger,
        ),
        onTap: onTap,
        semanticsLabel:
            onTap == null ? null : '$title, ${amount.formatted}, $status',
      );
    }

    final color = transaction.amount.minorUnits >= 0
        ? ExamplePalette.of(context).design.color(
              Theme.of(context).brightness,
              'success',
              fallback: Colors.green.shade700,
            )
        : Theme.of(context).colorScheme.onSurface;

    return ListTile(
      onTap: onTap,
      leading: CurrencyLogo(
        symbol: transaction.amount.currency,
        fallbackIcon: _iconForType(transaction.type),
      ),
      title: Text(
        transactionDisplayTitle(transaction.title),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        transactionDisplayStatus(transaction.subtitle),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        transaction.amount.formatted,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: color),
      ),
    );
  }
}

/// One payment card: what it is called, what it is, and what it has spent.
class CardTile extends StatelessWidget {
  const CardTile({required this.card, this.onTap, super.key});

  final PaymentCard card;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      final label = fallbackText(card.label, 'Card');
      return _ExampleMatteTile(
        onTap: onTap,
        semanticsLabel: onTap == null
            ? null
            : context
                .tr('Open {p0}, {p1}', {'p0': label, 'p1': card.statusLabel}),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: Center(
                  child: ExampleIconTile(
                    icon: card.virtual
                        ? Icons.smartphone_rounded
                        : Icons.credit_card_rounded,
                    color: ExampleColors.violet,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: ExampleInk.primary(context),
                      ),
                    ),
                    Text(
                      _cardSubtitle(card),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ExampleRowValue(
                value: card.spendThisMonth.formatted,
                caption: card.statusLabel,
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.credit_card),
        title: Text(fallbackText(card.label, 'Card')),
        subtitle: Text(_cardSubtitle(card)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(context.tr(card.statusLabel)),
            Text(card.spendThisMonth.formatted),
          ],
        ),
      ),
    );
  }
}

String _cardSubtitle(PaymentCard card) {
  final parts = [
    if (card.network.trim().isNotEmpty) card.network.trim(),
    if (card.last4.trim().isNotEmpty) '•••• ${card.last4.trim()}',
    card.virtual ? 'Virtual' : 'Physical',
  ];

  return parts.join(' • ');
}

String _accountSubtitle(AccountBalance account) {
  final primaryBank = account.linkedBankAccounts.firstOrNull;
  final reference = primaryBank?.displayReference ??
      (account.iban.trim().isNotEmpty ? account.iban : account.accountNumber);
  final parts = [
    if (account.provider.trim().isNotEmpty) account.provider.trim(),
    if (reference.trim().isNotEmpty) reference.trim(),
  ];

  return fallbackText(parts.join(' • '), 'Account details unavailable');
}

IconData _iconForType(TransactionType type) {
  return switch (type) {
    TransactionType.card => Icons.credit_card,
    TransactionType.transfer => Icons.swap_horiz,
    TransactionType.topUp => Icons.add_card,
    TransactionType.payment => Icons.receipt_long,
    TransactionType.fee => Icons.percent,
  };
}
