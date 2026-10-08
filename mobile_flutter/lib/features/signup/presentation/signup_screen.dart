import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phone_form_field/phone_form_field.dart';

import '../../../brands/example/example.dart';
import '../../../core/branding/app_design.dart';
import '../../../core/widgets/app_states.dart';
import '../../../core/models/platform_models.dart' show ActionResult;
import '../../platform/data/mobile_platform_api.dart';
import '../../../shared/shared.dart';
import '../../platform/application/platform_providers.dart';
import '../../rewards/domain/rewards_models.dart';
import '../application/referral_invitation_providers.dart';
import '../data/visitor_id_store.dart';
import '../data/referral_device_token.dart';
import '../domain/referral_invitation.dart';
import '../domain/referral_quote.dart';
import 'referral_signup_outcome.dart';
import '../domain/signup_destination.dart';
import '../../auth/presentation/example_auth_field.dart';
import '../../auth/presentation/email_verification_sheet.dart';
import 'password_strength_checklist.dart';
import 'legal_agreements.dart';
import '../../../shared/widgets/app_progress_indicator.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({
    this.invitationToken,
    this.initialReferralCode,
    this.referralSource = 'MANUAL_CODE',
    this.next,
    this.initialStep = 0,
    super.key,
  });

  final String? invitationToken;
  final String? initialReferralCode;
  final String referralSource;

  /// Where a campaign link asked the friend to land after sign-up
  /// (`?next=`), already reduced to the allowlist by the route request.
  final String? next;

  /// Step to open on; used by previews and tests to reach the review step.
  final int initialStep;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();

  /// Country and national number of the phone field, shared by both layouts
  /// so the value survives a swap between them. The registration payload
  /// sends `value.international`, the E.164 form.
  final _phoneController = PhoneController(
    initialValue: const PhoneNumber(isoCode: IsoCode.SI, nsn: ''),
  );
  final _passwordController = TextEditingController();
  late final TextEditingController _referralController;
  bool _isPhoneValid = false;
  bool _obscurePassword = true;
  bool _passwordSubmitted = false;
  final _acceptedAgreements = <LegalAgreementKey>{};
  bool _accountCreated = false;
  bool? _verificationEmailQueued;
  bool _continueWithoutInvitation = false;
  String? _appliedInvitationToken;
  ReferralInvitationPreview? _invitationPreview;
  String _accountType = 'personal';

  String _registrationAttemptId = VisitorIdStore.newVisitorId(Random.secure());
  ReferralQuote? _referralQuote;
  String? _quoteLocale;
  ReferralSignupOutcome? _referralOutcome;
  bool _signupDispatched = false;
  Future<ActionResult> Function(MobilePlatformApi)? _signupOperation;

  /// What the entered code promises, from the backend's referral check. Null
  /// until a code has been checked, or when the backend does not serve the
  /// check (the code is still validated at registration).
  ReferralWelcome? _referralWelcome;
  String _checkedReferralCode = '';

  /// The code came from a campaign link that no longer attributes (paused,
  /// expired or archived). The field is cleared and unlocked so the sign-up
  /// carries on as a normal one, with a note saying why.
  bool _inactiveInvitationLink = false;

  /// The destination the checked campaign link carries, used when the URL
  /// named none. Cleared with the code.
  String? _linkDestination;

  /// Codes a click was already recorded for, so a re-check of the same code
  /// (a retype, a paste) is not a second visit.
  final _clickedCodes = <String>{};
  Timer? _referralCheckTimer;

  /// A pause after the last keystroke before the code is looked up.
  static const Duration _referralCheckDelay = Duration(milliseconds: 500);
  late int _currentStep = widget.initialStep.clamp(0, 3);

  /// The last thing that stopped the form, already humanised. On EXAMPLE it is
  /// rendered inline above the action bar (and announced) instead of in a
  /// snack bar, which a magnified user never sees and the next frame's route
  /// work can dismiss.
  String? _exampleNotice;

  /// Two-column layout with the marketing hero. Same threshold as the sign-in
  /// screen so the two auth surfaces break at the same width.
  static const double _desktop = 900;

  /// Below this the two name fields stack: at 375 px the card content is
  /// 327 px, and two 157 px boxes cannot hold "Legal first name".
  static const double _stackFieldsBelow = 380;

  /// Drives the step change.
  ///
  /// The four steps are a corridor, not four pages, so moving between them is
  /// the same 200 ms arrival every other state change in the product uses —
  /// a fade and a 2 px rise on the panel only. Never a slide of the whole
  /// page: the progress rail, the app bar and the pinned action bar are the
  /// fixed walls of the room and they must not move while the content does.
  ///
  /// The controller animates the visible step without changing which form
  /// fields participate in the existing validation and submission flow.
  late final AnimationController _stepEnter;
  late final CurvedAnimation _stepCurve;

  @override
  void initState() {
    super.initState();
    // The invitation/legacy screens can leave before the Example form builds.
    // Initialize while mounted so disposal never creates a ticker.
    _stepEnter = AnimationController(
      vsync: this,
      duration: ExampleMotion.state,
      value: 1,
    );
    _stepCurve = CurvedAnimation(
      parent: _stepEnter,
      curve: ExampleMotion.arrive,
    );
    _referralController =
        TextEditingController(text: widget.initialReferralCode?.trim());
    _passwordController.addListener(_onPasswordChanged);
    _scheduleReferralCheck(_referralController.text);
  }

  void _onPasswordChanged() {
    setState(() {
      if (_passwordSubmitted && passwordMeetsPolicy(_passwordController.text)) {
        _exampleNotice = null;
      }
    });
  }

  /// Looks the code up once typing pauses, so the welcome and the inviter's
  /// name are on screen before the acceptance is asked for.
  void _scheduleReferralCheck(String value) {
    _referralCheckTimer?.cancel();
    final code = value.trim();
    if (code != _checkedReferralCode && !_signupDispatched) {
      _registrationAttemptId = VisitorIdStore.newVisitorId(Random.secure());
      _referralQuote = null;
    }
    if (code.isNotEmpty && _inactiveInvitationLink) {
      setState(() => _inactiveInvitationLink = false);
    }
    if (code.isEmpty) {
      if (_referralWelcome != null || _checkedReferralCode.isNotEmpty) {
        setState(() {
          _referralWelcome = null;
          _checkedReferralCode = '';
          _linkDestination = null;
        });
      }
      return;
    }
    if (code == _checkedReferralCode) return;
    _referralCheckTimer =
        Timer(_referralCheckDelay, () => _checkReferral(code));
  }

  Future<void> _checkReferral(String code) async {
    if (!mounted) return;
    final result = _invitationPreview == null
        ? await ref.read(mobilePlatformApiProvider).checkReferralCode(code)
        : null;
    if (!mounted || _referralController.text.trim() != code) return;
    if (result != null && result.campaignLinkInactive) {
      setState(() {
        _referralController.clear();
        _referralWelcome = null;
        _checkedReferralCode = '';
        _inactiveInvitationLink = true;
        _linkDestination = null;
      });
      return;
    }
    setState(() {
      _referralWelcome = result;
      _checkedReferralCode = code;
      _linkDestination = result?.isCampaignLink == true
          ? signupDestination(result!.destination)
          : null;
    });
    await _loadReferralQuote(code);
    // Addendum A: a campaign link counts the visit. Personal codes do not,
    // and nothing about it can hold up the sign-up.
    if (result != null && result.isCampaignLink && _clickedCodes.add(code)) {
      unawaited(_recordCampaignClick(code));
    }
  }

  /// One click for [code] with the install's visitor id; every failure is
  /// swallowed by the API, and this never throws into the screen.
  Future<void> _recordCampaignClick(String code) async {
    try {
      final locale = Localizations.maybeLocaleOf(context)?.languageCode;
      final visitorId = await ref.read(visitorIdStoreProvider).getOrCreate();
      if (!mounted) return;
      await ref.read(mobilePlatformApiProvider).recordCampaignLinkClick(
            code,
            visitorId: visitorId,
            locale: locale,
          );
    } catch (_) {
      // Telemetry only.
    }
  }

  /// The sign-in route the completed sign-up hands over to: the router
  /// honours `from` once the customer is signed in, so an allowlisted
  /// campaign destination (the URL's `next`, else the link's own) lands
  /// them there instead of Home.
  String get _signInRoute =>
      signInRouteAfterSignup(widget.next ?? _linkDestination);

  /// Referral code as it will be sent, or empty.
  String get _referralCodeText => _referralController.text.trim();

  Future<void> _loadReferralQuote(String code) async {
    if (!mounted || code.isEmpty || _signupDispatched) return;
    final locale = AppLocalizations.of(context).locale.toLanguageTag();
    if (_referralQuote?.isExpired(DateTime.now()) == true ||
        (_quoteLocale != null && _quoteLocale != locale)) {
      _registrationAttemptId = VisitorIdStore.newVisitorId(Random.secure());
    }
    final attemptId = _registrationAttemptId;
    setState(() {
      _referralQuote = null;
    });
    try {
      final quote = await ref.read(mobilePlatformApiProvider).getReferralQuote(
          registrationAttemptId: attemptId,
          referralCode: code,
          source: _invitationPreview == null
              ? widget.referralSource
              : 'EMAIL_INVITATION',
          invitationToken: _activeInvitationToken,
          locale: locale);
      if (!mounted ||
          _referralCodeText != code ||
          _registrationAttemptId != attemptId) {
        return;
      }
      setState(() {
        _referralQuote = quote;
        _quoteLocale = locale;
        _checkedReferralCode = code;
      });
    } catch (_) {
      // A referral lookup must never block account creation. An unavailable
      // quote is submitted for review together with the requested code.
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _referralController.dispose();
    _referralCheckTimer?.cancel();
    _stepCurve.dispose();
    _stepEnter.dispose();
    super.dispose();
  }

  /// Move to [step] and play its arrival, or land it instantly when the
  /// platform asks for reduced motion.
  void _goToStep(int step) {
    final target = step.clamp(0, 3);
    if (target == _currentStep) return;
    setState(() => _currentStep = target);
    if (!context.isExampleTheme || ExampleMotion.reduced(context)) {
      _stepEnter.value = 1;
    } else {
      _stepEnter.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(platformActionControllerProvider);
    final tenantConfig = ref.watch(mobileTenantConfigProvider);
    final invitationToken = _activeInvitationToken;
    final invitation = invitationToken == null
        ? null
        : ref.watch(referralInvitationPreviewProvider(invitationToken));

    ref.listen(platformActionControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (result) {
          if (result != null && mounted) {
            setState(() {
              _accountCreated = true;
              _verificationEmailQueued =
                  result.metadata['verificationEmailSent'] as bool?;
              if (_referralCodeText.isNotEmpty) {
                _referralOutcome =
                    ReferralSignupOutcome.fromJson(result.metadata);
              }
            });
          }
        },
        error: (error, stackTrace) {
          if (mounted) {
            final data = error is DioException ? error.response?.data : null;
            if (data is Map &&
                canRestartReferralSignup(
                    (data['code'] ?? data['Code'])?.toString())) {
              setState(() {
                _signupOperation = null;
                _signupDispatched = false;
              });
            }
            _message(_signupErrorMessage(error));
          }
        },
      );
    });

    if (_accountCreated) {
      return _SignupComplete(
        referralOutcome: _referralOutcome,
        accountType: _accountType,
        email: _emailController.text.trim(),
        emailRequestFailed: _verificationEmailQueued == false,
        onConfirmEmail: () =>
            _confirmEmail(sendCodeFirst: _verificationEmailQueued == false),
        onResendEmail: () => _confirmEmail(sendCodeFirst: true),
        onContinue: () => context.go(_signInRoute),
      );
    }

    if (invitation != null && invitation.isLoading) {
      return const _InvitationLoadingScreen();
    }
    if (invitation != null && invitation.hasError) {
      final failure = invitation.error is ReferralInvitationFailure
          ? invitation.error! as ReferralInvitationFailure
          : const ReferralInvitationFailure(
              ReferralInvitationFailureType.network,
            );
      return _InvitationFailureScreen(
        failure: failure,
        onRetry: failure.type == ReferralInvitationFailureType.network
            ? () => ref.invalidate(
                  referralInvitationPreviewProvider(invitationToken!),
                )
            : null,
        onContinueWithoutInvitation: () => setState(() {
          _continueWithoutInvitation = true;
          _invitationPreview = null;
          _appliedInvitationToken = null;
          _referralWelcome = null;
          _checkedReferralCode = '';
          _emailController.clear();
          _referralController.clear();
        }),
      );
    }

    final resolvedInvitation = invitation?.valueOrNull;
    if (resolvedInvitation != null &&
        _appliedInvitationToken != invitationToken) {
      _emailController.text = resolvedInvitation.email;
      _referralController.text = resolvedInvitation.referralCode;
      _invitationPreview = resolvedInvitation;
      _appliedInvitationToken = invitationToken;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _checkReferral(resolvedInvitation.referralCode);
      });
    }

    final config = tenantConfig.valueOrNull;
    if (context.isExampleTheme) {
      if (tenantConfig.isLoading) {
        return Scaffold(
          body: LoadingState(label: context.tr('Preparing signup')),
        );
      }
      return _buildExampleSignup(action, config);
    }
    return Scaffold(
      appBar: AppBar(
        title: context.isExampleTheme
            ? Row(
                children: [
                  const ExampleMark(size: 28),
                  const SizedBox(width: 12),
                  Text(context.tr('Create account')),
                ],
              )
            : Text(context.tr('Create account')),
        actions: [
          TextButton(
            onPressed: () => context.go('/login'),
            child: Text(context.tr('Sign in')),
          ),
        ],
      ),
      body: tenantConfig.isLoading
          ? LoadingState(label: context.tr('Preparing signup'))
          : SafeArea(
              top: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: _SignupSurface(
                    child: Form(
                      key: _formKey,
                      child: Stepper(
                        currentStep: _currentStep,
                        type: StepperType.vertical,
                        onStepTapped: (step) {
                          if (step <= _currentStep) {
                            setState(() => _currentStep = step);
                          }
                        },
                        controlsBuilder: (context, details) => Padding(
                          padding: const EdgeInsets.only(top: 18),
                          child: Row(
                            children: [
                              FilledButton(
                                onPressed: action.isLoading
                                    ? null
                                    : () => _continue(config),
                                child: action.isLoading && _currentStep == 3
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: AppProgressIndicator(
                                            strokeWidth: 2),
                                      )
                                    : Text(
                                        _currentStep == 3
                                            ? context.tr('Create account')
                                            : context.tr('Continue'),
                                      ),
                              ),
                              if (_currentStep > 0) ...[
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: action.isLoading
                                      ? null
                                      : () => setState(() => _currentStep--),
                                  child: Text(context.tr('Back')),
                                ),
                              ],
                            ],
                          ),
                        ),
                        steps: [
                          Step(
                            title: Text(context.tr('Choose your account')),
                            subtitle: Text(
                              _accountType == 'business'
                                  ? context.tr(
                                      'For registered organisations and their team')
                                  : context.tr('For your own money and cards'),
                            ),
                            isActive: _currentStep >= 0,
                            state: _stepState(0),
                            content: _AccountTypeStep(
                              value: _accountType,
                              showBusiness:
                                  config?.businessOnboardingEnabled ?? true,
                              onChanged: (value) =>
                                  setState(() => _accountType = value),
                            ),
                          ),
                          Step(
                            title: Text(context.tr('About you')),
                            subtitle:
                                Text(context.tr('Your legal contact details')),
                            isActive: _currentStep >= 1,
                            state: _stepState(1),
                            content: Column(
                              children: [
                                if (_invitationPreview != null) ...[
                                  _ReferralInvitationBanner(
                                    inviterDisplayName:
                                        _invitationPreview!.inviterDisplayName,
                                    welcomeAmount:
                                        _invitationPreview!.welcomeAmount,
                                    welcomeCurrency:
                                        _invitationPreview!.welcomeCurrency,
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                TextFormField(
                                  controller: _firstNameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    labelText: context.tr('Legal first name'),
                                    prefixIcon:
                                        const Icon(Icons.person_outline),
                                  ),
                                  validator: _required,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _lastNameController,
                                  textInputAction: TextInputAction.next,
                                  textCapitalization: TextCapitalization.words,
                                  decoration: InputDecoration(
                                    labelText: context.tr('Legal last name'),
                                    prefixIcon:
                                        const Icon(Icons.badge_outlined),
                                  ),
                                  validator: _required,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  key: const Key('signup_email'),
                                  controller: _emailController,
                                  readOnly: _invitationPreview != null,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [AutofillHints.email],
                                  decoration: InputDecoration(
                                    labelText: context.tr('Email'),
                                    prefixIcon: const Icon(Icons.mail_outline),
                                  ),
                                  validator: _emailValidator,
                                ),
                                const SizedBox(height: 12),
                                // Formats as you type, synchronously inside
                                // the keyboard event, so the caret never
                                // races a later rewrite.
                                PhoneFormField(
                                  key: const Key('signup_phone'),
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  textInputAction: TextInputAction.next,
                                  autofillHints: const [
                                    AutofillHints.telephoneNumber
                                  ],
                                  autovalidateMode:
                                      AutovalidateMode.onUserInteraction,
                                  countrySelectorNavigator:
                                      _countrySelector(context),
                                  decoration: InputDecoration(
                                    labelText: context.tr('Mobile phone'),
                                    hintText: context.tr(
                                        'Used for security and verification'),
                                  ),
                                  validator: _phoneValidator(context),
                                  onChanged: _onPhoneChanged,
                                ),
                              ],
                            ),
                          ),
                          Step(
                            title: Text(context.tr('Secure your account')),
                            subtitle: Text(
                              config?.referralsEnabled == true
                                  ? context.tr('Password and invitation')
                                  : context.tr('Create a strong password'),
                            ),
                            isActive: _currentStep >= 2,
                            state: _stepState(2),
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFormField(
                                  controller: _passwordController,
                                  obscureText: _obscurePassword,
                                  autofillHints: const [
                                    AutofillHints.newPassword
                                  ],
                                  autovalidateMode: _passwordSubmitted
                                      ? AutovalidateMode.always
                                      : AutovalidateMode.disabled,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: InputDecoration(
                                    labelText: context.tr('Password'),
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: _passwordValidator,
                                ),
                                const SizedBox(height: 10),
                                PasswordStrengthChecklist(
                                  password: _passwordController.text,
                                  showErrors: _passwordSubmitted,
                                  dark: false,
                                ),
                                if (config?.referralsEnabled == true ||
                                    _invitationPreview != null) ...[
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    key: const Key('signup_referral_code'),
                                    controller: _referralController,
                                    readOnly: _signupDispatched ||
                                        _invitationPreview != null ||
                                        (!_inactiveInvitationLink &&
                                            widget.initialReferralCode
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true),
                                    textCapitalization:
                                        TextCapitalization.characters,
                                    decoration: InputDecoration(
                                      labelText: config?.referralRequired ==
                                              true
                                          ? context.tr('Referral code')
                                          : context
                                              .tr('Referral code (optional)'),
                                      prefixIcon: const Icon(
                                          Icons.people_outline_rounded),
                                      helperText: _invitationPreview != null
                                          ? context.tr(
                                              'Confirmed by your email invitation.')
                                          : !_inactiveInvitationLink &&
                                                  widget.initialReferralCode
                                                          ?.trim()
                                                          .isNotEmpty ==
                                                      true
                                              ? context.tr(
                                                  'Applied from your invitation link.')
                                              : context.tr(
                                                  'The code is verified before your account is created.'),
                                    ),
                                    onChanged: (value) {
                                      _scheduleReferralCheck(value);
                                      setState(() {});
                                    },
                                    validator: (value) {
                                      if (config?.referralRequired == true &&
                                          (value == null ||
                                              value.trim().isEmpty)) {
                                        return context
                                            .tr('A referral code is required');
                                      }
                                      if ((value?.trim().length ?? 0) > 32) {
                                        return context
                                            .tr('Use at most 32 characters');
                                      }
                                      return null;
                                    },
                                  ),
                                  if (_inactiveInvitationLink) ...[
                                    const SizedBox(height: 12),
                                    _InactiveInvitationLinkNote(
                                      key: const Key(
                                          'signup_referral_link_inactive'),
                                      required:
                                          config?.referralRequired == true,
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                          Step(
                            title: Text(context.tr('Review')),
                            subtitle: Text(context
                                .tr('Confirm before we create the account')),
                            isActive: _currentStep >= 3,
                            state: _stepState(3),
                            content: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _ReviewRow(
                                  label: context.tr('Account'),
                                  value: _accountType == 'business'
                                      ? 'Business'
                                      : 'Personal',
                                ),
                                _ReviewRow(
                                  label: context.tr('Name'),
                                  value:
                                      '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                                          .trim(),
                                ),
                                _ReviewRow(
                                  label: context.tr('Email'),
                                  value: _emailController.text.trim(),
                                ),
                                if (_invitationPreview != null)
                                  _ReviewRow(
                                    label: context.tr('Invitation'),
                                    value:
                                        'Invited by ${_invitationPreview!.inviterDisplayName}',
                                  ),
                                if (_accountType == 'business')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 10),
                                    child: Text(
                                      context.tr(
                                          'After sign-in, we will guide you through company details, associated people, and documents. You can leave and resume that process.'),
                                    ),
                                  ),
                                const SizedBox(height: 14),
                                _legalAgreements(config),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildExampleSignup(
    AsyncValue<Object?> action,
    MobileTenantConfig? config,
  ) {
    final theme = Theme.of(context);
    final titles = <(String, String)>[
      (
        'Choose your account',
        _accountType == 'business'
            ? 'For a registered organisation and its team'
            : 'For your own money and cards',
      ),
      ('About you', 'Your legal contact details'),
      (
        'Secure your account',
        config?.referralsEnabled == true
            ? 'Password and invitation'
            : 'Create a strong password',
      ),
      ('Review', 'Confirm before we create the account'),
    ];
    final title = titles[_currentStep];
    final busy = action.isLoading;
    // The rail is the fixed wall of the corridor: it never moves and never
    // fades, so the room stays put while its contents change.
    final progress = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ExampleStepProgress(
          current: _currentStep,
          total: titles.length,
          label: context.tr('Step {p0} of {p1}',
              {'p0': _currentStep + 1, 'p1': titles.length}),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
    // Title, sub and the fields arrive together, as one panel: splitting the
    // heading from the body would read as two things landing at once.
    final panel = _StepArrival(
      animation: _stepCurve,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The one headline of this screen, in both layouts, and the only
          // text that shines: ShaderMask keeps the band on the glyphs.
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: ExampleSheen.text(
              intensity: ExampleSheenIntensity.soft,
              child: Text(title.$1, style: theme.textTheme.headlineSmall),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            title.$2,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ExampleInk.secondary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _exampleSteps(config),
        ],
      ),
    );
    final notice = _exampleNotice;
    final alert = ExampleStateSwitch(
      alignment: Alignment.topCenter,
      child: notice == null
          ? const SizedBox(key: ValueKey('no-notice'), width: double.infinity)
          : Padding(
              key: ValueKey('notice:$notice'),
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: ExampleAuthAlert(message: notice),
            ),
    );
    final actions = _ExampleStepActions(
      primaryLabel: _currentStep == 3 ? 'Create account' : 'Continue',
      onPrimary: busy ? null : () => _continue(config),
      onBack:
          _currentStep == 0 || busy ? null : () => _goToStep(_currentStep - 1),
      busy: busy && _currentStep == 3,
    );

    Widget form(Widget child) => Form(key: _formKey, child: child);

    // A shell above may already run a scope; a second one would mean two
    // tickers and two unrelated rhythms, so ask existsAbove before adding one.
    Widget scope(Widget child) => !ExampleSheenScope.existsAbove(context)
        ? ExampleSheenScope(child: child)
        : child;

    return ExampleAtmosphere.auth(
      // One scope above both layouts, so the step bar in the body and the
      // primary action in the bottom bar share a single ticker.
      child: scope(
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth >= _desktop) {
              return Scaffold(
                backgroundColor: Colors.transparent,
                body: SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Marketing, and never the first tab stop: the sign-in
                      // escape hatch lives under the form instead.
                      Expanded(
                        flex: 5,
                        child: ExcludeFocus(
                          child: _ExampleSignupHero(
                            currentStep: _currentStep,
                            steps: titles,
                          ),
                        ),
                      ),
                      VerticalDivider(
                        width: 1,
                        color: ExampleBorders.subtleSideOf(context).color,
                      ),
                      Expanded(
                        flex: 6,
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.xl,
                              vertical: AppSpacing.xxl,
                            ),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: form(
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    progress,
                                    panel,
                                    alert,
                                    const SizedBox(height: AppSpacing.lg),
                                    actions,
                                    const SizedBox(height: AppSpacing.md),
                                    Center(
                                      child: _ExampleSignInLink(
                                        onTap: busy
                                            ? null
                                            : () => context.go('/login'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.transparent,
                scrolledUnderElevation: 0,
                centerTitle: true,
                leading: IconButton(
                  tooltip: _currentStep == 0
                      ? context.tr('Back to sign in')
                      : context.tr('Previous step'),
                  onPressed: busy
                      ? null
                      : () {
                          if (_currentStep == 0) {
                            context.go('/login');
                          } else {
                            _goToStep(_currentStep - 1);
                          }
                        },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                ),
                title: Text(context.tr('Create account'),
                    style: theme.textTheme.titleMedium),
                actions: [
                  _ExampleSignInLink(
                    compact: true,
                    onTap: busy ? null : () => context.go('/login'),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
              ),
              body: SafeArea(
                top: false,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: form(
                      SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xs,
                          AppSpacing.lg,
                          AppSpacing.xl,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            progress,
                            panel,
                            alert,
                            // What used to be roughly 340 px of empty
                            // atmosphere between the last tile and the CTA
                            // bar. The desktop hero shows the whole journey
                            // in its left column; the phone never could, so
                            // the rooms still ahead land here instead — the
                            // void filled with the one thing it was missing,
                            // which is where the flow goes next.
                            _ExampleStepTrail(
                              current: _currentStep,
                              steps: titles,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // One lit object, not two. The bar used to be a frosted panel
              // with a frosted-looking button inside it — two rounded glass
              // rectangles a few pixels apart, which is how a CTA bar stops
              // reading as an edge of the room and starts reading as a card
              // that fell in. The bar is now a hairline over the atmosphere
              // and the button itself is the glass.
              bottomNavigationBar: DecoratedBox(
                decoration: BoxDecoration(
                  border: ExampleBorders.hairlineOf(
                    context,
                    top: true,
                    bottom: false,
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Center(
                    heightFactor: 1,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          AppSpacing.sm,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        // Center above loosens the width and the maxWidth cap
                        // leaves minWidth at 0, so an unbounded child sizes to
                        // its label and Continue once shipped 111 px wide.
                        // Re-tighten here: infinity resolves to the 430 cap on
                        // desktop and to the viewport on a phone.
                        child: SizedBox(
                          width: double.infinity,
                          child: actions,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // Keep the existing active-step form lifetime and validation scope.
  Widget _exampleSteps(MobileTenantConfig? config) =>
      _exampleSignupStep(_currentStep, config);

  Widget _exampleSignupStep(int step, MobileTenantConfig? config) {
    final showReferral =
        config?.referralsEnabled == true || _invitationPreview != null;
    switch (step) {
      case 0:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _ExampleAccountChoice(
              selected: _accountType == 'personal',
              icon: Icons.person_outline,
              title: context.tr('Personal account'),
              description: context.tr('Manage your own money.'),
              // The sentence this replaces read "Manage your money,
              // verification, wallets, and cards." — four nouns wrapping
              // across three lines in a 72 pt tile. Same words, spent as the
              // list they always were: it scans in one pass, it is the same
              // medicine the tier facts got on the setup screen, and it gives
              // the two tiles the body that the step needed anyway.
              features: const ['Wallets', 'Cards', 'Verification'],
              onTap: () => setState(() => _accountType = 'personal'),
            ),
            if (config?.businessOnboardingEnabled ?? true) ...[
              const SizedBox(height: AppSpacing.sm),
              _ExampleAccountChoice(
                selected: _accountType == 'business',
                icon: Icons.business_center_outlined,
                title: context.tr('Business account'),
                description: context.tr('Apply as a registered organisation.'),
                features: const ['Owners', 'Team', 'Documents'],
                onTap: () => setState(() => _accountType = 'business'),
              ),
            ],
          ],
        );
      case 1:
        final firstName = ExampleAuthField(
          label: context.tr('Legal first name'),
          controller: _firstNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: _required,
        );
        final lastName = ExampleAuthField(
          label: context.tr('Legal last name'),
          controller: _lastNameController,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          validator: _required,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_invitationPreview != null) ...[
              _ReferralInvitationBanner(
                inviterDisplayName: _invitationPreview!.inviterDisplayName,
                welcomeAmount: _invitationPreview!.welcomeAmount,
                welcomeCurrency: _invitationPreview!.welcomeCurrency,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < _stackFieldsBelow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      firstName,
                      const SizedBox(height: AppSpacing.sm),
                      lastName,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: firstName),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: lastName),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            ExampleAuthField(
              key: const Key('signup_email'),
              label: context.tr('Email'),
              controller: _emailController,
              readOnly: _invitationPreview != null,
              hintText: context.tr('name@example.com'),
              keyboardType: TextInputType.emailAddress,
              prefixIcon: Icons.mail_outline,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              enableSuggestions: false,
              validator: _emailValidator,
            ),
            const SizedBox(height: AppSpacing.sm),
            const ExampleAuthFieldLabel('Mobile phone'),
            const SizedBox(height: AppSpacing.xs),
            _ExamplePhoneField(
              controller: _phoneController,
              countrySelector: _countrySelector(context),
              onChanged: _onPhoneChanged,
              validator: _phoneValidator(context),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              context.tr('Used for security and verification'),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: ExampleInk.secondary(context),
                  ),
            ),
          ],
        );
      case 2:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExampleAuthField(
              label: context.tr('Password'),
              controller: _passwordController,
              hintText: '••••••••••••',
              obscureText: _obscurePassword,
              autofillHints: const [AutofillHints.newPassword],
              prefixIcon: Icons.lock_outline,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction:
                  showReferral ? TextInputAction.next : TextInputAction.done,
              suffix: ExamplePasswordToggle(
                obscured: _obscurePassword,
                onTap: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
              ),
              validator: _passwordValidator,
              autovalidateMode: _passwordSubmitted
                  ? AutovalidateMode.always
                  : AutovalidateMode.disabled,
            ),
            const SizedBox(height: AppSpacing.sm),
            PasswordStrengthChecklist(
              password: _passwordController.text,
              showErrors: _passwordSubmitted,
            ),
            if (showReferral) ...[
              const SizedBox(height: AppSpacing.md),
              ExampleAuthField(
                key: const Key('signup_referral_code'),
                label: config?.referralRequired == true
                    ? context.tr('Referral code')
                    : context.tr('Referral code (optional)'),
                controller: _referralController,
                readOnly: _signupDispatched ||
                    _invitationPreview != null ||
                    widget.initialReferralCode?.trim().isNotEmpty == true,
                prefixIcon: Icons.people_outline_rounded,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                helperText: _invitationPreview != null
                    ? context.tr('Confirmed by your email invitation.')
                    : context.tr('Verified before your account is created.'),
                onChanged: (value) {
                  _scheduleReferralCheck(value);
                  setState(() {});
                },
                validator: (value) {
                  if (config?.referralRequired == true &&
                      (value == null || value.trim().isEmpty)) {
                    return context.tr('A referral code is required');
                  }
                  return null;
                },
              ),
            ],
          ],
        );
      default:
        final referral = _referralController.text.trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: ExampleSurface.of(context, 1),
                borderRadius: const BorderRadius.all(
                  Radius.circular(AppRadii.lg),
                ),
                border: ExampleBorders.subtleOf(context),
                boxShadow: ExampleShadows.ambientOf(context),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  children: [
                    _ReviewRow(
                      label: context.tr('Account'),
                      value:
                          _accountType == 'business' ? 'Business' : 'Personal',
                    ),
                    _ReviewRow(
                      label: context.tr('Name'),
                      value:
                          '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'
                              .trim(),
                    ),
                    _ReviewRow(
                      label: context.tr('Email'),
                      value: _emailController.text.trim(),
                    ),
                    if (referral.isNotEmpty)
                      _ReviewRow(
                          label: context.tr('Referral code'), value: referral),
                  ],
                ),
              ),
            ),
            if (_accountType == 'business') ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                context.tr(
                    'After sign-in we will guide you through company details, associated people, and documents. You can leave and resume that process.'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ExampleInk.secondary(context),
                    ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _legalAgreements(config),
          ],
        );
    }
  }

  StepState _stepState(int step) {
    if (_currentStep > step) return StepState.complete;
    return _currentStep == step ? StepState.editing : StepState.indexed;
  }

  void _continue(MobileTenantConfig? config) {
    if (_exampleNotice != null) setState(() => _exampleNotice = null);
    if (_currentStep == 1) {
      final contactValid = _required(_firstNameController.text) == null &&
          _required(_lastNameController.text) == null &&
          _emailValidator(_emailController.text) == null &&
          _isPhoneValid;
      if (!contactValid) {
        _message('Complete your contact details before continuing.');
        return;
      }
    }
    if (_currentStep == 2) {
      final passwordValid =
          _passwordValidator(_passwordController.text) == null;
      final referralValid = config?.referralRequired != true ||
          _referralController.text.trim().isNotEmpty;
      if (!passwordValid || !referralValid) {
        setState(() => _passwordSubmitted = true);
        _formKey.currentState?.validate();
        _message(
          passwordValid
              ? 'Complete the security details before continuing.'
              : 'Your password is too weak. Check the requirements below the field.',
        );
        return;
      }
    }
    if (_currentStep < 3) {
      _goToStep(_currentStep + 1);
      return;
    }
    _submit(config);
  }

  Widget _legalAgreements(MobileTenantConfig? config) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_signupDispatched) ...[
            Text(context.tr(
                'Retries keep the original signup details until the account status is known.')),
            const SizedBox(height: 8),
          ],
          Text(context.tr(
              'We use device and connection information to help prevent referral abuse.')),
          const SizedBox(height: 8),
          LegalAgreementsSection(
            specs: _legalSpecs(config),
            accepted: _acceptedAgreements,
            onChanged: (key, accepted) => setState(() {
              if (accepted) {
                _acceptedAgreements.add(key);
              } else {
                _acceptedAgreements.remove(key);
              }
            }),
          ),
        ],
      );

  List<LegalAgreementSpec> _legalSpecs(MobileTenantConfig? config) =>
      legalAgreementSpecs(
        config,
        business: _accountType == 'business',
        appName: AppDesignTheme.nameOf(context).isNotEmpty
            ? AppDesignTheme.nameOf(context)
            : 'App',
      );

  void _submit(MobileTenantConfig? config) {
    if (_signupOperation != null) {
      ref
          .read(platformActionControllerProvider.notifier)
          .run(_signupOperation!);
      return;
    }
    setState(() => _passwordSubmitted = true);
    if (!(_formKey.currentState?.validate() ?? false) || !_isPhoneValid) {
      _message('Review the highlighted details.');
      return;
    }
    final specs = _legalSpecs(config);
    if (!allLegalAgreementsAccepted(specs, _acceptedAgreements)) {
      _message('Please accept all legal agreements to continue.');
      return;
    }
    _formKey.currentState!.save();
    final referral = _referralController.text.trim();
    final referralTermsVersion =
        referral.isEmpty ? null : _referralQuote?.termsVersion;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final accountType = _accountType;
    final phone = _phoneE164;
    final quote = _referralQuote;
    // Entering or retaining a referral code requests attribution when the
    // account is created; no separate referral checkbox is required.
    final needsReview = referral.isNotEmpty &&
        (quote == null ||
            quote.isExpired(DateTime.now()) ||
            _checkedReferralCode != referral ||
            _quoteLocale !=
                AppLocalizations.of(context).locale.toLanguageTag());
    final attemptId = _registrationAttemptId;
    final source =
        _invitationPreview != null ? 'EMAIL_INVITATION' : widget.referralSource;
    final token = _invitationPreview == null ? null : _activeInvitationToken;
    final agreements =
        legalAgreementsPayload(specs, _acceptedAgreements, config);
    _signupDispatched = true;
    final deviceStore = ref.read(referralDeviceTokenStoreProvider);
    _signupOperation = (api) async => api.signUp(
          email: email,
          password: password,
          firstName: firstName,
          lastName: lastName,
          accountType: accountType,
          phone: phone,
          referralCode: referral.isEmpty ? null : referral,
          referralSource: referral.isEmpty ? null : source,
          invitationToken: token,
          legalAgreements: agreements,
          referralAccepted: referral.isEmpty ? null : !needsReview,
          referralNeedsReview: needsReview,
          installationToken: await deviceStore.getOrCreate(),
          referralTermsVersion: referralTermsVersion,
          registrationAttemptId: attemptId,
          referralQuoteId: referral.isEmpty ? null : quote?.quoteId,
          referralTermsHash: referral.isEmpty ? null : quote?.termsHash,
          referralPolicyHash: referral.isEmpty ? null : quote?.policyHash,
        );
    ref.read(platformActionControllerProvider.notifier).run(_signupOperation!);
  }

  String? get _activeInvitationToken {
    if (_continueWithoutInvitation) return null;
    final token = widget.invitationToken;
    return token == null || token.isEmpty ? null : token;
  }

  Future<void> _confirmEmail({bool sendCodeFirst = false}) async {
    final verified = await showEmailVerificationSheet(
      context,
      email: _emailController.text.trim(),
      sendCodeFirst: sendCodeFirst,
    );
    if (verified && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('Email confirmed. Sign in to continue.'))));
      context.go(_signInRoute);
    }
  }

  /// The number in E.164 (`+4915123456789`), or null while nothing is typed.
  String? get _phoneE164 {
    final number = _phoneController.value;
    return number.nsn.isEmpty ? null : number.international;
  }

  void _onPhoneChanged(PhoneNumber number) {
    final valid = number.nsn.isNotEmpty && number.isValid();
    if (valid != _isPhoneValid && mounted) {
      setState(() => _isPhoneValid = valid);
    }
  }

  /// Required, then valid for its country by libphonenumber's metadata (any
  /// line type: the backend accepts whatever `IsValidNumber` does). The
  /// messages come from the phone field's own translations.
  PhoneNumberInputValidator _phoneValidator(BuildContext context) =>
      PhoneValidator.compose([
        PhoneValidator.required(context),
        PhoneValidator.valid(context),
      ]);

  /// The country picker: a searchable sheet that slides up over the form and
  /// can be dragged taller, the same shape both layouts had before, on the
  /// app's sheet corner rather than the package's.
  CountrySelectorNavigator _countrySelector(BuildContext context) =>
      CountrySelectorNavigator.draggableBottomSheet(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadii.xl)),
        backgroundColor:
            context.isExampleTheme ? ExampleSurface.of(context, 1) : null,
      );

  void _message(String message) {
    if (!context.isExampleTheme) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    setState(() => _exampleNotice = message);
    // A repeated identical message is not re-announced by a live region on
    // its own, so say it explicitly.
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }
}

class _SignupSurface extends StatelessWidget {
  const _SignupSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) return child;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      decoration: BoxDecoration(
        color: context.brandDesign.color(
            Theme.of(context).brightness, 'surface',
            fallback: ExampleColors.darkSurface),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: context.brandDesign
              .color(Theme.of(context).brightness, 'accent',
                  fallback: ExampleColors.lavender)
              .withValues(alpha: .14),
        ),
        boxShadow: [
          BoxShadow(
            color: context.brandDesign
                .color(Theme.of(context).brightness, 'fill',
                    fallback: ExampleColors.violet)
                .withValues(alpha: .08),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }
}

class _ExampleStepProgress extends StatelessWidget {
  const _ExampleStepProgress({
    required this.current,
    required this.total,
    required this.label,
  });

  final int current;
  final int total;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    // The done segments carry the primary fill in both themes; the remaining
    // ones are a track. On paper no single tone can be 3:1 against both the
    // page and the violet fill, so daylight splits the two jobs: the track
    // keeps the surface step (4.26:1 against the fill, which is the state
    // boundary WCAG 1.4.11 asks for), and the strip is enclosed in a night .58
    // pill — 4.66:1 on paper — so its full extent is visible and the three
    // steps still to run stop being a 1.18:1 ghost. Twilight is untouched: no
    // outline, no inset, the same 3 px segments as before.
    //
    // The step you are ON is iris rather than violet. Colour alone is a weak
    // signal here (iris to violet measures 1.45:1 in Twilight and 1.16:1 on
    // paper), which is exactly why it is spent on the *current* segment and
    // not asked to separate done from undone: the track already does that at
    // 4.26:1, and the lighter accent simply says which of the filled segments
    // is live. Both clear the 3:1 non-text floor against the track
    // (lightIris 4.95:1, lightViolet 4.26:1).
    final light = ExampleTheme.isLight(context);
    final done = ExampleInk.accent(context, ExampleColors.violet);
    final live = ExampleInk.accent(context, ExampleColors.iris);
    final todo = ExampleTheme.pick(
      context,
      dark: ExamplePalette.of(context).borderSubtle,
      light: ExamplePalette.of(context).surfaceHigh,
    );
    return Semantics(
      container: true,
      label: context.tr('Signup progress'),
      value: label,
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The step bar is the screen's progress host: one band across the
          // whole strip, clipped to the pill it is drawn as.
          ExampleSheen(
            borderRadius: const BorderRadius.all(
              Radius.circular(AppRadii.pill),
            ),
            child: Container(
              padding: light ? const EdgeInsets.all(1.5) : EdgeInsets.zero,
              decoration: light
                  ? BoxDecoration(
                      border: Border.all(
                        color: ExamplePalette.of(context).textTertiary,
                      ),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(AppRadii.pill),
                      ),
                    )
                  : null,
              child: Row(
                children: [
                  for (var index = 0; index < total; index++) ...[
                    Expanded(
                      child: AnimatedContainer(
                        duration: duration,
                        curve: ExampleMotion.arrive,
                        height: 3,
                        decoration: BoxDecoration(
                          color: index == current
                              ? live
                              : index < current
                                  ? done
                                  : todo,
                          borderRadius: const BorderRadius.all(
                            Radius.circular(AppRadii.pill),
                          ),
                        ),
                      ),
                    ),
                    if (index != total - 1)
                      const SizedBox(width: AppSpacing.xxs),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            // Secondary, not tertiary: this is the only place the form says
            // how much is left, and it has to clear 4.5:1 to count.
            style: theme.textTheme.labelSmall?.copyWith(
              color: ExampleInk.secondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// One of the two account types. The whole row is the target, it answers a
/// press through [ExamplePressable], and it reads to a screen reader as a
/// single selectable button rather than four separate strings.
class _ExampleAccountChoice extends StatelessWidget {
  const _ExampleAccountChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.features = const <String>[],
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  /// What the account actually contains, as items rather than a sentence.
  final List<String> features;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    final fill = ExampleInk.accent(context, ExampleColors.violet);
    const radius = BorderRadius.all(Radius.circular(AppRadii.lg));
    return Semantics(
      button: true,
      selected: selected,
      label: features.isEmpty
          ? '$title. $description'
          : '$title. $description ${features.join(', ')}.',
      onTap: onTap,
      excludeSemantics: true,
      child: ExamplePressable(
        onTap: onTap,
        borderRadius: radius,
        child: AnimatedContainer(
          duration: duration,
          curve: ExampleMotion.arrive,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            // Selected steps up a surface level in Twilight, where the levels
            // are visible. On paper the levels are a whisper apart, so the
            // selected tile keeps the white surface and lets the 1.5 px fill
            // edge and the ambient under it carry the state.
            color: selected
                ? ExampleTheme.pick(
                    context,
                    dark: ExampleSurface.level2,
                    light: ExampleSurface.light1,
                  )
                : ExampleSurface.of(context, 1),
            borderRadius: radius,
            boxShadow: selected
                ? ExampleShadows.ambientOf(context)
                : ExampleShadows.none,
            border: selected
                ? Border.fromBorderSide(
                    BorderSide(color: fill, width: 1.5),
                  )
                : Border.fromBorderSide(exampleControlEdge(context)),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: duration,
                curve: ExampleMotion.arrive,
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? fill : ExampleSurface.of(context, 2),
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppRadii.sm),
                  ),
                  border: selected
                      ? null
                      : Border.fromBorderSide(exampleControlEdge(context)),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  // Pearl on the fill in both themes: the fill moves, the
                  // label on it does not.
                  color: selected
                      ? ExamplePalette.of(context).onFill
                      : ExampleInk.secondary(context),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ExampleInk.secondary(context),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (features.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.xxs,
                        runSpacing: AppSpacing.xxs,
                        children: [
                          for (final feature in features)
                            _ChoiceChip(label: feature, selected: selected),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? ExampleInk.accent(context, ExampleColors.iris)
                    : ExampleInk.tertiary(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Back and the primary action. They sit side by side while both labels fit
/// on one line and stack when they do not, which is what happens at 320 px
/// and at a 1.3 text scale; neither ever shrinks below 52 pt.
class _ExampleStepActions extends StatelessWidget {
  const _ExampleStepActions({
    required this.primaryLabel,
    required this.onPrimary,
    required this.onBack,
    required this.busy,
  });

  final String primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback? onBack;
  final bool busy;

  static const double _stackBelow = 340;

  @override
  Widget build(BuildContext context) {
    // The screen's one decisive action, in the shared glass material. It sits
    // on `ExampleAtmosphere.auth` in both layouts — a pinned bar over the
    // painted room on a phone, the form column on desktop — so the ground is
    // atmosphere and the bounded blur is doing real work rather than frosting
    // a flat panel. Loading holds the silhouette, the width and the position
    // and swaps the label for a ring, so the bar never jumps mid-submit.
    final primary = ExampleGlassButton(
      label: primaryLabel,
      ground: ExampleGlassGround.atmosphere,
      sheen: true,
      loading: busy,
      loadingSemanticsLabel: 'Creating your account',
      onPressed: onPrimary,
    );
    // Full width, explicitly. The CTA bar wraps this in
    // `Center(heightFactor: 1, child: ConstrainedBox(maxWidth: 430))`, and a
    // Center loosens minWidth to 0 — so an unbounded child sizes to its label
    // and "Continue" once shipped as a 109 px pill floating in the middle of
    // the bar. The two-button branch below escapes it because both children
    // sit in Expanded.
    if (onBack == null) return SizedBox(width: double.infinity, child: primary);
    // Same object, unfilled: never louder than primary, never as quiet as a
    // text link.
    final back = ExampleGlassButton(
      label: context.tr('Back'),
      tone: ExampleGlassButtonTone.neutral,
      ground: ExampleGlassGround.atmosphere,
      onPressed: onBack,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (constraints.maxWidth < _stackBelow || scale > 1.3) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppSpacing.xs),
              back,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: back),
            const SizedBox(width: AppSpacing.sm),
            Expanded(flex: 2, child: primary),
          ],
        );
      },
    );
  }
}

/// The step change, as an arrival rather than a page turn.
///
/// Opacity and a 2 px rise, 200 ms, on the panel only — the same gesture
/// [ExampleStateSwitch] performs, while retaining the current form's active
/// step. Transform and opacity only, so nothing around it reflows; under
/// reduced motion the controller is pinned at 1 and this becomes a plain child.
class _StepArrival extends StatelessWidget {
  const _StepArrival({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  /// The product's state-change rise. Two pixels: felt, never seen.
  static const double _rise = 2;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final t = animation.value.clamp(0.0, 1.0).toDouble();
            return Opacity(
              opacity: t,
              child: Transform.translate(
                offset: Offset(0, (1 - t) * _rise),
                child: child,
              ),
            );
          },
        ),
      );
}

/// The rooms still ahead, on the phone.
///
/// Desktop shows the whole journey in the hero column; the phone had nothing,
/// so a short step left roughly a third of a page of empty atmosphere between
/// the last control and the CTA bar. This fills it with the one thing that
/// space was missing — where the flow goes next — and it disappears on the
/// last step, where the review and the agreements already fill the page.
///
/// Deliberately quiet: secondary and tertiary ink, hairline discs, no fill.
/// It orients, it never competes with the form above it.
class _ExampleStepTrail extends StatelessWidget {
  const _ExampleStepTrail({required this.current, required this.steps});

  final int current;
  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming = <(int, (String, String))>[
      for (var index = current + 1; index < steps.length; index++)
        (index, steps[index]),
    ];
    if (upcoming.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('STILL AHEAD'),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10.5,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w700,
              color: ExampleInk.tertiary(context),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final entry in upcoming)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: exampleControlEdge(context).color,
                        ),
                      ),
                      child: Text(
                        '${entry.$1 + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: ExampleInk.tertiary(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$2.$1,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              // Night .72 over the daylight page composites to
                              // 7.4:1; pearl .68 is unchanged in Twilight.
                              color: ExampleInk.secondary(context),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            entry.$2.$2,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ExampleInk.tertiary(context),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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

/// One noun from an account type, as an item.
class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
        decoration: BoxDecoration(
          // One surface step above whatever the tile is sitting on, so the
          // chips read on both the selected and the unselected tile without
          // a second border.
          color: ExampleSurface.of(context, selected ? 3 : 2),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.pill)),
        ),
        child: Text(
          label,
          // Night .72 over lightSurfaceHigh composites to (75,71,95) — 7.05:1
          // on paper — and pearl .68 keeps its Twilight value.
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: ExampleInk.secondary(context),
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
}

/// The escape hatch back to sign-in. 44 pt tall wherever it appears.
class _ExampleSignInLink extends StatelessWidget {
  const _ExampleSignInLink({required this.onTap, this.compact = false});

  final VoidCallback? onTap;

  /// In the app bar, where the question in front of it would not fit.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final button = TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        foregroundColor: ExampleInk.accent(context, ExampleColors.iris),
        textStyle: theme.textTheme.labelLarge,
      ),
      child: Text(
        context.tr('Sign in'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (compact) return button;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            context.tr('Already have an account?'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: ExampleInk.secondary(context),
            ),
          ),
        ),
        button,
      ],
    );
  }
}

/// The country picker plus number, dressed as a [ExampleAuthField].
///
/// The package draws its own `TextField` inside an `InputDecorator`, so the
/// box, the animated edge and the error line are rebuilt here instead: the
/// inner validator is silenced and an outer [FormField] carries the same
/// rule, which keeps `Form.validate` behaving exactly as for every other
/// field while the message lands under the box rather than inside the
/// decorator.
class _ExamplePhoneField extends StatefulWidget {
  const _ExamplePhoneField({
    required this.controller,
    required this.countrySelector,
    required this.onChanged,
    required this.validator,
  });

  final PhoneController controller;
  final CountrySelectorNavigator countrySelector;
  final ValueChanged<PhoneNumber> onChanged;
  final PhoneNumberInputValidator validator;

  @override
  State<_ExamplePhoneField> createState() => _ExamplePhoneFieldState();
}

class _ExamplePhoneFieldState extends State<_ExamplePhoneField> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'ExamplePhoneField');
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() {
    if (!mounted || _focusNode.hasFocus == _focused) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) => FormField<PhoneNumber>(
        initialValue: widget.controller.value,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (_) => widget.validator(widget.controller.value),
        builder: _buildField,
      );

  Widget _buildField(FormFieldState<PhoneNumber> field) {
    final theme = Theme.of(context);
    final error = field.errorText;
    final invalid = error != null;
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    // The same three edges as ExampleAuthField, resolved the same way.
    final edge = invalid
        ? ExampleInk.accent(context, ExampleColors.danger)
        : _focused
            ? ExampleTheme.pick(
                context,
                dark: ExamplePalette.of(context).borderEmphasis,
                light: ExamplePalette.of(context).accent,
              )
            : exampleControlEdge(context).color;
    final inputStyle = (theme.textTheme.bodyLarge ?? const TextStyle())
        .copyWith(color: ExampleInk.primary(context), fontSize: 16, height: 1.5);
    final muted = ExampleInk.tertiary(context);
    const radius = BorderRadius.all(Radius.circular(AppRadii.sm));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: duration,
          curve: ExampleMotion.arrive,
          decoration: BoxDecoration(
            color: ExampleSurface.of(context, 1),
            borderRadius: radius,
          ),
          foregroundDecoration: BoxDecoration(
            border: Border.all(color: edge),
            borderRadius: radius,
          ),
          child: PhoneFormField(
            key: const Key('signup_phone'),
            controller: widget.controller,
            focusNode: _focusNode,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.telephoneNumber],
            countrySelectorNavigator: widget.countrySelector,
            countryButtonStyle: CountryButtonStyle(
              textStyle: inputStyle,
              dropdownIconColor: muted,
              padding: const EdgeInsets.only(
                left: AppSpacing.sm,
                right: AppSpacing.xxs,
              ),
            ),
            style: inputStyle,
            cursorColor: ExampleInk.accent(context, ExampleColors.iris),
            decoration: InputDecoration(
              isDense: true,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(
                AppSpacing.xxs,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              hintText: context.tr('Mobile phone'),
              hintStyle: inputStyle.copyWith(color: muted),
              prefixIconConstraints: const BoxConstraints(
                minWidth: ExampleAuthField.controlSize,
                minHeight: ExampleAuthField.controlSize,
              ),
            ),
            // Silenced on purpose: the outer FormField above owns the same
            // rule, so the Form still refuses an invalid number while the
            // message renders under the box instead of inside it.
            validator: null,
            autovalidateMode: AutovalidateMode.disabled,
            onChanged: (number) {
              widget.onChanged(number);
              field.didChange(number);
            },
          ),
        ),
        ExampleStateSwitch(
          alignment: Alignment.topLeft,
          child: invalid
              ? Padding(
                  key: ValueKey('error:$error'),
                  padding: const EdgeInsets.only(top: AppSpacing.xs),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      error,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ExampleInk.accent(context, ExampleColors.danger),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('none')),
        ),
      ],
    );
  }
}

class _ReferralInvitationBanner extends StatelessWidget {
  const _ReferralInvitationBanner({
    required this.inviterDisplayName,
    this.welcomeAmount = 0,
    this.welcomeCurrency = 'USD',
  });

  final String inviterDisplayName;

  /// The welcome the invitee earns at qualification; 0 leaves the banner as
  /// the one line it always was.
  final double welcomeAmount;
  final String welcomeCurrency;

  /// The welcome sentence, or null when the programme states no amount.
  String? _welcomeLine(BuildContext context) => welcomeAmount <= 0
      ? null
      : context.tr(
          '{p0} after you verify, order a card and make your first top-up.',
          {'p0': formatReferralAmount(welcomeCurrency, welcomeAmount)});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final welcome = _welcomeLine(context);
    if (context.isExampleTheme) {
      return DecoratedBox(
        key: const Key('referral_invitation_banner'),
        decoration: BoxDecoration(
          color: ExampleSurface.of(context, 1),
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.sm)),
          border: ExampleBorders.emphasisOf(context),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Icon(
                Icons.mark_email_read_outlined,
                size: 20,
                color: ExampleInk.accent(context, ExampleColors.iris),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('Invited by {p0}', {'p0': inviterDisplayName}),
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: ExampleInk.primary(context)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (welcome != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        welcome,
                        key: const Key('signup_invitation_welcome'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ExampleInk.secondary(context),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final colors = theme.colorScheme;
    return Container(
      key: const Key('referral_invitation_banner'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.mark_email_read_outlined,
              color: colors.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('Invited by {p0}', {'p0': inviterDisplayName}),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colors.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (welcome != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    welcome,
                    key: const Key('signup_invitation_welcome'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onPrimaryContainer,
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

class _InvitationLoadingScreen extends StatelessWidget {
  const _InvitationLoadingScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(context.tr('Create account'))),
        body: LoadingState(
            label: context.tr('Checking your referral invitation')),
      );
}

class _InvitationFailureScreen extends StatelessWidget {
  const _InvitationFailureScreen({
    required this.failure,
    required this.onContinueWithoutInvitation,
    this.onRetry,
  });

  final ReferralInvitationFailure failure;
  final VoidCallback? onRetry;
  final VoidCallback onContinueWithoutInvitation;

  @override
  Widget build(BuildContext context) {
    final message = switch (failure.type) {
      ReferralInvitationFailureType.invalid =>
        'This referral invitation is invalid.',
      ReferralInvitationFailureType.expired =>
        'This referral invitation has expired or has already been used.',
      ReferralInvitationFailureType.network =>
        'We could not check this referral invitation. Check your connection and try again.',
    };
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('Create account'))),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mail_lock_outlined, size: 54),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (onRetry != null) ...[
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: Text(context.tr('Retry')),
                    ),
                  ],
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: onContinueWithoutInvitation,
                    child:
                        Text(context.tr('Create account without invitation')),
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

String _signupErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final marker = [
        data['code'],
        data['Code'],
        data['message'],
        data['Message'],
      ].whereType<Object>().join(' ').toLowerCase();
      if (marker.contains('invitation_email_mismatch') ||
          marker.contains('invited email') ||
          marker.contains('invitation email')) {
        return 'This invitation belongs to a different email address. Use the invited email to continue.';
      }
    }
  }
  return friendlyErrorMessage(error);
}

class _AccountTypeStep extends StatelessWidget {
  const _AccountTypeStep({
    required this.value,
    required this.onChanged,
    this.showBusiness = true,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final bool showBusiness;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          _AccountChoice(
            selected: value == 'personal',
            icon: Icons.person_outline,
            title: context.tr('Personal account'),
            description: context
                .tr('Manage your money, verification, wallets, and cards.'),
            onTap: () => onChanged('personal'),
          ),
          if (showBusiness) ...[
            const SizedBox(height: 10),
            _AccountChoice(
              selected: value == 'business',
              icon: Icons.business_outlined,
              title: context.tr('Business account'),
              description: context.tr(
                  'Apply for an organisation with owners, team, and documents.'),
              onTap: () => onChanged('business'),
            ),
          ],
        ],
      );
}

class _AccountChoice extends StatelessWidget {
  const _AccountChoice({
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return NeoSurfaceCard(
      color: selected ? colors.primaryContainer : colors.surface,
      borderColor: selected ? colors.primary : colors.outlineVariant,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor:
                  selected ? colors.primary : colors.surfaceContainerHighest,
              foregroundColor:
                  selected ? colors.onPrimary : colors.onSurfaceVariant,
              child: Icon(icon),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 3),
                  Text(description),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colors.primary : colors.outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.label, required this.value});
  final String label;
  final String value;

  /// Below this the label moves above the value: at 375 px the review panel
  /// is 279 px wide inside its padding, and an email in 175 px wraps badly.
  static const double _stackBelow = 300;

  @override
  Widget build(BuildContext context) {
    if (!context.isExampleTheme) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 86, child: Text(label)),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      );
    }
    final theme = Theme.of(context);
    final caption = Text(
      label,
      style: theme.textTheme.bodyMedium
          ?.copyWith(color: ExampleInk.secondary(context)),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final reading = Text(
      value,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: ExampleInk.primary(context),
        fontWeight: FontWeight.w600,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            if (constraints.maxWidth < _stackBelow || scale > 1.3) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [caption, const SizedBox(height: 2), reading],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 104, child: caption),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: reading),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SignupComplete extends StatelessWidget {
  const _SignupComplete({
    this.referralOutcome,
    required this.accountType,
    required this.email,
    required this.emailRequestFailed,
    required this.onConfirmEmail,
    required this.onResendEmail,
    required this.onContinue,
  });
  final ReferralSignupOutcome? referralOutcome;
  final String accountType;
  final String email;
  final bool emailRequestFailed;
  final VoidCallback onConfirmEmail;
  final VoidCallback onResendEmail;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      child: Icon(Icons.mark_email_read_outlined, size: 40),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      context.tr('Confirm your email'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      context.tr(
                          emailRequestFailed
                              ? 'Your account is created, but we could not request a confirmation email. Request a new code to confirm {p0}.'
                              : 'Your account is created. Check {p0} for a six-digit confirmation code. Delivery can take a few minutes.',
                          {'p0': email}),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                          'If the email is missing, check Spam or Junk, then request a new code.'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      accountType == 'business'
                          ? context.tr(
                              'After that we will guide you through representative verification, company details, associated people, and documents.')
                          : context.tr(
                              'After that your home screen will guide you through identity verification and funding your wallet.'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (referralOutcome != null) ...[
                      const SizedBox(height: 16),
                      ReferralSignupOutcomeView(outcome: referralOutcome!),
                    ],
                    const SizedBox(height: 26),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onConfirmEmail,
                        icon: const Icon(Icons.pin_outlined, size: 18),
                        label: Text(context.tr('Enter confirmation code')),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onResendEmail,
                      child: Text(context.tr('Resend confirmation email')),
                    ),
                    TextButton(
                      onPressed: onContinue,
                      child: Text(context.tr('I will do this at sign in')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

String? _required(String? value) =>
    value == null || value.trim().isEmpty ? 'Required' : null;

String? _emailValidator(String? value) {
  final text = value?.trim() ?? '';
  final valid = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  return valid ? null : 'Enter a valid email';
}

String? _passwordValidator(String? value) {
  final password = value ?? '';
  if (passwordMeetsPolicy(password)) return null;
  final missing = passwordRules
      .where((rule) => !rule.test(password))
      .map((rule) => rule.label)
      .toList();
  return 'Still needed: ${missing.join(', ')}';
}

/// Left column of the desktop signup: brand, promise, and the four steps.
/// The desktop left column: the same room as the sign-in hero, with the four
/// steps of this form standing in for the feature list so the user can see
/// how far the account takes them before they start typing.
class _ExampleSignupHero extends StatelessWidget {
  const _ExampleSignupHero({required this.currentStep, required this.steps});

  final int currentStep;
  final List<(String, String)> steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Shifted dawn, same as the sign-in hero: one room across the
          // divider rather than two panels.
          const ExampleAtmosphere.auth(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xxl + AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExampleLockup(height: 31),
                  const Spacer(),
                  ConstrainedBox(
                    // 640, not 580: the statement moved up to the desktop
                    // display tier and each of its two lines needs the room.
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Open your account\nin a few minutes.'),
                          // The desktop display tier. The shared ramp stops at
                          // 44 px and this hero was set at 34 in an 800 px
                          // column, which is below every competitor on the
                          // board. Desktop only — the hero does not render
                          // under 900 px, so nothing at 375 or 393 reflows.
                          style: AppTypography.displayXl(theme.textTheme),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          context.tr(
                              'Cards, accounts and crypto in one place. We only ask for what we need to verify you.'),
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: ExampleInk.secondary(context),
                            fontWeight: FontWeight.w400,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        for (var index = 0; index < steps.length; index++) ...[
                          _ExampleHeroStep(
                            number: index + 1,
                            title: steps[index].$1,
                            subtitle: steps[index].$2,
                            state: index < currentStep
                                ? _HeroStepState.done
                                : index == currentStep
                                    ? _HeroStepState.current
                                    : _HeroStepState.upcoming,
                          ),
                          if (index != steps.length - 1)
                            const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    AppDesignTheme.nameOf(context).isNotEmpty
                        ? AppDesignTheme.nameOf(context)
                        : context.tr('App'),
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

enum _HeroStepState { done, current, upcoming }

class _ExampleHeroStep extends StatelessWidget {
  const _ExampleHeroStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.state,
  });

  final int number;
  final String title;
  final String subtitle;
  final _HeroStepState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = state != _HeroStepState.upcoming;
    final duration = ExampleMotion.of(context, ExampleMotion.state);
    final fill = ExampleInk.accent(context, ExampleColors.violet);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: duration,
          curve: ExampleMotion.arrive,
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: switch (state) {
              _HeroStepState.current => fill,
              _HeroStepState.done => ExampleSurface.of(context, 2),
              _HeroStepState.upcoming => ExampleSurface.of(context, 1),
            },
            border: Border.all(
              color: state == _HeroStepState.current
                  ? fill
                  : exampleControlEdge(context).color,
            ),
          ),
          child: state == _HeroStepState.done
              ? Icon(
                  Icons.check_rounded,
                  size: 17,
                  color: ExampleInk.accent(context, ExampleColors.success),
                )
              : Text(
                  '$number',
                  style: theme.textTheme.labelLarge?.copyWith(
                    // The number sits on the fill while the step is current,
                    // so it stays pearl there and takes the theme ink once the
                    // disc is a surface again.
                    color: state == _HeroStepState.current
                        ? ExamplePalette.of(context).onFill
                        : active
                            ? ExampleInk.primary(context)
                            : ExampleInk.tertiary(context),
                  ),
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: active
                      ? ExampleInk.primary(context)
                      : ExampleInk.secondary(context),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: ExampleInk.secondary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The note under the referral field when the prefilled code was a campaign
/// link that no longer attributes: the sign-up is a normal one from here.
class _InactiveInvitationLinkNote extends StatelessWidget {
  const _InactiveInvitationLinkNote({required this.required, super.key});

  /// The tenant requires a code, so the customer needs another one.
  final bool required;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_off_rounded, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('This invitation link is no longer active'),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  required
                      ? context.tr('Enter another referral code to continue.')
                      : context.tr(
                          'You can still sign up without a code, or enter another one.'),
                  style: theme.textTheme.bodySmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
