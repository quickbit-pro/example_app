import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

const _neutral = Color(0xfff2eafb);

Future<void> _pump(WidgetTester tester, Widget child) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [ExampleBrand()],
        ),
        home: Scaffold(
          body: Center(child: SizedBox(width: 343, child: child)),
        ),
      ),
    );

List<Text> _amountTexts(WidgetTester tester) => tester
    .widgetList<Text>(find.descendant(
      of: find.byType(ExampleAmount),
      matching: find.byType(Text),
    ))
    .toList();

String _plainText(Text text) => text.data ?? text.textSpan!.toPlainText();

void main() {
  setUp(() => Money.maskAmounts = false);
  tearDown(() => Money.maskAmounts = false);

  testWidgets('privacy immediately removes all outgoing amount digits',
      (tester) async {
    var amount = 125.50;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(builder: (context, setState) {
        update = setState;
        return ExampleAmount(
          amount: amount,
          currency: 'USD',
          tone: ExampleAmountTone.signed,
          code: ExampleAmountCode.always,
          color: _neutral,
          semanticsLabel: 'Balance 125.50 USD',
        );
      }),
    );
    expect(_amountTexts(tester).map(_plainText), [r'+$125.50 USD']);

    update(() => amount = 256.75);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(_amountTexts(tester).map(_plainText), contains(r'+$125.50 USD'));

    update(() => Money.maskAmounts = true);
    await tester.pump();

    // No settle: privacy must take effect in this frame, even mid-crossfade.
    final texts = _amountTexts(tester);
    expect(texts.map(_plainText), ['••••']);
    expect((texts.single.textSpan as TextSpan).style!.color, _neutral);
    expect(
        tester.getSemantics(find.byType(ExampleAmount)).label, 'Amount hidden');
    expect(find.byType(AnimatedSwitcher), findsNothing);
    expect(find.bySemanticsLabel('Balance 125.50 USD'), findsNothing);
  });

  testWidgets('privacy hides positive and negative signs and their colors',
      (tester) async {
    Money.maskAmounts = true;
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExampleAmount(
            amount: 42,
            currency: 'USD',
            tone: ExampleAmountTone.signed,
            code: ExampleAmountCode.always,
            color: _neutral,
          ),
          ExampleAmount(
            amount: -42,
            currency: 'USD',
            tone: ExampleAmountTone.delta,
            color: _neutral,
          ),
        ],
      ),
    );
    for (final text in _amountTexts(tester)) {
      expect(_plainText(text), '••••');
      expect((text.textSpan as TextSpan).style!.color, _neutral);
    }
  });

  testWidgets('zero has no positive sign or gain tint', (tester) async {
    await _pump(
      tester,
      const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ExampleAmount(
            amount: 0,
            currency: 'USD',
            tone: ExampleAmountTone.signed,
            color: _neutral,
            animate: false,
          ),
          ExampleAmount(
            amount: 0,
            currency: 'USD',
            tone: ExampleAmountTone.delta,
            color: _neutral,
            animate: false,
          ),
        ],
      ),
    );
    final texts = _amountTexts(tester);
    expect(texts, hasLength(2));
    for (final text in texts) {
      expect(_plainText(text), r'$0.00');
      expect((text.textSpan as TextSpan).style!.color, _neutral);
    }
  });

  testWidgets('labeled pressable exposes working semantic tap and long press',
      (tester) async {
    var taps = 0;
    var longPresses = 0;
    await _pump(
      tester,
      ExamplePressable(
        semanticsLabel: 'Open account',
        onTap: () => taps++,
        onLongPress: () => longPresses++,
        child: const SizedBox(height: 56, child: Text('Account details')),
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Open account'));
    tester.semantics.longPress(find.semantics.byLabel('Open account'));
    expect(taps, 1);
    expect(longPresses, 1);

    await _pump(
      tester,
      ExamplePressable(
        enabled: false,
        semanticsLabel: 'Open account',
        onTap: () => taps++,
        onLongPress: () => longPresses++,
        child: const SizedBox(height: 56, child: Text('Account details')),
      ),
    );
    final disabled = tester.getSemantics(find.byType(ExamplePressable));
    expect(disabled.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(disabled.getSemanticsData().hasAction(SemanticsAction.longPress),
        isFalse);
  });

  testWidgets('glass button is accessible and loading removes its tap action',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ExampleGlassButton(
        label: 'Confirm payment',
        onPressed: () => taps++,
        sheen: false,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Confirm payment'));
    expect(taps, 1);

    await _pump(
      tester,
      ExampleGlassButton(
        label: 'Confirm payment',
        onPressed: () => taps++,
        loading: true,
        sheen: false,
      ),
    );
    final loading = tester.getSemantics(find.byType(ExampleGlassButton));
    expect(loading.label, 'Confirm payment, in progress');
    expect(loading.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);
    expect(taps, 1);
  });

  testWidgets('card remains accessible when its internal hover is disabled',
      (tester) async {
    var taps = 0;
    await _pump(
      tester,
      ExampleLivingCard(
        onTap: () => taps++,
        semanticsLabel: 'Open card',
        enableHoverTilt: false,
        sweepOnArrival: false,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Open card'));
    expect(taps, 1);
    await tester.tap(find.byType(ExampleLivingCard));
    expect(taps, 2);
  });

  testWidgets('loader stops scheduling frames when animations are disabled',
      (tester) async {
    var reduceMotion = true;
    late StateSetter update;
    await _pump(
      tester,
      StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
          ),
          child: const ExampleLoader(),
        );
      }),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse);

    update(() => reduceMotion = false);
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isTrue);

    update(() => reduceMotion = true);
    await tester.pump();
    // Drain the frame that was already queued before the ticker stopped.
    await tester.pump();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
