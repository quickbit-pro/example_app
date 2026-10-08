import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/auth_token_provider.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/widgets/app_states.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, int) respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
          Future<void>? cancelFuture) =>
      respond(options, ++calls);
  @override
  void close({bool force = false}) {}
}

ResponseBody _ok() => ResponseBody.fromString('{}', 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  for (final type in [
    DioExceptionType.connectionError,
    DioExceptionType.connectionTimeout,
    DioExceptionType.receiveTimeout
  ]) {
    test('retries a temporary read failure once: $type', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      final adapter = _Adapter((request, call) async {
        if (call == 1) throw DioException(requestOptions: request, type: type);
        return _ok();
      });
      dio.httpClientAdapter = adapter;
      expect((await dio.get<Object?>('/profile')).statusCode, 200);
      expect(adapter.calls, 2);
    });
    test('network failures have an actionable message: $type', () {
      expect(
          friendlyErrorMessage(
              DioException(requestOptions: RequestOptions(), type: type)),
          'We could not reach the service. Check your connection and try again.');
    });
  }

  for (final method in ['GET', 'POST', 'PUT', 'PATCH', 'DELETE']) {
    test('persistent 503 is bounded and mutations are not replayed: $method',
        () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      final adapter =
          _Adapter((_, __) async => ResponseBody.fromString('', 503));
      dio.httpClientAdapter = adapter;
      await expectLater(
          dio.request<void>('/request', options: Options(method: method)),
          throwsA(isA<DioException>()));
      expect(adapter.calls, method == 'GET' ? 2 : 1);
    });
  }

  test('does not retry validation or rate-limit responses', () async {
    for (final status in [400, 403, 404, 422, 429]) {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final dio = container.read(dioProvider);
      final adapter =
          _Adapter((_, __) async => ResponseBody.fromString('', status));
      dio.httpClientAdapter = adapter;
      await expectLater(
          dio.get<void>('/profile'), throwsA(isA<DioException>()));
      expect(adapter.calls, 1);
    }
  });

  test('does not retry across a session boundary', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dio = container.read(dioProvider);
    final adapter = _Adapter((request, _) async {
      Future<void>.delayed(const Duration(milliseconds: 30), () {
        container.read(authSessionGenerationProvider.notifier).state++;
      });
      throw DioException(
          requestOptions: request, type: DioExceptionType.connectionError);
    });
    dio.httpClientAdapter = adapter;
    await expectLater(dio.get<void>('/profile'), throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });
}
