import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/l10n/app_localizations.dart';
import 'package:mobile_flutter/features/auth/presentation/login_error_message.dart';

void main() {
  const en = AppLocalizations(Locale('en'), {});
  DioException failure(int status,
      {String path = '/api/v1/mobile/auth/login',
      Object? data,
      Map<String, List<String>>? headers}) {
    final request = RequestOptions(path: path);
    return DioException(
        requestOptions: request,
        response: Response(
            requestOptions: request,
            statusCode: status,
            data: data,
            headers: Headers.fromMap(headers ?? {})));
  }

  test('rejected password is not described as an expired session', () {
    expect(
        loginErrorMessage(failure(401), en), 'Email or password is incorrect.');
    expect(
        loginErrorMessage(
            failure(401, path: '/api/v1/mobile/auth/refresh'), en),
        'Your session has expired. Sign in again to continue.');
  });
  test('lockout shows remaining minutes from the existing API contract', () {
    expect(
        loginErrorMessage(
            failure(429, data: {
              'code': 'auth.locked_out',
              'title':
                  'Too many failed sign-in attempts. Try again in 11 minutes.',
            }),
            en),
        'Too many failed sign-in attempts. Try again in 11 min.');
  });
  test('prefers Retry-After and distinguishes general throttling', () {
    expect(
        loginErrorMessage(
            failure(429, data: {
              'code': 'auth.locked_out'
            }, headers: {
              'retry-after': ['61']
            }),
            en),
        'Too many failed sign-in attempts. Try again in 2 min.');
    expect(
        loginErrorMessage(failure(429, data: {'code': 'auth.locked_out'}), en),
        'Too many failed sign-in attempts. Please wait before trying again.');
    expect(loginErrorMessage(failure(429), en),
        'Too many requests. Please wait a moment and try again.');
  });
  test('all supported locales translate password and lockout messages', () {
    for (final language in appLanguages) {
      final messages = (jsonDecode(
                  File('assets/l10n/${language.code}.json').readAsStringSync())
              as Map<String, dynamic>)
          .cast<String, String>();
      final l10n = AppLocalizations(language.locale, messages);
      final password = loginErrorMessage(failure(401), l10n);
      final locked = loginErrorMessage(
          failure(429, data: {
            'code': 'auth.locked_out',
            'title':
                'Too many failed sign-in attempts. Try again in 15 minutes.'
          }),
          l10n);
      expect(locked, contains('15'));
      expect(locked, isNot(contains('{p0}')));
      if (language.code != 'en') {
        expect(password, isNot('Email or password is incorrect.'));
        expect(locked,
            isNot('Too many failed sign-in attempts. Try again in 15 min.'));
      }
    }
  });
}
