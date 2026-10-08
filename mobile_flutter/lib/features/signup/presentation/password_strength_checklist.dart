import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';

/// The password rules enforced by the backend (`PasswordPolicy`).
class PasswordRule {
  const PasswordRule(this.label, this.test);

  final String label;
  final bool Function(String value) test;
}

const passwordRules = [
  PasswordRule('At least 12 characters', _atLeast12),
  PasswordRule('An uppercase letter (A–Z)', _hasUpper),
  PasswordRule('A lowercase letter (a–z)', _hasLower),
  PasswordRule('A number (0–9)', _hasDigit),
];

bool _atLeast12(String v) => v.length >= 12;
bool _hasUpper(String v) => v.contains(RegExp('[A-Z]'));
bool _hasLower(String v) => v.contains(RegExp('[a-z]'));
bool _hasDigit(String v) => v.contains(RegExp('[0-9]'));

bool passwordMeetsPolicy(String value) =>
    passwordRules.every((rule) => rule.test(value));

/// Live checklist under the password field: each rule flips to a green tick
/// as it is satisfied, and a strength bar summarises progress. Rules that are
/// still missing turn red once the user has tried to continue.
class PasswordStrengthChecklist extends StatelessWidget {
  const PasswordStrengthChecklist({
    required this.password,
    this.showErrors = false,
    this.dark = true,
    super.key,
  });

  final String password;
  final bool showErrors;

  /// Twilight styling. Kept for the white-label callers that pass it; on a
  /// Example screen the theme decides, so this flag is ignored there.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) {
      return _LegacyPasswordStrengthChecklist(
        password: password,
        showErrors: showErrors,
        dark: dark,
      );
    }
    final theme = Theme.of(context);
    final met = passwordRules.where((rule) => rule.test(password)).length;
    final total = passwordRules.length;
    final complete = met == total;
    // On Example the status hues are resolved for the active theme, so the
    // checklist reads the same on paper as it does on night and Twilight keeps
    // its exact constants; every other brand keeps the pair it shipped with.
    final example = context.isExampleTheme;
    // Geist and the theme's own type scale, on Example in either theme.
    final branded = example || dark;
    final okColor = example
        ? ExampleInk.accent(context, ExampleColors.success)
        : (dark
            ? context.brandDesign.color(theme.brightness, 'success',
                fallback: ExampleColors.success)
            : context.brandDesign.color(theme.brightness, 'success',
                fallback: Colors.green.shade700));
    // On EXAMPLE an unmet rule is the same red as the field error under the
    // box above it, and the halfway bar is the warning amber; the
    // white-label path keeps the colours it shipped with.
    final badColor = example
        ? ExampleInk.accent(context, ExampleColors.danger)
        : (dark
            ? context.brandDesign.color(theme.brightness, 'danger',
                fallback: ExampleColors.danger)
            : theme.colorScheme.error);
    final midColor = example
        ? ExampleInk.accent(context, ExampleColors.warning)
        : (dark
            ? context.brandDesign.color(theme.brightness, 'warning',
                fallback: ExampleColors.warning)
            : context.brandDesign
                .color(theme.brightness, 'warning', fallback: Colors.orange));
    final muted = example
        ? ExampleInk.tertiary(context)
        : (dark
            ? context.brandDesign.color(theme.brightness, 'textTertiary',
                fallback: ExampleColors.textTertiary)
            : theme.colorScheme.onSurfaceVariant);
    final barColor = complete
        ? okColor
        : met >= 3
            ? (example
                ? ExampleInk.accent(context, ExampleColors.iris)
                : (dark
                    ? context.brandDesign.color(theme.brightness, 'accent',
                        fallback: ExampleColors.iris)
                    : theme.colorScheme.primary))
            : met >= 2
                ? midColor
                : badColor;
    final strengthLabel = password.isEmpty
        ? 'Choose a strong password'
        : complete
            ? 'Strong password'
            : met >= 3
                ? 'Almost there'
                : 'Too weak';
    final labelStyle = branded
        ? theme.textTheme.labelMedium
        : const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700);

    return Semantics(
      container: true,
      liveRegion: true,
      label: context.tr('Password strength'),
      value: '$strengthLabel. $met of $total requirements met.',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.xs),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween<double>(
                      end: password.isEmpty ? 0 : met / total,
                    ),
                    duration: ExampleMotion.of(context, ExampleMotion.state),
                    curve: ExampleMotion.arrive,
                    builder: (context, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 5,
                      backgroundColor: muted.withValues(alpha: .25),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Bounded so a long label at a large text scale wraps inside
              // its own share of the row instead of pushing the bar out.
              Flexible(
                child: Text(
                  strengthLabel,
                  style: labelStyle?.copyWith(
                    color: password.isEmpty ? muted : barColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.xxs,
            children: [
              for (final rule in passwordRules)
                _RuleChip(
                  label: context.tr(rule.label),
                  met: rule.test(password),
                  error: showErrors && !rule.test(password),
                  okColor: okColor,
                  badColor: badColor,
                  muted: muted,
                  branded: branded,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({
    required this.label,
    required this.met,
    required this.error,
    required this.okColor,
    required this.badColor,
    required this.muted,
    required this.branded,
  });

  final String label;
  final bool met;
  final bool error;
  final Color okColor;
  final Color badColor;
  final Color muted;

  /// Example (either theme), or a white-label caller asking for the dark
  /// styling: read the type scale from the theme instead of the literals.
  final bool branded;

  @override
  Widget build(BuildContext context) {
    final color = met ? okColor : (error ? badColor : muted);
    final style = (branded
            ? Theme.of(context).textTheme.bodySmall ?? const TextStyle()
            : const TextStyle(fontSize: 12))
        .copyWith(
      color: color,
      fontWeight: met || error ? FontWeight.w600 : FontWeight.w400,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met
              ? Icons.check_circle_rounded
              : error
                  ? Icons.cancel_rounded
                  : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: AppSpacing.xxs),
        // A rule label is a whole phrase: at a 2.0 text scale two of the four
        // are wider than the 375 px column, so it must be allowed to wrap
        // rather than overflow the row it sits in.
        Flexible(child: Text(label, style: style)),
      ],
    );
  }
}

class _LegacyPasswordStrengthChecklist extends StatelessWidget {
  const _LegacyPasswordStrengthChecklist({
    required this.password,
    this.showErrors = false,
    this.dark = true,
  });

  final String password;
  final bool showErrors;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final met = passwordRules.where((rule) => rule.test(password)).length;
    final total = passwordRules.length;
    final complete = met == total;
    final okColor = dark
        ? context.brandDesign
            .color(theme.brightness, 'success', fallback: ExampleColors.success)
        : context.brandDesign.color(theme.brightness, 'success',
            fallback: Colors.green.shade700);
    final badColor = dark
        ? context.brandDesign
            .color(theme.brightness, 'warning', fallback: ExampleColors.warning)
        : theme.colorScheme.error;
    final muted = dark
        ? context.brandDesign.color(theme.brightness, 'textTertiary',
            fallback: ExampleColors.textTertiary)
        : theme.colorScheme.onSurfaceVariant;
    final barColor = complete
        ? okColor
        : met >= 3
            ? (dark
                ? context.brandDesign.color(theme.brightness, 'accent',
                    fallback: ExampleColors.iris)
                : theme.colorScheme.primary)
            : met >= 2
                ? context.brandDesign
                    .color(theme.brightness, 'warning', fallback: Colors.orange)
                : badColor;
    final strengthLabel = password.isEmpty
        ? 'Choose a strong password'
        : complete
            ? 'Strong password'
            : met >= 3
                ? 'Almost there'
                : 'Too weak';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: password.isEmpty ? 0 : met / total,
                  minHeight: 5,
                  backgroundColor: muted.withValues(alpha: .25),
                  valueColor: AlwaysStoppedAnimation<Color>(barColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              strengthLabel,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: password.isEmpty ? muted : barColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final rule in passwordRules)
              _LegacyRuleChip(
                label: context.tr(rule.label),
                met: rule.test(password),
                error: showErrors && !rule.test(password),
                okColor: okColor,
                badColor: badColor,
                muted: muted,
              ),
          ],
        ),
      ],
    );
  }
}

class _LegacyRuleChip extends StatelessWidget {
  const _LegacyRuleChip({
    required this.label,
    required this.met,
    required this.error,
    required this.okColor,
    required this.badColor,
    required this.muted,
  });

  final String label;
  final bool met;
  final bool error;
  final Color okColor;
  final Color badColor;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final color = met ? okColor : (error ? badColor : muted);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          met
              ? Icons.check_circle_rounded
              : error
                  ? Icons.cancel_rounded
                  : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: met || error ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}
