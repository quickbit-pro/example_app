import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/theme/app_theme.dart';
import 'package:mobile_flutter/flavors.dart';
import 'package:mobile_flutter/core/models/equals_money.dart';
import 'package:mobile_flutter/features/platform/presentation/personal_onboarding_localizations.dart';
import 'package:mobile_flutter/shared/widgets/searchable_multi_select_dropdown.dart';
import 'package:mobile_flutter/features/profile/presentation/kyc_status_overview_screen.dart';
import 'package:mobile_flutter/features/platform/presentation/onboarding_banking_screen.dart';
import 'package:mobile_flutter/features/kyc/presentation/kyc_screen.dart';
import 'package:mobile_flutter/features/kyc/presentation/unified_cdd_screen.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';

void main() {
  testWidgets('country names are searchable and selection retains ISO codes',
      (tester) async {
    var selected = <String>[];
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      for (final code in equalsCountryCodes) {
        expect(personalOnboardingCountryLabel(context, code), isNot(code),
            reason: code);
      }
      return SearchableMultiSelectDropdown(
        label: 'Destination countries',
        values: selected,
        options: equalsCountryCodes,
        labelBuilder: (code) => personalOnboardingCountryLabel(context, code),
        onChanged: (value) => selected = value,
      );
    }))));
    final label = tester.getRect(find.text('Destination countries'));
    final hint = tester.getRect(find.text('Select options'));
    expect(label.bottom, lessThan(hint.top));
    await tester.tap(find.text('Select options'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Slovenia');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Slovenia'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply (1)'));
    await tester.pumpAndSettle();
    expect(selected, ['SI']);
  });

  testWidgets(
      'approved questionnaire keeps card answers and readable desktop layout',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final answers = <String, dynamic>{
      'equalsMainPurpose': ['SAVINGS'],
      'equalsSourceOfFunds': ['RECEIVING_FUNDS_FROM_OWN_ACCOUNTS'],
      'equalsDestinationCountries': ['SL'],
      'equalsCurrenciesRequired': ['EUR'],
      'equalsExpectedAnnualVolume': '0-10000',
      'equalsExpectedPayments': '5-10',
      'equalsCardsRequested': true,
      'equalsCardPurposes': ['TRAVEL'],
      'equalsCardAnnualSpend': '0-10000',
      'equalsNumberOfCardsRequired': '0-10',
      'equalsAtmWithdrawalsRequired': false,
    };
    Map<String, dynamic>? saved;
    final dio = onboardingDio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.method == 'PUT') {
        saved = Map<String, dynamic>.from(request.data as Map);
      }
      handler.resolve(Response(requestOptions: request, data: {
        'status': 'approved',
        'banking': true,
        'missingFields': [],
        'submissionRequested': false,
        'answers': answers,
      }));
    }));
    const brand = AppBranding(
        appName: 'Hoppa',
        brandId: 'hoppa',
        primarySeedHex: 'C5E92F',
        accentSeedHex: 'C5E92F',
        loginBackgroundHex: '',
        themeMode: 'dark',
        fontFamily: '',
        logoAsset: '',
        radiusScale: '1',
        supportEmail: '',
        supportPhone: '',
        legalEntity: 'Hoppa');
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
            theme: buildAppThemes(brand).dark,
            home: const UnifiedCddScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Identity verified'), findsOneWidget);
    expect(find.text('Sierra Leone'), findsOneWidget);
    expect(find.text('SL'), findsNothing);
    final fields = find.byType(SearchableMultiSelectDropdown);
    expect(tester.getSize(fields.first).width, lessThanOrEqualTo(760));
    final label = tester.getRect(find.text('Main purposes'));
    final value = tester.getRect(find.text('Savings'));
    expect(label.bottom, lessThan(value.top));
    expect(find.text('Card purposes'), findsOneWidget);
    expect(find.text('Annual card spend'), findsOneWidget);
    expect(find.text('Number of cards required'), findsOneWidget);
    expect(find.text('ATM withdrawals required'), findsOneWidget);
    await tester.ensureVisible(find.text('Save answers'));
    await tester.tap(find.text('Save answers'));
    await tester.pumpAndSettle();
    expect(saved?['equalsCardsRequested'], true);
    expect(saved?['equalsCardPurposes'], ['TRAVEL']);
    expect(saved?['equalsAtmWithdrawalsRequired'], false);
    expect(saved?['equalsDestinationCountries'], ['SL']);
    expect(tester.takeException(), isNull);
  });

  for (final entry in <String, Widget>{
    'status': const HoppaKycStatusScreen(),
    'banking': const OnboardingBankingScreen(),
  }.entries) {
    testWidgets(
        '${entry.key} resumes approved unfinished CDD without another PoA upload',
        (tester) async {
      final paths = <String>[];
      final dio = onboardingDio();
      dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
        paths.add(request.path);
        handler.resolve(Response(requestOptions: request, data: {
          'status': 'approved',
          'banking': true,
          'submissionRequested': false,
          'missingFields': ['equalsQuestionnaire'],
          'answers': {},
        }));
      }));
      await tester.pumpWidget(ProviderScope(overrides: [
        dioProvider.overrideWithValue(dio),
        unifiedCddPreferenceProvider.overrideWith((ref) async => true),
        mobileTenantConfigProvider
            .overrideWith((ref) async => MobileTenantConfig.fromJson({
                  'equalsMoneyEnabled': true,
                  'unifiedCddOnboardingEnabled': true,
                })),
      ], child: MaterialApp(home: entry.value)));
      await tester.pumpAndSettle();
      expect(find.text('Finish your application'), findsOneWidget);
      expect(find.byType(UnifiedCddScreen), findsOneWidget);
      expect(find.text('Proof of address is required.'), findsNothing);
      expect(find.text('In review'), findsNothing);
      expect(paths.where((path) => path.contains('/cdd/session')).length, 1);
      expect(paths.any((path) => path.contains('/equals/onboarding')), isFalse);
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('upstream not found is explained without showing technical JSON', () {
    final error = DioException(
        requestOptions: RequestOptions(path: unifiedCddRoot),
        response: Response(
            requestOptions: RequestOptions(path: unifiedCddRoot),
            statusCode: 404,
            data: {
              'title': 'We could not complete this onboarding step.',
              'detail':
                  '{"title":"Not Found","status":404,"traceId":"internal-trace"}'
            }));
    expect(unifiedCddErrorMessage(error),
        'Verification is temporarily unavailable. Please try again shortly.');
  });

  test('validation messages survive the bridge while technical bodies do not',
      () {
    DioException error(Object detail) => DioException(
        requestOptions: RequestOptions(path: unifiedCddRoot),
        response: Response(
            requestOptions: RequestOptions(path: unifiedCddRoot),
            statusCode: 409,
            data: {'detail': detail}));
    expect(
        unifiedCddErrorMessage(
            error('{"message":"Select a banking plan first."}')),
        'Select a banking plan first.');
    expect(
        unifiedCddErrorMessage(
            error('{"traceId":"internal","title":"Conflict"}')),
        'Could not complete verification. Please retry this step.');
  });

  test('older configurations default to legacy without a preferences request',
      () async {
    final dio = onboardingDio();
    var calls = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      calls++;
      handler
          .resolve(Response(requestOptions: request, data: {'enabled': true}));
    }));
    final container = ProviderContainer(overrides: [
      dioProvider.overrideWithValue(dio),
      mobileTenantConfigProvider
          .overrideWith((ref) async => MobileTenantConfig.fromJson({})),
    ]);
    addTearDown(container.dispose);
    expect(await container.read(unifiedCddPreferenceProvider.future), isFalse);
    expect(calls, 0);
  });

  testWidgets(
      'selected customer starts CDD directly and retry reuses the session',
      (tester) async {
    final paths = <String>[];
    final dio = onboardingDio();
    var attempts = 0;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      if (++attempts == 1) {
        handler.reject(DioException(
            requestOptions: request, type: DioExceptionType.connectionError));
      } else {
        handler.resolve(Response(requestOptions: request, data: {
          'flow': 'unified_cdd',
          'status': 'in_progress',
          'cryptoCard': true,
          'exchange': true,
          'banking': false,
          'missingFields': [],
          'verificationUrl': 'https://verify.example.com/cdd',
          'submissionRequested': false,
        }));
      }
    }));
    await tester.pumpWidget(ProviderScope(overrides: [
      dioProvider.overrideWithValue(dio),
      unifiedCddPreferenceProvider.overrideWith((ref) async => true),
    ], child: const MaterialApp(home: KycScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Could not connect. Please retry this step.'),
        findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Continue verification'), findsOneWidget);
    expect(paths, ['$unifiedCddRoot/session', '$unifiedCddRoot/session']);
    expect(find.text('Start verification'), findsNothing);
  });

  testWidgets('only selected optional provider appears after submission',
      (tester) async {
    final dio = onboardingDio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      handler.resolve(Response(requestOptions: request, data: {
        'status': 'approved',
        'cryptoCard': true,
        'exchange': true,
        'banking': false,
        'missingFields': [],
        'submissionRequested': true,
        'interlace': 'submitted',
        'boomFi': 'reconciliation_required',
        'equalsMoney': 'not_selected',
      }));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const MaterialApp(home: UnifiedCddScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Crypto card'), findsOneWidget);
    expect(find.text('Exchange'), findsOneWidget);
    expect(find.text('Banking'), findsNothing);
    expect(find.text('In progress — we are checking your submission'),
        findsOneWidget);
    expect(find.text('reconciliation_required'), findsNothing);
    expect(find.text('Retry submission'), findsNothing);
  });
  testWidgets('queued application shows progress and cannot be resubmitted',
      (tester) async {
    final dio = onboardingDio();
    final paths = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      paths.add(request.path);
      handler.resolve(Response(requestOptions: request, data: {
        'status': 'approved',
        'banking': true,
        'exchange': true,
        'submissionRequested': true,
        'missingFields': [],
        'interlace': 'not_started',
        'equalsMoney': 'not_started',
        'boomFi': 'disabled_in_staging',
      }));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const MaterialApp(home: UnifiedCddScreen())));
    await tester.pumpAndSettle();
    expect(find.text('In progress'), findsNWidgets(2));
    expect(find.text('Unavailable in staging'), findsOneWidget);
    expect(find.text('not_started'), findsNothing);
    expect(find.text('Retry submission'), findsNothing);
    expect(find.text('Activate selected services'), findsNothing);
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(paths, ['$unifiedCddRoot/session', unifiedCddRoot]);
  });
}

Dio onboardingDio() {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
    if (request.path == '/api/v1/mobile/onboarding/requirements') {
      handler.resolve(Response(requestOptions: request, data: {'nextAction': 'START_KYC2'}));
    } else if (request.path == '/api/v1/mobile/onboarding/invite') {
      handler.resolve(Response(requestOptions: request, data: {'inviteRequired': false}));
    } else { handler.next(request); }
  }));
  return dio;
}
