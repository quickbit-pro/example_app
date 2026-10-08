import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../../core/models/banking_models.dart';
import '../../profile/presentation/security_sheets.dart'
    show showExampleSheet, ExampleSheetHeader;
import '../domain/referral_copy.dart';
import '../domain/rewards_models.dart';
import 'referral_widgets.dart';

/// The receipt for one reward: what it is, what it was worked out from, and
/// where it stands. The same content opens as a sheet on the phone and in
/// the drawer on the desktop workspace, so both say exactly the same thing.
///
/// Delivery is stated in the copy contract's words: "Added to USD balance"
/// only after confirmation, "Waiting for…" before it. The engine's own
/// explanation sentence, when it sends one, sits under that line rather than
/// replacing it, so the state is always in the app's vocabulary.
class ReferralRewardExplanationView extends StatelessWidget {
  const ReferralRewardExplanationView({
    required this.reward,
    required this.usesVouchers,
    this.onClose,
    super.key,
  });

  final ReferralReward reward;
  final bool usesVouchers;

  /// Renders a Close control when set (a sheet); a drawer supplies its own.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final explanation = reward.explanation;
    final delivery =
        referralRewardEvidenceDelivery(reward, usesVouchers: usesVouchers);
    final localizations = MaterialLocalizations.of(context);
    final when = reward.occurredAt ?? reward.createdAt;
    final paidAt = reward.paidAt;
    final reference = reward.creditId ?? reward.voucherId;
    final engineNote = explanation?.deliveryExplanation.trim() ?? '';
    final balance = reward.balance;
    String amount(double value, String? exact) =>
        '${exact ?? value} ${reward.currency}';
    final facts = <(String, String)>[
      if (balance?.cashKnown == true)
        (
          context.tr('Cash paid'),
          amount(balance!.cashPaid!, balance.cashPaidText)
        ),
      if (balance?.cashKnown != true)
        (context.tr('Cash paid'), context.tr('Not verified')),
      if (balance?.offsetSettled != null)
        (
          context.tr('Settled by offset'),
          amount(balance!.offsetSettled!, balance.offsetSettledText)
        ),
      if (balance?.reservedCash != null)
        (
          context.tr('Cash in flight'),
          amount(balance!.reservedCash!, balance.reservedCashText)
        ),
      if (balance?.remainingPayable != null)
        (
          context.tr('Remaining payable'),
          amount(balance!.remainingPayable!, balance.remainingPayableText)
        ),
      for (final reason in reward.holdReasons)
        (
          context.tr('Hold reason'),
          context.tr(switch (reason) {
            'PAYOUT_COOLING_PERIOD' => 'Payout waiting period',
            'FRAUD_REVIEW' => 'Referral review',
            'PROVIDER_CORRECTION_PENDING' => 'Awaiting a provider correction',
            _ => 'Manual review',
          })
        ),
      if (reward.releaseAt != null)
        (
          context.tr('Time hold ends'),
          localizations.formatMediumDate(reward.releaseAt!.toLocal())
        ),
      (context.tr('Event'), context.tr(reward.eventLabel)),
      if (reward.friendAlias != null && reward.friendAlias!.isNotEmpty)
        (context.tr('Friend'), reward.friendAlias!),
      if (when != null)
        (context.tr('Date'), localizations.formatMediumDate(when.toLocal())),
      if (explanation != null && explanation.basis.isNotEmpty)
        (
          context.tr('Calculation basis'),
          context.tr(explanation.basisLabel),
        ),
      if (explanation?.rate != null)
        (context.tr('Rate'), formatReferralPercent(explanation!.rate!)),
      if (explanation?.termsVersion != null)
        (context.tr('Terms version'), '${explanation!.termsVersion}'),
      if (explanation != null && explanation.rounding.isNotEmpty)
        (context.tr('Rounding'), context.tr(explanation.rounding)),
      if (paidAt != null &&
          (usesVouchers ||
              (balance?.cashKnown == true && (balance?.cashPaid ?? 0) > 0)))
        (
          usesVouchers ? context.tr('Claimed on') : context.tr('Credited on'),
          localizations.formatMediumDate(paidAt.toLocal()),
        ),
      if (reference != null && reference.isNotEmpty)
        (context.tr('Delivery reference'), reference),
    ];
    final capNote = explanation?.capNote?.trim();
    return Column(
      key: const Key('referral_reward_explanation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          Money.formatAmount(reward.currency, reward.amount),
          key: const Key('referral_reward_explanation_amount'),
          style: referralFigureStyle(context, size: 32),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          context.tr(reward.eventLabel),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: ExampleInk.primary(context),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        ReferralStatusLine(
          key: const Key('referral_reward_explanation_status'),
          delivery: delivery,
          currency: reward.currency,
          fontSize: 14,
        ),
        if (engineNote.isNotEmpty &&
            (usesVouchers ||
                reward.stage != ReferralRewardStage.paid ||
                reward.balance?.cashKnown == true) &&
            reward.holdReasons.isEmpty &&
            reward.status.toUpperCase() != 'HELD') ...[
          const SizedBox(height: AppSpacing.xxs),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 22),
            child: Text(
              context.tr(engineNote),
              style: referralBodyStyle(context),
            ),
          ),
        ],
        if (capNote != null && capNote.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            capNote,
            key: const Key('referral_reward_explanation_cap'),
            style: referralBodyStyle(context),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 1,
          child: ColoredBox(
            color: ExampleBorders.hairlineSideOf(context).color,
          ),
        ),
        for (final (label, value) in facts) _Fact(label: label, value: value),
        if (onClose != null) ...[
          const SizedBox(height: AppSpacing.md),
          ExampleGlassButton(
            label: context.tr('Close'),
            tone: ExampleGlassButtonTone.neutral,
            sheen: false,
            onPressed: onClose,
          ),
        ],
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: Text(label, style: referralBodyStyle(context)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 3,
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: ExampleInk.primary(context),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Opens the receipt as a drawer on the right, for the desktop workspace.
///
/// Not a `Scaffold.endDrawer`: that would put a drawer button in the page's
/// app bar and arm an edge-swipe gesture. A right-anchored route with the
/// same content, dismissed by the scrim, Escape or its Close control.
Future<void> showReferralRewardDrawer(
  BuildContext context,
  ReferralReward reward, {
  required bool usesVouchers,
}) {
  final duration = ExampleMotion.of(context, ExampleMotion.sheet);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: context.tr('Close'),
    barrierColor: Colors.black.withValues(alpha: .38),
    transitionDuration: duration,
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      final width = MediaQuery.sizeOf(dialogContext).width;
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: SizedBox(
          key: const Key('referral_reward_drawer'),
          width: width < 520 ? width : 440,
          height: double.infinity,
          child: Material(
            color: ExampleSurface.navigationOf(dialogContext),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.xs,
                      0,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ExampleSheetHeader(
                            title: dialogContext
                                .tr('How this reward was calculated'),
                          ),
                        ),
                        IconButton(
                          tooltip: dialogContext.tr('Close'),
                          onPressed: () => Navigator.pop(dialogContext),
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.sm,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      child: ReferralRewardExplanationView(
                        reward: reward,
                        usesVouchers: usesVouchers,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) =>
        SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: ExampleMotion.sheetCurve,
        reverseCurve: ExampleMotion.exit,
      )),
      child: child,
    ),
  );
}

/// Opens the receipt as a sheet. The Example sheet under the brand, the plain
/// Material one for a white-label tenant.
Future<void> showReferralRewardExplanation(
  BuildContext context,
  ReferralReward reward, {
  required bool usesVouchers,
}) {
  final title = context.tr('How this reward was calculated');
  if (!context.isExampleTheme) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            ReferralRewardExplanationView(
              reward: reward,
              usesVouchers: usesVouchers,
              onClose: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }
  return showExampleSheet<void>(
    context,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(title: title),
        const SizedBox(height: AppSpacing.md),
        ReferralRewardExplanationView(
          reward: reward,
          usesVouchers: usesVouchers,
          onClose: () => Navigator.pop(sheetContext),
        ),
      ],
    ),
  );
}
