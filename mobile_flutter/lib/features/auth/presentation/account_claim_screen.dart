import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../brands/example/example_glass_button.dart';
import '../../../brands/example/example_sheen.dart';
import '../../../brands/example/example_tokens.dart';
import '../../../brands/example/example_ui.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/api/dio_provider.dart';
import '../../../shared/theme/app_theme_extensions.dart';
import 'example_auth_field.dart' show exampleControlEdge;
import '../application/auth_providers.dart';
import '../data/auth_api.dart';
import '../../signup/presentation/password_strength_checklist.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class AccountClaimScreen extends ConsumerStatefulWidget {
  const AccountClaimScreen({super.key});

  @override
  ConsumerState<AccountClaimScreen> createState() => _AccountClaimScreenState();
}

class _AccountClaimScreenState extends ConsumerState<AccountClaimScreen> {
  static const _accountLinkPollInterval = Duration(seconds: 16);

  final _emailKey = GlobalKey<FormState>();
  final _verifyKey = GlobalKey<FormState>();
  final _accountLinkPasswordKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _passwordSubmitted = false;
  AccountClaimChallenge? _challenge;
  AccountLinkSession? _accountLink;
  Timer? _accountLinkPollTimer;
  bool _accountLinkPollInFlight = false;
  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  String get _brandName => ref.read(appConfigProvider).branding.appName;
  String get _dashboardUrl =>
      ref.read(appConfigProvider).branding.transferDashboardUrl;

  /// The show / hide eye every password field on this screen carries, so a
  /// customer can check what they typed before it becomes their password.
  Widget _eye({required bool obscured, required VoidCallback onTap}) =>
      IconButton(
        tooltip: obscured
            ? context.tr('Show password')
            : context.tr('Hide password'),
        onPressed: onTap,
        icon: Icon(
          obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
      );

  @override
  void dispose() {
    _accountLinkPollTimer?.cancel();
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (context.isExampleTheme) return _buildExample(theme);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Connect existing account')),
        leading: IconButton(
          onPressed: _busy ? null : () => context.go('/login'),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: _accountLink != null
                        ? _accountLinkStep(theme)
                        : _challenge == null
                            ? _emailStep(theme)
                            : _verificationStep(theme),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExample(ThemeData theme) {
    final showingEmail = _accountLink == null && _challenge == null;
    final showingVerification = _accountLink == null && _challenge != null;
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    if (desktop && showingEmail) {
      // One scope per screen: the headline lives in the body and the CTA in
      // the bottom bar, so the scope sits above the Scaffold.
      return _sheenScope(
          context,
          ExampleGlow(
            desktop: true,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: SafeArea(
                child: Column(
                  children: [
                    Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: _claimHairline(context)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const ExampleLockup(height: 24),
                          const Spacer(),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: ExampleInk.primary(context),
                            ),
                            onPressed:
                                _busy ? null : () => context.go('/login'),
                            child: Text(context.tr('Back to sign in')),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(32, 56, 32, 48),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: _exampleDesktopEmailStep(theme),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ));
    }
    return _sheenScope(
        context,
        ExampleGlow(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              centerTitle: true,
              title: Text(context.tr('Connect existing account')),
              leading: IconButton(
                onPressed: _busy ? null : () => context.go('/login'),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
              ),
            ),
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 430),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(23, 16, 23, 112),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _accountLink != null
                          ? _accountLinkStep(theme)
                          : showingEmail
                              ? _exampleEmailStep(theme)
                              : _exampleVerificationStep(theme),
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: _accountLink != null
                ? null
                : SafeArea(
                    top: false,
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: Container(
                          color: Colors.transparent,
                          padding: const EdgeInsets.fromLTRB(23, 12, 23, 10),
                          child: SizedBox(
                            height: 50,
                            child: showingVerification
                                // Primary action of the verification step.
                                ? ExampleSheen(
                                    intensity: ExampleSheenIntensity.onFill,
                                    borderRadius: BorderRadius.circular(
                                      context.brandShape.radius(AppRadii.md),
                                    ),
                                    child: FilledButton.icon(
                                      onPressed: _busy ? null : _complete,
                                      icon: _busy
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: AppProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(Icons.link_rounded,
                                              size: 18),
                                      label:
                                          Text(context.tr('Connect account')),
                                    ),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: _busy ? null : _requestCode,
                                    icon: _busy
                                        ? const SizedBox.square(
                                            dimension: 18,
                                            child: AppProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.mark_email_read_outlined,
                                            size: 18,
                                          ),
                                    label: Text(
                                        context.tr('Send verification code')),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ));
  }

  /// D10 "Desktop Connect account": hero, then the QR and email options as
  /// two side-by-side cards.
  Widget _exampleDesktopEmailStep(ThemeData theme) => Form(
        key: _emailKey,
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _claimTile(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.verified_user_outlined,
                color: ExamplePalette.of(context).accent,
                size: 22,
              ),
            ),
            const SizedBox(height: 16),
            // The one shining headline of the desktop connect screen, and the
            // one line on it that earns display type. It was set at 22 px in a
            // 720 px column — the "small line over a list of panels" the
            // competitive read scored us down on, and under the 36 px the
            // nearest competitor heads its equivalent with. The ramp's ceiling
            // is the answer here rather than the 64 px auth tier: the brand
            // name is interpolated, so the line must be free to wrap to two
            // centred lines instead of being pushed toward a truncation it can
            // never take. Mobile keeps its own 22 px step, untouched.
            ExampleSheen.text(
              intensity: ExampleSheenIntensity.soft,
              child: Text(
                context.tr('Already registered with {p0}?', {'p0': _brandName}),
                textAlign: TextAlign.center,
                style: theme.textTheme.displayLarge,
              ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                context.tr(
                    'Scan a one-time QR from {p0} Security — the fastest option. You can also verify with your account email.',
                    {'p0': _brandName}),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _claimInk(context, .62),
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 32),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: ExampleGlassPanel(
                      radius: 22,
                      emphasis: true,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              // A QR is dark modules on a light ground in both
                              // themes; on paper the pearl tile needs its own
                              // hairline or it dissolves into the panel.
                              color: ExampleColors.pearl,
                              borderRadius: BorderRadius.circular(14),
                              border: ExampleTheme.isLight(context)
                                  ? Border.fromBorderSide(
                                      ExampleBorders.subtleSideOf(context),
                                    )
                                  : null,
                            ),
                            child: const Icon(
                              Icons.qr_code_2_rounded,
                              size: 64,
                              color: ExampleColors.night,
                            ),
                          ),
                          const SizedBox(height: 18),
                          Text(
                            context.tr(
                                'Scan {p0} transfer QR', {'p0': _brandName}),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ExampleInk.primary(context),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.tr(
                                'Open {p0} Security on your phone and point it at this code.',
                                {'p0': _brandName}),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.4,
                              color: _claimInk(context, .62),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // Primary action of the desktop step, in the glass
                          // material. It takes the plain ground even though
                          // the screen has a glow: the button is already
                          // inside a frosted panel, and a second bounded blur
                          // over the first only greys the fill without adding
                          // any depth the eye can read.
                          ExampleGlassButton(
                            label: context.tr('Scan with camera'),
                            icon: Icons.qr_code_scanner_rounded,
                            sheen: true,
                            loading: _busy,
                            radius: context.brandShape.radius(AppRadii.md),
                            onPressed: _busy ? null : _scanAccountLink,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            context.tr('Recommended · No email code required'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: ExamplePalette.of(context).success,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _TransferQrInstructions(
                            brandName: _brandName,
                            dashboardUrl: _dashboardUrl,
                            example: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ExampleGlassPanel(
                      radius: 22,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            context.tr('Or verify by email'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: ExampleInk.primary(context),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            context
                                .tr('{p0} account email', {'p0': _brandName}),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: _claimInk(context, .70),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextFormField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            autofillHints: const [AutofillHints.email],
                            decoration: InputDecoration(
                              hintText: context.tr('name@example.com'),
                              prefixIcon:
                                  const Icon(Icons.mail_outline, size: 18),
                            ),
                            validator: (value) =>
                                (value?.trim().contains('@') ?? false)
                                    ? null
                                    : 'Enter a valid email',
                          ),
                          const Spacer(),
                          const SizedBox(height: 18),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _requestCode,
                            icon: _busy
                                ? const SizedBox.square(
                                    dimension: 18,
                                    child: AppProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.mark_email_read_outlined,
                                    size: 18),
                            label: Text(context.tr('Send verification code')),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _exampleEmailStep(ThemeData theme) => Form(
        key: _emailKey,
        child: Column(
          key: const ValueKey('example-email'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: _claimTile(context),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.verified_user_outlined,
                  color: ExamplePalette.of(context).accent,
                ),
              ),
            ),
            const SizedBox(height: 17),
            // The one shining headline of the mobile connect step. The Align
            // keeps the sweep tight to the glyphs instead of spanning the
            // stretched column.
            Align(
              child: ExampleSheen.text(
                intensity: ExampleSheenIntensity.soft,
                child: Text(
                  context
                      .tr('Already registered with {p0}?', {'p0': _brandName}),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                  'Scan a one-time QR from {p0} Security — the fastest option. You can also verify with your account email.',
                  {'p0': _brandName}),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _claimInk(context, .62),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 23),
            // Primary action of this step, in the glass material. The screen
            // is wrapped in a ExampleGlow, so the bounded blur has real light
            // under it and the button reads as a lit object rather than a
            // violet slab. The bar at the bottom carries the secondary email
            // route, so exactly one button on screen shines.
            ExampleGlassButton(
              label: context.tr('Scan {p0} transfer QR', {'p0': _brandName}),
              icon: Icons.qr_code_scanner_rounded,
              ground: ExampleGlassGround.atmosphere,
              sheen: true,
              loading: _busy,
              height: 50,
              radius: context.brandShape.radius(AppRadii.md),
              onPressed: _busy ? null : _scanAccountLink,
            ),
            const SizedBox(height: 7),
            Text(
              context.tr('Recommended · No email code required'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ExamplePalette.of(context).success,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _TransferQrInstructions(
              brandName: _brandName,
              dashboardUrl: _dashboardUrl,
              example: true,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    context.tr('or verify by email'),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _claimInk(context, .44),
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              context.tr('{p0} account email', {'p0': _brandName}),
              style: theme.textTheme.labelMedium?.copyWith(
                color: _claimInk(context, .70),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                hintText: context.tr('name@example.com'),
                prefixIcon: const Icon(Icons.mail_outline, size: 18),
              ),
              validator: (value) => (value?.trim().contains('@') ?? false)
                  ? null
                  : 'Enter a valid email',
            ),
          ],
        ),
      );

  Widget _exampleVerificationStep(ThemeData theme) => Form(
        key: _verifyKey,
        child: Column(
          key: const ValueKey('example-verification'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The one shining headline of the verification step.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ExampleSheen.text(
                intensity: ExampleSheenIntensity.soft,
                child: Text(
                  context.tr('Check your email'),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _challenge!.message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _claimInk(context, .62),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('Six-digit code'),
              style: theme.textTheme.labelMedium?.copyWith(
                color: _claimInk(context, .70),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            _ExampleOtpField(controller: _code),
            const SizedBox(height: 18),
            _ExampleClaimField(
              label: context.tr('Create app password'),
              controller: _password,
              obscureText: _obscurePassword,
              validator: _passwordError,
              onChanged: (_) => setState(() {}),
              suffixIcon: _eye(
                obscured: _obscurePassword,
                onTap: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
            const SizedBox(height: 10),
            PasswordStrengthChecklist(
              password: _password.text,
              showErrors: _passwordSubmitted,
            ),
            const SizedBox(height: 14),
            _ExampleClaimField(
              label: context.tr('Confirm password'),
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match',
              suffixIcon: _eye(
                obscured: _obscureConfirm,
                onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton(
                onPressed:
                    _busy ? null : () => setState(() => _challenge = null),
                child: Text(context.tr('Use a different email')),
              ),
            ),
          ],
        ),
      );

  Widget _emailStep(ThemeData theme) => Form(
        key: _emailKey,
        child: Column(
          key: const ValueKey('email'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.verified_user_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
                context.tr('Already registered with {p0}?', {'p0': _brandName}),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                  'The fastest option is to scan a one-time QR from {p0} Security. You can also verify with the email on your {p1} account.',
                  {'p0': _brandName, 'p1': _brandName}),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _scanAccountLink,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label:
                  Text(context.tr('Scan {p0} transfer QR', {'p0': _brandName})),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr('Recommended · No email code required'),
              textAlign: TextAlign.center,
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: AppSpacing.md),
            _TransferQrInstructions(
              brandName: _brandName,
              dashboardUrl: _dashboardUrl,
              example: false,
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Text(context.tr('or verify by email'),
                      style: theme.textTheme.labelMedium),
                ),
                const Expanded(child: Divider()),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: InputDecoration(
                labelText: context.tr('{p0} account email', {'p0': _brandName}),
                prefixIcon: const Icon(Icons.mail_outline),
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                return text.contains('@')
                    ? null
                    : context.tr('Enter a valid email');
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _requestCode,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.mark_email_read_outlined),
              label: Text(context.tr('Send verification code')),
            ),
          ],
        ),
      );

  Widget _verificationStep(ThemeData theme) => Form(
        key: _verifyKey,
        child: Column(
          key: const ValueKey('verification'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('Check your email'),
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            Text(_challenge!.message,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _code,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                labelText: context.tr('Six-digit code'),
                prefixIcon: const Icon(Icons.pin_outlined),
              ),
              validator: (value) =>
                  value?.length == 6 ? null : 'Enter all 6 digits',
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.tr('Create app password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: _eye(
                  obscured: _obscurePassword,
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: _passwordError,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordStrengthChecklist(
              password: _password.text,
              showErrors: _passwordSubmitted,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.tr('Confirm password'),
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: _eye(
                  obscured: _obscureConfirm,
                  onTap: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match',
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _complete,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded),
              label: Text(context.tr('Connect account')),
            ),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _challenge = null),
              child: Text(context.tr('Use a different email')),
            ),
          ],
        ),
      );

  Widget _accountLinkStep(ThemeData theme) {
    final accountLink = _accountLink!;
    final isWaiting = accountLink.status == 'PENDING_SCAN' ||
        accountLink.status == 'AWAITING_APPROVAL';

    if (isWaiting) {
      final secondsLeft = accountLink.expiresAt
          .difference(DateTime.now())
          .inSeconds
          .clamp(0, 300);
      return Column(
        key: const ValueKey('account-link-waiting'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.phonelink_lock_rounded,
              size: 52, color: theme.colorScheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            context.tr('Approve in {p0}', {'p0': _brandName}),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.tr(
                'Return to {p0} Security, confirm this app and device, then tap “Approve app access”. This screen will continue automatically.',
                {'p0': _brandName}),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.lg),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: .35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 22,
                    child: AppProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      context.tr('Waiting for approval · {p0}:{p1}', {
                        'p0': secondsLeft ~/ 60,
                        'p1': (secondsLeft % 60).toString().padLeft(2, '0')
                      }),
                      style: theme.textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: _busy ? null : _resetAccountLink,
            child: Text(context.tr('Cancel and scan again')),
          ),
        ],
      );
    }

    if (accountLink.status == 'APPROVED') {
      return Form(
        key: _accountLinkPasswordKey,
        child: Column(
          key: const ValueKey('account-link-approved'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.verified_rounded,
                size: 52, color: theme.colorScheme.primary),
            const SizedBox(height: AppSpacing.md),
            Text(
              context.tr('Access approved'),
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              context.tr(
                  'Create a password for this app. Your {p0} password is never shared or changed.',
                  {'p0': _brandName}),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _password,
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.tr('Create app password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: _eye(
                  obscured: _obscurePassword,
                  onTap: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: _passwordError,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordStrengthChecklist(
              password: _password.text,
              showErrors: _passwordSubmitted,
              dark: Theme.of(context).brightness == Brightness.dark,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _confirmPassword,
              obscureText: _obscureConfirm,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: context.tr('Confirm password'),
                prefixIcon: const Icon(Icons.lock_reset_outlined),
                suffixIcon: _eye(
                  obscured: _obscureConfirm,
                  onTap: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (value) =>
                  value == _password.text ? null : 'Passwords do not match',
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: _busy ? null : _completeAccountLink,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: AppProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.link_rounded),
              label: Text(context.tr('Finish connecting account')),
            ),
          ],
        ),
      );
    }

    return Column(
      key: const ValueKey('account-link-ended'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.link_off_rounded, size: 52, color: theme.colorScheme.error),
        const SizedBox(height: AppSpacing.md),
        Text(
          accountLink.status == 'DENIED'
              ? context.tr('Request denied')
              : context.tr('Transfer QR expired'),
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          context.tr(
              'No account access was granted. Generate a new QR in {p0} Security and try again.',
              {'p0': _brandName}),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          onPressed: _resetAccountLink,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: Text(context.tr('Scan a new QR')),
        ),
      ],
    );
  }

  Future<void> _scanAccountLink() async {
    final qrPayload = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => _AccountLinkScannerPage(
          brandName: _brandName,
          dashboardUrl: _dashboardUrl,
        ),
      ),
    );
    if (!mounted || qrPayload == null) return;

    setState(() => _busy = true);
    try {
      final session = await ref.read(authApiProvider).scanAccountLink(
            qrPayload: qrPayload,
            deviceName:
                kIsWeb ? 'Web browser' : '${defaultTargetPlatform.name} device',
          );
      if (!mounted) return;
      setState(() => _accountLink = session);
      _startAccountLinkPolling();
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startAccountLinkPolling() {
    _accountLinkPollTimer?.cancel();
    _accountLinkPollTimer = Timer.periodic(
      _accountLinkPollInterval,
      (_) => _refreshAccountLinkStatus(),
    );
  }

  Future<void> _refreshAccountLinkStatus() async {
    final current = _accountLink;
    if (current == null || current.isTerminal || _accountLinkPollInFlight) {
      return;
    }

    _accountLinkPollInFlight = true;
    try {
      final refreshed =
          await ref.read(authApiProvider).getAccountLinkStatus(current);
      if (!mounted || _accountLink?.challengeId != refreshed.challengeId) {
        return;
      }
      setState(() => _accountLink = refreshed);
      if (refreshed.status == 'APPROVED' || refreshed.isTerminal) {
        _accountLinkPollTimer?.cancel();
      }
    } on DioException catch (error) {
      // Hoppa deliberately rate-limits this read-only status endpoint. A 429
      // is transient and must not terminate an otherwise valid QR session.
      if (error.response?.statusCode == 429) return;
      _accountLinkPollTimer?.cancel();
      _showError(error);
    } catch (error) {
      _accountLinkPollTimer?.cancel();
      _showError(error);
    } finally {
      _accountLinkPollInFlight = false;
    }
  }

  Future<void> _completeAccountLink() async {
    if (!_validatePasswordStep(_accountLinkPasswordKey)) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).completeAccountLink(
            token: _accountLink!.token,
            password: _password.text,
          );
      if (!mounted) return;
      await _showAccountConnectedDialog();
      if (mounted) context.go('/login');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _resetAccountLink() {
    _accountLinkPollTimer?.cancel();
    _password.clear();
    _confirmPassword.clear();
    setState(() => _accountLink = null);
  }

  Future<void> _requestCode() async {
    if (!_emailKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final challenge =
          await ref.read(authApiProvider).requestAccountClaim(_email.text);
      if (mounted) setState(() => _challenge = challenge);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete() async {
    if (!_validatePasswordStep(_verifyKey)) return;
    setState(() => _busy = true);
    try {
      await ref.read(authApiProvider).completeAccountClaim(
            email: _email.text,
            challengeId: _challenge!.id,
            code: _code.text,
            password: _password.text,
          );
      if (!mounted) return;
      await _showAccountConnectedDialog();
      if (mounted) context.go('/login');
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showAccountConnectedDialog() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.check_circle_outline),
          title: Text(context.tr('Account connected')),
          content: Text(context.tr(
              'Your {p0} data is now linked. Sign in with the password you just created.',
              {'p0': _brandName})),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.tr('Continue to sign in')),
            ),
          ],
        ),
      );

  /// Validates a password step and switches the checklist into error mode
  /// so unmet rules are highlighted.
  bool _validatePasswordStep(GlobalKey<FormState> key) {
    setState(() => _passwordSubmitted = true);
    return key.currentState?.validate() ?? false;
  }

  String? _passwordError(String? value) {
    final password = value ?? '';
    if (passwordMeetsPolicy(password)) return null;
    final missing = passwordRules
        .where((rule) => !rule.test(password))
        .map((rule) => rule.label.toLowerCase());
    return context.tr('Still needed: {p0}', {'p0': missing.join(', ')});
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyErrorMessage(error))),
    );
  }
}

/// One scope for the screen, unless a shell above already runs one: two
/// scopes would mean two tickers and two unrelated rhythms.
Widget _sheenScope(BuildContext context, Widget child) =>
    !ExampleSheenScope.existsAbove(context)
        ? ExampleSheenScope(child: child)
        : child;

/// Secondary and tertiary ink on the Example-only connect surfaces.
///
/// The Twilight values here are ad-hoc pearl alphas (.44 to .78) rather than
/// the named [ExampleColors.textSecondary] and [ExampleColors.textTertiary], so
/// the dark branch keeps the exact literal each line shipped with and only
/// daylight resolves: night .72 for a body voice, night .50 for a quiet one.
Color _claimInk(BuildContext context, double darkAlpha) => ExampleTheme.pick(
      context,
      dark: context.brandDesign
          .color(Theme.of(context).brightness, 'ink',
              fallback: ExampleColors.pearl)
          .withValues(alpha: darkAlpha),
      light: darkAlpha >= .6
          ? context.brandDesign.color(
              Theme.of(context).brightness, 'textSecondary',
              fallback: ExampleColors.lightTextSecondary)
          : context.brandDesign.color(
              Theme.of(context).brightness, 'textTertiary',
              fallback: ExampleColors.lightTextTertiary),
    );

/// The tinted square behind the step badge icon.
Color _claimTile(BuildContext context) => ExampleTheme.pick(
      context,
      dark: context.brandDesign
          .color(Theme.of(context).brightness, 'surfaceHigh',
              fallback: ExampleColors.darkSurfaceHigh)
          .withValues(alpha: .62),
      light: context.brandDesign.color(
          Theme.of(context).brightness, 'surfaceHigh',
          fallback: ExampleColors.lightSurfaceHigh),
    );

/// The structural hairline under the desktop header bar — a rule, not a
/// control, so it keeps the daylight lavender hairline.
Color _claimHairline(BuildContext context) => ExampleTheme.pick(
      context,
      dark: context.brandDesign
          .color(Theme.of(context).brightness, 'accent',
              fallback: ExampleColors.lavender)
          .withValues(alpha: .10),
      light: context.brandDesign.color(
          Theme.of(context).brightness, 'borderSubtle',
          fallback: ExampleColors.lightBorderSubtle),
    );

class _ExampleClaimField extends StatelessWidget {
  const _ExampleClaimField({
    required this.label,
    required this.controller,
    required this.obscureText,
    required this.validator,
    this.onChanged,
    this.suffixIcon,
  });

  final String label;
  final TextEditingController controller;
  final bool obscureText;
  final FormFieldValidator<String> validator;
  final ValueChanged<String>? onChanged;

  /// The show / hide control; every password field here carries one.
  final Widget? suffixIcon;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: _claimInk(context, .70),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              hintText: '••••••••••••',
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: suffixIcon,
            ),
            validator: validator,
            onChanged: onChanged,
          ),
        ],
      );
}

class _ExampleOtpField extends StatelessWidget {
  const _ExampleOtpField({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: Stack(
          children: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, child) => Row(
                children: [
                  for (var index = 0; index < 6; index++) ...[
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: ExampleSurface.of(context, 1),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            // A code cell is a control, so its resting edge
                            // has to clear 3:1 on paper — the daylight
                            // hairline would leave six invisible boxes.
                            color: index < value.text.length
                                ? ExamplePalette.of(context).fill
                                : exampleControlEdge(context).color,
                            width: index < value.text.length ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          index < value.text.length ? value.text[index] : '',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                    if (index != 5) const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Positioned.fill(
              child: Opacity(
                opacity: .01,
                child: TextFormField(
                  controller: controller,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  decoration: const InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                  ),
                  validator: (value) =>
                      value?.length == 6 ? null : 'Enter all 6 digits',
                ),
              ),
            ),
          ],
        ),
      );
}

String _displayUrl(String url) =>
    url.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

/// Step-by-step guide for obtaining the one-time transfer QR from the
/// provider dashboard (Security → App transfer).
class _TransferQrInstructions extends StatelessWidget {
  const _TransferQrInstructions({
    required this.brandName,
    required this.dashboardUrl,
    required this.example,
  });

  final String brandName;
  final String dashboardUrl;
  final bool example;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor =
        example ? _claimInk(context, .78) : theme.colorScheme.onSurfaceVariant;
    final titleColor =
        example ? ExampleInk.primary(context) : theme.colorScheme.onSurface;
    final linkColor =
        example ? ExamplePalette.of(context).accent : theme.colorScheme.primary;
    final where = dashboardUrl.isEmpty ? brandName : _displayUrl(dashboardUrl);
    final steps = [
      'Go to $where and log in to your existing account.',
      'Open Security and choose App transfer.',
      'Tap “Generate account transfer QR”.',
      'Come back here, tap “Scan with camera” and point it at the QR. The code works once and expires after five minutes.',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: example
            ? ExampleTheme.pick(
                context,
                dark: context.brandDesign
                    .color(Theme.of(context).brightness, 'ink',
                        fallback: ExampleColors.pearl)
                    .withValues(alpha: .05),
                light: context.brandDesign.color(
                    Theme.of(context).brightness, 'surfaceSubtle',
                    fallback: ExampleColors.lightSurfaceSubtle),
              )
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: example
              ? ExampleTheme.pick(
                  context,
                  dark: context.brandDesign
                      .color(Theme.of(context).brightness, 'ink',
                          fallback: ExampleColors.pearl)
                      .withValues(alpha: .1),
                  light: context.brandDesign.color(
                      Theme.of(context).brightness, 'borderSubtle',
                      fallback: ExampleColors.lightBorderSubtle),
                )
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline_rounded, size: 16, color: titleColor),
              const SizedBox(width: 6),
              Text(
                context.tr('How to get the QR'),
                style: TextStyle(
                  color: titleColor,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < steps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 18,
                    child: Text(
                      '${i + 1}.',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      steps[i],
                      style: TextStyle(
                          color: textColor, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          if (dashboardUrl.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: linkColor,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(0, 32),
                ),
                onPressed: () => launchUrl(
                  Uri.parse(dashboardUrl),
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: Text(
                    context.tr('Open {p0}', {'p0': _displayUrl(dashboardUrl)})),
              ),
            ),
        ],
      ),
    );
  }
}

class _AccountLinkScannerPage extends StatefulWidget {
  const _AccountLinkScannerPage({
    required this.brandName,
    this.dashboardUrl = '',
  });

  final String brandName;
  final String dashboardUrl;

  @override
  State<_AccountLinkScannerPage> createState() =>
      _AccountLinkScannerPageState();
}

class _AccountLinkScannerPageState extends State<_AccountLinkScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Scan {p0} QR', {'p0': widget.brandName})),
          actions: [
            IconButton(
              tooltip: context.tr('Toggle torch'),
              onPressed: _controller.toggleTorch,
              icon: const Icon(Icons.flashlight_on_outlined),
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: _controller,
              onDetect: (capture) {
                if (_handled) return;
                final value = capture.barcodes
                    .map((barcode) => barcode.rawValue)
                    .whereType<String>()
                    .firstOrNull;
                if (value == null || value.isEmpty) return;
                _handled = true;
                Navigator.of(context).pop(value);
              },
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 3),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 48,
              child: Card(
                color: Colors.black87,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.dashboardUrl.isEmpty
                        ? context.tr(
                            'In {p0}, open Security → App transfer, generate a QR, then place it inside the frame.',
                            {
                                'p0': widget.brandName
                              })
                        : context.tr(
                            'Log in at {p0}, open Security → App transfer, tap “Generate account transfer QR”, then place it inside the frame.',
                            {'p0': _displayUrl(widget.dashboardUrl)}),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
}
