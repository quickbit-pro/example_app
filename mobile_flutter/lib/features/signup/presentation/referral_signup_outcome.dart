import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../domain/referral_quote.dart';

class ReferralSignupOutcomeView extends StatelessWidget {
  const ReferralSignupOutcomeView({required this.outcome, super.key});
  final ReferralSignupOutcome outcome;
  @override
  Widget build(BuildContext context) => Semantics(
      liveRegion: true,
      child: Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.tr(outcome.label),
                        key: const Key('referral_signup_outcome')),
                    if (outcome.correlationId case final reference?) ...[
                      const SizedBox(height: 8),
                      Text(context.tr('Referral reference')),
                      SelectableText(reference,
                          key: const Key('referral_signup_reference')),
                    ],
                  ]))));
}
