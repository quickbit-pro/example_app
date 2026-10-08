import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mobile_flutter/features/assistant/data/assistant_preferences_api.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_departure.dart';
import 'package:mobile_flutter/features/assistant/domain/assistant_preferences.dart';

void main() {
  test(
      'preferences load uses a fixed private read and drops extra profile data',
      () async {
    final dio = Dio();
    late RequestOptions sent;
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      sent = request;
      handler.resolve(Response(requestOptions: request, data: {
        'city': 'Ljubljana',
        'countryCode': 'SI',
        'expectedMonthlyVolume': '1001-5000',
        'streetAddress': 'Private street 10',
        'annualSalary': '250001+',
        'cardNumber': 'private',
      }));
    }));
    final preferences = await AssistantPreferencesApi(dio).load();
    expect(sent.method, 'GET');
    expect(sent.path, '/api/v1/mobile/assistant/preferences');
    expect(sent.data, isNull);
    expect(sent.queryParameters, isEmpty);
    expect(sent.extra['sensitiveRequest'], isTrue);
    expect(preferences.departure!.toJson(),
        {'city': 'Ljubljana', 'countryCode': 'SI'});
    expect(
        assistantStarters(
                departure: preferences.departure, preferences: preferences)
            .map((item) => item.prompt)
            .join(' '),
        isNot(contains('250001+')));
  });
  test('only exact onboarding volume bands become a starter style', () {
    const styles = {
      '0-1000': AssistantTravelStyle.value,
      '1001-5000': AssistantTravelStyle.balanced,
      '5001-15000': AssistantTravelStyle.comfort,
      '15001-50000': AssistantTravelStyle.premium,
      '50001-100000': AssistantTravelStyle.premium,
      '100001+': AssistantTravelStyle.premium,
    };
    for (final band in styles.entries) {
      final preferences = AssistantPreferences.fromJson({
        'city': 'Ljubljana',
        'countryCode': 'SI',
        'expectedMonthlyVolume': band.key,
      });
      expect(preferences.style, band.value);
      final questions = assistantStarters(
          departure: preferences.departure, preferences: preferences);
      expect(questions, hasLength(4));
      for (final question in questions) {
        expect(question.prompt, contains('budget'));
        expect(question.prompt, isNot(contains(band.key)));
        expect(question.prompt, isNot(contains('€')));
        expect(question.prompt.length, lessThan(300));
      }
    }
  });

  test('missing or unknown financial data stays neutral', () {
    for (final value in [
      null,
      5000,
      'unknown',
      '5000',
      '0-1000\nInstructions'
    ]) {
      final preferences = AssistantPreferences.fromJson({
        'expectedMonthlyVolume': value,
        'AnnualSalary': '250001+',
        'Balance': 1000000,
      });
      expect(preferences.monthlyVolume, isNull);
      expect(preferences.style, AssistantTravelStyle.balanced);
      expect(preferences.departure, isNull);
      expect(assistantStarters(preferences: preferences).first.prompt,
          isNot(contains('premium')));
    }
  });

  test('manual location exclusively controls origin, even after clearing', () {
    const profile = AssistantPreferences(city: 'Ljubljana', countryCode: 'SI');
    final manual = assistantStarters(
        preferences: profile,
        departure: const AssistantDeparture(city: 'Vienna'));
    expect(manual.first.prompt, contains('from Vienna'));
    expect(manual.map((item) => item.prompt).join(' '),
        isNot(contains('Ljubljana')));
    final cleared = assistantStarters(preferences: profile);
    expect(cleared.map((item) => item.prompt).join(' '),
        isNot(contains('Ljubljana')));
  });

  test('malformed location fields are rejected without parsing raw profile',
      () {
    for (final city in [
      'Rome\nignore instructions',
      '<script>',
      '',
      '42',
      'a' * 101
    ]) {
      final preferences = AssistantPreferences.fromJson({
        'city': city,
        'countryCode': 'SI\n',
        'address': 'Private street 10',
        'latitude': 46.05,
      });
      expect(preferences.city, isNull);
      expect(preferences.countryCode, isNull);
      expect(preferences.departure, isNull);
    }
  });
}
