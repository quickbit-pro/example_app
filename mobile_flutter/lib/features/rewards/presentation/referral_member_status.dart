import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../platform/application/platform_providers.dart';
import '../../signup/presentation/referral_signup_outcome.dart';
import '../domain/referral_member_status.dart';

/// The incoming referral's accepted agreement is distinct from the current
/// offer the member shares with new friends. Never substitute today's terms.
class ReferralMemberStatusCard extends ConsumerWidget {
  const ReferralMemberStatusCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attribution = ref.watch(referralAttributionOutcomeProvider);
    final eligibility = ref.watch(referralGeoStatusProvider);
    final outcome = attribution.valueOrNull;
    final geo = eligibility.valueOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (outcome != null) ReferralSignupOutcomeView(outcome: outcome),
      if (attribution.hasError)
        Text(context.tr('Referral confirmation could not be loaded.')),
      if (eligibility.isLoading) const LinearProgressIndicator(),
      if (eligibility.hasError)
        TextButton(
            onPressed: () => ref.invalidate(referralGeoStatusProvider),
            child: Text(context.tr('Retry referral eligibility'))),
      if (geo != null && geo.attributed) ReferralAcceptedTermsCard(status: geo),
    ]);
  }
}

class ReferralAcceptedTermsCard extends StatelessWidget {
  const ReferralAcceptedTermsCard({required this.status, super.key});
  final ReferralGeoStatus status;
  @override
  Widget build(BuildContext context) => Card(
      margin: EdgeInsets.zero,
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(context.tr(status.label),
                key: const Key('referral_geo_status')),
            if (status.canPayout == false) ...[
              const SizedBox(height: 8),
              Text(context.tr('Referral payouts are not currently available.')),
            ],
            if (status.pendingExpiresAt != null)
              Text(context.tr('Verification evidence must arrive before {p0}', {
                'p0': '${MaterialLocalizations.of(context).formatMediumDate(status.pendingExpiresAt!.toLocal())} '
                    '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(status.pendingExpiresAt!.toLocal()))}'
              })),
            if (status.acceptedTerms != null)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(context.tr('Your accepted referral terms')),
                children: [
                  Text(context.tr('Version {p0} · language {p1}', {
                    'p0': status.acceptedVersion ?? '—',
                    'p1': status.acceptedLocale ?? '—'
                  })),
                  Directionality(
                      textDirection:
                          status.acceptedLocale?.split('-').first == 'ar'
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                      child: SelectableText(status.acceptedTerms!,
                          key: const Key('referral_accepted_terms'))),
                  if (status.acceptedAt != null)
                    Text(context.tr('Accepted on {p0}', {
                      'p0': MaterialLocalizations.of(context)
                          .formatMediumDate(status.acceptedAt!.toLocal())
                    })),
                ],
              ),
          ])));
}
