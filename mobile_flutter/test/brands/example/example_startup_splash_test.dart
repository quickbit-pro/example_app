import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_startup_splash.dart';
import 'package:mobile_flutter/brands/example/example_mark.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';

class _RestoredAuth extends AuthController {
  _RestoredAuth(this.result);
  final Future<AuthState> result;
  @override
  Future<AuthState> build() => result;
}

void main() {
  Future<void> pumpSplash(WidgetTester tester, Future<AuthState> session) =>
      tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(() => _RestoredAuth(session))
        ],
        child: const MaterialApp(
            home:
                ExampleStartupSplash(child: Scaffold(body: Text('App ready')))),
      ));

  testWidgets('startup hides the session loader beneath its translucent glow',
      (tester) async {
    final session = Completer<AuthState>();
    final loaderColor = ValueNotifier<Color>(Colors.red);
    const captureKey = ValueKey('startup-frame');
    addTearDown(loaderColor.dispose);
    addTearDown(() => session.complete(const AuthState()));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authControllerProvider
            .overrideWith(() => _RestoredAuth(session.future)),
      ],
      child: MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: ExampleStartupSplash(
            child: Scaffold(
              body: Center(
                child: ValueListenableBuilder<Color>(
                  valueListenable: loaderColor,
                  builder: (_, color, __) =>
                      ExampleLoader(size: 42, color: color),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    Future<Uint8List> pixels() async {
      final boundary =
          tester.renderObject<RenderRepaintBoundary>(find.byKey(captureKey));
      return (await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes =
            await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        image.dispose();
        return bytes!.buffer.asUint8List();
      }))!;
    }

    final first = await pixels();
    loaderColor.value = Colors.green;
    await tester.pump(); // Same animation frame, different loader underneath.
    expect(await pixels(), orderedEquals(first),
        reason:
            'The session loader must not bleed through the startup splash.');
  });

  testWidgets('startup completes the customer intro before revealing the app',
      (tester) async {
    await pumpSplash(tester, Future.value(const AuthState()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    if (!kIsWeb) {
      expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          1,
          reason: 'Native must finish the logo assembly.');
      await tester.pump(const Duration(milliseconds: 1250));
    }
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.text('App ready').hitTestable(), findsOneWidget);
  });

  testWidgets(
      'sealed biometric session shows login without an automatic prompt',
      (tester) async {
    await pumpSplash(
        tester, Future.value(const AuthState(biometricLocked: true)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    if (!kIsWeb) {
      expect(
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          1,
          reason: 'Native must finish the logo assembly.');
      await tester.pump(const Duration(milliseconds: 1250));
    }
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AnimatedOpacity), findsNothing);
    expect(find.text('App ready').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slow session restoration still holds the splash',
      (tester) async {
    final session = Completer<AuthState>();
    await pumpSplash(tester, session.future);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1);
    session.complete(const AuthState());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(AnimatedOpacity), findsNothing);
  });
}
