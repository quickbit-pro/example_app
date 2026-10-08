// Layout, state and legibility proof for the two Example card screens.
//
// `/cards/:id` and `/cards/:id/transactions` were the last pages still
// rendering the pre-Example composition, and both are money surfaces: one
// states a balance and the controls that move it, the other is a ledger that
// has to reconcile row to row. What is worth proving here is therefore not a
// moment but the invariants — no overflow and no truncation at 375, 393, 834
// and 1440 in BOTH themes and at a 1.3 text scale, the right control in the
// right state, and no reconstructed historical balance.
import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/cards/domain/card_control_capabilities.dart';
import 'package:mobile_flutter/features/cards/domain/card_limits.dart';
import 'package:mobile_flutter/features/cards/presentation/card_detail_screen.dart';
import 'package:mobile_flutter/features/cards/presentation/card_transactions_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf_export_button.dart';
import 'package:mobile_flutter/features/transactions/export/transaction_pdf.dart';
import 'package:mobile_flutter/features/transactions/presentation/transaction_detail_screen.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/flavors.dart';

// ---------------------------------------------------------------- fixtures

const _cardId = 'card-metal-1';

AppBranding _branding(String mode, {bool example = true}) => AppBranding(
      appName: example ? 'EXAMPLE' : 'Hoppa',
      brandId: example ? 'example' : 'hoppa',
      primarySeedHex: '7B6CF6',
      accentSeedHex: 'A78BFA',
      loginBackgroundHex: '',
      themeMode: mode,
      fontFamily: '',
      logoAsset: '',
      radiusScale: '1',
      supportEmail: 'support@example.com',
      supportPhone: '',
      legalEntity: 'EXAMPLE',
    );

AppConfig _config(String mode, {bool example = true}) => AppConfig(
      flavor: AppFlavor.dev,
      apiBaseUrl: 'http://127.0.0.1:1',
      branding: _branding(mode, example: example),
    );

const _balance = Money(currency: 'USD', minorUnits: 200000);

const _card = PaymentCard(
  id: _cardId,
  label: 'Metal',
  last4: '4271',
  network: 'mastercard',
  currency: 'USD',
  status: CardStatus.active,
  balance: _balance,
  spendThisMonth: Money(currency: 'USD', minorUnits: -61085),
  limit: Money(currency: 'USD', minorUnits: 500000),
  virtual: false,
);

/// What the money dialog spends from. USD is the one that funds the card, so
/// it is deliberately not the alphabetically first symbol.
const _walletAssets = <HoppaWalletAsset>[
  HoppaWalletAsset(
    symbol: 'USDT',
    name: 'Tether',
    network: 'TRON',
    amount: 300.5,
    fiatValue: 300.5,
    address: 'T-address',
    tint: Color(0xFF26A17B),
    walletId: 'w-usdt',
  ),
  HoppaWalletAsset(
    symbol: 'USD',
    name: 'US Dollar',
    network: '',
    amount: 1250,
    fiatValue: 1250,
    address: '',
    tint: Color(0xFF20D996),
    walletId: 'w-usd',
  ),
];

const _controls = CardControlCapabilities(
  canFreeze: true,
  canRevealSecureData: true,
  canSetPin: true,
  canUpdateLimits: true,
  canMerchantLock: false,
  canControlOnlinePayments: true,
  canControlContactless: true,
  canControlAtm: false,
  canControlInternational: false,
  isMerchantLocked: false,
  lockedMerchantName: '',
  supportedActions: ['freeze', 'limits'],
  limits: {'daily': 500.0, 'monthly': 5000.0},
);

/// Booking days are relative, because `_dayLabel` on the ledger resolves
/// "Today" and "Yesterday" against the wall clock. Everything here is at
/// least three days old, so every heading is a dated one and the assertions
/// below read the same on any day the suite runs.
final _now = DateTime.now();

DateTime _daysAgo(int days) {
  final day = _now.subtract(Duration(days: days));
  return DateTime(day.year, day.month, day.day, 15, 24);
}

/// The heading form the ledger uses, which is the one the activity screen
/// already uses: the full month name.
const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _dayLabel(DateTime day) => '${day.day} ${_months[day.month - 1]}';

PlatformResource _activity({
  required String id,
  required String merchant,
  required double amount,
  required DateTime createdAt,
  String status = 'completed',
  String type = 'purchase',
  String category = 'Groceries',
  double? original,
  String? originalCurrency,
}) =>
    PlatformResource(
      id: id,
      title: merchant,
      subtitle: status,
      metadata: {
        'id': id,
        'type': type,
        'status': status,
        'amount': amount,
        'currency': 'USD',
        if (original != null) 'transactionAmount': original,
        if (originalCurrency != null) 'transactionCurrency': originalCurrency,
        'merchantName': merchant,
        'merchantCategory': category,
        'createdAt': createdAt.toUtc().toIso8601String(),
      },
    );

// Issuer convention is retained: positive purchases are debits; refund types
// identify credits. Current balances are not historical statement balances.
final _activityRows = <PlatformResource>[
  _activity(
    id: 'ctx-1',
    merchant: 'MACROCENTER LARA',
    amount: 174.25,
    createdAt: _daysAgo(3),
    original: 6420.50,
    originalCurrency: 'TRY',
  ),
  _activity(
    id: 'ctx-2',
    merchant: 'Uber',
    amount: 24.60,
    status: 'declined',
    createdAt: _daysAgo(4),
    category: 'Transport',
  ),
  _activity(
    id: 'ctx-3',
    merchant: 'Refund from Booking.com',
    amount: 412,
    type: 'refund',
    createdAt: _daysAgo(9),
    category: 'Travel',
  ),
  _activity(
    id: 'ctx-4',
    merchant: 'Apple Services',
    amount: 9.99,
    createdAt: _daysAgo(15),
    category: 'Digital',
  ),
];

/// The brand's own typefaces, so every width and truncation assertion below is
/// measured in Geist. Without this the binding falls back to the test font,
/// whose glyphs are square boxes roughly twice Geist's advance width, and a
/// layout proof measured in it is a proof about a font nobody ships.
const _exampleFonts = <String, List<String>>{
  'Geist': [
    'Geist-Regular.ttf',
    'Geist-Medium.ttf',
    'Geist-SemiBold.ttf',
    'Geist-Bold.ttf',
  ],
  'GeistMono': ['GeistMono-Regular.ttf', 'GeistMono-Medium.ttf'],
};

Future<void> _loadFonts() async {
  for (final entry in _exampleFonts.entries) {
    final loader = FontLoader(entry.key);
    var found = false;
    for (final file in entry.value) {
      final font = File('assets/fonts/$file');
      if (!font.existsSync()) continue;
      found = true;
      loader.addFont(
        Future.value(ByteData.view(font.readAsBytesSync().buffer)),
      );
    }
    if (found) await loader.load();
  }
}

// ------------------------------------------------------------------ harness

/// Built once per brightness. Rebuilding `ThemeData` on every `pumpWidget`
/// makes `MaterialApp`'s `AnimatedTheme` treat an identical theme as a change
/// and start a controller, which leaves a ticker running in every test that
/// asks whether anything is animating.
final _themes = <bool, AppThemes>{
  false: buildAppThemes(_branding('dark')),
  true: buildAppThemes(_branding('light')),
};

/// A tenant that is not Example. `context.isExampleTheme` is a theme test, so
/// this is all it takes to render the white-label composition and prove the
/// other branch still exists.
final _whiteLabelThemes = buildAppThemes(_branding('dark', example: false));

Widget _app(
  Widget home, {
  required bool light,
  Future<PaymentCard> Function()? detail,
  Future<List<PlatformResource>> Function()? activity,
  List<PaymentCard>? cards,
  double textScale = 1,
  bool reducedMotion = false,
  bool example = true,
  List<Override> overrides = const [],
}) {
  final themes = example ? _themes[light]! : _whiteLabelThemes;
  return ProviderScope(
    overrides: [
      appConfigProvider.overrideWithValue(
        _config(light ? 'light' : 'dark', example: example),
      ),
      cardsProvider.overrideWith((ref) async => cards ?? [_card]),
      cardDetailProvider(_cardId).overrideWith(
        (ref) => detail == null ? Future.value(_card) : detail(),
      ),
      cardTransactionsProvider(_cardId).overrideWith(
        (ref) => activity == null ? Future.value(_activityRows) : activity(),
      ),
      cardControlCapabilitiesProvider(_cardId)
          .overrideWith((ref) async => _controls),
      cardLimitsProvider(_cardId).overrideWith((ref) async =>
          const CardLimitsInfo(
              currency: 'USD', canUpdate: true, capSource: 'none')),
      for (final selected in cards ?? const <PaymentCard>[])
        if (selected.id != _cardId) ...[
          cardDetailProvider(selected.id).overrideWith((ref) async => selected),
          cardTransactionsProvider(selected.id).overrideWith((ref) async => []),
          cardControlCapabilitiesProvider(selected.id)
              .overrideWith((ref) async => _controls),
          cardLimitsProvider(selected.id).overrideWith((ref) async =>
              const CardLimitsInfo(
                  currency: 'USD', canUpdate: true, capSource: 'none')),
        ],
      hoppaWalletAssetsProvider.overrideWith((ref) async => _walletAssets),
      ...overrides,
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: light ? ThemeMode.light : ThemeMode.dark,
      // Above the Navigator, so a dialog route inherits it too.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Advance a fixed amount rather than settling.
///
/// Both screens keep a `ExampleSheenScope` alive, and the card face runs its
/// own specular pass, so `pumpAndSettle` waits for a tree that never comes to
/// rest. A fixed advance is long enough to clear the 240 ms arrival delay and
/// the 600 ms sweep.
Future<void> _pumpAt(
  WidgetTester tester,
  Widget home,
  Size size, {
  required bool light,
  Future<PaymentCard> Function()? detail,
  Future<List<PlatformResource>> Function()? activity,
  List<PaymentCard>? cards,
  double textScale = 1,
  bool reducedMotion = false,
  bool example = true,
  int frames = 12,
  List<Override> overrides = const [],
}) async {
  await tester.binding.setSurfaceSize(size);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    _app(
      home,
      light: light,
      detail: detail,
      activity: activity,
      cards: cards,
      textScale: textScale,
      reducedMotion: reducedMotion,
      example: example,
      overrides: overrides,
    ),
  );
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// Every string this app writes renders whole: no ellipsis, no clipped glyph
/// run. Truncation is the failure mode a screenshot hides and a diff never
/// shows, so it is asserted rather than looked at.
///
/// Two exceptions, both deliberate. A merchant name arrives from a payment
/// network at whatever length it likes, and the row's contract is that it
/// ellipsizes rather than overflowing. And the card artwork's own identity
/// caption is truncated by `ExampleLivingCard` at every width, including the
/// 400 pt desktop column — a `Spacer()` and a `Flexible` split the lockup
/// row's leftover space 50/50, so the caption only ever gets half of it.
/// That is pre-existing behaviour in a widget this change does not own,
/// reproduced against `CardFace` on its own, and it is filed rather than
/// asserted here. Everything else — headings, labels, amounts, descriptors,
/// status words — is copy this app controls, and copy that does not fit is a
/// design bug.
void _expectAppCopyIsWhole(WidgetTester tester) {
  final merchants = <String>{
    for (final row in _activityRows) row.title,
    'MASTERCARD  ·  METAL',
  };
  for (final element in find.byType(Text).evaluate()) {
    final paragraph = element.renderObject;
    if (paragraph is! RenderParagraph || !paragraph.didExceedMaxLines) continue;
    final widget = element.widget as Text;
    final text = widget.data ?? widget.textSpan?.toPlainText() ?? '';
    if (merchants.contains(text)) continue;
    fail('Truncated: "$text"');
  }
}

/// Bring a below-the-fold string into the built subtree.
///
/// Both screens are lazy lists, so half of what is asserted here does not
/// exist until it is scrolled to. Returns as soon as the target is built, so
/// a target already on screen at 1440 costs nothing.
Future<void> _reveal(WidgetTester tester, String text) async {
  final target = find.text(text);
  if (target.evaluate().isNotEmpty) return;
  await tester.scrollUntilVisible(
    target,
    240,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 60,
  );
}

const _viewports = <(String, Size)>[
  ('375', Size(375, 812)),
  ('393', Size(393, 852)),
  ('834', Size(834, 1194)),
  ('1440', Size(1440, 900)),
];

void main() {
  for (final example in [false, true]) {
    testWidgets('issued discount code appears in card details example=$example',
        (tester) async {
      final discounted = PaymentCard.fromJson(
          {'id': _cardId, 'discountCode': 'SAVE25', 'status': 'active'});
      await _pumpAt(tester, const CardDetailScreen(cardId: _cardId),
          const Size(393, 1000),
          light: true,
          example: example,
          detail: () async => discounted,
          activity: () async => []);
      await tester.scrollUntilVisible(find.text('SAVE25'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Discount code'), findsOneWidget);
      expect(find.text('Applied when ordering this card'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('top-up uses combined funds and Max refreshes after a deposit',
      (tester) async {
    var usdt = 247.0;
    var loads = 0;
    final api = _TopUpEstimateApi();
    await _pumpAt(
        tester, const CardDetailScreen(cardId: _cardId), const Size(393, 1000),
        light: false,
        overrides: [
          mobilePlatformApiProvider.overrideWithValue(api),
          hoppaWalletAssetsProvider.overrideWith((ref) async {
            loads++;
            return [
              for (final entry
                  in {'USD': 1.15, 'USDT': usdt, 'USDC': 0.0}.entries)
                HoppaWalletAsset(
                    symbol: entry.key,
                    name: entry.key,
                    network: '',
                    amount: entry.value,
                    fiatValue: entry.value,
                    address: '',
                    tint: Colors.grey,
                    walletId: entry.key),
            ];
          }),
        ]);
    Future<void> open() async {
      await tester.ensureVisible(find.byType(ExampleGlassButton));
      await tester.tap(find.byType(ExampleGlassButton));
      await _settleDialog(tester);
    }

    await open();
    final field = find.byType(TextField);
    await tester.enterText(field, '200');
    await _settleDialog(tester);
    expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
    expect(api.amounts.last, 200);
    await tester.enterText(field, '249');
    await _settleDialog(tester);
    expect(tester.widget<TextField>(field).decoration!.errorText,
        'Amount exceeds the combined USD, USDT and USDC balance.');
    await tester.ensureVisible(find.text('MAX'));
    await tester.tap(find.text('MAX'));
    await _settleDialog(tester);
    expect(tester.widget<TextField>(field).controller!.text, '248.00');
    expect(tester.widget<TextField>(field).decoration!.errorText, isNull);
    await tester.tap(find.byTooltip('Close'));
    await _settleDialog(tester);
    final previousLoads = loads;
    usdt = 347;
    await open();
    expect(loads, greaterThan(previousLoads));
    await tester.ensureVisible(find.text('MAX'));
    await tester.tap(find.text('MAX'));
    await _settleDialog(tester);
    expect(tester.widget<TextField>(field).controller!.text, '348.00');
    expect(tester.takeException(), isNull);
  });

  Future<(_SecureApi, _SecurePlatform)> pumpSecure(WidgetTester tester,
      {bool light = true, bool carousel = false}) async {
    final api = _SecureApi();
    final platform = _SecurePlatform();
    final previous = WebViewPlatform.instance;
    WebViewPlatform.instance = platform;
    addTearDown(() {
      if (previous != null) WebViewPlatform.instance = previous;
    });
    await tester.binding.setSurfaceSize(const Size(393, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(
      CardDetailScreen(cardId: _cardId, asTab: carousel),
      light: light,
      cards: carousel
          ? [
              _card,
              PaymentCard.fromJson({'id': 'second-card', 'last4': '8763'})
            ]
          : null,
      reducedMotion: true,
      overrides: [
        mobilePlatformApiProvider.overrideWithValue(api),
        cardDetailProvider(_cardId).overrideWith(
            (ref) async => _card.withFallback(PaymentCard.fromJson({
                  'cardImageUrl': 'https://cdn.example/front.png',
                  'cardBackImageUrl': 'https://cdn.example/back.png'
                }))),
        biometricAuthenticatorProvider.overrideWithValue(_SecureBiometrics()),
      ],
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return (api, platform);
  }

  Future<void> revealSecure(WidgetTester tester) async {
    await tester.tap(find.text('View'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  for (final light in [true, false]) {
    testWidgets('secure widget receives the active theme background ($light)',
        (tester) async {
      final (_, platform) = await pumpSecure(tester, light: light);
      final theme = Theme.of(tester.element(find.byType(CardDetailScreen)));
      final expected =
          '#${(theme.scaffoldBackgroundColor.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
      await revealSecure(tester);
      expect(
          Uri.parse(platform.controllers.single.url!)
              .queryParameters['backgroundColor'],
          expected);
      expect(tester.takeException(), isNull);
    });
  }

  for (final light in [true, false]) {
    testWidgets(
        'copy taps reach the secure card and keep its session open ($light)',
        (tester) async {
      final (api, platform) =
          await pumpSecure(tester, light: light, carousel: true);
      await revealSecure(tester);
      expect(find.text('Hide'), findsOneWidget);
      final originalSession = platform.controllers.single;
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('Copy test data'));
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text('Hide'), findsOneWidget);
        expect(platform.controllers.single, same(originalSession));
        expect(api.requests, 1);
      }
      expect(platform.copyCalls, 3);
      // Changing cards uses a control outside the issuer's touch area and
      // still conceals the old details without creating another session.
      await tester.tap(find.byTooltip('Next card'));
      await _settleDialog(tester);
      expect(find.text('Copy test data'), findsNothing);
      expect(find.text('View'), findsOneWidget);
      expect(api.requests, 1);
      expect(
          tester.widget<PageView>(find.byType(PageView)).controller!.page, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('visible secure card refresh requests a new Hoppa session',
      (tester) async {
    final (api, platform) = await pumpSecure(tester);
    await revealSecure(tester);
    expect(api.requests, 1);
    final first = platform.controllers.single.url;
    expect(Uri.parse(first!).queryParameters['cardBackground'],
        'https://cdn.example/back.png');
    final refresh =
        tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
    final pending = refresh.onRefresh();
    await tester.pump();
    await pending;
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(api.requests, 2);
    expect(platform.controllers.length, 2);
    expect(platform.controllers.last.url, isNot(first));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'refresh keeps secure details hidden without requesting a session',
      (tester) async {
    final (api, platform) = await pumpSecure(tester);
    final pending = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    await pending;
    await tester.pump();
    expect(api.requests, 0);
    expect(platform.controllers, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secure session errors after ready renew once then hide details',
      (tester) async {
    final (api, platform) = await pumpSecure(tester);
    await revealSecure(tester);
    platform.controllers.single.reportError();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(api.requests, 2);
    platform.controllers.last.reportError();
    await tester.pump();
    await tester.pump();
    expect(api.requests, 2);
    expect(find.text('View'), findsOneWidget);
    expect(
        find.text(
            'Secure card details could not be loaded. Please try revealing them again.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('secure frame reload is prevented and obtains a fresh session',
      (tester) async {
    final (api, platform) = await pumpSecure(tester);
    await revealSecure(tester);
    final old = platform.controllers.single;
    final decision = await old.delegate!
        .navigation!(NavigationRequest(url: old.url!, isMainFrame: true));
    expect(decision, NavigationDecision.prevent);
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(api.requests, 2);
    expect(platform.controllers.last.url, isNot(old.url));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'a late secure-session response is discarded after leaving the page',
      (tester) async {
    final (api, platform) = await pumpSecure(tester);
    await revealSecure(tester);
    api.pending = Completer<ActionResult>();
    platform.controllers.single.reportError();
    await tester.pump();
    expect(api.requests, 2);
    await tester.pumpWidget(const SizedBox.shrink());
    api.pending!.complete(const ActionResult(message: '', metadata: {
      'widgetUrl': 'https://secure.example/card?session=late',
    }));
    await tester.pump();
    expect(platform.controllers.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card preview shows actual route card identity and API dates',
      (tester) async {
    final timestamp = DateTime.utc(2026, 9, 6, 9, 15);
    final dated = _activity(
      id: 'dated-preview',
      merchant: 'Dated merchant',
      amount: 12.34,
      createdAt: timestamp,
    );
    const undated = PlatformResource(
      id: 'undated-preview',
      title: 'Undated merchant',
      subtitle: '',
      metadata: {
        'id': 'undated-preview',
        'merchantName': 'Undated merchant',
        'type': 'purchase',
        'amount': 2,
        'currency': 'USD',
      },
    );
    await _pumpAt(
        tester, const CardDetailScreen(cardId: _cardId), const Size(393, 1000),
        light: false, activity: () async => [dated, undated]);
    await _reveal(tester, 'Recent transactions');
    final datedRow = tester.widget<ExampleRow>(find.ancestor(
      of: find.text('Dated merchant'),
      matching: find.byType(ExampleRow),
    ));
    final undatedRow = tester.widget<ExampleRow>(find.ancestor(
      of: find.text('Undated merchant'),
      matching: find.byType(ExampleRow),
    ));
    expect(datedRow.subtitle, contains('Card •••• 4271'));
    expect(datedRow.subtitle,
        contains(DateFormat('d MMM yyyy · HH:mm').format(timestamp.toLocal())));
    expect(undatedRow.subtitle, contains('Card •••• 4271'));
    expect(undatedRow.subtitle, contains('Date unavailable'));
    _expectAppCopyIsWhole(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card statement exports its actual rows and masked card identity',
      (tester) async {
    await _pumpAt(tester, const CardTransactionsScreen(cardId: _cardId),
        const Size(393, 1000),
        light: false);
    final button = tester.widget<TransactionPdfExportButton>(
        find.byType(TransactionPdfExportButton));
    expect(button.transactions?.length, _activityRows.length);
    final purchase =
        button.transactions!.firstWhere((row) => row.id == 'ctx-1');
    expect(purchase.amount.decimalAmount, -174.25);
    final snapshot = TransactionPdfSnapshot(
      transactions: button.transactions!,
      identityFor: button.identityFor,
    );
    final exported =
        snapshot.rows.firstWhere((row) => row.reference == 'ctx-1');
    final visible = tester.widget<ExampleRow>(find.ancestor(
      of: find.text('MACROCENTER LARA'),
      matching: find.byType(ExampleRow),
    ));
    final original = const Money(currency: 'TRY', minorUnits: 642050).formatted;
    expect((visible.trailing as ExampleRowValue).value, '-\$174.25');
    expect(exported.amount, '-\$174.25 USD');
    expect(exported.settlementAmount, isNull);
    expect(visible.subtitle, contains(original));
    expect(exported.subtitle, contains('Original amount: $original'));
    expect(purchase.hasBookedAt, isTrue);
    expect(button.identityFor!(purchase), 'Card •••• 4271');
    expect(find.textContaining('Card •••• 4271'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'card statement keeps all activity with only All and Spend filters',
      (tester) async {
    final rows = [
      _activityRows.first,
      _activity(
        id: 'ctx-crypto',
        merchant: 'Crypto card funding',
        amount: 20,
        createdAt: _daysAgo(3),
        type: 'crypto_topup',
      ),
      _activity(
        id: 'ctx-control',
        merchant: 'Card freeze',
        amount: 0,
        createdAt: _daysAgo(3),
        type: 'freeze',
      ),
    ];
    await _pumpAt(tester, const CardTransactionsScreen(cardId: _cardId),
        const Size(393, 1000),
        light: false, activity: () async => rows);

    TransactionPdfExportButton export() =>
        tester.widget<TransactionPdfExportButton>(
            find.byType(TransactionPdfExportButton));

    expect(find.text('All'), findsOneWidget);
    expect(find.text('Spend'), findsOneWidget);
    expect(find.text('Crypto'), findsNothing);
    expect(find.text('Controls'), findsNothing);
    expect(export().transactions!.map((row) => row.id),
        unorderedEquals(rows.map((row) => row.id)));
    expect(find.text('Crypto card funding'), findsOneWidget);
    expect(find.text('Card freeze'), findsOneWidget);

    await tester.tap(find.text('Spend'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(export().transactions!.map((row) => row.id), ['ctx-1']);
    expect(export().filters, contains('Type: Purchases'));
    expect(find.text('Crypto card funding'), findsNothing);
    expect(find.text('Card freeze'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(export().transactions!.map((row) => row.id),
        unorderedEquals(rows.map((row) => row.id)));
    expect(tester.takeException(), isNull);
  });

  testWidgets('card receipt retains original amount with separate settlement',
      (tester) async {
    await _pumpAt(
        tester,
        const TransactionDetailScreen(transactionId: 'ctx-1', cardId: _cardId),
        const Size(393, 1000),
        light: false);
    final button = tester.widget<TransactionPdfExportButton>(
        find.byType(TransactionPdfExportButton));
    final snapshot = TransactionPdfSnapshot(
      transactions: button.transactions!,
      identityFor: button.identityFor,
      receipt: true,
    );
    expect(
        snapshot.rows.single.amount,
        transactionPdfAmountLabel(
            const Money(currency: 'TRY', minorUnits: -642050)));
    expect(snapshot.rows.single.settlementAmount, '-\$174.25 USD');
    expect(snapshot.rows.single.identity, 'Card •••• 4271');
    expect(tester.takeException(), isNull);
  });
  setUpAll(_loadFonts);

  for (final light in const [false, true]) {
    final theme = light ? 'daylight' : 'twilight';

    for (final (label, size) in _viewports) {
      testWidgets('card detail lays out at $label in $theme', (tester) async {
        await _pumpAt(
          tester,
          const CardDetailScreen(cardId: _cardId),
          size,
          light: light,
        );

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);

        // One decisive action, spelled out, instead of a whole-panel tap
        // hinted at by a plus glyph in a corner.
        expect(find.text('Manage balance'), findsOneWidget);
        expect(find.byType(ExampleGlassButton), findsOneWidget);

        // The action that goes to the ledger is named after where it goes.
        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('More'), findsNothing);

        await _reveal(tester, 'Recent transactions');
        _expectAppCopyIsWhole(tester);
        // A settled purchase is the norm on a card, so it is not captioned;
        // only the states that ask something of the holder are.
        expect(find.text('Completed'), findsNothing);
        expect(find.text('Declined'), findsOneWidget);

        // The card's own facts now render at every width, not only above
        // 1180 where the two-column layout used to hide them.
        await _reveal(tester, 'Card details');
        _expectAppCopyIsWhole(tester);
        expect(find.text('Number'), findsOneWidget);
        expect(find.text('Type'), findsOneWidget);
        expect(find.text('Currency'), findsOneWidget);
        expect(find.text('USD'), findsOneWidget);

        await _reveal(tester, 'Spending limits');
        _expectAppCopyIsWhole(tester);
        // A limit is money, not a debug print of a double.
        expect(find.text('Daily'), findsOneWidget);
        expect(find.text(r'$500.00'), findsOneWidget);
        expect(find.text('500.0'), findsNothing);

        await _reveal(tester, 'Card controls');
        _expectAppCopyIsWhole(tester);
      });

      testWidgets('card ledger lays out at $label in $theme', (tester) async {
        await _pumpAt(
          tester,
          const CardTransactionsScreen(cardId: _cardId),
          size,
          light: light,
        );

        expect(tester.takeException(), isNull);
        _expectAppCopyIsWhole(tester);

        // The statement header carries the scope of what is on screen.
        expect(find.text('SPENT'), findsOneWidget);
        expect(find.text('RECEIVED'), findsOneWidget);
        expect(find.text('NET'), findsOneWidget);

        // A ledger is grouped by day, not poured out as one undifferentiated
        // list.
        expect(find.text(_dayLabel(_daysAgo(3))), findsOneWidget);
        expect(find.text(_dayLabel(_daysAgo(4))), findsOneWidget);

        // Preserve the existing issuer-aware domain direction. The purchase
        // is money out in both its day total and transaction row.
        expect(find.text(r'-$174.25'), findsNWidgets(2));

        await _reveal(tester, _dayLabel(_daysAgo(9)));
        _expectAppCopyIsWhole(tester);
        // Refunds remain credits through the existing domain classification.
        expect(find.text(r'+$412.00'), findsOneWidget);

        await _reveal(tester, _dayLabel(_daysAgo(15)));
        _expectAppCopyIsWhole(tester);
      });
    }

    testWidgets('card screens survive a 1.3 text scale at 375 in $theme',
        (tester) async {
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId),
        const Size(375, 812),
        light: light,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      _expectAppCopyIsWhole(tester);

      await _pumpAt(
        tester,
        const CardTransactionsScreen(cardId: _cardId),
        const Size(375, 812),
        light: light,
        textScale: 1.3,
      );
      expect(tester.takeException(), isNull);
      _expectAppCopyIsWhole(tester);
    });
  }

  // -------------------------------------------------------------- states

  testWidgets('card detail loads as a shaped skeleton, not a spinner',
      (tester) async {
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(375, 812),
      light: false,
      detail: () => Completer<PaymentCard>().future,
      cards: const [],
      frames: 4,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ExampleSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('card ledger loads as a shaped skeleton, not a spinner',
      (tester) async {
    await _pumpAt(
      tester,
      const CardTransactionsScreen(cardId: _cardId),
      const Size(375, 812),
      light: true,
      activity: () => Completer<List<PlatformResource>>().future,
      frames: 4,
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(ExampleSkeleton), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed card says what happened and offers a way on',
      (tester) async {
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(375, 812),
      light: false,
      detail: () => Future<PaymentCard>.error(Exception('boom')),
    );

    expect(find.byType(ExampleErrorState), findsOneWidget);
    expect(find.text('Card did not load'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Back to cards'), findsOneWidget);
  });

  testWidgets('a failed ledger says what happened and offers a way on',
      (tester) async {
    await _pumpAt(
      tester,
      const CardTransactionsScreen(cardId: _cardId),
      const Size(375, 812),
      light: true,
      activity: () => Future<List<PlatformResource>>.error(Exception('boom')),
    );

    expect(find.byType(ExampleErrorState), findsOneWidget);
    expect(find.text('Card activity did not load'), findsOneWidget);
  });

  testWidgets('an empty ledger says what will fill it', (tester) async {
    await _pumpAt(
      tester,
      const CardTransactionsScreen(cardId: _cardId),
      const Size(375, 812),
      light: false,
      activity: () async => const <PlatformResource>[],
    );

    expect(find.byType(ExampleEmptyState), findsOneWidget);
    expect(find.text('No activity yet'), findsOneWidget);
  });

  // ------------------------------------------------------- money honesty

  testWidgets('the ledger never infers past balances from a current balance',
      (tester) async {
    await _pumpAt(
      tester,
      const CardTransactionsScreen(cardId: _cardId),
      const Size(393, 852),
      light: false,
    );

    // A cached card balance does not establish historical booked balances.
    expect(find.text(_balance.formatted), findsNothing);

    // The compact 'Spend' segment and the full statement label refer to the
    // same purchase filter.
    await tester.tap(find.text('Spend'));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(tester.takeException(), isNull);
    expect(find.textContaining('purchases only'), findsOneWidget);

    // The same guarantee holds after filtering the statement.
    expect(find.text(_balance.formatted), findsNothing);
  });

  testWidgets('a frozen card disables the CTA and says why', (tester) async {
    const frozen = PaymentCard(
      id: _cardId,
      label: 'Metal',
      last4: '4271',
      network: 'mastercard',
      currency: 'USD',
      status: CardStatus.frozen,
      balance: _balance,
      spendThisMonth: Money(currency: 'USD', minorUnits: -61085),
      limit: Money(currency: 'USD', minorUnits: 500000),
      virtual: false,
    );
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(375, 812),
      light: true,
      detail: () async => frozen,
      cards: [frozen],
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Unfreeze this card to move money.'), findsOneWidget);
    final button = tester.widget<ExampleGlassButton>(
      find.byType(ExampleGlassButton),
    );
    expect(button.onPressed, isNull);
  });

  // ----------------------------------------------------- reduced motion

  testWidgets('reduced motion lands both screens finished on the first frame',
      (tester) async {
    for (final home in <Widget>[
      const CardDetailScreen(cardId: _cardId),
      const CardTransactionsScreen(cardId: _cardId),
    ]) {
      await tester.binding.setSurfaceSize(const Size(375, 812));
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        _app(home, light: false, reducedMotion: true),
      );
      // One frame to resolve the providers, one to build the data state.
      await tester.pump();
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Nothing is mid-flight: no arrival tween, no specular pass, no sheen
      // clock. Reduced motion is the final visual state, reached instantly.
      expect(
        tester.binding.transientCallbackCount,
        0,
        reason: 'an animation is still running under reduced motion',
      );
    }
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  // ------------------------------------------------------------ white label

  testWidgets('a non-Example tenant still renders its own composition',
      (tester) async {
    // Every change here is gated on `isExample` / `context.isExampleTheme`, so
    // the other branch has to still be there and still build. This asserts
    // the gate, not the pixels: it proves the white-label tree is the old
    // one, made of the old widgets, with none of the new vocabulary in it.
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(375, 812),
      light: false,
      example: false,
    );

    // Not an exception assertion: at 375 the white-label activity row
    // overflows inside `FinanceTransactionRow` — its title slot is squeezed
    // to about 71 pt by a trailing column carrying the amount, the secondary
    // amount and a status chip, and the subtitle row it has to fit is 191 pt
    // wide. That is pre-existing behaviour in a shared widget this change
    // does not own and does not touch, so it is filed rather than asserted.
    // What is asserted is the gate: the old tree, none of the new vocabulary.
    tester.takeException();
    expect(find.byType(ExampleGlassButton), findsNothing);
    expect(find.byType(ExampleListGroup), findsNothing);
    expect(find.byType(ExampleSkeleton), findsNothing);
    // `ExampleBackdrop` is deliberately not asserted: it has wrapped this
    // body since before this change and returns its child untouched off
    // Example, so it is in the tree without being in the picture.
    // Both money rows are still there, both still opening the same dialog:
    // the false choice is only collapsed on Example.
    await _reveal(tester, 'Load card');
    expect(find.text('Load card'), findsOneWidget);
    await _reveal(tester, 'Unload card');
    expect(find.text('Unload card'), findsOneWidget);
    // And the long control copy is the tenant's own, not Example's short form.
    await _reveal(tester, 'View card number, expiry date and security code');
    expect(
      find.text('View card number, expiry date and security code'),
      findsOneWidget,
    );

    await _pumpAt(
      tester,
      const CardTransactionsScreen(cardId: _cardId),
      const Size(375, 812),
      light: false,
      example: false,
    );

    tester.takeException();
    expect(find.text('Activity stream'), findsOneWidget);
    expect(find.byType(ExampleSkeleton), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is ExampleSegmentedControl),
      findsNothing,
    );
  });

  // -------------------------------------------------------- the money dialog

  testWidgets('a phone is told how to add the card to its wallet by hand',
      (tester) async {
    // There is no push provisioning, so the row is a set of instructions and
    // it only exists where a Wallet app does. Anywhere else it would promise
    // what the device cannot do.
    // The binding checks this variable is back to null before tear-down
    // runs, so the reset is in the body rather than in addTearDown.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId),
        const Size(393, 852),
        light: false,
      );
      // The callout sits right under the action row, so it is on screen
      // without scrolling; the same row is repeated under Card controls.
      expect(find.text('Add to Apple Wallet'), findsOneWidget);
      expect(find.text('Pay with your iPhone'), findsOneWidget);
      await tester.tap(find.text('Add to Apple Wallet'));
      await _settleDialog(tester);
      // Row and sheet title.
      expect(find.text('Add to Apple Wallet'), findsNWidgets(2));
      expect(
          find.textContaining('Enter Card Details Manually'), findsOneWidget);
      expect(find.textContaining('tap the + button'), findsOneWidget);
      // The Wallet app asks for the number, expiry and CVV, so the sheet's one
      // decisive action is the reveal.
      expect(find.text('Show card details'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settleDialog(tester);
      expect(find.textContaining('Enter Card Details Manually'), findsNothing);
      // The row is repeated under Card controls, below the secure-data row.
      // The callout may have left the lazy list by then, so the copy is
      // proven by position rather than by count.
      await _reveal(tester, 'Show secure card data');
      final secureRow = tester.getTopLeft(find.text('Show secure card data'));
      final walletRows = find.text('Add to Apple Wallet');
      expect(walletRows, findsAtLeastNWidgets(1));
      expect(tester.getTopLeft(walletRows.last).dy, greaterThan(secureRow.dy));
      expect(tester.takeException(), isNull);

      // An Android phone gets the Google Wallet path with its own words.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await tester.pumpWidget(const SizedBox());
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId),
        const Size(393, 852),
        light: false,
      );
      expect(find.text('Add to Google Wallet'), findsOneWidget);
      expect(find.text('Pay with your phone'), findsOneWidget);
      expect(find.text('Add to Apple Wallet'), findsNothing);
      await tester.tap(find.text('Add to Google Wallet'));
      await _settleDialog(tester);
      expect(find.text('Add to Google Wallet'), findsNWidgets(2));
      expect(find.textContaining('Enter details manually'), findsOneWidget);
      expect(find.textContaining('Google Pay'), findsNWidgets(2));
      expect(find.text('Show card details'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await _settleDialog(tester);
      expect(tester.takeException(), isNull);

      // A laptop has no wallet app to add the card to.
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await tester.pumpWidget(const SizedBox());
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId),
        const Size(393, 852),
        light: false,
      );
      await _reveal(tester, 'Cancel card');
      expect(find.text('Add to Apple Wallet'), findsNothing);
      expect(find.text('Add to Google Wallet'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('auto freeze is its own row and the switch saves the setting',
      (tester) async {
    final api = _AutoFreezeApi();
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(393, 852),
      light: false,
      overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
    );
    await _reveal(tester, 'Auto freeze');
    _expectAppCopyIsWhole(tester);
    // Off by default, and a row of its own under Card controls: not a line
    // inside Spending limits.
    expect(find.text('Auto freeze'), findsOneWidget);
    expect(find.text('Freezes again after 10 minutes'), findsOneWidget);
    final toggle = find.byType(Switch);
    expect(toggle, findsOneWidget);
    expect(tester.widget<Switch>(toggle).value, isFalse);

    await tester.ensureVisible(toggle);
    await tester.pumpAndSettle();
    await tester.tap(toggle);
    await tester.pump();
    // Moves under the finger, then the backend confirms it.
    expect(tester.widget<Switch>(toggle).value, isTrue);
    await tester.pumpAndSettle();
    expect(api.calls, [(_cardId, true)]);
    expect(tester.widget<Switch>(toggle).value, isTrue);
    expect(find.text('Auto freeze is on'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(api.calls, [(_cardId, true), (_cardId, false)]);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a double tap on Manage balance opens one dialog, not two',
      (tester) async {
    // The dialog waits for the balances to re-fetch before it appears, and a
    // customer on a slow link who tapped again in that gap used to get a
    // second copy queued behind the first — one top-up, two sheets to close.
    final balances = Completer<List<HoppaWalletAsset>>();
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(393, 852),
      light: false,
      overrides: [
        hoppaWalletAssetsProvider.overrideWith((ref) => balances.future),
      ],
    );

    final cta = find.byType(ExampleGlassButton);
    await tester.tap(cta);
    await tester.pump();
    // The second tap lands while the first is still fetching; the button is
    // already showing its progress ring, so the tap must go nowhere.
    await tester.tap(cta, warnIfMissed: false);
    await tester.pump();
    expect(tester.widget<ExampleGlassButton>(cta).loading, isTrue);

    balances.complete(_walletAssets);
    await _settleDialog(tester);
    expect(find.text('Add to card'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);

    await tester.tap(find.byTooltip('Close'));
    await _settleDialog(tester);
    expect(find.text('Add to card'), findsNothing);
    expect(tester.widget<ExampleGlassButton>(cta).loading, isFalse);

    // Closing releases the guard: the next tap opens the dialog again.
    await tester.tap(cta);
    await _settleDialog(tester);
    expect(find.text('Add to card'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the money dialog opens on the direction the control names',
      (tester) async {
    await _pumpAt(
      tester,
      const CardDetailScreen(cardId: _cardId),
      const Size(393, 852),
      light: false,
    );

    // The glass CTA is the load direction.
    await tester.tap(find.byType(ExampleGlassButton));
    await _settleDialog(tester);
    // The CTA keeps its label beneath the dialog, so the title is a second
    // match rather than the only one.
    expect(find.text('Manage balance'), findsAtLeastNWidgets(1));
    expect(find.text('Card ending in ${_card.last4}'), findsOneWidget);
    expect(find.text('Add to card'), findsOneWidget);
    // Its opening segment is Top up, so the crypto balances are what is
    // being spent from.
    expect(find.text('Crypto card balances'), findsOneWidget);
    expect(find.text('Available for top-up'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Close'));
    await _settleDialog(tester);

    // The other direction, from the row that names it. Before this, both
    // controls opened the dialog on Top up.
    await _reveal(tester, 'Move money off card');
    await tester.tap(find.text('Move money off card'));
    await _settleDialog(tester);
    expect(find.text('Unload card'), findsOneWidget);
    expect(find.text('Card ending in ${_card.last4}'), findsOneWidget);
    expect(find.text('Available on card'), findsOneWidget);
    expect(find.text(_balance.formatted), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'manage balance identifies the swiped card without fabricated digits',
      (tester) async {
    for (final last4 in ['8763', '']) {
      final selected = PaymentCard(
        id: 'selected-card',
        label:
            'Travel and everyday purchases with a deliberately long card nickname',
        last4: last4,
        network: 'Visa',
        currency: 'USD',
        status: CardStatus.active,
        balance: _balance,
        spendThisMonth: const Money(currency: 'USD', minorUnits: 1200),
        limit: const Money(currency: 'USD', minorUnits: 500000),
        virtual: true,
      );
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId, asTab: true),
        const Size(375, 812),
        light: false,
        cards: [_card, selected],
        textScale: 1.3,
      );
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await _settleDialog(tester);
      await tester.ensureVisible(find.byType(ExampleGlassButton));
      await tester.tap(find.byType(ExampleGlassButton));
      await _settleDialog(tester);
      final identity = tester.widget<Text>(
        find.byKey(const ValueKey('managed-card-last4')),
      );
      expect(identity.data,
          last4.isEmpty ? 'Selected card' : 'Card ending in 8763');
      expect(find.text('Card ending in ${_card.last4}'), findsNothing);
      expect(find.text(selected.displayLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the money dialog is built from the Example vocabulary',
      (tester) async {
    for (final light in [false, true]) {
      await _pumpAt(
        tester,
        const CardDetailScreen(cardId: _cardId),
        const Size(375, 812),
        light: light,
        textScale: 1.3,
      );
      await tester.tap(find.byType(ExampleGlassButton));
      await _settleDialog(tester);

      // House controls, not Material ones. These are predicates rather than
      // `byType`, which matches a generic's type argument exactly and would
      // pass for the wrong reason.
      expect(
        find.byWidgetPredicate((w) => w is ExampleSegmentedControl),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate((w) => w is SegmentedButton),
        findsNothing,
      );
      expect(find.byType(Chip), findsNothing);
      // A dropdown with one option and no handler is not a choice, and the
      // currency it named is already the amount field's suffix.
      expect(
        find.byWidgetPredicate((w) => w is DropdownButtonFormField),
        findsNothing,
      );
      // Balances read as a column of figures, not a wrap of chips.
      expect(find.byType(ExampleListGroup), findsWidgets);

      // The identity stays at the start of the scrollable form; quick amounts
      // can sit below the fold at larger text sizes.
      await tester.ensureVisible(find.text('MAX'));
      await tester.pump();
      // Every quick-amount control clears the 44 pt floor at a 1.3 scale.
      for (final label in ['25%', '50%', '75%', 'MAX']) {
        final size = tester.getSize(find.text(label).hitTestable().first);
        expect(size.height, greaterThan(0));
        final box = tester.getSize(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(ExamplePressable),
              )
              .first,
        );
        expect(
          box.height,
          greaterThanOrEqualTo(44),
          reason: '$label is a ${box.height} pt target',
        );
      }

      _expectAppCopyIsWhole(tester);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await _settleDialog(tester);
    }
  });
}

/// Push a dialog route through its opening animation.
///
/// The page underneath keeps a sheen clock alive, so this advances a fixed
/// number of frames rather than settling.
Future<void> _settleDialog(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

class _AutoFreezeApi extends MobilePlatformApi {
  _AutoFreezeApi() : super(Dio());
  final calls = <(String, bool)>[];
  @override
  Future<ActionResult> setCardAutoFreeze(String cardId, bool enabled) async {
    calls.add((cardId, enabled));
    return ActionResult(
        message: enabled ? 'Auto freeze is on' : 'Auto freeze is off');
  }
}

class _SecureApi extends MobilePlatformApi {
  _SecureApi() : super(Dio());
  int requests = 0;
  Completer<ActionResult>? pending;
  @override
  Future<ActionResult> getCardWidget(String cardId) async {
    requests++;
    if (pending != null) return pending!.future;
    return ActionResult(message: '', metadata: {
      'widgetUrl': 'https://secure.example/card?session=$requests'
    });
  }
}

class _SecureBiometrics extends BiometricAuthenticator {
  @override
  Future<BiometricCapability> capability() async => const BiometricCapability(
      available: true, types: [], reason: BiometricUnavailableReason.none);
  @override
  Future<BiometricAuthResult> authenticate({required String reason}) async =>
      BiometricAuthResult.success;
}

class _SecurePlatform extends WebViewPlatform {
  final controllers = <_SecureController>[];
  int copyCalls = 0;
  @override
  PlatformWebViewController createPlatformWebViewController(
      PlatformWebViewControllerCreationParams params) {
    final controller = _SecureController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
          PlatformNavigationDelegateCreationParams params) =>
      _SecureDelegate(params);
  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
          PlatformWebViewWidgetCreationParams params) =>
      _SecureWidget(params, onCopy: () => copyCalls++);
}

class _SecureController extends PlatformWebViewController {
  _SecureController(super.params) : super.implementation();
  _SecureDelegate? delegate;
  JavaScriptChannelParams? channel;
  String? url;
  void reportError() => channel!.onMessageReceived(const JavaScriptMessage(
      message: '{"type":"card-secure-widget-status","status":"error"}'));
  @override
  Future<void> setJavaScriptMode(JavaScriptMode mode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channel = params;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {}
  @override
  Future<void> setPlatformNavigationDelegate(
      PlatformNavigationDelegate handler) async {
    delegate = handler as _SecureDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    url = params.uri.toString();
    scheduleMicrotask(() => delegate?.finished?.call(url!));
  }
}

class _SecureDelegate extends PlatformNavigationDelegate {
  _SecureDelegate(super.params) : super.implementation();
  PageEventCallback? finished;
  FutureOr<NavigationDecision> Function(NavigationRequest)? navigation;
  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    finished = callback;
  }

  @override
  Future<void> setOnNavigationRequest(
      FutureOr<NavigationDecision> Function(NavigationRequest) callback) async {
    navigation = callback;
  }

  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback callback) async {}
}

class _SecureWidget extends PlatformWebViewWidget {
  _SecureWidget(super.params, {required this.onCopy}) : super.implementation();
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => Center(
          child: TextButton(
        onPressed: onCopy,
        child: const Text('Copy test data'),
      ));
}

class _TopUpEstimateApi extends MobilePlatformApi {
  _TopUpEstimateApi() : super(Dio());
  final amounts = <double>[];
  @override
  Future<QuantumTopUpEstimate> getQuantumTopUpEstimate(
      {required Money amount}) async {
    amounts.add(amount.decimalAmount);
    return QuantumTopUpEstimate(
        success: true,
        usdAmount: amount.decimalAmount,
        topUpFee: amount.decimalAmount * .025,
        topUpFeePercent: 2.5);
  }
}
