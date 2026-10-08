import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../../shared/shared.dart';
import '../../../shared/widgets/app_progress_indicator.dart';
import '../domain/rewards_models.dart';
import 'referral_explanation.dart';

// ---------------------------------------------------------------------------
// Referral programme v2 sections. Each widget renders the house Example tree
// when the brand is active and the pre-Example Material tree otherwise, so a
// white-label tenant keeps its own materials. Every figure — amounts, rates,
// windows, minimums — comes from the API; nothing here asserts a number.
// ---------------------------------------------------------------------------

/// The offer, first: "$3 for them. $1 + 0.25% for you."
///
/// A referral page used to open on the customer's own balance; the customer
/// who has earned nothing yet was shown a zero. The offer is what they can do
/// something about, so it leads, in the words the programme actually pays.
class ReferralOfferHeadline extends StatelessWidget {
  const ReferralOfferHeadline({required this.summary, super.key});

  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    final offer = summary.offer;
    if (offer == null) return const SizedBox.shrink();
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final lines = <String>[];
    if (offer.hasWelcome) {
      lines.add(context.tr('{p0} for them.', {
        'p0': formatReferralAmount(offer.welcomeCurrency, offer.welcomeAmount),
      }));
    }
    final referrer = describeReferrerReward(offer);
    if (referrer != null) {
      lines.add(context.tr('{p0} for you.', {'p0': referrer}));
    }
    if (lines.isEmpty) return const SizedBox.shrink();

    final headline = Text(
      lines.join(' '),
      key: const Key('referral_offer_headline'),
      style: isExample
          ? theme.textTheme.headlineSmall?.copyWith(
              color: ExampleInk.primary(context),
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
              height: 1.2,
            )
          : theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
    );
    // Marketing copy supplements the mandatory conditions from the accepted
    // offer: the tenant's own words first, a blank line, then the generated
    // conditions. Either half may be absent, and neither leaves a stray
    // line break behind when it is.
    final detail = [
      if (summary.hasProgramDescription) summary.programDescription!.trim(),
      _offerDetail(context, offer).trim(),
    ].where((line) => line.isNotEmpty).join('\n\n');
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        headline,
        if (detail.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            detail,
            key: const Key('referral_offer_detail'),
            style: isExample
                ? TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: ExampleInk.secondary(context),
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ],
      ],
    );
    if (isExample) {
      return ExampleGlassPanel(
        radius: AppRadii.lg,
        borderAlpha: .30,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('THE OFFER'),
                style: ExampleTextStyles.label(context)),
            const SizedBox(height: AppSpacing.xs),
            body,
          ],
        ),
      );
    }
    return NeoSurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: body,
    );
  }

  /// How the friend qualifies and how long the top-up share runs, stated
  /// from the programme's flags rather than assumed.
  static String _offerDetail(BuildContext context, ReferralOffer offer) {
    final steps = <String>[
      if (offer.requiresKyc) context.tr('verifies their identity'),
      if (offer.requiresPaidCard) context.tr(offer.promoCodePolicyEnabled ? 'gets a paid or promo card' : 'gets a paid card'),
      if (offer.requiresTopup)
        offer.minimumTopup != null && offer.minimumTopup! > 0
            ? context
                .tr('makes a first external credited top-up of at least {p0}', {
                'p0': formatReferralAmount(
                    offer.welcomeCurrency, offer.minimumTopup!),
              })
            : context.tr('makes their first top-up'),
    ];
    final sentences = <String>[];
    if (offer.promoCodePolicyEnabled) {
      sentences.add(context.tr('The welcome reward cannot be combined with a promo code. Your referral bonus and top-up commission still apply.'));
    }
    if (steps.isNotEmpty) {
      sentences.add(
        context.tr(
            'Paid once your friend {p0}.', {'p0': _joinSteps(context, steps)}),
      );
    }
    if (offer.hasTopupReward) {
      final rate = offer.topupCalculationType == 'FIXED'
          ? formatReferralAmount(offer.welcomeCurrency, offer.topupRate)
          : formatReferralPercent(offer.topupRate);
      final window = offer.earningWindowDays > 0
          ? context.tr('for {p0} days', {'p0': offer.earningWindowDays})
          : context.tr('with no end date');
      sentences.add(
        offer.topupCalculationType == 'PERCENT_OF_MARGIN'
            ? context.tr(
                'Then {p0} of settled margin on eligible top-ups {p1}.',
                {'p0': rate, 'p1': window})
            : offer.topupCalculationType == 'PERCENT_OF_WL_FEE'
                ? context.tr('Then {p0} of the fee after cost on every top-up {p1}.',
                    {'p0': rate, 'p1': window})
                : offer.topupCalculationType == 'FIXED'
                    ? context.tr('Then {p0} on every top-up {p1}.',
                        {'p0': rate, 'p1': window})
                    : context.tr('Then {p0} of every top-up {p1}.',
                        {'p0': rate, 'p1': window}),
      );
    }
    if (offer.requiresTopup || offer.hasTopupReward) {
      sentences.add(context.tr(
          'Only external credited top-ups qualify. Reward funds and internal transfers are excluded.'));
    }
    if (offer.customerRecurringRate > 0) {
      sentences.add(context.tr(
          'Your friend also receives {p0} of settled margin.',
          {'p0': formatReferralPercent(offer.customerRecurringRate)}));
    }
    if (offer.maxEligibleVolumePerRelationship != null) {
      sentences.add(
          context.tr('Eligible top-up volume is capped at {p0} per friend.', {
        'p0': formatReferralAmount(
            offer.welcomeCurrency, offer.maxEligibleVolumePerRelationship!)
      }));
    }
    if (offer.maximumRecurringReward != null) {
      sentences.add(context.tr(
          'Total recurring rewards across all recipients are capped at {p0} per friend. Refunds do not reopen this limit.',
          {
            'p0': formatReferralAmount(
                offer.welcomeCurrency, offer.maximumRecurringReward!)
          }));
    }
    if (offer.hasTopupReward &&
        offer.maxEligibleVolumePerRelationship == null) {
      sentences.add(context.tr('Eligible top-up volume: no cap per friend.'));
    }
    if (offer.hasTopupReward && offer.maximumRecurringReward == null) {
      sentences.add(context.tr('Recurring rewards: no cap per friend.'));
    }
    sentences.add(context.tr(
        'Each referral keeps the tier, rate, caps and earning window accepted at sign-up. Later tier changes apply to new referrals and do not reset existing counters.'));
    return sentences.join(' ');
  }

  static String _joinSteps(BuildContext context, List<String> steps) {
    if (steps.length == 1) return steps.single;
    final head = steps.sublist(0, steps.length - 1).join(', ');
    return '$head${context.tr(' and ')}${steps.last}';
  }
}

/// Terms and privacy, before the first share.
///
/// The summary carries no code or link until the current terms version is
/// accepted, so this panel stands where the invite card will be. One tick,
/// one button; the text itself scrolls inside a bounded well so a long
/// document does not push the rest of the page off screen.
class ReferralTermsGate extends StatefulWidget {
  const ReferralTermsGate({
    required this.terms,
    required this.onAccept,
    this.busy = false,
    super.key,
  });

  final ReferralTerms terms;
  final ValueChanged<int> onAccept;
  final bool busy;

  @override
  State<ReferralTermsGate> createState() => _ReferralTermsGateState();
}

class _ReferralTermsGateState extends State<ReferralTermsGate> {
  bool _read = false;

  /// The well's own controller: the page around it is a `ListView`, and a
  /// scrollbar left to find the primary controller would find that one.
  final _wellController = ScrollController();

  static const double _wellHeight = 200;

  @override
  void dispose() {
    _wellController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final terms = widget.terms;
    final secondary = isExample
        ? ExampleInk.secondary(context)
        : theme.colorScheme.onSurfaceVariant;
    final bodyStyle = TextStyle(fontSize: 13, height: 1.5, color: secondary);
    final textWell = ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: _wellHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isExample
              ? (ExampleTheme.isLight(context)
                  ? ExampleColors.lightSurfaceSubtle
                  : ExampleColors.appBackground.withValues(alpha: .55))
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
        ),
        child: Scrollbar(
          controller: _wellController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _wellController,
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Text(
              terms.text ?? '',
              key: const Key('referral_terms_text'),
              style: bodyStyle,
            ),
          ),
        ),
      ),
    );
    final privacy = terms.privacyNotice;
    final checkboxLabel =
        context.tr('I have read and accept the referral terms.');
    final canAccept = _read && !widget.busy;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('Before you share'),
          style: isExample
              ? theme.textTheme.titleMedium?.copyWith(
                  color: ExampleInk.primary(context),
                  fontWeight: FontWeight.w700,
                )
              : theme.textTheme.titleLarge,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.tr(
              'Read the programme terms and accept them once. Your invite code and link unlock right after.'),
          style: bodyStyle,
        ),
        const SizedBox(height: AppSpacing.sm),
        textWell,
        if (privacy != null && privacy.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr('Privacy notice'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
              color: secondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(privacy, style: bodyStyle),
        ],
        const SizedBox(height: AppSpacing.sm),
        _TickRow(
          checked: _read,
          label: checkboxLabel,
          enabled: !widget.busy,
          onChanged: (value) => setState(() => _read = value),
          semanticsKey: const Key('referral_terms_checkbox'),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (isExample)
          ExampleGlassButton(
            key: const Key('referral_terms_accept'),
            label: context.tr('Accept and continue'),
            icon: Icons.check_rounded,
            sheen: false,
            loading: widget.busy,
            loadingSemanticsLabel: 'Accepting terms',
            onPressed: canAccept ? () => widget.onAccept(terms.version) : null,
          )
        else
          FilledButton.icon(
            key: const Key('referral_terms_accept'),
            onPressed: canAccept ? () => widget.onAccept(terms.version) : null,
            icon: widget.busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: AppProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(context.tr('Accept and continue')),
          ),
      ],
    );
    if (isExample) {
      return ExampleGlassPanel(
        key: const Key('referral_terms_gate'),
        radius: AppRadii.lg,
        borderAlpha: .30,
        padding: const EdgeInsets.all(AppSpacing.md),
        child: content,
      );
    }
    return NeoSurfaceCard(
      key: const Key('referral_terms_gate'),
      padding: const EdgeInsets.all(AppSpacing.md),
      child: content,
    );
  }
}

/// A tick and a sentence, as one target. Material draws its own checkbox; on
/// Example the box is painted and the row owns the gesture, the same pattern
/// the legal agreements use at signup.
class _TickRow extends StatelessWidget {
  const _TickRow({
    required this.checked,
    required this.label,
    required this.onChanged,
    this.enabled = true,
    this.semanticsKey,
  });

  final bool checked;
  final String label;
  final ValueChanged<bool> onChanged;
  final bool enabled;
  final Key? semanticsKey;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    if (!isExample) {
      return CheckboxListTile(
        key: semanticsKey,
        value: checked,
        onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: theme.textTheme.bodyMedium),
      );
    }
    final fill = ExampleInk.accent(context, ExampleColors.violet);
    return Semantics(
      key: semanticsKey,
      container: true,
      checked: checked,
      enabled: enabled,
      label: label,
      child: ExamplePressable(
        onTap: enabled ? () => onChanged(!checked) : null,
        borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Row(
            children: [
              ExcludeSemantics(
                child: AnimatedContainer(
                  duration: ExampleMotion.of(context, ExampleMotion.state),
                  curve: ExampleMotion.arrive,
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: checked ? fill : Colors.transparent,
                    borderRadius:
                        const BorderRadius.all(Radius.circular(AppRadii.xs)),
                    border: Border.all(
                      color: checked
                          ? fill
                          : ExampleTheme.pick(
                              context,
                              dark: ExampleColors.borderEmphasis,
                              light: ExampleColors.lightViolet,
                            ),
                    ),
                  ),
                  child: checked
                      ? const Icon(
                          Icons.check_rounded,
                          size: 15,
                          color: ExampleColors.pearl,
                        )
                      : null,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ExcludeSemantics(
                  child: Text(
                    label,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ExampleInk.primary(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The levels, only when there is a ladder to climb: a programme with one
/// visible level has no story to tell about the next one.
class ReferralLevelsCard extends StatelessWidget {
  const ReferralLevelsCard({required this.summary, super.key});

  final ReferralSummary summary;

  @override
  Widget build(BuildContext context) {
    if (!summary.showsLevels) return const SizedBox.shrink();
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final currency = summary.offer?.welcomeCurrency ?? summary.rewards.currency;
    final levels = [...summary.levels]
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
    final currentCode = summary.currentLevel?.code;
    final rows = [
      for (final level in levels)
        _LevelRow(
          level: level,
          current: level.code == currentCode,
          currency: currency,
        ),
    ];
    if (isExample) {
      return ExampleListGroup(
        key: const Key('referral_levels'),
        title: context.tr('Levels'),
        children: rows,
      );
    }
    return Column(
      key: const Key('referral_levels'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Levels'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        NeoGroupedCard(children: rows),
      ],
    );
  }
}

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.level,
    required this.current,
    required this.currency,
  });

  final ReferralLevel level;
  final bool current;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rate = describeReferrerReward(ReferralOffer(
      welcomeCurrency: currency,
      qualificationCalculationType: level.qualificationCalculationType,
      qualificationRate: level.qualificationRate,
      topupCalculationType: level.topupCalculationType,
      topupRate: level.topupRate,
    ));
    final capParts = <String>[];
    if (level.volumeCapSource != null) {
      capParts.add(context.tr('Eligible top-up volume: {p0}', {
        'p0': level.effectiveVolumeCap == null
            ? context.tr('No cap')
            : formatReferralAmount(currency, level.effectiveVolumeCap!)
      }));
      if (level.volumeCapSource == 'PROGRAM_DEFAULT') {
        capParts.add(context.tr('Volume cap inherited from program default'));
      }
    }
    if (level.recurringRewardCapSource != null) {
      capParts.add(context.tr('Recurring reward cap: {p0}', {
        'p0': level.effectiveRecurringRewardCap == null
            ? context.tr('No cap')
            : formatReferralAmount(currency, level.effectiveRecurringRewardCap!)
      }));
      if (level.recurringRewardCapSource == 'PROGRAM_DEFAULT') {
        capParts.add(context.tr('Reward cap inherited from program default'));
      }
    }
    final subtitle = [_subtitle(context, rate), ...capParts].join(' · ');
    if (context.isExampleTheme) {
      return ExampleRow(
        title: level.name,
        subtitle: subtitle,
        subtitleMaxLines: 6,
        trailing: current
            ? ExamplePill(
                label: context.tr('Current'),
                color: ExampleColors.iris,
              )
            : null,
      );
    }
    return ListTile(
      title: Text(level.name),
      subtitle: Text(subtitle),
      trailing: current
          ? StatusChip(
              label: context.tr('Current'),
              tone: FinanceStatusTone.info,
            )
          : null,
    );
  }

  /// What it takes to reach the level, after the rate it pays. A level may
  /// ask for qualified referrals, a combined top-up amount of those friends,
  /// both (and then both must be met), or nothing — the starting level.
  String _subtitle(BuildContext context, String? rate) {
    final qualified = level.minimumQualifiedReferrals;
    final volume = level.minimumTopupVolume;
    final money =
        volume == null ? null : formatReferralAmount(currency, volume);
    if (qualified != null && money != null) {
      return rate == null
          ? context.tr('From {p0} qualified referrals and {p1} in top-ups',
              {'p0': qualified, 'p1': money})
          : context.tr(
              '{p0} · from {p1} qualified referrals and {p2} in top-ups',
              {'p0': rate, 'p1': qualified, 'p2': money},
            );
    }
    if (qualified != null) {
      return rate == null
          ? context.tr('From {p0} qualified referrals', {'p0': qualified})
          : context.tr('{p0} · from {p1} qualified referrals',
              {'p0': rate, 'p1': qualified});
    }
    if (money != null) {
      return rate == null
          ? context.tr('From {p0} in top-ups', {'p0': money})
          : context
              .tr('{p0} · from {p1} in top-ups', {'p0': rate, 'p1': money});
    }
    return rate == null
        ? context.tr('Starting level')
        : context.tr('{p0} · starting level', {'p0': rate});
  }
}

/// Every friend invited, where they stand, and what they have earned the
/// inviter so far. Names are what the inviter typed into an email
/// invitation; everyone else is the stable pseudonym the API assigns.
class ReferralFriendsList extends StatelessWidget {
  const ReferralFriendsList({required this.friends, super.key});

  final List<ReferralFriend> friends;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    if (friends.isEmpty) {
      if (isExample) {
        return ExampleEmptyState(
          key: const Key('referral_friends_empty'),
          compact: true,
          icon: Icons.people_outline_rounded,
          title: context.tr('No friends yet'),
          body: context.tr(
              'Friends you invite appear here with their progress and what they have earned you.'),
        );
      }
      return NeoSurfaceCard(
        key: const Key('referral_friends_empty'),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('Your friends'), style: theme.textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(context.tr(
                'Friends you invite appear here with their progress and what they have earned you.')),
          ],
        ),
      );
    }
    final rows = [for (final friend in friends) _FriendRow(friend: friend)];
    if (isExample) {
      return ExampleListGroup(
        key: const Key('referral_friends'),
        title: context.tr('Your friends'),
        children: rows,
      );
    }
    return Column(
      key: const Key('referral_friends'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(context.tr('Your friends'), style: theme.textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        NeoGroupedCard(children: rows),
      ],
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.friend});

  final ReferralFriend friend;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final stage = context.tr(friend.stage.label);
    final since = friend.attributedAt == null
        ? null
        : MaterialLocalizations.of(context)
            .formatShortDate(friend.attributedAt!.toLocal());
    final subtitle =
        since == null ? stage : context.tr('Joined {p0}', {'p0': since});
    final earned = Money.formatAmount(friend.currency, friend.earnedAmount);
    final chip = ReferralStageChip(
      label: stage,
      tone: _friendTone(friend.stage),
    );
    final trailing = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          earned,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: isExample
                ? ExampleInk.primary(context)
                : theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 4),
        chip,
      ],
    );
    if (isExample) {
      return ExampleRow(
        title: friend.displayName,
        subtitle: subtitle,
        minHeight: 64,
        leading: ExampleIconTile(
          icon: friend.recipientName == null
              ? Icons.person_outline_rounded
              : Icons.mark_email_read_outlined,
          color: ExampleColors.iris,
        ),
        trailing: trailing,
        semanticsLabel: '${friend.displayName}, $stage, $earned',
      );
    }
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: .13),
        child: Icon(
          friend.recipientName == null
              ? Icons.person_outline_rounded
              : Icons.mark_email_read_outlined,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(friend.displayName),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }

  static FinanceStatusTone _friendTone(ReferralFriendStage stage) {
    switch (stage) {
      case ReferralFriendStage.qualified:
        return FinanceStatusTone.success;
      case ReferralFriendStage.windowEnded:
        return FinanceStatusTone.neutral;
      case ReferralFriendStage.invited:
        return FinanceStatusTone.info;
      case ReferralFriendStage.verifying:
      case ReferralFriendStage.cardIssued:
      case ReferralFriendStage.unknown:
        return FinanceStatusTone.warning;
    }
  }
}

/// A stage as a chip, in the house token for the brand and the finance tone
/// for a tenant.
class ReferralStageChip extends StatelessWidget {
  const ReferralStageChip({
    required this.label,
    this.tone = FinanceStatusTone.neutral,
    super.key,
  });

  final String label;
  final FinanceStatusTone tone;

  @override
  Widget build(BuildContext context) {
    if (context.isExampleTheme) {
      return ExamplePill(label: label, color: _exampleColor(tone));
    }
    return StatusChip(label: label, tone: tone);
  }

  static Color _exampleColor(FinanceStatusTone tone) {
    switch (tone) {
      case FinanceStatusTone.success:
        return ExampleColors.success;
      case FinanceStatusTone.warning:
        return ExampleColors.warning;
      case FinanceStatusTone.danger:
        return ExampleColors.warning;
      case FinanceStatusTone.info:
      case FinanceStatusTone.neutral:
        return ExampleColors.iris;
    }
  }
}

/// The reward ledger by stage, under the one sentence that explains how the
/// money arrives. Wallet-credit programmes state the minimum and how much has
/// accumulated towards it; voucher programmes point at the voucher list.
class ReferralRewardsLedger extends StatelessWidget {
  const ReferralRewardsLedger({
    required this.summary,
    required this.rewards,
    super.key,
  });

  final ReferralSummary summary;
  final List<ReferralReward> rewards;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final totals = summary.rewards;
    final currency = totals.currency;
    final groups = groupReferralRewards(rewards);
    final secondary = isExample
        ? ExampleInk.secondary(context)
        : theme.colorScheme.onSurfaceVariant;
    final bodyStyle = TextStyle(fontSize: 13, height: 1.45, color: secondary);

    final delivery = <Widget>[];
    if (summary.creditsWallet) {
      delivery.add(Text(
        context.tr(
            'Rewards are added to your {p0} balance automatically once they reach {p1}.',
            {
              'p0': currency,
              'p1': formatReferralAmount(currency, summary.minimumCreditAmount),
            }),
        key: const Key('referral_minimum_credit'),
        style: bodyStyle,
      ));
      if (summary.minimumCreditAmount > 0 &&
          summary.accumulatedTowardsCredit > 0) {
        final fraction =
            (summary.accumulatedTowardsCredit / summary.minimumCreditAmount)
                .clamp(0.0, 1.0);
        delivery.add(const SizedBox(height: AppSpacing.xs));
        delivery.add(
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Accumulated so far'),
                  style: bodyStyle,
                ),
              ),
              Text(
                Money.formatAmount(currency, summary.accumulatedTowardsCredit),
                key: const Key('referral_accumulated'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: isExample
                      ? ExampleInk.primary(context)
                      : theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
        );
        delivery.add(const SizedBox(height: 6));
        delivery.add(
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction.toDouble(),
              minHeight: 6,
              backgroundColor: isExample
                  ? (ExampleTheme.isLight(context)
                      ? ExampleColors.lightSurfaceHigh
                      : ExampleColors.pearl.withValues(alpha: .10))
                  : null,
              color: isExample
                  ? ExampleInk.accent(context, ExampleColors.iris)
                  : null,
            ),
          ),
        );
      }
    } else {
      delivery.add(Text(
        context.tr('Rewards are issued as vouchers you redeem from this page.'),
        key: const Key('referral_voucher_delivery'),
        style: bodyStyle,
      ));
    }
    if (totals.failed > 0) {
      delivery.add(const SizedBox(height: AppSpacing.xs));
      delivery.add(Text(
        context.tr(
            '{p0} could not be credited. Support has been notified and will resolve it.',
            {'p0': Money.formatAmount(currency, totals.failed)}),
        style: bodyStyle.copyWith(
          color: isExample
              ? ExampleInk.accent(context, ExampleColors.warning)
              : theme.colorScheme.error,
        ),
      ));
    }

    final sections = <Widget>[];
    for (final stage in referralLedgerStages) {
      final rows = groups[stage] ?? const <ReferralReward>[];
      final total = totals.forStage(stage);
      if (rows.isEmpty && total <= 0) continue;
      sections.add(_LedgerGroup(
        stage: stage,
        total: total,
        currency: currency,
        rows: rows,
      ));
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: delivery,
    );

    if (isExample) {
      return Column(
        key: const Key('referral_rewards'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExampleSectionTitle(title: context.tr('Your rewards')),
          const SizedBox(height: AppSpacing.sm),
          ExampleGlassPanel(
            radius: AppRadii.lg,
            padding: const EdgeInsets.all(AppSpacing.md),
            child: header,
          ),
          if (sections.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            ExampleEmptyState(
              key: const Key('referral_rewards_empty'),
              compact: true,
              icon: Icons.savings_outlined,
              title: context.tr('No rewards yet'),
              body: context.tr(
                  'Rewards appear here as your friends qualify and top up.'),
            ),
          ] else
            for (final section in sections) ...[
              const SizedBox(height: AppSpacing.sm),
              section,
            ],
        ],
      );
    }
    return Column(
      key: const Key('referral_rewards'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeoSurfaceCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.tr('Your rewards'),
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 6),
              header,
              if (sections.isEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  context.tr(
                      'Rewards appear here as your friends qualify and top up.'),
                  key: const Key('referral_rewards_empty'),
                ),
              ],
            ],
          ),
        ),
        for (final section in sections) ...[
          const SizedBox(height: AppSpacing.sm),
          section,
        ],
      ],
    );
  }
}

class _LedgerGroup extends StatelessWidget {
  const _LedgerGroup({
    required this.stage,
    required this.total,
    required this.currency,
    required this.rows,
  });

  final ReferralRewardStage stage;
  final double total;
  final String currency;
  final List<ReferralReward> rows;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final title = context.tr(stage.label);
    final amount = Money.formatAmount(currency, total);
    final children = [
      for (final reward in rows) _RewardRow(reward: reward),
    ];
    if (isExample) {
      return ExampleListGroup(
        key: Key('referral_rewards_${stage.name}'),
        title: '$title · $amount',
        children: children.isEmpty
            ? [
                ExampleRow(
                  title: context.tr('Total'),
                  trailing: Text(
                    amount,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: ExampleInk.primary(context),
                    ),
                  ),
                ),
              ]
            : children,
      );
    }
    return Column(
      key: Key('referral_rewards_${stage.name}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title, style: theme.textTheme.titleMedium),
            ),
            Text(
              amount,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        if (children.isNotEmpty) NeoGroupedCard(children: children),
      ],
    );
  }
}

/// The receipt for a ledger row, in the brand's sheet or the Material one.
void _showRewardExplanation(BuildContext context, ReferralReward reward) {
  showReferralRewardExplanation(
    context,
    reward,
    usesVouchers: referralVoucherDeliveryModes.contains(reward.deliveryMode),
  );
}

class _RewardRow extends StatelessWidget {
  const _RewardRow({required this.reward});

  final ReferralReward reward;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final when = reward.occurredAt ?? reward.createdAt;
    final date = when == null
        ? null
        : MaterialLocalizations.of(context).formatShortDate(when.toLocal());
    final parts = <String>[
      if (reward.friendAlias != null && reward.friendAlias!.isNotEmpty)
        reward.friendAlias!,
      if (date != null) date,
    ];
    final title = context.tr(reward.eventLabel);
    final subtitle = parts.isEmpty ? null : parts.join(' · ');
    final amount = Money.formatAmount(reward.currency, reward.amount);
    final amountStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      fontFeatures: const [FontFeature.tabularFigures()],
      color:
          isExample ? ExampleInk.primary(context) : theme.colorScheme.onSurface,
    );
    if (isExample) {
      return ExampleRow(
        title: title,
        subtitle: subtitle,
        trailing: Text(amount, style: amountStyle),
        onTap: () => _showRewardExplanation(context, reward),
        semanticsLabel: '$title, ${subtitle ?? ''}, $amount',
      );
    }
    return ListTile(
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: Text(amount, style: amountStyle),
      onTap: () => _showRewardExplanation(context, reward),
    );
  }
}
