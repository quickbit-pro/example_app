import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/presentation/example_otp_field.dart';
import 'package:mobile_flutter/flavors.dart';

const _exampleBranding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

/// A tenant with no `ExampleBrand` extension: the cells have to draw from the
/// Material theme alone.
const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

Widget _host({
  required Widget child,
  AppBranding branding = _exampleBranding,
  Brightness brightness = Brightness.dark,
}) {
  final themes = buildAppThemes(branding);
  return MaterialApp(
    theme: brightness == Brightness.dark ? themes.dark : themes.light,
    themeMode: ThemeMode.light,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(20), child: child),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Widget app, {
  double width = 375,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Finder _input() => find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(EditableText),
    );

List<String?> _cells(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(Text),
    ))
    .map((w) => w.data)
    .toList();

/// Delivers [code] the way the platform's one-time-code autofill does: as an
/// editing-state update tagged with the field's autofill id.
Future<void> _autofill(WidgetTester tester, String code) async {
  final editable = tester.state<EditableTextState>(_input());
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/textinput',
    const JSONMethodCodec().encodeMethodCall(MethodCall(
      'TextInputClient.updateEditingStateWithTag',
      [
        0,
        {editable.autofillId: TextEditingValue(text: code).toJSON()},
      ],
    )),
    (_) {},
  );
  await tester.pump();
}

void main() {
  testWidgets('returning from email reconnects input without losing digits', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpAt(tester, _host(child: ExampleOtpField(controller: controller)));
    await tester.enterText(_input(), '123');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.testTextInput.hide();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    tester.testTextInput.log.clear();
    await tester.tap(find.byType(TextFormField));
    await tester.pump();
    expect(controller.text, '123');
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.testTextInput.log.map((call) => call.method), contains('TextInput.setClient'));
    await tester.enterText(_input(), '123456');
    expect(controller.text, '123456');
    await _autofill(tester, '987654');
    expect(controller.text, '987654');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const variants = <(String, AppBranding, Brightness)>[
    ('Example twilight', _exampleBranding, Brightness.dark),
    ('Example daylight', _exampleBranding, Brightness.light),
    ('white-label', _tenantBranding, Brightness.dark),
  ];

  for (final (name, branding, brightness) in variants) {
    testWidgets('eight cells take paste, deletion and autofill ($name)',
        (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final semantics = tester.ensureSemantics();
      await _pumpAt(
        tester,
        _host(
          branding: branding,
          brightness: brightness,
          child: ExampleOtpField(controller: controller, length: 8),
        ),
      );

      // A pasted code with letters between the digits keeps only the digits,
      // and a ninth digit has nowhere to go.
      await tester.enterText(_input(), 'a1b2c3d4e5f6g7h89');
      await tester.pump();
      expect(controller.text, '12345678');
      expect(_cells(tester), ['1', '2', '3', '4', '5', '6', '7', '8']);

      await tester.enterText(_input(), '1234567');
      await tester.pump();
      expect(_cells(tester), ['1', '2', '3', '4', '5', '6', '7', '']);

      final editable = tester.state<EditableTextState>(_input());
      expect(
          editable.widget.autofillHints, contains(AutofillHints.oneTimeCode));
      await _autofill(tester, '87654321');
      expect(controller.text, '87654321');
      expect(_cells(tester), ['8', '7', '6', '5', '4', '3', '2', '1']);

      // The hidden input announces itself with a length-aware name.
      expect(find.bySemanticsLabel('8-digit code'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('the validator asks for all eight digits', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final formKey = GlobalKey<FormState>();
    await _pumpAt(
      tester,
      _host(
        child: Form(
          key: formKey,
          child: ExampleOtpField(controller: controller, length: 8),
        ),
      ),
    );

    await tester.enterText(_input(), '1234567');
    await tester.pump();
    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter all 8 digits'), findsOneWidget);

    await tester.enterText(_input(), '12345678');
    await tester.pump();
    expect(formKey.currentState!.validate(), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('eight cells stay readable on a 360 phone', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpAt(
      tester,
      _host(child: ExampleOtpField(controller: controller, length: 8)),
      width: 360,
    );

    final cells = find.descendant(
      of: find.byType(ExampleOtpField),
      matching: find.byType(Container),
    );
    expect(cells, findsNWidgets(8));
    for (final cell in cells.evaluate()) {
      final size = tester.getSize(find.byWidget(cell.widget));
      expect(size.width, greaterThanOrEqualTo(30));
      expect(size.height, 56);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('six cells remain the default with their own name',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final semantics = tester.ensureSemantics();
    await _pumpAt(
      tester,
      _host(child: ExampleOtpField(controller: controller)),
    );

    await tester.enterText(_input(), '1234567');
    await tester.pump();
    expect(controller.text, '123456');
    expect(_cells(tester), ['1', '2', '3', '4', '5', '6']);
    expect(find.bySemanticsLabel('Six-digit code'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
