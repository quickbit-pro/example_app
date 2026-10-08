import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/auth/presentation/example_auth_field.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('$brightness restores a dismissed Android web keyboard',
        (tester) async {
      final controller = TextEditingController(text: 'Example1234');
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
            body: ExampleAuthField(
          controller: controller,
          label: 'Password',
          obscureText: true,
          prefixIcon: Icons.lock_outline,
          autofillHints: const [AutofillHints.password],
        )),
      ));
      final field = find.byType(TextField);
      await tester.tap(field);
      await tester.pump();
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.focusNode.hasFocus, isTrue);

      // Android's Back/hide-keyboard action can leave Flutter focused.
      tester.testTextInput.hide();
      tester.testTextInput.log.clear();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(editable.focusNode.hasFocus, isTrue);
      expect(controller.text, 'Example1234');
      // A show-only request is ignored by the web engine if it still thinks
      // it is editing. Recovery must reattach the client, preserving the value.
      expect(tester.testTextInput.log.map((call) => call.method),
          contains('TextInput.setClient'));

      // Consecutive taps must also recover, even inside double-tap timing.
      tester.testTextInput.hide();
      tester.testTextInput.log.clear();
      await tester.tap(field);
      await tester.pump();
      expect(tester.testTextInput.isVisible, isTrue);
      expect(tester.testTextInput.log.map((call) => call.method),
          contains('TextInput.setClient'));
      expect(controller.text, 'Example1234');
      await tester.pumpWidget(const SizedBox.shrink());
    },
        skip: !kIsWeb,
        variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
  testWidgets('visible keyboard keeps the connection and password value',
      (tester) async {
    final controller = TextEditingController(text: 'Example1234');
    addTearDown(controller.dispose);
    addTearDown(tester.view.resetViewInsets);
    var obscure = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: StatefulBuilder(
          builder: (context, setState) => ExampleAuthField(
                controller: controller,
                label: 'Password',
                obscureText: obscure,
                prefixIcon: Icons.lock_outline,
                suffix: ExamplePasswordToggle(
                  obscured: obscure,
                  onTap: () => setState(() => obscure = !obscure),
                ),
              )),
    )));
    final field = find.byType(TextField);
    await tester.tap(field);
    await tester.pump();
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    tester.testTextInput.log.clear();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.byIcon(Icons.lock_outline));
    await tester.pump();
    expect(tester.testTextInput.log.map((call) => call.method),
        isNot(contains('TextInput.setClient')));
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);
    await tester.tap(find.byType(ExamplePasswordToggle));
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).obscureText,
        isFalse);
    expect(controller.text, 'Example1234');
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  for (final readOnly in [false, true]) {
    testWidgets(
        'non-editable field does not reconnect input (readOnly=$readOnly)',
        (tester) async {
      final controller = TextEditingController(text: 'Example1234');
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ExampleAuthField(
        controller: controller,
        enabled: readOnly,
        readOnly: readOnly,
        obscureText: true,
      ))));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      if (!readOnly) expect(tester.testTextInput.isVisible, isFalse);
      // Web keeps a readonly DOM input for selection. It must not be
      // reconnected by the editable-field keyboard recovery.
      tester.testTextInput.log.clear();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.log.map((call) => call.method),
          isNot(contains('TextInput.setClient')));
      expect(controller.text, 'Example1234');
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  }
}
