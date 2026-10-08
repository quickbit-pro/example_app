import 'package:file_picker/file_picker.dart';
import 'package:mobile_flutter/core/models/upload_document.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/platform_models.dart';
import 'package:mobile_flutter/features/platform/application/platform_providers.dart';
import 'package:mobile_flutter/features/platform/data/mobile_platform_api.dart';
import 'package:mobile_flutter/features/platform/presentation/wallets_screen.dart';
import 'package:mobile_flutter/features/rewards/domain/rewards_models.dart';
import 'package:mobile_flutter/features/wallets/domain/receiving_account_details.dart';

void main() {
  for (final extension in ['pdf', 'jpg', 'jpeg', 'png']) {
    test('browser $extension proof of address sends bytes, filename and MIME',
        () async {
      final dio = Dio();
      final bytes = Uint8List.fromList(utf8.encode('document-content'));
      final document = UploadDocument.fromPlatformFile(PlatformFile(
        name: 'address.$extension',
        size: bytes.length,
        bytes: bytes,
      ));
      var calls = 0;
      dio.httpClientAdapter = _RecordingAdapter((options, body) {
        calls++;
        expect(body, contains('name="ProofOfAddress"'));
        expect(body, contains('filename="address.$extension"'));
        expect(body, contains(UploadDocument.mimeTypes[extension]!));
        expect(body, contains('document-content'));
        expect(body, contains('name="MainPurpose"'));
        return ResponseBody.fromString('{"message":"submitted"}', 200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
      });
      await MobilePlatformApi(dio).startEqualsMoneyOnboarding(
        requestedFeatures: ['PAYMENTS'],
        mainPurpose: ['PURCHASE_OF_GOODS_OR_SERVICES'],
        sourceOfFunds: ['RECEIVING_FUNDS_FROM_OWN_ACCOUNTS'],
        destinationOfFunds: ['GB'],
        currenciesRequired: ['GBP'],
        annualVolume: '10001-50000',
        numberOfPayments: '5-10',
        proofOfAddress: document,
      );
      expect(calls, 1);
    });
  }

  test('browser additional documents retain bytes on repeated uploads',
      () async {
    final dio = Dio();
    final document = UploadDocument.fromPlatformFile(PlatformFile(
      name: 'address.pdf',
      size: 3,
      bytes: Uint8List.fromList([65, 66, 67]),
    ));
    var calls = 0;
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      calls++;
      expect(body, contains('name="Files"'));
      expect(body, contains('filename="address.pdf"'));
      expect(body, contains('ABC'));
      return ResponseBody.fromString('{"message":"uploaded"}', 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });
    final api = MobilePlatformApi(dio);
    for (var i = 0; i < 2; i++) {
      await api.uploadEqualsMoneyDocument(
          type: 'PROOF_OF_ADDRESS', documents: [document]);
    }
    expect(calls, 2);
  });

  test('unreadable, unsupported and oversize documents explain rejection', () {
    for (final file in [
      PlatformFile(name: 'address.pdf', size: 10),
      PlatformFile(name: 'address.exe', size: 1, bytes: Uint8List(1)),
      PlatformFile(
          name: 'address.pdf',
          size: UploadDocument.maxBytes + 1,
          bytes: Uint8List(UploadDocument.maxBytes + 1)),
    ]) {
      expect(
          () => UploadDocument.fromPlatformFile(file), throwsFormatException);
    }
  });

  test('identity approval cannot come from issuer or stale positive text', () {
    for (final json in <Map<String, dynamic>>[
      {},
      {
        'Interlace': {'Status': 'approved'}
      },
      {'HoppaCardKycApproved': false, 'hoppaStatus': 'approved'},
      {'hoppaStatus': 'pending'},
      {'hoppaStatus': 'rejected'},
    ]) {
      expect(KycDetailedStatus.fromJson(json).isHoppaApproved, isFalse);
    }
    expect(
        KycDetailedStatus.fromJson({'HoppaCardKycApproved': true})
            .isHoppaApproved,
        isTrue);
  });

  for (final pascalCase in [false, true]) {
    test(
        'receiving accounts preserve budget and currency identity '
        'in ${pascalCase ? 'PascalCase' : 'camelCase'} responses', () async {
      String key(String value) =>
          pascalCase ? '${value[0].toUpperCase()}${value.substring(1)}' : value;
      Map<String, dynamic> bank(String currency, String iban, String bankId) =>
          {
            key('currency'): currency,
            key('iban'): iban,
            key('bankAccountId'): bankId,
            key('swift'): 'EQALGB2L',
            key('bankName'): 'Equals Money',
          };
      final dio = Dio();
      dio.httpClientAdapter = _RecordingAdapter((options, body) {
        expect(options.method, 'GET');
        expect(options.path, '/api/v1/mobile/banking/receiving-accounts');
        expect(options.queryParameters, isEmpty);
        return ResponseBody.fromString(
          jsonEncode({
            key('accounts'): [
              {
                key('accountId'): 'budget-a',
                key('parentAccountId'): 'shared-owner',
                key('accountType'): 'BUDGET',
                key('accountHolderName'): 'First account holder',
                key('currency'): 'EUR',
                key('linkedBankAccounts'): [
                  bank('EUR', 'GB82WEST12345698765432', 'bank-a-eur'),
                  bank('GBP', 'GB29NWBK60161331926819', 'bank-a-gbp'),
                ],
              },
              {
                key('accountId'): 'budget-b',
                key('parentAccountId'): 'shared-owner',
                key('accountType'): 'BUDGET',
                key('accountHolderName'): 'Second account holder',
                key('linkedBankAccounts'): [
                  bank('EUR', 'DE89370400440532013000', 'bank-b-eur'),
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

      final resources = await MobilePlatformApi(dio).getEqualsBankingInfos();
      expect(
          resources.map((row) => row.id), ['budget-a', 'budget-a', 'budget-b']);
      expect(resources.map((row) => row.metadata['currency']),
          ['EUR', 'GBP', 'EUR']);
      expect(resources.map((row) => row.metadata['budgetId']),
          ['budget-a', 'budget-a', 'budget-b']);
      expect(resources.map((row) => row.metadata[key('parentAccountId')]),
          everyElement('shared-owner'));
      expect(resources.map((row) => row.metadata['userName']), [
        'First account holder',
        'First account holder',
        'Second account holder'
      ]);
      for (final row in resources) {
        expect(row.metadata['linkedBankAccounts'], hasLength(1));
        expect(row.metadata.containsKey('accountNumber'), isFalse);
        final linked =
            (row.metadata['linkedBankAccounts'] as List).single as Map;
        expect(linked.containsKey('accountNumber'), isFalse);
        expect(linked[key('bankAccountId')], isNotEmpty);
      }

      final receiving = receivingAccountsFromResources(resources);
      PlatformResource budget(String id) => PlatformResource.fromJson({
            'id': id,
            'accountId': 'shared-owner',
          });
      final firstEuro = receivingAccountForBudget(budget('budget-a'), receiving,
          currency: 'EUR');
      final firstPound = receivingAccountForBudget(
          budget('budget-a'), receiving,
          currency: 'GBP');
      final secondEuro = receivingAccountForBudget(
          budget('budget-b'), receiving,
          currency: 'EUR');
      expect(firstEuro?.accountNumber, 'GB82WEST12345698765432');
      expect(firstEuro?.holder, 'First account holder');
      expect(firstEuro?.swift, 'EQALGB2L');
      expect(firstEuro?.bankName, 'Equals Money');
      expect(firstPound?.accountNumber, 'GB29NWBK60161331926819');
      expect(secondEuro?.accountNumber, 'DE89370400440532013000');
      expect(secondEuro?.holder, 'Second account holder');
      expect(
          receivingAccountForBudget(budget('budget-b'), receiving,
              currency: 'GBP'),
          isNull);
      expect(
          receivingAccountForBudget(budget('unrelated-budget'), receiving,
              currency: 'EUR'),
          isNull);
    });
  }

  test('funding forms keep the currency-specific equals banking endpoint',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/banking/equals-banking-info');
      expect(options.queryParameters, {'currency': 'EUR'});
      return ResponseBody.fromString(
        jsonEncode({
          'currency': 'EUR',
          'accountNumber': 'GB82WEST12345698765432',
          'paymentMethod': 'sepa',
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });
    final result =
        await MobilePlatformApi(dio).getEqualsBankingInfo(currency: ' eur ');
    expect(result.metadata['accountNumber'], 'GB82WEST12345698765432');
    expect(result.metadata['paymentMethod'], 'sepa');
  });

  test(
      'receiving accounts do not turn an internal bank ID into an account number',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      return ResponseBody.fromString(
        jsonEncode({
          'Accounts': [
            {
              'AccountId': 'budget-without-details',
              'AccountType': 'BUDGET',
              'LinkedBankAccounts': [
                {'Currency': 'EUR', 'BankAccountId': 'internal-bank-id'},
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
    final result = await MobilePlatformApi(dio).getEqualsBankingInfos();
    expect(receivingAccountsFromResources(result), isEmpty);
  });

  test('empty receiving account envelopes produce no resources', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) =>
        ResponseBody.fromString('{"Accounts":[]}', 200, headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        }));
    expect(await MobilePlatformApi(dio).getEqualsBankingInfos(), isEmpty);
  });

  test(
      'receiving account failures propagate without a funding-details fallback',
      () async {
    final dio = Dio();
    var calls = 0;
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      calls++;
      expect(options.path, '/api/v1/mobile/banking/receiving-accounts');
      return ResponseBody.fromString('{"message":"Unavailable"}', 503,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          });
    });
    await expectLater(MobilePlatformApi(dio).getEqualsBankingInfos(),
        throwsA(isA<DioException>()));
    expect(calls, 1);
  });

  test('requests referral analytics with the programme and the period',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'GET');
      expect(options.path, '/api/v1/mobile/rewards/referrals/analytics');
      expect(options.queryParameters, {
        'programId': 'prog-1',
        'range': 'month',
        'from': '2026-09-01T00:00:00.000Z',
        'to': '2026-09-15T00:00:00.000Z',
      });
      return ResponseBody.fromString(
        jsonEncode({
          'Range': 'month',
          'Currency': 'EUR',
          'Totals': {'Attributed': 4, 'Qualified': 2, 'ConversionRate': 0.5},
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    });
    final analytics = await MobilePlatformApi(dio).getReferralMemberAnalytics(
      programId: 'prog-1',
      range: ReferralAnalyticsRange.month,
      from: DateTime.utc(2026, 9, 1),
      to: DateTime.utc(2026, 9, 15),
    );
    expect(analytics.range, ReferralAnalyticsRange.month);
    expect(analytics.currency, 'EUR');
    expect(analytics.totals.qualified, 2);
    expect(analytics.totals.conversionRate, 0.5);
  });

  test('loads the normalized estimated total assets response', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'GET');
      expect(options.path, '/api/v1/mobile/portfolio/summary');
      expect(options.queryParameters, {'currency': 'USD'});
      return ResponseBody.fromString(
        jsonEncode({
          'userId': 10466,
          'currency': 'USD',
          'estimatedTotalAssets': 1122.4421029138275,
          'calculatedAt': '2026-09-01T11:05:06.4146157+00:00',
          'providerTotals': [
            {
              'provider': 'interlace',
              'estimatedTotalAssets': 2.294867665,
              'currency': 'USD',
              'assetCount': 5,
              'isAvailable': true,
              'unpricedAssetCodes': ['BTC', 'ETH'],
            },
            {
              'provider': 'equalsmoney',
              'estimatedTotalAssets': 512.1292856096623,
              'currency': 'USD',
              'assetCount': 7,
              'isAvailable': true,
              'unpricedAssetCodes': <String>[],
            },
          ],
          'unpricedAssetCodes': ['BTC', 'ETH'],
          'isComplete': true,
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final estimate = await MobilePlatformApi(dio).getPortfolioEstimate(
      currency: 'usd',
    );

    expect(estimate.total, closeTo(1122.4421029138275, 0.0000001));
    expect(estimate.baseCurrency, 'USD');
    expect(estimate.valuedAt, isNotNull);
    expect(estimate.isPartial, isFalse);
    expect(estimate.missingCurrencies, ['BTC', 'ETH']);
    expect(estimate.providerTotals, hasLength(2));
    expect(estimate.providerTotals.first.provider, 'interlace');
    expect(estimate.providerTotals.first.total, closeTo(2.294867665, 1e-9));
  });

  test('accepts the legacy PascalCase portfolio proxy response', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      return ResponseBody.fromString(
        jsonEncode({
          'Currency': 'USD',
          'Total': 1122.4421029138275,
          'ValuedAt': '2026-09-01T11:05:06.4146157+00:00',
          'IsPartial': false,
          'IsStale': false,
          'MissingCurrencies': ['BTC', 'ETH'],
          'ProviderTotals': [
            {
              'Provider': 'boomfi',
              'Total': 608.0179496391652,
              'Currency': 'USD',
              'AssetCount': 3,
              'IsAvailable': true,
              'UnpricedAssetCodes': <String>[],
            },
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final estimate = await MobilePlatformApi(dio).getPortfolioEstimate();

    expect(estimate.total, closeTo(1122.4421029138275, 0.0000001));
    expect(estimate.providerTotals.single.provider, 'boomfi');
    expect(
        estimate.providerTotals.single.total, closeTo(608.0179496391652, 1e-9));
  });

  test('parses USDT and USDC Quantum top-up exchange quotes', () {
    final estimate = QuantumTopUpEstimate.fromJson({
      'success': true,
      'usdAmount': 100,
      'topupfee': 1.25,
      'usdToUsdt': {
        'baseCurrency': 'USD',
        'quoteCurrency': 'USDT',
        'baseAmount': '100',
        'rfqAmount': '99.50',
        'rfqCurrency': 'USDT',
        'fee': '0.50',
        'feeCurrency': 'USDT',
        'rate': '0.995',
      },
      'usdToUsdc': {
        'baseCurrency': 'USD',
        'quoteCurrency': 'USDC',
        'baseAmount': '100',
        'rfqAmount': '99.60',
        'rfqCurrency': 'USDC',
        'fee': '0.40',
        'feeCurrency': 'USDC',
        'rate': '0.996',
      },
    });

    expect(estimate.usdt?.rate, .995);
    expect(estimate.usdt?.rfqAmount, 99.5);
    expect(estimate.usdt?.fee, .5);
    expect(estimate.usdc?.rate, .996);
    expect(estimate.usdc?.rfqAmount, 99.6);
    expect(estimate.usdc?.fee, .4);
  });

  test('signup sends account and referral attribution fields', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'POST');
      expect(options.path, '/api/v1/mobile/auth/signup');
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(payload['accountType'], 'business');
      expect(payload['referralCode'], 'INVITE42');
      expect(payload['referralSource'], 'EMAIL_INVITATION');
      expect(payload['invitationToken'], 'opaque.+/_-token==');
      return ResponseBody.fromString(
        jsonEncode({'message': 'Account created'}),
        201,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    final result = await api.signUp(
      email: 'owner@example.test',
      password: 'StrongPassword1',
      firstName: 'Owner',
      lastName: 'Example',
      accountType: 'business',
      referralCode: 'INVITE42',
      referralSource: 'EMAIL_INVITATION',
      invitationToken: 'opaque.+/_-token==',
    );

    expect(result.message, 'Account created');
  });

  test('loads referral rewards and friends with paging, bare or enveloped',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'GET');
      expect(options.queryParameters['programId'], 'p1');
      expect(options.queryParameters['page'], 2);
      expect(options.queryParameters['pageSize'], 25);
      if (options.path == '/api/v1/mobile/rewards/referrals/rewards') {
        return ResponseBody.fromString(
          jsonEncode([
            {'amount': 1.5, 'currency': 'USD', 'stage': 'READY'},
          ]),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      expect(options.path, '/api/v1/mobile/rewards/referrals/friends');
      return ResponseBody.fromString(
        jsonEncode({
          'items': [
            {'alias': 'user-A1B2C', 'stage': 'QUALIFIED', 'earnedAmount': 4},
          ],
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    final rewards =
        await api.getReferralRewards(programId: 'p1', page: 2, pageSize: 25);
    final friends =
        await api.getReferralFriends(programId: 'p1', page: 2, pageSize: 25);

    expect(rewards.single.amount, 1.5);
    expect(rewards.single.stage, ReferralRewardStage.ready);
    expect(friends.single.alias, 'user-A1B2C');
    expect(friends.single.earnedAmount, 4);
  });

  test('accepts referral terms at the given version', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'POST');
      expect(
        options.path,
        '/api/v1/mobile/rewards/referrals/terms-acceptance',
      );
      expect(jsonDecode(body), {'termsVersion': 3});
      return ResponseBody.fromString(
        jsonEncode({'accepted': true, 'version': 3}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final result = await MobilePlatformApi(dio).acceptReferralTerms(3);

    expect(result.message, 'Terms accepted');
  });

  test('checks a referral code and treats an absent check as unknown',
      () async {
    final dio = Dio();
    var status = 200;
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'GET');
      expect(options.path, '/api/v1/mobile/auth/check-referral');
      expect(options.queryParameters['referralCode'], 'ABC1234');
      expect(options.extra['skipAuthRefresh'], isTrue);
      return ResponseBody.fromString(
        jsonEncode({
          'valid': true,
          'inviterDisplayName': 'John',
          'welcomeAmount': 3,
          'welcomeCurrency': 'USD',
          'termsVersion': 2,
        }),
        status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    final welcome = await api.checkReferralCode(' ABC1234 ');
    expect(welcome?.inviterDisplayName, 'John');
    expect(welcome?.welcomeAmount, 3);
    expect(welcome?.termsVersion, 2);

    status = 404;
    expect(await api.checkReferralCode('ABC1234'), isNull);
    expect(await api.checkReferralCode('   '), isNull);
  });

  test('an inactive campaign link is a clear answer from check-referral',
      () async {
    final dio = Dio();
    var body = jsonEncode({
      'type': 'https://api.neobanking.local/problems/auth.referral.campaign_link_inactive',
      'title': 'This invitation link is no longer active.',
      'status': 400,
      'detail': 'CAMPAIGN_LINK_INACTIVE',
      'code': 'auth.referral.campaign_link_inactive',
    });
    var status = 400;
    dio.httpClientAdapter = _RecordingAdapter((options, _) {
      return ResponseBody.fromString(body, status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    });

    final api = MobilePlatformApi(dio);
    final inactive = await api.checkReferralCode('AUTUMN26');
    expect(inactive?.campaignLinkInactive, isTrue);
    expect(inactive?.valid, isFalse);

    // An older facade passes the platform body through as the detail.
    body = jsonEncode({
      'code': 'auth.referral.validation_failed',
      'detail': '{"code":"CAMPAIGN_LINK_INACTIVE","message":"Link paused"}',
    });
    expect((await api.checkReferralCode('AUTUMN26'))?.campaignLinkInactive,
        isTrue);

    // Any other 400 is still an unknown code.
    body = jsonEncode({'code': 'auth.referral.validation_failed'});
    expect(await api.checkReferralCode('AUTUMN26'), isNull);
    status = 404;
    expect(await api.checkReferralCode('AUTUMN26'), isNull);
  });

  test('campaign link routes: list, create, patch and performance', () async {
    final dio = Dio();
    final requests = <({String method, String path, Map<String, dynamic> query, String body})>[];
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      requests.add((
        method: options.method,
        path: options.path,
        query: options.queryParameters,
        body: body,
      ));
      final payload = options.method == 'GET' &&
              !options.path.endsWith('/performance')
          ? [
              {
                'id': 'link-1',
                'name': 'Autumn newsletter',
                'code': 'AUTUMN26',
                'channel': 'email',
                'status': 'ACTIVE',
                'signupCount': 3,
              }
            ]
          : options.path.endsWith('/performance')
              ? {'signups': 3, 'qualified': 1, 'rewardsAccrued': 2.5, 'currency': 'USD'}
              : {
                  'id': 'link-1',
                  'name': 'Autumn newsletter',
                  'code': 'AUTUMN26',
                  'channel': 'email',
                  'status': options.method == 'PATCH' ? 'PAUSED' : 'ACTIVE',
                };
      return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });
    });

    final api = MobilePlatformApi(dio);
    final links = await api.getReferralCampaignLinks(
      programId: 'prog-1',
      status: ReferralCampaignLinkStatus.active,
    );
    expect(links.single.code, 'AUTUMN26');
    expect(links.single.signupCount, 3);

    final created = await api.createReferralCampaignLink(
      const ReferralCampaignLinkDraft(
        name: 'Autumn newsletter',
        channel: ReferralCampaignChannel.email,
        code: 'autumn26',
        locale: 'de',
      ),
    );
    expect(created.id, 'link-1');

    final paused = await api.updateReferralCampaignLink(
      'link-1',
      status: ReferralCampaignLinkStatus.paused,
    );
    expect(paused.status, ReferralCampaignLinkStatus.paused);

    final figures = await api.getReferralCampaignLinkPerformance(
      'link-1',
      range: ReferralAnalyticsRange.ninetyDays,
    );
    expect(figures.signups, 3);
    expect(figures.rewardsAccrued, 2.5);

    expect(requests.map((r) => '${r.method} ${r.path}'), [
      'GET /api/v1/mobile/rewards/referrals/links',
      'POST /api/v1/mobile/rewards/referrals/links',
      'PATCH /api/v1/mobile/rewards/referrals/links/link-1',
      'GET /api/v1/mobile/rewards/referrals/links/link-1/performance',
    ]);
    expect(requests[0].query, {'programId': 'prog-1', 'status': 'ACTIVE'});
    final createBody = jsonDecode(requests[1].body) as Map<String, dynamic>;
    expect(createBody['name'], 'Autumn newsletter');
    expect(createBody['channel'], 'email');
    expect(createBody['code'], 'AUTUMN26');
    expect(createBody['locale'], 'de');
    expect(createBody.containsKey('expiresAt'), isFalse);
    expect(jsonDecode(requests[2].body), {'status': 'PAUSED'});
    expect(requests[3].query, {'range': '90d'});
  });

  test('sends a referral invitation through the mobile API', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'POST');
      expect(
        options.path,
        '/api/v1/mobile/rewards/referrals/invitations',
      );
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(payload, {
        'recipientEmail': 'friend@example.test',
        'recipientName': 'Friend',
      });
      return ResponseBody.fromString(
        jsonEncode({'message': 'Invitation sent'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final result = await MobilePlatformApi(dio).sendReferralInvitation(
      email: ' friend@example.test ',
      name: ' Friend ',
    );

    expect(result.message, 'Invitation sent');
  });

  group('PlatformResource', () {
    test('parses common Hoppa-style fields into display rows', () {
      final resource = PlatformResource.fromJson({
        'Id': 'tier_1',
        'Name': 'Premium',
        'description': 'Higher card limits',
      });

      expect(resource.id, 'tier_1');
      expect(resource.title, 'Premium');
      expect(resource.subtitle, 'Higher card limits');
    });

    test('parses Hoppa crypto address fields into display rows', () {
      final resource = PlatformResource.fromJson({
        'Address': '0xabc',
        'Currency': 'USDT',
        'Network': 'Ethereum',
      });

      expect(resource.id, 'USDT');
      expect(resource.title, 'USDT');
      expect(resource.subtitle, '0xabc');
    });

    test('extracts nested wallet addresses from Hoppa wallet rows', () {
      final wallet = PlatformResource.fromJson({
        'id': 'wallet_1',
        'accountId': 'account_1',
        'nickname': 'Treasury',
        'addresses': [
          {
            'currency': 'USDT',
            'chain': 'Tron',
            'address': 'TXabc123',
            'selected': true,
          },
        ],
      });

      final addresses = depositAddressesFromWallets([wallet]);

      expect(addresses, hasLength(1));
      expect(addresses.single.title, 'USDT');
      expect(addresses.single.subtitle, 'TXabc123');
      expect(addresses.single.metadata['walletId'], 'wallet_1');
      expect(addresses.single.metadata['chain'], 'Tron');
    });

    test('extracts common deposit address aliases from wallet rows', () {
      final wallet = PlatformResource.fromJson({
        'WalletId': 'wallet_2',
        'DepositAddresses': [
          {
            'AssetCode': 'ETH',
            'Protocol': 'Ethereum',
            'BlockchainAddress': '0xabc',
          },
        ],
      });

      final addresses = depositAddressesFromWallets([wallet]);

      expect(addresses, hasLength(1));
      expect(addresses.single.title, 'ETH');
      expect(addresses.single.subtitle, '0xabc');
      expect(addresses.single.metadata['walletId'], 'wallet_2');
      expect(addresses.single.metadata['Protocol'], 'Ethereum');
    });

    test('drops malformed nested wallet address rows', () {
      final wallet = PlatformResource.fromJson({
        'id': 'wallet_3',
        'addresses': [
          {
            'currency': 'USDT',
            'chain': 'Tron',
          },
          {
            'chain': 'Ethereum',
            'address': '0xabc',
          },
          {
            'currency': 'BTC',
            'address': 'bc1abc',
          },
        ],
      });

      final addresses = depositAddressesFromWallets([wallet]);

      expect(addresses, isEmpty);
    });

    test('does not treat nested metadata values as wallet addresses', () {
      final wallet = PlatformResource.fromJson({
        'id': 'wallet_4',
        'currency': 'USDT',
        'addresses': [
          {
            'chain': 'Tron',
            'selected': 'TXnotAnAddress',
          },
        ],
      });

      final addresses = depositAddressesFromWallets([wallet]);

      expect(addresses, isEmpty);
    });

    test('merges endpoint and wallet-derived addresses without duplicates', () {
      final endpoint = PlatformResource.fromJson({
        'currency': 'USDT',
        'network': 'Tron',
        'address': 'TXabc123',
      });
      final wallet = PlatformResource.fromJson({
        'id': 'wallet_1',
        'addresses': [
          {
            'currency': 'USDT',
            'chain': 'Tron',
            'address': 'TXabc123',
          },
          {
            'currency': 'ETH',
            'chain': 'Ethereum',
            'address': '0xabc',
          },
        ],
      });

      final merged = mergeDepositAddressResources(
        [endpoint],
        depositAddressesFromWallets([wallet]),
      );

      expect(merged, hasLength(2));
      expect(merged.map((resource) => resource.subtitle), [
        'TXabc123',
        '0xabc',
      ]);
    });

    test('merge drops malformed address resources', () {
      final malformed = PlatformResource.fromJson({
        'id': 'address_1',
        'subtitle': 'not-an-address-fallback',
      });

      final merged = mergeDepositAddressResources([malformed], const []);

      expect(merged, isEmpty);
    });

    testWidgets('deposit address list does not expose withdraw action',
        (tester) async {
      final address = PlatformResource.fromJson({
        'currency': 'USDT',
        'network': 'Tron',
        'address': 'TXabc123',
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            assetsProvider.overrideWith((ref) async => const []),
            depositAddressesProvider.overrideWith((ref) async => [address]),
            bankingBalancesProvider.overrideWith((ref) async => const []),
          ],
          child: const MaterialApp(
            home: WalletsScreen(initialView: WalletView.addresses),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('TXabc123'), findsOneWidget);
      expect(find.text('Withdraw'), findsNothing);
      expect(find.text('Destination'), findsNothing);
    });
  });

  test('uses generic display values for empty backend payloads', () {
    final resource = PlatformResource.fromJson(const {});

    expect(resource.id, 'item');
    expect(resource.title, 'Item');
    expect(resource.subtitle, isEmpty);
  });

  test('parses Hoppa detailed KYC approval booleans', () {
    final status = KycDetailedStatus.fromJson({
      'HoppaCardKycApproved': true,
      'BankKycApproved': false,
      'CardIssuerKycApproved': true,
      'Interlace': {'Status': 'APPROVED', 'Approved': true},
      'EqualsMoney': {
        'Status': 'PENDING',
        'RequiredAction': 'WAIT_FOR_REVIEW',
      },
    });

    expect(status.hoppaStatus, 'approved');
    expect(status.bankStatus, 'PENDING');
    expect(status.cardIssuerStatus, 'approved');
    expect(status.nextAction, 'WAIT_FOR_REVIEW');
  });

  test('does not complete bank setup from identity approval only', () {
    final status = KycDetailedStatus.fromJson({
      'HoppaCardKycApproved': true,
      'BankKycApproved': true,
      'CardIssuerKycApproved': false,
    });

    expect(status.isHoppaApproved, isTrue);
    expect(status.isBankApproved, isFalse);
    expect(status.canUseEqualsMoneyBanking, isFalse);
    expect(status.completedSetupStepCount, 1);
  });

  test('keeps EqualsMoney not started banking incomplete', () {
    final status = KycDetailedStatus.fromJson({
      'hoppaCardKycApproved': true,
      'bankKycApproved': true,
      'cardIssuerKycApproved': true,
      'interlace': {
        'provider': 'Interlace',
        'status': 'approved',
        'approved': true,
        'externalId': '69fc9449c571827ed5cf9b98',
      },
      'equalsMoney': {
        'applicationId': null,
        'applicationStatus': null,
        'accountId': null,
        'requiredAction': null,
        'actionUrl': null,
        'additionalDocumentsRequested': [],
        'provider': 'EqualsMoney',
        'status': 'not_started',
        'approved': false,
        'externalId': null,
      },
    });

    expect(status.isHoppaApproved, isTrue);
    expect(status.isBankApproved, isFalse);
    expect(status.canUseEqualsMoneyBanking, isFalse);
    expect(status.hasEqualsMoneyReviewState, isFalse);
    expect(status.bankStatus, 'not_started');
    expect(status.completedSetupStepCount, 2);
  });

  test('treats active EqualsMoney account as completed bank setup', () {
    final status = KycDetailedStatus.fromJson({
      'hoppaCardKycApproved': true,
      'bankKycApproved': true,
      'cardIssuerKycApproved': true,
      'equalsMoney': {
        'applicationStatus': 'active',
        'accountId': 'F59168',
        'requiredAction': null,
        'status': 'active',
        'approved': false,
        'externalId': 'F59168',
      },
    });

    expect(status.completedSetupStepCount, 3);
    expect(status.isEqualsMoneyOnboarded, isTrue);
    expect(status.equalsMoneyAccountId, 'F59168');
    expect(status.nextAction, 'KYC approved');
  });

  test('blocks EqualsMoney banking while provider input is requested', () {
    final status = KycDetailedStatus.fromJson({
      'hoppaCardKycApproved': true,
      'bankKycApproved': true,
      'cardIssuerKycApproved': true,
      'equalsMoney': {
        'applicationStatus': 'active',
        'accountId': 'F59168',
        'status': 'active',
        'approved': true,
        'actionUrl': 'https://example.test/equals-check',
        'additionalDocumentsRequested': [
          {
            'type': 'PROOF_OF_FUNDS',
            'text': 'Proof of funds',
            'expectedResponseType': 'text',
            'informationRequestId': 'request_123',
            'applicationId': 'app_123',
            'associatedPersonId': 'person_123',
            'associatedPersonName': 'Jane Owner',
            'associatedPersonEmail': 'jane@example.test',
          },
        ],
      },
    });

    expect(status.requiresEqualsMoneyAction, isTrue);
    expect(status.isEqualsMoneyOnboarded, isFalse);
    expect(status.canUseEqualsMoneyBanking, isFalse);
    expect(status.equalsMoneyAdditionalDocumentsRequested.single.applicationId,
        'app_123');
    final request = status.equalsMoneyAdditionalDocumentsRequested.single;
    expect(request.expectsFiles, isFalse);
    expect(request.informationRequestId, 'request_123');
    expect(request.associatedPersonName, 'Jane Owner');
    expect(request.associatedPersonEmail, 'jane@example.test');
  });

  test('uploads EqualsMoney documents with associated person id', () async {
    final uploadedFields = <String, String>{};
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final data = options.data;
          if (data is FormData) {
            for (final field in data.fields) {
              uploadedFields[field.key] = field.value;
            }
          }

          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              data: const {'message': 'uploaded'},
              statusCode: 200,
            ),
          );
        },
      ),
    );
    final file = await File(
      '${Directory.systemTemp.path}/equalsmoney-document-test.txt',
    ).writeAsString('document');
    addTearDown(() {
      if (file.existsSync()) {
        file.deleteSync();
      }
    });

    await MobilePlatformApi(dio).uploadEqualsMoneyDocument(
      type: 'PASSPORT',
      paths: [file.path],
      applicationId: 'app_123',
      associatedPersonId: 'person_123',
    );

    expect(uploadedFields['Type'], 'PASSPORT');
    expect(uploadedFields['ApplicationId'], 'app_123');
    expect(uploadedFields['AssociatedPersonId'], 'person_123');
  });

  test('submits EqualsMoney text information with associated person id',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'POST');
      expect(options.path, '/api/v1/mobile/kyc/equalsmoney/information');
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(payload['type'], 'SOURCE_OF_FUNDS');
      expect(payload['response'], 'Consulting income');
      expect(payload['associatedPersonId'], 'person_123');
      return ResponseBody.fromString(
        jsonEncode({'message': 'submitted'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    await MobilePlatformApi(dio).submitEqualsMoneyInformation(
      type: 'SOURCE_OF_FUNDS',
      response: 'Consulting income',
      associatedPersonId: 'person_123',
    );
  });

  test('creates and confirms an EqualsMoney balance conversion', () async {
    var requestCount = 0;
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      requestCount++;
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(options.queryParameters['accountId'], 'account_123');
      if (requestCount == 1) {
        expect(options.path, '/api/v1/mobile/banking/orders/quote');
        expect(
          ((payload['sourceCurrency'] as Map)['currency'] as Map)['budgetId'],
          'budget_123',
        );
        expect(
          ((payload['sourceCurrency'] as Map)['currency']
              as Map)['currencyCode'],
          'GBP',
        );
        expect(
          ((payload['targetCurrency'] as Map)['currency']
              as Map)['currencyCode'],
          'EUR',
        );
        return ResponseBody.fromString(
          jsonEncode({
            'orderId': 'order_123',
            'quoteRequestId': 'quote_123',
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      expect(options.path, '/api/v1/mobile/banking/orders/trade');
      expect(payload['orderId'], 'order_123');
      expect(payload['quoteRequestId'], 'quote_123');
      return ResponseBody.fromString(
        jsonEncode({'orderId': 'trade_123'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    await api.createEqualsMoneyConversionQuote(
      accountId: 'account_123',
      budgetId: 'budget_123',
      sourceCurrency: 'GBP',
      targetCurrency: 'EUR',
      amount: 25,
    );
    await api.executeEqualsMoneyConversion(
      accountId: 'account_123',
      orderId: 'order_123',
      quoteRequestId: 'quote_123',
    );
    expect(requestCount, 2);
  });

  test('loads Interlace withdrawal balance and fee review', () async {
    var requestCount = 0;
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      requestCount++;
      expect(options.method, 'GET');
      if (requestCount == 1) {
        expect(
          options.path,
          '/api/v1/mobile/transfers/withdrawals/available-balance',
        );
        return ResponseBody.fromString(
          jsonEncode({
            'TotalAvailableUSDT': 12.5,
            'TotalAvailableUSDC': 20,
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      expect(
        options.path,
        '/api/v1/mobile/transfers/withdrawals/fee-and-quota',
      );
      expect(options.queryParameters, {
        'chain': 'TRX',
        'address': 'TXdestination',
        'currency': 'USDT',
        'amount': '5.25',
      });
      return ResponseBody.fromString(
        jsonEncode({
          'Code': '000000',
          'Data': {
            'CrossChainQuota': '1000',
            'Fees': [
              {'Amount': '0.50', 'Currency': 'USDT', 'Type': 'GAS'},
            ],
          },
        }),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    final balance = await api.getCryptoWithdrawalAvailableBalance();
    final quote = await api.getCryptoWithdrawalFeeAndQuota(
      chain: 'TRX',
      address: 'TXdestination',
      currency: 'USDT',
      amount: '5.25',
    );

    expect(balance.availableFor('USDT'), 12.5);
    expect(quote.fees.single.amount, 0.5);
    expect(quote.fees.single.type, 'GAS');
  });

  test('loads secure card widget from the public card widget route', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.method, 'GET');
      expect(options.uri.path, '/api/v1/mobile/cards/42/widget');
      expect(options.uri.queryParameters, isEmpty);
      return _jsonResponse({
        'success': true,
        'widgetUrl': 'https://secure.example.test/card-widget',
      });
    });

    final widget = await MobilePlatformApi(dio).getCardWidget('42');

    expect(
      widget.metadata['widgetUrl'],
      'https://secure.example.test/card-widget',
    );
  });

  test('uses OTP API sequence for Interlace crypto withdrawal', () async {
    var requestCount = 0;
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      requestCount++;
      expect(options.method, 'POST');
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (requestCount == 1) {
        expect(
          options.path,
          '/api/v1/mobile/transfers/withdrawals/crypto',
        );
        expect(payload['Currency'], 'USDC');
        expect(payload['Chain'], 'ETH');
        expect(payload['Amount'], '7.5');
        expect(payload['DestinationAddress'], '0xdestination');
        expect(payload['ConfirmExchangeRate'], isTrue);
        return ResponseBody.fromString(
          jsonEncode({
            'Success': true,
            'OtpRequired': true,
            'VerificationToken': 'verify_123',
            'Message': 'Code sent',
          }),
          202,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }
      if (requestCount == 2) {
        expect(
          options.path,
          '/api/v1/mobile/transfers/withdrawals/crypto/confirm',
        );
        expect(payload['VerificationToken'], 'verify_123');
        expect(payload['OtpCode'], '12345678');
        return ResponseBody.fromString(
          jsonEncode({
            'Success': true,
            'Status': 'PROCESSING',
            'TransactionId': 'txn_123',
          }),
          202,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      }

      expect(
        options.path,
        '/api/v1/mobile/transfers/withdrawals/crypto/resend',
      );
      expect(payload['VerificationToken'], 'verify_123');
      return ResponseBody.fromString(
        jsonEncode({'Success': true, 'Message': 'Code resent'}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final api = MobilePlatformApi(dio);
    final started = await api.createCryptoWithdrawal(
      currency: 'USDC',
      chain: 'ETH',
      amount: '7.5',
      destinationAddress: '0xdestination',
    );
    final confirmed = await api.confirmCryptoWithdrawal(
      verificationToken: started.verificationToken,
      otpCode: '12345678',
    );
    final resent = await api.resendCryptoWithdrawalOtp(
      verificationToken: started.verificationToken,
    );

    expect(started.otpRequired, isTrue);
    expect(started.verificationToken, 'verify_123');
    expect(confirmed.transactionId, 'txn_123');
    expect(resent.success, isTrue);
  });
  group('campaign link clicks (addendum A)', () {
    test('posts the visitor id and locale to the anonymous click route',
        () async {
      final dio = Dio();
      RequestOptions? seen;
      String body = '';
      dio.httpClientAdapter = _RecordingAdapter((options, requestBody) {
        seen = options;
        body = requestBody;
        return ResponseBody.fromString('', 204);
      });
      await MobilePlatformApi(dio).recordCampaignLinkClick(
        ' AUTUMN26 ',
        visitorId: '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10',
        locale: 'de',
      );
      expect(seen!.method, 'POST');
      expect(seen!.path, '/api/v1/mobile/rewards/referrals/links/AUTUMN26/clicks');
      expect(seen!.extra['skipAuthRefresh'], isTrue);
      final json = jsonDecode(body) as Map<String, dynamic>;
      expect(json['visitorId'], '5b2f7c3e-1c7a-4c1e-9f3d-2a6e8b4d9c10');
      expect(json['locale'], 'de');
    });

    test('never throws: an older backend, a dead link or no network', () async {
      for (final status in [404, 400, 500]) {
        final dio = Dio();
        dio.httpClientAdapter = _RecordingAdapter(
            (options, body) => ResponseBody.fromString('{"error":1}', status));
        await expectLater(
          MobilePlatformApi(dio).recordCampaignLinkClick('AUTUMN26',
              visitorId: 'v1'),
          completes,
        );
      }
      final offline = Dio();
      offline.httpClientAdapter = _RecordingAdapter(
          (options, body) => throw const SocketException('offline'));
      await expectLater(
        MobilePlatformApi(offline)
            .recordCampaignLinkClick('AUTUMN26', visitorId: 'v1'),
        completes,
      );
      // A blank code is not a request at all.
      var calls = 0;
      final blank = Dio();
      blank.httpClientAdapter = _RecordingAdapter((options, body) {
        calls++;
        return ResponseBody.fromString('', 204);
      });
      await MobilePlatformApi(blank).recordCampaignLinkClick(' ', visitorId: 'v1');
      expect(calls, 0);
    });
  });
}

ResponseBody _jsonResponse(Object payload, {int statusCode = 200}) {
  return ResponseBody.fromString(
    jsonEncode(payload),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );

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
