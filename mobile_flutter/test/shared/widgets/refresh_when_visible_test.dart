import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/shared/widgets/refresh_when_visible.dart';

void main() {
  testWidgets('refreshes on entry, interval and return; pauses when hidden',
      (tester) async {
    var calls = 0;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: RefreshWhenVisible(
        onRefresh: () async {
          calls++;
        },
        child: const Scaffold(body: Text('History')),
      ),
    ));
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: Text('Other page')),
    ));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 2);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(calls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 3);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 4);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 4);
  });

  testWidgets('slow requests cannot overlap and errors allow another attempt',
      (tester) async {
    var calls = 0;
    final first = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: RefreshWhenVisible(
      onRefresh: () {
        calls++;
        return calls == 1 ? first.future : Future.value();
      },
      child: const SizedBox(),
    )));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(calls, 1);
    first.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 30));
    expect(calls, 2);
    await tester.pumpWidget(const SizedBox());
  });
}
