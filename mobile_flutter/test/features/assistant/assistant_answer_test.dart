import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_colors.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/assistant/presentation/assistant_answer.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_api.dart';
import 'package:mobile_flutter/flavors.dart';

AppBranding _branding(AppDesign design) => AppBranding(
      appName: 'Hoppa',
      brandId: 'hoppa',
      primarySeedHex: '621A96',
      accentSeedHex: 'C6F24E',
      loginBackgroundHex: '',
      themeMode: 'dark',
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@hoppa.com',
      supportPhone: '',
      legalEntity: 'Hoppa',
      design: design,
    );

Future<void> _pumpAnswer(
  WidgetTester tester,
  String text, {
  Brightness brightness = Brightness.dark,
  double textScale = 1,
  AssistantStructuredAnswer? answer,
  AppDesign design = const AppDesign(),
  ValueChanged<String>? onOpenSource,
  bool example = true,
}) async {
  await tester.binding.setSurfaceSize(const Size(320, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final themes = buildAppThemes(_branding(design));
  await tester.pumpWidget(MaterialApp(
    theme: !example
        ? ThemeData()
        : brightness == Brightness.dark
            ? themes.dark
            : themes.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: AssistantAnswer(
            text: text, answer: answer, onOpenSource: onOpenSource),
      ),
    ),
  ));
  await tester.pump();
}

Finder get _answer => find.byType(AssistantAnswer);
Finder get _richText =>
    find.descendant(of: _answer, matching: find.byType(RichText));

Iterable<TextSpan> _spans(InlineSpan span) sync* {
  if (span is TextSpan) {
    yield span;
    for (final child in span.children ?? const <InlineSpan>[]) {
      yield* _spans(child);
    }
  }
}

const _cardAnswer = AssistantStructuredAnswer(
  title: 'Quiet stays in Rome',
  summary: 'Three options to compare for your next break.',
  options: [
    AssistantAnswerOption(
      title: 'Trilussa Palace Hotel',
      highlights: [
        'Trastevere location with a private spa.',
        'Ask for a quiet room and a refundable rate.',
      ],
      details:
          'Spa sessions are charged separately. Check the cancellation deadline for your chosen rate.',
    ),
    AssistantAnswerOption(
      title: 'The Code Hotel',
      highlights: ['Central location near the Spanish Steps.'],
      details: 'Spa access depends on the room package.',
    ),
    AssistantAnswerOption(
      title: 'The One Boutique Hotel',
      highlights: ['A smaller stay with spa packages.'],
    ),
  ],
  nextStep: 'What are your travel dates and party size?',
);

void main() {
  const linkedAnswer = AssistantStructuredAnswer(
    title: 'A quiet stay',
    summary: 'Compare this hotel for your dates.',
    options: [
      AssistantAnswerOption(
          title: 'Garden hotel',
          highlights: ['Quiet courtyard'],
          source: AssistantSource(
              title: 'Garden hotel', url: 'https://hotel.com/rooms?guests=2'))
    ],
  );

  for (final brightness in Brightness.values) {
    testWidgets(
        'Example website button opens exact URL at large text in $brightness',
        (tester) async {
      String? opened;
      await _pumpAnswer(tester, 'Reply',
          answer: linkedAnswer,
          brightness: brightness,
          textScale: 2,
          onOpenSource: (url) => opened = url);
      expect(find.text('View website'), findsOneWidget);
      expect(find.text('hotel.com'), findsOneWidget);
      await tester.ensureVisible(find.text('View website'));
      await tester.tap(find.text('View website'));
      expect(opened, linkedAnswer.options.single.source!.url);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('website buttons work without the Example theme', (tester) async {
    await _pumpAnswer(tester, 'Reply',
        answer: linkedAnswer, example: false, onOpenSource: (_) {});
    expect(find.text('Garden hotel'), findsOneWidget);
    expect(find.text('View website'), findsOneWidget);
  });

  testWidgets('unsafe manually constructed source never becomes a button',
      (tester) async {
    await _pumpAnswer(tester, 'Reply',
        answer: const AssistantStructuredAnswer(
            title: 'Stay',
            summary: 'Consider this hotel.',
            options: [
              AssistantAnswerOption(
                  title: 'Hotel',
                  highlights: ['Courtyard'],
                  source: AssistantSource(
                      title: 'Hotel', url: 'javascript:alert(1)')),
            ]),
        onOpenSource: (_) => fail('Must not launch'));
    expect(find.text('Hotel'), findsOneWidget);
    expect(find.text('View website'), findsNothing);
  });

  testWidgets(
      'structured options use clear cards with details hidden until requested',
      (tester) async {
    await _pumpAnswer(tester, 'Legacy duplicate must not be rendered.',
        answer: _cardAnswer);
    expect(find.text(_cardAnswer.title), findsOneWidget);
    expect(find.text(_cardAnswer.summary), findsOneWidget);
    expect(find.text('Legacy duplicate must not be rendered.'), findsNothing);
    expect(find.text('01'), findsOneWidget);
    expect(find.text('02'), findsOneWidget);
    expect(find.text('03'), findsOneWidget);
    expect(find.text('Next step'), findsOneWidget);
    expect(find.text(_cardAnswer.nextStep!), findsOneWidget);
    expect(find.text(_cardAnswer.options.first.details!), findsNothing);
    expect(find.text(_cardAnswer.options[1].details!), findsNothing);
    expect(find.text('More details'), findsNWidgets(2));

    await tester.tap(find.text('More details').first);
    await tester.pump();
    expect(find.text(_cardAnswer.options.first.details!), findsOneWidget);
    expect(find.text(_cardAnswer.options[1].details!), findsNothing);
    expect(find.text('Less details'), findsOneWidget);
    await tester.ensureVisible(find.text('Less details'));
    await tester.tap(find.text('Less details'));
    await tester.pump();
    expect(find.text(_cardAnswer.options.first.details!), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'long old answers have a bounded preview with a reversible expansion',
      (tester) async {
    final firstParagraph =
        List.filled(30, 'A long hotel description.').join(' ');
    final reply = '$firstParagraph\n\nLast detail remains available.';
    await _pumpAnswer(tester, reply);
    expect(find.text(firstParagraph), findsNothing);
    expect(find.text('Last detail remains available.'), findsNothing);
    expect(find.text('Show full answer'), findsOneWidget);
    expect(tester.getSize(_answer).height, lessThan(420));
    await tester.tap(find.text('Show full answer'));
    await tester.pump();
    expect(find.text(firstParagraph), findsOneWidget);
    expect(find.text('Last detail remains available.'), findsOneWidget);
    await tester.ensureVisible(find.text('Show less'));
    await tester.tap(find.text('Show less'));
    await tester.pump();
    expect(find.text(firstParagraph), findsNothing);
    expect(find.text('Last detail remains available.'), findsNothing);
  });

  testWidgets('many short legacy lines also collapse', (tester) async {
    final reply = List.generate(30, (index) => '- Option $index').join('\n');
    await _pumpAnswer(tester, reply);
    expect(find.text('Option 29'), findsNothing);
    expect(find.text('Show full answer'), findsOneWidget);
    expect(tester.getSize(_answer).height, lessThan(350));
  });

  testWidgets('a replacement reply resets open details and legacy expansion',
      (tester) async {
    await _pumpAnswer(tester, 'Previous', answer: _cardAnswer);
    await tester.tap(find.text('More details').first);
    await tester.pump();
    const replacement = AssistantStructuredAnswer(
      title: 'A different stay',
      summary: 'Compare this option.',
      options: [
        AssistantAnswerOption(
          title: 'Another hotel',
          highlights: ['Near the station.'],
          details: 'New details should start collapsed.',
        ),
      ],
    );
    await _pumpAnswer(tester, 'New reply', answer: replacement);
    expect(find.text('New details should start collapsed.'), findsNothing);
    expect(find.text('More details'), findsOneWidget);
    final first = List.filled(50, 'Old content.').join(' ');
    final second = List.filled(50, 'New content.').join(' ');
    await _pumpAnswer(tester, first);
    await tester.tap(find.text('Show full answer'));
    await tester.pump();
    await _pumpAnswer(tester, second);
    expect(find.text(second), findsNothing);
    expect(find.text('Show full answer'), findsOneWidget);
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'structured cards wrap at 320px with large text in ${brightness.name}',
        (tester) async {
      await _pumpAnswer(tester, 'Legacy',
          answer: _cardAnswer, brightness: brightness, textScale: 2);
      for (final element in _richText.evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.width, lessThanOrEqualTo(288));
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('clarification answers need no empty recommendation cards',
      (tester) async {
    const answer = AssistantStructuredAnswer(
      title: 'Let’s choose your dates',
      summary: 'I can help compare nearby destinations.',
      options: [],
      nextStep: 'When would you like to travel?',
    );
    await _pumpAnswer(tester, 'Legacy', answer: answer);
    expect(find.text(answer.title), findsOneWidget);
    expect(find.text('01'), findsNothing);
    expect(find.text('More details'), findsNothing);
    expect(find.text(answer.nextStep!), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('short headings gain visual and accessibility hierarchy',
      (tester) async {
    await _pumpAnswer(tester,
        '# Flights\nUse nearby airports.\n\n## Hotels\nCompare cancellation.\n\n**Next steps**\nChoose your dates.');

    for (final heading in ['Flights', 'Hotels', 'Next steps']) {
      final finder = find.text(heading);
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).style!.fontWeight, FontWeight.w700);
      final semantics = tester.widget<Semantics>(find.ancestor(
        of: finder,
        matching: find.byWidgetPredicate((widget) =>
            widget is Semantics && widget.properties.header == true),
      ));
      expect(semantics.properties.header, isTrue);
    }
    expect(find.text('# Flights'), findsNothing);
    expect(find.text('**Next steps**'), findsNothing);
    expect(find.text('Choose your dates.'), findsOneWidget);
  });

  testWidgets('short plain section labels become headings and keep their colon',
      (tester) async {
    final longLabel = '${List.filled(9, 'Long label').join(' ')}:';
    await _pumpAnswer(tester,
        'Options:\nCompare these trips.\n\nBefore you book:\n- Check cancellation:\n\nhttps://example.com/path:\n\n$longLabel');
    for (final label in ['Options:', 'Before you book:']) {
      final finder = find.text(label);
      expect(finder, findsOneWidget);
      expect(tester.widget<Text>(finder).style!.fontWeight, FontWeight.w700);
      expect(
          find.ancestor(
            of: finder,
            matching: find.byWidgetPredicate((widget) =>
                widget is Semantics && widget.properties.header == true),
          ),
          findsOneWidget);
    }
    expect(find.text('•'), findsOneWidget);
    for (final body in [
      'Check cancellation:',
      'https://example.com/path:',
      longLabel
    ]) {
      expect(tester.widget<Text>(find.text(body)).style!.fontWeight,
          isNot(FontWeight.w700));
    }
  });

  testWidgets('inline bold preserves readable text and surrounding punctuation',
      (tester) async {
    await _pumpAnswer(tester,
        'Choose **flexible fares**, then compare **baggage**.\nKeep an unmatched ** marker.');
    final finder = find.text(
        'Choose flexible fares, then compare baggage.\nKeep an unmatched ** marker.');
    expect(finder, findsOneWidget);
    final text = tester.widget<Text>(finder);
    final bold = _spans(text.textSpan!)
        .where((span) => span.style?.fontWeight == FontWeight.w700)
        .map((span) => span.text);
    expect(bold, ['flexible fares', 'baggage']);
    expect(text.style!.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('paragraph gaps and explicit newlines remain readable',
      (tester) async {
    await _pumpAnswer(
        tester, 'First paragraph.\r\nSecond line.\r\n\r\n\r\nFinal paragraph.');
    final first = find.text('First paragraph.\nSecond line.');
    final last = find.text('Final paragraph.');
    expect(first, findsOneWidget);
    expect(last, findsOneWidget);
    expect(tester.getTopLeft(last).dy - tester.getBottomLeft(first).dy,
        greaterThanOrEqualTo(8));
    expect(tester.takeException(), isNull);
  });

  testWidgets('bullets hang beside their text and keep continuation lines',
      (tester) async {
    await _pumpAnswer(tester,
        '- **Hotel A**\n  Breakfast included\n* Hotel B\n+ Hotel C\n• Hotel D\n\n2. Flight A\n7) Flight B');

    expect(find.text('•'), findsNWidgets(4));
    expect(find.text('Hotel A\nBreakfast included'), findsOneWidget);
    expect(find.text('2.'), findsOneWidget);
    expect(find.text('7)'), findsOneWidget);
    expect(find.text('Flight A'), findsOneWidget);
    expect(find.text('Flight B'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Hotel A\nBreakfast included')).dx,
        tester.getTopLeft(find.text('Hotel B')).dx);
    expect(tester.getTopLeft(find.text('Hotel B')).dx,
        greaterThan(tester.getTopLeft(find.text('•').first).dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('URLs markdown links and HTML remain visible inert text',
      (tester) async {
    const text = 'https://example.com/hotel\n'
        '[Book hotel](https://example.com/booking)\n'
        '<a href="javascript:alert(1)">Offer</a>\n'
        '[Unsafe](javascript:alert(1))';
    await _pumpAnswer(tester, text);
    expect(find.text(text), findsOneWidget);
    for (final widget in tester.widgetList<RichText>(_richText)) {
      expect(
          _spans(widget.text).every((span) => span.recognizer == null), isTrue);
    }
    await tester.tap(find.text(text));
    await tester.pump();
    expect(find.text(text), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all content is registered for selection', (tester) async {
    await _pumpAnswer(
        tester, '## Travel ideas\nCompare **fares**.\n- Read terms');
    expect(find.descendant(of: _answer, matching: find.byType(SelectionArea)),
        findsOneWidget);
    for (final widget in tester.widgetList<RichText>(_richText)) {
      expect(widget.selectionRegistrar, isNotNull);
      expect(widget.selectionColor, isNotNull);
    }
  });

  testWidgets('unknown syntax and long emphasized sentences stay body copy',
      (tester) async {
    final longSentence = List.filled(25, 'Long sentence').join(' ');
    await _pumpAnswer(tester, '### Unrecognized heading\n\n**$longSentence**');
    expect(find.text('### Unrecognized heading'), findsOneWidget);
    expect(find.text(longSentence), findsOneWidget);
    expect(
        find.descendant(
          of: _answer,
          matching: find.byWidgetPredicate((widget) =>
              widget is Semantics && widget.properties.header == true),
        ),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final brightness in Brightness.values) {
    testWidgets('${brightness.name} palette and mobile wrapping stay readable',
        (tester) async {
      final host = '${List.filled(20, 'longhostname').join()}.example.com';
      final word = List.filled(35, 'unbroken').join();
      await _pumpAnswer(
          tester, '## Recommended trip\n- https://$host/flights\n\n**$word**',
          brightness: brightness, textScale: 1.5);
      await tester.ensureVisible(find.text('Show full answer'));
      await tester.tap(find.text('Show full answer'));
      await tester.pump();
      final text = tester.widget<Text>(find.text('https://$host/flights'));
      expect(text.style!.color, ExamplePalette.forBrightness(brightness).ink);
      expect(text.style!.fontSize, 13.5);
      expect(text.style!.height, 1.5);
      expect(text.maxLines, isNull);
      expect(text.softWrap, isTrue);

      for (final element in _richText.evaluate().where((element) =>
          element.findAncestorWidgetOfExactType<TextButton>() == null)) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(paragraph.didExceedMaxLines, isFalse);
        expect(paragraph.size.width, lessThanOrEqualTo(288));
        final boxes = paragraph.getBoxesForSelection(TextSelection(
          baseOffset: 0,
          extentOffset: paragraph.text.toPlainText().length,
        ));
        for (final box in boxes) {
          expect(box.left, greaterThanOrEqualTo(-0.5));
          expect(box.right, lessThanOrEqualTo(paragraph.size.width + 0.5));
        }
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets(
        '${brightness.name} custom brand palette and typography apply once',
        (tester) async {
      const design = AppDesign({
        'layout': 'example',
        'light': {'ink': '#172E26'},
        'dark': {'ink': '#EEF5F0'},
        'typography': {'fontFamily': 'Brand Sans', 'scale': 1.2},
      });
      await _pumpAnswer(
          tester, '## Your options\nCompare **fares**.\n- Read terms',
          brightness: brightness, design: design);
      final expectedColor = brightness == Brightness.dark
          ? const Color(0xFFEEF5F0)
          : const Color(0xFF172E26);
      for (final text in tester.widgetList<Text>(
          find.descendant(of: _answer, matching: find.byType(Text)))) {
        expect(text.style!.color, expectedColor);
        expect(text.style!.fontSize, closeTo(13.5 * 1.2, 0.001));
        expect(text.style!.fontFamily, 'Brand Sans');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('empty response has no spurious content or spacing',
      (tester) async {
    await _pumpAnswer(tester, ' \n\n');
    expect(_richText, findsNothing);
    expect(tester.getSize(_answer).height, 0);
    expect(tester.takeException(), isNull);
  });
}
