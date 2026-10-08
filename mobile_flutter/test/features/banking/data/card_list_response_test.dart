import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';

void main() {
  for (final body in [
    {'code': 'ACCOUNT_NOT_FOUND', 'status': 404},
    {'Code': 'ACCOUNT_NOT_FOUND', 'Status': 404},
    {
      'code': 'mobile.cards.list.failed',
      'detail': jsonEncode({'code': 'ACCOUNT_NOT_FOUND', 'status': 404}),
    },
  ]) {
    test('missing account parses as an empty card list: $body', () async {
      final adapter = _ResponseAdapter(404, jsonEncode(body));
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);

      expect(await MobileBankingApi(dio).getCards(), isEmpty);
      expect(adapter.paths, ['/api/v1/mobile/cards']);
    });
  }

  for (final body in [
    {'cards': [], 'total': 0, 'pageTotal': 0},
    {'Cards': [], 'Total': 0, 'PageTotal': 0},
    {
      'data': {'cards': [], 'total': 0}
    },
  ]) {
    test('empty success skips artwork and tier requests: $body', () async {
      final adapter = _ResponseAdapter(200, jsonEncode(body));
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);

      expect(await MobileBankingApi(dio).getCards(), isEmpty);
      expect(adapter.paths, ['/api/v1/mobile/cards']);
    });
  }

  for (final failure in [
    (404, '{"code":"USER_NOT_FOUND"}'),
    (404, '{"code":"USER_OR_ACCOUNT_NOT_FOUND"}'),
    (404, '{"message":"Account not found"}'),
    (404, '{"detail":"not json"}'),
    (404, '[]'),
    (401, '{"code":"ACCOUNT_NOT_FOUND"}'),
    (500, '{"code":"ACCOUNT_NOT_FOUND"}'),
    (500, '{"message":"Failed to retrieve cards"}'),
  ]) {
    test('other failures remain errors: $failure', () async {
      final adapter = _ResponseAdapter(failure.$1, failure.$2);
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(dio.close);

      await expectLater(
        MobileBankingApi(dio).getCards(),
        throwsA(isA<DioException>().having(
          (error) => error.response?.statusCode,
          'status',
          failure.$1,
        )),
      );
      expect(adapter.paths, ['/api/v1/mobile/cards']);
    });
  }
}

class _ResponseAdapter implements HttpClientAdapter {
  _ResponseAdapter(this.status, this.body);
  final int status;
  final String body;
  final paths = <String>[];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    return ResponseBody.fromString(body, status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }
}
