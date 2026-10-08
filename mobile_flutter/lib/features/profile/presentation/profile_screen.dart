import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../core/l10n/language_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/shell/banking_shell.dart';
import '../../../core/privacy/private_mode_provider.dart';
import '../../../core/branding/app_design.dart';

import '../../../brands/example/example.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/models/banking_models.dart';
import '../../../core/theme/theme_preference_provider.dart';
import '../../../core/widgets/app_states.dart';
import '../../../shared/shared.dart';
import '../../auth/application/auth_providers.dart';
import '../../auth/application/biometric_providers.dart';
import '../../auth/data/biometric_authenticator.dart';
import '../../banking/application/banking_providers.dart';
import '../../platform/application/platform_providers.dart';
import '../../auth/data/auth_api.dart';
import 'kyc_status_overview_screen.dart';
import 'legal_documents_sheet.dart';
import 'security_sheets.dart';
import 'biometric_reset_dialog.dart';
import 'nickname_editor.dart';
import '../../platform/presentation/tiers_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final config = ref.watch(appConfigProvider);
    final tenantConfig = ref.watch(mobileTenantConfigProvider).valueOrNull;
    // Read here rather than inside `dashboard.when`, because the loading
    // skeleton needs it too: the tenant config resolves independently of the
    // dashboard, so the Account group can be drawn at the row count that is
    // actually coming instead of at a guess that then jumps.
    final rewardsEnabled = tenantConfig?.referralsEnabled == true ||
        tenantConfig?.vouchersEnabled == true;
    final desktop = config.branding.isExample &&
        MediaQuery.sizeOf(context).width >= ExampleBreakpoints.desktop;

    ref.listen(platformActionControllerProvider, (previous, next) {
      next.whenOrNull(
        error: (error, stackTrace) =>
            ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(error))),
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        centerTitle: config.branding.isExample && !desktop,
        leading: config.branding.isExample && !desktop
            ? IconButton(
                tooltip: context.tr('Back'),
                onPressed: () => context.go('/home'),
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
              )
            : null,
        title: Text(desktop
            ? context.tr('Settings & security')
            : context.tr('Settings')),
        actions: config.branding.isExample
            ? null
            : [
                IconButton(
                  tooltip: context.tr('Refresh'),
                  onPressed: () {
                    ref.invalidate(dashboardProvider);
                    ref.invalidate(assetsProvider);
                  },
                  icon: const Icon(Icons.refresh),
                ),
              ],
      ),
      body: dashboard.when(
        data: (snapshot) {
          final supportEmail =
              tenantConfig?.supportEmail ?? config.branding.supportEmail;
          void editProfile() => _showProfileDialog(
                context,
                ref,
                snapshot.profile.name,
                snapshot.profile.email,
              );
          Future<void> signOut() async {
            await ref
                .read(authControllerProvider.notifier)
                .logout(clearBiometric: true);
            if (context.mounted) context.go('/login');
          }

          return config.branding.isExample
              ? _ExampleProfileContent(
                  snapshot: snapshot,
                  supportEmail: supportEmail,
                  rewardsEnabled: rewardsEnabled,
                  onEditProfile: () => _showPersonalDetails(
                    context,
                    snapshot.profile,
                    supportEmail,
                  ),
                  onEditNickname: () => showNicknameEditor(context, snapshot.profile.nickname),
                  onSignOut: signOut,
                )
              : _ProfileContent(
                  snapshot: snapshot,
                  supportEmail: supportEmail,
                  rewardsEnabled: rewardsEnabled,
                  onEditProfile: editProfile,
                  onEditNickname: () => showNicknameEditor(context, snapshot.profile.nickname),
                  onSignOut: signOut,
                );
        },
        // Settings has an entirely predictable shape, so Example loads into
        // that shape rather than into a centred spinner, and fails into a
        // designed, announced error rather than a bare one. Other brands keep
        // the shared states they render today.
        error: (error, stackTrace) => config.branding.isExample
            ? ExampleBackdrop(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: ExampleErrorState(
                      title: context.tr('Settings could not load'),
                      error: error,
                      onRetry: () => ref.invalidate(dashboardProvider),
                    ),
                  ),
                ),
              )
            : ErrorState(
                error: error,
                onRetry: () => ref.invalidate(dashboardProvider),
              ),
        loading: () => config.branding.isExample
            ? ExampleBackdrop(
                child: _ExampleSettingsSkeleton(rewardsEnabled: rewardsEnabled),
              )
            : LoadingState(label: context.tr('Loading profile')),
      ),
    );
  }
}

class _ExampleProfileContent extends ConsumerStatefulWidget {
  const _ExampleProfileContent({
    required this.snapshot,
    required this.supportEmail,
    required this.rewardsEnabled,
    required this.onEditNickname,
    required this.onEditProfile,
    required this.onSignOut,
  });

  final DashboardSnapshot snapshot;
  final String supportEmail;
  final bool rewardsEnabled;
  final VoidCallback onEditNickname;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;

  @override
  ConsumerState<_ExampleProfileContent> createState() =>
      _ExampleProfileContentState();
}

class _ExampleProfileContentState extends ConsumerState<_ExampleProfileContent> {
  int _desktopSection = 0;

  /// Every icon tile in Settings carries the same accent. Colour is reserved
  /// for meaning — success on the device you are signed in on, danger on the
  /// one destructive row — so the list never becomes a swatch chart.
  /// `ExampleIconTile` washes it at .14 and deepens the glyph to `lightIris`
  /// on paper, so one token covers both themes.
  static const Color _tile = ExampleColors.iris;

  @override
  Widget build(BuildContext context) {
    final profile = widget.snapshot.profile;
    final enrollment = ref.watch(biometricEnrollmentProvider).valueOrNull;
    final capability = ref.watch(biometricCapabilityProvider).valueOrNull;
    final biometricLabel =
        kIsWeb ? 'Passkey' : capability?.describe() ?? 'Biometrics';
    final biometricEnabled =
        enrollment?.enabled == true && enrollment?.hasToken == true;
    final securityAsync = ref.watch(accountSecurityProvider);
    final security = securityAsync.valueOrNull;
    final protection = _ProtectionReading.resolve(
      security: securityAsync,
      identityVerified: profile.isKycReady,
      passkeyEnabled: biometricEnabled,
      biometricLabel: biometricLabel,
      // Null means the capability check has not answered yet; assume the
      // common case (a device that can hold a passkey) rather than briefly
      // drawing a three-segment meter that then grows a fourth.
      passkeyOffered: capability == null || capability.available,
    );

    // A settings row states a fact about the account, so it must not state a
    // default as if it were one. Before this, an unread security summary
    // rendered "Authenticator app codes" and "Not set" — a screen that told
    // you two-step verification was off while the request was still in
    // flight, and kept telling you so if it failed. The row now carries its
    // own three states in the subtitle slot, on the one rhythm, with no
    // spinner and no layout move.
    String securityValue(String Function(AccountSecurity value) resolve) =>
        securityAsync.when(
          data: resolve,
          loading: () => 'Checking…',
          error: (_, __) => 'Unavailable',
        );

    final accountSection = _SettingsSection(
      label: context.tr('Account'),
      children: [
        ExampleRow(
          leading: const ExampleIconTile(icon: Icons.alternate_email, color: _tile),
          title: context.tr('Nickname'),
          subtitle: profile.nickname == null
              ? context.tr('Set your unique nickname') : '@${profile.nickname}',
          trailing: ExampleRow.chevron,
          onTap: widget.onEditNickname,
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.person_outline_rounded,
            color: _tile,
          ),
          title: context.tr('Personal details'),
          subtitle: context.tr('Name and contact'),
          trailing: ExampleRow.chevron,
          onTap: widget.onEditProfile,
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.verified_user_outlined,
            color: _tile,
          ),
          title: context.tr('Identity verification'),
          subtitle: profile.isKycReady
              ? context.tr('Verified')
              : friendlyStatus(profile.kycStatus),
          trailing: ExampleRow.chevron,
          onTap: () => profile.isKycReady
              ? showKycStatusSheet(context, ref)
              : context.go('/kyc'),
        ),
        if (widget.rewardsEnabled)
          ExampleRow(
            leading: const ExampleIconTile(
              icon: Icons.card_giftcard_outlined,
              color: _tile,
            ),
            title: context.tr('Rewards'),
            subtitle: context.tr('Referrals and vouchers'),
            trailing: ExampleRow.chevron,
            onTap: () => context.go('/rewards'),
          ),
      ],
    );

    final securitySection = _SettingsSection(
      label: context.tr('Security'),
      children: [
        ExampleRow(
          // This whole section is inside `_ExampleProfileContent`, so it never
          // renders for a white-label tenant and the naming can be ours.
          leading: ExampleIconTile(
            icon: kIsWeb
                ? Icons.key_rounded
                : capability?.hasFaceId == true
                    ? Icons.face_outlined
                    : Icons.fingerprint,
            color: _tile,
          ),
          title: biometricLabel,
          subtitle: context.tr('Card reveal & payments'),
          trailing: _SettingsSwitch(
            value: biometricEnabled,
            semanticsLabel: biometricLabel,
            onChanged: biometricEnabled || capability?.available == true
                ? (value) => _toggleBiometric(
                      value,
                      biometricLabel,
                    )
                : null,
          ),
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.shield_outlined,
            color: _tile,
          ),
          title: context.tr('Two-step verification'),
          subtitle: securityValue(
            (value) => value.twoFactorEnabled
                ? 'On · ${value.recoveryCodesRemaining} codes left'
                : 'Off',
          ),
          trailing: ExampleRow.chevron,
          onTap: () => showTwoFactorSheet(
            context,
            ref,
            enabled: security?.twoFactorEnabled == true,
          ),
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.vpn_key_rounded,
            color: _tile,
          ),
          title: context.tr('Change password'),
          subtitle: context.tr('Signs out other devices'),
          trailing: ExampleRow.chevron,
          onTap: () => showChangePasswordSheet(context, ref),
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.security_rounded,
            color: _tile,
          ),
          title: context.tr('Duress password'),
          subtitle: securityValue(
            (value) => value.duressPasswordSet
                ? 'Locks the account if used'
                : 'Not set',
          ),
          trailing: ExampleRow.chevron,
          onTap: () => showDuressPasswordSheet(
            context,
            ref,
            isSet: security?.duressPasswordSet == true,
          ),
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.phone_iphone_rounded,
            color: _tile,
          ),
          title: context.tr('Devices & sessions'),
          subtitle: context.tr('Where you are signed in'),
          trailing: ExampleRow.chevron,
          onTap: () => _showDevicesSheet(context, ref),
        ),
        ExampleRow(
          leading: const ExampleIconTile(icon: Icons.tune_rounded, color: _tile),
          title: context.tr('Limits'),
          subtitle: context.tr('Daily spend and ATM'),
          trailing: ExampleRow.chevron,
          onTap: () => context.go('/cards'),
        ),
      ],
    );

    // Preferences collects the settings that change what the customer sees,
    // as against the ones that protect the account. Private Mode moved here
    // out of Security: hiding a balance is privacy, not protection, and a
    // switch sitting halfway down the protection list made that list read as
    // a mixture instead of a subject.
    final preferencesSection = _SettingsSection(
      label: context.tr('Preferences'),
      children: [
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.visibility_off_outlined,
            color: _tile,
          ),
          title: context.tr('Private Mode'),
          subtitle: context.tr('Hide every balance'),
          trailing: _SettingsSwitch(
            value: ref.watch(privateModeProvider).valueOrNull ?? false,
            semanticsLabel: context.tr('Private Mode'),
            onChanged: (value) =>
                ref.read(privateModeProvider.notifier).set(value),
          ),
        ),
        const _ExampleAppearanceBlock(),
        const LanguagePicker(),
      ],
    );

    // Support and Legal were two panels of one row each. Three single-row
    // groups stacked down a page read as leftovers rather than as structure;
    // one group of two rows says the same thing and gives the section a
    // reason to be a section.
    final helpSection = _SettingsSection(
      label: context.tr('Help & legal'),
      children: [
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.support_agent_rounded,
            color: _tile,
          ),
          title: context.tr('Support tickets'),
          subtitle: context.tr('View requests and replies'),
          trailing: ExampleRow.chevron,
          onTap: _contactSupport,
        ),
        ExampleRow(
          leading: const ExampleIconTile(
            icon: Icons.description_outlined,
            color: _tile,
          ),
          title: context.tr('Legal documents'),
          subtitle: context.tr('Registration and card agreements'),
          trailing: ExampleRow.chevron,
          onTap: _showLegalDocuments,
        ),
      ],
    );

    final signOutSection = ExampleListGroup(
      children: [
        _ExampleDestructiveRow(
          icon: Icons.logout_rounded,
          title: context.tr('Sign out'),
          subtitle: context.tr('On this device'),
          onTap: _signOut,
        ),
      ],
    );

    return ExampleBackdrop(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 820;
          if (desktop) {
            final sections = <({String label, IconData icon, Widget body})>[
              (
                label: context.tr('Account'),
                icon: Icons.person_outline_rounded,
                body: accountSection,
              ),
              (
                label: context.tr('Security'),
                icon: Icons.shield_outlined,
                body: securitySection,
              ),
              (
                label: context.tr('Preferences'),
                icon: Icons.tune_rounded,
                body: preferencesSection,
              ),
              (
                label: context.tr('Help & legal'),
                icon: Icons.support_agent_rounded,
                body: helpSection,
              ),
            ];
            final index = _desktopSection.clamp(0, sections.length - 1);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: BorderDirectional(
                      end: ExampleBorders.hairlineSideOf(context),
                    ),
                  ),
                  child: SizedBox(
                    width: 250,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      children: [
                        for (var i = 0; i < sections.length; i++)
                          _DesktopSettingsNavItem(
                            label: sections[i].label,
                            icon: sections[i].icon,
                            selected: i == index,
                            onTap: () => setState(() => _desktopSection = i),
                          ),
                        const SizedBox(height: AppSpacing.md),
                        _DesktopSettingsNavItem(
                          label: context.tr('Sign out'),
                          icon: Icons.logout_rounded,
                          selected: false,
                          destructive: true,
                          onTap: _signOut,
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ExampleProfileHeader(
                              profile: profile,
                              protection: protection,
                              onTap: widget.onEditProfile,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            sections[index].body,
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, 32),
            children: [
              _ExampleProfileHeader(
                profile: profile,
                protection: protection,
                onTap: widget.onEditProfile,
              ),
              const SizedBox(height: AppSpacing.lg),
              accountSection,
              const SizedBox(height: AppSpacing.lg),
              securitySection,
              const SizedBox(height: AppSpacing.lg),
              preferencesSection,
              const SizedBox(height: AppSpacing.lg),
              helpSection,
              const SizedBox(height: AppSpacing.lg),
              signOutSection,
            ],
          );
        },
      ),
    );
  }

  void _signOut() {
    widget.onSignOut();
  }

  void _contactSupport() => context.push('/support');

  Future<void> _showLegalDocuments() => showLegalDocumentsSheet(context);

  Future<void> _toggleBiometric(bool value, String biometricLabel) async {
    if (!value) {
      await confirmBiometricReset(context, ref, biometricLabel);
      return;
    }
    final controller = ref.read(authControllerProvider.notifier);
    final result = await ref.read(biometricAuthenticatorProvider).authenticate(
          reason: 'Confirm to enable $biometricLabel sign-in',
        );
    if (result != BiometricAuthResult.success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('{p0} was not enabled.',
                {'p0': biometricLabel})),
          ),
        );
      }
      return;
    }
    await controller.enableBiometricForCurrentSession();
  }
}

/// One item of the 1440 settings rail.
///
/// It carries the same leading glyph as the mobile row it stands for, so the
/// two layouts read as one screen seen at two widths rather than as two
/// designs. Colour stays reserved for meaning: the destructive item is marked
/// by its glyph alone and its label keeps the page ink, exactly as the mobile
/// sign-out row does.
class _DesktopSettingsNavItem extends StatelessWidget {
  const _DesktopSettingsNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    // Glyph contrast on the page ground the rail sits on: danger 7.00:1 in
    // Twilight and 4.68:1 on paper, the active accent 7.37:1 and 5.78:1, the
    // resting tertiary 5.15:1 and 4.58:1 — all over the 3:1 icon floor, and
    // the atmosphere only ever lifts the ground away from the glyph.
    final glyph = destructive
        ? palette.danger
        : selected
            ? palette.accent
            : palette.textTertiary;
    final radius = BorderRadius.circular(10);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: selected
              ? palette.fill.withValues(alpha: palette.isDark ? .24 : .14)
              : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                children: [
                  Icon(icon, size: 18, color: glyph),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? palette.ink : palette.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The masthead of Settings — the one object on this screen that carries
/// weight, and the whole of its "big thing".
///
/// Settings is a high-frequency utility screen, so it earns its presence
/// typographically and structurally rather than with motion. Three things
/// separate this from the grouped-list header every bank ships:
///
/// 1. **Type.** The name is stated at `headlineMedium` (26 px) across the
///    full plate rather than squeezed into a row beside a 48 pt avatar. It
///    is the largest thing on the screen and the only step above the 22 px
///    page title, and everything below it drops away: section labels fall to
///    the 11 px eyebrow, rows stay at 14. 26 / 11 / 14 is a scale; the
///    16 / 15.5 / 14 it replaces was a single volume with rounding errors.
/// 2. **Depth by role.** The plate is `AppRadii.xl` where every list group
///    below it is `AppRadii.lg`, and it is the only element on the page that
///    takes `ExampleShadows.liftOf` — the violet lift in Twilight, the deeper
///    night shadow on paper — while the groups keep the resting ambient. One
///    lifted object reads as hierarchy; twelve identically bevelled panels
///    read as wallpaper.
/// 3. **A fact, not an ornament.** The plate closes on the protection meter
///    (see [_ProtectionReading]): how many of this account's defences are
///    actually on, encoded as filled segments *and* stated as a number.
///    Before it, the only way to learn that was to read five rows and keep
///    count.
///
/// The plate is two zones, and only the upper one is a button: pressing the
/// identity opens personal details, while the meter is inert and keeps its
/// own semantics. That split is structural, not cosmetic. `ExamplePressable`
/// excludes its entire subtree the moment it is handed a `semanticsLabel`, so
/// a label on the whole plate would have swallowed the meter — the one thing
/// on this screen that is not also a row — and the label on the zone it does
/// cover has to speak every line inside it. It names the tier and the email
/// as well as the name for exactly that reason: neither is stated anywhere
/// else on the screen, and labelling the zone with the name alone deleted
/// both from the accessibility tree.
///
/// Motion: none of its own. The lit top edge is the screen's only sheen host
/// — a panel's top hairline is on the allowed list — and it registers only
/// when a [ExampleSheenScope] is already above it, so Settings starts no
/// clock and reduced motion never reaches a ticker.
class _ExampleProfileHeader extends StatelessWidget {
  const _ExampleProfileHeader({
    required this.profile,
    required this.protection,
    required this.onTap,
  });

  final UserProfile profile;
  final _ProtectionReading protection;
  final VoidCallback onTap;

  /// The name's style, stated here rather than inline because the loading
  /// skeleton has to reserve its exact line box. Guessing at that line box is
  /// not a rounding error: 26 px at 1.15 measures 30 pt, four more than the
  /// block that used to stand in for it, and every section on the page moves
  /// by the difference the moment the account arrives.
  static TextStyle nameStyleOf(BuildContext context) =>
      (Theme.of(context).textTheme.headlineMedium ??
              const TextStyle(fontSize: 26))
          .copyWith(
        fontWeight: FontWeight.w700,
        color: ExampleInk.primary(context),
        height: 1.15,
      );

  /// The email's style, shared with the skeleton for the same reason.
  static TextStyle emailStyleOf(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall ?? const TextStyle(fontSize: 12))
          .copyWith(color: ExampleInk.secondary(context));

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.xl);

    Widget edge = ColoredBox(
      // Twilight catches light on a pearl edge; on paper the panel is already
      // white, so the top edge is the daylight hairline and the band reads as
      // a highlight travelling along it.
      color: ExampleTheme.pick(
        context,
        dark: ExamplePalette.of(context).ink.withValues(alpha: .16),
        light: ExamplePalette.of(context).borderSubtle,
      ),
    );
    if (ExampleSheenScope.maybeOf(context) != null) {
      edge = ExampleSheen(
        intensity: ExampleSheenIntensity.soft,
        sweepOnArrival: false,
        child: edge,
      );
    }

    // The tier is watched up here rather than beside the pill it draws,
    // because the button's label has to say it — see the note on excluded
    // subtrees above. One `Consumer` now feeds both the pill and the sentence
    // a screen reader hears, so they cannot come apart.
    final identity = Consumer(
      builder: (context, ref, _) {
        final tier = ref.watch(currentTierProvider).valueOrNull;
        final tierLabel = profile.isBusinessAccount
            ? context.tr('Business')
            : tier == null
                ? context.tr('Member')
                : context.tr('{p0} tier', {'p0': tierTitleOf(tier)});
        final email =
            fallbackText(profile.email, context.tr('Email not available'));
        return ExamplePressable(
          onTap: onTap,
          borderRadius: radius,
          // Gentler than the .985 a whole plate takes, because only the upper
          // zone moves and it is moving inside a panel that stays put.
          pressedScale: .99,
          // Everything the zone shows, in the order the eye takes it, then
          // the action it performs.
          semanticsLabel: '${_profileDisplayName(profile)}, $tierLabel, '
              '$email, open personal details',
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ExampleAvatar(name: profile.name, size: 48),
                    const Spacer(),
                    ExamplePill(label: tierLabel, color: ExampleColors.iris),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _profileDisplayName(profile),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        // The full plate width is what makes 26 px safe at
                        // 375: the name no longer shares its line with an
                        // avatar and a chevron, so it holds ~20 characters
                        // before it elides instead of ~8.
                        style: nameStyleOf(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    ExampleRow.chevronOf(context),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: emailStyleOf(context),
                ),
              ],
            ),
          ),
        );
      },
    );

    return Stack(
      // A loose Stack relaxes the tight width the list hands down, which
      // would let this plate shrink to the width of the name inside it.
      fit: StackFit.passthrough,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: radius,
            border: ExampleBorders.subtleOf(context),
            boxShadow: ExampleShadows.liftOf(context),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              // Full-bleed rather than inset to the text column: this is the
              // seam between two kinds of thing, not a divider between two
              // rows of the same kind.
              SizedBox(
                height: 1,
                child: ColoredBox(
                  color: ExampleBorders.hairlineSideOf(context).color,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: _ProtectionMeter(reading: protection),
              ),
            ],
          ),
        ),
        PositionedDirectional(
          top: 0,
          start: AppRadii.xl,
          end: AppRadii.xl,
          height: 1,
          child: edge,
        ),
      ],
    );
  }
}

/// How well defended this account actually is, resolved through the same
/// `AsyncValue.when` the row subtitles take — error branch and all — so the
/// meter can never disagree with the list under it.
///
/// Four defences are reachable from this screen — identity verification, the
/// passkey, two-step verification and the duress password. Until now the only
/// way to learn how many were on was to read five rows and keep count, which
/// is exactly the kind of thing a screen should state rather than make you
/// assemble.
///
/// Two decisions worth naming:
///
/// * **The denominator is what this device can actually do.** A machine with
///   no platform authenticator cannot enrol a passkey — the row's switch is
///   disabled — so on that machine the passkey is dropped from the reading
///   entirely and the meter reads "of 3". Counting a defence the user is not
///   allowed to turn on would be scolding them for their hardware.
/// * **Unknown is a state, not a zero.** While `accountSecurityProvider` is
///   in flight, or after it fails, two of the four are simply not known. The
///   meter says so ("Checking…" / "Unavailable") and every segment stays
///   inert, on the same three-state convention the row subtitles already use.
///   Painting them as off would state a fact the screen does not have.
class _ProtectionReading {
  const _ProtectionReading._({
    required this.segments,
    required this.status,
    required this.tone,
    required this.semanticsLabel,
  });

  /// One entry per defence this account can turn on, in the order they
  /// appear in the sections below. True means on.
  final List<bool> segments;

  /// The right-hand statement: "All 4 active", "2 of 4 active", "Checking…".
  final String status;

  /// Hue for the filled segments and the statement. Null while the reading is
  /// unknown, which is what makes the meter inert.
  final Color? tone;

  /// Spoken form. The meter is a bar and a count; a screen reader gets the
  /// same information as a sentence naming each defence and its state.
  final String semanticsLabel;

  static _ProtectionReading resolve({
    required AsyncValue<AccountSecurity> security,
    required bool identityVerified,
    required bool passkeyEnabled,
    required bool passkeyOffered,
    required String biometricLabel,
  }) {
    final names = <String>[
      'Identity verification',
      if (passkeyOffered) biometricLabel,
      'Two-step verification',
      'Duress password',
    ];
    // The same three branches, in the same order, that `securityValue` takes
    // for the row subtitles. `valueOrNull` returns the value a failed refetch
    // retained and never reaches the error case at all, which is how this
    // meter came to state a figure the rows underneath had already withdrawn.
    return security.when(
      data: (value) => _counted(names, <bool>[
        identityVerified,
        if (passkeyOffered) passkeyEnabled,
        value.twoFactorEnabled,
        value.duressPasswordSet,
      ]),
      loading: () => _unknown(
        names.length,
        status: 'Checking…',
        spoken: 'Checking account protection',
      ),
      error: (_, __) => _unknown(
        names.length,
        status: 'Unavailable',
        spoken: 'Account protection could not be read',
      ),
    );
  }

  /// The reading with the two server-held defences still unread: no tone, so
  /// every segment stays inert, and the state said in words. Painting them
  /// off would state a fact the screen does not have.
  static _ProtectionReading _unknown(
    int total, {
    required String status,
    required String spoken,
  }) =>
      _ProtectionReading._(
        segments: List<bool>.filled(total, false),
        status: status,
        tone: null,
        semanticsLabel: spoken,
      );

  /// The reading with every defence known: how many of [on] are true, the
  /// level colour that count earns, and the spoken sentence that names each
  /// of [names] and its state.
  static _ProtectionReading _counted(List<String> names, List<bool> on) {
    final total = on.length;
    final count = on.where((active) => active).length;
    // Colour by level, never per segment: a four-hue bar is a swatch chart.
    // Everything on is success, a partial account is the brand accent, and
    // one or none is the only case that asks for attention.
    final tone = count == total
        ? ExampleColors.success
        : count <= 1
            ? ExampleColors.warning
            : ExampleColors.iris;
    final spoken = [
      for (var i = 0; i < names.length; i++)
        '${names[i]} ${on[i] ? 'on' : 'off'}',
    ].join(', ');
    return _ProtectionReading._(
      segments: on,
      status: count == total ? 'All $total active' : '$count of $total active',
      tone: tone,
      semanticsLabel: 'Protection, $count of $total active. $spoken.',
    );
  }
}

/// The protection reading drawn: an eyebrow, the count, and one segment per
/// defence.
///
/// The form carries the state as well as the number — a glance at how much of
/// the bar is filled answers the question without reading a word — which is
/// the point of putting it here instead of adding a sixth sentence to the
/// Security list.
///
/// Deliberately static. This is a screen people open to flip a switch, and
/// the motion frequency rule says a screen used that often does not animate
/// beyond the 120 ms press; a meter that filled itself on every visit would
/// be charging the user for information they already have.
///
/// Contrast, every figure measured against the plate the meter sits on —
/// `ExampleSurface.of(context, 1)`, #FBF8FF in daylight and #101425 in
/// Twilight. Lit segments resolve through `ExampleInk.accent` and clear the
/// 3:1 non-text floor with room to spare: iris 5.93:1 on paper and 6.72:1 on
/// night, success 5.11 / 9.95, warning 5.29 / 10.29.
///
/// Unlit segments are **ink**, not a wash of the accent, and that is the
/// repair this component needed. Washing the accent cannot work on paper:
/// iris is a light violet, so at .18 through `ExampleInk.tint` it composited
/// to #EDE6FE — 1.15:1 on the plate, a denominator nobody can see — and the
/// level-2 surface it was picked over is 1.13:1, one step of 1.0147:1 away
/// and to the eye the same colour. Neither was ever going to read in
/// daylight. Ink is the one family that travels the right way in both themes,
/// darkening on paper and lightening on night, so an unlit segment is the ink
/// at [_trackFill] (1.72:1 on paper, 2.00:1 on night) inside a 1 px edge of
/// the same ink at [_trackEdge] (3.17:1 and 4.13:1, both over the 3:1
/// boundary floor). The edge is what makes the measure countable: you can see
/// how many segments there are before you read how many are lit, which is the
/// whole claim of putting a bar here rather than a sixth sentence.
///
/// The edge belongs to the unlit slot only. On a lit segment it would be a
/// grey ring around a solid accent, and the fill already states that segment
/// at 5:1 or better.
///
/// The bar still never carries information alone: the count beside it says
/// the same thing in words, which is what keeps it clear of WCAG 1.4.11
/// however quiet the track is.
class _ProtectionMeter extends StatelessWidget {
  const _ProtectionMeter({required this.reading});

  final _ProtectionReading reading;

  /// Ink volume of an unlit segment, and of the edge around it. Two numbers
  /// rather than one: the fill has to stay quiet enough that lit against
  /// unlit is still the first thing the eye reads, while the edge has to
  /// clear the 3:1 boundary floor on its own. Both are measured in the class
  /// doc above.
  static const double _trackFill = .24;
  static const double _trackEdge = .46;

  @override
  Widget build(BuildContext context) {
    final tone = reading.tone;
    // An unlit segment is the page ink at rest, so a defence that is off
    // reads as an empty slot rather than as a paler shade of on — and unknown
    // needs no hue of its own, because with no tone nothing lights up and the
    // whole measure stays in that same ink.
    final unlit = ExampleInk.primary(context);
    final track = unlit.withValues(alpha: _trackFill);
    final edge = Border.all(color: unlit.withValues(alpha: _trackEdge));
    final filled = tone == null ? track : ExampleInk.accent(context, tone);
    return Semantics(
      label: reading.semanticsLabel,
      excludeSemantics: true,
      // Its own node, not a paragraph appended to the button above it.
      // Without this the meter's config merged into the plate's node and a
      // screen reader read the whole thing as one button whose label ran
      // "…open personal details. Protection, 3 of 4 active…" — the second
      // sentence describing something the button does not do.
      container: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('PROTECTION'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ExampleTextStyles.label(context),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                reading.tone == null
                    ? context.tr(reading.status)
                    : reading.segments.every((active) => active)
                        ? context.tr(
                            'All {p0} active', {'p0': reading.segments.length})
                        : context.tr('{p0} of {p1} active', {
                            'p0': reading.segments
                                .where((active) => active)
                                .length,
                            'p1': reading.segments.length
                          }),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ExampleTextStyles.amount(
                  context,
                  size: ExampleAmountSize.inline,
                ).copyWith(
                  color: tone == null
                      ? ExampleInk.tertiary(context)
                      : ExampleInk.accent(context, tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 5,
            child: Row(
              children: [
                for (var i = 0; i < reading.segments.length; i++) ...[
                  if (i > 0) const SizedBox(width: 5),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: reading.segments[i] ? filled : track,
                        // Painted inside the box either way, so a segment is
                        // the same size lit or unlit and the bar never
                        // reflows as defences come on.
                        border: reading.segments[i] ? null : edge,
                        borderRadius: const BorderRadius.all(
                          Radius.circular(2.5),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A Settings section: its label and the group of rows under it.
///
/// [ExampleSectionTitle] states a heading at 15.5 px in the primary ink, which
/// is right on Home, where a heading sits over a chart or a card and has to
/// hold its own against them. On Settings it was the wrong register: a
/// 15.5 px heading one row above a 14 px row title is not a step, and six of
/// them down one page flattened the screen into a single volume — the exact
/// "everything is 14 to 16 px" complaint this pass exists to answer.
///
/// So the heading moves into the register the vocabulary already reserves for
/// section kickers — [ExampleTextStyles.label], 11 px semibold at +0.06 em,
/// secondary ink, body-grade in both themes — and a hairline runs from the
/// label to the right edge. The label stops competing with the content it
/// introduces, the rule gives the section an edge to sit on, and the screen
/// ends up with a real three-step scale: 26 px name, 11 px section, 14 px row.
/// This is a composition of existing vocabulary, not a second section-title
/// widget; nothing here re-decides a colour, a size or a spacing token.
class _SettingsSection extends StatelessWidget {
  const _SettingsSection({required this.label, required this.children});

  /// Stated in the sentence case it is written in and drawn uppercase, so the
  /// spoken heading is "Help & legal" rather than a shouted acronym.
  final String label;

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              children: [
                Semantics(
                  header: true,
                  label: label,
                  excludeSemantics: true,
                  child: Text(
                    label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ExampleTextStyles.label(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: SizedBox(
                    height: 1,
                    child: ColoredBox(
                      color: ExampleBorders.hairlineSideOf(context).color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ExampleListGroup(children: children),
        ],
      );
}

/// The one destructive row in Settings.
///
/// [ExampleRow] paints its title in the primary ink and takes no override, so
/// this mirrors its geometry exactly — the 56 pt floor,
/// `ExampleRow.defaultPadding`, the 40 pt leading square and the 12 pt gap —
/// and changes exactly one thing: the icon tile. No red panel, no red fill,
/// no full-width red button, and no red sentence either. A destructive action
/// has to be findable, not loud, and the glyph is enough to find it: danger
/// reads 6.38:1 on the Twilight group surface and 5.05:1 on the white one,
/// while the label keeps the page ink at 15.63:1 and 18.36:1 like every
/// other row.
/// The row also stands alone in its own group, which is the real separation.
class _ExampleDestructiveRow extends StatelessWidget {
  const _ExampleDestructiveRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caption = subtitle;
    return ExamplePressable(
      onTap: onTap,
      pressedScale: .985,
      borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
      semanticsLabel: caption == null ? title : '$title, $caption',
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: ExampleRow.defaultPadding,
          child: Row(
            children: [
              SizedBox.square(
                dimension: ExampleRow.leadingSize,
                child: Center(
                  child: ExampleIconTile(icon: icon, color: ExampleColors.danger),
                ),
              ),
              const SizedBox(width: ExampleRow.leadingGap),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (theme.textTheme.titleSmall ??
                              const TextStyle(fontSize: 14))
                          .copyWith(
                        fontWeight: FontWeight.w600,
                        color: ExampleInk.primary(context),
                        height: 1.3,
                      ),
                    ),
                    if (caption != null)
                      Text(
                        caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: (theme.textTheme.bodySmall ??
                                const TextStyle(fontSize: 12))
                            .copyWith(
                          color: ExampleInk.secondary(context),
                          height: 1.35,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Settings → Preferences → Theme.
///
/// The appearance control is the reason Pearl daylight is reachable at all,
/// and it is the first thing anyone opens on this screen, so it is the one
/// place in Settings that gets more than a row: three painted specimens of
/// the real palettes — paper ground, surface plate, ink bars, accent dot —
/// instead of a label that only names them. The System specimen is split on
/// a shallow diagonal with Twilight on one side and daylight on the other,
/// because "follows your device" is a statement about two themes and one
/// flat chip cannot make it.
///
/// It obeys the screen's rhythm rather than breaking it. The block opens with
/// an ordinary 56 pt [ExampleRow] — same leading square, same text column, so
/// the group's divider above it lands on the same inset as every other row —
/// and the specimens sit beneath it as the control. No second row height
/// enters the screen, and nothing here is a card inside a card: a specimen is
/// a material sample at radius 10, deliberately smaller and flatter than a
/// panel, and bounded to 372 pt so the desktop column cannot stretch three
/// swatches into three cards.
///
/// Utility register: no arrival moment, no sheen. The only motion is the
/// selection itself — the ring colour and the check badge over
/// [ExampleMotion.state] — and it is instant under reduced motion because
/// every duration is read through [ExampleMotion.of].
class _ExampleAppearanceBlock extends ConsumerWidget {
  const _ExampleAppearanceBlock();

  static const List<(ThemeMode, String)> _options = [
    (ThemeMode.system, 'System'),
    (ThemeMode.light, 'Light'),
    (ThemeMode.dark, 'Dark'),
  ];

  /// The specimen strip's geometry, named once because two widgets stand on
  /// it: [_ThemeSpecimen] draws the strip and [_ExampleSettingsSkeleton]
  /// reserves the same space while the account loads. At 375 the strip is
  /// about 101 pt — a swatch, its 8 pt gap, a 15 pt label and the block's
  /// bottom inset — which is most of what Preferences is. A skeleton that
  /// reserves only the row above it is 101 pt short, and everything under
  /// Preferences jumps by that when the data lands.
  static const double specimenMaxWidth = 372;
  static const double specimenAspect = 1.5;
  static const double specimenRadius = 15;
  static const double specimenLabelSize = 12.5;
  static const double specimenLabelLeading = 1.2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(appConfigProvider).branding;
    // A null preference means "whatever the tenant ships"; resolve it so the
    // control always names the mode the app is actually in rather than
    // showing three unselected swatches.
    final selected = ref.watch(themePreferenceProvider).valueOrNull ??
        branding.materialThemeMode;
    final systemIsDark =
        MediaQuery.platformBrightnessOf(context) == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExampleRow(
          leading: ExampleIconTile(
            icon: switch (selected) {
              ThemeMode.light => Icons.light_mode_rounded,
              ThemeMode.dark => Icons.dark_mode_rounded,
              ThemeMode.system => Icons.brightness_auto_rounded,
            },
            color: ExampleColors.iris,
          ),
          title: context.tr('Theme'),
          subtitle: switch (selected) {
            ThemeMode.light => 'Pearl daylight',
            ThemeMode.dark => 'Twilight',
            ThemeMode.system => systemIsDark
                ? 'Following this device · Twilight'
                : 'Following this device · Pearl daylight',
          },
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: specimenMaxWidth),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final option in _options) ...[
                    if (option != _options.first)
                      const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _ThemeSpecimen(
                        mode: option.$1,
                        label: context.tr(option.$2),
                        selected: option.$1 == selected,
                        onTap: () => ref
                            .read(themePreferenceProvider.notifier)
                            .setMode(option.$1),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One theme swatch and its label.
class _ThemeSpecimen extends StatelessWidget {
  const _ThemeSpecimen({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemeMode mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = ExamplePalette.of(context);
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    final radius = BorderRadius.circular(_ExampleAppearanceBlock.specimenRadius);
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr('{p0} theme', {'p0': label}),
      onTap: onTap,
      excludeSemantics: true,
      child: ExamplePressable(
        onTap: onTap,
        pressedScale: .96,
        borderRadius: radius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: _ExampleAppearanceBlock.specimenAspect,
              child: AnimatedContainer(
                duration: duration,
                curve: ExampleMotion.arrive,
                // The ring occupies its 2 pt whether it is the fill or fully
                // transparent, so choosing a theme never nudges the swatch
                // beside it: colour is the only thing that moves. The fill
                // measures 4.63:1 on the Twilight group surface and 5.10:1 on
                // the daylight one, so the ring is a visible indicator in
                // both themes rather than a tint.
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(
                    width: 2,
                    color: selected ? palette.fill : Colors.transparent,
                  ),
                ),
                padding: const EdgeInsets.all(3),
                child: Stack(
                  // Loose would relax the tight width this swatch takes from
                  // Expanded and collapse the painter to nothing.
                  fit: StackFit.passthrough,
                  children: [
                    RepaintBoundary(
                      child: CustomPaint(
                        painter: _ThemeSpecimenPainter(
                          mode: mode,
                          darkPalette: ExamplePalette.fromDesign(
                            Brightness.dark,
                            context.brandDesign,
                          ),
                          lightPalette: ExamplePalette.fromDesign(
                            Brightness.light,
                            context.brandDesign,
                          ),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    PositionedDirectional(
                      top: 5,
                      end: 5,
                      child: AnimatedScale(
                        duration: duration,
                        curve: ExampleMotion.arrive,
                        scale: selected ? 1 : .6,
                        child: AnimatedOpacity(
                          duration: duration,
                          curve: ExampleMotion.arrive,
                          opacity: selected ? 1 : 0,
                          // Deliberately redundant with the ring: a ring
                          // alone would make selection a hue-only signal,
                          // which is the one thing a colour-vision test
                          // catches every time.
                          child: _SpecimenCheck(palette: palette),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // 18.36:1 selected on the daylight group and 7.79:1 resting;
              // 15.63:1 and 7.66:1 in Twilight. Weight carries the state as
              // well as ink, so the label is never colour alone either.
              style: TextStyle(
                fontSize: _ExampleAppearanceBlock.specimenLabelSize,
                height: _ExampleAppearanceBlock.specimenLabelLeading,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? palette.ink : palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The selected mark. Pearl on the Twilight fill is 3.38:1 and the daylight
/// surface on the daylight fill is 5.10:1 — both over the 3:1 floor a
/// graphical mark has to clear.
class _SpecimenCheck extends StatelessWidget {
  const _SpecimenCheck({required this.palette});

  final ExamplePalette palette;

  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(color: palette.fill, shape: BoxShape.circle),
        child: Icon(
          Icons.check_rounded,
          size: 12,
          color: palette.isDark ? palette.onFill : palette.surface,
        ),
      );
}

/// The painted theme sample.
///
/// A swatch is either a real specimen or it is decoration, so every colour
/// here is a token the offered theme actually renders, read from
/// the configured dark and light palettes and never from the theme
/// currently on screen. That is the rule card artwork already follows: the
/// sample keeps its own material regardless of the page around it, which is
/// why this is the one place in the feature that names the other brightness.
///
/// The composition is the product in miniature — accent mark and a quiet
/// title on the page ground, then a surface plate with a heading and a line
/// of body on it — so the swatch previews the actual hierarchy rather than
/// showing three abstract colour bars.
class _ThemeSpecimenPainter extends CustomPainter {
  const _ThemeSpecimenPainter({
    required this.mode,
    required this.darkPalette,
    required this.lightPalette,
  });

  final ThemeMode mode;
  final ExamplePalette darkPalette;
  final ExamplePalette lightPalette;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    canvas.save();
    canvas.clipRRect(rrect);
    switch (mode) {
      case ThemeMode.dark:
        _paintTheme(canvas, rrect, darkPalette);
      case ThemeMode.light:
        _paintTheme(canvas, rrect, lightPalette);
      case ThemeMode.system:
        // Twilight on the left, daylight on the right, meeting on a
        // diagonal about 8 degrees off vertical. One layout cut into two
        // skins reads as a single app under two lights, which is exactly
        // what "system" means and what a flat chip cannot say.
        final (dark, light) = _split(rrect.outerRect);
        canvas
          ..save()
          ..clipPath(dark);
        _paintTheme(canvas, rrect, darkPalette);
        canvas
          ..restore()
          ..save()
          ..clipPath(light);
        _paintTheme(canvas, rrect, lightPalette);
        canvas.restore();
    }
    canvas.restore();
  }

  static (Path, Path) _split(Rect rect) {
    final top = rect.left + rect.width * .55;
    final bottom = rect.left + rect.width * .45;
    return (
      Path()
        ..moveTo(rect.left, rect.top)
        ..lineTo(top, rect.top)
        ..lineTo(bottom, rect.bottom)
        ..lineTo(rect.left, rect.bottom)
        ..close(),
      Path()
        ..moveTo(top, rect.top)
        ..lineTo(rect.right, rect.top)
        ..lineTo(rect.right, rect.bottom)
        ..lineTo(bottom, rect.bottom)
        ..close(),
    );
  }

  static void _paintTheme(Canvas canvas, RRect rrect, ExamplePalette palette) {
    final rect = rrect.outerRect;
    final fill = Paint()..isAntiAlias = true;
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(rrect, fill..color = palette.paper);

    // Chrome line: the accent mark and a quiet title, which is how every
    // Example screen opens.
    canvas.drawCircle(
      Offset(rect.left + 11, rect.top + 11),
      3.2,
      fill..color = palette.accent,
    );
    canvas.drawRRect(
      RRect.fromLTRBR(
        rect.left + 19,
        rect.top + 9.5,
        rect.left + 19 + rect.width * .30,
        rect.top + 12.5,
        const Radius.circular(1.5),
      ),
      fill..color = palette.textTertiary,
    );

    // The panel that everything in this product rests on.
    final plate = RRect.fromLTRBR(
      rect.left + 8,
      rect.top + rect.height * .40,
      rect.right - 8,
      rect.bottom - 8,
      const Radius.circular(6),
    );
    canvas
      ..drawRRect(plate, fill..color = palette.surface)
      ..drawRRect(plate.deflate(.5), stroke..color = palette.borderSubtle);

    final inner = plate.outerRect;
    canvas
      ..drawRRect(
        RRect.fromLTRBR(
          inner.left + 7,
          inner.top + 7,
          inner.left + 7 + (inner.width - 14) * .58,
          inner.top + 11,
          const Radius.circular(2),
        ),
        fill..color = palette.ink,
      )
      ..drawRRect(
        RRect.fromLTRBR(
          inner.left + 7,
          inner.top + 15,
          inner.left + 7 + (inner.width - 14) * .36,
          inner.top + 18,
          const Radius.circular(1.5),
        ),
        fill..color = palette.textSecondary,
      );

    // The swatch edge is drawn in the sample's OWN ink, not the page's,
    // because the daylight swatch (#F4EEFC paper) on the daylight group
    // (#FBF8FF) is a 1.03:1 step and would otherwise have no outline at all.
    // Night .22 over that paper composites to #C1BCCC, 1.76:1 against the
    // group — plainly a hairline rather than a line, which is exactly what
    // the resting edge is everywhere else in this system. Pearl .22 over
    // #050713 gives #393946 and does the same job for the Twilight sample on
    // either page.
    canvas.drawRRect(
      rrect.deflate(.5),
      stroke..color = palette.ink.withValues(alpha: .22),
    );
  }

  @override
  bool shouldRepaint(_ThemeSpecimenPainter oldDelegate) =>
      oldDelegate.mode != mode ||
      oldDelegate.darkPalette != darkPalette ||
      oldDelegate.lightPalette != lightPalette;
}

/// The one switch shape in Settings.
///
/// Material, never `Switch.adaptive`: the Cupertino control consults none of
/// `SwitchThemeData` and shipped a 1.31:1 off state on paper. Padding drops to
/// zero because the Material 3 default centres a 52 pt track inside a 60 pt
/// box, which parked every switch 4 px inboard of the chevrons above and
/// below it — three trailing controls landing on three different right edges
/// down one screen. At zero the box is the track, the whole trailing column
/// lines up, and the target is still 52 by 48, over the 44 pt floor on both
/// axes.
class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.value,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final bool value;

  /// The setting's name. The row's own text is not part of the switch node,
  /// so without this a screen reader announces an unnamed toggle.
  final String semanticsLabel;
  final ValueChanged<bool>? onChanged;

  /// The height a [ExampleRow] lays out at when this is its trailing widget,
  /// at the default text scale. Above it the row grows with its text and
  /// this number stops describing it — see [_ExampleSettingsSkeleton].
  ///
  /// The zero padding above trims Material's 60 pt box to the 52 × 48 track,
  /// and 48 is taller than anything else in the row — the leading square is
  /// 40, and 40 plus `ExampleRow.defaultPadding`'s 8 above and below is
  /// exactly the 56 pt floor every other row rests on. A switch clears that
  /// floor: 48 and the same padding come to 64. Two rows in Settings carry
  /// one — Passkey and Private Mode — and [_ExampleSettingsSkeleton] reserves
  /// this for those two and 56 for the rest.
  static const double rowHeight = 48 + 2 * AppSpacing.xs;

  @override
  Widget build(BuildContext context) => Semantics(
        label: semanticsLabel,
        child: Switch(
          value: value,
          padding: EdgeInsets.zero,
          onChanged: onChanged,
        ),
      );
}

/// Settings while the account is still loading.
///
/// A spinner says nothing about a screen whose shape is entirely
/// predictable, so the loading state is the screen: the masthead at its real
/// proportions — plate radius, lift, the 26 px name band, the seam and the
/// protection meter — then the section labels and their rules, then the
/// groups at their real row counts, down to the sign-out group that closes
/// the page.
///
/// Inside one envelope nothing changes position when the data lands, and
/// `settings_masthead_test.dart` measures that rather than taking it on
/// trust: on the phone column at the default text scale it compares the top
/// and the height of the plate and of every group here against the loaded
/// one, and every delta is 0.0.
///
/// The envelope is part of the claim, because two things sit outside it and
/// neither is fixed here.
///
/// * **Above the default text scale the column still drifts.** [_band]
///   reserves a measured line box and does follow the ambient scale — the
///   plate holds to the pixel at 1.3 and at 2.0 — but a row is reserved at
///   the flat 56 or 64 below, and `ExampleSkeleton.row` treats that as a
///   minimum its contents have not reached by 2.0, so the placeholder holds
///   its resting height while the real [ExampleRow] grows with the text.
///   Measured at 375 wide: the sign-out row is reserved at 56 at every scale
///   and lands at 61 at 1.3 and 84 at 2.0, and the drift accumulated above it
///   leaves its group 50 pt below where it was reserved at 1.3 and 320 pt
///   below at 2.0.
/// * **Above 820 pt there is no shared layout to compare.** The loaded page
///   splits into a rail and one section at a time (the `LayoutBuilder` in
///   [_ExampleProfileContentState]); this skeleton has no desktop branch and
///   draws the phone column at whatever width it is handed. At a 900 pt
///   window it is five groups 860 wide against a loaded page of one group
///   586 wide.
///
/// Four things make it hold inside that envelope.
///
/// 1. **Bands reserve line boxes, not blocks.** `ExampleSkeleton.line` lays
///    out at exactly the height it paints, which is right for a free block
///    and wrong for a stand-in: a 26 px block is 4 pt short of the name's
///    30 pt line box and a 12 px one is 5 pt short of the email's 17, so the
///    plate itself used to grow as it loaded. [_band] centres the painted
///    block inside the real line box instead — the shape
///    `ExampleSkeleton.amount` already takes for a balance — and it asks the
///    text engine for that box rather than multiplying `fontSize * height`
///    out, which is a different number.
/// 2. **The meter is the meter.** Rather than drawing something the shape of
///    one, this renders the real [_ProtectionMeter] on an unknown reading,
///    which is literally the state that arrives next: a loaded screen whose
///    security summary is still in flight shows exactly this, down to the
///    "Checking…". It cannot be a pixel out, and it cannot drift when the
///    meter changes.
/// 3. **The row counts are the row counts.** Security is six rows, not five.
///    Preferences is Private Mode, the theme row *and* the specimen strip
///    under it, which is a second row plus about 101 pt — the largest single
///    error in the old skeleton. Account follows the same rewards flag the
///    loaded section reads. And the page ends with the sign-out group, which
///    the skeleton used to omit altogether.
/// 4. **A row is not one height.** Every row rests on `ExampleRow`'s 56 pt
///    floor except the two that carry a switch — Passkey and Private Mode —
///    which are 64, because a `Switch` keeps a 48 pt tap target (see
///    [_SettingsSwitch.rowHeight]). Drawing them all at 56 left Security and
///    Preferences 8 pt short each, so everything below Security moved 8 pt
///    and everything below Preferences 16 when the account landed.
///
/// Exactly one sheen host for the whole page. The law's ceiling is two or
/// three, and a column of twelve independently shimmering rows is the wallet
/// cliché this system exists to avoid; with no scope above, or under reduced
/// motion, the band is a static highlight and no ticker starts.
class _ExampleSettingsSkeleton extends StatelessWidget {
  const _ExampleSettingsSkeleton({required this.rewardsEnabled});

  /// The same flag the loaded Account section reads. It comes from the tenant
  /// config, which resolves independently of the dashboard, so the group is
  /// drawn at the row count that is actually coming rather than at a guess.
  final bool rewardsEnabled;

  /// The reading the plate is about to hold. The masthead's own read of
  /// `accountSecurityProvider` is in flight while this screen is up, so the
  /// meter's loading state *is* its next state — four inert segments and
  /// "Checking…" — and asking [_ProtectionReading] for it keeps the two in
  /// step for free.
  static final _ProtectionReading _loading = _ProtectionReading.resolve(
    security: const AsyncValue<AccountSecurity>.loading(),
    identityVerified: false,
    passkeyEnabled: false,
    passkeyOffered: true,
    biometricLabel: kIsWeb ? 'Passkey' : 'Biometrics',
  );

  /// The specimen label's metrics, which is all [_band] needs of a style.
  static const TextStyle _specimenLabel = TextStyle(
    fontSize: _ExampleAppearanceBlock.specimenLabelSize,
    height: _ExampleAppearanceBlock.specimenLabelLeading,
  );

  /// The height of a settings row whose tallest content is its own text:
  /// [ExampleRow]'s 56 pt floor, which is the height that row lays out at
  /// while the text scale is 1.0. The two rows that carry a switch stand
  /// taller — see [_SettingsSwitch.rowHeight].
  static const double _rowHeight = 56;

  /// One line of [style] stood in for: a [block]-tall placeholder centred in
  /// the line box that string will occupy, so the column holds still when the
  /// text replaces it.
  ///
  /// The line box is measured, not multiplied out. `fontSize * height` is not
  /// the number the engine reports: it lays the 11 px section label at 1.2
  /// out as 13.0 rather than 13.2, the 26 px name at 1.15 as 30.0 rather than
  /// 29.9, and the 12 px email at 1.4 as 17.0 rather than 16.8. Reserving the
  /// arithmetic left the plate 0.3 pt short and every section label 0.2 pt
  /// too tall, which the group-for-group test reads as movement.
  /// [TextPainter.preferredLineHeight] is the measurement `Text` itself will
  /// make of the same style, ambient text scale and all.
  static Widget _band(
    BuildContext context,
    TextStyle style, {
    required double block,
    double? width,
    double? widthFactor,
    AlignmentGeometry alignment = AlignmentDirectional.centerStart,
  }) {
    // `Text` merges what it is handed onto the ambient default before it
    // measures anything, so this does too.
    final painter = TextPainter(
      text: TextSpan(
        text: ' ',
        style: DefaultTextStyle.of(context).style.merge(style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );
    final lineBox = painter.preferredLineHeight;
    painter.dispose();
    return SizedBox(
      height: lineBox,
      child: Align(
        alignment: alignment,
        child: ExampleSkeleton.line(
          width: width,
          widthFactor: widthFactor,
          height: block,
          sheen: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hairline = ExampleBorders.hairlineSideOf(context).color;
    final label = ExampleTextStyles.label(context);

    Widget rule() => Expanded(
          child: SizedBox(height: 1, child: ColoredBox(color: hairline)),
        );

    // [height] is the height the row it stands in for lays out at, which is
    // not one number: pass [_SettingsSwitch.rowHeight] for a row whose
    // trailing slot holds a switch.
    List<Widget> settingsRows(int count, {double height = _rowHeight}) => [
          for (var i = 0; i < count; i++)
            ExampleSkeleton.row(
              height: height,
              avatarSize: 34,
              trailing: false,
            ),
        ];

    // Passkey in Security and Private Mode in Preferences, at the height a
    // switch gives them.
    List<Widget> switchRow() =>
        settingsRows(1, height: _SettingsSwitch.rowHeight);

    Widget section(List<Widget> children) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                children: [
                  _band(context, label, block: 11, width: 62),
                  const SizedBox(width: AppSpacing.sm),
                  rule(),
                ],
              ),
            ),
            ExampleListGroup(children: children),
          ],
        );

    // The three theme swatches, at the geometry `_ExampleAppearanceBlock`
    // names, so the strip occupies the space it is about to fill.
    Widget specimens() => Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: _ExampleAppearanceBlock.specimenMaxWidth,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < 3; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const AspectRatio(
                            aspectRatio: _ExampleAppearanceBlock.specimenAspect,
                            child: ExampleSkeleton(
                              radius: _ExampleAppearanceBlock.specimenRadius,
                              sheen: false,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          _band(
                            context,
                            _specimenLabel,
                            block: 10,
                            width: 34,
                            alignment: Alignment.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

    return Semantics(
      label: context.tr('Loading settings'),
      child: ExampleSheen.text(
        intensity: ExampleSheenIntensity.soft,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, AppSpacing.xs, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ExampleSurface.of(context, 1),
                  borderRadius: BorderRadius.circular(AppRadii.xl),
                  border: ExampleBorders.subtleOf(context),
                  boxShadow: ExampleShadows.liftOf(context),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The avatar is the tallest thing in this row in
                          // both states, so the pill's stand-in only has to
                          // sit inside it, not match it.
                          const Row(
                            children: [
                              ExampleSkeleton.avatar(size: 48, sheen: false),
                              Spacer(),
                              ExampleSkeleton.line(
                                width: 74,
                                height: 18,
                                sheen: false,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _band(
                            context,
                            _ExampleProfileHeader.nameStyleOf(context),
                            block: 26,
                            widthFactor: .58,
                          ),
                          const SizedBox(height: 2),
                          _band(
                            context,
                            _ExampleProfileHeader.emailStyleOf(context),
                            block: 12,
                            widthFactor: .44,
                          ),
                        ],
                      ),
                    ),
                    SizedBox(height: 1, child: ColoredBox(color: hairline)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.sm,
                        AppSpacing.md,
                        AppSpacing.md,
                      ),
                      child: _ProtectionMeter(reading: _loading),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              section(settingsRows(rewardsEnabled ? 4 : 3)),
              const SizedBox(height: AppSpacing.lg),
              // Passkey carries a switch and stands 8 pt taller than the
              // five chevron rows under it.
              section([...switchRow(), ...settingsRows(5)]),
              const SizedBox(height: AppSpacing.lg),
              // Match the privacy, appearance, and language rows, including
              // the dividers that the loaded preferences group draws.
              section([
                ...switchRow(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...settingsRows(1), specimens()],
                ),
                ...settingsRows(1),
              ]),
              const SizedBox(height: AppSpacing.lg),
              section(settingsRows(2)),
              const SizedBox(height: AppSpacing.lg),
              // Sign out stands in its own unlabelled group, and so does its
              // placeholder; leaving it out shortened the page by a group.
              ExampleListGroup(children: settingsRows(1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileContent extends StatelessWidget {
  const _ProfileContent({
    required this.snapshot,
    required this.supportEmail,
    required this.rewardsEnabled,
    required this.onEditNickname,
    required this.onEditProfile,
    required this.onSignOut,
  });

  final DashboardSnapshot snapshot;
  final String supportEmail;
  final bool rewardsEnabled;
  final VoidCallback onEditNickname;
  final VoidCallback onEditProfile;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;

        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 16, wide ? 32 : 20, 110),
          children: [
            _ProfileHeader(
              profile: snapshot.profile,
              onEditProfile: onEditProfile,
            ),
            if (!snapshot.profile.isKycReady || !snapshot.canUseBanking) ...[
              const SizedBox(height: AppSpacing.md),
              _ReadinessCard(
                profile: snapshot.profile,
                canUseBanking: snapshot.canUseBanking,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SectionHeader(title: context.tr('Account')),
            const SizedBox(height: AppSpacing.xs),
            NeoGroupedCard(
              children: [
                NeoSettingsRow(
                  icon: Icons.alternate_email,
                  title: context.tr('Nickname'),
                  subtitle: snapshot.profile.nickname == null
                      ? context.tr('Set your unique nickname') : '@${snapshot.profile.nickname}',
                  onTap: onEditNickname,
                ),
                NeoSettingsRow(
                  icon: Icons.person_outline_rounded,
                  title: context.tr('Personal details'),
                  subtitle: context.tr('Name and contact information'),
                  onTap: onEditProfile,
                ),
                NeoSettingsRow(
                  icon: Icons.verified_user_outlined,
                  title: context.tr('Identity verification'),
                  subtitle: friendlyStatus(snapshot.profile.kycStatus),
                  onTap: () => context.go(
                    snapshot.profile.isKycReady ? '/kyc/status' : '/kyc',
                  ),
                ),
                if (snapshot.profile.isBusinessAccount)
                  NeoSettingsRow(
                    icon: Icons.business_outlined,
                    title: context.tr('Business details'),
                    subtitle: friendlyStatus(snapshot.profile.businessStatus),
                    onTap: () => context.go('/business'),
                  ),
                if (rewardsEnabled)
                  NeoSettingsRow(
                    icon: Icons.card_giftcard_outlined,
                    title: context.tr('Rewards'),
                    subtitle: context.tr('Referrals and vouchers'),
                    onTap: () => context.go('/rewards'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _SettingsPanel(
              supportEmail: supportEmail,
              onSignOut: onSignOut,
            ),
          ],
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.profile,
    required this.onEditProfile,
  });

  final UserProfile profile;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeoSurfaceCard(
      onTap: onEditProfile,
      child: Row(
        children: [
          CircleAvatar(
            radius: 34,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.18),
            child: Text(
              _initials(profile.name),
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileDisplayName(profile),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  fallbackText(
                      profile.email, context.tr('Email not available')),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.profile,
    required this.canUseBanking,
  });

  final UserProfile profile;
  final bool canUseBanking;

  @override
  Widget build(BuildContext context) {
    final steps = [
      _ReadinessStep(
        label: context.tr('Identity'),
        status: profile.kycStatus,
        route: '/kyc',
        complete: profile.isKycReady,
      ),
      if (profile.isBusinessAccount)
        _ReadinessStep(
          label: context.tr('Business'),
          status: profile.businessStatus,
          route: '/business',
          complete: _isReadyStatus(profile.businessStatus),
        ),
      _ReadinessStep(
        label: context.tr('Banking'),
        status: canUseBanking ? 'active' : profile.onboardingStatus,
        route: '/onboarding/banking',
        complete: canUseBanking,
      ),
    ];
    final completed = steps.where((step) => step.complete).length;
    final progress = completed / steps.length;
    final theme = Theme.of(context);

    return NeoSurfaceCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Account readiness'),
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$completed/${steps.length}',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: progress,
              backgroundColor: theme.colorScheme.surface,
            ),
          ),
          const SizedBox(height: 16),
          for (final step in steps) _ReadinessRow(step: step),
        ],
      ),
    );
  }
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel({
    required this.supportEmail,
    required this.onSignOut,
  });

  final String supportEmail;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isExample = ref.watch(appConfigProvider).branding.isExample;
    final enrollmentAsync = ref.watch(biometricEnrollmentProvider);
    final capabilityAsync = ref.watch(biometricCapabilityProvider);
    final capability = capabilityAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final enrollment = enrollmentAsync.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final supportsBiometrics = capability?.available ?? false;
    final biometricLabel =
        kIsWeb ? 'Passkey' : capability?.describe() ?? 'Biometrics';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: isExample
              ? context.tr('Security & privacy')
              : context.tr('Preferences'),
        ),
        const SizedBox(height: AppSpacing.xs),
        NeoGroupedCard(
          children: [
            if (supportsBiometrics || enrollment?.enabled == true)
              SwitchListTile.adaptive(
                value:
                    enrollment?.enabled == true && enrollment?.hasToken == true,
                onChanged: (value) =>
                    _toggleBiometric(context, ref, value, biometricLabel),
                secondary: Icon(
                  capability?.hasFaceId == true
                      ? Icons.face_outlined
                      : Icons.fingerprint,
                ),
                title: Text(context.tr('{p0} sign-in', {'p0': biometricLabel})),
                subtitle: Text(
                  enrollment?.canUnlock == true
                      ? context.tr(
                          'Unlock the app with {p0}.', {'p0': biometricLabel})
                      : context.tr('Sign in faster with {p0} next time.',
                          {'p0': biometricLabel}),
                ),
              ),
            NeoSettingsRow(
              icon: Icons.notifications_none_rounded,
              title: context.tr('Notifications'),
              subtitle: context.tr('Account and security updates'),
              onTap: () => context.go('/notifications'),
            ),
            if (!isExample) const _ThemePreferenceTile(),
            const LanguagePicker(),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(title: context.tr('Support')),
        const SizedBox(height: AppSpacing.xs),
        NeoGroupedCard(
          children: [
            NeoSettingsRow(
              icon: Icons.support_agent_rounded,
              title: context.tr('Support tickets'),
              subtitle: context.tr('View requests and replies'),
              onTap: () => context.push('/support'),
            ),
            NeoSettingsRow(
              icon: Icons.policy_outlined,
              title: context.tr('Legal documents'),
              subtitle: context.tr('Registration and card agreements'),
              onTap: () => showLegalDocumentsSheet(context),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
              side: BorderSide(color: theme.colorScheme.error),
            ),
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: Text(context.tr('Sign out')),
          ),
        ),
      ],
    );
  }

  Future<void> _toggleBiometric(
    BuildContext context,
    WidgetRef ref,
    bool value,
    String biometricLabel,
  ) async {
    final controller = ref.read(authControllerProvider.notifier);
    if (!value) {
      await confirmBiometricReset(context, ref, biometricLabel);
      return;
    }
    // To enable from the profile screen the user must re-authenticate
    // biometrically right now — confirms presence and OS enrollment before
    // we persist the access token.
    final auth = ref.read(biometricAuthenticatorProvider);
    final result = await auth.authenticate(
      reason: 'Confirm to enable $biometricLabel sign-in',
    );
    if (result != BiometricAuthResult.success) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(context
                  .tr('{p0} sign-in not enabled.', {'p0': biometricLabel}))),
        );
      }
      return;
    }
    await controller.enableBiometricForCurrentSession();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                context.tr('{p0} sign-in enabled.', {'p0': biometricLabel}))),
      );
    }
  }
}

class _ReadinessRow extends StatelessWidget {
  const _ReadinessRow({required this.step});

  final _ReadinessStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor =
        step.complete ? theme.colorScheme.primary : theme.colorScheme.tertiary;

    return InkWell(
      onTap: () => context.go(step.route),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(
              step.complete ? Icons.check_circle : Icons.radio_button_unchecked,
              color: statusColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                step.label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              friendlyStatus(step.status),
              style: theme.textTheme.labelLarge?.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadinessStep {
  const _ReadinessStep({
    required this.label,
    required this.status,
    required this.route,
    required this.complete,
  });

  final String label;
  final String status;
  final String route;
  final bool complete;
}

/// Identity details come from KYC, so they are shown read-only; changes go
/// through support rather than an in-app edit form.
Future<void> _showPersonalDetails(
  BuildContext context,
  UserProfile profile,
  String supportEmail,
) {
  String orDash(String value) => value.trim().isEmpty ? '—' : value.trim();
  final verified = profile.isKycReady;

  return showExampleSheet<void>(
    context,
    scrollable: false,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExampleSheetHeader(title: context.tr('Personal details')),
        const SizedBox(height: AppSpacing.md),
        ExampleListGroup(
          children: [
            ExampleRow(
              leading: const ExampleIconTile(
                icon: Icons.badge_outlined,
                color: ExampleColors.iris,
              ),
              title: orDash(profile.name),
              subtitle: context.tr('Name'),
            ),
            ExampleRow(
              leading: const ExampleIconTile(
                icon: Icons.alternate_email_rounded,
                color: ExampleColors.iris,
              ),
              title: orDash(profile.email),
              titleMaxLines: null,
              subtitle: context.tr('Email'),
            ),
            ExampleRow(
              leading: const ExampleIconTile(
                icon: Icons.account_balance_outlined,
                color: ExampleColors.iris,
              ),
              title: profile.isBusinessAccount
                  ? context.tr('Business')
                  : context.tr('Personal'),
              subtitle: context.tr('Account type'),
            ),
            ExampleRow(
              leading: ExampleIconTile(
                icon: Icons.verified_user_outlined,
                color: verified ? ExampleColors.success : ExampleColors.warning,
              ),
              title: verified
                  ? context.tr('Verified')
                  : friendlyStatus(profile.kycStatus),
              subtitle: context.tr('Verification'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ExampleSheetNote(
          context.tr(
              'Your name and email are verified during identity checks. To change them, open a support ticket from Settings.'),
        ),
      ],
    ),
  );
}

Future<void> _showProfileDialog(
  BuildContext context,
  WidgetRef ref,
  String currentName,
  String currentEmail,
) async {
  final nameController = TextEditingController(text: currentName);
  final emailController = TextEditingController(text: currentEmail);
  final result = await showDialog<(String, String)>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr('Update profile')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: nameController,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: context.tr('Name')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: context.tr('Email')),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            (nameController.text.trim(), emailController.text.trim()),
          ),
          child: Text(context.tr('Save')),
        ),
      ],
    ),
  );

  nameController.dispose();
  emailController.dispose();
  if (result == null) {
    return;
  }

  await ref.read(mobilePlatformApiProvider).updateProfile(
        name: result.$1,
        email: result.$2,
      );
  ref.invalidate(dashboardProvider);
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return '?';
  }
  if (parts.length == 1) {
    return parts.first.characters.first.toUpperCase();
  }

  return '${parts.first.characters.first}${parts.last.characters.first}'
      .toUpperCase();
}

String _profileDisplayName(UserProfile profile) {
  final name = profile.name.trim();
  if (name.isEmpty || name == 'User') {
    return 'Name not available';
  }

  return name;
}

bool _isReadyStatus(String value) {
  final normalized = value.toLowerCase().replaceAll('_', '-').trim();
  return normalized == 'approved' ||
      normalized == 'verified' ||
      normalized == 'complete' ||
      normalized == 'completed' ||
      normalized == 'active' ||
      normalized == 'ready';
}

class _ThemePreferenceTile extends ConsumerWidget {
  const _ThemePreferenceTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(themePreferenceProvider);
    final current = preference.maybeWhen(
      data: (value) => value,
      orElse: () => null,
    );
    final label = context.tr(_labelFor(current));
    final icon = _iconFor(current);

    return NeoSettingsRow(
      icon: icon,
      title: context.tr('Appearance'),
      subtitle: label,
      onTap: () => _openSheet(context, ref, current),
    );
  }

  Future<void> _openSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode? current,
  ) async {
    final selection = await showModalBottomSheet<_ThemeChoice>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                context.tr('Appearance'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle:
                  Text(context.tr('Choose how the app looks on this device.')),
            ),
            RadioGroup<_ThemeChoice>(
              groupValue: _ThemeChoice.fromMode(current),
              onChanged: (value) => Navigator.of(sheetContext).pop(value),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final choice in _choices)
                    RadioListTile<_ThemeChoice>(
                      value: choice,
                      title: Text(context.tr(choice.title)),
                      subtitle: Text(context.tr(choice.subtitle)),
                      secondary: Icon(choice.icon),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selection != null) {
      await ref.read(themePreferenceProvider.notifier).setMode(selection.mode);
    }
  }

  static String _labelFor(ThemeMode? mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Light';
      case ThemeMode.dark:
        return 'Dark';
      case ThemeMode.system:
        return 'Match system';
      case null:
        return 'Automatic (brand default)';
    }
  }

  static IconData _iconFor(ThemeMode? mode) {
    switch (mode) {
      case ThemeMode.light:
        return Icons.light_mode_outlined;
      case ThemeMode.dark:
        return Icons.dark_mode_outlined;
      case ThemeMode.system:
      case null:
        return Icons.brightness_auto_outlined;
    }
  }
}

class _ThemeChoice {
  const _ThemeChoice({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final ThemeMode? mode;
  final String title;
  final String subtitle;
  final IconData icon;

  static _ThemeChoice fromMode(ThemeMode? mode) {
    return _choices.firstWhere(
      (choice) => choice.mode == mode,
      orElse: () => _choices.first,
    );
  }
}

const List<_ThemeChoice> _choices = [
  _ThemeChoice(
    mode: null,
    title: 'Automatic',
    subtitle: 'Use the brand default for this app.',
    icon: Icons.brightness_auto_outlined,
  ),
  _ThemeChoice(
    mode: ThemeMode.system,
    title: 'Match system',
    subtitle: 'Switches with iOS / Android settings.',
    icon: Icons.phone_iphone,
  ),
  _ThemeChoice(
    mode: ThemeMode.light,
    title: 'Light',
    subtitle: 'Bright surfaces and dark text.',
    icon: Icons.light_mode_outlined,
  ),
  _ThemeChoice(
    mode: ThemeMode.dark,
    title: 'Dark',
    subtitle: 'Reduced glare in low-light settings.',
    icon: Icons.dark_mode_outlined,
  ),
];

/// Live sessions for the account with per-device sign-out. Revoking the
/// current device signs the app out locally as well.
Future<void> _showDevicesSheet(BuildContext context, WidgetRef ref) {
  String when(DateTime? value) {
    if (value == null) return 'Unknown';
    final diff = DateTime.now().difference(value);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inDays < 7) return '${diff.inDays} d ago';
    return '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
  }

  bool isLaptop(String name) {
    final lower = name.toLowerCase();
    return lower.contains('web') ||
        lower.contains('mac') ||
        lower.contains('windows');
  }

  return showExampleSheet<void>(
    context,
    scrollable: false,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final sessions = ref.watch(authSessionsProvider);

        Future<void> revoke(AuthDeviceSession session) async {
          try {
            await ref.read(authApiProvider).revokeSession(session.id);
            if (session.isCurrent) {
              if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              await ref.read(authControllerProvider.notifier).logout();
              return;
            }
            ref.invalidate(authSessionsProvider);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyErrorMessage(error))),
              );
            }
          }
        }

        Future<void> revokeOthers() async {
          try {
            await ref.read(authApiProvider).revokeOtherSessions();
            ref.invalidate(authSessionsProvider);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(context.tr('Other devices signed out.'))),
              );
            }
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(friendlyErrorMessage(error))),
              );
            }
          }
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExampleSheetHeader(
              title: context.tr('Devices & sessions'),
              actions: [
                IconButton(
                  tooltip: context.tr('Refresh'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => ref.invalidate(authSessionsProvider),
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: ExampleInk.secondary(context),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            ExampleSheetNote(
              context.tr(
                  'Every device that can open your account. Sign out any you do not recognise.'),
            ),
            const SizedBox(height: AppSpacing.md),
            Flexible(
              child: ExampleStateSwitch(
                child: sessions.when(
                  data: (items) => items.isEmpty
                      // A sentence in a note is what a screen shows when
                      // nobody designed the empty case. The list gets the
                      // designed one — the same glyph, title and body
                      // composition as every other empty state in the
                      // product, compact because it lives in a sheet.
                      ? Padding(
                          key: const ValueKey('empty'),
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.xs),
                          child: ExampleEmptyState(
                            compact: true,
                            icon: Icons.devices_other_rounded,
                            title: context.tr('No sessions to show'),
                            body: context.tr(
                                'Your account has no other active sessions right now.'),
                          ),
                        )
                      : SingleChildScrollView(
                          key: const ValueKey('sessions'),
                          child: ExampleListGroup(
                            children: [
                              for (final session in items)
                                ExampleRow(
                                  leading: ExampleIconTile(
                                    icon: isLaptop(session.deviceName)
                                        ? Icons.laptop_mac_rounded
                                        : Icons.phone_iphone_rounded,
                                    color: session.isCurrent
                                        ? ExampleColors.success
                                        : ExampleColors.iris,
                                  ),
                                  title: session.deviceName,
                                  subtitle: [
                                    if (session.isCurrent) 'This device',
                                    'Active ${when(session.lastUsedAt ?? session.createdAt)}',
                                    if ((session.ipAddress ?? '').isNotEmpty)
                                      session.ipAddress!,
                                  ].join(' · '),
                                  trailing: _SessionRevokeButton(
                                    label: session.isCurrent
                                        ? context.tr('Sign out')
                                        : context.tr('Revoke'),
                                    semanticsLabel: context.tr('Sign out {p0}',
                                        {'p0': session.deviceName}),
                                    onPressed: () => revoke(session),
                                  ),
                                ),
                            ],
                          ),
                        ),
                  // The caution note could not be retried and was not
                  // announced. The shared error state is a live region and
                  // carries the one action that actually helps.
                  error: (error, stackTrace) => Padding(
                    key: const ValueKey('error'),
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: ExampleErrorState(
                      compact: true,
                      title: context.tr('Devices could not load'),
                      error: error,
                      onRetry: () => ref.invalidate(authSessionsProvider),
                    ),
                  ),
                  // The list loads into the shape of the list: one sheen
                  // host for the whole block, never one per row.
                  loading: () => Semantics(
                    key: const ValueKey('loading'),
                    label: context.tr('Loading devices'),
                    child: ExampleSheen.text(
                      intensity: ExampleSheenIntensity.soft,
                      child: ExampleListGroup(
                        children: [
                          for (var i = 0; i < 3; i++)
                            const ExampleSkeleton.row(
                              height: 56,
                              avatarSize: 34,
                              trailing: false,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if ((sessions.valueOrNull?.length ?? 0) > 1) ...[
              const SizedBox(height: AppSpacing.md),
              ExampleSheetCta(
                label: context.tr('Sign out other devices'),
                tone: ExampleSheetCtaTone.danger,
                onPressed: revokeOthers,
              ),
            ],
          ],
        );
      },
    ),
  );
}

/// The per-row revoke control. A [TextButton] alone is 36 pt tall and its ink
/// is the scheme primary; this holds the 44 pt floor, carries danger on the
/// label only, and names the device it acts on for a screen reader.
class _SessionRevokeButton extends StatelessWidget {
  const _SessionRevokeButton({
    required this.label,
    required this.semanticsLabel,
    required this.onPressed,
  });

  final String label;
  final String semanticsLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ExamplePressable(
      onTap: onPressed,
      pressedScale: .96,
      semanticsLabel: semanticsLabel,
      borderRadius: BorderRadius.circular(AppRadii.xs),
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ExampleInk.accent(context, ExampleColors.danger),
          ),
        ),
      ),
    );
  }
}
