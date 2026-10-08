import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/app/router/app_back_navigation.dart';

void main() {
  Future<GoRouter> mount(WidgetTester tester,
      {String initial = '/home', ValueChanged<bool>? onCanHandlePop}) async {
    final router = GoRouter(initialLocation: initial, routes: [
      ShellRoute(
        builder: (_, __, child) => AppBackNavigation(child: child),
        routes: [
          for (final path in ['/home', '/money', '/money/pay', '/profile'])
            GoRoute(
                path: path,
                builder: (_, state) => Scaffold(
                      body: Text(state.uri.toString()),
                    )),
          GoRoute(
              path: '/cards',
              builder: (_, __) => const Scaffold(body: Text('Cards')),
              routes: [
                GoRoute(
                    path: ':id',
                    builder: (_, __) =>
                        const Scaffold(body: Text('Card details')))
              ]),
        ],
      ),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(
      routerConfig: router,
      onNavigationNotification: onCanHandlePop == null
          ? null
          : (notification) {
              onCanHandlePop(notification.canHandlePop);
              return true;
            },
    ));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Android is told the shell can handle Back after go navigation',
      (tester) async {
    final notifications = <bool>[];
    final router = await mount(tester, onCanHandlePop: notifications.add);
    expect(notifications.last, isFalse);
    router.go('/money');
    await tester.pumpAndSettle();
    expect(notifications.last, isTrue,
        reason: 'Android must dispatch Back to Flutter rather than exit.');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/home');
    expect(notifications.last, isFalse,
        reason: 'At Home with no history the system can leave the app.');
  });

  testWidgets('Android back returns through pages reached with go',
      (tester) async {
    final router = await mount(tester);
    router.go('/money?currency=RON');
    await tester.pumpAndSettle();
    router.go('/money/pay?budgetId=main');
    await tester.pumpAndSettle();
    router.go('/profile');
    await tester.pumpAndSettle();
    for (final expected in [
      '/money/pay?budgetId=main',
      '/money?currency=RON',
      '/home'
    ]) {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(router.routerDelegate.state.uri.toString(), expected);
    }
  });

  testWidgets('Android back pops a pushed page before shell history',
      (tester) async {
    final router = await mount(tester);
    router.go('/money');
    await tester.pumpAndSettle();
    router.push('/profile');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/money');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/home');
  });

  testWidgets('Android back closes dialogs and respects pending actions',
      (tester) async {
    final router = await mount(tester);
    router.go('/money');
    await tester.pumpAndSettle();
    final canClose = ValueNotifier(false);
    addTearDown(canClose.dispose);
    showDialog<void>(
        context: tester.element(find.text('/money')),
        builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: canClose,
            builder: (_, value, __) => PopScope(
                canPop: value,
                child: const Dialog(child: Text('Conversion')))));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Conversion'), findsOneWidget);
    expect(router.routerDelegate.state.uri.path, '/money');
    canClose.value = true;
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Conversion'), findsNothing);
    expect(router.routerDelegate.state.uri.path, '/money');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/home');
  });

  testWidgets('nested deep link pops without reopening the child',
      (tester) async {
    final router = await mount(tester, initial: '/cards/card-1');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/cards');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/home');
    expect(
        await router.backButtonDispatcher.invokeCallback(Future.value(false)),
        isFalse);
  });

  testWidgets('back from a deep link returns to its parent then Home',
      (tester) async {
    final router = await mount(tester, initial: '/money/pay');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/money');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(router.routerDelegate.state.uri.path, '/home');
  });
}
