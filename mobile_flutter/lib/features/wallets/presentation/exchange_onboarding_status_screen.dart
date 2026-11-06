import 'package:flutter/material.dart';

import '../../../core/l10n/app_localizations.dart';
import 'exchange_onboarding_panel.dart';
import 'exchange_verification_panel.dart';

/// The onboarding entry point must show provider follow-up requests even when
/// the user already has Exchange balances and the trading screen is available.
class ExchangeOnboardingStatusScreen extends StatelessWidget {
  const ExchangeOnboardingStatusScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Exchange'))),
        body: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: const ExchangeOnboardingPanel(
                            legacy: ExchangeVerificationPanel()))))),
      );
}
