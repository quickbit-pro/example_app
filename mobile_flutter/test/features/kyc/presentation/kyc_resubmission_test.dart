import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';
import 'package:mobile_flutter/brands/example/example.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/kyc/application/kyc_providers.dart';
import 'package:mobile_flutter/features/kyc/data/kyc_api.dart';
import 'package:mobile_flutter/features/kyc/presentation/kyc_resubmission_panel.dart';
import 'package:mobile_flutter/features/kyc/presentation/kyc_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

KycDetailedStatus resetStatus([String action = 'RESUBMIT_DOCUMENTS']) =>
    KycDetailedStatus.fromJson({
      'HoppaCardKycApproved': true,
      'CardIssuerKycApproved': true,
      'Interlace': {
        'Status': 'rejected',
        'RequiredAction': action,
        'Reason': 'Please upload a clearer photo.',
        'ResubmissionDocSets': ['IDENTITY', 'SELFIE'],
      },
    });

class _VerificationLauncher extends UrlLauncherPlatform {
  String? url;
  LaunchOptions? options;

  @override
  get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    this.url = url;
    this.options = options;
    return true;
  }
}

void main() {
  test('hosted resume reuses the browser tab without requiring a popup',
      () async {
    final previous = UrlLauncherPlatform.instance;
    final launcher = _VerificationLauncher();
    UrlLauncherPlatform.instance = launcher;
    addTearDown(() => UrlLauncherPlatform.instance = previous);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final link = Uri.parse('https://in.sumsub.com/websdk/p/existing');
    expect(
        await container.read(verificationLinkLauncherProvider)(link), isTrue);
    expect(launcher.url, link.toString());
    expect(launcher.options?.webOnlyWindowName, '_self');
    expect(launcher.options?.mode, PreferredLaunchMode.externalApplication);
  });

  test('reset overrides stale approvals and retains reason and documents', () {
    final status = resetStatus();
    expect(status.hoppaStatus, 'action_required');
    expect(status.isHoppaApproved, isFalse);
    expect(status.isCardIssuerApproved, isFalse);
    expect(status.cardIssuerStatus, 'action_required');
    expect(status.interlaceReason, 'Please upload a clearer photo.');
    expect(status.interlaceResubmissionDocSets, ['IDENTITY', 'SELFIE']);
  });

  test('camel-case payload supports reset and cleared action restores approval',
      () {
    final status = KycDetailedStatus.fromJson({
      'hoppaCardKycApproved': true,
      'interlace': {
        'requiredAction': 'RESUBMIT_DOCUMENTS',
        'reason': 'New photo'
      }
    });
    expect(status.requiresDocumentResubmission, isTrue);
    expect(status.interlaceReason, 'New photo');
    expect(
        KycDetailedStatus.fromJson({
          'HoppaCardKycApproved': true,
          'Interlace': {'RequiredAction': null}
        }).isHoppaApproved,
        isTrue);
    expect(
        resetStatus('CONTACT_SUPPORT').requiresDocumentResubmission, isFalse);
  });

  testWidgets('reset opens secure verification without restarting onboarding',
      (tester) async {
    final requests = <String>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.path);
      expect(options.data, isNull);
      handler.resolve(Response(requestOptions: options, data: {
        'success': true,
        'accessToken': 'https://in.sumsub.com/websdk/p/existing-applicant',
      }));
    }));
    Uri? opened;
    await tester.pumpWidget(ProviderScope(overrides: [
      kycApiProvider.overrideWithValue(KycApi(dio)),
      verificationLinkLauncherProvider.overrideWithValue((uri) async {
        opened = uri;
        return true;
      }),
      kycDetailedStatusProvider.overrideWith((ref) async => resetStatus()),
    ], child: const MaterialApp(home: KycScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Action required'), findsOneWidget);
    expect(find.text('• Identity document'), findsOneWidget);
    expect(
        find.text(
            'Reopen the secure Sumsub page to complete the requested verification steps.'),
        findsOneWidget);
    expect(find.text('Upload requested documents'), findsNothing);
    expect(find.text('Occupation'), findsNothing);
    await tester.tap(find.text('Reopen verification'));
    await tester.pumpAndSettle();
    expect(requests, ['/api/v1/mobile/kyc/resume']);
    expect(opened?.path, '/websdk/p/existing-applicant');
    expect(find.text('Check status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('support-only actions do not offer to reopen verification',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: KycResubmissionPanel(
                    status: resetStatus('CONTACT_SUPPORT'))))));
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Reopen verification'), findsNothing);
  });

  testWidgets('blocked opening keeps a button to reopen the same link',
      (tester) async {
    var requests = 0;
    var launches = 0;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests++;
      handler.resolve(Response(
          requestOptions: options,
          data: {'accessToken': 'https://in.sumsub.com/websdk/p/existing'}));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          kycApiProvider.overrideWithValue(KycApi(dio)),
          verificationLinkLauncherProvider
              .overrideWithValue((_) async => ++launches > 1),
        ],
        child: MaterialApp(
            home:
                Scaffold(body: KycResubmissionPanel(status: resetStatus())))));
    await tester.tap(find.text('Reopen verification'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open verification'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(launches, 2);
  });

  test('resume rejects failed responses and insecure links', () async {
    for (final body in [
      {'success': false, 'message': 'No reset is pending'},
      {'url': 'http://example.com/verification'},
      {'success': true},
    ]) {
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
        handler.resolve(Response(requestOptions: options, data: body));
      }));
      await expectLater(KycApi(dio).resumeVerification(), throwsA(anything));
    }
  });

  test('resume reads the hosted link from the provider response envelope',
      () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      handler.resolve(Response(requestOptions: options, data: {
        'data': {
          'Success': true,
          'AccessToken': 'https://in.sumsub.com/websdk/p/existing-applicant',
        }
      }));
    }));
    expect((await KycApi(dio).resumeVerification()).toString(),
        'https://in.sumsub.com/websdk/p/existing-applicant');
  });

  testWidgets('a failed resume can retry the existing verification flow',
      (tester) async {
    final requests = <String>[];
    final opened = <Uri>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      requests.add(options.path);
      if (requests.length == 1) {
        handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.badResponse,
            response: Response(requestOptions: options, statusCode: 400, data: {
              'message': 'We could not reopen verification. Please try again.',
            })));
        return;
      }
      handler.resolve(Response(requestOptions: options, data: {
        'accessToken': 'https://in.sumsub.com/websdk/p/existing-applicant',
      }));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          kycApiProvider.overrideWithValue(KycApi(dio)),
          verificationLinkLauncherProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
            home:
                Scaffold(body: KycResubmissionPanel(status: resetStatus())))));
    await tester.tap(find.text('Reopen verification'));
    await tester.pumpAndSettle();
    expect(opened, isEmpty);
    expect(find.text('We could not reopen verification. Please try again.'),
        findsOneWidget);
    await tester.tap(find.text('Reopen verification'));
    await tester.pumpAndSettle();
    expect(
        requests, ['/api/v1/mobile/kyc/resume', '/api/v1/mobile/kyc/resume']);
    expect(opened.single.path, '/websdk/p/existing-applicant');
    expect(find.text('We could not reopen verification. Please try again.'),
        findsNothing);
  });

  for (final action in ['CONTACT_SUPPORT', 'RESUBMIT_DATA']) {
    testWidgets('cold $action overrides stale identity approval',
        (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        kycDetailedStatusProvider
            .overrideWith((ref) async => resetStatus(action)),
      ], child: const MaterialApp(home: KycScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Action required'), findsOneWidget);
      expect(find.text('Contact support'), findsOneWidget);
      expect(find.text('KYC status'), findsNothing);
      expect(find.text('Occupation'), findsNothing);
      expect(find.text('Reopen verification'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final issuerStatus in ['pending', 'approved']) {
    testWidgets(
        'cold return with approved identity and $issuerStatus issuer shows status',
        (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        kycDetailedStatusProvider
            .overrideWith((ref) async => KycDetailedStatus.fromJson({
                  'HoppaCardKycApproved': true,
                  'CardIssuerKycApproved': issuerStatus == 'approved',
                  'Interlace': {
                    'Status': issuerStatus,
                    'RequiredAction': null,
                  },
                })),
        occupationCodesProvider.overrideWith((ref) async => []),
        dashboardProvider
            .overrideWith((ref) => Completer<DashboardSnapshot>().future),
        mobileTenantConfigProvider
            .overrideWith((ref) => Completer<MobileTenantConfig>().future),
      ], child: const MaterialApp(home: KycScreen())));
      await tester.pumpAndSettle();
      expect(find.text('KYC status'), findsOneWidget);
      expect(find.text('Occupation'), findsNothing);
      expect(find.text('Reopen verification'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final payload in <String, Map<String, dynamic>>{
    'missing status': {},
    'not started': {
      'HoppaCardKycApproved': false,
      'CardIssuerKycApproved': false,
      'Interlace': {'Status': 'not_started'},
    },
    'unapproved pending status': {
      'HoppaCardKycApproved': false,
      'hoppaStatus': 'pending',
      'CardIssuerKycApproved': false,
    },
  }.entries) {
    testWidgets('cold ${payload.key} keeps the initial form', (tester) async {
      await tester.pumpWidget(ProviderScope(overrides: [
        kycDetailedStatusProvider.overrideWith(
            (ref) async => KycDetailedStatus.fromJson(payload.value)),
        occupationCodesProvider.overrideWith((ref) async => []),
      ], child: const MaterialApp(home: KycScreen())));
      await tester.pumpAndSettle();
      expect(find.byType(Form), findsOneWidget);
      expect(find.text('Verify your identity'), findsOneWidget);
      expect(find.text('KYC status'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final brightness in Brightness.values) {
    testWidgets('resubmission fits a narrow Example screen in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        theme: ThemeData(
            brightness: brightness, extensions: const [ExampleBrand()]),
        home: Scaffold(
            body: ListView(
                children: [KycResubmissionPanel(status: resetStatus())])),
      )));
      expect(find.byType(ExampleGlassButton), findsOneWidget);
      expect(find.text('Reopen verification'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'returning from verification refreshes and clears the reopen action',
      (tester) async {
    var current = resetStatus();
    var reads = 0;
    await tester.pumpWidget(ProviderScope(overrides: [
      kycDetailedStatusProvider.overrideWith((ref) async {
        reads++;
        return current;
      }),
      dashboardProvider
          .overrideWith((ref) => Completer<DashboardSnapshot>().future),
      mobileTenantConfigProvider
          .overrideWith((ref) => Completer<MobileTenantConfig>().future),
    ], child: const MaterialApp(home: KycScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Reopen verification'), findsOneWidget);
    final previousReads = reads;
    current = KycDetailedStatus.fromJson({
      'HoppaCardKycApproved': true,
      'CardIssuerKycApproved': true,
      'Interlace': {'RequiredAction': null},
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(reads, greaterThan(previousReads));
    expect(find.text('Reopen verification'), findsNothing);
    expect(find.text('Occupation'), findsNothing);
    expect(find.text('KYC status'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
