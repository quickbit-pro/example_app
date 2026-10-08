import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../brands/example/example_glass_button.dart';
import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/api/dio_provider.dart';
import '../../../shared/shared.dart';
import '../../platform/application/platform_providers.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const routePath = '/onboarding';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);
    final showBankingStep =
        ref.watch(mobileTenantConfigProvider).valueOrNull?.equalsMoneyEnabled ??
            true;
    final theme = Theme.of(context);
    // One scope for the screen. The hero headline and the primary CTA are its
    // only hosts and they sit on opposite sides of the Scaffold, so the scope
    // has to sit above it. A white-label tenant starts no ticker at all.
    final example = context.isExampleTheme;

    final scaffold = Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 780;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 40,
                  maxWidth: 1120,
                ),
                child: Center(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(
                              child: _OnboardingHero(
                                appName: config.branding.appName,
                                showGlobalAccounts: showBankingStep,
                                wide: true,
                              ),
                            ),
                            const SizedBox(width: 28),
                            Expanded(
                              child: _OnboardingSteps(
                                appName: config.branding.appName,
                                showBankingStep: showBankingStep,
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _OnboardingHero(
                              appName: config.branding.appName,
                              showGlobalAccounts: showBankingStep,
                            ),
                            const SizedBox(height: 20),
                            _OnboardingSteps(
                              appName: config.branding.appName,
                              showBankingStep: showBankingStep,
                            ),
                          ],
                        ),
                ),
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go('/login'),
                child: Text(context.tr('Sign in')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              // The decisive action of the whole first-run screen, in the
              // glass material. Its sibling is an OutlinedButton whose theme
              // minimum is 54, which is also this component's default, so the
              // pair sits on one baseline without either being pinned. Plain
              // ground: a bottom bar is painted, and there is nothing behind
              // it worth bending.
              child: example
                  ? ExampleGlassButton(
                      label: context.tr('Get started'),
                      trailing: const Icon(Icons.arrow_forward, size: 19),
                      sheen: true,
                      radius: context.brandShape.radius(AppRadii.md),
                      onPressed: () => context.go('/signup'),
                    )
                  : FilledButton.icon(
                      onPressed: () => context.go('/signup'),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(context.tr('Get started')),
                    ),
            ),
          ],
        ),
      ),
      backgroundColor: theme.scaffoldBackgroundColor,
    );

    // A shell above may already run a scope; a second one would mean two
    // tickers and two unrelated rhythms, so ask existsAbove before adding one.
    return example && !ExampleSheenScope.existsAbove(context)
        ? ExampleSheenScope(child: scaffold)
        : scaffold;
  }
}

/// [ExampleSheen] for Example, the child untouched for every other brand.
class _Sheen extends StatelessWidget {
  const _Sheen({
    required this.on,
    required this.child,
    this.text = false,
  });

  final bool on;
  final Widget child;
  final bool text;

  @override
  Widget build(BuildContext context) {
    if (!on) return child;
    if (text) {
      return ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: child,
      );
    }
    return ExampleSheen(
      intensity: ExampleSheenIntensity.soft,
      child: child,
    );
  }
}

class _OnboardingHero extends StatelessWidget {
  const _OnboardingHero({
    required this.appName,
    this.showGlobalAccounts = true,
    this.wide = false,
  });

  /// True in the two-column layout, where the hero claim takes the desktop
  /// display tier. Defaults false so the single-column path is unchanged.
  final bool wide;

  final bool showGlobalAccounts;

  final String appName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = context.isExampleTheme;

    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isExample
              ? [
                  ExamplePalette.of(context).surface,
                  context.brandDesign.color(
                      Theme.of(context).brightness, 'surfaceHigh',
                      fallback: ExampleColors.indigo)
                ]
              : [
                  theme.colorScheme.primary,
                  theme.colorScheme.primary.withValues(alpha: .72),
                ],
        ),
        borderRadius: BorderRadius.circular(
          context.brandShape.radius(AppRadii.xl),
        ),
        border: isExample
            ? Border.all(
                color: context.brandDesign
                    .color(Theme.of(context).brightness, 'accent',
                        fallback: ExampleColors.lavender)
                    .withValues(alpha: .18),
              )
            : null,
        // The hero is artwork: it stays a dark object in both themes (law:
        // card artwork does not turn to paper). On daylight it therefore needs
        // to be *seated* rather than glowed — a violet .12 bloom is invisible
        // on F8F5FC — so the ambient night shadow carries it instead.
        boxShadow: !isExample
            ? null
            : ExampleTheme.isLight(context)
                ? ExampleShadows.ambientOf(context)
                : [
                    BoxShadow(
                      color: context.brandDesign
                          .color(Theme.of(context).brightness, 'fill',
                              fallback: ExampleColors.violet)
                          .withValues(alpha: .12),
                      blurRadius: 32,
                      offset: const Offset(0, 16),
                    ),
                  ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (isExample)
            const ExampleLockup(height: 44)
          else
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(
                      context.brandShape.radius(AppRadii.md),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: BrandMark(appName: appName, size: 42),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The screen's single shining headline. White glyphs on the
              // dark artwork read the pearl band identically in both themes.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: _Sheen(
                  on: isExample,
                  text: true,
                  // The first sentence a new person reads, and the same claim
                  // the sign-in hero makes — so it is set in the same desktop
                  // display tier rather than two registers for one line. It
                  // was 30 px in a 530 px column, under every competitor on
                  // the board; 64 px wraps to three lines there, which is what
                  // a marketing hero wants. Below 780 nothing changes and the
                  // phone keeps 30 px.
                  child: Text(
                    isExample
                        ? context.tr('The next generation of money.')
                        : context.tr(
                            'Your money stack, ready for bank transfers and crypto cards.'),
                    style: (isExample && wide
                            ? AppTypography.displayXl(theme.textTheme)
                            : theme.textTheme.displaySmall)
                        ?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.05,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isExample
                    ? showGlobalAccounts
                        ? context.tr(
                            'Global accounts, crypto and fiat balances, cards, and total control in one secure experience.')
                        : context.tr(
                            'Crypto balances, cards, rewards, and total control in one secure experience.')
                    : context.tr(
                        'Open an account, verify once, then manage fiat balances, payouts, card limits, and wallet assets from one mobile surface.'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.78),
                  height: 1.35,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: isExample
                ? [
                    if (showGlobalAccounts)
                      _HeroPill(
                        icon: Icons.public_rounded,
                        label: context.tr('Global accounts'),
                      ),
                    _HeroPill(
                      icon: Icons.swap_horiz_rounded,
                      label: showGlobalAccounts
                          ? context.tr('Crypto & fiat')
                          : context.tr('Crypto'),
                    ),
                    _HeroPill(
                      icon: Icons.credit_card_rounded,
                      label: context.tr('Cards'),
                    ),
                    _HeroPill(
                      icon: Icons.shield_outlined,
                      label: context.tr('Total control'),
                    ),
                  ]
                : [
                    _HeroPill(
                      icon: Icons.payments_outlined,
                      label: context.tr('EUR accounts'),
                    ),
                    _HeroPill(
                      icon: Icons.credit_card,
                      label: context.tr('Virtual cards'),
                    ),
                    _HeroPill(
                      icon: Icons.shield_outlined,
                      label: context.tr('Regulated KYC'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingSteps extends StatelessWidget {
  const _OnboardingSteps({
    required this.appName,
    this.showBankingStep = true,
  });

  final String appName;

  /// Hidden when the installation runs without EqualsMoney banking.
  final bool showBankingStep;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeoSurfaceCard(
      padding: const EdgeInsets.all(22),
      child: Padding(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('Setup path'),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                  'Follow the required steps to unlock banking, cards, and wallet access.'),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            _StepTile(
              index: 1,
              title: context.tr('Create your {p0} login', {'p0': appName}),
              subtitle:
                  context.tr('Email, secure password, and account recovery.'),
              icon: Icons.person_add_alt_1,
              status: '2 min',
            ),
            _StepTile(
              index: 2,
              title: context.tr('Verify identity'),
              subtitle: context
                  .tr('Document scan, profile questions, and issuer checks.'),
              icon: Icons.verified_user_outlined,
              status: 'Required',
            ),
            if (showBankingStep)
              _StepTile(
                index: 3,
                title: context.tr('Connect banking provider'),
                subtitle:
                    context.tr('Complete EqualsMoney onboarding for balances.'),
                icon: Icons.account_balance,
                status: 'Next',
              ),
            _StepTile(
              index: showBankingStep ? 4 : 3,
              title: context.tr('Activate cards and wallets'),
              subtitle: context
                  .tr('Order cards, set spend controls, and manage assets.'),
              icon: Icons.credit_score,
              status: 'After KYC',
            ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.status,
  });

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$index. $title',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      status,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(
          context.brandShape.radius(AppRadii.md),
        ),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
