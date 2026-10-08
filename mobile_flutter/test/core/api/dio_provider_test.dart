import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';
import 'package:mobile_flutter/features/auth/data/session_credential_storage.dart';
import 'package:mobile_flutter/features/signup/data/referral_invitation_repository.dart';
import 'package:mobile_flutter/features/signup/domain/referral_invitation.dart';
import 'package:mobile_flutter/flavors.dart';

class _StoredCredentials extends SessionCredentialStorage {
  StoredSession saved = const StoredSession(
      accessToken: 'expired-access-token',
      refreshToken: 'refresh-token',
      email: 'demo@example.test',
      userName: 'Demo');
  @override
  Future<StoredSession?> read() async => saved;
  @override
  Future<void> save(StoredSession value) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    saved = value;
  }
}

void main() {
  for (final late in [false, true]) {
    test('parallel 401s rotate once, including late responses: $late',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      var refreshes = 0;
      final bothStarted = Completer<void>();
      var expired = 0;
      server.listen((request) async {
        if (request.uri.path.endsWith('/auth/refresh')) {
          refreshes++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          request.response.headers.contentType = ContentType.json;
          request.response.write(
              jsonEncode({'accessToken': 'fresh', 'refreshToken': 'rotated'}));
        } else if (request.headers.value('authorization') == 'Bearer old') {
          expired++;
          if (expired == 2) bothStarted.complete();
          await bothStarted.future;
          if (late && request.uri.path == '/second') {
            await Future<void>.delayed(const Duration(milliseconds: 80));
          }
          request.response.statusCode = 401;
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write('{}');
        }
        await request.response.close();
      });
      final container = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://127.0.0.1:${server.port}',
          branding: AppBranding.fromEnvironment(),
        ))
      ]);
      addTearDown(container.dispose);
      container.read(authTokenProvider.notifier).state = 'old';
      container.read(refreshTokenProvider.notifier).state = 'refresh';
      final dio = container.read(dioProvider);
      await Future.wait([dio.get<void>('/first'), dio.get<void>('/second')]);
      expect(refreshes, 1);
      expect(container.read(authTokenProvider), 'fresh');
      expect(container.read(refreshTokenProvider), 'rotated');
    });
  }

  for (final late in [false, true]) {
    test('multipart 401 retries the complete receipt payload: late=$late',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final expiredUploadReceived = Completer<void>();
      final releaseUnauthorized = Completer<void>();
      final bodies = <List<int>>[];
      final contentTypes = <String?>[];
      final authorizations = <String?>[];
      var refreshes = 0;
      server.listen((request) async {
        final body = await request.fold<List<int>>(
          <int>[],
          (bytes, chunk) => bytes..addAll(chunk),
        );
        if (request.uri.path.endsWith('/auth/refresh')) {
          refreshes++;
          expect(jsonDecode(utf8.decode(body)), {'refreshToken': 'refresh'});
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({'accessToken': 'fresh'}));
        } else {
          bodies.add(body);
          contentTypes.add(request.headers.value(HttpHeaders.contentTypeHeader));
          final authorization =
              request.headers.value(HttpHeaders.authorizationHeader);
          authorizations.add(authorization);
          if (authorization == 'Bearer old') {
            expiredUploadReceived.complete();
            await releaseUnauthorized.future;
            request.response.statusCode = HttpStatus.unauthorized;
          } else {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'id': 'receipt-1'}));
          }
        }
        await request.response.close();
      });

      final container = ProviderContainer(overrides: [
        appConfigProvider.overrideWithValue(AppConfig(
          flavor: AppFlavor.dev,
          apiBaseUrl: 'http://127.0.0.1:${server.port}',
          branding: AppBranding.fromEnvironment(),
        )),
      ]);
      addTearDown(container.dispose);
      container.read(authTokenProvider.notifier).state = 'old';
      container.read(refreshTokenProvider.notifier).state = 'refresh';
      final receiptBytes = <int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        0,
        16,
        ...utf8.encode('private invoice scan'),
        0xff,
        0xd9,
      ];
      final form = FormData.fromMap({
        'currency': 'EUR',
        'image': MultipartFile.fromBytes(
          receiptBytes,
          filename: 'invoice.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final upload = container.read(dioProvider).post<Map<String, dynamic>>(
            '/api/v1/mobile/split-bills/scan',
            data: form,
            options: Options(extra: {'sensitiveRequest': true}),
          );
      await expiredUploadReceived.future;
      // Model another request having finished its token refresh before this
      // upload's delayed 401 arrives.
      if (late) container.read(authTokenProvider.notifier).state = 'fresh';
      releaseUnauthorized.complete();

      expect((await upload).data, {'id': 'receipt-1'});
      expect(refreshes, late ? 0 : 1);
      expect(authorizations, ['Bearer old', 'Bearer fresh']);
      expect(bodies, hasLength(2));
      expect(bodies[1], orderedEquals(bodies[0]));
      expect(contentTypes[0], startsWith('multipart/form-data; boundary='));
      expect(contentTypes[1], contentTypes[0]);
      final wireBody = latin1.decode(bodies[1]);
      expect(wireBody, contains('name="currency"\r\n\r\nEUR\r\n'));
      expect(wireBody, contains('name="image"; filename="invoice.jpg"'));
      expect(wireBody, contains('content-type: image/jpeg'));
      expect(wireBody, contains(latin1.decode(receiptBytes)));
      expect(container.read(authTokenProvider), 'fresh');
    });
  }

  test('temporary refresh failure preserves saved session tokens', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.statusCode =
          request.uri.path.endsWith('/auth/refresh') ? 503 : 401;
      await request.response.close();
    });
    final container = ProviderContainer(overrides: [
      appConfigProvider.overrideWithValue(AppConfig(
        flavor: AppFlavor.dev,
        apiBaseUrl: 'http://127.0.0.1:${server.port}',
        branding: AppBranding.fromEnvironment(),
      ))
    ]);
    addTearDown(container.dispose);
    container.read(authTokenProvider.notifier).state = 'old';
    container.read(refreshTokenProvider.notifier).state = 'refresh';
    await expectLater(container.read(dioProvider).get<void>('/protected'),
        throwsA(isA<DioException>()));
    expect(container.read(authTokenProvider), 'old');
    expect(container.read(refreshTokenProvider), 'refresh');
  });

  test('auth session parses refresh token', () {
    final session = AuthSession.fromJson(const {
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'userName': 'Demo User',
      'email': 'demo@example.test',
    });

    expect(session.accessToken, 'access-token');
    expect(session.refreshToken, 'refresh-token');
    expect(session.userName, 'Demo User');
    expect(session.email, 'demo@example.test');
  });

  test('dio refreshes access token once after a 401 and retries request',
      () async {
    final stored = _StoredCredentials();
    var protectedCalls = 0;
    var refreshCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);

    server.listen((request) async {
      if (request.uri.path == '/api/v1/mobile/auth/refresh') {
        refreshCalls++;
        final body = await utf8.decoder.bind(request).join();
        expect(jsonDecode(body), {'refreshToken': 'refresh-token'});

        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'accessToken': 'fresh-access-token',
            'refreshToken': 'rotated-refresh-token',
            'userName': 'Demo User',
            'email': 'demo@example.test',
          }));
        await request.response.close();
        return;
      }

      if (request.uri.path == '/api/v1/mobile/me') {
        protectedCalls++;
        if (protectedCalls == 1) {
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer expired-access-token',
          );
          request.response.statusCode = HttpStatus.unauthorized;
          await request.response.close();
          return;
        }

        expect(
          request.headers.value(HttpHeaders.authorizationHeader),
          'Bearer fresh-access-token',
        );
        expect(stored.saved.refreshToken, 'rotated-refresh-token');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'id': 'user-1'}));
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    final container = ProviderContainer(
      overrides: [
        sessionStorageProvider.overrideWithValue(stored),
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://127.0.0.1:${server.port}',
            branding: AppBranding.fromEnvironment(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(authTokenProvider.notifier).state = 'expired-access-token';
    container.read(refreshTokenProvider.notifier).state = 'refresh-token';

    final response = await container
        .read(dioProvider)
        .get<Map<String, dynamic>>('/api/v1/mobile/me');

    expect(response.data, {'id': 'user-1'});
    expect(protectedCalls, 2);
    expect(refreshCalls, 1);
    expect(container.read(authTokenProvider), 'fresh-access-token');
    expect(container.read(refreshTokenProvider), 'rotated-refresh-token');
  });

  test('dio expires a session after an unrecoverable 401', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response.statusCode = HttpStatus.unauthorized;
      await request.response.close();
    });

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://127.0.0.1:${server.port}',
            branding: AppBranding.fromEnvironment(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    container.read(authTokenProvider.notifier).state = 'expired-access-token';

    await expectLater(
      container.read(dioProvider).get<void>('/api/v1/mobile/me'),
      throwsA(isA<DioException>()),
    );

    expect(container.read(authTokenProvider), isNull);
    expect(container.read(refreshTokenProvider), isNull);
  });

  test('a new login invalidates protected data cached before authentication',
      () async {
    var protectedCalls = 0;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      protectedCalls++;
      if (request.headers.value(HttpHeaders.authorizationHeader) !=
          'Bearer valid-access-token') {
        request.response.statusCode = HttpStatus.unauthorized;
        await request.response.close();
        return;
      }

      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'name': 'Rok'}));
      await request.response.close();
    });

    final protectedProvider = FutureProvider<String>((ref) async {
      final response = await ref
          .watch(dioProvider)
          .get<Map<String, dynamic>>('/api/v1/mobile/me');
      return response.data?['name']?.toString() ?? '';
    });
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://127.0.0.1:${server.port}',
            branding: AppBranding.fromEnvironment(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(protectedProvider.future),
      throwsA(isA<DioException>()),
    );

    container.read(authTokenProvider.notifier).state = 'valid-access-token';
    final generation = container.read(authSessionGenerationProvider.notifier);
    generation.state = generation.state + 1;

    expect(await container.read(protectedProvider.future), 'Rok');
    expect(protectedCalls, 2);
  });

  test('sensitive invitation token is omitted from network error logs',
      () async {
    const invitationToken = 'opaque-secret-token-123';
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    server.listen((request) async {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({
          'message': 'failed for $invitationToken',
        }));
      await request.response.close();
    });

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            flavor: AppFlavor.dev,
            apiBaseUrl: 'http://127.0.0.1:${server.port}',
            branding: AppBranding.fromEnvironment(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final output = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) output.add(message);
    };
    addTearDown(() => debugPrint = previousDebugPrint);

    await expectLater(
      DioReferralInvitationRepository(container.read(dioProvider))
          .preview(invitationToken),
      throwsA(
        isA<ReferralInvitationFailure>().having(
          (failure) => failure.type,
          'type',
          ReferralInvitationFailureType.network,
        ),
      ),
    );

    expect(output.join('\n'), isNot(contains(invitationToken)));
  });
}
