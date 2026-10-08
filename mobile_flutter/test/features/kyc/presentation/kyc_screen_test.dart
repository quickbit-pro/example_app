// Layout, state and accessibility proof for the Example identity-verification
// screen.
//
// This is the highest-anxiety flow in the product, so the assertions are
// about reassurance being *present and correct*, not about pixels: that every
// question says what it is used for, that the three step states are told
// apart by shape and not only by hue, that a failed launch stays visible in
// a live region alongside the original snackbar feedback, and that the
// whole screen survives 375, 393, 834 and 1440 in both
// themes with no overflow and no truncated string.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/kyc/application/kyc_providers.dart';
import 'package:mobile_flutter/features/kyc/data/kyc_api.dart';
import 'package:mobile_flutter/features/kyc/presentation/kyc_screen.dart';
import 'package:mobile_flutter/shared/widgets/searchable_multi_select_dropdown.dart';

const List<Size> _sizes = [
  Size(375, 812),
  Size(393, 852),
  Size(834, 1112),
  Size(1440, 900),
];

/// flutter_test renders in a fallback face whose every glyph is one em wide,
/// about twice the average advance of Geist. [_realistic] puts string widths
/// back where a real humanist sans puts them, which is the only scale at
/// which "does anything truncate?" is a meaningful question; [_stress] leaves
/// the square metrics alone, so the same layouts are proved again carrying
/// roughly 2x type.
const double _realistic = 0.5;
const double _stress = 1;

ThemeData _theme(Brightness brightness) => ThemeData(
      brightness: brightness,
      extensions: const [ExampleBrand()],
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? ExampleColors.appBackground
          : ExampleColors.lightPaper,
    );

const List<OccupationCode> _occupations = [
  OccupationCode(value: '1', title: 'Engineer'),
  OccupationCode(value: '2', title: 'Teacher'),
];

/// A launcher that fails, so the rejection register can be rendered.
class _FailingKycController extends KycController {
  @override
  Future<KycLaunchOutcome?> build() async => throw Exception('offline');
}

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required Size size,
  double textScale = _realistic,
  bool failing = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        kycDetailedStatusProvider
            .overrideWith((ref) async => KycDetailedStatus.fromJson({})),
        occupationCodesProvider.overrideWith((ref) async => _occupations),
        if (failing)
          kycControllerProvider.overrideWith(_FailingKycController.new),
      ],
      child: MaterialApp(
        theme: _theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const KycScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectNoTruncation(WidgetTester tester) {
  final truncated = <String>[];
  for (final element in tester.allElements) {
    final object = element.renderObject;
    if (object is RenderParagraph && object.didExceedMaxLines) {
      truncated.add(object.text.toPlainText());
    }
  }
  expect(truncated, isEmpty, reason: 'truncated: $truncated');
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('occupation search and selection, ${brightness.name}',
        (tester) async {
      await _pump(
        tester,
        brightness: brightness,
        size: const Size(393, 852),
      );
      final picker = find.byType(SearchableSingleSelectDropdown);
      await tester.ensureVisible(picker);
      await tester.tap(picker);
      await tester.pumpAndSettle();

      final search = find.widgetWithText(TextField, 'Search occupation');
      await tester.enterText(search, '  TEACH  ');
      await tester.pumpAndSettle();
      expect(find.text('Teacher'), findsOneWidget);
      expect(find.text('Engineer'), findsNothing);

      await tester.enterText(search, 'no such occupation');
      await tester.pumpAndSettle();
      expect(find.text('No matching options'), findsOneWidget);
      await tester.enterText(search, '');
      await tester.pumpAndSettle();
      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('Teacher'), findsOneWidget);

      await tester.tap(find.text('Teacher'));
      await tester.pumpAndSettle();
      expect(tester.widget<SearchableSingleSelectDropdown>(picker).value, '2');
      expect(find.text('Teacher'), findsOneWidget);

      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.enterText(search, 'engineer');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(tester.widget<SearchableSingleSelectDropdown>(picker).value, '2');
      expect(tester.takeException(), isNull);
    });
  }

  group('verification holds every supported width in both themes', () {
    for (final brightness in Brightness.values) {
      for (final size in _sizes) {
        testWidgets('${brightness.name}, ${size.width.toInt()}', (
          tester,
        ) async {
          await _pump(tester, brightness: brightness, size: size);
          expect(tester.takeException(), isNull);
          _expectNoTruncation(tester);
        });

        testWidgets('2x type, ${brightness.name}, ${size.width.toInt()}', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            size: size,
            textScale: _stress,
          );
          expect(tester.takeException(), isNull);
        });

        testWidgets('failed launch, ${brightness.name}, ${size.width.toInt()}',
            (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            size: size,
            failing: true,
          );
          expect(tester.takeException(), isNull);
          _expectNoTruncation(tester);
        });
      }
    }
  });

  testWidgets('every question says what the answer is used for', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      size: const Size(375, 812),
    );
    for (final why in const [
      'The regulator that licenses your account requires it.',
      'A range is enough. We never ask for an exact figure.',
      'Tells us what normal activity looks like on your account.',
      'Sets your starting limits. An estimate is fine.',
      'Must match the ID you photograph in the next step.',
    ]) {
      expect(find.text(why), findsOneWidget, reason: why);
    }
  });

  testWidgets('the documents and the reason for them are stated up front', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      size: const Size(393, 852),
    );
    expect(find.text('What you will need'), findsOneWidget);
    expect(find.text('Photo ID'), findsOneWidget);
    expect(find.text('Selfie'), findsOneWidget);
    // Nothing has been asked for yet, so both slots are outlines — empty and
    // filled differ in material, not in tint.
    expect(find.byType(ExampleDashedPanel), findsNWidgets(2));
    expect(
      find.text('Required by law before an account can hold or send money.'),
      findsOneWidget,
    );
  });

  testWidgets('step state is shape, not only hue', (tester) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      size: const Size(375, 812),
    );
    // Step one is current (ring and dot); two and three are numerals, not
    // featureless rings.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('1'), findsNothing);
  });

  testWidgets('the decisive action is the glass CTA and nothing else is', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      size: const Size(375, 812),
    );
    expect(find.byType(ExampleGlassButton), findsOneWidget);
    expect(find.text('Start verification'), findsOneWidget);
  });

  testWidgets('a failed launch keeps inline and original snackbar feedback', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      size: const Size(375, 812),
      failing: true,
    );
    expect(find.text('Verification did not start'), findsOneWidget);
    expect(
      find.text('Allow pop-ups for this site, then start again.'),
      findsOneWidget,
    );
    // Keep the existing error feedback while the visual notice remains on
    // the form after the snackbar disappears.
    expect(find.byType(SnackBar), findsOneWidget);
    final liveNotice = find.ancestor(
      of: find.text('Verification did not start'),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Semantics && (widget.properties.liveRegion ?? false),
      ),
    );
    expect(liveNotice, findsOneWidget);
    // Verification still starts through the existing form action.
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Start verification'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Verification did not start'), findsOneWidget);
    expect(liveNotice, findsOneWidget);
  });

  testWidgets('loading options reserve the control instead of spinning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          kycDetailedStatusProvider
              .overrideWith((ref) async => KycDetailedStatus.fromJson({})),
          occupationCodesProvider.overrideWith(
            (ref) => Completer<List<OccupationCode>>().future,
          ),
        ],
        child: MaterialApp(
          theme: _theme(Brightness.dark),
          home: const KycScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Occupation'), findsOneWidget);
    expect(find.byType(ExampleSkeleton), findsOneWidget);
  });
}
