import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_limits_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Geist');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      font.addFont(Future.value(ByteData.sublistView(
          File('assets/fonts/Geist-$weight.ttf').readAsBytesSync())));
    }
    await font.load();
  });
  Future<void> openDialog(WidgetTester tester,
      {bool allowBasic = true,
      ValueChanged<String?>? onResult,
      ThemeData? theme,
      double scale = 1,
      GlobalKey? capture}) async {
    await tester.pumpWidget(RepaintBoundary(
      key: capture,
      child: MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(builder: (context) {
            return TextButton(
              onPressed: () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => ExchangeLimitsDialog(allowBasic: allowBasic),
                );
                onResult?.call(result);
              },
              child: const Text('Open'),
            );
          }),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  for (final choice in {'Basic': 'sdd', 'Higher limits': 'cdd'}.entries) {
    testWidgets('${choice.key} continues with the correct tier',
        (tester) async {
      String? result;
      await openDialog(tester, onResult: (value) => result = value);
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.text(choice.key));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(ExchangeLimitsDialog), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(result, choice.value);
      expect(find.byType(ExchangeLimitsDialog), findsNothing);
    });
  }

  testWidgets('higher-tier users cannot select Basic; Cancel returns no tier',
      (tester) async {
    String? result = 'unchanged';
    await openDialog(tester,
        allowBasic: false, onResult: (value) => result = value);
    expect(find.text('Basic'), findsNothing);
    expect(find.text('Higher limits'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  final themes = buildAppThemes(AppBranding.fromEnvironment());
  for (final dark in [false, true]) {
    for (final size in [
      const Size(390, 844),
      const Size(320, 568),
      const Size(568, 320)
    ]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('limits fit $size at $scale, dark: $dark', (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final capture = GlobalKey();
          await openDialog(tester,
              theme: dark ? themes.dark : themes.light,
              scale: scale,
              capture: capture);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(find.text('Higher limits'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text('Higher limits').hitTestable(), findsOneWidget);
          await tester.tap(find.text('Higher limits'));
          await tester.pumpAndSettle();
          final preview = Platform.environment['EXCHANGE_LIMITS_PREVIEW'];
          if (preview != null && size.width == 390 && scale == 1) {
            await tester.runAsync(() async {
              final boundary = capture.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: 2);
              final data =
                  await image.toByteData(format: ui.ImageByteFormat.png);
              File('$preview-${dark ? 'dark' : 'light'}.png')
                ..parent.createSync(recursive: true)
                ..writeAsBytesSync(data!.buffer.asUint8List());
              image.dispose();
            });
          }
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(find.byType(ExchangeLimitsDialog), findsNothing);
        });
      }
    }
  }
}
