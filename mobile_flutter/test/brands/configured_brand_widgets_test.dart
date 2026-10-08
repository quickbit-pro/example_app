import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_startup_splash.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/branding/app_design.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/shared/widgets/app_progress_indicator.dart';
import 'package:mobile_flutter/shared/widgets/brand_asset.dart';
import 'package:mobile_flutter/shared/widgets/brand_loader.dart';
import 'package:mobile_flutter/shared/widgets/neo_banking_components.dart';

class _BrandAssets extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{})!;
    }
    if (key == 'missing.png') throw FlutterError('Missing test logo');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8'
      '/x8AAwMCAO+aFOsAAAAASUVORK5CYII=',
    );
    return ByteData.sublistView(bytes);
  }
}

class _RestoredAuth extends AuthController {
  _RestoredAuth(this.result);
  final Future<AuthState> result;

  @override
  Future<AuthState> build() => result;
}

Widget _app(
  Widget child, {
  AppDesign design = const AppDesign(),
  Brightness brightness = Brightness.light,
  bool reduceMotion = false,
}) =>
    DefaultAssetBundle(
      bundle: _BrandAssets(),
      child: MaterialApp(
        themeAnimationDuration: Duration.zero,
        theme: ThemeData(
          brightness: brightness,
          extensions: [AppDesignTheme(design: design, appName: 'Acme Pay')],
        ),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Scaffold(body: Center(child: child)),
        ),
      ),
    );

Future<void> _splash(
  WidgetTester tester,
  Future<AuthState> session,
  AppDesign design, {
  bool reduceMotion = false,
}) =>
    tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(() => _RestoredAuth(session)),
      ],
      child: _app(
        const SizedBox.expand(
          child: ExampleStartupSplash(child: Text('App ready')),
        ),
        design: design,
        reduceMotion: reduceMotion,
      ),
    ));

void main() {
  testWidgets('splash wordmark has no inherited fallback underline',
      (tester) async {
    // Cold-start overlays sit above route Scaffolds, without a Material text
    // style ancestor. Check the resolved paragraph rather than a widget field.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [
        AppDesignTheme(design: AppDesign(), appName: 'Acme Pay'),
      ]),
      home: const Center(child: BrandWordmark(height: 24)),
    ));
    final paragraph = tester.widget<RichText>(find.descendant(
      of: find.byType(BrandWordmark),
      matching: find.byType(RichText),
    ));
    expect(paragraph.text.style?.decoration, TextDecoration.none);
  });

  testWidgets('all shared marks use tenant assets, name and dark logo',
      (tester) async {
    const design = AppDesign({
      'layout': 'example',
      'assets': {'logo': 'light.png', 'logoDark': 'dark.png'},
      'motion': {'enabled': false},
    });
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(_app(
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExampleMark(),
            ExampleWordmark(),
            ExampleLockup(),
            BrandMark(appName: 'Old Brand', logoAsset: 'old.png'),
          ],
        ),
        design: design,
        brightness: brightness,
      ));
      final images = tester.widgetList<Image>(find.byType(Image));
      expect(images.length, 3);
      expect(
        images.map((widget) => (widget.image as AssetImage).assetName),
        everyElement(brightness == Brightness.dark ? 'dark.png' : 'light.png'),
      );
      expect(find.text('Acme Pay'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('missing configured asset falls back to tenant initials',
      (tester) async {
    await tester.pumpWidget(_app(
      const ExampleMark(),
      design: const AppDesign({
        'assets': {'logo': 'missing.png'},
      }),
    ));
    await tester.pump();
    expect(find.text('AP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unconfigured artwork uses tenant initials and name',
      (tester) async {
    await tester.pumpWidget(_app(const Column(
      children: [ExampleMark(), ExampleWordmark()],
    )));
    expect(find.text('AP'), findsOneWidget);
    expect(find.text('Acme Pay'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo loader uses its asset and configured rotation duration',
      (tester) async {
    await tester.pumpWidget(_app(
      const AppProgressIndicator(semanticsLabel: 'Fetching accounts'),
      design: const AppDesign({
        'assets': {'logo': 'logo.png', 'loader': 'loading.png'},
        'loader': {'style': 'logo', 'durationMs': 2000},
        'motion': {'durationScale': .5},
      }),
    ));
    final image = tester.widget<Image>(find.byType(Image));
    expect((image.image as AssetImage).assetName, 'loading.png');
    await tester.pump(const Duration(milliseconds: 500));
    final rotation = tester.widget<RotationTransition>(
      find.descendant(
        of: find.byType(BrandLoader),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(rotation.turns.value, closeTo(.5, .02));
  });

  testWidgets('indeterminate loader never announces a fabricated percentage',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(
      const AppProgressIndicator(semanticsLabel: 'Fetching accounts'),
      design: const AppDesign({
        'loader': {'style': 'circular'}
      }),
    ));
    final semantics = tester.getSemantics(find.byType(BrandLoader));
    expect(semantics.label, 'Fetching accounts');
    expect(semantics.value, isEmpty);
    handle.dispose();
  });

  testWidgets('determinate progress retains the actual value and semantics',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(
      const AppProgressIndicator(
        value: .4,
        semanticsLabel: 'Uploading',
        semanticsValue: '40',
        strokeWidth: 2,
      ),
      design: const AppDesign({
        'loader': {'style': 'logo'}
      }),
    ));
    final indicator = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(indicator.value, .4);
    expect(indicator.strokeWidth, 2);
    expect(find.byType(BrandLoader), findsNothing);
    expect(
      tester.getSemantics(find.byType(CircularProgressIndicator)).value,
      '40',
    );
    handle.dispose();
  });

  testWidgets('system and config reduced motion stop loader rotation',
      (tester) async {
    for (final system in [false, true]) {
      await tester.pumpWidget(_app(
        const ExampleLoader.boot(),
        design: AppDesign({
          'loader': const {'style': 'logo'},
          'motion': {'enabled': system},
        }),
        reduceMotion: system,
      ));
      await tester.pump(const Duration(seconds: 2));
      final rotation = tester.widget<RotationTransition>(
        find.descendant(
          of: find.byType(BrandLoader),
          matching: find.byType(RotationTransition),
        ),
      );
      expect(rotation.turns.value, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      expect(find.text('Acme Pay'), findsOneWidget);
    }
  });

  testWidgets('configured splash shows artwork and honors minimum duration',
      (tester) async {
    await _splash(
        tester,
        Future.value(const AuthState()),
        const AppDesign({
          'layout': 'generic',
          'assets': {'splash': 'splash.png'},
          'splash': {
            'minimumDurationMs': 1000,
            'backgroundLight': '#F1EFE5',
          },
        }));
    await tester.pump();
    final image = tester.widget<BrandAsset>(find.byType(BrandAsset));
    expect(image.path, 'splash.png');
    expect(find.text('Acme Pay'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is ColoredBox && widget.color == const Color(0xFFF1EFE5)),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.text('App ready').hitTestable(), findsOneWidget);
  });

  testWidgets('configured timeout reveals app even if session restore hangs',
      (tester) async {
    final session = Completer<AuthState>();
    await _splash(
        tester,
        session.future,
        const AppDesign({
          'splash': {'minimumDurationMs': 0, 'maximumDurationMs': 500},
        }));
    await tester.pump(const Duration(milliseconds: 499));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AnimatedOpacity), findsNothing);
    session.complete(const AuthState());
    await tester.pump();
  });

  testWidgets('disabled splash reveals the app immediately', (tester) async {
    await _splash(
        tester,
        Future.value(const AuthState()),
        const AppDesign({
          'splash': {'enabled': false},
        }));
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.text('App ready').hitTestable(), findsOneWidget);
  });

  testWidgets('reduced motion skips decorative splash delay and fade',
      (tester) async {
    await _splash(
      tester,
      Future.value(const AuthState()),
      const AppDesign({
        'splash': {'minimumDurationMs': 10000}
      }),
      reduceMotion: true,
    );
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.text('App ready').hitTestable(), findsOneWidget);
  });
}
