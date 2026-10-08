// The sign-up phone field, driven the way a keyboard drives it.
//
// The field formats the number as it is typed. An earlier package did that
// asynchronously, rewriting the field a tick after the keyboard event, which
// on mobile browsers lost digits at the first inserted space; the current one
// formats inside the event. The typing tests below use a stand-in for the
// platform text input that keeps its own copy of the text and caret, applies
// every editing state the framework pushes back, and inserts each key at its
// own caret — which is what a real keyboard does, and what makes a caret
// reset or a late rewrite visible as digits landing in the wrong place.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/l10n/app_localization_delegates.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_auth_field.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/signup/presentation/signup_screen.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:phone_form_field/phone_form_field.dart';

const _germanMobile = '15123456789';

const _tenant = MobileTenantConfig(
  companyName: 'Hoppa',
  brandName: 'Hoppa',
  referralsEnabled: false,
  referralRegistrationMode: 'optional',
  vouchersEnabled: true,
  existingAccountClaimEnabled: true,
  boomFiExchangeEnabled: true,
  walletOutflowsEnabled: true,
  equalsMoneyEnabled: true,
);

/// The package's flag-and-dial-code button inside the field, and Germany's
/// row in the country sheet.
const _selectorKey = ValueKey('country-code-chip');
const _germanyKey = ValueKey('DE');

/// The sheet's search box carries the country-name autofill hint; nothing
/// else on the screen does.
final _searchBox = find.byWidgetPredicate((widget) =>
    widget is TextField &&
    (widget.autofillHints?.contains(AutofillHints.countryName) ?? false));

/// Records the sign-up payload; the network is never touched.
class _FakeApi extends MobilePlatformApi {
  _FakeApi({this.emailQueued = true}) : super(Dio());

  final bool emailQueued;

  final submittedPhones = <String?>[];

  @override
  Future<ActionResult> signUp({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required String accountType,
    String? phone,
    String? referralCode,
    String? referralSource,
    String? invitationToken,
    Map<String, dynamic>? legalAgreements,
    bool? referralAccepted,
    int? referralTermsVersion,
    String? registrationAttemptId,
    String? referralQuoteId,
    String? referralTermsHash,
    String? referralPolicyHash,
    bool referralNeedsReview = false,
    String? installationToken,
  }) async {
    submittedPhones.add(phone);
    return ActionResult(
        message: 'Account created',
        metadata: {'verificationEmailSent': emailQueued});
  }
}

AppBranding _branding({required bool example}) => AppBranding(
      appName: example ? 'EXAMPLE' : 'Hoppa',
      brandId: example ? 'example' : 'hoppa',
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: 'dark',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.test',
      supportPhone: '',
      legalEntity: example ? 'EXAMPLE' : 'Hoppa',
    );

/// Built once per brand: a fresh `ThemeData` on every pump makes
/// `MaterialApp` animate between identical themes.
final _themes = {
  for (final example in [true, false])
    example: buildAppThemes(_branding(example: example)),
};

Future<void> _pump(
  WidgetTester tester, {
  required _FakeApi api,
  required bool example,
}) async {
  final themes = _themes[example]!;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://127.0.0.1:1',
          branding: _branding(example: example),
        )),
        mobilePlatformApiProvider.overrideWithValue(api),
        mobileTenantConfigProvider.overrideWith((ref) async => _tenant),
      ],
      child: MaterialApp(
        // The app's own delegate list, so the field's copy is looked up the
        // way it is in production.
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLanguages.map((language) => language.locale),
        theme: themes.light,
        darkTheme: themes.dark,
        themeMode: ThemeMode.dark,
        home: const SignupScreen(initialStep: 1),
      ),
    ),
  );
  await _settle(tester);
}

/// A fixed advance rather than `pumpAndSettle`: the Example layout keeps a
/// sheen ticker that never comes to rest.
Future<void> _settle(WidgetTester tester, [int frames = 8]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder get _phoneInput => find.descendant(
      of: find.byType(PhoneFormField),
      matching: find.byType(EditableText),
    );

TextEditingController _phoneController(WidgetTester tester) =>
    tester.widget<EditableText>(_phoneInput).controller;

/// The dial code shown on the country button.
Finder _dialCode(String code) => find.descendant(
      of: find.byKey(_selectorKey),
      matching: find.textContaining(code),
    );

/// A labelled text field of the current layout: the white-label form uses
/// `TextFormField`s, the Example form its own [ExampleAuthField].
Finder _field(String label, {required bool example}) =>
    find.widgetWithText(example ? ExampleAuthField : TextFormField, label);

/// Fills in the contact step's name and email fields.
Future<void> _enterContactDetails(WidgetTester tester,
    {required bool example}) async {
  await tester.enterText(_field('Legal first name', example: example), 'Ada');
  await tester.enterText(_field('Legal last name', example: example), 'Lovelace');
  await tester.enterText(
      find.byKey(const Key('signup_email')), 'ada@example.test');
}

/// The field's own translated "invalid" message, resolved from its context.
String _invalidMessage(WidgetTester tester) =>
    PhoneFieldLocalization.of(tester.element(find.byType(PhoneFormField)))
        .invalidPhoneNumber;

/// Picks Germany in the country sheet by searching for it and tapping its
/// row. The search stays short: the sheet treats a longer text arriving in
/// one go as browser autofill and picks the first match by itself.
Future<void> _selectGermany(WidgetTester tester) async {
  await tester.tap(find.byKey(_selectorKey));
  await _settle(tester);
  await tester.enterText(_searchBox, 'Ger');
  await _settle(tester, 2);
  expect(_searchBox, findsOneWidget, reason: 'the sheet closed on its own');
  await tester.tap(find.byKey(_germanyKey));
  await _settle(tester);
  expect(_searchBox, findsNothing, reason: 'the sheet stays open');
  expect(_dialCode('49'), findsOneWidget);
}

/// The platform side of the text input connection.
///
/// Holds the text and caret the keyboard believes the field has, updated from
/// every `TextInput.setEditingState` the framework sends, and types each key
/// at that caret. A negative offset (what `TextEditingController.text =`
/// sends) cannot be honoured by any platform; browsers clamp it to the start.
class _Keyboard {
  _Keyboard(this.tester);

  final WidgetTester tester;
  String text = '';
  int caret = 0;
  int _seen = 0;

  void sync() {
    final log = tester.testTextInput.log;
    for (; _seen < log.length; _seen++) {
      final call = log[_seen];
      if (call.method != 'TextInput.setEditingState') continue;
      final args = call.arguments as Map;
      text = args['text'] as String;
      final base = args['selectionBase'] as int;
      caret = base.clamp(0, text.length);
    }
  }

  Future<void> type(String key) async {
    sync();
    text = text.replaceRange(caret, caret, key);
    caret += key.length;
    tester.testTextInput.updateEditingValue(TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: caret),
    ));
    // The formatted value goes back to the platform in the same event; the
    // extra frames would only expose a late rewrite.
    await tester.pump();
    await _settle(tester, 3);
    sync();
  }
}

/// Types the German mobile number one digit at a time and checks after each
/// key that nothing was lost or reordered and that the caret sits at the end,
/// both in the field and on the keyboard's side; and that the finished
/// number is shown grouped rather than as a bare run of digits.
Future<void> _typeGermanMobile(WidgetTester tester) async {
  await tester.showKeyboard(_phoneInput);
  await tester.pump();
  final keyboard = _Keyboard(tester);
  final nonDigit = RegExp(r'\D');
  for (var i = 1; i <= _germanMobile.length; i++) {
    final typed = _germanMobile.substring(0, i);
    await keyboard.type(_germanMobile[i - 1]);
    final controller = _phoneController(tester);
    final value = controller.value;
    expect(value.text.replaceAll(nonDigit, ''), typed,
        reason: 'after typing $typed the field holds "${value.text}"');
    expect(value.selection, TextSelection.collapsed(offset: value.text.length),
        reason: 'after typing $typed the caret is at ${value.selection}');
    expect(keyboard.text, value.text,
        reason: 'after typing $typed the keyboard sees "${keyboard.text}"');
    expect(keyboard.caret, keyboard.text.length,
        reason:
            'after typing $typed the keyboard caret is at ${keyboard.caret}');
    expect(tester.takeException(), isNull);
  }
  final shown = _phoneController(tester).text;
  expect(shown, isNot(_germanMobile),
      reason: 'the full number is shown grouped, not as "$shown"');
  expect(shown, matches(nonDigit),
      reason: 'the full number "$shown" has no group separator');
}

void main() {
  for (final example in [false, true]) {
    final layout = example ? 'Example' : 'white-label';

    testWidgets(
        '$layout: a German mobile number is taken digit by digit and grouped',
        (tester) async {
      await _pump(tester, api: _FakeApi(), example: example);
      await _selectGermany(tester);
      await _typeGermanMobile(tester);
    });

    testWidgets('$layout: searching the country sheet before it has settled',
        (tester) async {
      await _pump(tester, api: _FakeApi(), example: example);
      await tester.tap(find.byKey(_selectorKey));
      // The first frames in: the sheet is still sliding up. Its content
      // appears once the sheet's own localisation scope has loaded, one
      // frame after the route.
      var frames = 0;
      do {
        await tester.pump();
        frames++;
      } while (_searchBox.evaluate().isEmpty && frames < 3);
      expect(_searchBox, findsOneWidget,
          reason: 'the search box is not there after $frames frames');
      await tester.enterText(_searchBox, '49');
      await tester.pump();
      expect(tester.takeException(), isNull);
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(_germanyKey), findsOneWidget);
      await tester.tap(find.byKey(_germanyKey));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(_dialCode('49'), findsOneWidget);
    });

    testWidgets('$layout: an invalid number blocks continue with its message',
        (tester) async {
      await _pump(tester, api: _FakeApi(), example: example);
      await _enterContactDetails(tester, example: example);
      await _selectGermany(tester);
      await tester.enterText(_phoneInput, '123');
      await _settle(tester);

      final invalid = _invalidMessage(tester);
      expect(find.text(invalid), findsOneWidget);
      await tester.tap(find.text('Continue').hitTestable());
      await _settle(tester);
      expect(find.text('Complete your contact details before continuing.'),
          findsOneWidget);
      expect(find.text(invalid), findsOneWidget);
      expect(_field('Password', example: example).hitTestable(), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final emailQueued in [true, false]) {
    testWidgets(
        'signup submits E.164 and shows email queue status=$emailQueued',
        (tester) async {
      final api = _FakeApi(emailQueued: emailQueued);
      await _pump(tester, api: api, example: false);
      await _enterContactDetails(tester, example: false);
      await _selectGermany(tester);
      await _typeGermanMobile(tester);

      // The stepper keeps every step's controls in the tree; only the current
      // step's can be hit.
      Future<void> next() async {
        await tester.tap(find.text('Continue').hitTestable());
        await _settle(tester);
      }

      await next();
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Password'), 'Correct-Horse-42');
      await next();
      for (final box in tester.widgetList<Checkbox>(find.byType(Checkbox))) {
        box.onChanged!(true);
      }
      await _settle(tester, 2);
      // The review step runs below the fold; the last button is its own.
      final create = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(create.last);
      await _settle(tester, 2);
      await tester.tap(create.hitTestable());
      await _settle(tester);

      expect(api.submittedPhones, ['+4915123456789']);
      expect(find.text('Resend confirmation email'), findsOneWidget);
      expect(find.textContaining('We emailed'), findsNothing);
      expect(find.textContaining('we could not request a confirmation email'),
          emailQueued ? findsNothing : findsOneWidget);
      expect(find.textContaining('Delivery can take a few minutes.'),
          emailQueued ? findsOneWidget : findsNothing);
    });
  }

  group('the field speaks the app language', () {
    Future<String> invalidMessageIn(WidgetTester tester, Locale locale) async {
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: appLanguages.map((language) => language.locale),
        home: Builder(
          builder: (context) =>
              Text(PhoneFieldLocalization.of(context).invalidPhoneNumber),
        ),
      ));
      // The app's own copy for the locale is read from the asset bundle,
      // which only completes in real time; nothing renders until it has.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      return tester.widget<Text>(find.byType(Text)).data!;
    }

    testWidgets('translated where the field has the language', (tester) async {
      expect(await invalidMessageIn(tester, const Locale('de')),
          'Ungültige Telefonnummer');
    });

    testWidgets('English, without a report, where it does not', (tester) async {
      // Japanese is an app language the field's package lacks; a delegate
      // that refused it would make the framework report an error on every
      // build.
      expect(await invalidMessageIn(tester, const Locale('ja')),
          'Invalid phone number');
    });
  });
}
