import 'package:flutter/material.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../domain/referral_quote.dart';

class ReferralQuoteTermsView extends StatelessWidget {
  const ReferralQuoteTermsView({required this.quote, super.key});
  final ReferralQuote quote;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(context
            .tr('Referral terms · version {p0}', {'p0': quote.termsVersion})),
        if (quote.termsText.isNotEmpty)
          Directionality(
              textDirection: quote.locale?.split('-').first == 'ar'
                  ? TextDirection.rtl
                  : TextDirection.ltr,
              child: SelectableText(quote.termsText,
                  key: const Key('signup_referral_quoted_terms'))),
        if (quote.eligibilityNotice case final notice?)
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(context.tr(notice))),
        for (final boost in quote.boosts)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(boost.name,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(context.tr('Boost period: {p0}–{p1}', {
                      'p0': boost.startsAt.toUtc().toIso8601String(),
                      'p1': boost.endsAt.toUtc().toIso8601String()
                    })),
                    if (boost.kind == 'MULTIPLIER')
                      Text(context
                          .tr('Multiplier: {p0}×', {'p0': boost.multiplier})),
                    if (boost.kind == 'MILESTONE')
                      Text(context
                          .tr('Milestone: {p0} qualified friends · {p1}', {
                        'p0': boost.qualifiedFriendCount,
                        'p1': Money.formatAmount(
                            boost.currency, boost.milestoneAmount!)
                      })),
                    Text(context.tr('Maximum additional reward: {p0}', {
                      'p0': Money.formatAmount(
                          boost.currency, boost.maximumIncrementalReward)
                    })),
                  ])),
      ]);
}
