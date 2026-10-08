// The customer sheet design keeps the local app's auth contracts: existing
// validation, immediate resend availability, shared busy state, and Material
// presentation for other brands. Exercise the new layout around those flows.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/auth/presentation/example_auth_field.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/features/auth/presentation/email_verification_sheet.dart';
import 'package:mobile_flutter/features/auth/presentation/forgot_password_sheet.dart';
import 'package:mobile_flutter/features/profile/presentation/security_sheets.dart';
import 'package:mobile_flutter/flavors.dart';

const _email = 'naem@example.com';

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

/// A 500, which `friendlyErrorMessage` maps to a sentence this test asserts
/// on, so the copy under test is the copy a customer would actually read.
DioException _serverDown() => DioException(
      requestOptions: RequestOptions(path: '/api/v1/mobile/auth'),
      response: Response<Object>(
        requestOptions: RequestOptions(path: '/api/v1/mobile/auth'),
        statusCode: 503,
      ),
    );

const _serverDownCopy = 'The service is temporarily unavailable. Try again '
    'shortly.';

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi({
    this.failRequestReset = false,
    this.cooldown = 0,
    this.failReset = false,
    this.failResend = false,
    this.failVerify = false,
    this.hangResend = false,
  }) : super(Dio());

  final int cooldown;
  final bool failRequestReset;
  final bool failReset;
  final bool failResend;
  final bool failVerify;

  /// Hold resends open so tests can inspect the existing shared busy state.
  /// The first recovery request completes to reveal the password step.
  final bool hangResend;

  int _sends = 0;

  final List<String> calls = <String>[];

  @override
  Future<int> requestPasswordReset(String email) async {
    calls.add('requestPasswordReset:$email');
    if (hangResend && _sends++ > 0) await Completer<void>().future;
    if (failRequestReset) throw _serverDown();
    return cooldown;
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    calls.add('resetPassword:$email:$code');
    if (failReset) throw _serverDown();
  }

  @override
  Future<void> resendEmailVerification(String email) async {
    calls.add('resendEmailVerification:$email');
    if (hangResend) await Completer<void>().future;
    if (failResend) throw _serverDown();
  }

  @override
  Future<void> verifyEmail({
    required String email,
    required String code,
  }) async {
    calls.add('verifyEmail:$email:$code');
    if (failVerify) throw _serverDown();
  }
}

/// An API whose send never completes, so the sheet can be observed while it
/// is still asking.
class _HangingAuthApi extends AuthApi {
  _HangingAuthApi() : super(Dio());

  @override
  Future<void> resendEmailVerification(String email) =>
      Completer<void>().future;
}

/// Complete the initial send after the customer has entered a code.
class _GatedAuthApi extends AuthApi {
  _GatedAuthApi() : super(Dio());

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<void> resendEmailVerification(String email) => _gate.future;
}

/// The brand's own typefaces, so every width and truncation assertion is
/// measured in Geist rather than in the test font, whose glyphs are square
/// boxes roughly twice Geist's advance width.
const _exampleFonts = <String, List<String>>{
  'Geist': [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
    'Geist-Bold.ttf',
  ],
  'GeistMono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
};

Future<void> _loadFonts() async {
  for (final entry in _exampleFonts.entries) {
    final loader = FontLoader(entry.key);
    var found = false;
    for (final file in entry.value) {
      final font = File('assets/fonts/$file');
      if (!font.existsSync()) continue;
      found = true;
      loader.addFont(
        Future.value(ByteData.view(font.readAsBytesSync().buffer)),
      );
    }
    if (found) await loader.load();
  }
}

/// A screen with a single control that opens the sheet under test, so the
/// sheet is reached through a real `showModalBottomSheet` route rather than
/// pumped naked.
class _Host extends StatelessWidget {
  const _Host({required this.open});

  final Future<void> Function(BuildContext) open;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Builder(
            builder: (inner) => TextButton(
              onPressed: () => open(inner),
              child: const Text('open the sheet'),
            ),
          ),
        ),
      );
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required AuthApi api,
  required Future<void> Function(BuildContext) open,
  required bool light,
  Size size = const Size(375, 812),
  bool example = true,
  double textScale = 1,
  bool reducedMotion = false,
  DateTime Function()? now,
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  final themes = buildAppThemes(_branding(light: light, example: example));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authApiProvider.overrideWithValue(api),
        if (now != null) passwordRecoveryClockProvider.overrideWithValue(now),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: light ? ThemeMode.light : ThemeMode.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reducedMotion,
          ),
          child: child!,
        ),
        home: _Host(open: open),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('open the sheet'));
  await tester.pumpAndSettle();
}

/// Every string these sheets write renders whole. The one exception is the
/// customer's own address, which arrives at whatever length it likes and
/// whose row contract is to ellipsize rather than overflow.
void _expectAppCopyIsWhole(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.didExceedMaxLines) continue;
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (text == _email) continue;
    fail('Truncated: "$text"');
  }
}

/// WCAG relative luminance of an opaque colour.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

/// [fg] composited onto opaque [bg]. Every ink in this system carries an
/// alpha, so a ratio taken without this step is measuring a colour nothing
/// ever paints.
Color _over(Color fg, Color bg) => Color.from(
      alpha: 1,
      red: fg.r * fg.a + bg.r * (1 - fg.a),
      green: fg.g * fg.a + bg.g * (1 - fg.a),
      blue: fg.b * fg.a + bg.b * (1 - fg.a),
    );

/// WCAG 2.1 contrast of [fg] against [bg], alpha-composited first.
double _contrast(Color fg, Color bg) {
  final a = _luminance(_over(fg, bg));
  final b = _luminance(bg);
  final hi = math.max(a, b);
  final lo = math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/// Every pressable in the sheet clears the 44 pt floor in both directions.
///
/// Returns how many controls it measured, so a caller can prove the check
/// was not simply iterating an empty list.
int _expectTapTargets(WidgetTester tester) {
  var measured = 0;
  for (final finder in <Finder>[
    find.byType(ExampleSheetCta),
    find.byType(ExampleSheetTextAction),
  ]) {
    for (final element in finder.evaluate()) {
      final size = tester.getSize(find.byElementPredicate((e) => e == element));
      expect(
        size.height,
        greaterThanOrEqualTo(44),
        reason: '${element.widget.runtimeType} is ${size.height} pt tall',
      );
      expect(size.width, greaterThanOrEqualTo(44));
      measured++;
    }
  }
  return measured;
}

Future<void> _openForgotPassword(
  WidgetTester tester, {
  required AuthApi api,
  required bool light,
  Size size = const Size(375, 812),
  bool example = true,
  double textScale = 1,
  bool reducedMotion = false,
  DateTime Function()? now,
}) =>
    _pumpHost(
      tester,
      api: api,
      light: light,
      size: size,
      example: example,
      textScale: textScale,
      reducedMotion: reducedMotion,
      now: now,
      open: (context) => showForgotPasswordSheet(context, initialEmail: _email),
    );

Future<void> _openVerification(
  WidgetTester tester, {
  required AuthApi api,
  required bool light,
  Size size = const Size(375, 812),
  bool example = true,
  bool sendCodeFirst = false,
  double textScale = 1,
  bool reducedMotion = false,
}) =>
    _pumpHost(
      tester,
      api: api,
      light: light,
      size: size,
      example: example,
      textScale: textScale,
      reducedMotion: reducedMotion,
      open: (context) => showEmailVerificationSheet(
        context,
        email: _email,
        sendCodeFirst: sendCodeFirst,
      ),
    );

/// Step 1 -> step 2 of the recovery sheet.
Future<void> _sendCode(WidgetTester tester) async {
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
}

const _viewports = <(String, Size)>[
  ('375', Size(375, 812)),
  ('393', Size(393, 852)),
  ('834', Size(834, 1194)),
  ('1440', Size(1440, 900)),
];

Future<void> _tapAction(WidgetTester tester, String label) async {
  final action = find.text(label);
  await tester.ensureVisible(action);
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _fillReset(
  WidgetTester tester, {
  String code = '123456',
  String password = 'Sup3rSecretPass',
  String? confirmation,
}) async {
  final otp = find.descendant(
      of: find.byType(ExampleOtpField), matching: find.byType(EditableText));
  final passwords = find.byWidgetPredicate((w) =>
      w is EditableText &&
      (w.autofillHints?.contains(AutofillHints.newPassword) ?? false));
  await tester.enterText(otp, code);
  await tester.enterText(passwords.first, password);
  await tester.enterText(passwords.last, confirmation ?? password);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('resend respects server cooldown after backgrounding and keeps input', (tester) async {
    var now = DateTime.utc(2026, 9, 23);
    final api = _FakeAuthApi(cooldown: 60);
    await _openForgotPassword(tester, api: api, light: false, now: () => now);
    await _sendCode(tester);
    await tester.enterText(find.descendant(of: find.byType(ExampleOtpField), matching: find.byType(EditableText)), '123');
    expect(find.text('Resend in 60s'), findsOneWidget);
    await tester.tap(find.text('Resend in 60s'));
    expect(api.calls.where((c) => c.startsWith('requestPasswordReset:')).length, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    now = now.add(const Duration(seconds: 61));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Send a new code'), findsOneWidget);
    expect(tester.widget<ExampleOtpField>(find.byType(ExampleOtpField)).controller.text, '123');
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.startsWith('requestPasswordReset:')).length, 2);
    expect(find.text('Resend in 60s'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final light in [true, false]) {
    testWidgets(
        'reset code uses six cells with paste, deletion and autofill (light: $light)',
        (tester) async {
      await _openForgotPassword(tester, api: _FakeAuthApi(), light: light);
      await _sendCode(tester);
      final otp = find.byType(ExampleOtpField);
      final input =
          find.descendant(of: otp, matching: find.byType(EditableText));
      await tester.enterText(input, '1a2 34567');
      await tester.pump();
      final field = tester.widget<ExampleOtpField>(otp);
      expect(field.controller.text, '123456');
      final cells = find.descendant(of: otp, matching: find.byType(Text));
      expect(tester.widgetList<Text>(cells).map((w) => w.data).toList(),
          ['1', '2', '3', '4', '5', '6']);
      await tester.enterText(input, '12345');
      await tester.pump();
      expect(tester.widgetList<Text>(cells).map((w) => w.data).last, '');
      final editable = tester.state<EditableTextState>(input);
      expect(
          editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/textinput',
        const JSONMethodCodec().encodeMethodCall(MethodCall(
          'TextInputClient.updateEditingStateWithTag',
          [
            0,
            {
              editable.autofillId:
                  const TextEditingValue(text: '654321').toJSON(),
            }
          ],
        )),
        (_) {},
      );
      await tester.pump();
      expect(field.controller.text, '654321');
      expect(tester.widgetList<Text>(cells).map((w) => w.data).toList(),
          ['6', '5', '4', '3', '2', '1']);
      expect(tester.takeException(), isNull);
    });
  }

  setUpAll(_loadFonts);

  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';

    for (final (label, size) in _viewports) {
      testWidgets('recovery request lays out at $label in $theme',
          (tester) async {
        await _openForgotPassword(tester,
            api: _FakeAuthApi(), light: light, size: size);

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
        expect(_expectTapTargets(tester), 1);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byType(ExampleSheetHeader), findsOneWidget);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.text('Reset your password'), findsOneWidget);
        expect(find.byType(ExampleAuthField), findsOneWidget);
        expect(find.byType(ExampleGlassButton), findsOneWidget);
        expect(find.text('Send code'), findsOneWidget);
        expect(tester.getSize(find.byType(ExampleSheetCta)).width,
            lessThanOrEqualTo(560));
      });

      testWidgets('recovery reset lays out at $label in $theme',
          (tester) async {
        await _openForgotPassword(tester,
            api: _FakeAuthApi(), light: light, size: size);
        await _sendCode(tester);

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
        expect(_expectTapTargets(tester), 2);
        expect(find.text('Set a new password'), findsOneWidget);
        expect(find.byType(ExampleAuthField), findsNWidgets(3));
        expect(find.byType(ExampleOtpField), findsOneWidget);
        expect(find.text('Reset password'), findsOneWidget);
        expect(find.text(_email), findsOneWidget);
        expect(
            tester
                .widget<ExampleAuthField>(find.byType(ExampleAuthField).first)
                .readOnly,
            isTrue);
        expect(find.byType(ExampleSheetTextAction), findsOneWidget);
        expect(find.text('Send a new code'), findsOneWidget);
        expect(find.byType(ExampleGlassButton), findsOneWidget);
      });

      testWidgets('verification lays out at $label in $theme', (tester) async {
        await _openVerification(tester,
            api: _FakeAuthApi(), light: light, size: size);

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);
        expect(_expectTapTargets(tester), 2);
        expect(find.byType(AppBar), findsNothing);
        expect(find.byTooltip('Close'), findsOneWidget);
        expect(find.text('Confirm your email'), findsOneWidget);
        expect(find.byType(ExampleAuthField), findsOneWidget);
        expect(find.byType(ExampleGlassButton), findsOneWidget);
        expect(find.byType(ExampleCodeRecipient), findsOneWidget);
        expect(find.text(_email), findsOneWidget);
        expect(find.text('Send a new code'), findsOneWidget);
        expect(tester.getSize(find.byType(ExampleSheetCta)).width,
            lessThanOrEqualTo(560));
      });
    }

    testWidgets('initial verification send keeps the form available in $theme',
        (tester) async {
      await _openVerification(tester,
          api: _HangingAuthApi(), light: light, sendCodeFirst: true);

      expect(tester.takeException(), isNull);
      expect(find.byType(ExampleAuthField), findsOneWidget);
      expect(
          tester.widget<ExampleAuthField>(find.byType(ExampleAuthField)).enabled,
          isTrue);
      expect(find.byType(ExampleSheetCta), findsOneWidget);
      expect(find.byType(ExampleSkeleton), findsNothing);
    });

    testWidgets(
        'failed initial verification send leaves retry available in $theme',
        (tester) async {
      final api = _FakeAuthApi(failResend: true);
      await _openVerification(tester,
          api: api, light: light, sendCodeFirst: true);

      expect(tester.takeException(), isNull);
      expect(find.text(_serverDownCopy), findsOneWidget);
      expect(find.byType(ExampleAuthAlert), findsOneWidget);
      expect(find.byType(ExampleAuthField), findsOneWidget);
      await _tapAction(tester, 'Send a new code');
      expect(
          api.calls
              .where((c) => c.startsWith('resendEmailVerification'))
              .length,
          2);
    });

    testWidgets('recovery holds at text scale 1.3 in $theme', (tester) async {
      await _openForgotPassword(tester,
          api: _FakeAuthApi(), light: light, textScale: 1.3);
      await _sendCode(tester);
      expect(tester.takeException(), isNull);
      _expectAppCopyIsWhole(tester);
      expect(_expectTapTargets(tester), 2);
      expect(find.byType(ExampleAuthField), findsNWidgets(3));
      expect(find.byType(ExampleOtpField), findsOneWidget);
    });

    testWidgets('verification holds at text scale 1.3 in $theme',
        (tester) async {
      await _openVerification(tester,
          api: _FakeAuthApi(), light: light, textScale: 1.3);
      expect(tester.takeException(), isNull);
      _expectAppCopyIsWhole(tester);
      expect(_expectTapTargets(tester), 2);
      expect(tester.getSize(find.byType(ExampleSheetTextAction)).height,
          greaterThanOrEqualTo(44));
    });

    testWidgets('error and resend confirmation remain legible in $theme',
        (tester) async {
      await _openVerification(tester,
          api: _FakeAuthApi(failVerify: true), light: light, textScale: 1.3);
      await _tapAction(tester, 'Send a new code');
      expect(find.byType(ExampleAuthAlert), findsOneWidget);
      _expectAppCopyIsWhole(tester);

      await tester.enterText(find.byType(TextField), '123456');
      await _tapAction(tester, 'Confirm email');
      expect(find.text(_serverDownCopy), findsOneWidget);
      _expectAppCopyIsWhole(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'recovery resend keeps shared busy state and typed input in $theme',
        (tester) async {
      final api = _FakeAuthApi(hangResend: true);
      await _openForgotPassword(tester, api: api, light: light);
      await _sendCode(tester);
      await _fillReset(tester);
      await tester.ensureVisible(find.text('Send a new code'));
      await tester.tap(find.text('Send a new code'));
      await tester.pump();

      expect(
          api.calls.where((c) => c.startsWith('requestPasswordReset')).length,
          2);
      final cta =
          tester.widget<ExampleGlassButton>(find.byType(ExampleGlassButton));
      expect(cta.loading, isTrue);
      expect(cta.onPressed, isNull);
      expect(
          tester
              .widget<ExampleSheetTextAction>(find.byType(ExampleSheetTextAction))
              .onTap,
          isNull);
      for (final field
          in tester.widgetList<ExampleAuthField>(find.byType(ExampleAuthField))) {
        expect(field.enabled, isFalse);
      }
      expect(
          tester
              .widget<EditableText>(find
                  .byWidgetPredicate((w) =>
                      w is EditableText &&
                      (w.autofillHints?.contains(AutofillHints.newPassword) ??
                          false))
                  .first)
              .controller
              .text,
          'Sup3rSecretPass');
      expect(tester.takeException(), isNull);
    });

    testWidgets('verification resend keeps shared busy state in $theme',
        (tester) async {
      await _openVerification(tester,
          api: _FakeAuthApi(hangResend: true), light: light);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.tap(find.text('Send a new code'));
      await tester.pump();

      final cta =
          tester.widget<ExampleGlassButton>(find.byType(ExampleGlassButton));
      expect(cta.loading, isTrue);
      expect(cta.onPressed, isNull);
      expect(
          tester.widget<ExampleAuthField>(find.byType(ExampleAuthField)).enabled,
          isFalse);
      expect(
          tester
              .widget<ExampleSheetTextAction>(find.byType(ExampleSheetTextAction))
              .onTap,
          isNull);
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
          '123456');
      expect(tester.takeException(), isNull);
    });

    testWidgets('resend labels are legible disabled and ready in $theme',
        (tester) async {
      await _openVerification(tester, api: _FakeAuthApi(), light: light);
      final context = tester.element(find.byType(ExampleSheetTextAction));
      final ground = ExampleSurface.navigationOf(context);
      expect(ground.a, 1);
      final style = tester
          .widget<TextButton>(find.descendant(
            of: find.byType(ExampleSheetTextAction),
            matching: find.byType(TextButton),
          ))
          .style!;
      for (final states in <Set<WidgetState>>[
        {},
        {WidgetState.disabled}
      ]) {
        expect(_contrast(style.foregroundColor!.resolve(states)!, ground),
            greaterThanOrEqualTo(4.5));
      }
    });
  }

  testWidgets('invalid recovery email does not reach the API', (tester) async {
    final api = _FakeAuthApi();
    await _openForgotPassword(tester, api: api, light: false);
    await tester.enterText(find.byType(TextField), 'invalid');
    await _sendCode(tester);
    expect(find.text('Enter the email you signed up with.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('recovery server failure stays in the form', (tester) async {
    await _openForgotPassword(tester,
        api: _FakeAuthApi(failRequestReset: true), light: false);
    await _sendCode(tester);
    expect(find.byType(ExampleAuthAlert), findsOneWidget);
    expect(find.text(_serverDownCopy), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Send code'), findsOneWidget);
  });

  for (final (name, code, password, confirmation, message) in [
    (
      'short code',
      '123',
      'Sup3rSecretPass',
      'Sup3rSecretPass',
      'Enter the six-digit code from the email.'
    ),
    (
      'weak password',
      '123456',
      'short',
      'short',
      'Use at least 12 characters with uppercase, lowercase, and a number.'
    ),
    (
      'mismatched confirmation',
      '123456',
      'Sup3rSecretPass',
      'Sup3rSecretPas',
      'The passwords do not match.'
    ),
  ]) {
    testWidgets('recovery keeps baseline validation for $name', (tester) async {
      final api = _FakeAuthApi();
      await _openForgotPassword(tester, api: api, light: true);
      await _sendCode(tester);
      await _fillReset(tester,
          code: code, password: password, confirmation: confirmation);
      await _tapAction(tester, 'Reset password');
      expect(find.text(message), findsOneWidget);
      expect(api.calls.where((c) => c.startsWith('resetPassword')), isEmpty);
    });
  }

  testWidgets('valid reset reaches the API and closes with confirmation',
      (tester) async {
    final api = _FakeAuthApi();
    await _openForgotPassword(tester, api: api, light: false);
    await _sendCode(tester);
    await _fillReset(tester);
    await _tapAction(tester, 'Reset password');
    expect(api.calls, contains('resetPassword:$_email:123456'));
    expect(find.byType(ExampleSheetCta), findsNothing);
    expect(find.text('Password updated. Sign in with your new password.'),
        findsOneWidget);
  });

  testWidgets('failed reset keeps entered password', (tester) async {
    await _openForgotPassword(tester,
        api: _FakeAuthApi(failReset: true), light: true);
    await _sendCode(tester);
    await _fillReset(tester);
    await _tapAction(tester, 'Reset password');
    expect(find.text(_serverDownCopy), findsOneWidget);
    expect(find.byType(ExampleAuthField), findsNWidgets(3));
    expect(find.byType(ExampleOtpField), findsOneWidget);
    expect(
        tester
            .widget<EditableText>(find
                .byWidgetPredicate((w) =>
                    w is EditableText &&
                    (w.autofillHints?.contains(AutofillHints.newPassword) ??
                        false))
                .first)
            .controller
            .text,
        'Sup3rSecretPass');
  });

  testWidgets('verification validates six digits before making a request',
      (tester) async {
    final api = _FakeAuthApi();
    await _openVerification(tester, api: api, light: false);
    await tester.enterText(find.byType(TextField), '123');
    await _tapAction(tester, 'Confirm email');
    expect(
        find.text('Enter the six-digit code from the email.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('rejected verification code leaves the sheet open',
      (tester) async {
    await _openVerification(tester,
        api: _FakeAuthApi(failVerify: true), light: false);
    await tester.enterText(find.byType(TextField), '123456');
    await _tapAction(tester, 'Confirm email');
    expect(find.byType(ExampleAuthAlert), findsOneWidget);
    expect(find.text(_serverDownCopy), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.byType(ExampleSheetCta), findsOneWidget);
  });

  testWidgets('valid verification closes the sheet', (tester) async {
    final api = _FakeAuthApi();
    await _openVerification(tester, api: api, light: false);
    await tester.enterText(find.byType(TextField), '123456');
    await _tapAction(tester, 'Confirm email');
    expect(api.calls, contains('verifyEmail:$_email:123456'));
    expect(find.byType(ExampleSheetCta), findsNothing);
  });

  testWidgets('verification resend confirms and remains available immediately',
      (tester) async {
    final api = _FakeAuthApi();
    await _openVerification(tester, api: api, light: false);
    await _tapAction(tester, 'Send a new code');
    expect(
        find.text(
            'A new code is on its way. Check your spam folder if it does not arrive within a minute.'),
        findsOneWidget);
    expect(
        tester
            .widget<ExampleSheetTextAction>(find.byType(ExampleSheetTextAction))
            .onTap,
        isNotNull);
    await _tapAction(tester, 'Send a new code');
    expect(
        api.calls.where((c) => c.startsWith('resendEmailVerification')).length,
        2);
  });

  testWidgets('recovery resend remains immediate and keeps the form input',
      (tester) async {
    final api = _FakeAuthApi();
    await _openForgotPassword(tester, api: api, light: false);
    await _sendCode(tester);
    await _fillReset(tester);
    await _tapAction(tester, 'Send a new code');
    expect(
        api.calls.where((c) => c.startsWith('requestPasswordReset')).length, 2);
    expect(
        tester
            .widget<ExampleSheetTextAction>(find.byType(ExampleSheetTextAction))
            .onTap,
        isNotNull);
    expect(
        tester
            .widget<EditableText>(find
                .byWidgetPredicate((w) =>
                    w is EditableText &&
                    (w.autofillHints?.contains(AutofillHints.newPassword) ??
                        false))
                .first)
            .controller
            .text,
        'Sup3rSecretPass');
    await _tapAction(tester, 'Send a new code');
    expect(
        api.calls.where((c) => c.startsWith('requestPasswordReset')).length, 3);
  });

  testWidgets('reduced motion changes recovery step without crossfade',
      (tester) async {
    await _openForgotPassword(tester,
        api: _FakeAuthApi(), light: false, reducedMotion: true);
    await tester.tap(find.text('Send code'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Reset password'), findsOneWidget);
    expect(find.text('Send code'), findsNothing);
  });

  testWidgets('motion keeps recovery step transition', (tester) async {
    await _openForgotPassword(tester, api: _FakeAuthApi(), light: false);
    await tester.tap(find.text('Send code'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('Reset password'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets('initial verification completion keeps entered code',
      (tester) async {
    final api = _GatedAuthApi();
    await _openVerification(tester,
        api: api, light: false, sendCodeFirst: true, reducedMotion: true);
    await tester.enterText(find.byType(TextField), '123456');
    api.release();
    await tester.pumpAndSettle();
    expect(find.byType(ExampleAuthField), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '123456');
    expect(find.byType(ExampleSheetCta), findsOneWidget);
  });

  group('white-label', () {
    testWidgets('recovery retains its Material sheet', (tester) async {
      await _openForgotPassword(tester,
          api: _FakeAuthApi(), light: false, example: false);
      expect(tester.takeException(), isNull);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      expect(find.byType(ExampleSheetCta), findsNothing);
      expect(find.byType(ExampleAuthField), findsNothing);
      expect(find.byType(ExampleGlassButton), findsNothing);
    });

    testWidgets('verification retains its Material sheet and resend',
        (tester) async {
      final api = _FakeAuthApi();
      await _openVerification(tester,
          api: api, light: false, example: false, sendCodeFirst: true);
      expect(tester.takeException(), isNull);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Send a new code'), findsOneWidget);
      expect(find.byType(ExampleSheetCta), findsNothing);
      await _tapAction(tester, 'Send a new code');
      expect(
          api.calls
              .where((c) => c.startsWith('resendEmailVerification'))
              .length,
          2);
    });
  });
}
