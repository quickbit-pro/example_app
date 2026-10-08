import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';

import '../../../brands/example/example_tokens.dart';
import '../data/display_currency_provider.dart';

/// The display-unit dropdown shared by Home and Activity: the selected ISO
/// code and a chevron, opening a menu of the codes worth switching to.
///
/// Both screens value their figures through [homeDisplayCurrencyProvider], so
/// one control drives both — a unit picked on Activity is the unit Home shows
/// the total balance in, and vice versa. Callers add the codes their own data
/// carries through [currencies]; the majors and the current selection are
/// always offered.
class DisplayCurrencySelector extends ConsumerWidget {
  const DisplayCurrencySelector({
    this.currencies = const [],
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
    super.key,
  });

  /// Extra codes to offer beside USD, EUR and GBP. Blank entries are dropped.
  final Iterable<String> currencies;

  /// Hit padding around the label. The Home masthead has room for a tall
  /// target; a compact header row passes something tighter.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(homeDisplayCurrencyProvider);
    final codes = <String>{
      'USD',
      'EUR',
      'GBP',
      selected,
      for (final code in currencies)
        if (code.trim().isNotEmpty) code.trim().toUpperCase(),
    }.toList()
      ..sort();
    return PopupMenuButton<String>(
      tooltip: context.tr('Balance currency'),
      initialValue: selected,
      onSelected: (currency) =>
          ref.read(homeDisplayCurrencyProvider.notifier).state = currency,
      itemBuilder: (_) => [
        for (final code in codes) PopupMenuItem(value: code, child: Text(code))
      ],
      child: Padding(
        padding: padding,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(selected,
              style: TextStyle(
                  color: ExampleInk.primary(context),
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more_rounded,
              size: 18, color: ExampleInk.secondary(context)),
        ]),
      ),
    );
  }
}
