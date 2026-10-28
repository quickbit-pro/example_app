import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:mobile_flutter/features/signup/presentation/equals_document_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/auth/application/auth_providers.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/signup/presentation/equals_reagreement_gate.dart';

const documents = EqualsAgreementStatus(
    requiresAcceptance: true,
    available: true,
    version: 'v1',
    termsUrl: 'https://example.test/terms-v1.pdf',
    privacyUrl: 'https://equalsmoney.com/en-be/privacy');

class SignedInAuth extends AuthController {
  @override
  Future<AuthState> build() async => const AuthState(
      session: AuthSession(
          accessToken: 'test',
          refreshToken: 'test',
          userName: 'Customer',
          email: 'customer@example.test'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a status failure blocks the app and preserves retry and support',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(SignedInAuth.new),
          equalsAgreementStatusProvider
              .overrideWith((ref) => Future.error(Exception('Unavailable'))),
        ],
        child: const MaterialApp(
            home: EqualsReagreementGate(child: Text('Account contents')))));
    await tester.pumpAndSettle();
    expect(find.text('Account contents'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('server confirmation releases the app', (tester) async {
    await tester.pumpWidget(ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(SignedInAuth.new),
          equalsAgreementStatusProvider.overrideWith((ref) async =>
              const EqualsAgreementStatus(
                  requiresAcceptance: false,
                  available: true,
                  version: 'v1',
                  termsUrl: 'https://example.test/terms-v1.pdf',
                  privacyUrl: 'https://equalsmoney.com/en-be/privacy')),
        ],
        child: const MaterialApp(
            home: EqualsReagreementGate(child: Text('Account contents')))));
    await tester.pumpAndSettle();
    expect(find.text('Account contents'), findsOneWidget);
    expect(find.text('Review Equals Money agreements'), findsNothing);
  });

  testWidgets(
      'requires document access and two actions; failed save does not accept',
      (tester) async {
    final requests = <Map<String, dynamic>>[];
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      requests.add(Map<String, dynamic>.from(request.data as Map));
      handler.reject(DioException(
          requestOptions: request,
          response: Response(requestOptions: request, statusCode: 503),
          type: DioExceptionType.badResponse));
    }));
    await tester.pumpWidget(ProviderScope(
        overrides: [
          dioProvider.overrideWithValue(dio),
          equalsDocumentProvider.overrideWith((ref, kind) async =>
              EqualsDocument(
                  url: kind == 'terms'
                      ? documents.termsUrl
                      : documents.privacyUrl,
                  type: 'text/html',
                  bytes: Uint8List.fromList(utf8
                      .encode('<main><p>${'Legal text. ' * 20}</p></main>')))),
        ],
        child: const MaterialApp(
            home: Scaffold(
                body: SingleChildScrollView(
                    child: EqualsAgreementReview(status: documents))))));
    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);
    for (final title in [
      'I accept the Equals Money Terms and Conditions',
      'I confirm I have read and agree to the Equals Privacy Policy'
    ]) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('equals-document-confirm')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
    }
    expect(button().onPressed, isNotNull);
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(requests, [
      {
        'version': 'v1',
        'termsUrl': documents.termsUrl,
        'privacyUrl': documents.privacyUrl,
        'termsAccepted': true,
        'privacyAccepted': true,
        'termsAccessed': true
      }
    ]);
    expect(find.text('Acceptance could not be saved. Please try again.'),
        findsOneWidget);
    expect(button().onPressed, isNotNull);
  });

  testWidgets('missing documents never offer acceptance', (tester) async {
    await tester.pumpWidget(const ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: EqualsAgreementReview(
                    status: EqualsAgreementStatus(
                        requiresAcceptance: true,
                        available: false,
                        version: 'missing',
                        termsUrl: '',
                        privacyUrl: 'https://equalsmoney.com/privacy'))))));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });
}
