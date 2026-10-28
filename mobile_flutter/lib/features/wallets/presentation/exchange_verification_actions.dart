import 'package:flutter/material.dart';

class ExchangeVerificationActions extends StatelessWidget {
  const ExchangeVerificationActions({
    super.key,
    required this.showChooseLimits,
    required this.showActivate,
    required this.chooseLabel,
    this.onChooseLimits,
    this.onActivate,
  });

  final bool showChooseLimits;
  final bool showActivate;
  final String chooseLabel;
  final VoidCallback? onChooseLimits;
  final VoidCallback? onActivate;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: LayoutBuilder(builder: (context, constraints) {
          Widget fit(Widget button) => SizedBox(
                width: constraints.maxWidth < 480 ? double.infinity : null,
                child: button,
              );
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (showActivate)
                fit(FilledButton(
                  onPressed: onActivate,
                  child: const Text('Activate Exchange'),
                )),
              if (showChooseLimits)
                fit(showActivate
                    ? OutlinedButton(
                        onPressed: onChooseLimits, child: Text(chooseLabel))
                    : FilledButton(
                        onPressed: onChooseLimits, child: Text(chooseLabel))),
            ],
          );
        }),
      );
}
