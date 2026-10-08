import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/crypto/presentation/transak_checkout_dialog.dart';
import 'package:mobile_flutter/features/crypto/presentation/transak_checkout_frame.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/data/wallet_providers.dart';
import 'package:mobile_flutter/features/wallets/domain/wallet_models.dart';
import 'package:mobile_flutter/features/wallets/domain/withdrawal_models.dart';
import 'package:mobile_flutter/features/wallets/presentation/crypto_withdrawal_dialog.dart';
import 'package:mobile_flutter/features/wallets/presentation/deposit_address_dialog.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

// ---------------------------------------------------------------------------
// Harness
// ---------------------------------------------------------------------------

const _exampleBranding = AppBranding(
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

/// A tenant with no `ExampleBrand` extension: every Example branch must fall
/// through to the tree that shipped before this wave.
const _tenantBranding = AppBranding(
  appName: 'Hoppa',
  brandId: 'generic',
  primarySeedHex: '7C5CFF',
  accentSeedHex: '2DD4BF',
  loginBackgroundHex: '',
  themeMode: 'dark',
  fontFamily: '',
  logoAsset: '',
  radiusScale: '1',
  supportEmail: 'support@example.com',
  supportPhone: '',
  legalEntity: 'Hoppa',
);

/// The brand's own typefaces, so every truncation assertion below is measured
/// in Geist. Without this the binding falls back to the test font, whose
/// glyphs are square boxes roughly twice Geist's advance width, and a layout
/// proof measured in it is a proof about a font nobody ships.
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

/// The four widths the layout laws name.
const _phone = 375.0;
const _desktop = 1440.0;

/// A real, all-lowercase EVM address: 42 characters, so it passes the
/// validator's format check without tripping its EIP-55 mixed-case rule.
const _evmAddress = '0x71c7656ec7ab88b098defb751b7401b5f6d8976f';

const _usdt = HoppaWalletAsset(
  symbol: 'USDT',
  name: 'Tether',
  network: 'ETH / OP / ARB',
  amount: 320.394999,
  fiatValue: 320.39,
  address: _evmAddress,
  tint: Color(0xFF26A17B),
  walletId: 'w-usdt',
);

const _usdtTron = HoppaWalletAsset(
  symbol: 'USDT',
  name: 'Tether',
  network: 'TRX',
  amount: 320.394999,
  fiatValue: 320.39,
  address: 'TXabc0000000000000000000000000000ab',
  tint: Color(0xFF26A17B),
  walletId: 'w-usdt-tron',
);

Widget _host({
  required Widget child,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
  double height = 900,
  bool reducedMotion = false,
}) {
  final themes = buildAppThemes(branding);
  final theme = brightness == Brightness.dark ? themes.dark : themes.light;
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: theme,
      themeMode: ThemeMode.light,
      // The MediaQuery goes in through `builder`, above the Navigator: a
      // sheet or dialog route is a sibling of `home` under that Navigator, so
      // an override placed in `home` never reaches it.
      builder: (context, navigator) => MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reducedMotion,
        ),
        child: ExampleSheenScope(child: navigator ?? const SizedBox.shrink()),
      ),
      home: child,
    ),
  );
}

/// A host whose body carries a button that opens [open] against a real route.
Widget _opener({
  required void Function(BuildContext context) open,
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double textScale = 1,
  double height = 900,
  bool reducedMotion = false,
}) =>
    _host(
      width: width,
      height: height,
      brightness: brightness,
      branding: branding,
      overrides: overrides,
      textScale: textScale,
      reducedMotion: reducedMotion,
      child: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => open(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _pumpAt(
  WidgetTester tester,
  Widget app, {
  required double width,
  double height = 900,
}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

/// The tone of the screen's single decisive CTA.
ExampleGlassButtonTone _ctaTone(WidgetTester tester) =>
    tester.widget<ExampleGlassButton>(find.byType(ExampleGlassButton)).tone;

/// The rendered paragraph behind a `Text`, so a test can ask the thing that
/// actually matters — did this string have to be cut off to fit?
RenderParagraph _paragraph(WidgetTester tester, Finder finder) =>
    tester.renderObject<RenderParagraph>(finder);

/// Every `Text` currently laid out, and whether it had to be cut off to fit.
///
/// "Nothing truncates at 375, and nothing truncates at text scale 1.3" is a
/// floor, so it is checked as one: the whole visible tree at once, rather than
/// the one string a test happened to think of.
void _expectNothingTruncated(WidgetTester tester) {
  final cut = <String>[];
  for (final element in find.byType(Text).evaluate()) {
    final box = element.renderObject;
    if (box is RenderParagraph && box.didExceedMaxLines) {
      cut.add(box.text.toPlainText());
    }
  }
  expect(cut, isEmpty, reason: 'truncated at this size: $cut');
}

// ---------------------------------------------------------------------------
// A platform API that answers only what these dialogs ask
// ---------------------------------------------------------------------------

class _FakeApi extends MobilePlatformApi {
  _FakeApi({
    this.fees = const [
      CryptoWithdrawalFee(amount: 0.5, currency: 'USDT', type: 'GAS'),
    ],
  }) : super(Dio());

  final List<CryptoWithdrawalFee> fees;

  /// The same figure the asset carries, so the sheet's own `min(asset,
  /// withdrawable)` cannot quietly change which of the two rejection
  /// sentences is under test.
  static const double available = 320.394999;

  @override
  Future<CryptoWithdrawalBalance> getCryptoWithdrawalAvailableBalance() async =>
      const CryptoWithdrawalBalance(
        totalAvailableUsdt: available,
        totalAvailableUsdc: available,
      );

  @override
  Future<CryptoWithdrawalQuote> getCryptoWithdrawalFeeAndQuota({
    required String chain,
    required String address,
    required String currency,
    required String amount,
  }) async =>
      CryptoWithdrawalQuote(
        code: '000000',
        crossChainQuota: '',
        crossChainFeeRate: '',
        crossChainAmount: '',
        fees: fees,
        message: '',
      );

  @override
  Future<CryptoWithdrawalResult> createCryptoWithdrawal({
    required String currency,
    required String chain,
    required String amount,
    required String destinationAddress,
  }) async =>
      const CryptoWithdrawalResult(
        success: true,
        otpRequired: true,
        verificationToken: 'token-1',
        status: 'PENDING',
        message: 'Enter the 8-digit code sent to your registered email.',
        transactionId: 'tx-1',
        otpExpiresAt: null,
        fees: [],
      );
}

List<Override> _withdrawalOverrides({_FakeApi? api}) => [
      mobilePlatformApiProvider.overrideWithValue(api ?? _FakeApi()),
      hoppaWalletAssetsProvider.overrideWith((ref) async => const [_usdt]),
    ];

// A native WebView stand-in lets these tests exercise the actual checkout
// route and chrome without starting a platform view or making a request.
class _CheckoutPlatform extends WebViewPlatform {
  final requestedUrls = <Uri>[];

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) =>
      _CheckoutController(params, requestedUrls);

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) =>
      _CheckoutDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) =>
      _CheckoutWidget(params);
}

class _CheckoutController extends PlatformWebViewController {
  _CheckoutController(super.params, this.requestedUrls)
      : super.implementation();

  final List<Uri> requestedUrls;
  _CheckoutDelegate? _delegate;

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setBackgroundColor(Color color) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    _delegate = handler as _CheckoutDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    requestedUrls.add(params.uri);
    scheduleMicrotask(
        () => _delegate?.onPageFinished?.call(params.uri.toString()));
  }
}

class _CheckoutDelegate extends PlatformNavigationDelegate {
  _CheckoutDelegate(super.params) : super.implementation();

  PageEventCallback? onPageFinished;

  @override
  Future<void> setOnPageFinished(PageEventCallback callback) async {
    onPageFinished = callback;
  }
}

class _CheckoutWidget extends PlatformWebViewWidget {
  _CheckoutWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

/// Walks the withdrawal sheet from step 1 to step 2.
Future<void> _toReview(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextField, 'Destination wallet address'),
    _evmAddress,
  );
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, 'Amount (USDT)'),
    '12.5',
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ExampleGlassButton));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(_loadFonts);

  // ------------------------------------------------------------------
  // Receive: the address must be complete, and copying must confirm
  // ------------------------------------------------------------------
  group('Deposit address sheet', () {
    late List<String> copied;

    setUp(() {
      copied = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    for (final width in const [_phone, _desktop]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'shows every character of the address at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _opener(
                width: width,
                brightness: brightness,
                open: (context) => showStablecoinDepositDialog(
                  context,
                  addresses: const [_usdt],
                ),
              ),
              width: width,
            );
            await _openSheet(tester);

            final mono = tester.widget<ExampleMono>(
              find.byType(ExampleMono).first,
            );
            // Grouped for verification, and nothing dropped in the process.
            expect(mono.display, contains(' '));
            expect(mono.display.replaceAll(' ', ''), _evmAddress);
            expect(mono.display, isNot(contains('…')));

            // The measured question: the paragraph fits, so no end ellipsis
            // ever eats the checksum.
            final paragraph = _paragraph(tester, find.text(mono.display));
            expect(paragraph.didExceedMaxLines, isFalse);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          'copies the unbroken address and says so at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _opener(
                width: width,
                brightness: brightness,
                open: (context) => showStablecoinDepositDialog(
                  context,
                  addresses: const [_usdt],
                ),
              ),
              width: width,
            );
            await _openSheet(tester);

            expect(find.text('Copy address'), findsOneWidget);
            await tester.tap(find.byType(ExampleGlassButton));
            await tester.pumpAndSettle();

            // The clipboard gets the real address, not the grouped rendering.
            expect(copied, [_evmAddress]);
            expect(find.text('Copied'), findsOneWidget);
            expect(find.text('Copy address'), findsNothing);
          },
        );
      }
    }

    testWidgets('keeps the address whole at 375 and text scale 1.3',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.light,
          textScale: 1.3,
          open: (context) => showStablecoinDepositDialog(
            context,
            addresses: const [_usdt],
          ),
        ),
        width: _phone,
      );
      await _openSheet(tester);

      final mono = tester.widget<ExampleMono>(find.byType(ExampleMono).first);
      expect(mono.display.replaceAll(' ', ''), _evmAddress);
      expect(
        _paragraph(tester, find.text(mono.display)).didExceedMaxLines,
        isFalse,
      );
      _expectNothingTruncated(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('offers a network row per option and marks the selected one',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          open: (context) => showStablecoinDepositDialog(
            context,
            addresses: const [_usdt, _usdtTron],
          ),
        ),
        width: _phone,
      );
      await _openSheet(tester);

      // One row per network, and the panel names the standard it is showing.
      expect(find.byType(ExampleRow), findsNWidgets(2));
      expect(find.text('DEPOSIT ADDRESS'), findsOneWidget);

      String shown() => tester
          .widget<ExampleMono>(find.byType(ExampleMono).first)
          .display
          .replaceAll(' ', '');
      final first = shown();
      expect([_usdt.address, _usdtTron.address], contains(first));

      // Switching the network switches the address, which is the whole point
      // of the row: an ERC20 deposit sent to the TRC20 address is gone.
      final onErc = first == _usdt.address;
      await tester.tap(
        find.widgetWithText(ExampleRow, onErc ? 'TRC20' : 'ERC20'),
      );
      await tester.pumpAndSettle();
      expect(shown(), onErc ? _usdtTron.address : _usdt.address);
    });

    // The regression this suite exists for as much as anything else. A bare
    // `Center` in the pinned bar took the whole height `Scaffold` offers a
    // `bottomNavigationBar` — the entire sheet — and the body was laid out at
    // `Size(375.0, 0.0)`: a title, a void, and a Copy button for an address
    // nobody could see.
    for (final width in const [_phone, _desktop]) {
      testWidgets('leaves the body its height beside the CTA bar at $width',
          (tester) async {
        await _pumpAt(
          tester,
          _opener(
            width: width,
            brightness: Brightness.dark,
            open: (context) => showStablecoinDepositDialog(
              context,
              addresses: const [_usdt],
            ),
          ),
          width: width,
        );
        await _openSheet(tester);

        final body = tester.getSize(find.byType(ListView));
        final sheet = tester.getSize(find.byType(BottomSheet));
        expect(body.height, greaterThan(sheet.height / 2));
      });
    }

    testWidgets('finishes its arrival instantly under reduced motion',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          reducedMotion: true,
          open: (context) => showStablecoinDepositDialog(
            context,
            addresses: const [_usdt],
          ),
        ),
        width: _phone,
      );
      await tester.tap(find.text('open'));
      // Two frames: the sheet itself is still travelling, but the screen's
      // own moment must already be over — reduced motion means *arrived*,
      // not *faster*.
      await tester.pump();
      await tester.pump();

      final fades = tester.widgetList<Opacity>(
        find.ancestor(
          of: find.byType(ExampleMono),
          matching: find.byType(Opacity),
        ),
      );
      expect(fades, isNotEmpty);
      for (final fade in fades) {
        expect(fade.opacity, 1.0);
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('white-label keeps its own sheet, with no glass CTA',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          open: (context) => showStablecoinDepositDialog(
            context,
            addresses: const [_usdt],
          ),
        ),
        width: _phone,
      );
      await _openSheet(tester);

      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.byType(ExampleMono), findsNothing);
      expect(find.text('Deposit address'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------
  // Withdraw: the red button is the one that spends
  // ------------------------------------------------------------------
  group('Crypto withdrawal sheet', () {
    for (final width in const [_phone, _desktop]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'reserves danger for the step that sends, at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _opener(
                width: width,
                brightness: brightness,
                overrides: _withdrawalOverrides(),
                open: (context) =>
                    showCryptoWithdrawalDialog(context, asset: _usdt),
              ),
              width: width,
            );
            await _openSheet(tester);

            // Step 1: details.
            expect(find.text('STEP 1 OF 3'), findsOneWidget);
            expect(_ctaTone(tester), ExampleGlassButtonTone.primary);

            await _toReview(tester);

            // Step 2: review. Nothing has left the account yet, so nothing
            // here may be dressed as the point of no return.
            expect(find.text('STEP 2 OF 3'), findsOneWidget);
            expect(find.text('Send verification code'), findsOneWidget);
            expect(_ctaTone(tester), ExampleGlassButtonTone.primary);

            // `_ExampleConfirmCheck` is private to the dialog, so the
            // confirmation is reached through the tile it is built from.
            await tester.tap(find.byType(CheckboxListTile));
            await tester.pumpAndSettle();
            await tester.tap(find.byType(ExampleGlassButton));
            await tester.pumpAndSettle();

            // Step 3: the code. This press moves money, so this is the one
            // that is red.
            expect(find.text('STEP 3 OF 3'), findsOneWidget);
            expect(find.text('Confirm withdrawal'), findsOneWidget);
            expect(_ctaTone(tester), ExampleGlassButtonTone.danger);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('groups the existing withdrawal quote facts into a ledger',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          overrides: _withdrawalOverrides(),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);
      await _toReview(tester);

      double y(String label) => tester.getTopLeft(find.text(label)).dy;

      // Keep the existing quote facts; a visual port must not introduce a
      // new financial total that the provider did not supply.
      expect(y('You send'), lessThan(y('Network fee')));
      expect(y('Network fee'), lessThan(y('Available to send')));
      expect(y('Available to send'), lessThan(y('Network')));
      expect(y('Network'), lessThan(y('DESTINATION')));

      expect(find.textContaining('Total debited'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows each fee in the currency returned by the provider',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.light,
          overrides: _withdrawalOverrides(
            api: _FakeApi(
              fees: const [
                CryptoWithdrawalFee(amount: 0.5, currency: 'USDT', type: 'GAS'),
                CryptoWithdrawalFee(
                  amount: 0.002,
                  currency: 'ETH',
                  type: 'CROSS_CHAIN',
                ),
              ],
            ),
          ),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);
      await _toReview(tester);

      final amounts =
          tester.widgetList<ExampleAmount>(find.byType(ExampleAmount));
      expect(
        amounts
            .any((amount) => amount.amount == 0.5 && amount.currency == 'USDT'),
        isTrue,
      );
      expect(
        amounts.any(
            (amount) => amount.amount == 0.002 && amount.currency == 'ETH'),
        isTrue,
      );
      expect(find.text('Network fee'), findsOneWidget);
      expect(find.text('Cross-chain fee'), findsOneWidget);
      expect(find.textContaining('Total debited'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    for (final width in const [_phone, _desktop]) {
      for (final brightness in Brightness.values) {
        testWidgets(
          'pins the failure beside the button at $width in $brightness',
          (tester) async {
            await _pumpAt(
              tester,
              _opener(
                width: width,
                brightness: brightness,
                overrides: _withdrawalOverrides(),
                open: (context) =>
                    showCryptoWithdrawalDialog(context, asset: _usdt),
              ),
              width: width,
            );
            await _openSheet(tester);

            await tester.enterText(
              find.widgetWithText(TextField, 'Amount (USDT)'),
              '1',
            );
            await tester.pumpAndSettle();
            await tester.tap(find.byType(ExampleGlassButton));
            await tester.pumpAndSettle();

            const message = 'Enter an amount of at least 5 USDT.';
            expect(find.text(message), findsOneWidget);
            // Out of the scroller entirely, so it cannot be scrolled away
            // from the control that produced it.
            expect(
              find.descendant(
                of: find.byType(ListView),
                matching: find.text(message),
              ),
              findsNothing,
            );
            // And below the form: it sits in the pinned bar with the CTA.
            expect(
              tester.getTopLeft(find.text(message)).dy,
              greaterThan(
                tester.getTopLeft(find.text('Send to an external wallet')).dy,
              ),
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('preserves the existing insufficient balance message',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          overrides: _withdrawalOverrides(),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (USDT)'),
        '9999',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExampleGlassButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Your available USDT balance is 320.394999.'),
        findsOneWidget,
      );
    });

    testWidgets('preserves the existing Max amount precision', (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          overrides: _withdrawalOverrides(),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Max'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.widgetWithText(TextField, 'Amount (USDT)'),
      );
      expect(field.controller!.text, '320.39');
      expect(tester.takeException(), isNull);
    });

    testWidgets('cuts off nothing at 375 and text scale 1.3', (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.light,
          textScale: 1.3,
          overrides: _withdrawalOverrides(),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);
      _expectNothingTruncated(tester);
      expect(tester.takeException(), isNull);

      await _toReview(tester);
      _expectNothingTruncated(tester);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ExampleGlassButton));
      await tester.pumpAndSettle();
      expect(find.text('STEP 3 OF 3'), findsOneWidget);
      _expectNothingTruncated(tester);
      expect(tester.takeException(), isNull);
    });

    for (final width in const [_phone, _desktop]) {
      testWidgets('leaves the form its height beside the CTA bar at $width',
          (tester) async {
        await _pumpAt(
          tester,
          _opener(
            width: width,
            brightness: Brightness.light,
            overrides: _withdrawalOverrides(),
            open: (context) =>
                showCryptoWithdrawalDialog(context, asset: _usdt),
          ),
          width: width,
        );
        await _openSheet(tester);

        final body = tester.getSize(find.byType(ListView));
        final sheet = tester.getSize(find.byType(BottomSheet));
        expect(body.height, greaterThan(sheet.height / 2));
        // And the address field is reachable, which is the thing a
        // zero-height body actually costs.
        expect(
          find.widgetWithText(TextField, 'Destination wallet address'),
          findsOneWidget,
        );
      });
    }

    testWidgets('white-label keeps the filled button and the scrolled error',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _phone,
          brightness: Brightness.dark,
          branding: _tenantBranding,
          overrides: _withdrawalOverrides(),
          open: (context) => showCryptoWithdrawalDialog(context, asset: _usdt),
        ),
        width: _phone,
      );
      await _openSheet(tester);

      expect(find.byType(ExampleGlassButton), findsNothing);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.textContaining('STEP 1 OF 3'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Amount (USDT)'),
        '1',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      const message = 'Enter an amount of at least 5 USDT.';
      // Still inside the scroller, where every other brand has always had it.
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.text(message),
        ),
        findsOneWidget,
      );
      expect(
        find.text('Your available USDT balance is 320.394999.'),
        findsNothing,
      );
    });
  });

  // ------------------------------------------------------------------
  // Buy with card: our chrome, their page
  // ------------------------------------------------------------------
  group('Transak checkout chrome', () {
    const checkoutUrl = 'https://checkout.example.test/session-1';
    late _CheckoutPlatform checkoutPlatform;
    late WebViewPlatform? previousPlatform;

    setUp(() {
      previousPlatform = WebViewPlatform.instance;
      checkoutPlatform = _CheckoutPlatform();
      WebViewPlatform.instance = checkoutPlatform;
    });

    tearDown(() {
      if (previousPlatform != null) WebViewPlatform.instance = previousPlatform;
    });

    for (final brightness in Brightness.values) {
      testWidgets('is full-bleed at 375 and a column at 1440 in $brightness',
          (tester) async {
        await _pumpAt(
          tester,
          _opener(
            width: _phone,
            brightness: brightness,
            open: (context) => showTransakCheckout(context, checkoutUrl),
          ),
          width: _phone,
        );
        await _openSheet(tester);
        expect(find.byType(Dialog), findsOneWidget);
        final checkoutSurface = find.descendant(
          of: find.byType(Dialog),
          matching: find.byType(Scaffold),
        );
        expect(tester.getSize(checkoutSurface).width, _phone);

        tester.view.physicalSize = const Size(_desktop, 900);
        await tester.pumpWidget(
          _opener(
            width: _desktop,
            brightness: brightness,
            open: (context) => showTransakCheckout(context, checkoutUrl),
          ),
        );
        await tester.pumpAndSettle();

        // The open dialog follows the viewport instead of keeping the shape
        // it was opened at: a resized window is the normal case on web.
        expect(
          tester.getSize(checkoutSurface).width,
          480,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('preserves the checkout URL and the close action',
        (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: _desktop,
          brightness: Brightness.dark,
          open: (context) => showTransakCheckout(context, checkoutUrl),
        ),
        width: _desktop,
      );
      await _openSheet(tester);

      expect(find.byType(TransakCheckoutFrame), findsOneWidget);
      expect(checkoutPlatform.requestedUrls, [Uri.parse(checkoutUrl)]);
      expect(find.text('Buy with card'), findsOneWidget);
      expect(find.text('Secure checkout by Transak'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Close checkout'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('open'), findsOneWidget);
    });

    testWidgets('never overflows in a short desktop window', (tester) async {
      await _pumpAt(
        tester,
        _opener(
          width: 1024,
          height: 420,
          brightness: Brightness.light,
          open: (context) => showTransakCheckout(context, checkoutUrl),
        ),
        width: 1024,
        height: 420,
      );
      await _openSheet(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
