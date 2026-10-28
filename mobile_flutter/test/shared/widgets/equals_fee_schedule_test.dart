import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/shared/widgets/equals_fee_schedule.dart';
import 'package:mobile_flutter/shared/widgets/safeguarding_statement.dart';

void main() {
  testWidgets('loads assigned schedule and displays every fee and frequency',
      (tester) async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      expect(r.path, '/api/v1/mobile/onboarding/fees');
      expect(r.method, 'GET');
      h.resolve(Response(requestOptions: r, data: {
        'success': true,
        'data': {
          'tierLabel': 'Smart',
          'region': 'eu',
          'accountType': 'personal',
          'sections': [
            {
              'title': 'Payments',
              'rows': [
                {
                  'item': 'SEPA Out',
                  'value': '€0.30',
                  'frequency': 'Per payment',
                  'description':
                      "Euro transfers Can be set as 'Free Internal Transfers' In Retool."
                }
              ]
            }
          ]
        }
      }));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [dioProvider.overrideWithValue(dio)],
        child: const MaterialApp(
            home: Scaffold(body: EqualsFeeScheduleDialog()))));
    await tester.pumpAndSettle();
    expect(find.text('Smart schedule'), findsOneWidget);
    expect(find.text('SEPA Out'), findsOneWidget);
    expect(find.text('€0.30'), findsOneWidget);
    expect(find.text('Per payment'), findsOneWidget);
    expect(find.text('Euro transfers'), findsOneWidget);
  });

  testWidgets('no assigned plan does not invent a free tariff', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          equalsFeeScheduleProvider.overrideWith(
              (_) async => {'success': false, 'errorCode': 'NO_TIER_ASSIGNED'})
        ],
        child: const MaterialApp(
            home: Scaffold(body: EqualsFeeScheduleDialog()))));
    await tester.pumpAndSettle();
    expect(
        find.text('Choose a plan to see your fee schedule.'), findsOneWidget);
  });

  testWidgets('safeguarding includes existing dashboard wording and terms link',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showSafeguardingStatement(context,
                        statement: 'Configured regulatory disclosure',
                        termsUrl:
                            'https://docs.hoppa.global/equals_money_gtc_v1.0.pdf'),
                    child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text(equalsFundsNotice), findsOneWidget);
    expect(find.text('Equals Money Terms and Conditions'), findsOneWidget);
    expect(find.text('Configured regulatory disclosure'), findsOneWidget);
  });
}
