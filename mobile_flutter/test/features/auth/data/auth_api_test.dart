import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/features/auth/data/auth_api.dart';

void main() {
  const token = 'abcdefghijklmnopqrstuvwxyz0123456789ABCDEFG';
  const qrPayload =
      'hoppa://account-transfer?v=1&challenge=7f574db8-5cef-4ebb-9cc4-f89a43de0f80&token=$token';

  test('scans a Hoppa account-transfer QR and keeps token client-side',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/auth/account-link/scan');
      final request = jsonDecode(body) as Map<String, dynamic>;
      expect(request['qrPayload'], qrPayload);
      expect(request['deviceName'], 'iOS test device');
      return _jsonResponse({
        'challengeId': '7f574db8-5cef-4ebb-9cc4-f89a43de0f80',
        'status': 'AWAITING_APPROVAL',
        'expiresAt': '2026-08-27T12:05:00Z',
      });
    });

    final session = await AuthApi(dio).scanAccountLink(
      qrPayload: qrPayload,
      deviceName: 'iOS test device',
    );

    expect(session.token, token);
    expect(session.status, 'AWAITING_APPROVAL');
    expect(session.isTerminal, isFalse);
  });

  test('polling status preserves the opaque token', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/auth/account-link/status');
      expect((jsonDecode(body) as Map<String, dynamic>)['token'], token);
      return _jsonResponse({
        'challengeId': '7f574db8-5cef-4ebb-9cc4-f89a43de0f80',
        'status': 'APPROVED',
        'expiresAt': '2026-08-27T12:05:00Z',
      });
    });
    final initial = AccountLinkSession.fromJson(
      const {
        'challengeId': '7f574db8-5cef-4ebb-9cc4-f89a43de0f80',
        'status': 'AWAITING_APPROVAL',
        'expiresAt': '2026-08-27T12:05:00Z',
      },
      token: token,
    );

    final refreshed = await AuthApi(dio).getAccountLinkStatus(initial);

    expect(refreshed.token, token);
    expect(refreshed.status, 'APPROVED');
  });

  test('rejects unrelated QR codes before making a request', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      fail('No HTTP request should be made for an unrelated QR code.');
    });

    expect(
      () => AuthApi(dio).scanAccountLink(
        qrPayload: 'https://example.test/not-hoppa?token=$token',
        deviceName: 'test',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body) =>
    ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this._handler);

  final ResponseBody Function(RequestOptions options, String body) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = requestStream == null
        ? ''
        : await utf8.decodeStream(requestStream.cast<List<int>>());
    return _handler(options, body);
  }
}
