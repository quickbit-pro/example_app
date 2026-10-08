import 'package:dio/dio.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
// Proof that the sign-in form stays quiet until it is asked, then keeps up.
//
// Validation *timing* is presentation: the predicates and the messages belong
// to the product and are untouched here, but *when* a field turns red is the
// screen's manners. Two failure modes bracket the right answer. Validate from
// the first keystroke and "Enter a valid email" sits under the box while the
// customer is still typing the first letter of their address. Validate only on
// submit — what this screen did — and the red stays there after they have
// fixed it, so the form goes on accusing them of a mistake they already
// corrected until they press the button a second time.
//
// The EXAMPLE form therefore runs quiet-then-live: `AutovalidateMode.disabled`
// until Sign in has been pressed and refused, `AutovalidateMode.always` from
// then on. The white-label `_LoginCard` is deliberately NOT changed, and the
// last group pins that: a non-EXAMPLE tenant keeps the exact Material behaviour
// it shipped with.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/auth/data/session_credential_storage.dart';
import 'package:mobile_flutter/features/auth/presentation/example_auth_field.dart';
import 'package:mobile_flutter/features/auth/presentation/login_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two messages under test. They are the screen's own copy, quoted here so
/// a change to the wording fails this file rather than silently passing it.
const _emailError = 'Enter a valid email';
const _passwordError = 'Use at least 8 characters';

/// Long enough to clear the 8-character minimum.
const _goodPassword = 'correct-horse';
const _goodEmail = 'naem@example.com';

AppBranding _branding({required bool light, bool example = true}) => AppBranding(
      appName: example ? 'EXAMPLE' : 'Acme Pay',
      brandId: example ? 'example' : 'generic',
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: light ? 'light' : 'dark',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: 'EXAMPLE',
    );

const _tenant = MobileTenantConfig(
  companyName: 'EXAMPLE',
  brandName: 'EXAMPLE',
  referralsEnabled: true,
  referralRegistrationMode: 'open',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
  supportEmail: 'support@example.com',
);

/// No enrolled biometric, so `_maybeAutoPromptBiometric` returns before it can
/// raise an OS prompt the test has no way to answer.
const _noBiometrics = BiometricEnrollment(
  enabled: false,
  hasToken: false,
  email: '',
  userName: '',
  refreshToken: '',
);

const _noCapability = BiometricCapability(
  available: false,
  types: [],
  reason: BiometricUnavailableReason.none,
);

/// No restored session, and no keychain.
///
/// `AuthController.build` awaits this before it can publish a state, and the
/// real store talks to a platform channel that does not exist under
/// `flutter_test`. Left alone the controller stays `AsyncLoading` forever,
/// which disables Sign in — so the button under test would never be pressed
/// and the form would never be refused.
class _NoStoredSession implements SessionCredentialStorage {
  @override
  Future<StoredSession?> read() async => null;

  @override
  Future<void> save(StoredSession session) async {}

  @override
  Future<void> clear() async {}
}

/// The EXAMPLE input for a captioned field.
Finder _exampleInput(String label) => find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is ExampleAuthField && widget.label == label,
      ),
      matching: find.byType(EditableText),
    );

/// The white-label input for the same field, found through its floating label.
Finder _materialInput(String label) => find.descendant(
      of: find.widgetWithText(TextFormField, label),
      matching: find.byType(EditableText),
    );

Finder get _exampleSubmit => find.byWidgetPredicate(
      (widget) => widget is ExampleGlassButton && widget.label == 'Sign in',
    );

Finder get _materialSubmit => find.widgetWithText(FilledButton, 'Sign in');

/// The sign-in screen carries an ambient sheen that never stops, so
/// `pumpAndSettle` here would spin until it timed out. Every state change under
/// test is a cross-fade an order of magnitude shorter than this wait.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required bool light,
  bool example = true,
  AuthController? returningController,
  AuthApi? api,
  Size size = const Size(375, 812),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final branding = _branding(light: light, example: example);
  final themes = buildAppThemes(branding);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        if (api != null) authApiProvider.overrideWithValue(api),
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'https://example.invalid',
            branding: branding,
          ),
        ),
        if (returningController != null)
          authControllerProvider.overrideWith(() => returningController),
        sessionStorageProvider.overrideWithValue(_NoStoredSession()),
        mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
        biometricCapabilityProvider.overrideWith((ref) async =>
            returningController == null
                ? _noCapability
                : const BiometricCapability(
                    available: true,
                    types: [],
                    reason: BiometricUnavailableReason.none)),
        biometricEnrollmentProvider.overrideWith((ref) async =>
            returningController == null
                ? _noBiometrics
                : const BiometricEnrollment(
                    enabled: true,
                    hasToken: true,
                    email: 'test@example.test',
                    userName: 'Tester',
                    refreshToken: 'saved')),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: light ? ThemeMode.light : ThemeMode.dark,
        home: const LoginScreen(),
      ),
    ),
  );
  // The screen waits 350 ms before deciding whether to raise the biometric
  // prompt. Clear it here or the delay is a pending timer at teardown.
  await tester.pump(const Duration(milliseconds: 400));
  await _settle(tester);
}

/// Press Sign in with whatever is currently typed. The button can sit below the
/// fold on a 375 pt phone, so scroll it into range first.
Future<void> _press(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await _settle(tester);
  await tester.tap(button);
  await _settle(tester);
}

class _LockedAuth extends AuthController {
  _LockedAuth(
      {this.failure = BiometricLoginFailure.cancelled, this.stalled = false});
  final bool stalled;
  int cancellations = 0;
  @override
  void cancelBiometricLogin() {
    cancellations++;
    state = const AsyncData(AuthState());
  }

  final BiometricLoginFailure failure;
  int prompts = 0;
  @override
  Future<AuthState> build() async => const AuthState(biometricLocked: true);
  @override
  Future<void> loginWithBiometrics({required String reason}) async {
    prompts++;
    if (stalled) {
      state = const AsyncLoading();
      return;
    }
    state = AsyncError(BiometricLoginException(failure), StackTrace.current);
  }
}

void main() {
  for (final outcome in ['success', 'failure', 'cancel']) {
    testWidgets(
        'password recovery autofill uses email and replaces login only on $outcome',
        (tester) async {
      final api = _ResetAutofillApi(fail: outcome == 'failure');
      await _pumpLogin(tester,
          light: true, api: api, size: const Size(500, 1200));
      final loginPassword =
          tester.widget<EditableText>(_exampleInput('Password')).controller;
      await tester.enterText(_exampleInput('Email'), 'member@example.test');
      await tester.enterText(_exampleInput('Password'), 'OldPassword123!');
      final forgot = find.text('Forgot password?');
      await tester.ensureVisible(forgot);
      await tester.tap(forgot);
      await _settle(tester);
      await tester.tap(find.text('Send code'));
      await _settle(tester);

      Finder hinted(String hint) => find.byWidgetPredicate((w) =>
          w is EditableText && (w.autofillHints?.contains(hint) ?? false));
      final passwords = hinted(AutofillHints.newPassword);
      expect(passwords, findsNWidgets(2));
      final username = find.byWidgetPredicate((w) =>
          w is EditableText &&
          w.readOnly &&
          (w.autofillHints?.contains(AutofillHints.username) ?? false));
      expect(username, findsOneWidget);
      final usernameWidget = tester.widget<EditableText>(username);
      expect(usernameWidget.controller.text, 'member@example.test');
      expect(usernameWidget.readOnly, isTrue);
      expect(usernameWidget.autofillHints!.first, AutofillHints.username);
      final code = hinted(AutofillHints.oneTimeCode);
      await tester.ensureVisible(code);
      await tester.enterText(code, '123456');
      const updated = 'UpdatedPassword456!';
      for (final field in [passwords.first, passwords.last]) {
        await tester.ensureVisible(field);
        await tester.enterText(field, updated);
      }
      final fields =
          tester.testTextInput.setClientArgs!['fields'] as List<dynamic>;
      final credentials =
          fields.map((dynamic f) => f['autofill'] as Map).toList();
      final usernames = credentials
          .where((f) => (f['hints'] as List).contains(AutofillHints.username));
      expect(usernames, hasLength(1));
      expect(usernames.single['editingValue']['text'], 'member@example.test');
      expect(
          credentials.any(
              (f) => (f['hints'] as List).contains(AutofillHints.oneTimeCode)),
          isFalse);
      expect(
          credentials.where(
              (f) => (f['hints'] as List).contains(AutofillHints.newPassword)),
          hasLength(2));
      expect(
          tester.state<EditableTextState>(code).currentAutofillScope,
          isNot(same(tester
              .state<EditableTextState>(passwords.first)
              .currentAutofillScope)));

      if (outcome == 'cancel') {
        await tester.tap(find.byTooltip('Close'));
      } else {
        final reset = find.text('Reset password');
        await tester.ensureVisible(reset);
        await tester.tap(reset);
      }
      await _settle(tester);
      final saved = tester.testTextInput.log.where((call) =>
          call.method == 'TextInput.finishAutofillContext' &&
          call.arguments == true);
      if (outcome == 'success') {
        expect(api.resetEmail, 'member@example.test');
        expect(api.resetPasswordValue, updated);
        expect(loginPassword.text, updated);
        expect(saved, hasLength(1));
      } else {
        expect(loginPassword.text, 'OldPassword123!');
        expect(saved, isEmpty);
        if (outcome == 'failure') expect(passwords, findsNWidgets(2));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets(
      'password escape stays enabled while fingerprint unlock is stalled',
      (tester) async {
    final auth = _LockedAuth(stalled: true);
    await _pumpLogin(tester,
        light: false, example: false, returningController: auth);
    expect(find.text('Unlocking…'), findsOneWidget);
    final fallback = find.widgetWithText(TextButton, 'Use password instead');
    expect(tester.widget<TextButton>(fallback).onPressed, isNotNull);
    await tester.tap(fallback);
    await _settle(tester);
    expect(auth.cancellations, 1);
    expect(_materialInput('Password'), findsOneWidget);
    expect(tester.widget<FilledButton>(_materialSubmit).onPressed, isNotNull);
    expect(find.text('Unlocking…'), findsNothing);
  });

  testWidgets('timed out unlock shows password form', (tester) async {
    final auth = _LockedAuth(failure: BiometricLoginFailure.timedOut);
    await _pumpLogin(tester,
        light: false, example: false, returningController: auth);
    expect(_materialInput('Password'), findsOneWidget);
    expect(find.text('Use password instead'), findsNothing);
  });

  for (final example in [false, true]) {
    testWidgets('expired biometric session shows password form, example=$example',
        (tester) async {
      final auth =
          _LockedAuth(failure: BiometricLoginFailure.noStoredCredentials);
      await _pumpLogin(tester,
          light: true, example: example, returningController: auth);
      expect(auth.prompts, 1);
      expect(find.text('Use password instead'), findsNothing);
      expect(example ? _exampleInput('Password') : _materialInput('Password'),
          findsOneWidget);
      await _settle(tester);
      expect(auth.prompts, 1);
    });
  }

  testWidgets('returning PWA prompts once and offers unlock before password',
      (tester) async {
    final auth = _LockedAuth();
    await _pumpLogin(tester, light: true, returningController: auth);
    expect(auth.prompts, 1);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(EditableText), findsNothing);
    await _settle(tester);
    expect(auth.prompts, 1);
    await tester.tap(find.text('Unlock'));
    await _settle(tester);
    expect(auth.prompts, 2);
    await tester.tap(find.text('Use password instead'));
    await _settle(tester);
    expect(_exampleInput('Password'), findsOneWidget);
  });

  for (final light in [false, true]) {
    final theme = light ? 'Pearl' : 'Twilight';

    testWidgets(
        'the form says nothing while it is still being filled in '
        '($theme)', (tester) async {
      await _pumpLogin(tester, light: light);

      // A half-typed address and a short password: both would fail validation
      // if the form were live, and neither is a mistake yet.
      await tester.enterText(_exampleInput('Email'), 'n');
      await _settle(tester);
      await tester.enterText(_exampleInput('Password'), 'abc');
      await _settle(tester);

      expect(find.text(_emailError), findsNothing);
      expect(find.text(_passwordError), findsNothing);
    });

    testWidgets('a refused Sign in puts the reason under each field ($theme)',
        (tester) async {
      await _pumpLogin(tester, light: light);

      await _press(tester, _exampleSubmit);

      expect(find.text(_emailError), findsOneWidget);
      expect(find.text(_passwordError), findsOneWidget);
    });

    testWidgets(
        'each error clears as its own field is corrected, without a '
        'second press ($theme)', (tester) async {
      await _pumpLogin(tester, light: light);
      await _press(tester, _exampleSubmit);
      expect(find.text(_emailError), findsOneWidget);
      expect(find.text(_passwordError), findsOneWidget);

      // Fixing the address takes back the accusation about the address, and
      // leaves the one about the password standing — the form answers per
      // field, not all-or-nothing.
      await tester.enterText(_exampleInput('Email'), _goodEmail);
      await _settle(tester);
      expect(find.text(_emailError), findsNothing);
      expect(find.text(_passwordError), findsOneWidget);

      await tester.enterText(_exampleInput('Password'), _goodPassword);
      await _settle(tester);
      expect(find.text(_emailError), findsNothing);
      expect(find.text(_passwordError), findsNothing);
    });
  }

  group('white-label', () {
    // The Material form is out of scope for the EXAMPLE redesign, so what is
    // proved here is that it was left exactly as it was: quiet until the
    // button is pressed, and — because it never turns autovalidation on — the
    // error still sits there after the field is corrected, until the next
    // press re-runs the validators. That is the Flutter default, and changing
    // it would be a behaviour change to a tenant that did not ask for one.
    testWidgets('the Material form still validates on press only',
        (tester) async {
      await _pumpLogin(tester, light: false, example: false);

      await tester.enterText(_materialInput('Email'), 'n');
      await _settle(tester);
      expect(find.text(_emailError), findsNothing);

      await _press(tester, _materialSubmit);
      expect(find.text(_emailError), findsOneWidget);
      expect(find.text(_passwordError), findsOneWidget);

      // Correcting the address does not take the accusation back — the
      // Material form is not autovalidating, and this is the behaviour the
      // EXAMPLE form deliberately moved away from.
      await tester.enterText(_materialInput('Email'), _goodEmail);
      await _settle(tester);
      expect(find.text(_emailError), findsOneWidget);

      // It clears on the next press, when the validators run again. The
      // password is left short on purpose: this proves re-validation without
      // handing a valid credential to a login the test has no server for.
      await _press(tester, _materialSubmit);
      expect(find.text(_emailError), findsNothing);
      expect(find.text(_passwordError), findsOneWidget);
    });
  });
}

class _ResetAutofillApi extends AuthApi {
  _ResetAutofillApi({required this.fail}) : super(Dio());
  final bool fail;
  String? resetEmail;
  String? resetPasswordValue;

  @override
  Future<int> requestPasswordReset(String email) async => 0;

  @override
  Future<void> resetPassword(
      {required String email,
      required String code,
      required String newPassword}) async {
    if (fail) throw Exception('Simulated reset failure');
    resetEmail = email;
    resetPasswordValue = newPassword;
  }
}
