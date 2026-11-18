import 'package:flutter/material.dart';

import '../../core/l10n/app_localizations.dart';

/// The original provider wording remains accessible alongside its translation.
class LocalizedDisclosure extends StatelessWidget {
  const LocalizedDisclosure(this.original, {this.style, super.key});

  final String original;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final translated = context.tr(original);
    if (translated == original) return SelectableText(original, style: style);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(translated, style: style),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(context.tr('Original document (English)')),
          children: [SelectableText(original, style: style)],
        ),
      ],
    );
  }
}
