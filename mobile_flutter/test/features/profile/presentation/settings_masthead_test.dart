import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/application/biometric_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:local_auth/local_auth.dart' show BiometricType;
import 'package:mobile_flutter/features/auth/data/biometric_authenticator.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/profile/presentation/profile_screen.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Settings is the screen where Example's voice has to arrive without costing
/// anyone a tap. These tests pin the three things that carry it — the
/// masthead's type, the depth it is allowed to spend, and the protection
/// meter's arithmetic — plus the one rule that outranks all of them: a
/// white-label tenant must not see any of it.
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

const _profile = UserProfile(
  id: 'u1',
  name: 'Naem Kaya',
  email: 'naem@example.com',
  accountType: 'personal',
  kycStatus: 'approved',
  businessStatus: 'not_started',
  onboardingStatus: 'complete',
);

const _security = AccountSecurity(
  twoFactorEnabled: true,
  recoveryCodesRemaining: 8,
  duressPasswordSet: false,
);

const _capable = BiometricCapability(
  available: true,
  types: [BiometricType.face],
  reason: BiometricUnavailableReason.none,
);

const _incapable = BiometricCapability(
  available: false,
  types: [],
  reason: BiometricUnavailableReason.unsupportedDevice,
);

const _enrolled = BiometricEnrollment(
  enabled: true,
  hasToken: true,
  email: 'naem@example.com',
  userName: 'Naem Kaya',
  refreshToken: 'x',
);

const _notEnrolled = BiometricEnrollment(
  enabled: false,
  hasToken: false,
  email: 'naem@example.com',
  userName: 'Naem Kaya',
  refreshToken: '',
);

class _SignedInSettingsAuth extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
      session: AuthSession(
          accessToken: 'test',
          refreshToken: 'test',
          userName: 'Naem Kaya',
          email: 'naem@example.com'));
}

class _ResetSettingsAuth extends _SignedInSettingsAuth {
  int resets = 0;
  @override
  Future<void> logout({bool clearBiometric = false}) async {
    expect(clearBiometric, isTrue);
    resets++;
  }
}

List<Override> _overrides({
  AuthController? auth,
  AppBranding branding = _exampleBranding,
  UserProfile profile = _profile,
  AsyncValue<AccountSecurity> security = const AsyncValue.data(_security),
  BiometricCapability capability = _capable,
  BiometricEnrollment enrollment = _enrolled,
  Future<AccountSecurity> Function()? securityFuture,
  bool dashboardLoading = false,
}) =>
    [
      authControllerProvider
          .overrideWith(() => auth ?? _SignedInSettingsAuth()),
      appConfigProvider.overrideWithValue(
        AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'https://example.invalid',
          branding: branding,
        ),
      ),
      mobileTenantConfigProvider.overrideWith(
        (ref) async => MobileTenantConfig.fromJson(const {}),
      ),
      dashboardProvider.overrideWith(
        (ref) => dashboardLoading
            // Never completes: the skeleton is up and stays up.
            ? Completer<DashboardSnapshot>().future
            : Future<DashboardSnapshot>.value(
                DashboardSnapshot(
                  profile: profile,
                  accounts: const [],
                  cards: const [],
                  transactions: const [],
                  onboarding: const [],
                ),
              ),
      ),
      currentTierProvider.overrideWith((ref) async => null),
      accountSecurityProvider.overrideWith(
        (ref) => securityFuture != null
            ? securityFuture()
            : security.when(
                data: (value) => Future<AccountSecurity>.value(value),
                // A never-completing future is exactly the loading case: the
                // screen has asked and has not been told.
                loading: () => Completer<AccountSecurity>().future,
                error: (error, stackTrace) =>
                    Future<AccountSecurity>.error(error, stackTrace),
              ),
      ),
      biometricCapabilityProvider.overrideWith((ref) async => capability),
      biometricEnrollmentProvider.overrideWith((ref) async => enrollment),
    ];

Widget _host({
  required double width,
  required Brightness brightness,
  AppBranding branding = _exampleBranding,
  List<Override> overrides = const [],
  double height = 900,
  Key? key,
}) {
  final themes = buildAppThemes(branding);
  return ProviderScope(
    // Pumping a second `_host` into a running test updates the element that
    // is already there rather than building a new one, and the container it
    // holds keeps the futures its overrides have already produced: a provider
    // left on a never-completing future stays on it, so the screen never
    // leaves the state it was pumped in. Measured, not assumed — pump the
    // loading overrides, then the loaded ones with no key, and "Naem Kaya" is
    // still absent while the skeleton's semantics node is still up. A
    // different key forces a new element and a new container. Any test that
    // pumps two states has to pass one.
    key: key,
    overrides: overrides.isEmpty ? _overrides(branding: branding) : overrides,
    child: MaterialApp(
      theme: brightness == Brightness.dark ? themes.dark : themes.light,
      themeMode: ThemeMode.light,
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: const ProfileScreen(),
      ),
    ),
  );
}

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

/// WCAG contrast of [foreground] — alpha and all — composited onto the
/// opaque [background] it is painted on.
double _contrast(Color foreground, Color background) {
  final front = Color.alphaBlend(foreground, background).computeLuminance();
  final back = background.computeLuminance();
  final lighter = front > back ? front : back;
  final darker = front > back ? back : front;
  return (lighter + 0.05) / (darker + 0.05);
}

/// Every [BoxDecoration] on the page that paints a shadow, once each.
///
/// `DecoratedBox` is the whole population: a `Container` given a decoration
/// builds one, so `tester.allWidgets` yields the container *and* the box, and
/// counting both would report a single shadowed container twice — enough to
/// break the Twilight `hasLength(1)` on a page that had not changed.
/// Elevation is the other way to cast a shadow and no `BoxDecoration` can
/// carry it, so [_elevations] covers that separately.
List<BoxDecoration> _shadowed(WidgetTester tester) => [
      for (final widget in tester.allWidgets)
        if (widget is DecoratedBox && widget.decoration is BoxDecoration)
          widget.decoration as BoxDecoration,
    ].where((decoration) => decoration.boxShadow?.isNotEmpty == true).toList();

/// Every elevation the page asks the compositor for. A `Material` — and so a
/// `Card`, which is one — lifts through a [PhysicalShape] rather than through
/// a `BoxDecoration`, so a lift added that way is invisible to [_shadowed] and
/// shows up only here. The depth tests require this to hold nothing above
/// zero, which is the half of "nowhere else" they used to only assert.
List<double> _elevations(WidgetTester tester) => [
      for (final widget in tester.allWidgets)
        if (widget is PhysicalModel)
          widget.elevation
        else if (widget is PhysicalShape)
          widget.elevation,
    ].where((elevation) => elevation > 0).toList();

/// The protection meter's four segments, read off the decorations they are
/// painted with. The 2.5 radius is the meter's own and nothing else on the
/// page uses it.
List<BoxDecoration> _segments(WidgetTester tester) => [
      for (final widget in tester.allWidgets)
        if (widget is DecoratedBox &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).borderRadius ==
                const BorderRadius.all(Radius.circular(2.5)))
          widget.decoration as BoxDecoration,
    ];

/// Every list group on the page, in the order they come down it.
List<Rect> _groupRects(WidgetTester tester) {
  final groups = find.byType(ExampleListGroup);
  return [
    for (var i = 0; i < groups.evaluate().length; i++)
      tester.getRect(groups.at(i)),
  ];
}

/// The masthead plate: the one box at the hero radius that carries a shadow.
final Finder _plate = find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      (widget.decoration as BoxDecoration).borderRadius ==
          BorderRadius.circular(AppRadii.xl) &&
      (widget.decoration as BoxDecoration).boxShadow?.isNotEmpty == true,
);

void main() {
  for (final branding in [_exampleBranding, _tenantBranding]) {
    for (final capable in [true, false]) {
      testWidgets(
          '${branding.appName} can reset broken biometrics, available=$capable',
          (tester) async {
        final auth = _ResetSettingsAuth();
        await _pumpAt(
            tester,
            _host(
                width: 390,
                brightness: Brightness.dark,
                branding: branding,
                overrides: [
                  ..._overrides(
                      branding: branding,
                      auth: auth,
                      capability: capable ? _capable : _incapable),
                  biometricAuthenticatorProvider.overrideWith((ref) =>
                      throw StateError(
                          'Reset must not request the broken passkey')),
                ]),
            width: 390);
        final toggle = find.byType(Switch).first;
        await tester.scrollUntilVisible(toggle, 300,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(find.text('Turn off and sign out'), findsOneWidget);
        expect(auth.resets, 0);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(auth.resets, 0);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Turn off and sign out'));
        await tester.pumpAndSettle();
        expect(auth.resets, 1);
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final branding in [_exampleBranding, _tenantBranding]) {
    testWidgets('${branding.brandId} settings opens all shared legal PDFs',
        (tester) async {
      await _pumpAt(tester,
          _host(width: 390, brightness: Brightness.dark, branding: branding),
          width: 390);
      await tester.scrollUntilVisible(find.text('Legal documents'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Legal documents'));
      await tester.pumpAndSettle();
      expect(find.text('E-Sign Agreement / GLBA Disclosure'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      expect(find.textContaining('General Terms (US)'), findsOneWidget);
      expect(find.text('Additional Acknowledgements when Onboarding'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('personal details keeps a long email readable and aligned',
      (tester) async {
    const profile = UserProfile(
        id: 'email-test',
        name: 'Tester',
        email: 'long.email.address.for.testing@example.test',
        accountType: 'personal',
        kycStatus: 'approved',
        businessStatus: 'not_started',
        onboardingStatus: 'complete');
    await _pumpAt(
        tester,
        _host(
            width: 320,
            brightness: Brightness.dark,
            overrides: _overrides(profile: profile)),
        width: 320);
    await tester.tap(find.bySemanticsLabel(RegExp('open personal details')));
    await tester.pumpAndSettle();
    final rowFinder = find.widgetWithText(ExampleRow, profile.email);
    expect(rowFinder, findsOneWidget);
    final row = tester.widget<ExampleRow>(rowFinder);
    expect(row.titleMaxLines, isNull);
    final title =
        find.descendant(of: rowFinder, matching: find.text(profile.email));
    final label = find.descendant(of: rowFinder, matching: find.text('Email'));
    expect(tester.getTopLeft(title).dx, tester.getTopLeft(label).dx);
    expect(tester.takeException(), isNull);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('Example settings masthead', () {
    for (final width in const [375.0, 393.0, 834.0, 1440.0]) {
      for (final brightness in Brightness.values) {
        testWidgets('lays out at $width in $brightness', (tester) async {
          await _pumpAt(
            tester,
            _host(width: width, brightness: brightness),
            width: width,
          );

          // A RenderFlex overflow surfaces here, so this is the 375/393
          // no-overflow guarantee as much as it is a smoke test.
          expect(tester.takeException(), isNull);
          expect(find.text('Naem Kaya'), findsOneWidget);
          expect(find.text('naem@example.com'), findsOneWidget);
          expect(find.text('PROTECTION'), findsOneWidget);
        });
      }
    }

    testWidgets('announces the tier and the email, not only the name',
        (tester) async {
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.dark),
        width: 375,
      );

      // `ExamplePressable` excludes its whole subtree once it is handed a
      // label, so the label is the only place the tier pill and the email can
      // be spoken — and neither is stated anywhere else on this screen.
      // Labelling the zone with the name alone deleted both from the tree.
      final identity = find.bySemanticsLabel(RegExp('open personal details'));
      expect(identity, findsOneWidget);
      expect(
        tester.getSemantics(identity).label,
        'Naem Kaya, Member, naem@example.com, open personal details',
      );
      // And the meter is still its own node rather than a second sentence
      // tacked onto the button, which is the other half of the same rule.
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('^Protection,')))
            .label,
        startsWith('Protection, 3 of 4 active.'),
      );
    });

    testWidgets('states the name at the top of the type scale', (tester) async {
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.dark),
        width: 375,
      );

      // The screen's complaint was that nothing outranked the 22 px page
      // title. The name is `headlineMedium`, which is the step above it; if
      // this ever falls back to a title role the masthead is gone.
      final name = tester.widget<Text>(find.text('Naem Kaya'));
      expect(name.style?.fontSize, 26);
      expect(name.style?.fontWeight, FontWeight.w700);
    });

    testWidgets('spends its lift on the plate and nowhere else in Twilight',
        (tester) async {
      // 2400 tall rather than the 900 this used to run at. "Nowhere else" is
      // a claim about the whole page, and at 900 the lazy list has built four
      // of the five groups and never reaches the sign-out group at all, so a
      // lift added to that group would have been invisible to this test.
      // Measured both ways: 5 groups built at 2400 against 4 at 900, and at
      // 900 'Sign out' is absent even from a finder that does not skip
      // offstage. The two assertions under the pump keep that honest.
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.dark, height: 2400),
        width: 375,
        height: 2400,
      );
      expect(find.byType(ExampleListGroup), findsNWidgets(5));
      expect(find.text('Sign out'), findsOneWidget);

      // Hierarchy is the point: on night the plate is the only box on the
      // page that casts anything at all, at the hero radius, while every list
      // group below it rests at the card radius on a surface step.
      final shadowed = _shadowed(tester);
      expect(shadowed, hasLength(1));
      expect(shadowed.single.boxShadow, same(ExampleShadows.lift));
      expect(shadowed.single.borderRadius, BorderRadius.circular(AppRadii.xl));
      // "Nowhere else" has to include the other way of casting a shadow.
      expect(_elevations(tester), isEmpty);
    });

    testWidgets('spends its lift on the plate and nowhere else in Pearl',
        (tester) async {
      // 2400 for the same reason as Twilight: at 900 this saw four of the
      // five groups and never the sign-out group.
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.light, height: 2400),
        width: 375,
        height: 2400,
      );
      expect(find.byType(ExampleListGroup), findsNWidgets(5));
      expect(find.text('Sign out'), findsOneWidget);

      // The daylight claim is narrower and worth stating exactly rather than
      // borrowing Twilight's. On paper a white group on near-white paper has
      // no surface step to separate it, so every group carries the resting
      // ambient: six shadowed boxes, not one — the plate and the five groups,
      // counted below rather than only claimed here. What still holds, and
      // what the masthead's hierarchy actually rests on, is that exactly one
      // of them is *lifted*, and it is the plate at the hero radius.
      final shadowed = _shadowed(tester);
      expect(shadowed, hasLength(6));
      final lifted = shadowed
          .where((decoration) =>
              identical(decoration.boxShadow, ExampleShadows.liftLight))
          .toList();
      expect(lifted, hasLength(1));
      expect(lifted.single.borderRadius, BorderRadius.circular(AppRadii.xl));
      expect(
        shadowed.where((decoration) => !identical(decoration, lifted.single)),
        everyElement(
          isA<BoxDecoration>().having(
            (decoration) => decoration.boxShadow,
            'boxShadow',
            same(ExampleShadows.ambientLight),
          ),
        ),
      );
      expect(_elevations(tester), isEmpty);
    });

    testWidgets('labels every section in the eyebrow register', (tester) async {
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.dark),
        width: 375,
      );

      for (final label in const ['ACCOUNT', 'SECURITY', 'PREFERENCES']) {
        await tester.scrollUntilVisible(find.text(label), 200);
        expect(find.text(label), findsOneWidget);
      }
      // The last group is below the fold at 375 x 900, so it has to be
      // scrolled to rather than found — which is itself worth pinning: the
      // rest of the page keeps the rhythm the masthead sets.
      await tester.scrollUntilVisible(find.text('HELP & LEGAL'), 400);
      expect(find.text('HELP & LEGAL'), findsOneWidget);
      // The 15.5 px section title it replaced would still read as sentence
      // case; catching that is the whole point of asserting both.
      expect(find.text('Account'), findsNothing);
      expect(find.text('Security'), findsNothing);
    });
  });

  group('security state', () {
    testWidgets('the meter never outlives the rows', (tester) async {
      var fail = false;
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(
            securityFuture: () async {
              if (fail) throw Exception('refetch failed');
              return _security;
            },
          ),
        ),
        width: 375,
      );

      expect(find.text('3 of 4 active'), findsOneWidget);

      // Exactly what `security_sheets.dart` does after every change it makes.
      // Riverpod keeps the previous value across the failure, and that is the
      // whole trap: `valueOrNull` goes on returning "3 of 4 active" under two
      // rows that have already fallen back to "Unavailable".
      fail = true;
      ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
        listen: false,
      ).invalidate(accountSecurityProvider);
      await tester.pumpAndSettle();

      // Two rows and the meter, all saying the one thing the screen knows.
      expect(find.text('Unavailable'), findsNWidgets(3));
      expect(find.textContaining('active'), findsNothing);
    });

    testWidgets('keeps existing security sheet actions after a failed refetch',
        (tester) async {
      var fail = false;
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(
            securityFuture: () async {
              if (fail) throw Exception('refetch failed');
              return _security;
            },
          ),
        ),
        width: 375,
      );

      int chevrons() => find
          .byWidgetPredicate((widget) =>
              widget is Icon && widget.icon == Icons.chevron_right_rounded)
          .evaluate()
          .length;
      final live = chevrons();

      // The control: with the summary read, the row opens its sheet. Two-step
      // is ON in this fixture, so the sheet it opens is the disable flow.
      await tester.tap(find.text('Two-step verification'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      fail = true;
      ProviderScope.containerOf(
        tester.element(find.byType(ProfileScreen)),
        listen: false,
      ).invalidate(accountSecurityProvider);
      await tester.pumpAndSettle();
      expect(find.text('Unavailable'), findsNWidgets(3));
      // The design update retains the local app's actions and its cached
      // security state. A failed refresh changes the status presentation,
      // while the known account still opens the same disable/setup flows.
      expect(chevrons(), live);
      await tester.tap(find.text('Two-step verification'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Turn off two-step verification'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duress password'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.text('Set a duress password'), findsOneWidget);
      Navigator.of(tester.element(find.byType(ProfileScreen))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      // The row next to them does not depend on the read, and stays live.
      await tester.tap(find.text('Change password'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('protection meter', () {
    testWidgets('counts what is on, out of what this device offers',
        (tester) async {
      await _pumpAt(
        tester,
        _host(width: 375, brightness: Brightness.dark),
        width: 375,
      );

      // The native mock offers face authentication. Preserve that label
      // while counting verified identity, enrolled biometrics and enabled 2FA.
      expect(find.text('Face ID'), findsOneWidget);
      expect(find.text('Passkey'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('Face ID on')), findsOneWidget);
      expect(find.text('3 of 4 active'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Duress password off')),
        findsOneWidget,
      );
    });

    testWidgets('says so when everything is on', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(
            security: const AsyncValue.data(
              AccountSecurity(
                twoFactorEnabled: true,
                recoveryCodesRemaining: 8,
                duressPasswordSet: true,
              ),
            ),
          ),
        ),
        width: 375,
      );

      expect(find.text('All 4 active'), findsOneWidget);
    });

    testWidgets('omits unsupported biometrics from the protection count',
        (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(
            capability: _incapable,
            enrollment: _notEnrolled,
          ),
        ),
        width: 375,
      );

      // Two of three, not two of four: a defence the switch will not let you
      // turn on is not a defence you are missing.
      expect(find.text('2 of 3 active'), findsOneWidget);
      expect(find.textContaining('of 4'), findsNothing);
    });

    // The version of this test that shipped first asserted only that the four
    // segments resolved to two colours with three sharing one of them — which
    // the regression it was written to catch (an unlit track at the level-2
    // surface step, 1.13:1 on the plate) would have passed unchanged. A
    // daylight test has to measure daylight, so this one computes the ratios
    // and pins the exact numbers the component's doc states.
    for (final (brightness, fill, edge) in const [
      (Brightness.light, 1.72, 3.17),
      (Brightness.dark, 2.00, 4.13),
    ]) {
      testWidgets('draws a countable bar in $brightness', (tester) async {
        await _pumpAt(
          tester,
          _host(width: 375, brightness: brightness),
          width: 375,
        );

        // Lit and unlit are told apart by the edge, not by position: the
        // first segment is only the lit colour because this fixture happens
        // to have identity verification approved, and a test that reads
        // `segments.first` silently inverts when the fixture changes.
        final segments = _segments(tester);
        final unlit =
            segments.where((decoration) => decoration.border != null).toList();
        final lit =
            segments.where((decoration) => decoration.border == null).toList();
        expect(segments, hasLength(4));
        expect(lit, hasLength(3));
        expect(unlit, hasLength(1));

        final plate = ExampleSurface.forBrightness(brightness, 1);
        // The denominator has to be visible before the numerator means
        // anything, so both the unlit fill and its edge are measured against
        // the plate they sit on, and the edge clears the 3:1 boundary floor.
        expect(_contrast(unlit.single.color!, plate), closeTo(fill, .02));
        expect(
          _contrast((unlit.single.border! as Border).top.color, plate),
          closeTo(edge, .02),
        );
        expect(_contrast(lit.first.color!, plate), greaterThan(3));
      });
    }

    testWidgets('reports unknown rather than guessing zero', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(security: const AsyncValue.loading()),
        ),
        width: 375,
      );

      // Two of the four are still in flight, so the meter states that instead
      // of painting them off — the same three-state contract the row
      // subtitles already keep.
      expect(find.text('Checking…'), findsWidgets);
      expect(find.textContaining('active'), findsNothing);
    });
  });

  group('loading skeleton', () {
    for (final brightness in Brightness.values) {
      testWidgets('is the loaded page, group for group, in $brightness',
          (tester) async {
        const width = 375.0;
        // Tall enough that the whole column is laid out rather than lazily
        // built, so the last group's position is a real measurement and not a
        // viewport artefact.
        const height = 2400.0;

        await _pumpAt(
          tester,
          _host(
            width: width,
            brightness: brightness,
            height: height,
            overrides: _overrides(dashboardLoading: true),
            key: const ValueKey('loading'),
          ),
          width: width,
          height: height,
        );

        // The skeleton draws the meter by rendering the meter, on the reading
        // the screen is about to have. This is both the fixture for the
        // measurements below and the proof of that.
        expect(find.text('PROTECTION'), findsOneWidget);
        expect(find.text('Checking…'), findsOneWidget);
        expect(find.text('Naem Kaya'), findsNothing);

        final loadingPlate = tester.getRect(_plate);
        final loadingGroups = _groupRects(tester);
        expect(loadingGroups, hasLength(5));

        // A *different* key, and the two assertions under the pump are what
        // make this a comparison rather than a tautology: the same key would
        // reuse the element, and Riverpod would hand the reused container's
        // dashboard provider back on its never-completing future, leaving the
        // skeleton up and measuring it against itself.
        await _pumpAt(
          tester,
          _host(
            width: width,
            brightness: brightness,
            height: height,
            key: const ValueKey('loaded'),
          ),
          width: width,
          height: height,
        );
        expect(find.text('Naem Kaya'), findsOneWidget);
        expect(find.bySemanticsLabel('Loading settings'), findsNothing);

        final loadedPlate = tester.getRect(_plate);
        final loadedGroups = _groupRects(tester);

        // "Nothing changes position when the data lands" is a claim about
        // pixels, so it is checked in pixels. It was out by roughly 160-175 pt
        // before this: Security drawn at five rows against six, Preferences at
        // two rows against a row, a theme row and the specimen strip, no
        // sign-out group at all, and a plate about 10 pt short because the
        // skeleton's bands reserved the blocks they paint instead of the line
        // boxes of the strings they stand in for.
        expect(loadedPlate.top, closeTo(loadingPlate.top, .01));
        expect(loadedPlate.height, closeTo(loadingPlate.height, .01));
        expect(loadedGroups, hasLength(loadingGroups.length));
        for (var i = 0; i < loadedGroups.length; i++) {
          expect(
            loadedGroups[i].top,
            closeTo(loadingGroups[i].top, .01),
            reason: 'group $i moved when the data landed',
          );
          expect(
            loadedGroups[i].height,
            closeTo(loadingGroups[i].height, .01),
            reason: 'group $i changed height when the data landed',
          );
        }
      });
    }

    testWidgets('reserves every row at the height that row lands at',
        (tester) async {
      // The number the skeleton has to know: a switch keeps a 48 pt tap
      // target, which clears `ExampleRow`'s 56 pt floor once the row's 8 pt
      // padding is added, so the two rows that carry one are 64 and every
      // other row is 56. Drawing them all at 56 is 8 pt lost in Security and
      // 8 more in Preferences.
      //
      // Reading those heights off the loaded page alone characterises the
      // number without guarding it — nothing in the skeleton has to change
      // for that to keep passing, and setting the skeleton's switch row back
      // to 56 leaves it green. So both halves are measured and compared
      // element by element, in order: a switch reserved in the wrong slot
      // fails here even though the group totals still match and the
      // group-for-group test stays green.
      const width = 375.0;
      const height = 2400.0;

      await _pumpAt(
        tester,
        _host(
          width: width,
          brightness: Brightness.dark,
          height: height,
          overrides: _overrides(dashboardLoading: true),
          key: const ValueKey('loading'),
        ),
        width: width,
        height: height,
      );

      // The settings rows are the only skeletons on this page drawn at a
      // 34 pt avatar: the plate's is 48, and every band is a line, at 0.
      final reserved = find.byWidgetPredicate(
        (widget) => widget is ExampleSkeleton && widget.avatarSize == 34,
      );
      final reservedHeights = [
        for (var i = 0; i < reserved.evaluate().length; i++)
          tester.getSize(reserved.at(i)).height,
      ];

      await _pumpAt(
        tester,
        _host(
          width: width,
          brightness: Brightness.dark,
          height: height,
          key: const ValueKey('loaded'),
        ),
        width: width,
        height: height,
      );
      expect(find.text('Naem Kaya'), findsOneWidget);

      final rows = find.byType(ExampleRow);
      final loadedHeights = [
        for (var i = 0; i < rows.evaluate().length; i++)
          tester.getSize(rows.at(i)).height,
        // Sign out is a destructive row rather than a `ExampleRow`, and it is
        // the only child of the last group, so that group is its height.
        _groupRects(tester).last.height,
      ];

      // Pinned so an empty predicate cannot pass this by matching nothing on
      // both sides: fourteen navigable rows and sign out, two of which carry a
      // switch.
      expect(loadedHeights, hasLength(15));
      expect(loadedHeights.where((height) => height == 64), hasLength(2));
      expect(reservedHeights, loadedHeights);
    });

    testWidgets('follows the rewards flag the loaded page reads',
        (tester) async {
      // The tenant config resolves independently of the dashboard, so the
      // Account group is drawn at the count that is actually coming. With
      // referrals off that is three rows, and the whole column below depends on
      // it being the same three.
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          overrides: _overrides(dashboardLoading: true),
        ),
        width: 375,
      );

      final account = tester.getRect(find.byType(ExampleListGroup).first);
      expect(account.height, closeTo(56 * 3 + 2, .01));
    });
  });

  group('white-label', () {
    testWidgets('sees none of it', (tester) async {
      await _pumpAt(
        tester,
        _host(
          width: 375,
          brightness: Brightness.dark,
          branding: _tenantBranding,
        ),
        width: 375,
      );

      expect(tester.takeException(), isNull);
      // Every element of this pass lives inside `_ExampleProfileContent`,
      // which a tenant never reaches.
      expect(find.text('PROTECTION'), findsNothing);
      expect(find.text('ACCOUNT'), findsNothing);
      expect(find.byType(ExampleListGroup), findsNothing);
      expect(find.text('Account'), findsOneWidget);
    });
  });
}
