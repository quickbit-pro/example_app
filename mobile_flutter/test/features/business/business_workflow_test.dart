import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/application/banking_providers.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/business/presentation/business_gate.dart';

void main() {
  testWidgets('a selected plan still waits for backend payment confirmation',
      (tester) async {
    var state = 'SELECT_TIER';
    final checkoutConsents = <bool>[];
    const prefix = '/api/v1/mobile/business-onboarding/workflow';
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(
        onRequest: (request, handler) {
          Object response;
          switch ((request.method, request.path)) {
            case ('GET', prefix):
              response = {
                'state': state,
                'tiers': [
                  {'id': 12, 'name': 'Standard'}
                ],
                'payments': [
                  {
                    'id': 'payment-1',
                    'purpose': 'INITIAL',
                    'status': 'DUE',
                    'amount': 100,
                    'currency': 'GBP',
                  },
                ],
              };
            case ('POST', '$prefix/tier'):
              expect(request.data, {'tierId': 12});
              state = 'PAYMENT_REQUIRED';
              response = {'success': true};
            case ('POST', '$prefix/payments/payment-1/checkout'):
              final accepted = request.data['termsAccepted'] as bool;
              checkoutConsents.add(accepted);
              response = accepted
                  ? {'status': 'PAID'}
                  : {
                      'error': 'PAYMENT_TERMS_REQUIRED',
                      'terms': {
                        'title': 'Payment terms',
                        'items': ['An opening fee applies.'],
                        'checkboxLabel': 'I accept the test payment terms',
                      },
                    };
            default:
              fail('Unexpected request ${request.method} ${request.path}');
          }
          handler.resolve(
            Response(requestOptions: request, statusCode: 200, data: response),
          );
        },
      ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mobileBankingApiProvider.overrideWithValue(MobileBankingApi(dio)),
        ],
        child: const MaterialApp(
          home: BusinessGate(child: Text('KYB form')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('KYB form'), findsNothing);
    await tester.tap(find.text('Select Standard'));
    await tester.pumpAndSettle();
    expect(find.text('KYB form'), findsNothing);

    await tester.tap(find.text('Pay securely with Stripe'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final confirm = find.widgetWithText(FilledButton, 'Continue to Stripe');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(checkoutConsents, [false]);
    await tester.tap(find.text('I accept the test payment terms'));
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(checkoutConsents, [false, true]);
    expect(find.text('KYB form'), findsNothing);

    state = 'DRAFT';
    await tester.tap(find.text('Refresh status'));
    await tester.pumpAndSettle();
    expect(find.text('KYB form'), findsOneWidget);
  });
}
