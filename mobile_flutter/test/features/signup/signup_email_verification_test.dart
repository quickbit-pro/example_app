import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/auth/presentation/email_verification_sheet.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';

class _RecordingAdapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode({
        'message': options.path.endsWith('email-code')
            ? 'Code sent'
            : 'Account created'
      }),
      options.path.endsWith('email-code') ? 202 : 201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('signup email request sends no password and final signup carries code',
      () async {
    final adapter = _RecordingAdapter();
    final api = MobilePlatformApi(Dio()..httpClientAdapter = adapter);
    await api.requestSignupEmailCode(' member@example.test ');
    expect(
        adapter.requests.single.path, '/api/v1/mobile/auth/signup/email-code');
    expect(adapter.requests.single.data, {'email': 'member@example.test'});
    expect(adapter.requests.single.extra['sensitiveRequest'], isTrue);
    await api.signUp(
      email: 'member@example.test',
      password: 'ExamplePassword-39',
      firstName: 'New',
      lastName: 'Member',
      accountType: 'personal',
      emailVerificationCode: '123456',
      registrationAttemptId: 'same-attempt',
    );
    expect(adapter.requests.last.path, '/api/v1/mobile/auth/signup');
    expect(adapter.requests.last.data['emailVerificationCode'], '123456');
    expect(adapter.requests.last.data['registrationAttemptId'], 'same-attempt');
    expect(adapter.requests.last.extra['sensitiveRequest'], isTrue);
  });

  testWidgets('signup code sheet retries rejected codes and uses signup resend',
      (tester) async {
    final verifiedCodes = <String>[];
    var resends = 0;
    bool? completed;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: Builder(
      builder: (context) => TextButton(
        onPressed: () async {
          completed = await showEmailVerificationSheet(
            context,
            email: 'member@example.test',
            onResendCode: () async {
              resends++;
            },
            onVerifyCode: (code) async {
              verifiedCodes.add(code);
              if (code == '111111') {
                throw DioException(
                  requestOptions: RequestOptions(),
                  response: Response(
                      requestOptions: RequestOptions(),
                      statusCode: 400,
                      data: {'message': 'The code is invalid or expired.'}),
                  type: DioExceptionType.badResponse,
                );
              }
            },
          );
        },
        child: const Text('Begin signup'),
      ),
    )))));
    await tester.tap(find.text('Begin signup'));
    await tester.pumpAndSettle();
    expect(verifiedCodes, isEmpty);
    final field = find.byWidgetPredicate((widget) =>
        widget is EditableText &&
        widget.autofillHints?.contains(AutofillHints.oneTimeCode) == true);
    await tester.enterText(field, '111111');
    await tester.tap(find.text('Confirm email'));
    await tester.pumpAndSettle();
    expect(verifiedCodes, ['111111']);
    expect(completed, isNull);
    expect(find.text('Confirm your email'), findsOneWidget);
    await tester.tap(find.text('Send a new code'));
    await tester.pumpAndSettle();
    expect(resends, 1);
    await tester.enterText(field, '222222');
    await tester.tap(find.text('Confirm email'));
    await tester.pumpAndSettle();
    expect(verifiedCodes, ['111111', '222222']);
    expect(completed, isTrue);
    expect(find.text('Confirm your email'), findsNothing);
  });
}
