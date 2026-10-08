import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/identity/user_nickname.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/peer/data/peer_transfers_api.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';

void main() {
  test('recipient lookup sends exactly one identifier and parses nickname',
      () async {
    final dio = Dio();
    final calls = <Map<String, dynamic>>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      calls.add(Map<String, dynamic>.from(options.data as Map));
      handler.resolve(Response(requestOptions: options, data: {
        'userId': 'ana',
        'firstName': 'Ana',
        'nickname': 'ana_123',
        'maskedEmail': 'a***@example.com',
      }));
    }));
    final api = PeerTransfersApi(dio);
    for (final query in [
      ' @AnA_123 ',
      'ANA_123',
      'ana@example.com',
      '+38640123456'
    ]) {
      final user = await api.lookupQuery(query);
      expect(user.nickname, 'ana_123');
      expect(user.copyWith(isContact: true).nickname, 'ana_123');
      expect(user.contactHint, '@ana_123 · a***@example.com');
    }
    expect(calls, [
      {'nickname': 'ana_123'},
      {'nickname': 'ana_123'},
      {'email': 'ana@example.com'},
      {'phoneNumber': '+38640123456'},
    ]);
  });

  test('invalid nicknames are rejected before lookup', () {
    final api = PeerTransfersApi(Dio());
    for (final value in [
      '@',
      '@@ana',
      'ab',
      '@123456',
      'ana name',
      'ana!',
      '@аna',
      '@${'a' * 31}'
    ]) {
      expect(() => api.lookupQuery(value), throwsFormatException,
          reason: value);
    }
    expect(isValidNickname('a' * 30), isTrue);
    expect(normalizeNickname(' @AnA '), 'ana');
  });

  test('nickname-only profile updates preserve identity fields', () async {
    final dio = Dio();
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      expect(options.path, '/api/v1/mobile/profile');
      expect(options.data, {'nickname': 'ana_123'});
      handler.resolve(Response(requestOptions: options, data: {
        'id': 'ana',
        'name': 'Ana',
        'email': 'ana@example.com',
        'nickname': 'ana_123',
      }));
    }));
    final profile =
        await MobilePlatformApi(dio).updateProfile(nickname: 'ana_123');
    expect(profile.nickname, 'ana_123');
    expect(profile.name, 'Ana');
    expect(UserProfile.fromJson({'Nickname': 'ana'}).nickname, 'ana');
    expect(UserProfile.fromJson({}).nickname, isNull);
  });
}
