import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/dashboard/domain/dashboard_models.dart';
import 'package:mobile_flutter/features/dashboard/presentation/example_activation_panel.dart';

HoppaDashboardSnapshot snapshot(
        {bool approved = true,
        bool referrals = true,
        List<PaymentCard> cards = const []}) =>
    HoppaDashboardSnapshot(
      accountId: 'member-1',
      customerName: 'Member',
      accounts: const [],
      holdings: const [],
      activities: const [],
      cards: cards,
      onboardingProgress: 1,
      marketSentiment: '',
      requiresKyc: !approved,
      accountReady: approved,
      exchangeEnabled: true,
      outflowsEnabled: true,
      referralsEnabled: referrals,
      vouchersEnabled: false,
      isBusinessAccount: false,
      portfolioEstimate: null,
    );
PaymentCard card(CardStatus status, {bool virtual = false}) => PaymentCard(
      id: '1',
      label: 'Card',
      last4: '1234',
      network: 'Visa',
      currency: 'USD',
      status: status,
      balance: const Money(currency: 'USD', minorUnits: 0),
      spendThisMonth: const Money(currency: 'USD', minorUnits: 0),
      limit: const Money(currency: 'USD', minorUnits: 10000),
      virtual: virtual,
    );
void main() {
  test('shared steps follow KYC, funding history and card state', () {
    expect(activationSteps(snapshot(approved: false), false), isEmpty);
    expect(activationSteps(snapshot(), false).map((s) => s.action),
        ['deposit', 'order']);
    expect(activationSteps(snapshot(), true).map((s) => s.action), ['order']);
    expect(
        activationSteps(snapshot(cards: [card(CardStatus.pending)]), true)
            .single
            .title,
        'Activate after your card arrives');
    expect(
        activationSteps(
                snapshot(cards: [card(CardStatus.pending, virtual: true)]),
                true)
            .single
            .title,
        'Your card is being prepared');
    for (final status in [CardStatus.active, CardStatus.frozen]) {
      expect(activationSteps(snapshot(cards: [card(status)]), false), isEmpty);
    }
    expect(
        activationSteps(snapshot(cards: [card(CardStatus.cancelled)]), true)
            .single
            .action,
        'order');
  });

  for (final width in [320.0, 390.0, 1440.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('introduction and remaining checklist fit $width $brightness',
          (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        var claimed = false;
        final dio = Dio()
          ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
            if (request.method == 'GET') {
              handler.resolve(Response(requestOptions: request, data: {
                'data': [],
                'pagination': {'hasNext': false}
              }));
              return;
            }
            final show = request.data['claimIntroduction'] == true && !claimed;
            if (show) claimed = true;
            handler.resolve(Response(requestOptions: request, data: {
              'showIntroduction': show,
              'hasCompletedDeposit': false
            }));
          }));
        await tester.pumpWidget(ProviderScope(
            overrides: [dioProvider.overrideWithValue(dio)],
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                  body: ListView(children: [
                ExampleActivationPanel(snapshot: snapshot()),
                const ExampleReferralTeaser(enabled: true),
              ])),
            )));
        await tester.pumpAndSettle();
        expect(find.text('Your account is approved'), findsOneWidget);
        expect(find.text('Maybe later'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Maybe later'));
        await tester.pumpAndSettle();
        expect(find.text('Your account is approved'), findsNothing);
        expect(find.text('Make your first deposit'), findsOneWidget);
        expect(find.text('Order your card'), findsOneWidget);
        expect(find.text('Invite a friend & earn'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
      'failed progress lookup stays quiet and retries after approval refresh',
      (tester) async {
    var approved = false;
    var failing = true;
    var requests = 0;
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        requests++;
        if (failing) {
          handler.reject(DioException(requestOptions: request));
          return;
        }
        handler.resolve(Response(
            requestOptions: request,
            data: {'showIntroduction': false, 'hasCompletedDeposit': true}));
      }));
    late StateSetter refresh;
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(home: Scaffold(
          body: StatefulBuilder(builder: (_, setState) {
            refresh = setState;
            return ExampleActivationPanel(
                snapshot: snapshot(approved: approved));
          }),
        ))));
    await tester.pumpAndSettle();
    expect(requests, 0);
    refresh(() => approved = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Finish setting up'), findsNothing);
    refresh(() => failing = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(find.text('Order your card'), findsOneWidget);
    expect(find.text('Make your first deposit'), findsNothing);
    expect(find.text('Your account is approved'), findsNothing);
  });
  testWidgets(
      'referral teaser opens existing share flow and respects eligibility',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const Scaffold(body: ExampleReferralTeaser(enabled: true))),
      GoRoute(
          path: '/rewards',
          builder: (_, state) => Scaffold(
              body: Text('rewards ${state.uri.queryParameters['tab']}'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Invite now'));
    await tester.pumpAndSettle();
    expect(find.text('rewards share'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ExampleReferralTeaser(enabled: false))));
    expect(find.text('Invite now'), findsNothing);
  });
}
