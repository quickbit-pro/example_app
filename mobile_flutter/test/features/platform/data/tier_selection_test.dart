import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/api/dio_provider.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/presentation/tiers_screen.dart';

void main() {
  test('PlatformResource parses Hoppa tier id/name aliases', () {
    final resource = PlatformResource.fromJson({
      'TierId': 7,
      'TierName': 'Premium',
      'Description': 'Higher limits',
    });

    expect(resource.id, '7');
    expect(resource.title, 'Premium');
    expect(resource.subtitle, 'Higher limits');
  });

  test('selectTier sends numeric TierId payload', () async {
    Map<String, dynamic>? requestBody;
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        expect(options.method, 'POST');
        expect(options.path, '/api/v1/mobile/tiers/current');
        requestBody = jsonDecode(body) as Map<String, dynamic>;

        return ResponseBody.fromString(
          '{"message":"Tier changed"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final result = await MobilePlatformApi(dio).selectTier(
      tierId: 7,
      tierCycle: 'yearly',
    );

    expect(result.message, 'Tier changed');
    expect(requestBody, {'tierId': 7, 'tierCycle': 'yearly'});
  });

  test('selectTier accepts Hoppa 200 response with matching tierId', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        return ResponseBody.fromString(
          jsonEncode({
            'success': false,
            'userId': 10534,
            'tierId': 243,
            'tierName': '',
            'tierLevel': '',
            'orderId': null,
            'totalCost': 0,
            'currency': 'USD',
            'status': '',
            'purchasedAt': '2026-05-02T14:03:41Z',
            'activatedAt': null,
            'expiresAt': null,
            'paymentDetails': {
              'amount': 0,
              'currency': 'USD',
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    final result = await MobilePlatformApi(dio).selectTier(tierId: 243);

    expect(
      result.message,
      'Tier selection received. Refreshing your tier status.',
    );
    expect(result.metadata['success'], isFalse);
    expect(result.metadata['tierId'], 243);
  });

  test('selectTier treats failure payload as error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        return ResponseBody.fromString(
          '{"success":false,"message":"Hoppa requires TierId"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    expect(
      () => MobilePlatformApi(dio).selectTier(tierId: 7),
      throwsA(isA<Exception>()),
    );
  });

  test('selectTier treats explicit payment failure as error', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        return ResponseBody.fromString(
          jsonEncode({
            'success': false,
            'tierId': 243,
            'paymentDetails': {
              'failureReason': 'Payment declined',
            },
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

    expect(
      () => MobilePlatformApi(dio).selectTier(tierId: 243),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('Payment declined'),
        ),
      ),
    );
  });

  test('tier action confirms ambiguous selection after refresh', () async {
    final calls = <String>[];
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        calls.add('${options.method} ${options.path}');
        if (options.method == 'POST') {
          return ResponseBody.fromString(
            jsonEncode({
              'success': false,
              'userId': 10534,
              'tierId': 243,
              'tierName': '',
              'tierLevel': '',
              'orderId': null,
              'totalCost': 0,
              'currency': 'USD',
              'status': '',
              'purchasedAt': '2026-05-02T14:03:41Z',
              'activatedAt': null,
              'expiresAt': null,
              'paymentDetails': {
                'amount': 0,
                'currency': 'USD',
              },
            }),
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        if (options.path == '/api/v1/mobile/tiers') {
          return ResponseBody.fromString(
            '{"tiers":[]}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        expect(options.path, '/api/v1/mobile/tiers/current');
        return ResponseBody.fromString(
          '{"TierId":243,"TierCycle":"monthly","Status":"active"}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);

    await container.read(platformActionControllerProvider.notifier).selectTier(
          tierId: 243,
        );

    final state = container.read(platformActionControllerProvider);
    expect(state.value?.message, 'Tier selection confirmed.');
    expect(state.value?.metadata['confirmedTierId'], 243);
    expect(calls, contains('POST /api/v1/mobile/tiers/current'));
    expect(calls, contains('GET /api/v1/mobile/tiers/current'));
  });

  test('current tier outage remains unknown instead of requiring setup',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter(
          (options, body) => ResponseBody.fromString('{}', 503));
    final container =
        ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);
    await expectLater(container.read(currentTierProvider.future),
        throwsA(isA<DioException>()));
    expect(container.read(currentTierProvider).hasError, isTrue);
  });

  test('selected tier survives a catalogue outage', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) =>
          ResponseBody.fromString(
              options.path.endsWith('/current') ? '{"TierId":7}' : '{}',
              options.path.endsWith('/current') ? 200 : 503,
              headers: {
                Headers.contentTypeHeader: [Headers.jsonContentType]
              }));
    final container =
        ProviderContainer(overrides: [dioProvider.overrideWithValue(dio)]);
    addTearDown(container.dispose);
    expect(tierIdOf(await container.read(currentTierProvider.future)), 7);
  });

  test('currentTierProvider hydrates current TierId from full tier list',
      () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = _RecordingAdapter((options, body) {
        if (options.path == '/api/v1/mobile/tiers/current') {
          return ResponseBody.fromString(
            '{"TierId":7,"TierCycle":"monthly","Status":"active"}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }

        expect(options.path, '/api/v1/mobile/tiers');
        return ResponseBody.fromString(
          jsonEncode({
            'tiers': [
              {
                'TierId': 7,
                'name': 'Premium',
                'features': ['priority support'],
                'cardBenefits': [
                  {'cardTypeId': 4, 'cardTypeName': 'Virtual Premium'},
                ],
              },
            ],
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });
    final container = ProviderContainer(
      overrides: [
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);

    final tier = await container.read(currentTierProvider.future);

    expect(tier?.id, '7');
    expect(tier?.title, 'Premium');
    expect(tier?.metadata['features'], ['priority support']);
    expect(tier?.metadata['cardBenefits'], isNotEmpty);
  });

  testWidgets('tiers screen displays price, benefits, limits and card fees',
      (tester) async {
    final tier = PlatformResource.fromJson({
      'TierId': 7,
      'name': 'Premium',
      'description': 'Higher limits',
      'tierLevel': 2,
      'monthlyFee': '9.99',
      'yearlyFee': '99.99',
      'currencyCode': 'EUR',
      'features': ['priority support'],
      'benefits': [
        {'name': 'airport lounge'},
      ],
      'limits': {
        'dailyLimit': '1000',
        'monthlyLimit': '10000',
      },
      'dailyRewardsEnabled': true,
      'dailyFreeDraws': 3,
      'cardBenefits': [
        {
          'cardTypeId': 4,
          'cardTypeName': 'Virtual Premium',
          'isVirtual': true,
          'freeCardsIncluded': 2,
          'maxCards': 5,
          'issuanceFee': '0',
          'replacementFee': '5',
          'monthlyFee': '1',
          'currencyCode': 'EUR',
          'cardFeatures': ['cashback'],
        },
      ],
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tiersProvider.overrideWith((ref) async => [tier]),
          currentTierProvider.overrideWith((ref) async => tier),
        ],
        child: const MaterialApp(home: TiersScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Premium'), findsWidgets);
    expect(
        find.text('Price monthly 9.99 EUR • yearly 99.99 EUR'), findsWidgets);
    expect(find.text('Feature Priority Support'), findsWidgets);
    expect(find.text('Benefit Airport Lounge'), findsWidgets);
    expect(find.text('Monthly limit 10000'), findsWidgets);
    expect(find.text('Daily rewards enabled'), findsWidgets);
    expect(
      find.textContaining('Card Virtual Premium'),
      findsWidgets,
    );
    expect(find.textContaining('Cashback', findRichText: true), findsWidgets);
    expect(find.text('7'), findsNothing);
  });
}

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
