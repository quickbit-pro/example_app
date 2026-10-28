import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/wallets/presentation/exchange_verification_panel.dart';

const answers = {
  'sdd_country_select': 'SI',
  'investment_citizenship': '82',
  'employment_type_or_status': '15',
  'industry': '51',
  'employment_jurisdiction': 'SI',
  'acting_capacity': '156',
  'annual_income': '75',
  'expected_deposit_one_year': '83',
  'hnwi_str': '78',
  'source_of_funds': '66',
  'source_of_funds_of_country': 'SI',
  'source_of_wealth_of_country': 'SI',
};

class SavedAnswersApi extends MobilePlatformApi {
  SavedAnswersApi({this.complete = true, this.timeout = false, this.kycLevel = 'CDD'}) : super(Dio());
  final bool complete, timeout;
  final String kycLevel;
  int directCalls = 0, manualCalls = 0;
  Map<String, String>? submitted;
  @override
  Future<Map<String, dynamic>> getExchangeVerification() async => {
        'eligible': true,
        'status': 'approved',
        'tier': kycLevel.toLowerCase(),
        'hasProviderAccount': directCalls > 0 && !timeout,
        if (directCalls > 0 && !timeout) 'provider': {'kycStatus': 'pending'},
      };
  @override
  Future<Map<String, dynamic>> getExchangeApplication() async => {
        'supported': true,
        'readyToSubmit': complete,
        'kycLevel': kycLevel,
        'answers': kycLevel == 'SDD'
            ? {for (final entry in answers.entries.take(6)) entry.key: entry.value,
                if (!complete) 'acting_capacity': ''}
            : {...answers, if (!complete) 'annual_income': ''},
        'missingFields': complete ? [] : [kycLevel == 'SDD' ? 'acting_capacity' : 'annual_income'],
      };
  @override
  Future<Map<String, dynamic>> submitExchangeApplicationFromSumsub() async {
    directCalls++;
    if (timeout) {
      throw DioException(
          requestOptions: RequestOptions(path: '/application'),
          type: DioExceptionType.receiveTimeout);
    }
    return {};
  }

  @override
  Future<Map<String, dynamic>> submitExchangeApplication(
      Map<String, String> value) async {
    manualCalls++;
    submitted = value;
    return {};
  }
}

Future<void> host(WidgetTester tester, SavedAnswersApi api) async {
  tester.view.physicalSize = const Size(1000, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
      overrides: [mobilePlatformApiProvider.overrideWithValue(api)],
      child: const MaterialApp(
          home: Scaffold(body: ExchangeVerificationPanel()))));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('completed Sumsub declarations submit once without another form',
      (tester) async {
    final api = SavedAnswersApi();
    await host(tester, api);
    expect(api.directCalls, 0);
    await tester.tap(find.text('Activate Exchange'));
    await tester.pumpAndSettle();
    expect(api.directCalls, 1);
    expect(api.manualCalls, 0);
    expect(find.byType(ExchangeApplicationDialog), findsNothing);
    expect(find.text('Activate Exchange'), findsNothing);
    expect(find.textContaining('under review'), findsOneWidget);
  });
  testWidgets(
      'partial declarations ask only for missing fields and preserve saved values',
      (tester) async {
    final api = SavedAnswersApi(complete: false);
    await host(tester, api);
    await tester.tap(find.text('Activate Exchange'));
    await tester.pumpAndSettle();
    expect(find.byType(ExchangeApplicationDialog), findsOneWidget);
    expect(find.text('Annual income (EUR)'), findsOneWidget);
    expect(find.text('Country of residence'), findsNothing);
    expect(find.text('Employment status'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('€10,000–€50,000').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(api.directCalls, 0);
    expect(api.manualCalls, 1);
    expect(api.submitted, answers);
    expect(tester.takeException(), isNull);
  });
  testWidgets('SDD corrections submit without CDD financial declarations', (tester) async {
    final api = SavedAnswersApi(complete: false, kycLevel: 'SDD');
    await host(tester, api);
    await tester.tap(find.text('Activate Exchange'));
    await tester.pumpAndSettle();
    expect(find.text('Annual income (EUR)'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Myself').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit application'));
    await tester.pumpAndSettle();
    expect(api.manualCalls, 1);
    expect(api.submitted, {for (final entry in answers.entries.take(6)) entry.key: entry.value});
    expect(tester.takeException(), isNull);
  });
  testWidgets('uncertain direct submission blocks duplicate activation',
      (tester) async {
    final api = SavedAnswersApi(timeout: true);
    await host(tester, api);
    await tester.tap(find.text('Activate Exchange'));
    await tester.pumpAndSettle();
    expect(api.directCalls, 1);
    expect(find.textContaining('We could not confirm'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Activate Exchange'))
            .onPressed,
        isNull);
    expect(find.textContaining('DioException'), findsNothing);
  });
}
