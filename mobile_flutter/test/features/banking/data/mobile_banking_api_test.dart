import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_flutter/core/models/banking_models.dart';
import 'package:mobile_flutter/features/banking/data/mobile_banking_api.dart';
import 'package:mobile_flutter/features/business/application/business_draft.dart';

void main() {
  test('saves a local business draft with full people and roles', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/business-onboarding/workflow/draft');
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(payload['taxId'], 'BUSINESS-TAX');
      expect(payload['industry'], {'main': 'INFORMATION_AND_COMMUNICATION'});
      expect(payload['registeredAddress']['country'], 'GB');
      expect(payload['contactEmail'], 'alex@example.test');
      final people = payload['associatedPeople'] as List;
      expect(people.map((person) => person['associationType']), [
        'APPLICANT',
        'DIRECTOR',
        'ULTIMATE_BENEFICIAL_OWNER',
      ]);
      expect(people.first['taxId'], 'PERSON-TAX');
      expect(people.first['address'], {
        'addressLine1': 'Main Street',
        'addressLine2': null,
        'buildingNumber': '1',
        'city': 'Kyiv',
        'region': 'Kyiv',
        'postcode': '01001',
        'country': 'UA',
      });
      expect(people.last['ownershipPercentage'], 0);
      return ResponseBody.fromString(
        '{"success":true,"status":"DRAFT","associatedPeople":[{"id":"1"},{"id":"2"},{"id":"3"}]}',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    });
    final person = {
      'firstName': 'Alex',
      'lastName': 'Smith',
      'emailAddress': 'alex@example.test',
      'taxId': 'PERSON-TAX',
      'nationalities': ['UA'],
      'addresses': [
        {
          'streetName': 'Main Street',
          'buildingNumber': '1',
          'city': 'Kyiv',
          'region': 'Kyiv',
          'postcode': '01001',
          'countryCode': 'UA',
        },
      ],
    };
    final draft = localBusinessDraft({
      'type': 'PRIVATE_COMPANY',
      'taxId': 'BUSINESS-TAX',
      'industry': {'main': 'INFORMATION_AND_COMMUNICATION'},
      'addresses': [
        {'addressType': 'REGISTERED', 'countryCode': 'GB'},
      ],
    }, [
      {...person, 'associationType': 'APPLICANT'},
      {...person, 'associationType': 'DIRECTOR'},
      {
        ...person,
        'associationType': 'ULTIMATE_BENEFICIAL_OWNER',
        'ownershipPercentage': 0,
      },
    ]);
    final response = await MobileBankingApi(dio).saveBusinessDraft(draft);
    expect(response['status'], 'DRAFT');
  });

  test('business uploads return the local evidence reference', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path,
          '/api/v1/mobile/business-onboarding/associated-people/7/documents');
      return ResponseBody.fromString(
        '{"success":true,"documentId":42}',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    });
    final response = await MobileBankingApi(dio).uploadBusinessOnboardingDocument(
      purpose: 'PROOF_OF_IDENTITY',
      bytes: Uint8List.fromList([1]),
      fileName: 'identity.pdf',
      associatedPersonId: '7',
    );
    expect(response['documentId'], 42);
  });

  test(
      'validates card discounts with the mobile endpoint and sends the code on order',
      () async {
    final dio = Dio();
    var calls = 0;
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      calls++;
      final payload = jsonDecode(body) as Map<String, dynamic>;
      if (calls == 1) {
        expect(options.path, '/api/v1/mobile/cards/discount-codes/validate');
        expect(payload, {'code': 'SAVE'});
        return ResponseBody.fromString(
            '{"isValid":true,"discountType":"fixed","buyDiscountFixed":3}', 200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType]
            });
      }
      expect(options.path, '/api/v1/mobile/cards');
      expect(payload['discountCode'], 'SAVE');
      return ResponseBody.fromString('', 204);
    });
    final api = MobileBankingApi(dio);
    final discount = await api.validateCardDiscount(' save ');
    expect(discount.isValid, isTrue);
    expect(discount.price(20, 'buy'), 3);
    await api.orderCard(label: 'Travel', virtual: true, discountCode: ' save ');
    expect(calls, 2);
  });

  test('omits a blank discount code from a card order', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(jsonDecode(body), isNot(contains('discountCode')));
      return ResponseBody.fromString('', 204);
    });
    await MobileBankingApi(dio)
        .orderCard(label: 'Travel', virtual: true, discountCode: ' ');
  });

  group('banking model parsing', () {
    test('parses money from minor units', () {
      final money = Money.fromJson({
        'currency': 'EUR',
        'minorUnits': 12345,
      });

      expect(money.formatted, '€123.45');
    });

    test('parses account balances', () {
      final account = AccountBalance.fromJson({
        'id': 'acc_1',
        'name': 'Main',
        'iban': 'SI56',
        'balance': {'currency': 'EUR', 'minorUnits': 1000},
        'available': {'currency': 'EUR', 'minorUnits': 800},
      });

      expect(account.id, 'acc_1');
      expect(account.balance.formatted, '€10.00');
      expect(account.available.formatted, '€8.00');
    });

    test('parses linked EqualsMoney bank details', () {
      final account = AccountBalance.fromJson({
        'accountId': 'F59168',
        'displayName': 'Account balance',
        'provider': 'EqualsMoney',
        'budgetId': 'budget-1',
        'parentAccountId': 'F59168',
        'accountType': 'BUDGET',
        'accountHolderName': 'Example Ltd',
        'supportedCurrencies': ['GBP', 'EUR', 'USD'],
        'linkedBankAccounts': [
          {
            'currency': 'EUR',
            'iban': 'SI56123456789012345',
            'accountNumber': '12345678',
            'swift': 'BANKSI22',
            'bankName': 'Equals Money',
          },
        ],
      });

      expect(account.id, 'F59168');
      expect(account.provider, 'EqualsMoney');
      expect(account.budgetId, 'budget-1');
      expect(account.parentAccountId, 'F59168');
      expect(account.accountType, 'BUDGET');
      expect(account.accountHolderName, 'Example Ltd');
      expect(account.supportedCurrencies, ['GBP', 'EUR', 'USD']);
      expect(account.iban, 'SI56123456789012345');
      expect(account.linkedBankAccounts.single.swift, 'BANKSI22');
    });

    test('parses multi-currency EqualsMoney budget balances', () {
      final account = AccountBalance.fromJson({
        'accountId': 'F59168',
        'displayName': 'rok test',
        'provider': 'EqualsMoney',
        'supportedCurrencies': ['EUR', 'GBP', 'USD'],
        'balances': [
          {'currency': 'GBP', 'amount': '200.00'},
          {'currency': 'USD', 'amount': '100.00'},
          {'currency': 'EUR', 'amount': '0.00'},
        ],
      });

      expect(account.currencyBalances.map((money) => money.formatted), [
        '£200.00',
        '\$100.00',
        '€0.00',
      ]);
    });

    test('parses currency-keyed account balances', () {
      final account = AccountBalance.fromJson({
        'accountId': 'F59168',
        'balances': {
          'GBP': {'available': '377.00'},
          'EUR': 3.25,
        },
      });

      expect(account.currencyBalances.map((money) => money.formatted), [
        '£377.00',
        '€3.25',
      ]);
    });

    test('labels Equals Money and crypto cards by provider', () {
      final equalsCard = PaymentCard.fromJson({
        'id': 'equals-card',
        'bankProvider': 'EqualsMoney',
      });
      final cryptoCard = PaymentCard.fromJson({
        'id': 'crypto-card',
        'bankProvider': 'Interlace',
      });

      expect(equalsCard.providerLabel, 'Fiat account');
      expect(cryptoCard.providerLabel, 'Crypto card');
    });

    test('empty dashboard snapshot exposes zero balance', () {
      final snapshot = DashboardSnapshot(
        profile: UserProfile.fromJson(const {}),
        accounts: const [],
        cards: const [],
        transactions: const [],
        onboarding: const [],
      );

      expect(snapshot.profile.email, isEmpty);
      expect(snapshot.accounts, isEmpty);
      expect(snapshot.cards, isEmpty);
      expect(snapshot.transactions, isEmpty);
      expect(snapshot.onboarding, isEmpty);
      expect(snapshot.totalBalance.minorUnits, 0);
    });

    test('card ordering requires issuer approval despite completed identity KYC', () {
      final snapshot = DashboardSnapshot(
        profile: UserProfile.fromJson(const {'kycStatus': 'approved'}),
        accounts: const [],
        cards: const [],
        transactions: const [],
        onboarding: const [],
      );

      expect(snapshot.canUseBanking, isFalse);
      expect(snapshot.canOrderCard, isFalse);
    });

    test('parses payout quote and otp responses', () {
      final quote = PayoutQuote.fromJson({
        'QuoteId': 'quote-123',
        'SourceAmount': 100,
        'SourceCurrency': 'EUR',
        'TargetAmount': 85.5,
        'TargetCurrency': 'GBP',
        'ExchangeRate': 0.855,
        'Fee': 1.25,
        'ExpiresAt': '2026-05-05T12:00:00Z',
      });
      final otp = PayoutOtpInitiation.fromJson({
        'Success': true,
        'VerificationToken': 'token-123',
        'Message': 'Sent',
      });

      expect(quote.id, 'quote-123');
      expect(quote.feeLabel, 'EUR 1.25');
      expect(quote.rateLabel, '1 EUR = 0.855000 GBP');
      expect(otp.success, isTrue);
      expect(otp.verificationToken, 'token-123');
    });
  });

  test('dashboard requests go out together instead of one after another',
      () async {
    final dio = Dio();
    final gate = _GatedAdapter();
    dio.httpClientAdapter = gate;

    final pending = MobileBankingApi(dio).getDashboard();
    await gate.arrived(4);

    expect(
      gate.paths,
      unorderedEquals([
        '/api/v1/mobile/me',
        '/api/v1/mobile/banking/accounts',
        '/api/v1/mobile/cards',
        '/api/v1/mobile/transactions',
      ]),
      reason: 'No dashboard request should wait for another response.',
    );

    gate.release({
      '/api/v1/mobile/me': {'name': 'Customer', 'kycStatus': 'approved'},
      '/api/v1/mobile/onboarding/status': {'tasks': []},
      '/api/v1/mobile/banking/accounts': {'accounts': []},
      '/api/v1/mobile/cards': {'cards': []},
      '/api/v1/mobile/transactions': {'transactions': []},
    });
    final snapshot = await pending;

    expect(snapshot.profile.name, 'Customer');
    expect(snapshot.onboarding, isEmpty);
    expect(gate.paths, contains('/api/v1/mobile/onboarding/status'),
        reason: 'A profile without the onboarding block still asks for it.');
  });

  test('dashboard reads onboarding from the profile instead of a request',
      () async {
    final dio = Dio();
    final gate = _GatedAdapter();
    dio.httpClientAdapter = gate;

    final pending = MobileBankingApi(dio).getDashboard();
    await gate.arrived(4);
    gate.release({
      '/api/v1/mobile/me': {
        'name': 'Customer',
        'kycStatus': 'not_started',
        'onboarding': {
          'status': 'not_started',
          'currentStep': 'start',
          'requiredActions': ['start_onboarding'],
        },
      },
      '/api/v1/mobile/banking/accounts': {'accounts': []},
      '/api/v1/mobile/cards': {'cards': []},
      '/api/v1/mobile/transactions': {'transactions': []},
    });
    final snapshot = await pending;

    expect(snapshot.onboarding.single.id, 'start_onboarding');
    expect(snapshot.onboarding.single.route, '/kyc');
    expect(gate.paths, isNot(contains('/api/v1/mobile/onboarding/status')));
  });

  test('loads balances for account rows that omit their amounts', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      final payload = switch (options.path) {
        '/api/v1/mobile/banking/accounts' => {
            'accounts': [
              {
                'accountId': 'equals-main',
                'displayName': 'Account balance',
                'provider': 'EqualsMoney',
              },
            ],
          },
        '/api/v1/mobile/banking/accounts/equals-main/balances' => {
            'balances': [
              {
                'accountId': 'equals-main',
                'currency': 'GBP',
                'available': '377.00'
              },
            ],
          },
        _ => throw StateError('Unexpected request: ${options.path}'),
      };
      return ResponseBody.fromString(
        jsonEncode(payload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final accounts = await MobileBankingApi(dio).getAccounts();

    expect(accounts.single.currencyBalances.single.formatted, '£377.00');
  });

  test('aggregate balances attach only to the exact budget and provider',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      final payload = options.path == '/api/v1/mobile/banking/accounts'
          ? {
              'accounts': [
                for (final id in ['first', 'second'])
                  {
                    'accountId': 'shared-parent',
                    'budgetId': id,
                    'provider': 'EqualsMoney',
                    'displayName': id,
                  },
              ]
            }
          : {
              'balances': [
                {
                  'accountId': 'first',
                  'provider': 2,
                  'currency': 'EUR',
                  'available': 0
                },
                {
                  'accountId': 'second',
                  'provider': 'EqualsMoney',
                  'currency': 'RON',
                  'available': 200
                },
                {
                  'accountId': 'shared-parent',
                  'provider': 'EqualsMoney',
                  'currency': 'GBP',
                  'available': 999
                },
                {
                  'accountId': 'first',
                  'provider': 'Interlace',
                  'currency': 'USD',
                  'available': 888
                },
                {'currency': 'CHF', 'available': 777},
              ]
            };
      if (options.path != '/api/v1/mobile/banking/accounts') {
        expect(
            options.path,
            anyOf(
              '/api/v1/mobile/banking/accounts/first/balances',
              '/api/v1/mobile/banking/accounts/second/balances',
            ));
      }
      return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });
    final accounts = await MobileBankingApi(dio).getAccounts();
    expect(accounts.first.currencyBalances.single.currency, 'EUR');
    expect(accounts.first.currencyBalances.single.minorUnits, 0);
    expect(accounts.last.currencyBalances.single.currency, 'RON');
    expect(accounts.last.currencyBalances.single.minorUnits, 20000);
  });

  test(
      'unscoped or mismatching balance responses do not create account balances',
      () async {
    for (final balances in <Object>[
      {
        'EUR': {'available': 50}
      },
      [
        {'currency': 'EUR', 'available': 50}
      ],
      [
        {
          'accountId': 'interlace-parent',
          'provider': 'Interlace',
          'currency': 'EUR',
          'available': 50
        }
      ],
    ]) {
      final dio = Dio();
      dio.httpClientAdapter =
          _RecordingAdapter((options, body) => ResponseBody.fromString(
                  jsonEncode(options.path == '/api/v1/mobile/banking/accounts'
                      ? {
                          'accounts': [
                            {
                              'accountId': 'business-account',
                              'provider': 'Interlace'
                            }
                          ]
                        }
                      : {'balances': balances}),
                  200,
                  headers: {
                    Headers.contentTypeHeader: [Headers.jsonContentType]
                  }));
      final accounts = await MobileBankingApi(dio).getAccounts();
      expect(accounts.single.currencyBalances, isEmpty);
    }
  });

  test('existing scoped zero balances are preserved without enrichment',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/banking/accounts');
      return ResponseBody.fromString(
          jsonEncode({
            'accounts': [
              {
                'accountId': 'existing',
                'currencyBalances': [
                  {'currency': 'EUR', 'available': 0}
                ],
              }
            ]
          }),
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
    });
    final accounts = await MobileBankingApi(dio).getAccounts();
    expect(accounts.single.currencyBalances.single.currency, 'EUR');
    expect(accounts.single.currencyBalances.single.minorUnits, 0);
  });

  test('adds back-only tier artwork to a card that already has a front',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      final payload = switch (options.path) {
        '/api/v1/mobile/cards' => {
            'cards': [
              {
                'id': 'issued-card',
                'cardTypeId': 29,
                'network': 'Visa',
                'CardImageUrl': 'https://cdn.example/front.png',
                'CardBackImageUrl': null
              }
            ],
            'tierInfo': {'tierId': 5},
          },
        '/api/v1/mobile/tiers/card-tier/5' => {
            'CardTypeTiers': [
              {
                'CardTypeSecondaryId': 29,
                'CardTypeId': 104,
                'CardType': {
                  'Id': 104,
                  'CardImageUrl': null,
                  'CardBackImageUrl': 'https://cdn.example/back.png'
                }
              }
            ],
          },
        _ => throw StateError('Unexpected request: ${options.path}'),
      };
      return ResponseBody.fromString(jsonEncode(payload), 200, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });
    });
    final card = (await MobileBankingApi(dio).getCards()).single;
    expect(card.artworkUrl, 'https://cdn.example/front.png');
    expect(card.backArtworkUrl, 'https://cdn.example/back.png');
  });

  test('enriches issued cards with artwork from tier associations', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      final payload = switch (options.path) {
        '/api/v1/mobile/cards' => {
            'cards': [
              {
                'id': 'issued-card',
                'cardTypeId': 29,
                'maskedCardNumber': '**** 3191',
                'cardImageUrl': null,
              },
            ],
            'tierInfo': {'tierId': 5},
          },
        '/api/v1/mobile/tiers/card-tier/5' => {
            'cardTypeTiers': [
              {
                'cardTypeId': 104,
                'cardTypeSecondaryId': 29,
                'cardType': {
                  'id': 104,
                  'name': 'Hoppa Virtual',
                  'cardImageUrl':
                      'https://hoppa.global/images/orange-purple-card.png',
                },
              },
            ],
          },
        _ => throw StateError('Unexpected request: ${options.path}'),
      };
      return ResponseBody.fromString(
        jsonEncode(payload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final cards = await MobileBankingApi(dio).getCards();

    expect(cards.single.cardTypeId, 29);
    expect(cards.single.cardTypeName, 'Hoppa Virtual');
    expect(
      cards.single.artworkUrl,
      'https://hoppa.global/images/orange-purple-card.png',
    );
  });

  test('loads the current tier when the card response has no tier id',
      () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      final payload = switch (options.path) {
        '/api/v1/mobile/cards' => {
            'cards': [
              {
                'id': 'issued-card',
                'cardTypeSecondaryId': 29,
                'maskedCardNumber': '**** 3191',
              },
            ],
          },
        '/api/v1/mobile/tiers/current' => {'tierId': 5},
        '/api/v1/mobile/tiers/card-tier/5' => {
            'cardTypeTiers': [
              {
                'cardTypeSecondaryId': 29,
                'cardType': {
                  'id': 104,
                  'name': 'Hoppa Black',
                  'cardImageUrl': '/uploads/cards/hoppa-black.png',
                  'cardNetwork': 'MasterCard',
                },
              },
            ],
          },
        _ => throw StateError('Unexpected request: ${options.path}'),
      };
      return ResponseBody.fromString(
        jsonEncode(payload),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final cards = await MobileBankingApi(dio).getCards();

    expect(
      cards.single.artworkUrl,
      'https://dashboard.hoppa.global/uploads/cards/hoppa-black.png',
    );
    expect(cards.single.network, 'MasterCard');
  });

  test('a business assessment requires a queued response', () async {
    final dio = Dio();
    var attempts = 0;
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(options.path, '/api/v1/mobile/business-onboarding/workflow/assess');
      expect(options.method, 'POST');
      attempts++;
      return ResponseBody.fromString(
        attempts == 1 ? '{}' : '{"status":"ASSESSMENT_PENDING"}',
        attempts == 1 ? 200 : 202,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    });
    final api = MobileBankingApi(dio);
    await expectLater(api.requestBusinessAssessment(), throwsStateError);
    await api.requestBusinessAssessment();
  });

  test('uploads browser-selected business documents from bytes', () async {
    final dio = Dio();
    dio.httpClientAdapter = _RecordingAdapter((options, body) {
      expect(
        options.path,
        '/api/v1/mobile/business-onboarding/documents',
      );
      expect(body, contains('PROOF_OF_FORMATION'));
      expect(body, contains('formation.pdf'));
      expect(body, contains('PDF'));
      expect(body, contains('application/pdf'));
      return ResponseBody.fromString(
        '{"success":true,"documentId":42}',
        200,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );
    });

    await MobileBankingApi(dio).uploadBusinessOnboardingDocument(
      purpose: 'PROOF_OF_FORMATION',
      bytes: Uint8List.fromList(utf8.encode('PDF')),
      fileName: 'formation.pdf',
    );
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

/// Holds every request until [release], so a test can prove which requests
/// were issued before any response existed. Requests arriving after the
/// release (follow-ups such as card artwork) are answered immediately.
class _GatedAdapter implements HttpClientAdapter {
  final paths = <String>[];
  final _waiting = <String, Completer<ResponseBody>>{};
  Map<String, Object>? _payloads;
  var _expected = 0;
  Completer<void>? _arrivals;

  Future<void> arrived(int count) {
    if (paths.length >= count) return Future.value();
    _expected = count;
    return (_arrivals = Completer<void>()).future;
  }

  void release(Map<String, Object> payloads) {
    _payloads = payloads;
    for (final entry in _waiting.entries) {
      entry.value.complete(_respond(entry.key));
    }
  }

  ResponseBody _respond(String path) {
    return ResponseBody.fromString(
      jsonEncode(_payloads![path] ?? const <String, Object>{}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    paths.add(options.path);
    if (_payloads != null) return Future.value(_respond(options.path));
    final completer = Completer<ResponseBody>();
    _waiting[options.path] = completer;
    if (paths.length >= _expected && _arrivals?.isCompleted == false) {
      _arrivals!.complete();
    }
    return completer.future;
  }
}
