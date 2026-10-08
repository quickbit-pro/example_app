import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/l10n/app_localizations.dart';
import '../../rewards/domain/rewards_models.dart';

/// What a referral code means for the person entering it, and the one
/// acceptance the programme needs from them.
///
/// The welcome line only renders when the backend states an amount — the app
/// never asserts a figure of its own. The acceptance is the referred user's
/// consent that their inviter is credited for the sign-up; it is required
/// whenever a code is entered by hand or arrives on a link, and it is already
/// given when the code came from an email invitation, which the invitation
/// itself disclosed, so the tick is shown made and locked.
class ReferralAcceptanceSection extends StatelessWidget {
  const ReferralAcceptanceSection({
    required this.accepted,
    required this.onChanged,
    this.inviterDisplayName,
    this.welcomeAmount = 0,
    this.welcomeCurrency = 'USD',
    this.locked = false,
    this.enabled = true,
    super.key,
  });

  /// Whether the referred user has accepted the credit.
  final bool accepted;

  /// Called with the new value; never called while [locked].
  final ValueChanged<bool> onChanged;

  /// The inviter, when the code check or the invitation preview named one.
  final String? inviterDisplayName;

  /// The welcome reward at qualification; 0 hides the welcome line.
  final double welcomeAmount;
  final String welcomeCurrency;

  /// Pre-accepted and not editable (email invitations).
  final bool locked;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final isExample = context.isExampleTheme;
    final theme = Theme.of(context);
    final inviter = inviterDisplayName?.trim();
    final label = inviter == null || inviter.isEmpty
        ? context.tr(
            'I accept that the person who invited me is credited for my sign-up.')
        : context.tr(
            'I accept that {p0} is credited for my sign-up.', {'p0': inviter});
    final secondary = isExample
        ? ExampleInk.secondary(context)
        : theme.colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (welcomeAmount > 0) ...[
          Text(
            context.tr(
                '{p0} after you verify, order a card and make your first top-up.',
                {'p0': formatReferralAmount(welcomeCurrency, welcomeAmount)}),
            key: const Key('signup_referral_welcome'),
            style: isExample
                ? theme.textTheme.bodyMedium?.copyWith(
                    color: ExampleInk.primary(context),
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  )
                : theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
          ),
          SizedBox(height: isExample ? AppSpacing.xs : 8),
        ],
        _AcceptanceTick(
          checked: accepted,
          enabled: !locked && enabled,
          label: label,
          onChanged: onChanged,
        ),
        if (locked) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(
            context.tr('Confirmed by your email invitation.'),
            style: TextStyle(fontSize: 12, height: 1.4, color: secondary),
          ),
        ],
      ],
    );
  }
}

/// One target: the box and the sentence. Material draws a real checkbox; on
/// Example the box is painted and the panel owns the gesture, the same shape
/// the legal agreements on the review step use.
class _AcceptanceTick extends StatelessWidget {
  const _AcceptanceTick({
    required this.checked,
    required this.enabled,
    required this.label,
    required this.onChanged,
  });

  final bool checked;
  final bool enabled;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!context.isExampleTheme) {
      return CheckboxListTile(
        key: const Key('signup_referral_accept'),
        value: checked,
        onChanged: enabled ? (value) => onChanged(value ?? false) : null,
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(label, style: theme.textTheme.bodyMedium),
      );
    }
    final fill = ExampleInk.accent(context, ExampleColors.violet);
    final light = ExampleTheme.isLight(context);
    final radius = BorderRadius.circular(AppRadii.sm);
    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
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
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: enabled
                  ? ExampleInk.primary(context)
                  : ExampleInk.secondary(context),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      key: const Key('signup_referral_accept'),
      container: true,
      checked: checked,
      enabled: enabled,
      label: label,
      child: ExcludeSemantics(
        child: light
            ? Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: enabled ? () => onChanged(!checked) : null,
                  borderRadius: radius,
                  child: Ink(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: checked
                          ? ExampleColors.lightViolet.withValues(alpha: .06)
                          : ExampleColors.lightSurface,
                      borderRadius: radius,
                      border: Border.fromBorderSide(
                        checked
                            ? const BorderSide(
                                color: ExampleColors.lightViolet,
                                width: 1.5,
                              )
                            : ExampleBorders.controlSideOf(context),
                      ),
                    ),
                    child: content,
                  ),
                ),
              )
            : ExampleGlassPanel(
                radius: AppRadii.sm,
                padding: const EdgeInsets.all(AppSpacing.sm),
                borderAlpha: checked ? .34 : .16,
                onTap: enabled ? () => onChanged(!checked) : null,
                child: content,
              ),
      ),
    );
  }
}
