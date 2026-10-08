import 'package:flutter/material.dart';

import '../../brands/example/example_colors.dart';
import '../../brands/example/example_ui.dart';
import '../../core/branding/app_design.dart';

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: isExample ? FontWeight.w600 : null,
                  letterSpacing: isExample ? -.15 : null,
                ),
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: isExample
                ? TextButton.styleFrom(
                    foregroundColor: context.brandDesign.isConfigured
                        ? ExamplePalette.of(context).accent
                        : ExampleColors.iris,
                    minimumSize: const Size(44, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  )
                : null,
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}
