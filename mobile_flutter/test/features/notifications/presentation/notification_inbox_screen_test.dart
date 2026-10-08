// Layout and accessibility proof for the Example notification inbox.
//
// flutter_test loads no pubspec fonts, so nothing here asserts pixels. It
// asserts what a design wave can actually break on this surface: that the
// empty inbox — the state most customers see most of the time — and the
// populated inbox both survive 375, 393, 834 and 1440 in BOTH themes with no
// RenderFlex overflow and no truncated string, that read and unread differ in
// form and not only in hue, and that tap-to-open rows retain full content
// and an accessible destination label.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/features/notifications/application/notification_inbox_providers.dart';
import 'package:mobile_flutter/features/notifications/domain/app_notification.dart';
import 'package:mobile_flutter/features/notifications/presentation/notification_inbox_screen.dart';
import 'package:mobile_flutter/features/notifications/presentation/notifications_popover.dart';

/// The four widths in the brief.
const List<Size> _sizes = [
  Size(375, 812),
  Size(393, 852),
  Size(834, 1112),
  Size(1440, 900),
];

ThemeData _theme(Brightness brightness) => ThemeData(
      brightness: brightness,
      extensions: const [ExampleBrand()],
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? ExampleColors.appBackground
          : ExampleColors.lightPaper,
    );

List<AppNotification> _items() {
  // 15:00 on the current day, not `DateTime.now()`. The screen buckets by
  // calendar day, so `now - 2h` lands in Yesterday whenever the suite runs in
  // the first two hours after midnight and the Today section never renders.
  final today = DateTime.now();
  final now = DateTime(today.year, today.month, today.day, 15);
  return [
    AppNotification(
      id: '1',
      eventType: 'card',
      title: 'Card delivered',
      body: 'Your Example card was delivered.',
      route: '/cards',
      createdAt: now.subtract(const Duration(hours: 2)),
      readAt: null,
    ),
    AppNotification(
      id: '2',
      eventType: 'money',
      title: 'Payment received',
      body: 'EUR 240.00 arrived.',
      route: '/wallets',
      createdAt: now.subtract(const Duration(days: 1, hours: 3)),
      readAt: now,
    ),
    AppNotification(
      id: '3',
      eventType: 'kyc',
      title: 'Verification approved',
      body: 'Your identity checks are complete.',
      route: '/kyc',
      createdAt: now.subtract(const Duration(days: 6)),
      readAt: now,
    ),
  ];
}

/// flutter_test renders in a fallback face whose every glyph is one em wide,
/// which is roughly twice the average advance of Geist. So the widths here
/// are read twice, at two scales, and each scale proves a different thing:
///
/// * [_realistic] (0.5) puts string widths back in the neighbourhood a real
///   humanist sans produces, which is the only scale at which asking "does
///   any string truncate?" means anything.
/// * [_stress] (1.0) leaves the square metrics alone, so every layout is
///   effectively carrying 2x type. Nothing there may overflow.
const double _realistic = 0.5;
const double _stress = 1;

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  required Size size,
  required List<AppNotification> items,
  double textScale = _realistic,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notificationInboxProvider.overrideWith((ref) async => items),
      ],
      child: MaterialApp(
        theme: _theme(brightness),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: const NotificationInboxScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Every laid-out paragraph, checked for the ellipsis. A design that needs
/// `overflow: ellipsis` to survive a supported width has not survived it.
///
/// Notification title and body wrap so the inbox preserves all content.
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
  group('inbox holds every supported width in both themes', () {
    for (final brightness in Brightness.values) {
      for (final size in _sizes) {
        testWidgets('empty, ${brightness.name}, ${size.width.toInt()}', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            size: size,
            items: const [],
          );
          expect(tester.takeException(), isNull);
          _expectNoTruncation(tester);
          // The empty inbox is a designed screen, not an apology: it says
          // what will arrive here.
          expect(find.text('You are all caught up'), findsOneWidget);
          expect(find.text('WHAT ARRIVES HERE'), findsOneWidget);
        });

        testWidgets('populated, ${brightness.name}, ${size.width.toInt()}', (
          tester,
        ) async {
          await _pump(
            tester,
            brightness: brightness,
            size: size,
            items: _items(),
          );
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
            items: _items(),
            textScale: _stress,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  testWidgets('days are grouped, and the live count is one pill', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      size: const Size(375, 812),
      items: _items(),
    );
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Earlier'), findsOneWidget);
    expect(find.text('1 unread'), findsOneWidget);
  });

  testWidgets('read and unread differ in form, not only in hue', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      size: const Size(375, 812),
      items: _items(),
    );
    // Unread: the filled cut of the mark, inside a tile. Read: the outline,
    // bare. Both survive greyscale.
    expect(find.byType(ExampleIconTile), findsOneWidget);
    expect(find.byIcon(Icons.credit_card_rounded), findsOneWidget);
    expect(find.byIcon(Icons.account_balance_wallet_outlined), findsOneWidget);
    expect(find.byIcon(Icons.verified_user_outlined), findsOneWidget);
  });

  testWidgets('rows announce full content and their existing destinations',
      (tester) async {
    await _pump(
      tester,
      brightness: Brightness.dark,
      size: const Size(375, 812),
      items: _items(),
    );
    final labels = tester
        .widgetList<Semantics>(find.byType(Semantics))
        .map((s) => s.properties.label)
        .whereType<String>()
        .toList();
    for (final item in _items()) {
      expect(
        labels.any((label) =>
            label.contains(item.title) &&
            label.contains(item.body) &&
            label
                .contains('Opens ${notificationDestinationLabel(item.route)}')),
        isTrue,
      );
    }
    for (final row in tester.widgetList<ExampleRow>(find.byType(ExampleRow))) {
      expect(row.onTap, isNotNull);
      expect(row.onLongPress, isNull);
    }
  });

  testWidgets('loading is shape-matched rows, never a spinner', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationInboxProvider.overrideWith(
            (ref) => Completer<List<AppNotification>>().future,
          ),
        ],
        child: MaterialApp(
          theme: _theme(Brightness.light),
          home: const NotificationInboxScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(ExampleSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  group('the desktop popover holds both themes', () {
    for (final brightness in Brightness.values) {
      for (final width in const [375.0, 1440.0]) {
        testWidgets('${brightness.name}, ${width.toInt()}', (tester) async {
          tester.view.physicalSize = Size(width, 900);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                notificationInboxProvider.overrideWith((ref) async => _items()),
              ],
              child: MaterialApp(
                theme: _theme(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(_realistic)),
                  child: child!,
                ),
                home: Scaffold(
                  body: Builder(
                    builder: (context) => TextButton(
                      onPressed: () => showNotificationsPopover(context),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          _expectNoTruncation(tester);
          expect(find.text('Notifications'), findsOneWidget);
          expect(find.text('View all notifications'), findsOneWidget);
        });
      }
    }
  });
}
