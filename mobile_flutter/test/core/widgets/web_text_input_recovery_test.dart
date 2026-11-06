import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/web/web_text_input_probe.dart';
import 'package:mobile_flutter/core/widgets/web_text_input_recovery.dart';

class Probe implements WebTextInputProbe {
  @override
  bool supported = true;
  @override
  bool documentFocused = true;
  @override
  bool editingElementFocused = true;
  VoidCallback? onResume;
  bool stopped = false;
  @override
  VoidCallback listen(VoidCallback callback) {
    onResume = callback;
    return () {
      stopped = true;
      onResume = null;
    };
  }
}

void main() {
  void desktopTest(String name, WidgetTesterCallback body) =>
      testWidgets(name, body,
          variant: TargetPlatformVariant.only(TargetPlatform.windows));
  late Probe probe;
  late TextEditingController controller;
  late FocusNode focus;
  setUp(() {
    probe = Probe();
    controller = TextEditingController(text: 'Keep this draft');
    focus = FocusNode();
  });
  tearDown(() {
    controller.dispose();
    focus.dispose();
  });
  Future<void> mount(WidgetTester tester, {bool readOnly = false}) async {
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) =>
            WebTextInputRecovery(probe: probe, child: child!),
        home: Scaffold(
            body: Column(children: [
          TextField(
              controller: controller, focusNode: focus, readOnly: readOnly),
          TextButton(onPressed: () {}, child: const Text('Other action')),
        ]))));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    tester.testTextInput.log.clear();
  }

  bool reconnected(WidgetTester tester) => tester.testTextInput.log
      .any((call) => call.method == 'TextInput.setClient');

  desktopTest('normal desktop input and selection do not reconnect',
      (tester) async {
    await mount(tester);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
    expect(controller.text, 'Keep this draft');
  });
  desktopTest('click reconnects a stale browser input and preserves selection',
      (tester) async {
    await mount(tester);
    controller.selection = const TextSelection(baseOffset: 2, extentOffset: 7);
    probe.editingElementFocused = false;
    // A tap can legitimately move the caret. Record that selection after the
    // normal TextField handler, before the deferred reconnection runs.
    await tester.tap(find.byType(TextField));
    final selection = controller.selection;
    await tester.pumpAndSettle();
    expect(reconnected(tester), true);
    expect(focus.hasFocus, true);
    expect(controller.text, 'Keep this draft');
    expect(controller.selection, selection);
    await tester.enterText(find.byType(TextField), 'Typing works');
    expect(controller.text, 'Typing works');
  });
  desktopTest('background browser is left alone and resume repairs stale input',
      (tester) async {
    await mount(tester);
    probe.editingElementFocused = false;
    probe.documentFocused = false;
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
    probe.documentFocused = true;
    probe.onResume!();
    await tester.pumpAndSettle();
    expect(reconnected(tester), true);
    expect(controller.text, 'Keep this draft');
  });
  desktopTest(
      'silent browser disconnect repairs without clicking or refreshing',
      (tester) async {
    await mount(tester);
    controller.selection = const TextSelection.collapsed(offset: 4);
    probe.editingElementFocused = false;
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(reconnected(tester), true);
    expect(controller.text, 'Keep this draft');
    expect(controller.selection, const TextSelection.collapsed(offset: 4));
  });

  desktopTest('current composition is never interrupted', (tester) async {
    await mount(tester);
    controller.value = const TextEditingValue(
        text: 'Draft composing',
        selection: TextSelection.collapsed(offset: 15),
        composing: TextRange(start: 6, end: 15));
    probe.editingElementFocused = false;
    probe.onResume!();
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
    expect(controller.value.composing, const TextRange(start: 6, end: 15));
  });
  desktopTest('read-only input is not reconnected', (tester) async {
    await mount(tester, readOnly: true);
    probe.editingElementFocused = false;
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
  });
  desktopTest('clicking another control does not steal focus back',
      (tester) async {
    await mount(tester);
    probe.editingElementFocused = false;
    await tester.tap(find.text('Other action'));
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
    expect(focus.hasFocus, false);
  });
  desktopTest('a new control selected during repair keeps its focus',
      (tester) async {
    await mount(tester);
    probe.editingElementFocused = false;
    probe.onResume!();
    await tester.pump(); // Begin the blur, but do not reopen the field yet.
    tester.testTextInput.log.clear();
    await tester.tap(find.text('Other action'));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, false);
    expect(reconnected(tester), false);
    expect(controller.text, 'Keep this draft');
  });

  desktopTest('an open dialog keeps its own focus', (tester) async {
    await mount(tester);
    final context = tester.element(find.byType(TextField));
    showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('Dialog')));
    await tester.pumpAndSettle();
    probe.editingElementFocused = false;
    probe.onResume!();
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
  });
  desktopTest('disposing cancels browser listeners and pending checks',
      (tester) async {
    await mount(tester);
    probe.editingElementFocused = false;
    probe.onResume!();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(probe.stopped, true);
    expect(tester.takeException(), isNull);
  });
  desktopTest('other platforms use the existing input behavior',
      (tester) async {
    probe.supported = false;
    await mount(tester);
    probe.editingElementFocused = false;
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(reconnected(tester), false);
    expect(probe.onResume, isNull);
  });
}
