import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:mobile_flutter/core/diagnostics/app_build_info.dart';
import 'package:mobile_flutter/core/diagnostics/browser_name.dart';
import 'package:mobile_flutter/core/diagnostics/client_environment.dart';
import 'package:mobile_flutter/core/widgets/app_version_header.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('Geist')
      ..addFont(rootBundle.load('assets/fonts/Geist-Regular.ttf'));
    await font.load();
  });
  const info =
      AppBuildInfo(version: '0.1.7', buildNumber: '11', revision: 'abc1234');

  test('build label distinguishes releases with the same package version', () {
    expect(info.label, 'v0.1.7+11 · abc1234');
    expect(
        const AppBuildInfo(
                version: '0.1.7', buildNumber: '11', revision: 'def5678')
            .label,
        isNot(info.label));
    expect(const AppBuildInfo(version: '').label, 'Version unavailable');
  });

  test('direct builds use the actual installed package version', () async {
    PackageInfo.setMockInitialValues(
        appName: 'Test',
        packageName: 'test.app',
        version: '3.4.5',
        buildNumber: '77',
        buildSignature: '');
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final value = await container.read(appBuildInfoProvider.future);
    expect(value.version, '3.4.5');
    expect(value.buildNumber, '77');
  });

  for (final testCase in <String, String>{
    'Mozilla/5.0 AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36': 'Chrome',
    'Mozilla/5.0 Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0': 'Edge',
    'Mozilla/5.0 Chrome/131.0.0.0 Safari/537.36 EdgA/131.0.0.0': 'Edge',
    'Mozilla/5.0 AppleWebKit/605.1.15 EdgiOS/131.0 Mobile/15E148 Safari/605.1.15':
        'Edge',
    'Mozilla/5.0 Chrome/131.0 Safari/537.36 OPR/115.0': 'Opera',
    'Mozilla/5.0 Chrome/131.0 SamsungBrowser/27.0 Safari/537.36':
        'Samsung Internet',
    'Mozilla/5.0 Gecko/20100101 Firefox/132.0': 'Firefox',
    'Mozilla/5.0 FxiOS/132.0 Mobile/15E148 Safari/605.1.15': 'Firefox',
    'Mozilla/5.0 AppleWebKit/605.1.15 Version/18.0 Mobile/15E148 Safari/604.1':
        'Safari',
    'Mozilla/5.0 AppleWebKit/605.1.15 CriOS/131.0 Mobile/15E148 Safari/604.1':
        'Chrome',
    'Mozilla/5.0 Chrome/131.0 Safari/537.36 Brave/1.73': 'Brave',
    'Mozilla/5.0 Chromium/131.0 Safari/537.36': 'Chromium',
    'Mozilla/5.0 GSA/123.0 Safari/604.1': 'Google app',
    'Mozilla/5.0 Chrome/131.0 Instagram 353.0': 'In-app browser',
    'Unrecognized client': 'Browser',
  }.entries) {
    test('browser name: ${testCase.value} from ${testCase.key}', () {
      expect(browserNameForUserAgent(testCase.key), testCase.value);
    });
  }

  test('native builds show the platform instead of a browser', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    expect(currentClientEnvironment(), 'Android');
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(currentClientEnvironment(), 'iOS');
  });

  Future<void> mount(WidgetTester tester,
      {double width = 320,
      Brightness brightness = Brightness.dark,
      double scale = 1,
      EdgeInsets padding = EdgeInsets.zero,
      double keyboard = 0,
      String client = 'Chrome',
      Widget? home}) async {
    await tester.binding.setSurfaceSize(Size(width, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          appBuildInfoProvider.overrideWith((ref) async => info),
          clientEnvironmentProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
            theme: ThemeData(brightness: brightness, fontFamily: 'Geist'),
            builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(scale),
                      padding: padding,
                      viewPadding: padding,
                      viewInsets: EdgeInsets.only(bottom: keyboard)),
                  child: AppVersionFrame(child: child!),
                ),
            home: home ??
                Scaffold(
                    appBar: AppBar(title: const Text('Home'), actions: [
                      IconButton(
                          onPressed: () {},
                          icon: const Icon(Icons.help_outline))
                    ]),
                    body: const Text('Page content')))));
    await tester.pumpAndSettle();
  }

  for (final width in [320.0, 900.0, 1280.0, 1600.0]) {
    for (final brightness in Brightness.values) {
      testWidgets('version and browser fit at $width ${brightness.name}',
          (tester) async {
        await mount(tester,
            width: width,
            brightness: brightness,
            scale: 1.5,
            client: 'Samsung Internet');
        expect(find.text(info.label), findsOneWidget);
        expect(
            find.text(width >= 900 ? 'Samsung Internet' : '· Samsung Internet'),
            findsOneWidget);
        final header = tester.getRect(find.byKey(AppVersionFrame.headerKey));
        final title = tester.getRect(find.text('Home'));
        if (width >= 900) {
          final help = tester.getRect(find.byIcon(Icons.help_outline));
          expect(help.right, lessThanOrEqualTo(header.left));
          expect(title.top, lessThan(header.bottom));
          expect(header.top, lessThan(title.bottom));
          expect(tester.getTopLeft(find.byType(Scaffold)).dy, 0);
          expect(header.width, lessThan(400));
        } else {
          expect(header.bottom, lessThanOrEqualTo(title.top));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('header respects the notch without duplicating page padding',
      (tester) async {
    MediaQueryData? childMedia;
    await mount(tester,
        padding: const EdgeInsets.only(top: 44, bottom: 34),
        keyboard: 280, home: Builder(builder: (context) {
      childMedia = MediaQuery.of(context);
      return const Scaffold(body: Text('Safe content'));
    }));
    expect(tester.getTopLeft(find.byKey(AppVersionFrame.headerKey)).dy,
        greaterThanOrEqualTo(44));
    expect(childMedia!.padding.top, 0);
    expect(childMedia!.viewInsets.bottom, 280);
    expect(childMedia!.padding.bottom, 34);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'header remains visible on another page and in a dialog at $width',
        (tester) async {
      await mount(tester,
          width: width,
          home: Builder(
              builder: (context) => Scaffold(
                  appBar: AppBar(title: const Text('Home')),
                  body: TextButton(
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (context) => Scaffold(
                                  appBar: AppBar(title: const Text('Details')),
                                  body: TextButton(
                                      onPressed: () => showDialog<void>(
                                          context: context,
                                          builder: (_) => const AlertDialog(
                                              title: Text('Dialog'))),
                                      child: const Text('Open dialog'))))),
                      child: const Text('Open details')))));
      await tester.tap(find.text('Open details'));
      await tester.pumpAndSettle();
      expect(find.text('Details'), findsOneWidget);
      expect(find.text(info.label), findsOneWidget);
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      expect(find.text('Dialog'), findsOneWidget);
      expect(find.text(info.label), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
