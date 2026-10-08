import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/widgets/refresh_action.dart';

void main() {
  testWidgets('refresh blocks repeat taps until the fresh data arrives',
      (tester) async {
    final pending = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RefreshAction(onRefresh: () {
      calls++;
      return pending.future;
    }))));
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed,
        isNotNull);
  });
  testWidgets('failed refresh shows feedback and allows retry', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RefreshAction(onRefresh: () async {
      calls++;
      if (calls == 1) throw Exception('Refresh failed');
    }))));
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    await tester.tap(find.byTooltip('Refresh'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
