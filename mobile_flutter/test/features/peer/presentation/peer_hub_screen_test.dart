import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/peer/application/peer_providers.dart';
import 'package:mobile_flutter/features/peer/data/peer_transfers_api.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_composer.dart';
import 'package:mobile_flutter/features/peer/presentation/peer_hub_screen.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';

const _ana = PeerUser(
  userId: 'u-2',
  firstName: 'Ana',
  lastName: 'Kovač',
  initials: 'AK',
  avatarColor: Color(0xFF27D7C2),
  maskedEmail: 'an***@x.io',
);

const _bo = PeerUser(
  userId: 'u-3',
  firstName: 'Bo',
  lastName: 'Lee',
  initials: 'BL',
  avatarColor: Color(0xFF7B6CF6),
);

final _requests = PeerRequests(
  received: [
    PeerPaymentRequest(
      id: 'r-1',
      sent: false,
      otherUser: _ana,
      amount: 42.5,
      currency: 'USD',
      note: 'Dinner',
      status: 'pending',
      createdAt: DateTime(2026, 9, 4, 8),
      expiresAt: DateTime(2026, 9, 11, 8),
    ),
  ],
  sent: [
    PeerPaymentRequest(
      id: 'r-2',
      sent: true,
      otherUser: _bo,
      amount: 10,
      currency: 'USDC',
      status: 'pending',
      createdAt: DateTime(2026, 9, 4, 8),
      expiresAt: DateTime(2026, 9, 11, 8),
    ),
  ],
);

final _recent = [
  PeerTransfer(
    id: 't-1',
    sent: true,
    otherUser: _bo,
    amount: 25,
    currency: 'USD',
    status: 'completed',
    fee: 0,
    createdAt: DateTime(2026, 9, 3, 8),
    note: 'Tickets',
  ),
  PeerTransfer(
    id: 't-2',
    sent: false,
    otherUser: _ana,
    amount: 8,
    currency: 'USDT',
    status: 'completed',
    fee: 0,
    createdAt: DateTime(2026, 9, 2, 8),
  ),
];

final _contacts = [
  PeerContact(id: 'c-1', user: _ana, addedAt: DateTime(2026, 9, 1)),
];

Widget _app(
    {required Size size,
    PeerComposerMode mode = PeerComposerMode.send,
    bool light = false}) {
  final themes = buildAppThemes(_branding);
  final theme = light ? themes.light : themes.dark;
  return ProviderScope(
    overrides: [
      peerRequestsProvider.overrideWith((ref) async => _requests),
      peerRecentProvider.overrideWith((ref) async => _recent),
      peerContactsProvider.overrideWith((ref) async => _contacts),
      peerTransfersEnabledProvider.overrideWith((ref) async => true),
      peerAvailableBalancesProvider.overrideWith((ref) async => {'USD': 120.0}),
      peerFeeInfoProvider.overrideWith((ref) async => _fee),
      hoppaWalletAssetsProvider.overrideWith((ref) async => const [_asset]),
      hoppaWalletAddressesProvider.overrideWith((ref) async => const [_asset]),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        theme: theme,
        darkTheme: theme,
        themeMode: light ? ThemeMode.light : ThemeMode.dark,
        home: PeerHubScreen(initialMode: mode),
      ),
    ),
  );
}

const _fee = PeerFeeInfo(
  freeTransfersPerDay: 10,
  transfersUsedToday: 2,
  freeTransfersRemaining: 8,
  feePercent: 1,
  feeAmount: 0,
  feeCurrency: 'USD',
  feeApplies: false,
  isRateLimited: false,
  rateLimitSecondsRemaining: 0,
  dailySendLimit: 50,
  sendsRemainingToday: 48,
  minAmount: 0.01,
  maxAmount: 1000000,
  currencies: ['USD', 'USDC', 'USDT'],
);

const _branding = AppBranding(
  appName: 'EXAMPLE',
  brandId: 'example',
  primarySeedHex: '7B6CF6',
  accentSeedHex: 'A78BFA',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'EXAMPLE',
);

const _asset = HoppaWalletAsset(
  symbol: 'USDT',
  name: 'Tether',
  network: 'TRON',
  amount: 10,
  fiatValue: 10,
  address: 'T-deposit-address',
  tint: Colors.green,
  walletId: 'wallet-1',
);

void main() {
  testWidgets('crypto action follows the current Send / Request selection',
      (tester) async {
    const size = Size(1280, 1000);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(size: size));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Request'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crypto wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Stablecoin'), findsOneWidget);
    expect(find.text('USDT'), findsWidgets);
    expect(find.text('USDC'), findsWidgets);
    await tester.tap(find.text('USDC').last);
    await tester.pumpAndSettle();
    expect(find.text('No USDC address yet'), findsOneWidget);
    Navigator.of(tester.element(find.text('Stablecoin'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crypto wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Send to an external wallet'), findsOneWidget);
    expect(find.text('Stablecoin'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('request route opens deposits immediately without a mode switch',
      (tester) async {
    const size = Size(1280, 1000);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(size: size, mode: PeerComposerMode.request));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crypto wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Stablecoin'), findsOneWidget);
    expect(find.text('Send to an external wallet'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final light in [false, true]) {
    testWidgets(
        'phone hub shows hero, requests with actions, contacts and recent (light=$light)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(size: const Size(390, 1400), light: light));
      await tester.pumpAndSettle();

      expect(find.text('Send & request'), findsOneWidget);
      expect(find.text('Instant transfers between members'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Request'), findsOneWidget);
      expect(find.text('Ana Kovač asks you'), findsOneWidget);
      expect(find.text(r'Pay $42.50'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.text('You asked Bo Lee'), findsOneWidget);
      expect(find.text('Cancel request'), findsOneWidget);
      expect(find.text('2 open'), findsOneWidget);
      expect(find.text('Contacts'), findsOneWidget);
      expect(find.text(r'-$25.00'), findsOneWidget);
      expect(find.text('+8.00 USDT'), findsOneWidget);
      expect(find.byType(PeerComposer), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'desktop hub embeds the composer beside the lists (light=$light)',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(_app(size: const Size(1280, 1000), light: light));
      await tester.pumpAndSettle();

      expect(find.byType(PeerComposer), findsOneWidget);
      expect(find.text('Who are you sending to?'), findsOneWidget);
      expect(find.text('Nickname, email or phone number'), findsOneWidget);
      expect(find.text('Ana Kovač asks you'), findsOneWidget);
      expect(find.text('Instant transfers between members'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
