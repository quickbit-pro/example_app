import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_flutter/features/money/presentation/accounts_hub_header.dart';
import 'package:mobile_flutter/features/money/presentation/money_screen.dart';

void main() {
  testWidgets('accounts hub shows Money, Crypto, and Exchange', (tester) async {
    final router = GoRouter(
      initialLocation: '/money',
      routes: [
        GoRoute(
          path: '/money',
          builder: (_, __) => const _HubHarness(),
        ),
        GoRoute(
          path: '/wallets/addresses',
          builder: (_, __) => const Text('Deposit route'),
        ),
        GoRoute(
          path: '/wallets/assets',
          builder: (_, __) => const Text('Crypto route'),
        ),
        GoRoute(
          path: '/wallets/exchange',
          builder: (_, __) => const Text('Exchange route'),
        ),
        GoRoute(
          path: '/money/pay',
          builder: (_, __) => const Text('Pay route'),
        ),
        GoRoute(
          path: '/crypto/buy',
          builder: (_, __) => const Text('Buy route'),
        ),
        GoRoute(
          path: '/payments',
          builder: (_, __) => const Text('Funding route'),
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    expect(find.text('All'), findsNothing);
    expect(find.text('Money'), findsOneWidget);
    expect(find.text('Crypto'), findsOneWidget);
    expect(find.text('Deposit'), findsNothing);
    expect(find.text('Exchange'), findsOneWidget);
    expect(find.text('Quick actions'), findsNothing);
    expect(find.text('Buy crypto'), findsNothing);
  });

  testWidgets('Equals selection uses the secondary white-label color',
      (tester) async {
    const secondary = Color(0xFF00BFA6);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF7C5CFF),
    ).copyWith(secondary: secondary, onSecondary: Colors.black);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme),
        home: const DefaultTabController(
          length: 3,
          child: Scaffold(body: EqualsMoneyTabBar()),
        ),
      ),
    );

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    final indicator = tabBar.indicator! as BoxDecoration;
    expect(indicator.color, secondary);
    expect(tabBar.labelColor, Colors.black);
  });
}

class _HubHarness extends StatelessWidget {
  const _HubHarness();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: AccountsHubHeader(
            selected: AccountsHubSection.money,
            showCrypto: true,
            showExchange: true,
          ),
        ),
      );
}
