import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example_ui.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';

const _card = PaymentCard(
  id: 'card-1',
  label: 'Quantum Black',
  last4: '4242',
  network: 'Visa',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 1200),
  spendThisMonth: Money(currency: 'USD', minorUnits: 300),
  limit: Money(currency: 'USD', minorUnits: 50000),
  virtual: true,
);

const _serverCard = PaymentCard(
  id: 'server-card',
  label: 'Provider card',
  last4: '4242',
  network: 'Visa',
  currency: 'USD',
  status: CardStatus.active,
  balance: Money(currency: 'USD', minorUnits: 1200),
  spendThisMonth: Money(currency: 'USD', minorUnits: 300),
  limit: Money(currency: 'USD', minorUnits: 50000),
  virtual: true,
  cardImageUrl: 'https://cards.example.test/provider/full.png',
  cardThumbnailUrl: 'https://cards.example.test/provider/thumbnail.png',
  cardImageAlt: 'Provider blue card',
  cardTextColor: '#112233',
);

Widget _host({
  required double width,
  required Brightness brightness,
  Widget? child,
  bool reducedMotion = false,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: ThemeData(brightness: brightness),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 900),
        disableAnimations: reducedMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: child ??
                ExampleLivingCard(
                  card: _card,
                  height: ExampleLivingCard.heightFor(width),
                ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  for (final width in const [375.0, 393.0, 834.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('living card fits at $width in $brightness', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(_host(width: width, brightness: brightness));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(ExampleLivingCard), findsOneWidget);
        // Provisioned cards retain their real masked metadata, without
        // inventing a replacement metallic design when artwork is absent.
        expect(find.textContaining('4242'), findsOneWidget);
        expect(find.textContaining('••••  ••••  ••••  4242'), findsNothing);
        expect(find.byType(ExampleLockup), findsNothing);
      });
    }
  }

  testWidgets('holds at a 1.6 text scale without overflow', (tester) async {
    await tester.pumpWidget(
      _host(width: 375, brightness: Brightness.light, textScale: 1.6),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact provisioned cards add no number or baked-in brand',
      (tester) async {
    await tester.pumpWidget(
      _host(
        width: 96,
        brightness: Brightness.dark,
        child: const ExampleLivingCard(card: _card, height: 57, compact: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('••••  ••••'), findsNothing);

    await tester.pumpWidget(
      _host(
        width: 70,
        brightness: Brightness.dark,
        child: const ExampleLivingCard(card: _card, height: 44, compact: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('a short face falls back to the compact layout', (tester) async {
    await tester.pumpWidget(
      _host(
        width: 140,
        brightness: Brightness.light,
        child: const ExampleLivingCard(card: _card, height: 88),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('frozen goes under glass, never behind a banner', (tester) async {
    await tester.pumpWidget(
      _host(
        width: 375,
        brightness: Brightness.light,
        child: const ExampleLivingCard(
          card: _card,
          height: 200,
          status: CardStatus.frozen,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final blur = tester.widgetList<BackdropFilter>(find.byType(BackdropFilter));
    expect(blur, isNotEmpty);
    expect(blur.first.filter, isA<ImageFilter>());
    expect(find.text('Frozen'), findsOneWidget);
  });

  testWidgets('publishes a masked description, never the number',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(width: 375, brightness: Brightness.dark));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(RegExp(r'ending 4 2 4 2')),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('the arrival pass runs once and settles', (tester) async {
    await tester.pumpWidget(_host(width: 375, brightness: Brightness.dark));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // Mid-pass the painter is live; pumpAndSettle proves it terminates rather
    // than looping, which is the whole contract of a single moment.
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion schedules no animation at all', (tester) async {
    await tester.pumpWidget(
      _host(width: 375, brightness: Brightness.dark, reducedMotion: true),
    );
    await tester.pump();
    // No frame is scheduled once the tree is built: with the sweep suppressed
    // there is nothing left ticking on the card screen.
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposes cleanly when the face leaves the tree', (tester) async {
    await tester.pumpWidget(_host(width: 375, brightness: Brightness.dark));
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pumpWidget(
      _host(
        width: 375,
        brightness: Brightness.dark,
        child: const SizedBox.shrink(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an explicit label wins over the masked default', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _host(
        width: 375,
        brightness: Brightness.light,
        child: const ExampleLivingCard(
          card: _card,
          height: 200,
          semanticsLabel: 'Preview of New card',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Preview of New card'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('provider artwork URLs remain authoritative at both sizes',
      (tester) async {
    for (final compact in [false, true]) {
      await tester.pumpWidget(
        _host(
          width: compact ? 70 : 375,
          brightness: Brightness.light,
          reducedMotion: true,
          child: ExampleLivingCard(
            card: _serverCard,
            height: compact ? 44 : 220,
            compact: compact,
            sweepOnArrival: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url,
          compact ? _serverCard.cardThumbnailUrl : _serverCard.cardImageUrl);
      expect(image.semanticLabel, _serverCard.cardImageAlt);
      expect(find.byType(ExampleLockup), findsNothing);
      expect(
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where(
              (paint) =>
                  paint.painter.runtimeType.toString() ==
                  '_BrushedMetalPainter',
            ),
        isEmpty,
      );
      if (compact) expect(find.textContaining('4242'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('ExamplePaymentCard is untouched and still renders',
      (tester) async {
    await tester.pumpWidget(
      _host(
        width: 375,
        brightness: Brightness.dark,
        child: const ExamplePaymentCard(card: _card),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ExamplePaymentCard), findsOneWidget);
  });
}
