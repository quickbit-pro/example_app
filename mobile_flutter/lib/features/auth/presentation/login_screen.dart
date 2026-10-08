import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/l10n/language_picker.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/api/dio_provider.dart';
import '../../../core/widgets/app_states.dart';
import 'login_error_message.dart';
import '../../../shared/theme/app_theme_extensions.dart';
import '../../../shared/theme/app_typography.dart';
import '../../platform/application/platform_providers.dart';
import '../application/auth_providers.dart';
import '../application/biometric_providers.dart';
import 'example_auth_field.dart';
import 'auth_keyboard_recovery.dart';
import 'email_verification_sheet.dart';
import 'forgot_password_sheet.dart';
import 'install_app_banner.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _rememberEmailKey = 'login.rememberEmail';
  static const _rememberedEmailKey = 'login.rememberedEmail';

  final _formKey = GlobalKey<FormState>();

  /// True once the customer has pressed Sign in and been refused.
  ///
  /// The form stays quiet until then, and live from then on. Validating from
  /// the first keystroke would put "Enter a valid email" under the field while
  /// someone is still typing the first letter of their address; validating
  /// only on submit — what this did — leaves the red sitting there after they
  /// have fixed it, so the screen accuses them of a mistake they just
  /// corrected and only takes it back if they press the button again.
  bool _submitAttempted = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _rememberMe = false;
  bool _enableBiometricOnLogin = false;
  bool _obscurePassword = true;
  bool _restoringSession = true;
  bool _returningUnlock = false;
  bool _unlockPrompted = false;
  bool _usePassword = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedEmail();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final config = ref.watch(appConfigProvider);
    final equalsMoneyEnabled = ref.watch(mobileTenantConfigProvider).maybeWhen(
          data: (tenant) => tenant.equalsMoneyEnabled,
          orElse: () => true,
        );
    final accountClaimEnabled = ref.watch(mobileTenantConfigProvider).maybeWhen(
          data: (tenant) => tenant.existingAccountClaimEnabled,
          orElse: () => false,
        );
    final theme = Theme.of(context);
    final finance = context.financeTheme;
    final loginBackgroundColor = config.branding.isExample
        ? context.brandDesign.color(Theme.of(context).brightness, 'paper',
            fallback: ExampleColors.appBackground)
        : config.branding.loginBackgroundColor;
    final useDarkLoginForeground = loginBackgroundColor != null &&
        loginBackgroundColor.computeLuminance() > 0.45;
    final loginForegroundColor = useDarkLoginForeground
        ? const Color(0xFF0E1116)
        : theme.colorScheme.onPrimary;
    final enrollmentAsync = ref.watch(biometricEnrollmentProvider);
    final capabilityAsync = ref.watch(biometricCapabilityProvider);

    ref.listen(authControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (state) {
          if (state.isAuthenticated) {
            _saveRememberedEmail();
          } else if (state.requiresTwoFactor &&
              previous?.valueOrNull?.requiresTwoFactor != true) {
            _promptTwoFactorCode();
          }
        },
        error: (error, stackTrace) {
          if (error is BiometricLoginException &&
              (error.kind == BiometricLoginFailure.noStoredCredentials ||
                  error.kind == BiometricLoginFailure.timedOut)) {
            // The unlock screen remembers that this was a returning session.
            // Expired credentials or a stalled attempt need password sign-in.
            setState(() => _usePassword = true);
          }
          if (_isEmailNotVerified(error)) {
            _promptEmailVerification();
            return;
          }
          final message =
              loginErrorMessage(error, AppLocalizations.of(context));
          if (config.branding.isExample) {
            // The EXAMPLE card renders the failure inline, above the button
            // the user just pressed; announce it so it is not silent for a
            // screen reader when the same error repeats.
            SemanticsService.sendAnnouncement(
              View.of(context),
              message,
              Directionality.of(context),
            );
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      );
    });

    final canUnlockBiometric = enrollmentAsync.maybeWhen(
          data: (e) => e.canUnlock,
          orElse: () => false,
        ) &&
        capabilityAsync.maybeWhen(
          data: (c) => c.available,
          orElse: () => false,
        );
    if (!authState.isLoading) _restoringSession = false;
    if (authState.valueOrNull?.biometricLocked == true) {
      _returningUnlock = true;
    }
    if (_restoringSession) {
      return Scaffold(
        body: Center(
            child: LoadingState(label: context.tr('Restoring your session'))),
      );
    }
    if (_returningUnlock && !_usePassword) {
      if (canUnlockBiometric && !_unlockPrompted && !authState.isLoading) {
        _unlockPrompted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_usePassword) _onBiometricUnlock(silent: true);
        });
      }
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.fingerprint,
                      size: 56, color: theme.colorScheme.primary),
                  const SizedBox(height: 24),
                  Text(context.tr('Welcome back'),
                      style: theme.textTheme.headlineMedium),
                  const SizedBox(height: 12),
                  Text(context.tr('Unlock to continue to your account.')),
                  const SizedBox(height: 24),
                  if (authState.hasError) ...[
                    Text(
                        loginErrorMessage(
                            authState.error!, AppLocalizations.of(context)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: canUnlockBiometric && !authState.isLoading
                        ? _onBiometricUnlock
                        : null,
                    icon: const Icon(Icons.fingerprint),
                    label: Text(authState.isLoading
                        ? context.tr('Unlocking…')
                        : context.tr('Unlock')),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _usePassword = true);
                      ref
                          .read(authControllerProvider.notifier)
                          .cancelBiometricLogin();
                    },
                    child: Text(context.tr('Use password instead')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }
    // Web Example uses passkeys; native builds retain device-specific labels.
    final usePasskeyNaming = kIsWeb && config.branding.isExample;
    final biometricLabel = capabilityAsync.maybeWhen(
      data: (c) => usePasskeyNaming ? 'Passkey' : c.describe(),
      orElse: () => usePasskeyNaming ? 'Passkey' : 'Biometrics',
    );
    final biometricIcon = usePasskeyNaming
        ? Icons.key_rounded
        : capabilityAsync.maybeWhen(
            data: (c) => c.hasFaceId ? Icons.face_outlined : Icons.fingerprint,
            orElse: () => Icons.fingerprint,
          );
    final greetingName = enrollmentAsync.maybeWhen(
      data: (e) => e.userName.isEmpty
          ? (e.email.isEmpty ? '' : e.email.split('@').first)
          : e.userName.split(' ').first,
      orElse: () => '',
    );

    if (config.branding.isExample) {
      return _ExampleLoginView(
        appName: ref.read(appConfigProvider).branding.appName,
        errorMessage: authState.hasError &&
                !_isEmailNotVerified(authState.error!)
            ? loginErrorMessage(authState.error!, AppLocalizations.of(context))
            : null,
        equalsMoneyEnabled: equalsMoneyEnabled,
        formKey: _formKey,
        submitAttempted: _submitAttempted,
        emailController: _emailController,
        passwordController: _passwordController,
        obscurePassword: _obscurePassword,
        isLoading: authState.isLoading,
        // The EXAMPLE transfer flow is part of the fixed product design. Keep it
        // visible while tenant configuration is loading (including PWA startup).
        accountClaimEnabled: true,
        biometricLabel: biometricLabel,
        biometricIcon: biometricIcon,
        biometricEnabled: canUnlockBiometric,
        onTogglePassword: () => setState(
          () => _obscurePassword = !_obscurePassword,
        ),
        onSubmit: _submit,
        onBiometric: _onBiometricUnlock,
        rememberMe: _rememberMe,
        onRememberChanged: _setRememberMe,
        biometricCapable: capabilityAsync.maybeWhen(
          data: (c) => c.available,
          orElse: () => false,
        ),
        enableBiometric: _enableBiometricOnLogin,
        onEnableBiometricChanged: (v) =>
            setState(() => _enableBiometricOnLogin = v),
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (useDarkLoginForeground
              ? SystemUiOverlayStyle.dark
              : SystemUiOverlayStyle.light)
          .copyWith(statusBarColor: Colors.transparent),
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(
            onPrimary: loginForegroundColor,
          ),
        ),
        child: Scaffold(
          body: DecoratedBox(
            decoration: BoxDecoration(
              color: config.branding.isExample ? null : loginBackgroundColor,
              gradient: config.branding.isExample
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        context.brandDesign.color(
                            Theme.of(context).brightness, 'surface',
                            fallback: const Color(0xFF03091A)),
                        context.brandDesign.color(
                            Theme.of(context).brightness, 'paper',
                            fallback: ExampleColors.appBackground),
                        context.brandDesign.color(
                            Theme.of(context).brightness, 'surfaceHigh',
                            fallback: const Color(0xFF050819)),
                      ],
                    )
                  : loginBackgroundColor == null
                      ? finance.heroGradient
                      : null,
            ),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 820;
                  final cardChild = _LoginCard(
                    emailFocusNode: _emailFocusNode,
                    passwordFocusNode: _passwordFocusNode,
                    formKey: _formKey,
                    emailController: _emailController,
                    passwordController: _passwordController,
                    rememberMe: _rememberMe,
                    enableBiometric: _enableBiometricOnLogin,
                    biometricCapable: capabilityAsync.maybeWhen(
                      data: (c) => c.available,
                      orElse: () => false,
                    ),
                    biometricLabel: biometricLabel,
                    obscurePassword: _obscurePassword,
                    isLoading: authState.isLoading,
                    onRememberChanged: _setRememberMe,
                    onEnableBiometricChanged: (v) =>
                        setState(() => _enableBiometricOnLogin = v),
                    onTogglePassword: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    onSubmit: _submit,
                    accountClaimEnabled: accountClaimEnabled,
                    appName: config.branding.appName,
                  );

                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 48 : 16,
                        vertical: wide ? 24 : 12,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1080),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: _BrandPanel(
                                      appName: config.branding.appName,
                                      greeting: greetingName,
                                      canUnlockBiometric: canUnlockBiometric,
                                      biometricLabel: biometricLabel,
                                      biometricIcon: biometricIcon,
                                      onUnlock: _onBiometricUnlock,
                                      isLoading: authState.isLoading,
                                    ),
                                  ),
                                  const SizedBox(width: 28),
                                  Expanded(child: cardChild),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _MobileHero(
                                    appName: config.branding.appName,
                                    greeting: greetingName,
                                    logoAsset: config.branding.logoAsset,
                                  ),
                                  const SizedBox(height: 12),
                                  if (canUnlockBiometric) ...[
                                    _BiometricUnlockCard(
                                      label: biometricLabel,
                                      icon: biometricIcon,
                                      onTap: _onBiometricUnlock,
                                      isLoading: authState.isLoading,
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                    Row(
                                      children: [
                                        Expanded(
                                            child: Divider(
                                                color: loginForegroundColor
                                                    .withValues(alpha: 0.2))),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12),
                                          child: Text(
                                            context.tr('or sign in'),
                                            style: theme.textTheme.labelMedium
                                                ?.copyWith(
                                              color: loginForegroundColor
                                                  .withValues(alpha: 0.7),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                            child: Divider(
                                                color: loginForegroundColor
                                                    .withValues(alpha: 0.2))),
                                      ],
                                    ),
                                    const SizedBox(height: AppSpacing.md),
                                  ],
                                  cardChild,
                                ],
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Second sign-in step for accounts with 2FA: authenticator or recovery code.
  Future<void> _promptTwoFactorCode() async {
    final controller = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('Enter your code')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr(
                  'Open your authenticator app and enter the 6-digit code, or use one of your recovery codes.'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: InputDecoration(labelText: context.tr('Code')),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.tr('Verify')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final controllerNotifier = ref.read(authControllerProvider.notifier);
    if (submitted != true || controller.text.trim().isEmpty) {
      controllerNotifier.cancelTwoFactor();
      return;
    }
    await controllerNotifier.completeTwoFactor(controller.text);
    // A wrong code keeps the challenge alive; ask again.
    if (mounted &&
        ref.read(authControllerProvider).valueOrNull?.requiresTwoFactor ==
            true) {
      _promptTwoFactorCode();
    }
  }

  static bool _isEmailNotVerified(Object error) {
    if (error is! DioException) return false;
    final data = error.response?.data;
    return error.response?.statusCode == 403 &&
        data is Map &&
        data['code']?.toString() == 'auth.email_not_verified';
  }

  /// The backend refused the sign-in until the address is confirmed: collect
  /// the code (sending a fresh one first), then retry the same credentials.
  Future<void> _promptEmailVerification() async {
    final verified = await showEmailVerificationSheet(
      context,
      email: _emailController.text.trim(),
      sendCodeFirst: true,
    );
    if (!mounted) return;
    if (verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('Email confirmed. Signing you in…'))),
      );
      _submit();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.tr('Confirm your email address to sign in.')),
        ),
      );
    }
  }

  void _submit() {
    if (!_submitAttempted) setState(() => _submitAttempted = true);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    HapticFeedback.lightImpact();
    ref.read(authControllerProvider.notifier).login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          persistForBiometric: _enableBiometricOnLogin,
        );
  }

  Future<void> _onBiometricUnlock({bool silent = false}) async {
    HapticFeedback.selectionClick();
    try {
      await ref.read(authControllerProvider.notifier).loginWithBiometrics(
            reason: 'Sign in to your account',
          );
    } on BiometricLoginException catch (e) {
      if (silent && e.kind == BiometricLoginFailure.cancelled) {
        return; // user dismissed the silent auto-prompt; ignore
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message ?? 'Biometric sign-in failed.')),
      );
    }
  }

  Future<void> _loadRememberedEmail() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted || preferences.getBool(_rememberEmailKey) != true) {
      return;
    }
    final email = preferences.getString(_rememberedEmailKey);
    if (email == null || email.trim().isEmpty) return;
    setState(() {
      _emailController.text = email;
      _rememberMe = true;
    });
  }

  Future<void> _saveRememberedEmail() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_rememberEmailKey, _rememberMe);
    if (_rememberMe) {
      await preferences.setString(
        _rememberedEmailKey,
        _emailController.text.trim(),
      );
      return;
    }
    await preferences.remove(_rememberedEmailKey);
  }

  Future<void> _setRememberMe(bool value) async {
    setState(() => _rememberMe = value);
    if (value) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_rememberEmailKey, false);
    await preferences.remove(_rememberedEmailKey);
  }
}

/// The EXAMPLE sign-in screen.
///
/// The boot lands here: the same night sky the loader ran on
/// ([ExampleAtmosphere.auth] — one violet dawn above the lockup, an indigo
/// mid and a teal counter-light), the brand lockup where the splash left it,
/// and then a form that gets out of the way. Nothing on this screen animates
/// on arrival; the 420 ms route transition already owns that. Everything
/// that does move is a state change on [ExampleMotion.state].
class _ExampleLoginView extends StatelessWidget {
  const _ExampleLoginView({
    required this.formKey,
    required this.submitAttempted,
    required this.emailController,
    required this.passwordController,
    required this.obscurePassword,
    required this.isLoading,
    required this.accountClaimEnabled,
    required this.biometricLabel,
    required this.biometricIcon,
    required this.biometricEnabled,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onBiometric,
    required this.appName,
    required this.equalsMoneyEnabled,
    required this.rememberMe,
    required this.onRememberChanged,
    required this.biometricCapable,
    required this.enableBiometric,
    required this.onEnableBiometricChanged,
    this.errorMessage,
  });

  final String appName;
  final bool rememberMe;
  final ValueChanged<bool> onRememberChanged;

  /// Device has a usable authenticator (shows the "enable" switch).
  final bool biometricCapable;
  final bool enableBiometric;
  final ValueChanged<bool> onEnableBiometricChanged;

  /// Hides the fiat/IBAN marketing lines when the banking provider is off.
  final bool equalsMoneyEnabled;
  final GlobalKey<FormState> formKey;

  /// Whether Sign in has already been pressed and refused. Drives the form
  /// from quiet to live; see `_LoginScreenState._submitAttempted`.
  final bool submitAttempted;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool isLoading;
  final bool accountClaimEnabled;
  final String biometricLabel;
  final IconData biometricIcon;
  final bool biometricEnabled;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onBiometric;

  /// The server's answer to the last attempt, already humanised. Rendered in
  /// the form instead of a snack bar so it cannot be missed or scrolled past.
  final String? errorMessage;

  /// Two-column layout with the marketing hero.
  static const double _desktop = 900;

  /// Below this the two secondary actions stack instead of sharing a row,
  /// because in Geist "Connect account" cannot sit beside "Create account"
  /// any narrower without truncating to "Connect acco…".
  ///
  /// Measured rather than guessed. Each button spends 76 px before it draws a
  /// letter — 24 px of padding a side, a 20 px icon and the 8 px gap after it
  /// — and "Connect account" sets at about 118 px in the label style, so a
  /// button needs ~194 px and the pair needs 2 x 194 + the 12 px gap = 400 px.
  /// The old threshold was 360, which is above the 327 px card it was checked
  /// against but below the width the copy actually needs, so every viewport
  /// between the two drew a row with the longer label clipped — including the
  /// 517 px browser window this was caught in. 420 carries the arithmetic plus
  /// headroom for a heavier fallback face.
  static const double _stackActionsBelow = 420;

  /// Primary and secondary action height. 52 keeps a 44 pt target with room
  /// for a 24 pt line at 130 percent text scale.
  static const double _actionHeight = 52;

  @override
  Widget build(BuildContext context) {
    final light = ExampleTheme.isLight(context);
    // A shell above may already run a scope; a second one would mean two
    // tickers and two unrelated rhythms, so ask existsAbove before adding one.
    Widget scope(Widget child) => !ExampleSheenScope.existsAbove(context)
        ? ExampleSheenScope(child: child)
        : child;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // The chrome glyphs follow the ground under them: pearl over night,
      // night over paper.
      value: (light ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light)
          .copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: ExampleSurface.of(context, 0),
      ),
      child: ExampleAtmosphere.auth(
        // One scope for the whole screen: the CTA and the headline are its
        // only hosts, and it stops ticking the moment this route is covered.
        child: scope(
          Scaffold(
            backgroundColor: Colors.transparent,
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= _desktop;
                  final form = _form(context, constraints, wide: wide);
                  if (!wide) return form;
                  return Row(
                    children: [
                      // The hero is marketing: it must never take the first
                      // tab stop away from the email field.
                      Expanded(
                        child: ExcludeFocus(
                          child: _ExampleLoginDesktopHero(
                            appName: appName,
                            showGlobalAccounts: equalsMoneyEnabled,
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: ExampleBorders.subtleSideOf(context).color,
                      ),
                      // On Twilight the atmosphere itself separates the two
                      // columns (1.40:1 across the divider). On paper it does
                      // not — hero ground and form ground measured 1.02:1 and
                      // the divider 1.03:1, so the sign-in form had no
                      // material of its own and the page read as the generic
                      // centred-form-on-white every neobank ships. Daylight
                      // therefore seats the form on a white sheet with an
                      // ambient shadow cast back over the hero: paper ground,
                      // floating sheet, white fields. Twilight keeps the
                      // shared ground, byte for byte.
                      SizedBox(
                        width: 520,
                        child: light
                            ? DecoratedBox(
                                decoration: BoxDecoration(
                                  color: context.brandDesign.color(
                                      Theme.of(context).brightness, 'surface',
                                      fallback: ExampleColors.lightSurface),
                                  boxShadow: ExampleShadows.sheetLight,
                                ),
                                child: form,
                              )
                            : form,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _form(
    BuildContext context,
    BoxConstraints constraints, {
    required bool wide,
  }) {
    final theme = Theme.of(context);
    final light = ExampleTheme.isLight(context);
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final error = errorMessage;
    // A pointer user on a wide screen expects the caret and the browser's
    // fill affordance without a click; on touch this would force the keyboard
    // open over the whole card, so it stays off there.
    final autofocusEmail = kIsWeb && wide && emailController.text.isEmpty;
    // Measured here rather than by a LayoutBuilder further down: the card is
    // sized by an IntrinsicHeight, and an intrinsic pass throws when it meets
    // a layout callback.
    final maxCardWidth = wide ? 520.0 : 430.0;
    final cardWidth = constraints.maxWidth < maxCardWidth
        ? constraints.maxWidth
        : maxCardWidth;

    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            minHeight: constraints.maxHeight,
          ),
          child: IntrinsicHeight(
            // Group credential fields for the browser's autofill UI. Leaving
            // the route does not request a new credential save prompt.
            child: AutofillGroup(
              onDisposeAction: AutofillContextAction.cancel,
              child: FocusTraversalGroup(
                child: Form(
                  key: formKey,
                  autovalidateMode: submitAttempted
                      ? AutovalidateMode.always
                      : AutovalidateMode.disabled,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Row(children: [
                          Expanded(child: ExampleLockup(height: 28)),
                          LanguagePicker(compact: true)
                        ]),
                        const SizedBox(height: AppSpacing.xxl),
                        // The one headline of this screen, and the only text
                        // that shines: the band is masked to the glyphs, so
                        // the space around them stays flat.
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: ExampleSheen.text(
                            intensity: ExampleSheenIntensity.soft,
                            child: Text(
                              context.tr('Welcome back'),
                              style: theme.textTheme.headlineSmall,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          context.tr('Sign in to your account'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: ExampleInk.secondary(context),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ExampleAuthField(
                          label: context.tr('Email'),
                          controller: emailController,
                          hintText: context.tr('name@example.com'),
                          prefixIcon: Icons.mail_outline,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email
                          ],
                          textInputAction: TextInputAction.next,
                          autofocus: autofocusEmail,
                          autocorrect: false,
                          enableSuggestions: false,
                          enabled: !isLoading,
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            return text.contains('@')
                                ? null
                                : context.tr('Enter a valid email');
                          },
                        ),
                        const SizedBox(height: AppSpacing.md),
                        ExampleAuthField(
                          label: context.tr('Password'),
                          controller: passwordController,
                          hintText: '••••••••••••',
                          prefixIcon: Icons.lock_outline,
                          obscureText: obscurePassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => onSubmit(),
                          enabled: !isLoading,
                          suffix: ExamplePasswordToggle(
                            obscured: obscurePassword,
                            onTap: onTogglePassword,
                          ),
                          validator: (value) => (value?.length ?? 0) >= 8
                              ? null
                              : 'Use at least 8 characters',
                        ),
                        ExampleStateSwitch(
                          alignment: Alignment.topCenter,
                          child: error == null
                              ? const SizedBox(
                                  key: ValueKey('no-error'),
                                  width: double.infinity,
                                )
                              : Padding(
                                  key: ValueKey('error:$error'),
                                  padding:
                                      const EdgeInsets.only(top: AppSpacing.sm),
                                  child: ExampleAuthAlert(message: error),
                                ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _ExampleSwitchGroup(
                          children: [
                            _ExampleSwitchRow(
                              title: context.tr('Remember email'),
                              subtitle: context.tr(
                                  'Only your email is stored on this device.'),
                              value: rememberMe,
                              onChanged: isLoading ? null : onRememberChanged,
                            ),
                            if (biometricCapable && !biometricEnabled)
                              _ExampleSwitchRow(
                                title: context.tr('Enable {p0} sign-in',
                                    {'p0': biometricLabel}),
                                subtitle: context.tr(
                                    'After this login, unlock the app with {p0}.',
                                    {'p0': biometricLabel}),
                                value: enableBiometric,
                                onChanged:
                                    isLoading ? null : onEnableBiometricChanged,
                              ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        // The one decisive action of the whole product, in
                        // the glass material rather than a flat fill. The
                        // ground follows what is genuinely behind the button:
                        // on mobile, and on Twilight desktop, the form floats
                        // straight on the auth atmosphere, so a bounded blur
                        // has real light to bend. On the daylight desktop the
                        // form sits on an opaque white sheet, where the same
                        // filter would sample flat white and only wash the
                        // fill out — so the material goes opaque there and
                        // keeps the identical silhouette, radius and motion.
                        ExampleGlassButton(
                          label: context.tr('Sign in'),
                          ground: wide && light
                              ? ExampleGlassGround.surface
                              : ExampleGlassGround.atmosphere,
                          // The screen's single sweep, on its single scope.
                          sheen: true,
                          loading: isLoading,
                          loadingSemanticsLabel: 'Signing in',
                          height: _actionHeight,
                          // Deliberately not the component's pill default:
                          // three stacked full-width actions at two different
                          // radii read as an accident rather than hierarchy.
                          // On this screen the glass material is what
                          // separates the primary, not a rounder corner.
                          radius: context.brandShape.radius(AppRadii.md),
                          onPressed: isLoading ? null : onSubmit,
                        ),
                        if (biometricEnabled) ...[
                          const SizedBox(height: AppSpacing.sm),
                          SizedBox(
                            height: _actionHeight,
                            child: ExamplePressable(
                              child: OutlinedButton.icon(
                                onPressed: isLoading ? null : onBiometric,
                                icon: Icon(biometricIcon, size: 19),
                                label: Text(
                                  context
                                      .tr('Use {p0}', {'p0': biometricLabel}),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xs),
                        Center(
                          child: _ExampleLink(
                            label: context.tr('Forgot password?'),
                            onTap: () async {
                              final result = await showForgotPasswordSheet(
                                context,
                                initialEmail: emailController.text,
                              );
                              if (!context.mounted || result == null) return;
                              // Replace stale autofilled credentials after verified recovery.
                              emailController.text = result.email;
                              passwordController.text = result.password;
                            },
                          ),
                        ),
                        // Below the primary action on purpose: an install ask
                        // before the user has done anything is an ambush.
                        InstallAppBanner(appName: appName),
                        const SizedBox(height: AppSpacing.md),
                        _ExampleRule(
                            label: context.tr('New to {p0}?', {'p0': appName})),
                        const SizedBox(height: AppSpacing.sm),
                        _ExampleSecondaryActions(
                          width: cardWidth - AppSpacing.lg * 2,
                          stackBelow: _stackActionsBelow,
                          height: _actionHeight,
                          children: [
                            _ExampleSecondaryButton(
                              icon: Icons.person_add_alt_1_outlined,
                              label: context.tr('Create account'),
                              onTap: () => context.go('/signup'),
                            ),
                            if (accountClaimEnabled)
                              _ExampleSecondaryButton(
                                icon: Icons.login_rounded,
                                label: context.tr('Connect account'),
                                onTap: () => context.go('/account-claim'),
                              ),
                          ],
                        ),
                        if (keyboardVisible)
                          const SizedBox(height: AppSpacing.lg)
                        else
                          const Spacer(),
                        _ExampleTrustLine(
                          label:
                              context.tr('Protected by secure authentication'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "New to EXAMPLE?" between two rules.
///
/// The label keeps its natural width and the two rules absorb the remainder, so
/// up their space first and the label ellipsises last; nothing here can
/// overflow, at any width or text scale.
class _ExampleRule extends StatelessWidget {
  const _ExampleRule({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final rule = ExampleBorders.subtleSideOf(context).color;
    return Row(
      children: [
        Expanded(child: Divider(color: rule)),
        // Non-flex: the label takes its natural width and the two rules
        // absorb whatever is left, so the brand name is never clipped.
        // No LayoutBuilder here - this row sits inside a card that computes
        // intrinsic dimensions, which a LayoutBuilder cannot answer.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: ExampleInk.secondary(context),
                ),
            maxLines: 1,
            textAlign: TextAlign.center,
          ),
        ),
        Expanded(child: Divider(color: rule)),
      ],
    );
  }
}

/// The pair of equal-weight actions under the rule.
///
/// Two same-role controls belong side by side only while both fit; under
/// [stackBelow] they become full-width rows, which is the layout that
/// survives 200 percent text without a single truncated label.
class _ExampleSecondaryActions extends StatelessWidget {
  const _ExampleSecondaryActions({
    required this.children,
    required this.width,
    required this.stackBelow,
    required this.height,
  });

  final List<Widget> children;

  /// Width this row will be given, measured by the caller.
  ///
  /// Deliberately not a [LayoutBuilder]: the card around it is sized by an
  /// [IntrinsicHeight] so the trust line can be pushed to the foot, and an
  /// intrinsic pass cannot measure through a layout callback.
  final double width;
  final double stackBelow;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (children.length == 1) {
      return SizedBox(height: height, child: children.single);
    }
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    if (width < stackBelow || scale > 1.3) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(height: AppSpacing.xs),
            SizedBox(height: height, child: children[index]),
          ],
        ],
      );
    }
    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (var index = 0; index < children.length; index++) ...[
            if (index > 0) const SizedBox(width: AppSpacing.sm),
            Expanded(child: children[index]),
          ],
        ],
      ),
    );
  }
}

/// The quiet promise at the foot of the card. Icon plus a [Flexible] label so
/// it centres at any width and wraps rather than clipping.
class _ExampleTrustLine extends StatelessWidget {
  const _ExampleTrustLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.shield_outlined,
            size: 14,
            color: ExampleInk.secondary(context),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: ExampleInk.secondary(context),
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
}

class _ExampleSecondaryButton extends StatelessWidget {
  const _ExampleSecondaryButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ExampleGlassButton(
        label: label,
        icon: icon,
        // Neutral, not primary. "Create account" and "Connect account" sit
        // under a rule that reads "New to EXAMPLE?" — they are the alternative
        // to signing in, not the thing this screen is for. Glass gives them
        // the brand's material and the running sheen; the neutral tone keeps
        // them from out-shouting the violet Sign in directly above.
        tone: ExampleGlassButtonTone.neutral,
        // The login card is a painted panel, so there is nothing behind these
        // worth blurring — `surface` goes opaque and keeps the identical
        // silhouette rather than spending a BackdropFilter on a flat ground.
        ground: ExampleGlassGround.surface,
        // Matches `_ExampleSecondaryActions._actionHeight`, which wraps this in
        // a tight SizedBox. Passing it explicitly stops the button's own 54
        // default from being silently clamped by a constraint it cannot see.
        height: _ExampleLoginView._actionHeight,
        // Square-ish, not a pill: these are a paired row under a rule, and two
        // pills side by side read as a segmented control rather than as two
        // separate destinations.
        radius: AppRadii.sm,
        onPressed: onTap,
      );
}

/// Compact switch row used on the EXAMPLE login card. The row is one semantics
/// node — title, hint and the switch's own state and action — and at least
/// 48 pt tall whatever the text scale does.
/// Seats the sign-in preferences on a surface — on paper only.
///
/// Twilight needs no container: the night ground is itself a material, so the
/// two rows read as quiet content between the fields and the CTA, and this
/// returns exactly the Column they were before. On pearl daylight they were
/// painted straight onto the F8F5FC ground between white fields and a solid
/// violet button, which reads as a hole where a surface is missing rather
/// than as breathing room — so daylight gives them the same white sheet the
/// fields sit on, with a hairline between the rows.
class _ExampleSwitchGroup extends StatelessWidget {
  const _ExampleSwitchGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final column = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0 && ExampleTheme.isLight(context))
            Divider(
              height: 1,
              thickness: 1,
              color: ExampleBorders.subtleSideOf(context).color,
            ),
          children[i],
        ],
      ],
    );
    if (!ExampleTheme.isLight(context)) return column;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.brandDesign.color(
            Theme.of(context).brightness, 'surface',
            fallback: ExampleColors.lightSurface),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.fromBorderSide(ExampleBorders.subtleSideOf(context)),
        boxShadow: ExampleShadows.ambientOf(context),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        child: column,
      ),
    );
  }
}

class _ExampleSwitchRow extends StatelessWidget {
  const _ExampleSwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ExampleInk.secondary(context),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            // Material, not adaptive: the Cupertino switch ignores
            // SwitchThemeData, so on paper its off state was a white thumb on
            // a near-white track at 1.31:1. This row is Example-only.
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}

/// A text link with a real target: 44 pt tall, keyboard focusable, underlined
/// so the affordance is not carried by colour alone.
class _ExampleLink extends StatelessWidget {
  const _ExampleLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Lavender is the link ink on night (7.2:1) and 1.7:1 on paper, so
    // daylight takes the accent role instead: lightIris, 6.2:1 on white.
    final linkInk = ExampleTheme.pick(
      context,
      dark: context.brandDesign.color(Theme.of(context).brightness, 'accent',
          fallback: ExampleColors.lavender),
      light: context.brandDesign.color(Theme.of(context).brightness, 'accent',
          fallback: ExampleColors.lightIris),
    );
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        foregroundColor: linkInk,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.xs)),
        ),
        textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
              decoration: TextDecoration.underline,
              decorationColor: linkInk,
            ),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
    );
  }
}

class _ExampleLoginDesktopHero extends StatelessWidget {
  const _ExampleLoginDesktopHero(
      {required this.appName, this.showGlobalAccounts = true});

  final String appName;

  final bool showGlobalAccounts;

  /// The hero's own lights, Twilight.
  ///
  /// The auth dawn plus the two soft masses this column used to carry before
  /// the atmosphere widget replaced them wholesale: an iris orb high right, a
  /// violet one low left. The preset alone is tuned for a phone — its dawn
  /// sits at Alignment(0, -1.05) with radius 1.15, so on a 920 x 900 desktop
  /// panel it reaches past the bottom edge and reads as flat fill. These two
  /// give the column modelling again without touching the preset every other
  /// screen shares.
  static const List<ExampleAtmosphereGlow> _heroGlows = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -1.05),
      radius: 1.15,
      alpha: .38,
      mid: ExampleColors.indigo,
      midAlpha: .55,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.iris,
      center: Alignment(.9, -.9),
      radius: .7,
      alpha: .08,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(-.8, .9),
      radius: .8,
      alpha: .10,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.1, 1.05),
      radius: .9,
      alpha: .07,
      midStop: .45,
    ),
  ];

  /// The same room on paper. Alphas are stated before the .80 daylight
  /// intensity the painter applies, so the iris mass lands at an effective
  /// .088 and the violet one at .104. Measured over the worst two-glow stack
  /// in the column: night ink 13.9:1, secondary 6.74:1, tertiary 4.30:1 —
  /// every role clear of its floor, which is what caps the iris at .11.
  static const List<ExampleAtmosphereGlow> _heroLightGlows = [
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(0, -1.05),
      radius: 1.15,
      alpha: .20,
      mid: ExampleColors.iris,
      midAlpha: .13,
      midStop: .4,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.iris,
      center: Alignment(.9, -.9),
      radius: .7,
      alpha: .11,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.violet,
      center: Alignment(-.8, .9),
      radius: .8,
      alpha: .13,
      midStop: .45,
    ),
    ExampleAtmosphereGlow(
      color: ExampleColors.teal,
      center: Alignment(1.1, 1.05),
      radius: .9,
      alpha: .16,
      midStop: .45,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Same dawn as the form side, shifted so the light reads as one
          // room across the divider instead of two panels — plus the two
          // masses that give a 920 px column depth a phone preset cannot.
          const ExampleAtmosphere(
            glows: _heroGlows,
            lightGlows: _heroLightGlows,
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl + AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExampleLockup(height: 31),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('The next generation of money.'),
                          // The desktop display tier, not displaySmall. The
                          // shared ramp stops at 44 px and this hero was set
                          // at 30 in an 860 px column — below every named
                          // competitor, including the one the research calls
                          // the easiest to out-hierarchy. 64 px is desktop
                          // only; mobile never reaches this branch.
                          style: AppTypography.displayXl(theme.textTheme),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          showGlobalAccounts
                              ? context.tr(
                                  'Global accounts, crypto and fiat in one balance, virtual and physical cards, rewards, and total control.')
                              : context.tr(
                                  'Crypto in one balance, virtual and physical cards, rewards, and total control.'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: ExampleInk.secondary(context),
                            fontWeight: FontWeight.w400,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        // One product object, not five icon bullets.
                        //
                        // The bullets restated the sentence directly above
                        // them — "global accounts, crypto and fiat in one
                        // balance, virtual and physical cards, rewards, and
                        // total control" is the same five items — in the
                        // icon-list template the research names as the
                        // weakest thing Kast, Nexo and RedotPay ship, from
                        // four different icon families. Nothing is lost by
                        // deleting them, and the first-time visitor now meets
                        // the brand's actual object instead of a feature
                        // grid. Not a sheen host: the screen already spends
                        // its budget on the headline and the CTA.
                        const _ExampleHeroCard(),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    appName,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ExampleInk.tertiary(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The card, seated, as the desktop hero's one object.
///
/// ISO 7810 at 372 pt wide — large enough to read as the product rather than
/// as an illustration, small enough that the 580 pt copy column still governs
/// the composition. The artwork stays night in both themes (a real card is
/// dark in daylight), so the seating is what changes: a violet bloom on
/// Twilight, a night ambient on paper, via the tokens the card face already
/// uses. Non-interactive and excluded from semantics — the hero column is
/// already inside an `ExcludeFocus`, and a screen reader on the sign-in page
/// wants the form, not the marketing.
class _ExampleHeroCard extends StatelessWidget {
  const _ExampleHeroCard();

  /// ISO 7810 ID-1, the only ratio a card face is drawn at.
  static const double _width = 372;
  static const double _aspectRatio = 1.586;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(
          width: _width,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: ExampleTheme.isLight(context)
                  ? ExampleShadows.sheetLight
                  : ExampleShadows.glow(
                      context.brandDesign.color(
                          Theme.of(context).brightness, 'fill',
                          fallback: ExampleColors.violet),
                      alpha: .28,
                      blur: 48,
                      spread: -10,
                    ),
            ),
            child: const ExamplePaymentCard(height: _width / _aspectRatio),
          ),
        ),
      );
}

class _MobileHero extends StatelessWidget {
  const _MobileHero({
    required this.appName,
    required this.greeting,
    required this.logoAsset,
  });

  final String appName;
  final String greeting;
  final String logoAsset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onPrimary;
    final hasLogo = logoAsset.trim().isNotEmpty;
    final isExample = appName.trim().toLowerCase() == 'example';

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 6, 2, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isExample)
                const ExampleLockup(height: 32)
              else ...[
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: fg.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: hasLogo
                      ? Padding(
                          padding: const EdgeInsets.all(8),
                          child: Image.asset(logoAsset, fit: BoxFit.contain),
                        )
                      : Icon(Icons.bolt_outlined, color: fg, size: 28),
                ),
                const SizedBox(width: 14),
                Text(
                  appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: isExample ? 12 : AppSpacing.lg),
          Text(
            greeting.isEmpty
                ? context.tr('Welcome')
                : context.tr('Welcome back,'),
            style: (isExample
                    ? theme.textTheme.bodyMedium
                    : theme.textTheme.bodyLarge)
                ?.copyWith(
              color: fg.withValues(alpha: 0.78),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            greeting.isEmpty ? context.tr('Sign in to your account') : greeting,
            style: (isExample
                    ? theme.textTheme.headlineMedium
                    : theme.textTheme.displaySmall)
                ?.copyWith(
              color: fg,
              fontWeight: isExample ? FontWeight.w600 : FontWeight.w800,
              height: 1.05,
            ),
          ),
        ],
      ),
    );
  }
}

class _BiometricUnlockCard extends StatelessWidget {
  const _BiometricUnlockCard({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isLoading,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = theme.colorScheme.onPrimary;

    return Material(
      color: fg.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(AppRadii.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: isLoading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          child: Row(
            children: [
              Container(
                height: 52,
                width: 52,
                decoration: BoxDecoration(
                  color: fg.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: fg, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Unlock with {p0}', {'p0': label}),
                      style: theme.textTheme.titleMedium?.copyWith(color: fg),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      context.tr('Tap to continue securely'),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: fg.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded,
                  color: fg.withValues(alpha: 0.8)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.appName,
    required this.greeting,
    required this.canUnlockBiometric,
    required this.biometricLabel,
    required this.biometricIcon,
    required this.onUnlock,
    required this.isLoading,
  });

  final String appName;
  final String greeting;
  final bool canUnlockBiometric;
  final String biometricLabel;
  final IconData biometricIcon;
  final VoidCallback onUnlock;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onPrimary;
    final isExample = appName.trim().toLowerCase() == 'example';

    return Container(
      constraints: const BoxConstraints(minHeight: 420),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(isExample ? 18 : AppRadii.xl),
        border: Border.all(color: foreground.withValues(alpha: 0.12)),
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
                Container(
                  height: 48,
                  width: 48,
                  decoration: BoxDecoration(
                    color: foreground.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(Icons.bolt_outlined, color: foreground),
                ),
                const SizedBox(width: 12),
                Text(
                  appName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greeting.isEmpty
                    ? context.tr('Welcome')
                    : context.tr('Welcome back, {p0}', {'p0': greeting}),
                style: theme.textTheme.displaySmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr(
                    'Banking, cards, and crypto access in one protected account.'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: foreground.withValues(alpha: 0.78),
                  height: 1.4,
                ),
              ),
              if (canUnlockBiometric) ...[
                const SizedBox(height: 22),
                _BiometricUnlockCard(
                  label: biometricLabel,
                  icon: biometricIcon,
                  onTap: onUnlock,
                  isLoading: isLoading,
                ),
              ],
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _TrustChip(
                  icon: Icons.lock_outline,
                  label: context.tr('Secure session')),
              _TrustChip(
                  icon: Icons.verified_user_outlined,
                  label: context.tr('KYC checks')),
              _TrustChip(
                  icon: Icons.fingerprint,
                  label: context.tr('Biometric login')),
            ],
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.emailController,
    required this.passwordController,
    required this.rememberMe,
    required this.enableBiometric,
    required this.biometricCapable,
    required this.biometricLabel,
    required this.obscurePassword,
    required this.isLoading,
    required this.onRememberChanged,
    required this.onEnableBiometricChanged,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.accountClaimEnabled,
    required this.appName,
  });

  final GlobalKey<FormState> formKey;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool rememberMe;
  final bool enableBiometric;
  final bool biometricCapable;
  final String biometricLabel;
  final bool obscurePassword;
  final bool isLoading;
  final ValueChanged<bool> onRememberChanged;
  final ValueChanged<bool> onEnableBiometricChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final bool accountClaimEnabled;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExample = appName.trim().toLowerCase() == 'example';

    return Card(
      elevation: 0,
      color: isExample
          ? context.brandDesign.color(Theme.of(context).brightness, 'surface',
              fallback: ExampleColors.darkSurface)
          : theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
        side: isExample
            ? BorderSide(
                color: context.brandDesign
                    .color(Theme.of(context).brightness, 'accent',
                        fallback: ExampleColors.lavender)
                    .withValues(alpha: .14),
              )
            : BorderSide.none,
      ),
      child: Padding(
        padding: EdgeInsets.all(isExample ? 16 : 24),
        child: Form(
          key: formKey,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: LanguagePicker(compact: true)),
                Text(
                  context.tr('Sign in'),
                  style: (isExample
                          ? theme.textTheme.titleLarge
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(
                    fontWeight: isExample ? FontWeight.w600 : FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('Use your email and password to continue.'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SizedBox(height: isExample ? 16 : 24),
                TextFormField(
                  controller: emailController,
                  focusNode: emailFocusNode,
                  onTapAlwaysCalled: true,
                  onTap: () => recoverAuthKeyboard(context, emailFocusNode),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email
                  ],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('Email'),
                    prefixIcon: const Icon(Icons.mail_outline),
                  ),
                  validator: (value) {
                    final trimmed = value?.trim() ?? '';
                    if (trimmed.isEmpty || !trimmed.contains('@')) {
                      return context.tr('Enter a valid email');
                    }
                    return null;
                  },
                ),
                SizedBox(height: isExample ? 10 : 14),
                TextFormField(
                  controller: passwordController,
                  focusNode: passwordFocusNode,
                  onTapAlwaysCalled: true,
                  onTap: () => recoverAuthKeyboard(context, passwordFocusNode),
                  obscureText: obscurePassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onSubmit(),
                  decoration: InputDecoration(
                    labelText: context.tr('Password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: obscurePassword
                          ? context.tr('Show password')
                          : context.tr('Hide password'),
                      onPressed: onTogglePassword,
                      icon: Icon(
                        obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.length < 8) {
                      return context.tr('Use at least 8 characters');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  value: rememberMe,
                  onChanged: onRememberChanged,
                  contentPadding: EdgeInsets.zero,
                  title: Text(context.tr('Remember email')),
                  subtitle:
                      Text(context.tr('Only your email is stored locally.')),
                  dense: isExample,
                  visualDensity:
                      isExample ? VisualDensity.compact : VisualDensity.standard,
                ),
                if (biometricCapable)
                  SwitchListTile.adaptive(
                    value: enableBiometric,
                    onChanged: onEnableBiometricChanged,
                    contentPadding: EdgeInsets.zero,
                    title: Text(context
                        .tr('Enable {p0} sign-in', {'p0': biometricLabel})),
                    subtitle: Text(
                      context.tr(
                          'After this login, unlock the app with biometrics.'),
                    ),
                  ),
                SizedBox(height: isExample ? 10 : 18),
                FilledButton.icon(
                  onPressed: isLoading ? null : onSubmit,
                  icon: isLoading
                      ? const SizedBox.square(
                          dimension: 18,
                          child: AppProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.login_rounded),
                  label: Text(context.tr('Sign in')),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: isLoading ? null : () => context.go('/signup'),
                  icon: const Icon(Icons.person_add_alt_1),
                  label: Text(context.tr('Create account')),
                ),
                if (accountClaimEnabled) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed:
                        isLoading ? null : () => context.go('/account-claim'),
                    icon: const Icon(Icons.link_rounded),
                    label: Text(context.tr(
                        'Connect an existing {p0} account', {'p0': appName})),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TrustChip extends StatelessWidget {
  const _TrustChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
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
