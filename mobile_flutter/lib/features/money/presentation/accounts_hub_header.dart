import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import '../../../app/routes.dart';
import '../../../brands/example/example_colors.dart';
import '../../../brands/example/example_ui.dart';

enum AccountsHubSection { money, crypto, deposit, exchange }

/// The Money / Crypto / Exchange switch that sits above the accounts hub and
/// the wallets list.
///
/// Both themes are already first class here and nothing in this file names a
/// brightness: Example renders one [ExampleSegmentedControl], whose track, edge,
/// selected fill and both label inks resolve per brightness inside the
/// vocabulary, and every other brand renders the Material [SegmentedButton]
/// off its own `ColorScheme`. The conditional style properties preserve the
/// Material theme defaults outside the Example layout.
///
/// One constraint for callers: this widget reads its own width through a
/// [LayoutBuilder] to pick the desktop breakpoint, so it must never be placed
/// under an ancestor that measures it for intrinsic dimensions (an
/// `IntrinsicHeight`/`IntrinsicWidth`, or a `DataTable`/`Table` cell). Today's
/// three call sites put it in a `Column` or a `ListView`, which do not.
class AccountsHubHeader extends StatelessWidget {
  const AccountsHubHeader({
    required this.selected,
    required this.showCrypto,
    required this.showExchange,
    this.showMoney = true,
    super.key,
  });

  final AccountsHubSection selected;
  final bool showMoney;
  final bool showCrypto;
  final bool showExchange;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= (kIsWeb ? 500 : 760);
        if (isExample) {
          final control = ExampleSegmentedControl<AccountsHubSection>(
            height: desktop ? 40 : 44,
            segments: [
              if (showMoney)
                (value: AccountsHubSection.money, label: context.tr('Money')),
              if (showCrypto)
                (value: AccountsHubSection.crypto, label: context.tr('Crypto')),
              if (showExchange)
                (
                  value: AccountsHubSection.exchange,
                  label: context.tr('Exchange')
                ),
            ],
            selected: selected == AccountsHubSection.deposit ? null : selected,
            onChanged: (section) => switch (section) {
              AccountsHubSection.money => context.go(AppRoutes.money),
              AccountsHubSection.crypto => context.go(AppRoutes.walletAssets),
              AccountsHubSection.deposit =>
                context.go(AppRoutes.walletAddresses),
              AccountsHubSection.exchange =>
                context.go(AppRoutes.walletExchange),
            },
          );
          return Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: desktop ? 420 : double.infinity,
              child: control,
            ),
          );
        }
        final selector = SizedBox(
          width: desktop ? 520 : double.infinity,
          height: desktop ? 38 : null,
          child: SegmentedButton<AccountsHubSection>(
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(
                Size(44, desktop ? 38 : (isExample ? 44 : 52)),
              ),
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(
                  horizontal: isExample ? 8 : 12,
                  vertical: desktop ? 4 : (isExample ? 8 : 10),
                ),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (!states.contains(WidgetState.selected)) {
                  return isExample ? ExamplePalette.of(context).surface : null;
                }
                if (isExample) return ExamplePalette.of(context).fill;
                return NavigationBarTheme.of(context).indicatorColor ??
                    Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: .18);
              }),
              foregroundColor: WidgetStateProperty.resolveWith((states) {
                if (!isExample) return null;
                return states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.onPrimary
                    : ExamplePalette.of(context).textSecondary;
              }),
              side: WidgetStatePropertyAll(
                BorderSide(
                  color: isExample
                      ? (ExamplePalette.of(context).brightness ==
                              Brightness.light
                          ? ExamplePalette.of(context).borderSubtle
                          : ExamplePalette.of(context)
                              .borderSubtle
                              .withValues(alpha: .10))
                      : Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            showSelectedIcon: false,
            segments: [
              if (showMoney)
                ButtonSegment(
                  value: AccountsHubSection.money,
                  label: Text(context.tr('Money')),
                ),
              if (showCrypto) ...[
                ButtonSegment(
                  value: AccountsHubSection.crypto,
                  label: Text(context.tr('Crypto')),
                ),
              ],
              if (showExchange)
                ButtonSegment(
                  value: AccountsHubSection.exchange,
                  label: Text(context.tr('Exchange')),
                ),
            ],
            emptySelectionAllowed: true,
            selected: selected == AccountsHubSection.deposit ? {} : {selected},
            onSelectionChanged: (selection) {
              switch (selection.first) {
                case AccountsHubSection.money:
                  context.go(AppRoutes.money);
                  return;
                case AccountsHubSection.crypto:
                  context.go(AppRoutes.walletAssets);
                  return;
                case AccountsHubSection.deposit:
                  context.go(AppRoutes.walletAddresses);
                  return;
                case AccountsHubSection.exchange:
                  context.go(AppRoutes.walletExchange);
                  return;
              }
            },
          ),
        );
        return Align(alignment: Alignment.centerLeft, child: selector);
      },
    );
  }
}
