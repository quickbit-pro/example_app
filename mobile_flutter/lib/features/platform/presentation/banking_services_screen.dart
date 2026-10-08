import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import '../../../shared/widgets/safeguarding_statement.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../brands/example/example.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/models/platform_models.dart';
import '../../../core/widgets/app_states.dart';
import '../application/platform_providers.dart';
import 'platform_widgets.dart';

/// Banking services: the rails behind the account, said as money first.
///
/// A utility screen, so it gets consistency and no arrival moment — the same
/// header rhythm as the other five platform screens (app bar title, one lede
/// line, then sections). What it does not share is the "Actions" list group:
/// this screen has exactly one action, and a one-row group is a heavier
/// container than the thing inside it. The rate quote is therefore the page's
/// single decisive control, a [ExampleGlassButton] on the plain painted
/// scaffold, and it is the only filled object here.
///
/// The balances are the subject, so they are set as money rather than as
/// generic resource rows: currency avatar, code, provider line, and the
/// figure in [ExampleAmount]'s tabular numerals on the right, so two providers
/// line up down one column instead of hiding inside a subtitle sentence. When
/// a provider returns a balance this screen cannot read as a number, the
/// whole section falls back to the shared [ResourceList] rather than dropping
/// a value on the floor.
class BankingServicesScreen extends ConsumerWidget {
  const BankingServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PlatformActionListener(
      child: Scaffold(
        appBar: AppBar(title: Text(context.tr('Banking services'))),
        body: context.isExampleTheme ? const _ExampleBody() : const _LegacyBody(),
      ),
    );
  }
}

/// The reading column. A list of rows gains nothing from 1400 px of width, so
/// past this the block centres instead of stretching into dead space.
const double _bankingMaxContentWidth = 720;

/// The amount this screen quotes. Stated in the copy rather than hidden in
/// the call, because "create a quote" without a figure is a control that does
/// not say what it will do.
const Money _quoteAmount = Money(currency: 'EUR', minorUnits: 10000);

class _ExampleBody extends ConsumerWidget {
  const _ExampleBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(bankingBalancesProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        return ListView(
          padding: wide
              ? const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.xxl,
                )
              : platformExamplePadding,
          children: [
            Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: _bankingMaxContentWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PlatformLede(
                      text: context.tr(
                          'What your providers are holding for you, and the rate you can lock before moving any of it.'),
                    ),
                    platformSectionGap,
                    ExampleSectionTitle(title: context.tr('Provider balances')),
                    const SizedBox(height: AppSpacing.sm),
                    ExampleStateSwitch(
                      alignment: Alignment.topCenter,
                      child: balances.when(
                        data: (items) => items.isEmpty
                            ? ExampleEmptyState(
                                key: const ValueKey('balances-empty'),
                                compact: true,
                                icon: Icons.account_balance_wallet_outlined,
                                title: context.tr('No balances to show yet'),
                                body: context.tr(
                                    'Provider balances appear here once the banking rail finishes connecting your account. Check again in a moment.'),
                                actionLabel: context.tr('Check again'),
                                onAction: () =>
                                    ref.invalidate(bankingBalancesProvider),
                              )
                            : _BalanceGroup(
                                key: const ValueKey('balances-data'),
                                items: items,
                              ),
                        error: (error, stackTrace) => PlatformErrorState(
                          key: const ValueKey('balances-error'),
                          error: error,
                          onRetry: () =>
                              ref.invalidate(bankingBalancesProvider),
                        ),
                        loading: () => PlatformLoadingGroup(
                          key: const ValueKey('balances-loading'),
                          label: context.tr('Loading balances'),
                        ),
                      ),
                    ),
                    const SafeguardingStatementButton(),
                    platformSectionGap,
                    ExampleSectionTitle(title: context.tr('Rate quote')),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'A quote holds a EUR to USD rate for a short window, so '
                      'the figure you agree to is the figure that settles. '
                      'This one quotes '
                      '${_quoteAmount.formatted}.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.45,
                        color: ExampleInk.secondary(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    const _QuoteButton(),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The screen's one decisive control.
///
/// `ExampleGlassGround.surface`, not `atmosphere`: it sits on the plain
/// painted scaffold with nothing behind it worth sampling, so the material
/// goes opaque and keeps its silhouette instead of dissolving into paper.
/// Feedback lands on this button — the shared action controller is global, so
/// without the local pending flag every control in the platform set would
/// have spun at once.
class _QuoteButton extends ConsumerStatefulWidget {
  const _QuoteButton();

  @override
  ConsumerState<_QuoteButton> createState() => _QuoteButtonState();
}

class _QuoteButtonState extends ConsumerState<_QuoteButton> {
  bool _pending = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(platformActionControllerProvider, (previous, next) {
      if (!next.isLoading && _pending && mounted) {
        setState(() => _pending = false);
      }
    });
    final busy = ref.watch(platformActionControllerProvider).isLoading;

    return ExampleGlassButton(
      label: context.tr('Lock a EUR to USD rate'),
      icon: Icons.currency_exchange_rounded,
      semanticsLabel: context.tr(
          'Lock a EUR to USD rate for {p0}', {'p0': _quoteAmount.formatted}),
      loadingSemanticsLabel: 'Creating the quote',
      ground: ExampleGlassGround.surface,
      loading: _pending && busy,
      onPressed: busy
          ? null
          : () {
              setState(() => _pending = true);
              ref.read(platformActionControllerProvider.notifier).run(
                    (api) => api.createQuote(
                      fromCurrency: 'EUR',
                      toCurrency: 'USD',
                      amount: _quoteAmount,
                    ),
                  );
            },
    );
  }
}

/// The balances as money rows.
///
/// Every row that can be read as a figure is set in [ExampleAmount], which is
/// the same tabular numeral voice the dashboard and the card ledger use — the
/// reason two providers' balances line up at all. A payload this screen
/// cannot parse is not guessed at: if no row yields a number the section
/// hands the whole list back to the shared [ResourceList], which renders the
/// service's own strings.
class _BalanceGroup extends StatelessWidget {
  const _BalanceGroup({required this.items, super.key});

  final List<PlatformResource> items;

  @override
  Widget build(BuildContext context) {
    final balances = items.map(_balanceOf).toList();
    if (!balances.any((balance) => balance.amount != null)) {
      return ResourceList(
        resources: items,
        emptyTitle: context.tr('No balances to show yet'),
        emptyMessage: context.tr(
            'Provider balances appear here once the banking rail finishes connecting your account.'),
        icon: Icons.account_balance_wallet_outlined,
      );
    }

    return ExampleListGroup(
      children: [
        for (final balance in balances)
          ExampleRow(
            leading: balance.currency.isEmpty
                ? const ExampleIconTile(
                    icon: Icons.account_balance_wallet_outlined,
                    color: ExampleColors.iris,
                  )
                : ExampleCurrencyAvatar(code: balance.currency),
            title: balance.title,
            subtitle: balance.detail,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExampleAmount(
                  amount: balance.amount,
                  currency: balance.currency,
                  size: ExampleAmountSize.small,
                  code: ExampleAmountCode.auto,
                  animate: false,
                  textAlign: TextAlign.end,
                ),
                const SizedBox(width: AppSpacing.xs),
                ExampleRow.chevronOf(context),
              ],
            ),
            semanticsLabel: balance.semantics,
            onTap: () => showPlatformResourceDetails(context, balance.resource,
                showSafeguarding: true),
          ),
      ],
    );
  }
}

/// One provider balance, resolved from whatever shape the rail returned.
class _ProviderBalance {
  const _ProviderBalance({
    required this.resource,
    required this.title,
    required this.currency,
    required this.amount,
    required this.detail,
  });

  final PlatformResource resource;
  final String title;
  final String currency;

  /// Major units, or null when the payload carried no readable figure. The
  /// row still renders — [ExampleAmount] holds the line with an em dash — so a
  /// half-populated response never collapses the column.
  final double? amount;
  final String? detail;

  String get semantics {
    final where = detail == null ? title : '$title, $detail';
    return amount == null
        ? 'Open $where'
        : 'Open $where, ${Money.formatAmount(currency, amount!)}';
  }
}

const List<String> _balanceCurrencyKeys = [
  'currency',
  'Currency',
  'currencyCode',
  'CurrencyCode',
  'assetCode',
  'AssetCode',
  'asset',
  'Asset',
];

const List<String> _balanceAmountKeys = [
  'available',
  'Available',
  'availableBalance',
  'AvailableBalance',
  'balance',
  'Balance',
  'amount',
  'Amount',
];

const List<String> _balanceDetailKeys = [
  'provider',
  'Provider',
  'accountName',
  'AccountName',
  'type',
  'Type',
  'status',
  'Status',
  'state',
  'State',
];

_ProviderBalance _balanceOf(PlatformResource resource) {
  final metadata = resource.metadata;
  final currency = (_metadataText(metadata, _balanceCurrencyKeys) ??
          _currencyFromTitle(resource.title) ??
          '')
      .trim()
      .toUpperCase();
  final amount = _balanceAmount(metadata);
  final rawTitle = resource.title.trim();
  final title = currency.isNotEmpty
      ? currency
      : (rawTitle.isEmpty ? 'Balance' : friendlyStatus(rawTitle));
  final detail = _metadataText(metadata, _balanceDetailKeys);

  return _ProviderBalance(
    resource: resource,
    title: title,
    currency: currency,
    amount: amount,
    detail: detail == null ? null : friendlyStatus(detail),
  );
}

double? _balanceAmount(Map<String, dynamic> metadata) {
  for (final key in _balanceAmountKeys) {
    final value = metadata[key];
    if (value == null) continue;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString().trim().replaceAll(',', ''));
    if (parsed != null) return parsed;
  }
  return null;
}

String? _metadataText(Map<String, dynamic> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key]?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
  }
  return null;
}

/// A balance whose title is already an ISO code or an asset symbol — the
/// common shape when the rail returns one object per currency.
String? _currencyFromTitle(String title) {
  final value = title.trim().toUpperCase();
  return RegExp(r'^[A-Z]{3,5}$').hasMatch(value) ? value : null;
}

/// The pre-Example screen, kept byte-identical for every white-label tenant.
class _LegacyBody extends ConsumerWidget {
  const _LegacyBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(bankingBalancesProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ActionButton(
          icon: Icons.currency_exchange,
          label: context.tr('Create EUR to USD quote'),
          onPressed: (ref) =>
              ref.read(platformActionControllerProvider.notifier).run(
                    (api) => api.createQuote(
                      fromCurrency: 'EUR',
                      toCurrency: 'USD',
                      amount: const Money(currency: 'EUR', minorUnits: 10000),
                    ),
                  ),
        ),
        const SizedBox(height: 24),
        Text(context.tr('Provider balances'),
            style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        balances.when(
          data: (items) => ResourceList(
            resources: items,
            showSafeguarding: true,
            emptyTitle: context.tr('No balances yet'),
            emptyMessage:
                context.tr('Provider balances will appear after setup.'),
            icon: Icons.account_balance_wallet_outlined,
          ),
          error: (error, stackTrace) => ErrorState(
            error: error,
            onRetry: () => ref.invalidate(bankingBalancesProvider),
          ),
          loading: () => LoadingState(label: context.tr('Loading balances')),
        ),
        const SafeguardingStatementButton(),
      ],
    );
  }
}
