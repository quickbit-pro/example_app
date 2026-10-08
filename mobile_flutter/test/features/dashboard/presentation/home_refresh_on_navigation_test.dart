import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/router/app_back_navigation.dart';
import 'package:mobile_flutter/features/dashboard/data/dashboard_providers.dart';
import 'package:mobile_flutter/features/dashboard/presentation/home_refresh_on_navigation.dart';

void main() {
  Future<GoRouter> mount(WidgetTester tester, Future<void> Function() refresh,
      {String initial = '/home'}) async {
    final router = GoRouter(initialLocation: initial, routes: [
      ShellRoute(
        builder: (_, __, child) => HomeRefreshOnNavigation(
          child: AppBackNavigation(child: child),
        ),
        routes: [
          for (final path in ['/home', '/rewards', '/cards'])
            GoRoute(
              path: path,
              builder: (_, __) => Scaffold(body: Text(path)),
            ),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [refreshHoppaDashboardProvider.overrideWithValue(refresh)],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('PWA resume refreshes Home once, but focus alone does not',
      (tester) async {
    var calls = 0;
    await mount(tester, () async => calls++);
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(calls, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('resuming a different page does not fetch Home', (tester) async {
    var calls = 0;
    final router = await mount(tester, () async => calls++, initial: '/cards');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(calls, 0);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('refreshes on first Home visit and when returning from Rewards',
      (tester) async {
    var calls = 0;
    final router = await mount(tester, () async => calls++);
    expect(calls, 1);
    router.go('/rewards');
    await tester.pumpAndSettle();
    expect(calls, 1);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(calls, 2);
    router.refresh();
    await tester.pumpAndSettle();
    expect(calls, 2, reason: 'Rebuilds on Home must not refetch in a loop.');
  });

  for (final pushed in [false, true]) {
    testWidgets('Android Back from Cards refreshes Home, push=$pushed',
        (tester) async {
      var calls = 0;
      final router = await mount(tester, () async => calls++);
      if (pushed) {
        router.push('/cards');
      } else {
        router.go('/cards');
      }
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routerDelegate.state.uri.path, '/home');
      expect(calls, 2);
    });
  }

  testWidgets('does not fetch Home on other pages or when closing a dialog',
      (tester) async {
    var calls = 0;
    final router =
        await mount(tester, () async => calls++, initial: '/rewards');
    expect(calls, 0);
    router.go('/home');
    await tester.pumpAndSettle();
    expect(calls, 1);
    showDialog<void>(
      context: tester.element(find.text('/home')),
      builder: (_) => const AlertDialog(content: Text('Dialog')),
    );
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(calls, 1);
  });

  testWidgets('refresh failure does not prevent navigation or a later retry',
      (tester) async {
    var calls = 0;
    final router = await mount(tester, () async {
      calls++;
      throw StateError('offline');
    });
    expect(tester.takeException(), isNull);
    router.go('/cards');
    await tester.pumpAndSettle();
    router.go('/home');
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
