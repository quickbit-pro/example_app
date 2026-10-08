import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/auth/presentation/account_claim_screen.dart';
import 'package:mobile_flutter/features/auth/presentation/forgot_password_sheet.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/features/profile/presentation/security_sheets.dart';
import 'package:mobile_flutter/flavors.dart';

class _SignedIn extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
      session: AuthSession(
          accessToken: 'test',
          refreshToken: 'test',
          userName: 'Member',
          email: 'member@example.test'));
}

class _Api extends AuthApi {
  _Api() : super(Dio());
  bool failChange = false;
  int changeCalls = 0;
  @override
  Future<AccountSecurity> changePassword(
      {required String currentPassword, required String newPassword}) async {
    changeCalls++;
    if (failChange) throw Exception('Change rejected');
    return AccountSecurity.fromJson({});
  }

  @override
  Future<AccountClaimChallenge> requestAccountClaim(String email) async =>
      AccountClaimChallenge(
          id: 'test', expiresAt: DateTime(2030), message: 'Check your email');
  @override
  Future<int> requestPasswordReset(String email) async => 0;
}

Future<void> _pump(WidgetTester tester,
    {required bool example, required String flow, _Api? api}) async {
  tester.view.physicalSize = const Size(500, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final branding = AppBranding(
    appName: example ? 'Example' : 'Test',
    brandId: example ? 'example' : 'generic',
    primarySeedHex: '7B6CF6',
    accentSeedHex: 'A78BFA',
    loginBackgroundHex: '',
    themeMode: 'light',
    fontFamily: '',
    logoAsset: '',
    radiusScale: '1',
    supportEmail: '',
    supportPhone: '',
    legalEntity: 'Test',
  );
  final themes = buildAppThemes(branding);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      authApiProvider.overrideWithValue(api ?? _Api()),
      authControllerProvider.overrideWith(_SignedIn.new),
      appConfigProvider.overrideWithValue(AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'https://example.invalid',
          branding: branding)),
    ],
    child: MaterialApp(
        theme: themes.light,
        home: flow == 'connect'
            ? const AccountClaimScreen()
            : Consumer(
                builder: (context, ref, _) => Scaffold(
                        body: TextButton(
                      onPressed: () => flow == 'change'
                          ? showChangePasswordSheet(context, ref)
                          : showForgotPasswordSheet(context,
                              initialEmail: 'member@example.test'),
                      child: const Text('Open'),
                    )))),
  ));
  await tester.pump();
  if (flow == 'connect') {
    final email = find.byWidgetPredicate((w) =>
        w is EditableText &&
        w.autofillHints?.contains(AutofillHints.email) == true);
    await tester.ensureVisible(email);
    await tester.enterText(email, 'member@example.test');
    final send = find.text('Send verification code');
    await tester.ensureVisible(send);
    await tester.tap(send);
  } else {
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    if (flow == 'reset') await tester.tap(find.text('Send code'));
  }
  // Example's sheen runs continuously; advance the transition explicitly.
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final example in [true, false]) {
    testWidgets(
        'Reset uses six cells with paste and OTP autofill (Example: $example)',
        (tester) async {
      await _pump(tester, example: example, flow: 'reset');
      final otp = find.byType(ExampleOtpField);
      expect(otp, findsOneWidget);
      expect(find.descendant(of: otp, matching: find.byType(Expanded)),
          findsNWidgets(6));
      final input =
          find.descendant(of: otp, matching: find.byType(EditableText));
      await tester.ensureVisible(input);
      await tester.enterText(input, '12a34567');
      await tester.pump();
      final field = tester.widget<EditableText>(input);
      expect(field.controller.text, '123456');
      expect(field.autofillHints, contains(AutofillHints.oneTimeCode));
      for (final digit in '123456'.split('')) {
        expect(find.descendant(of: otp, matching: find.text(digit)),
            findsOneWidget);
      }
      tester.testTextInput
          .updateEditingValue(const TextEditingValue(text: '654321'));
      await tester.pump();
      expect(field.controller.text, '654321');
      await tester.enterText(input, '65432');
      await tester.pump();
      expect(field.controller.text, '65432');
      expect(find.descendant(of: otp, matching: find.text('')), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    for (final fails in [false, true]) {
      testWidgets(
          'Change password saves correct account only after success (Example: $example, fails: $fails)',
          (tester) async {
        final api = _Api()..failChange = fails;
        await _pump(tester, example: example, flow: 'change', api: api);
        final passwords = find.byWidgetPredicate((w) =>
            w is EditableText &&
            w.autofillHints?.contains(AutofillHints.newPassword) == true);
        final current = find.byWidgetPredicate((w) =>
            w is EditableText &&
            w.autofillHints?.contains(AutofillHints.password) == true);
        await tester.enterText(current, 'Old-password!82');
        for (final field in [passwords.first, passwords.last]) {
          await tester.ensureVisible(field);
          await tester.enterText(field, 'New-password!83');
        }
        final username =
            (tester.testTextInput.setClientArgs!['fields'] as List<dynamic>)
                .map((dynamic field) => field['autofill'] as Map)
                .singleWhere((field) =>
                    (field['hints'] as List).contains(AutofillHints.username));
        expect(username['editingValue']['text'], 'member@example.test');
        tester.testTextInput.log.clear();
        final submit = find.text('Change password').last;
        await tester.ensureVisible(submit);
        await tester.tap(submit);
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(api.changeCalls, 1);
        expect(
            tester.testTextInput.log
                .where((call) =>
                    call.method == 'TextInput.finishAutofillContext' &&
                    call.arguments == true)
                .length,
            fails ? 0 : 1);
        await tester.pumpWidget(const SizedBox.shrink());
        expect(
            tester.testTextInput.log
                .where((call) =>
                    call.method == 'TextInput.finishAutofillContext' &&
                    call.arguments == true)
                .length,
            fails ? 0 : 1);
      });
    }
    for (final flow in ['change', 'reset']) {
      testWidgets(
          '$flow autofill fills both new password fields (Example: $example)',
          (tester) async {
        await _pump(tester, example: example, flow: flow);
        final fields = find.byWidgetPredicate((w) =>
            w is EditableText &&
            w.autofillHints?.contains(AutofillHints.newPassword) == true);
        expect(fields, findsNWidgets(2));
        await tester.ensureVisible(fields.first);
        await tester.showKeyboard(fields.first);
        final states = tester.stateList<EditableTextState>(fields).toList();
        final scope = states.first.currentAutofillScope;
        expect(scope, isNotNull);
        expect(states.last.currentAutofillScope, same(scope));
        // Confirm the platform receives both password fields when one is focused.
        final platformFields =
            tester.testTextInput.setClientArgs!['fields'] as List<dynamic>;
        if (flow == 'reset' || flow == 'change') {
          final autofill =
              platformFields.map((dynamic field) => field['autofill'] as Map);
          final username = autofill.singleWhere((field) =>
              (field['hints'] as List).contains(AutofillHints.username));
          expect(username['editingValue']['text'], 'member@example.test');
          expect(
              autofill.any((field) =>
                  (field['hints'] as List).contains(AutofillHints.oneTimeCode)),
              isFalse);
        }
        final ids = platformFields
            .map((dynamic field) => field['autofill']['uniqueIdentifier'])
            .toSet();
        expect(ids, containsAll(states.map((state) => state.autofillId)));
        const generated = 'Generated-password!83';
        await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
          'flutter/textinput',
          const JSONMethodCodec().encodeMethodCall(MethodCall(
            'TextInputClient.updateEditingStateWithTag',
            [
              0,
              {
                for (final state in states)
                  state.autofillId:
                      const TextEditingValue(text: generated).toJSON()
              },
            ],
          )),
          (_) {},
        );
        await tester.pump();
        for (final state in states) {
          expect(state.widget.controller.text, generated);
        }
        // Manual editing still requires independent confirmation.
        await tester.enterText(fields.first, 'Another-password!84');
        expect(states.last.widget.controller.text, generated);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  for (final example in [true, false]) {
    testWidgets(
        'connect lets both new password fields be shown (Example: $example)',
        (tester) async {
      await _pump(tester, example: example, flow: 'connect');
      final fields = find.byWidgetPredicate((w) =>
          w is EditableText &&
          w.autofillHints?.contains(AutofillHints.newPassword) == true);
      expect(fields, findsNWidgets(2));
      List<bool> obscured() => tester
          .widgetList<EditableText>(fields)
          .map((field) => field.obscureText)
          .toList();
      expect(obscured(), [true, true]);
      // One eye per field, and each works on its own field only: checking
      // the confirmation does not expose the password above it.
      final eyes = find.byTooltip('Show password');
      expect(eyes, findsNWidgets(2));
      await tester.ensureVisible(eyes.last);
      await tester.tap(eyes.last);
      await tester.pump();
      expect(obscured(), [true, false]);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Show password'));
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(obscured(), [false, false]);
      await tester.tap(find.byTooltip('Hide password').last);
      await tester.pump();
      expect(obscured(), [false, true]);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
