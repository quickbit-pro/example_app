import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/onboarding/presentation/personal_onboarding_gate.dart';

void main() {
  Future<void> mount(WidgetTester tester, Dio dio,
      {bool banking = true}) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: MaterialApp(
            home: PersonalOnboardingGate(
                banking: banking,
                child: const Scaffold(body: Text('Saved questionnaire'))))));
    await tester.pumpAndSettle();
  }

  Dio backend(String action, Map<String, dynamic> invite,
      {void Function(RequestOptions)? observe}) {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      observe?.call(r);
      h.resolve(Response(
          requestOptions: r,
          data: r.path.endsWith('/requirements') ? {'nextAction': action} : invite));
    }));
    return dio;
  }

  testWidgets('free tier without invite resumes the saved questionnaire',
      (tester) async {
    await mount(tester, backend('START_KYC2', {'inviteRequired': false}));
    expect(find.text('Saved questionnaire'), findsOneWidget);
    expect(find.text('Review payment'), findsNothing);
  });
  testWidgets('card-only flow does not request a banking invite',
      (tester) async {
    final paths = <String>[];
    await mount(
        tester,
        backend('START_KYC1', {'inviteRequired': true},
            observe: (r) => paths.add(r.path)),
        banking: false);
    expect(find.text('Saved questionnaire'), findsOneWidget);
    expect(paths, ['$personalOnboardingRoot/requirements']);
  });
  testWidgets('no invite shows Request invite and clicking it shows pending approval', (tester) async {
    var requested = false;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      if (request.path.endsWith('/invite/request')) {
        expect(request.method, 'POST');
        requested = true;
      }
      handler.resolve(Response(requestOptions: request, data: request.path.endsWith('/requirements')
          ? {'nextAction': 'START_KYC2'}
          : {'inviteRequired': true, 'inviteStatus': requested ? 'pending' : null}));
    }));
    await mount(tester, dio);
    expect(find.text('Request invite'), findsOneWidget);
    expect(find.text('Verify invite code'), findsNothing);
    await tester.tap(find.text('Request invite'));
    await tester.pumpAndSettle();
    expect(requested, isTrue);
    expect(find.text('Request invite'), findsNothing);
    expect(find.textContaining('waiting for administrator approval'), findsOneWidget);
  });
  for (final status in ['pending', 'denied', 'approved']) {
    testWidgets('$status invite never unlocks banking', (tester) async {
      await mount(
          tester,
          backend(
              'START_KYC2', {'inviteRequired': true, 'inviteStatus': status}));
      expect(find.text('Saved questionnaire'), findsNothing);
      expect(find.text('Equals Money banking invite'), findsOneWidget);
      if (status == 'denied') expect(find.text('Request invite'), findsNothing);
    });
  }
  testWidgets('expired code requests a new approval instead of accepting it',
      (tester) async {
    await mount(
        tester,
        backend('START_KYC2', {
          'inviteRequired': true,
          'inviteStatus': 'approved',
          'canRequestNewCode': true
        }));
    expect(find.text('Request new code'), findsOneWidget);
    expect(find.text('Verify invite code'), findsNothing);
  });
  testWidgets('accepted code refreshes server status and resumes',
      (tester) async {
    var accepted = false;
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.path.endsWith('/verify')) {
        expect(r.data, {'code': 'ABCD1234'});
        accepted = true;
      }
      h.resolve(Response(
          requestOptions: r,
          data: r.path.endsWith('/requirements')
              ? {'nextAction': 'START_KYC2'}
              : {
                  'inviteRequired': !accepted,
                  'inviteStatus': accepted ? 'accepted' : 'approved'
                }));
    }));
    await mount(tester, dio);
    await tester.enterText(find.byType(TextField), 'ABCD1234');
    await tester.pump();
    await tester.tap(find.text('Verify invite code'));
    await tester.pumpAndSettle();
    expect(find.text('Saved questionnaire'), findsOneWidget);
  });
  testWidgets(
      'payment requires explicit terms and does not unlock on confirmation',
      (tester) async {
    final accepted = <bool>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      if (r.path.contains('/checkout')) {
        final consent = r.data['termsAccepted'] == true;
        accepted.add(consent);
        h.resolve(Response(
            requestOptions: r,
            statusCode: consent ? 200 : 428,
            data: consent
                ? {'status': 'processing'}
                : {
                    'error': 'PAYMENT_TERMS_REQUIRED',
                    'amount': 100,
                    'currency': 'EUR',
                    'terms': {
                      'title': 'Opening payment',
                      'intro': 'Opening fee',
                      'checkboxLabel': 'I accept payment terms',
                      'items': []
                    }
                  }));
      } else {
        h.resolve(Response(
            requestOptions: r,
            data: r.path.endsWith('/requirements')
                ? {'nextAction': 'PAY_GATE_1'}
                : {'inviteRequired': false}));
      }
    }));
    await mount(tester, dio);
    await tester.tap(find.text('Review payment'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(accepted, [false]);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue to payment'))
            .onPressed,
        isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Continue to payment'));
    await tester.pumpAndSettle();
    expect(accepted, [false, true]);
    expect(find.text('Confirming your payment'), findsOneWidget);
    expect(find.text('Saved questionnaire'), findsNothing);
    expect(find.text('Review payment'), findsNothing);
  });
  testWidgets('missing server status fails closed', (tester) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(
        onRequest: (r, h) => h.resolve(Response(requestOptions: r, data: {}))));
    await mount(tester, dio);
    expect(find.text('Saved questionnaire'), findsNothing);
    expect(find.text('Check status'), findsOneWidget);
  });
}
